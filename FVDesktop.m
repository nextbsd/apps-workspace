/*
 * This file is part of Workspace.
 * Copyright (C) 2026 FileViewer contributors
 *
 * Workspace is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3,
 * as published by the Free Software Foundation.
 *
 * Workspace is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Workspace. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import "FVDesktop.h"
#import "FVApplication.h"
#import "FVDesktopSettings.h"
#import "FVEject.h"
#import "FVInspector.h"
#import "FVModel.h"
#import "FVThumbnails.h"
#import "FVWindow.h"
#import <GNUstepGUI/GSTheme.h>
#include <sys/stat.h>

/* Above the background (NSDesktopWindowLevel), below every app's
   windows: macOS's desktop icon level. */
static const NSInteger FVDesktopLevel = NSDesktopWindowLevel + 20;

/* The icon grid: a cell holds a 48-point icon, the size of the Dock's
   and close to File Viewer's icon view, and two lines of name. */
static const CGFloat FVCellWidth = 100;
static const CGFloat FVCellHeight = 88;
static const CGFloat FVIconSize = 48;

/* How icons are ordered: Workspace's defaults. Where the user put an icon
   by moving it ({path = "column row";}) is a file of its own in the
   account's Preferences: Workspace's background process shares its
   defaults and would write an older copy of them back. Only the icons the
   user moved are in it; the rest flow from the top corner in order (the
   disks, then the files), moving up as others go. The file before this,
   org.nextbsd.Workspace.Desktop.plist, kept every icon and is no longer
   read. */
static NSString *const FVDesktopSortKey = @"DesktopIconSort";

static NSString *
FVDesktopPositionsPath (void)
{
  return [NSHomeDirectory ()
      stringByAppendingPathComponent:@"Library/Preferences/org.nextbsd.Workspace.DesktopPlaced.plist"];
}
/* Dragged icons that include a disk: only the desktop takes them, so a
   disk can be moved about but never dropped into a folder. */
static NSString *const FVDesktopIconsPboardType = @"org.nextbsd.Workspace.desktopIcons";

static NSInteger FVCompareDesktopItems (id a, id b, void *context);

/* Key, so Workspace's shortcuts work after a click on the desktop, but
   never main: in the in-window menu style GNUstep would put the menu
   along the top of the desktop. */
@interface FVDesktopWindow : NSWindow
@end

@implementation FVDesktopWindow

- (BOOL)canBecomeKeyWindow
{
  return YES;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}

@end

/* One icon: the startup disk, a connected disk, or an item in ~/Desktop. */
@interface FVDesktopEntry : NSObject
{
@public
  NSString *path;
  NSString *name;
  NSString *label;
  BOOL disk;
  BOOL startup;
  NSInteger column, row;
}
@end

@implementation FVDesktopEntry

- (void)dealloc
{
  RELEASE (path);
  RELEASE (name);
  RELEASE (label);
  DEALLOC;
}

@end

/*
 * The desktop's icons. Their actions are File Viewer's: a viewer of
 * ~/Desktop that is never shown (the agent) does them on the icons
 * chosen here, given as its selection, so copying, pasting, renaming,
 * Get Info, Open With and the rest behave as they do in a File Viewer
 * window.
 */
@interface FVDesktopView : NSView <NSTextFieldDelegate>
{
  NSMutableArray *entries;
  NSMutableSet *selected;
  NSMutableDictionary *icons;
  FVWindow *agent;
  NSString *desktopPath;
  NSTimer *monitor;
  NSArray *stamp;
  BOOL shown;			/* set up: the icons are there once -update ran */
  BOOL disks;			/* the startup disk and /Volumes too */
  BOOL banding;
  BOOL dragPending;
  NSRect band;
  NSPoint downPoint;
  NSString *downPath;
  NSTextField *editor;
  NSString *editingPath;
  NSString *pendingEdit;
  NSPoint pendingDrop;
  NSArray *pendingDropNames;
  NSString *typed;
  NSTimeInterval typedAt;
  NSInteger redraws;
  NSPoint menuPoint;
  NSMutableDictionary *positions;
}
- (void)update;
@end

@implementation FVDesktopView

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame:frame]) != nil)
    {
      entries = [[NSMutableArray alloc] init];
      selected = [[NSMutableSet alloc] init];
      icons = [[NSMutableDictionary alloc] init];
      desktopPath = [[NSHomeDirectory () stringByAppendingPathComponent:@"Desktop"] copy];
      [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [self registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType,
                                                              FVDesktopIconsPboardType, nil]];
      monitor = RETAIN ([NSTimer scheduledTimerWithTimeInterval:2
                                                         target:self
                                                       selector:@selector (check:)
                                                       userInfo:nil
                                                        repeats:YES]);
    }
  return self;
}

- (void)dealloc
{
  [monitor invalidate];
  RELEASE (monitor);
  RELEASE (entries);
  RELEASE (selected);
  RELEASE (icons);
  RELEASE (agent);
  RELEASE (desktopPath);
  RELEASE (stamp);
  RELEASE (downPath);
  RELEASE (editor);
  RELEASE (editingPath);
  RELEASE (pendingEdit);
  RELEASE (pendingDropNames);
  RELEASE (typed);
  RELEASE (positions);
  DEALLOC;
}

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)acceptsFirstResponder
{
  return shown;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

/* ---- What the desktop shows ---- */

- (FVWindow *)agent
{
  if (agent == nil)
    {
      [[NSFileManager defaultManager] createDirectoryAtPath:desktopPath
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:NULL];
      agent = [[FVWindow alloc] initWithPath:desktopPath];
      [[agent window] setExcludedFromWindowsMenu:YES];
    }
  return agent;
}

- (BOOL)light
{
  return [[FVDesktopSettings effectiveValueForKey:@"NBAppearance"] isEqual:@"light"];
}

/* The Windows style fills the desktop from the left, as Windows does;
   the others from the right, as a Mac does. */
- (BOOL)fromLeft
{
  return [[FVDesktopSettings effectiveValueForKey:@"NBWindowStyle"] isEqual:@"tiling"];
}

/* The part of the screen icons may use: clear of the menu bar and of the
   Dock's edge. WindowServer reports them as the screen's visible frame;
   where nothing does, the settings say where they are. */
- (NSRect)area
{
  NSRect area = [self bounds];
  CGFloat top = 14, bottom = 14, left = 14, right = 14;
  NSScreen *screen = [[self window] screen];
  NSRect frame = [screen frame], visible = [screen visibleFrame];
  if (screen && !NSEqualRects (frame, visible) && NSWidth (visible) > 0)
    {
      top += NSMaxY (frame) - NSMaxY (visible);
      bottom += NSMinY (visible) - NSMinY (frame);
      left += NSMinX (visible) - NSMinX (frame);
      right += NSMaxX (frame) - NSMaxX (visible);
    }
  else
    {
      if ([[FVDesktopSettings effectiveValueForKey:@"NBMenuStyle"] isEqual:@"macmenubar"])
        top += 24;
      NSString *dock = [FVDesktopSettings effectiveValueForKey:@"NBDockPosition"];
      if ([dock isEqual:@"right"])
        right += 68;
      else if ([dock isEqual:@"left"])
        left += 68;
      else if ([dock isEqual:@"top"])
        top += 72;
      else
        bottom += 72;
    }
  area.origin.x += left;
  area.origin.y += top;
  area.size.width -= left + right;
  area.size.height -= top + bottom;
  return area;
}

- (NSInteger)columns
{
  return MAX (1, (NSInteger)(NSWidth ([self area]) / FVCellWidth));
}

- (NSInteger)rows
{
  return MAX (1, (NSInteger)(NSHeight ([self area]) / FVCellHeight));
}

- (NSRect)cellRectForColumn:(NSInteger)column row:(NSInteger)row
{
  NSRect area = [self area];
  CGFloat x = [self fromLeft] ? NSMinX (area) + column * FVCellWidth
                              : NSMaxX (area) - (column + 1) * FVCellWidth;
  return NSMakeRect (x, NSMinY (area) + row * FVCellHeight, FVCellWidth, FVCellHeight);
}

- (void)cellAtPoint:(NSPoint)p column:(NSInteger *)column row:(NSInteger *)row
{
  NSRect area = [self area];
  CGFloat dx = [self fromLeft] ? p.x - NSMinX (area) : NSMaxX (area) - p.x;
  *column = MAX (0, MIN ([self columns] - 1, (NSInteger)floor (dx / FVCellWidth)));
  *row = MAX (0, MIN ([self rows] - 1, (NSInteger)floor ((p.y - NSMinY (area)) / FVCellHeight)));
}

- (NSRect)iconRectFor:(FVDesktopEntry *)entry
{
  NSRect cell = [self cellRectForColumn:entry->column row:entry->row];
  return NSMakeRect (floor (NSMidX (cell) - FVIconSize / 2), NSMinY (cell) + 4, FVIconSize,
                     FVIconSize);
}

- (NSDictionary *)labelAttributes:(BOOL)selectedLabel
{
  NSMutableParagraphStyle *style = AUTORELEASE ([[NSMutableParagraphStyle alloc] init]);
  [style setAlignment:NSCenterTextAlignment];
  [style setLineBreakMode:NSLineBreakByWordWrapping];
  /* White on any background, as a Mac's desktop names are, over a
     shadow (drawRect:). */
  NSColor *color = selectedLabel ? [NSColor selectedControlTextColor] : [NSColor whiteColor];
  return [NSDictionary dictionaryWithObjectsAndKeys:
      [NSFont systemFontOfSize:12], NSFontAttributeName, color, NSForegroundColorAttributeName,
      style, NSParagraphStyleAttributeName, nil];
}

/* The name as shown: whole when it fits in two lines, else shortened in
   the middle, keeping its start and its end with the extension, as the
   Finder does ("Screenshot 2026-11…00.10.png"). */
- (NSString *)labelFor:(FVDesktopEntry *)entry
{
  if (entry->label)
    return entry->label;
  NSDictionary *attrs = [self labelAttributes:NO];
  NSSize box = NSMakeSize (FVCellWidth - 6, 1000);
  CGFloat twoLines = 2 * [[NSFont systemFontOfSize:12] defaultLineHeightForFont] + 1;
  NSString *name = entry->name;
  NSString *display = name;
  if ([name boundingRectWithSize:box options:NSStringDrawingUsesLineFragmentOrigin
                      attributes:attrs].size.height > twoLines)
    {
      NSUInteger length = [name length];
      NSUInteger tail = MIN (length / 3, [[name pathExtension] length] + 6);
      NSUInteger head;
      display = nil;
      for (head = length - tail; head > 1; head--)
        {
          NSString *candidate = [NSString stringWithFormat:@"%@\u2026%@",
              [name substringToIndex:head], [name substringFromIndex:length - tail]];
          if ([candidate boundingRectWithSize:box options:NSStringDrawingUsesLineFragmentOrigin
                                   attributes:attrs].size.height <= twoLines)
            {
              display = candidate;
              break;
            }
        }
      if (display == nil)
        display = name;
    }
  entry->label = [display copy];
  return entry->label;
}

/* The name under the icon: at most two lines, as wide as it needs. */
- (NSRect)labelRectFor:(FVDesktopEntry *)entry
{
  NSRect cell = [self cellRectForColumn:entry->column row:entry->row];
  NSRect text = [[self labelFor:entry] boundingRectWithSize:NSMakeSize (FVCellWidth - 6, 32)
      options:NSStringDrawingUsesLineFragmentOrigin
      attributes:[self labelAttributes:NO]];
  CGFloat width = MIN (FVCellWidth + 2, ceil (NSWidth (text)) + 8);
  CGFloat height = MIN (32, ceil (NSHeight (text)) + 2);
  return NSMakeRect (floor (NSMidX (cell) - width / 2), NSMinY (cell) + FVIconSize + 8, width,
                     height);
}

- (FVDesktopEntry *)entryAtPoint:(NSPoint)p
{
  NSEnumerator *e = [entries reverseObjectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    if (NSPointInRect (p, NSInsetRect ([self iconRectFor:entry], -4, -2))
        || NSPointInRect (p, [self labelRectFor:entry]))
      return entry;
  return nil;
}

- (FVDesktopEntry *)entryForPath:(NSString *)value
{
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    if ([entry->path isEqual:value])
      return entry;
  return nil;
}

- (NSImage *)iconFor:(FVDesktopEntry *)entry
{
  NSImage *image = [icons objectForKey:entry->path];
  if (image)
    return image;
  /* The theme's disks: Workspace's own HardDisk would hide its HardDisk. */
  if (entry->startup)
    {
      image = [NSImage imageNamed:@"Root_PC"];
      if (image == nil)
        image = [NSImage imageNamed:@"HardDisk"];
    }
  else if (entry->disk)
    {
      image = [NSImage imageNamed:@"RemovableDisk"];
      if (image == nil)
        image = [NSImage imageNamed:@"HardDisk"];
    }
  else
    /* File Viewer's icon, with its thumbnail once made: not kept here. */
    return [[self agent] iconForPath:entry->path];
  if (image)
    [icons setObject:image forKey:entry->path];
  return image;
}

/* What's there now: the disks, then the files, each in the order the
   user sorted them. */
- (NSArray *)currentStamp
{
  struct stat st;
  NSNumber *changed = [NSNumber numberWithDouble:
      stat ([desktopPath fileSystemRepresentation], &st) == 0 ? (double)st.st_mtime : 0];
  return [NSArray arrayWithObjects:changed, FVVolumesInMountRoots (), nil];
}

- (NSArray *)sortedDesktopItems
{
  NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:desktopPath
                                                                       error:NULL];
  NSMutableArray *found = [NSMutableArray array];
  NSUInteger i;
  for (i = 0; i < [names count]; i++)
    {
      NSString *name = [names objectAtIndex:i];
      if ([name hasPrefix:@"."])
        continue;
      FVItem *item = [FVItem itemAtPath:[desktopPath stringByAppendingPathComponent:name]];
      if (item)
        [found addObject:item];
    }
  NSString *sort = [[NSUserDefaults standardUserDefaults] stringForKey:FVDesktopSortKey];
  NSString *column = [sort isEqual:@"kind"] ? @"kind" : [sort isEqual:@"date"] ? @"modified" : nil;
  return [found sortedArrayUsingFunction:FVCompareDesktopItems context:column];
}

static NSInteger
FVCompareDesktopItems (id a, id b, void *context)
{
  NSString *column = (NSString *)context;
  if (column)
    {
      id x = [a valueForColumn:column], y = [b valueForColumn:column];
      NSComparisonResult r = NSOrderedSame;
      if ([x respondsToSelector:@selector (compare:)] && y)
        r = [x compare:y];
      /* Newest first, as the Finder sorts by date. */
      if ([column isEqual:@"modified"])
        r = -r;
      if (r != NSOrderedSame)
        return r;
    }
  return [[a name] localizedCaseInsensitiveCompare:[b name]];
}

- (void)reloadEntries
{
  NSMutableArray *list = [NSMutableArray array];
  FVDesktopEntry *entry;
  NSArray *volumes = disks ? [FVVolumesInMountRoots ()
      sortedArrayUsingSelector:@selector (localizedCaseInsensitiveCompare:)] : [NSArray array];
  NSUInteger i;
  if (disks)
    {
      entry = AUTORELEASE ([[FVDesktopEntry alloc] init]);
      entry->path = [@"/" copy];
      entry->name = [@"NextBSD" copy];
      entry->disk = entry->startup = YES;
      [list addObject:entry];
    }
  for (i = 0; i < [volumes count]; i++)
    {
      entry = AUTORELEASE ([[FVDesktopEntry alloc] init]);
      entry->path = [[volumes objectAtIndex:i] copy];
      entry->name = [[entry->path lastPathComponent] copy];
      entry->disk = YES;
      [list addObject:entry];
    }
  NSArray *items = [self sortedDesktopItems];
  for (i = 0; i < [items count]; i++)
    {
      entry = AUTORELEASE ([[FVDesktopEntry alloc] init]);
      entry->path = [[[items objectAtIndex:i] path] copy];
      entry->name = [[[items objectAtIndex:i] name] copy];
      [list addObject:entry];
    }
  [entries setArray:list];
  /* Forget the chosen icons that went away. */
  NSMutableSet *paths = [NSMutableSet set];
  NSEnumerator *e = [entries objectEnumerator];
  while ((entry = [e nextObject]) != nil)
    [paths addObject:entry->path];
  [selected intersectSet:paths];
  /* The icons the user moved stay where they are; the others flow in
     order around them. Clean Up and Sort By let them all flow again. */
  [self layoutEntries];
  [self savePositions];
  [self selectionChanged];
}

/* Icons keep the cell the user put them in; the others take the next free
   cell, down each column from the corner. */
- (NSMutableDictionary *)positions
{
  if (positions == nil)
    {
      NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:FVDesktopPositionsPath ()];
      positions = [[NSMutableDictionary alloc] initWithDictionary:
          [saved isKindOfClass:[NSDictionary class]] ? saved : [NSDictionary dictionary]];
    }
  return positions;
}

- (void)writePositions
{
  NSString *file = FVDesktopPositionsPath ();
  [[NSFileManager defaultManager]
            createDirectoryAtPath:[file stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES
                       attributes:nil
                            error:NULL];
  [[self positions] writeToFile:file atomically:YES];
}

- (void)layoutEntries
{
  NSDictionary *saved = [self positions];
  NSInteger columns = [self columns], rows = [self rows];
  NSMutableSet *taken = [NSMutableSet set];
  NSMutableArray *unplaced = [NSMutableArray array];
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    {
      NSArray *cell = [[saved objectForKey:entry->path] componentsSeparatedByString:@" "];
      if ([cell count] == 2)
        {
          NSInteger c = [[cell objectAtIndex:0] integerValue];
          NSInteger r = [[cell objectAtIndex:1] integerValue];
          NSString *key = [NSString stringWithFormat:@"%ld %ld", (long)c, (long)r];
          if (c >= 0 && r >= 0 && c < columns && r < rows && ![taken containsObject:key])
            {
              entry->column = c;
              entry->row = r;
              [taken addObject:key];
              continue;
            }
        }
      [unplaced addObject:entry];
    }
  NSInteger c = 0, r = 0;
  e = [unplaced objectEnumerator];
  while ((entry = [e nextObject]) != nil)
    {
      while ([taken containsObject:[NSString stringWithFormat:@"%ld %ld", (long)c, (long)r]])
        if (++r >= rows)
          {
            r = 0;
            c++;
          }
      entry->column = c;
      entry->row = r;
      [taken addObject:[NSString stringWithFormat:@"%ld %ld", (long)c, (long)r]];
    }
  [self setNeedsDisplay:YES];
}

/* The moved icons' cells as they are now. A moved file that's gone from
   ~/Desktop is forgotten; a moved disk keeps its place while it's away
   (unplugged, or the disks hidden). */
- (void)savePositions
{
  NSMutableDictionary *now = [NSMutableDictionary dictionary];
  NSDictionary *placed = [self positions];
  NSEnumerator *e = [placed keyEnumerator];
  NSString *path;
  while ((path = [e nextObject]) != nil)
    {
      FVDesktopEntry *entry = [self entryForPath:path];
      if (entry)
        [now setObject:[NSString stringWithFormat:@"%ld %ld", (long)entry->column,
                                                  (long)entry->row]
                forKey:path];
      else if (![path hasPrefix:[desktopPath stringByAppendingString:@"/"]])
        [now setObject:[placed objectForKey:path] forKey:path];
    }
  if ([now isEqual:placed])
    return;
  [[self positions] setDictionary:now];
  [self writePositions];
}

/* What's in ~/Desktop is always on the desktop; the disks, when the
   Desktop icons setting says so (the Mac style's default). */
- (void)update
{
  shown = YES;
  disks = [FVDesktopSettings desktopShowsDisks];
  [self reloadEntries];
}

- (BOOL)showsThumbnailFiles
{
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    if (!entry->disk && [FVThumbnailOperation supportsPath:entry->path])
      return YES;
  return NO;
}

- (void)check:(NSTimer *)timer
{
  if (!shown)
    return;
  /* Thumbnails arrive from File Viewer's queue later: draw again while
     the desktop shows files that have them. */
  if (redraws > 0 || [self showsThumbnailFiles])
    {
      if (redraws > 0)
        redraws--;
      [self setNeedsDisplay:YES];
    }
  NSArray *now = [self currentStamp];
  if ([now isEqual:stamp])
    return;
  redraws = 3;
  ASSIGN (stamp, now);
  [self reloadEntries];
  [self placeArrivals];
}

/* A new folder starts with its name being edited; dropped items go where
   they were dropped. */
- (void)placeArrivals
{
  if (pendingDropNames)
    {
      NSInteger column, row;
      [self cellAtPoint:pendingDrop column:&column row:&row];
      NSArray *names = AUTORELEASE (RETAIN (pendingDropNames));
      DESTROY (pendingDropNames);
      NSMutableArray *moved = [NSMutableArray array];
      NSUInteger i;
      for (i = 0; i < [names count]; i++)
        {
          FVDesktopEntry *entry = [self entryForPath:
              [desktopPath stringByAppendingPathComponent:[names objectAtIndex:i]]];
          if (entry)
            [moved addObject:entry];
        }
      [self moveEntries:moved toColumn:column row:row];
    }
  if (pendingEdit && [self entryForPath:pendingEdit])
    {
      [selected removeAllObjects];
      [selected addObject:pendingEdit];
      [self selectionChanged];
      NSString *value = AUTORELEASE (RETAIN (pendingEdit));
      DESTROY (pendingEdit);
      [self beginEditing:value];
    }
}

- (void)setFrame:(NSRect)frame
{
  [super setFrame:frame];
  if (shown)
    [self layoutEntries];
}

/* ---- Drawing ---- */

- (void)drawRect:(NSRect)dirty
{
  [[NSColor clearColor] set];
  NSRectFill (dirty);
  if (!shown)
    return;
  BOOL light = [self light];
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    {
      NSRect cell = [self cellRectForColumn:entry->column row:entry->row];
      if (!NSIntersectsRect (cell, dirty))
        continue;
      BOOL chosen = [selected containsObject:entry->path];
      NSRect iconRect = [self iconRectFor:entry];
      if (chosen)
        {
          [[NSColor colorWithCalibratedWhite:0 alpha:light ? .14 : .32] set];
          [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect (iconRect, -4, -4)
                                           xRadius:6
                                           yRadius:6] fill];
        }
      NSImage *image = [self iconFor:entry];
      NSSize size = [image size];
      CGFloat scale = size.width > 0 && size.height > 0
                          ? MIN (FVIconSize / size.width, FVIconSize / size.height) : 1;
      NSRect drawn = NSMakeRect (floor (NSMidX (iconRect) - size.width * scale / 2),
                                 floor (NSMidY (iconRect) - size.height * scale / 2),
                                 floor (size.width * scale), floor (size.height * scale));
      [image drawInRect:drawn
               fromRect:NSZeroRect
              operation:NSCompositeSourceOver
               fraction:1.0
         respectFlipped:YES
                  hints:nil];
      if ([entry->path isEqual:editingPath])
        continue;
      NSRect label = [self labelRectFor:entry];
      NSRect text = NSInsetRect (label, 4, 1);
      if (chosen)
        {
          [[NSColor selectedControlColor] set];
          [[NSBezierPath bezierPathWithRoundedRect:label xRadius:4 yRadius:4] fill];
        }
      else
        {
          /* A shadow under white names, so they read on any background. */
          NSMutableDictionary *shadow = AUTORELEASE ([[self labelAttributes:NO] mutableCopy]);
          [shadow setObject:[NSColor colorWithCalibratedWhite:0 alpha:.75]
                     forKey:NSForegroundColorAttributeName];
          [[self labelFor:entry] drawInRect:NSOffsetRect (text, 0, 1) withAttributes:shadow];
        }
      [[self labelFor:entry] drawInRect:text withAttributes:[self labelAttributes:chosen]];
    }
  if (banding)
    {
      [[NSColor colorWithCalibratedWhite:light ? 0 : 1 alpha:.12] set];
      NSRectFillUsingOperation (band, NSCompositeSourceOver);
      [[NSColor colorWithCalibratedWhite:light ? 0 : 1 alpha:.55] set];
      NSFrameRect (band);
    }
}

/* ---- Choosing ---- */

- (NSArray *)selectedPaths
{
  NSMutableArray *paths = [NSMutableArray array];
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    if ([selected containsObject:entry->path])
      [paths addObject:entry->path];
  return paths;
}

- (NSArray *)selectedEntries
{
  NSMutableArray *chosen = [NSMutableArray array];
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    if ([selected containsObject:entry->path])
      [chosen addObject:entry];
  return chosen;
}

/* The agent acts on the chosen icons; the Inspector follows them. */
- (void)selectionChanged
{
  if (agent || [selected count])
    {
      [[self agent] setSelectionOverride:[self selectedPaths]];
      [[FVInspector sharedInspector] viewerSelectionChanged:agent];
    }
  [self setNeedsDisplay:YES];
}

- (BOOL)selectionHasDisk
{
  NSEnumerator *e = [[self selectedEntries] objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    if (entry->disk)
      return YES;
  return NO;
}

- (BOOL)selectionHasStartupDisk
{
  return [selected containsObject:@"/"];
}

- (void)mouseDown:(NSEvent *)event
{
  [[self window] makeKeyWindow];
  [[self window] makeFirstResponder:self];
  [self endEditing:YES];
  if (!shown)
    return;
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  FVDesktopEntry *entry = [self entryAtPoint:p];
  NSUInteger flags = [event modifierFlags];
  downPoint = p;
  ASSIGN (downPath, entry ? entry->path : nil);
  if (entry && [event clickCount] == 2)
    {
      [self open:self];
      return;
    }
  if (entry == nil)
    {
      if (!(flags & (NSShiftKeyMask | NSCommandKeyMask)))
        [selected removeAllObjects];
      banding = YES;
      band = NSMakeRect (p.x, p.y, 0, 0);
      [self selectionChanged];
      return;
    }
  if (flags & (NSShiftKeyMask | NSCommandKeyMask | NSControlKeyMask))
    {
      if ([selected containsObject:entry->path])
        [selected removeObject:entry->path];
      else
        [selected addObject:entry->path];
    }
  else if (![selected containsObject:entry->path])
    {
      [selected removeAllObjects];
      [selected addObject:entry->path];
    }
  dragPending = [selected containsObject:entry->path];
  [self selectionChanged];
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  if (banding)
    {
      band = NSMakeRect (MIN (p.x, downPoint.x), MIN (p.y, downPoint.y),
                         fabs (p.x - downPoint.x), fabs (p.y - downPoint.y));
      NSEnumerator *e = [entries objectEnumerator];
      FVDesktopEntry *entry;
      while ((entry = [e nextObject]) != nil)
        if (NSIntersectsRect (band, [self iconRectFor:entry])
            || NSIntersectsRect (band, [self labelRectFor:entry]))
          [selected addObject:entry->path];
        else if (!([event modifierFlags] & (NSShiftKeyMask | NSCommandKeyMask)))
          [selected removeObject:entry->path];
      [self selectionChanged];
      return;
    }
  if (!dragPending || (fabs (p.x - downPoint.x) < 4 && fabs (p.y - downPoint.y) < 4))
    return;
  dragPending = NO;
  NSArray *paths = [self selectedPaths];
  if (![paths count])
    return;
  /* Files go anywhere File Viewer takes files; disks only move about the
     desktop. */
  NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSDragPboard];
  if ([self selectionHasDisk])
    [pb declareTypes:[NSArray arrayWithObject:FVDesktopIconsPboardType] owner:nil];
  else
    {
      [pb declareTypes:[NSArray arrayWithObjects:NSFilenamesPboardType,
                                                 FVDesktopIconsPboardType, nil]
                 owner:nil];
      [pb setPropertyList:paths forType:NSFilenamesPboardType];
    }
  [pb setPropertyList:paths forType:FVDesktopIconsPboardType];
  FVDesktopEntry *first = [self entryForPath:downPath];
  if (first == nil)
    first = [[self selectedEntries] objectAtIndex:0];
  NSImage *image = AUTORELEASE ([[self iconFor:first] copy]);
  [image setScalesWhenResized:YES];
  [image setSize:NSMakeSize (FVIconSize, FVIconSize)];
  NSRect iconRect = [self iconRectFor:first];
  [self dragImage:image
               at:NSMakePoint (NSMinX (iconRect), NSMaxY (iconRect))
           offset:NSZeroSize
            event:event
       pasteboard:pb
           source:self
        slideBack:YES];
}

- (void)mouseUp:(NSEvent *)event
{
  if (banding)
    {
      banding = NO;
      [self setNeedsDisplay:YES];
    }
  dragPending = NO;
}

/* ---- Dragging ---- */

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local
{
  return local ? NSDragOperationMove | NSDragOperationCopy | NSDragOperationGeneric
               : NSDragOperationCopy;
}

/* A folder or disk icon under the pointer, other than those dragged. */
- (FVDesktopEntry *)dropTargetAt:(NSPoint)p fromSelf:(BOOL)fromSelf
{
  FVDesktopEntry *entry = [self entryAtPoint:p];
  if (entry == nil || (fromSelf && [selected containsObject:entry->path]))
    return nil;
  if (entry->disk || [[FVItem itemAtPath:entry->path] directory])
    return [[NSWorkspace sharedWorkspace] isFilePackageAtPath:entry->path] ? nil : entry;
  return nil;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
  if (!shown)
    return NSDragOperationNone;
  BOOL fromSelf = [sender draggingSource] == self;
  NSPoint p = [self convertPoint:[sender draggingLocation] fromView:nil];
  FVDesktopEntry *target = [self dropTargetAt:p fromSelf:fromSelf];
  if (fromSelf)
    return target && ![self selectionHasDisk] ? NSDragOperationMove : NSDragOperationGeneric;
  if (![[[sender draggingPasteboard] types] containsObject:NSFilenamesPboardType])
    return NSDragOperationNone;
  return NSDragOperationCopy;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
  return [self draggingUpdated:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
  if (!shown)
    return NO;
  BOOL fromSelf = [sender draggingSource] == self;
  NSPoint p = [self convertPoint:[sender draggingLocation] fromView:nil];
  FVDesktopEntry *target = [self dropTargetAt:p fromSelf:fromSelf];
  if (fromSelf)
    {
      if (target && ![self selectionHasDisk])
        {
          /* Onto a folder or disk: in it. */
          [[self agent] runOperation:@"move" paths:[self selectedPaths] destination:target->path];
          return YES;
        }
      /* Elsewhere on the desktop: the icons move there, keeping their
         places relative to the one the pointer holds. */
      FVDesktopEntry *held = [self entryForPath:downPath];
      NSInteger column, row;
      [self cellAtPoint:NSMakePoint (p.x, p.y) column:&column row:&row];
      if (held)
        [self moveEntries:[self selectedEntries]
                 byColumns:column - held->column
                      rows:row - held->row];
      return YES;
    }
  NSArray *paths = [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
  if (![paths isKindOfClass:[NSArray class]] || ![paths count])
    return NO;
  /* As in File Viewer, dropped files are copied: into the folder or disk
     under the pointer, else onto the desktop where they were dropped. */
  if (target)
    [[self agent] runOperation:@"copy" paths:paths destination:target->path];
  else
    {
      NSMutableArray *names = [NSMutableArray array];
      NSUInteger i;
      for (i = 0; i < [paths count]; i++)
        [names addObject:[[paths objectAtIndex:i] lastPathComponent]];
      ASSIGN (pendingDropNames, names);
      pendingDrop = p;
      [[self agent] runOperation:@"copy" paths:paths destination:desktopPath];
    }
  return YES;
}

/* Moves icons to cells: each to the nearest free one. */
- (void)placeEntries:(NSArray *)moving atCells:(NSArray *)cells
{
  NSInteger columns = [self columns], rows = [self rows];
  NSMutableSet *taken = [NSMutableSet set];
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    if (![moving containsObject:entry])
      [taken addObject:[NSString stringWithFormat:@"%ld %ld", (long)entry->column,
                                                  (long)entry->row]];
  NSUInteger i;
  for (i = 0; i < [moving count]; i++)
    {
      entry = [moving objectAtIndex:i];
      NSArray *want = [cells objectAtIndex:i];
      NSInteger c = MAX (0, MIN (columns - 1, [[want objectAtIndex:0] integerValue]));
      NSInteger r = MAX (0, MIN (rows - 1, [[want objectAtIndex:1] integerValue]));
      NSInteger best = -1, bestC = c, bestR = r, cc, rr;
      for (cc = 0; cc < columns; cc++)
        for (rr = 0; rr < rows; rr++)
          {
            if ([taken containsObject:[NSString stringWithFormat:@"%ld %ld", (long)cc, (long)rr]])
              continue;
            NSInteger d = (cc - c) * (cc - c) + (rr - r) * (rr - r);
            if (best < 0 || d < best)
              {
                best = d;
                bestC = cc;
                bestR = rr;
              }
          }
      entry->column = bestC;
      entry->row = bestR;
      [taken addObject:[NSString stringWithFormat:@"%ld %ld", (long)bestC, (long)bestR]];
      /* Moved by the user: it stays here. */
      [[self positions] setObject:[NSString stringWithFormat:@"%ld %ld", (long)bestC,
                                                         (long)bestR]
                           forKey:entry->path];
    }
  /* The icons that flow close up around it. */
  [self layoutEntries];
  [self savePositions];
}

- (void)moveEntries:(NSArray *)moving byColumns:(NSInteger)dc rows:(NSInteger)dr
{
  NSMutableArray *cells = [NSMutableArray array];
  NSEnumerator *e = [moving objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    [cells addObject:[NSArray arrayWithObjects:[NSNumber numberWithInteger:entry->column + dc],
                                               [NSNumber numberWithInteger:entry->row + dr], nil]];
  [self placeEntries:moving atCells:cells];
}

- (void)moveEntries:(NSArray *)moving toColumn:(NSInteger)column row:(NSInteger)row
{
  NSMutableArray *cells = [NSMutableArray array];
  NSUInteger i;
  for (i = 0; i < [moving count]; i++)
    [cells addObject:[NSArray arrayWithObjects:[NSNumber numberWithInteger:column],
                                               [NSNumber numberWithInteger:row + i], nil]];
  [self placeEntries:moving atCells:cells];
}

/* ---- Menus ---- */

- (NSMenu *)menuForEvent:(NSEvent *)event
{
  if (!shown)
    return [super menuForEvent:event];
  [self endEditing:YES];
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  FVDesktopEntry *entry = [self entryAtPoint:p];
  NSMenu *menu;
  if (entry == nil)
    {
      [selected removeAllObjects];
      [self selectionChanged];
      menuPoint = p;
      menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Desktop"]);
      [self addItem:@"New Folder" action:@selector (newFolder:) to:menu];
      [self addItem:@"Paste Item" action:@selector (paste:) to:menu];
      [self addItem:@"Clean Up" action:@selector (cleanUp:) to:menu];
      NSMenu *sort = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Sort By"]);
      [[self addItem:@"Name" action:@selector (sortBy:) to:sort] setRepresentedObject:@"name"];
      [[self addItem:@"Kind" action:@selector (sortBy:) to:sort] setRepresentedObject:@"kind"];
      [[self addItem:@"Date Modified" action:@selector (sortBy:) to:sort]
          setRepresentedObject:@"date"];
      [[menu addItemWithTitle:@"Sort By" action:NULL keyEquivalent:@""] setSubmenu:sort];
      [self addItem:@"Change Background…" action:@selector (changeBackground:) to:menu];
      return menu;
    }
  if (![selected containsObject:entry->path])
    {
      [selected removeAllObjects];
      [selected addObject:entry->path];
      [self selectionChanged];
    }
  menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"File"]);
  if ([self selectionHasDisk])
    {
      [self addItem:@"Open" action:@selector (open:) to:menu];
      [self addItem:@"Get Info" action:@selector (info:) to:menu];
      if (![self selectionHasStartupDisk])
        [self addItem:@"Eject" action:@selector (eject:) to:menu];
      return menu;
    }
  NSArray *titles = [NSArray arrayWithObjects:@"Open", @"Open With…", @"Get Info", @"Rename",
      @"Make Alias", @"Show in File Viewer", @"Add to Dock", @"Add to Favorites", @"Copy",
      @"Duplicate", @"Move to Trash", nil];
  SEL actions[] = { @selector (open:), @selector (openWith:), @selector (info:),
                    @selector (rename:), @selector (makeAlias:), @selector (showInFileViewer:),
                    @selector (addToDock:), @selector (addFavorite:), @selector (copy:),
                    @selector (duplicate:), @selector (trash:) };
  NSUInteger i;
  for (i = 0; i < [titles count]; i++)
    [self addItem:[titles objectAtIndex:i] action:actions[i] to:menu];
  return menu;
}

- (id<NSMenuItem>)addItem:(NSString *)title action:(SEL)action to:(NSMenu *)menu
{
  id<NSMenuItem> item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
  [item setTarget:self];
  return item;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = [item action];
  NSUInteger count = [selected count];
  BOOL disk = [self selectionHasDisk];
  if (!shown)
    return NO;
  if (action == @selector (paste:))
    return [[[NSPasteboard generalPasteboard] types] containsObject:NSFilenamesPboardType];
  if (action == @selector (newFolder:) || action == @selector (cleanUp:)
      || action == @selector (changeBackground:) || action == @selector (selectAll:))
    return YES;
  if (action == @selector (sortBy:))
    {
      NSString *sort = [[NSUserDefaults standardUserDefaults] stringForKey:FVDesktopSortKey];
      [item setState:[[item representedObject] isEqual:sort ? sort : @"name"] ? NSOnState
                                                                             : NSOffState];
      return YES;
    }
  if (action == @selector (open:) || action == @selector (info:))
    return count > 0;
  if (action == @selector (eject:))
    return count > 0 && FVCanEjectPaths ([self selectedPaths]);
  if (action == @selector (rename:))
    return count == 1 && !disk;
  if (action == @selector (addToDock:) || action == @selector (addFavorite:))
    return count > 0 && !disk && [[self agent] validateMenuItem:item];
  return count > 0 && !disk;
}

/* ---- Actions ---- */

/* The agent does it, on the chosen icons. */
- (void)forward:(SEL)action
{
  [self endEditing:YES];
  [[self agent] setSelectionOverride:[self selectedPaths]];
  [[self agent] performSelector:action withObject:self];
}

- (void)open:(id)sender
{
  NSArray *paths = [self selectedPaths];
  NSUInteger i;
  for (i = 0; i < [paths count]; i++)
    {
      NSString *p = [paths objectAtIndex:i];
      BOOL folder = [[FVItem itemAtPath:p] directory]
                    && ![[NSWorkspace sharedWorkspace] isFilePackageAtPath:p];
      NSString *extension = [[p pathExtension] lowercaseString];
      if (folder && ![extension isEqual:@"app"])
        [(FVApplication *)[NSApp delegate] openPath:p];
      else
        [[self agent] openPath:p];
    }
}

- (void)openWith:(id)sender
{
  [self forward:_cmd];
}

- (void)info:(id)sender
{
  [self forward:_cmd];
}

- (void)makeAlias:(id)sender
{
  [self forward:_cmd];
}

- (void)addToDock:(id)sender
{
  [self forward:_cmd];
}

- (void)addFavorite:(id)sender
{
  [self forward:_cmd];
}

- (void)copy:(id)sender
{
  [self forward:_cmd];
}

- (void)cut:(id)sender
{
  [self forward:_cmd];
}

- (void)copyPath:(id)sender
{
  [self forward:_cmd];
}

- (void)duplicate:(id)sender
{
  [self forward:_cmd];
}

- (void)trash:(id)sender
{
  [self forward:_cmd];
}

- (void)paste:(id)sender
{
  [self endEditing:YES];
  /* From the desktop's menu, where it was opened. */
  NSArray *paths = [[NSPasteboard generalPasteboard] propertyListForType:NSFilenamesPboardType];
  if ([sender isKindOfClass:[NSMenuItem class]] && [[[sender menu] title] isEqual:@"Desktop"]
      && [paths isKindOfClass:[NSArray class]])
    {
      NSMutableArray *names = [NSMutableArray array];
      NSUInteger i;
      for (i = 0; i < [paths count]; i++)
        [names addObject:[[paths objectAtIndex:i] lastPathComponent]];
      ASSIGN (pendingDropNames, names);
      pendingDrop = menuPoint;
    }
  [[self agent] setSelectionOverride:[NSArray array]];
  [[self agent] paste:self];
}

- (void)eject:(id)sender
{
  NSArray *paths = [self selectedPaths];
  NSUInteger i;
  for (i = 0; i < [paths count]; i++)
    FVEjectVolume ([paths objectAtIndex:i]);
}

- (void)showInFileViewer:(id)sender
{
  NSArray *paths = [self selectedPaths];
  if ([paths count])
    [(FVApplication *)[NSApp delegate] selectFile:[paths objectAtIndex:0]
                         inFileViewerRootedAtPath:desktopPath];
}

/* New Folder makes "New Folder" (or "New Folder 2"…) on the desktop and
   starts editing its name once it shows. */
- (void)newFolder:(id)sender
{
  [self endEditing:YES];
  NSString *target = [desktopPath stringByAppendingPathComponent:@"New Folder"];
  NSUInteger n = 2;
  struct stat st;
  while (lstat ([target fileSystemRepresentation], &st) == 0)
    target = [desktopPath stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"New Folder %lu", (unsigned long)n++]];
  ASSIGN (pendingEdit, target);
  /* From the desktop's menu, where it was opened; from the File menu,
     the next free place. */
  if ([sender isKindOfClass:[NSMenuItem class]] && [[sender menu] supermenu] == nil
      && [[[sender menu] title] isEqual:@"Desktop"])
    {
      ASSIGN (pendingDropNames, [NSArray arrayWithObject:[target lastPathComponent]]);
      pendingDrop = menuPoint;
    }
  [[self agent] setSelectionOverride:[NSArray array]];
  [[self agent] runOperation:@"mkdir" paths:[NSArray arrayWithObject:target] destination:nil];
}

- (void)cleanUp:(id)sender
{
  [[self positions] removeAllObjects];
  [self reloadEntries];
}

- (void)sortBy:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setObject:[sender representedObject]
                                            forKey:FVDesktopSortKey];
  [self cleanUp:sender];
}

- (void)changeBackground:(id)sender
{
  [(FVApplication *)[NSApp delegate] showBackgroundPreferences:sender];
}

- (void)selectAll:(id)sender
{
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    [selected addObject:entry->path];
  [self selectionChanged];
}

/* ---- Renaming in place ---- */

- (void)rename:(id)sender
{
  NSArray *paths = [self selectedPaths];
  if ([paths count] == 1 && ![self selectionHasDisk])
    [self beginEditing:[paths objectAtIndex:0]];
}

- (void)beginEditing:(NSString *)value
{
  FVDesktopEntry *entry = [self entryForPath:value];
  if (entry == nil || entry->disk)
    return;
  [self endEditing:YES];
  NSRect cell = [self cellRectForColumn:entry->column row:entry->row];
  NSRect frame = NSMakeRect (NSMinX (cell) - 12, NSMinY (cell) + FVIconSize + 6,
                             FVCellWidth + 24, 22);
  editor = [[NSTextField alloc] initWithFrame:frame];
  [editor setStringValue:entry->name];
  [editor setFont:[NSFont systemFontOfSize:12]];
  [editor setAlignment:NSCenterTextAlignment];
  [editor setDelegate:self];
  [editor setTarget:self];
  [editor setAction:@selector (commitEditing:)];
  ASSIGN (editingPath, value);
  [self addSubview:editor];
  [[self window] makeKeyWindow];
  [[self window] makeFirstResponder:editor];
  /* The name without its extension, as the Finder selects it. */
  NSText *text = [[self window] fieldEditor:YES forObject:editor];
  NSString *ext = [entry->name pathExtension];
  NSUInteger length = [ext length] && ![[FVItem itemAtPath:value] directory]
                          ? [entry->name length] - [ext length] - 1 : [entry->name length];
  [text setSelectedRange:NSMakeRange (0, length)];
  [self setNeedsDisplay:YES];
}

- (void)commitEditing:(id)sender
{
  [self endEditing:YES];
}

/* Escape cancels; GNUstep binds it to complete:. */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)view doCommandBySelector:(SEL)command
{
  if (sel_isEqual (command, @selector (cancelOperation:))
      || sel_isEqual (command, @selector (complete:)))
    {
      [self endEditing:NO];
      return YES;
    }
  return NO;
}

- (void)controlTextDidEndEditing:(NSNotification *)note
{
  if (editor)
    [self endEditing:YES];
}

- (void)endEditing:(BOOL)commit
{
  if (editor == nil)
    return;
  NSTextField *field = AUTORELEASE (editor);
  NSString *source = AUTORELEASE (editingPath);
  editor = nil;
  editingPath = nil;
  NSString *name = [field stringValue];
  [field setDelegate:nil];
  [field removeFromSuperview];
  [[self window] makeFirstResponder:self];
  [self setNeedsDisplay:YES];
  if (!commit || ![name length] || [name isEqual:[source lastPathComponent]])
    return;
  /* The icon keeps its place under its new name. */
  NSString *renamed = [[source stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:name];
  FVDesktopEntry *entry = [self entryForPath:source];
  NSString *problem = [[self agent] renamePath:source toName:name];
  if (problem)
    {
      FVRunAlert (@"Workspace", @"Can’t Rename", problem, @"OK", nil);
      return;
    }
  /* A moved icon keeps its place under the new name. */
  if (entry && [[self positions] objectForKey:source])
    [[self positions] setObject:[NSString stringWithFormat:@"%ld %ld", (long)entry->column,
                                                           (long)entry->row]
                         forKey:renamed];
  [selected removeAllObjects];
  [selected addObject:renamed];
}

/* ---- Keys ---- */

- (FVDesktopEntry *)neighbourOf:(FVDesktopEntry *)from dx:(NSInteger)dx dy:(NSInteger)dy
{
  FVDesktopEntry *best = nil;
  NSInteger bestScore = 0;
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  /* Columns count from the corner the icons fill from: right is "back"
     a column on a Mac desktop. */
  NSInteger sign = [self fromLeft] ? 1 : -1;
  while ((entry = [e nextObject]) != nil)
    {
      if (entry == from)
        continue;
      NSInteger x = (entry->column - from->column) * sign, y = entry->row - from->row;
      NSInteger along = dx ? x * dx : y * dy;
      NSInteger across = dx ? labs (y) : labs (x);
      if (along <= 0)
        continue;
      NSInteger score = along * along + across * across * 4;
      if (best == nil || score < bestScore)
        {
          best = entry;
          bestScore = score;
        }
    }
  return best;
}

- (void)keyDown:(NSEvent *)event
{
  NSString *text = [event charactersIgnoringModifiers];
  if (!shown || ![text length])
    {
      [super keyDown:event];
      return;
    }
  unichar c = [text characterAtIndex:0];
  NSUInteger flags = [event modifierFlags];
  if (c == NSF2FunctionKey)
    {
      [self rename:self];
      return;
    }
  if ((c == NSDownArrowFunctionKey && (flags & NSCommandKeyMask)) || c == '\r'
      || c == NSEnterCharacter)
    {
      [self open:self];
      return;
    }
  if ((c == NSBackspaceCharacter || c == NSDeleteCharacter) && (flags & NSCommandKeyMask))
    {
      if ([selected count] && ![self selectionHasDisk])
        [self trash:self];
      return;
    }
  NSInteger dx = c == NSRightArrowFunctionKey ? 1 : c == NSLeftArrowFunctionKey ? -1 : 0;
  NSInteger dy = c == NSDownArrowFunctionKey ? 1 : c == NSUpArrowFunctionKey ? -1 : 0;
  if (dx || dy)
    {
      NSArray *chosen = [self selectedEntries];
      FVDesktopEntry *next;
      if (![chosen count])
        next = [entries count] ? [entries objectAtIndex:0] : nil;
      else
        next = [self neighbourOf:[chosen lastObject] dx:dx dy:dy];
      if (next)
        {
          if (!(flags & NSShiftKeyMask))
            [selected removeAllObjects];
          [selected addObject:next->path];
          [self selectionChanged];
        }
      return;
    }
  if (flags & (NSCommandKeyMask | NSControlKeyMask))
    {
      [super keyDown:event];
      return;
    }
  /* Typing a name chooses the first icon that starts with it. */
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  NSString *prefix = now - typedAt < 1 && typed ? [typed stringByAppendingString:text] : text;
  ASSIGN (typed, prefix);
  typedAt = now;
  NSEnumerator *e = [entries objectEnumerator];
  FVDesktopEntry *entry;
  while ((entry = [e nextObject]) != nil)
    if ([entry->name rangeOfString:prefix
                           options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == 0)
      {
        [selected removeAllObjects];
        [selected addObject:entry->path];
        [self selectionChanged];
        return;
      }
}

@end

@implementation FVDesktop

+ (FVDesktop *)sharedDesktop
{
  static FVDesktop *shared;
  if (shared == nil)
    shared = [[FVDesktop alloc] init];
  return shared;
}

- (id)init
{
  if ((self = [super init]) != nil)
    windows = [[NSMutableArray alloc] init];
  return self;
}

- (void)show
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (screensDidChange:)
             name:NSApplicationDidChangeScreenParametersNotification
           object:nil];
  /* The style, the window mode, the Dock and the menus decide whether
     there are icons and where they go; the appearance, their colours. */
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (settingsChanged:)
             name:FVDesktopSettingsChangedNotification
           object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector (settingsChanged:)
                                               name:GSThemeDidActivateNotification
                                             object:nil];
  [self screensDidChange:nil];
}

- (void)settingsChanged:(NSNotification *)note
{
  /* The window mode reaches the defaults a moment after the notice when
     leaving tiling. */
  [[NSUserDefaults standardUserDefaults] synchronize];
  [iconView update];
  [NSObject cancelPreviousPerformRequestsWithTarget:iconView selector:@selector (update)
                                             object:nil];
  [iconView performSelector:@selector (update) withObject:nil afterDelay:1.0];
}

/* A window for each display again, at its full frame: the Dock and the
   menu bar are above it. The icons are on the main display's. */
- (void)screensDidChange:(NSNotification *)note
{
  NSArray *screens = [NSScreen screens];
  NSUInteger i;

  while ([windows count] > [screens count])
    {
      [[windows lastObject] close];
      [windows removeLastObject];
    }
  for (i = 0; i < [screens count]; i++)
    {
      NSRect frame = [[screens objectAtIndex:i] frame];
      if (i < [windows count])
        {
          [[windows objectAtIndex:i] setFrame:frame display:NO];
          continue;
        }
      NSWindow *window = [[FVDesktopWindow alloc] initWithContentRect:frame
                                                            styleMask:NSBorderlessWindowMask
                                                              backing:NSBackingStoreBuffered
                                                                defer:NO];
      [window setReleasedWhenClosed:NO];
      [window setOpaque:NO];
      [window setBackgroundColor:[NSColor clearColor]];
      [window setLevel:FVDesktopLevel];
      [window setCanHide:NO];
      [window setExcludedFromWindowsMenu:YES];
      [window setHasShadow:NO];
      if (i == 0)
        {
          iconView = [[FVDesktopView alloc] initWithFrame:[[window contentView] bounds]];
          [window setContentView:iconView];
          [window setInitialFirstResponder:iconView];
        }
      [window orderBack:self];
      [windows addObject:window];
      RELEASE (window);
    }
  [iconView update];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (iconView);
  RELEASE (windows);
  DEALLOC;
}

@end
