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

#import "FVWindow.h"
#import "FVApplication.h"
#import "FVOperations.h"
#import "FVIconView.h"
#import "FVLauncher.h"
#import "FVThumbnails.h"
#import "FVPanels.h"
#import "FVInspector.h"
#include <sys/statvfs.h>
#include <sys/stat.h>
#ifndef __linux__
#include <sys/param.h>
#include <sys/ucred.h>
#include <sys/mount.h>
#endif
#include <dirent.h>

/* The viewer background follows the theme; it is not a preference. A
   ViewerBackgroundColor saved by older versions is ignored. */
NSColor *
FVViewerBackgroundColor (void)
{
  return [[NSColor windowBackgroundColor]
      blendedColorWithFraction:.1 ofColor:[NSColor blackColor]];
}

/* Keep the text colours for the life of the app. libs-gui's table row drawing
   swaps a selected cell's text colour for the theme's highlight colour without
   retaining the original, so a cell holding the only reference to an
   autoreleased colour ends up pointing at freed memory. */
NSColor *
FVViewerTextColor (void)
{
  static NSColor *white = nil;
  static NSColor *black = nil;
  if (!white)
    {
      white = RETAIN ([NSColor whiteColor]);
      black = RETAIN ([NSColor blackColor]);
    }
  NSColor *color = [FVViewerBackgroundColor () colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  CGFloat brightness = .299 * [color redComponent] + .587 * [color greenComponent]
                       + .114 * [color blueComponent];
  return brightness < .5 ? white : black;
}

/* GNUstep's NSBrowser background setter is a stub; its matrices use this getter. */
@interface FVBrowser : NSBrowser

@end

@implementation FVBrowser

- (void)tile
{
  [super tile];
  NSEnumerator *views = [[self subviews] objectEnumerator];
  NSView *view;
  while ((view = [views nextObject]))
    if ([view isKindOfClass:[NSScrollView class]])
      {
        [(NSScrollView *)view setBackgroundColor:FVViewerBackgroundColor ()];
        [[(NSScrollView *)view contentView] setBackgroundColor:FVViewerBackgroundColor ()];
      }
}

- (NSColor *)backgroundColor
{
  return FVViewerBackgroundColor ();
}

@end

@interface FVWindow (Activity)

- (NSInteger)runDialog:(id<FVModalDialog>)dialog;
- (void)updateActivity;

@end

/* libs-base strips a leading /private, and raises when nothing is left. */
static NSString *
FVStandardizedPath (NSString *value)
{
  return [value isEqual:@"/private"] ? value : [value stringByStandardizingPath];
}

/* Apply the same visibility policy to every Locations section and mount poll. */
static NSArray *
FVVisibleLocationPaths (NSArray *paths)
{
  NSMutableArray *visible = [NSMutableArray array];
  BOOL excludeRun = FVExcludeRunFilesystems ();
  NSUInteger i;
  for (i = 0; i < [paths count]; i++)
    {
      id path = [paths objectAtIndex:i];
      if (![path isKindOfClass:[NSString class]])
        continue;
      NSString *standard = FVStandardizedPath (path);
      if (excludeRun && ([standard isEqual:@"/run"] || [standard hasPrefix:@"/run/"]))
        continue;
      [visible addObject:path];
    }
  return visible;
}

/* A volume is a mount point directly inside a mount root. On the BSDs the
   mount table is read without waiting, and nothing is stat'ed, so a hung
   network mount can't block the main thread, which polls this every second. */
static NSArray *
FVVolumesInMountRoots (void)
{
  NSMutableArray *found = [NSMutableArray array];
  NSArray *roots = [NSArray arrayWithObjects:@"/Volumes", @"/media",
      [@"/media" stringByAppendingPathComponent:NSUserName ()],
      [@"/run/media" stringByAppendingPathComponent:NSUserName ()], nil];
#ifdef __linux__
  NSUInteger i;
  for (i = 0; i < [roots count]; i++)
    {
      NSString *root = [roots objectAtIndex:i];
      struct stat parent;
      if (lstat ([root fileSystemRepresentation], &parent) != 0 || !S_ISDIR (parent.st_mode))
        continue;
      NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL];
      NSUInteger n;
      for (n = 0; n < [names count]; n++)
        {
          NSString *full = [root stringByAppendingPathComponent:[names objectAtIndex:n]];
          struct stat child;
          if ([[names objectAtIndex:n] hasPrefix:@"."]
              || lstat ([full fileSystemRepresentation], &child) != 0
              || !S_ISDIR (child.st_mode) || child.st_dev == parent.st_dev
              || [found containsObject:full])
            continue;
          [found addObject:full];
        }
    }
#else
  struct statfs *mounts;
  int count = getmntinfo (&mounts, MNT_NOWAIT);
  int m;
  for (m = 0; m < count; m++)
    {
      NSString *full = [[NSFileManager defaultManager]
          stringWithFileSystemRepresentation:mounts[m].f_mntonname
                                      length:strlen (mounts[m].f_mntonname)];
      if ([roots containsObject:[full stringByDeletingLastPathComponent]]
          && ![[full lastPathComponent] hasPrefix:@"."] && ![found containsObject:full])
        [found addObject:full];
    }
#endif
  return [found sortedArrayUsingSelector:@selector (caseInsensitiveCompare:)];
}

/* Whether / holds a folder with this name. Reading / never enters a filesystem
   mounted on the entry, unlike stat, so an autofs or NFS mount at /Network
   whose server is down can't block the sidebar. */
static BOOL
FVRootHasFolder (NSString *name)
{
  DIR *root = opendir ("/");
  struct dirent *entry;
  BOOL found = NO;
  if (!root)
    return NO;
  while (!found && (entry = readdir (root)))
    if ((entry->d_type == DT_DIR || entry->d_type == DT_LNK)
        && !strcmp (entry->d_name, [name fileSystemRepresentation]))
      found = YES;
  closedir (root);
  return found;
}

static NSString *
FVFileStamp (NSString *file, BOOL follow)
{
  struct stat st;
  if ((follow ? stat ([file fileSystemRepresentation], &st)
              : lstat ([file fileSystemRepresentation], &st)) != 0)
    return @"unavailable";
  return [NSString stringWithFormat:@"%llu:%llu:%llu:%u:%u:%u:%lld:%ld:%lld:%ld",
      (unsigned long long)st.st_dev, (unsigned long long)st.st_ino,
      (unsigned long long)st.st_size, (unsigned)st.st_mode, (unsigned)st.st_uid,
      (unsigned)st.st_gid, (long long)st.st_mtim.tv_sec, st.st_mtim.tv_nsec,
      (long long)st.st_ctim.tv_sec, st.st_ctim.tv_nsec];
}

static NSTextField *
FVLabel (NSRect frame, NSString *text)
{
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [field setEditable:NO];
  [field setBezeled:NO];
  [field setBordered:NO];
  [field setDrawsBackground:NO];
  [field setStringValue:text];
  return field;
}

static NSButton *
FVButton (NSView *view, NSString *title, SEL action, id target, CGFloat x, CGFloat width)
{
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (x, 0, width, 30)]);
  [button setTitle:title];
  [button setTarget:target];
  [button setAction:action];
  [view addSubview:button];
  return button;
}

/* Draw toolbar glyphs at their native size without depending on a theme's
   optional image names. Coordinates use AppKit's bottom-left origin. */
static NSImage *
FVToolbarImage (NSUInteger kind)
{
  NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize:NSMakeSize (20, 20)]);
  [image lockFocus];
  [[NSColor controlTextColor] set];
  NSBezierPath *glyph = [NSBezierPath bezierPath];
  [glyph setLineWidth:1.8];
  [glyph setLineCapStyle:NSRoundLineCapStyle];
  [glyph setLineJoinStyle:NSRoundLineJoinStyle];
  if (kind < 3)
    {
      if (kind == 2)
        {
          [glyph moveToPoint:NSMakePoint (10, 3)];
          [glyph lineToPoint:NSMakePoint (10, 17)];
          [glyph moveToPoint:NSMakePoint (4, 11)];
          [glyph lineToPoint:NSMakePoint (10, 17)];
          [glyph lineToPoint:NSMakePoint (16, 11)];
        }
      else
        {
          CGFloat tip = kind == 0 ? 3 : 17;
          CGFloat tail = 20 - tip;
          CGFloat wing = kind == 0 ? 9 : 11;
          [glyph moveToPoint:NSMakePoint (tail, 10)];
          [glyph lineToPoint:NSMakePoint (tip, 10)];
          [glyph moveToPoint:NSMakePoint (wing, 16)];
          [glyph lineToPoint:NSMakePoint (tip, 10)];
          [glyph lineToPoint:NSMakePoint (wing, 4)];
        }
    }
  else if (kind == 3)
    {
      [glyph moveToPoint:NSMakePoint (2, 10)];
      [glyph lineToPoint:NSMakePoint (10, 17)];
      [glyph lineToPoint:NSMakePoint (18, 10)];
      [glyph moveToPoint:NSMakePoint (4, 11)];
      [glyph lineToPoint:NSMakePoint (4, 3)];
      [glyph lineToPoint:NSMakePoint (8, 3)];
      [glyph lineToPoint:NSMakePoint (8, 8)];
      [glyph lineToPoint:NSMakePoint (12, 8)];
      [glyph lineToPoint:NSMakePoint (12, 3)];
      [glyph lineToPoint:NSMakePoint (16, 3)];
      [glyph lineToPoint:NSMakePoint (16, 11)];
    }
  else if (kind == 4)
    {
      [glyph appendBezierPathWithArcWithCenter:NSMakePoint (10, 10)
                                       radius:7
                                   startAngle:45
                                     endAngle:340];
      [glyph moveToPoint:NSMakePoint (15, 18)];
      [glyph lineToPoint:NSMakePoint (15, 13)];
      [glyph lineToPoint:NSMakePoint (10, 13)];
    }
  else if (kind == 5)
    {
      NSUInteger row;
      for (row = 0; row < 3; row++)
        {
          CGFloat y = 4 + row * 6;
          [glyph moveToPoint:NSMakePoint (3, y)];
          [glyph lineToPoint:NSMakePoint (4, y)];
          [glyph moveToPoint:NSMakePoint (8, y)];
          [glyph lineToPoint:NSMakePoint (17, y)];
        }
    }
  else if (kind == 6)
    {
      [glyph appendBezierPathWithRect:NSMakeRect (2, 3, 16, 14)];
      [glyph moveToPoint:NSMakePoint (7, 3)];
      [glyph lineToPoint:NSMakePoint (7, 17)];
      [glyph moveToPoint:NSMakePoint (13, 3)];
      [glyph lineToPoint:NSMakePoint (13, 17)];
    }
  else
    {
      NSUInteger row, column;
      for (row = 0; row < 2; row++)
        for (column = 0; column < 2; column++)
          [glyph appendBezierPathWithRect:NSMakeRect (3 + column * 9, 3 + row * 9, 5, 5)];
    }
  [glyph stroke];
  [image unlockFocus];
  return image;
}

static void
FVToolbarButton (NSView *view, NSString *title, SEL action, id target,
                 CGFloat x, NSUInteger kind)
{
  NSButton *button = FVButton (view, title, action, target, x, 36);
  [button setImage:FVToolbarImage (kind)];
  [button setImagePosition:NSImageOnly];
  [button setBordered:NO];
  [button setToolTip:title];
}

static NSInteger
FVCompare (id lhs, id rhs, void *context)
{
  FVItem *left = lhs, *right = rhs;
  NSDictionary *options = context;
  NSString *key = [options objectForKey:@"key"];
  if ([[options objectForKey:@"folders"] boolValue] && [left directory] != [right directory])
    return [left directory] ? NSOrderedAscending : NSOrderedDescending;
  id a, b;
  if ([key isEqual:@"size"])
    {
      a = [[left attributes] objectForKey:NSFileSize];
      b = [[right attributes] objectForKey:NSFileSize];
    }
  else if ([key isEqual:@"date"])
    {
      a = [left accessedDate] ? [left accessedDate] : [[left attributes] objectForKey:NSFileModificationDate];
      b = [right accessedDate] ? [right accessedDate] : [[right attributes] objectForKey:NSFileModificationDate];
    }
  else
    {
      a = [left valueForColumn:key];
      b = [right valueForColumn:key];
    }
  if (!a || !b)
    return a ? NSOrderedAscending : (b ? NSOrderedDescending : NSOrderedSame);
  NSInteger result = [a isKindOfClass:[NSString class]]
                         ? [a localizedCaseInsensitiveCompare:b ? b : @""]
                         : [a compare:b];
  if (!result)
    result = [[left name] localizedCaseInsensitiveCompare:[right name]];
  return [[options objectForKey:@"ascending"] boolValue] ? result : -result;
}

/* A small modal panel avoids unsupported NSAlert accessory APIs. */
@interface FVDialog : NSObject <FVModalDialog>
{
  NSPanel *panel;
  NSTextField *field;
  NSButton *apply;
  NSPopUpButton *choices;
}

- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
              value:(NSString *)value
            buttons:(NSArray *)buttons;
- (NSInteger)run;
- (NSString *)value;
- (BOOL)apply;
- (id)initWithApplications:(NSArray *)applications file:(NSString *)path;
- (NSString *)selectedApplication;
- (void)browseApplication:(id)sender;

@end

@implementation FVDialog

- (id)initWithApplications:(NSArray *)applications file:(NSString *)path
{
  self = [self initWithTitle:@"Open With"
                    message:[NSString stringWithFormat:@"Choose an application to open %@.",
                                                       [path lastPathComponent]]
                      value:@""
                    buttons:[NSArray arrayWithObjects:@"Open", @"Cancel", nil]];
  if (self)
    {
      [panel setContentSize:NSMakeSize (620, 300)];
      [field removeFromSuperview];
      RELEASE (field);
      field = nil;
      NSColor *textColor = FVDialogTextColor (panel);
      NSView *content = [panel contentView];
      NSArray *views = [content subviews];
      NSUInteger j;
      for (j = 0; j < [views count]; j++)
        {
          id view = [views objectAtIndex:j];
          if ([view isKindOfClass:[NSTextField class]])
            {
              [view setFrame:NSMakeRect (18, 250, 584, 30)];
              [view setStringValue:@"Open With"];
              [view setFont:[NSFont boldSystemFontOfSize:20]];
              [view setTextColor:textColor];
              [view setSelectable:NO];
            }
          else if ([view isKindOfClass:[NSButton class]] && [view tag] == 0)
            [view setEnabled:[applications count] > 0];
        }
      NSTextField *filename = FVLabel (NSMakeRect (18, 210, 584, 32), [path lastPathComponent]);
      [filename setFont:[NSFont systemFontOfSize:14]];
      [filename setTextColor:textColor];
      [filename setSelectable:NO];
      [content addSubview:filename];
      choices = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (18, 164, 458, 28)
                                          pullsDown:NO];
      NSUInteger i;
      for (i = 0; i < [applications count]; i++)
        {
          NSString *app = [applications objectAtIndex:i];
          /* Include the path to distinguish installations with the same name. */
          [choices addItemWithTitle:app];
          [[choices lastItem] setRepresentedObject:app];
        }
      [[panel contentView] addSubview:choices];
      NSButton *browse = FVButton (content, @"Other…", @selector (browseApplication:), self, 484, 118);
      [browse setFrameOrigin:NSMakePoint (484, 164)];
      [browse setTag:2];
      apply = [[NSButton alloc] initWithFrame:NSMakeRect (18, 120, 584, 26)];
      [apply setButtonType:NSSwitchButton];
      [apply setTitle:@"Always open this file type with the selected application"];
      [apply setEnabled:[[path pathExtension] length] > 0];
      [content addSubview:apply];
      NSString *help = [[path pathExtension] length]
          ? [NSString stringWithFormat:@"Applies to .%@ files in Workspace.\nChange later with File → Open With…",
                                       [[path pathExtension] lowercaseString]]
          : @"Files without an extension can only be opened once with this choice.";
      NSTextField *hint = FVLabel (NSMakeRect (18, 76, 584, 36), help);
      [hint setTextColor:textColor];
      [hint setFont:[NSFont systemFontOfSize:12]];
      [hint setSelectable:NO];
      [content addSubview:hint];
    }
  return self;
}

- (void)browseApplication:(id)sender
{
  NSOpenPanel *picker = [NSOpenPanel openPanel];
  [picker setTitle:@"Choose an application"];
  [picker setCanChooseDirectories:YES];
  [picker setCanChooseFiles:YES];
  [picker setAllowsMultipleSelection:NO];
  NSArray *directories = NSSearchPathForDirectoriesInDomains (NSApplicationDirectory,
                                                              NSAllDomainsMask, YES);
  if ([picker runModalForDirectory:[directories count] ? [directories objectAtIndex:0] : nil
                             file:nil types:[NSArray arrayWithObject:@"app"]] != NSOKButton)
    return;
  NSString *app = [picker filename];
  if (![[NSWorkspace sharedWorkspace] locateApplicationBinary:app])
    return;
  [choices addItemWithTitle:app];
  [[choices lastItem] setRepresentedObject:app];
  [choices selectItem:[choices lastItem]];
  NSArray *views = [[panel contentView] subviews];
  NSUInteger i;
  for (i = 0; i < [views count]; i++)
    {
      id view = [views objectAtIndex:i];
      if ([view isKindOfClass:[NSButton class]] && [view tag] == 0 && view != apply)
        [view setEnabled:YES];
    }
}

- (NSString *)selectedApplication
{
  return [[choices selectedItem] representedObject];
}

- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
              value:(NSString *)value
            buttons:(NSArray *)buttons
{
  if ((self = [super init]))
    {
      /* A prompt is one line of text over its field; a choice gets more room. */
      CGFloat height = value ? 140 : 230;
      panel = [[FVDialogPanel alloc] initWithContentRect:NSMakeRect (0, 0, 620, height)
                                               styleMask:NSTitledWindowMask
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
      [panel setTitle:title];
      NSView *content = [panel contentView];
      NSTextField *label = FVLabel (NSMakeRect (18, 100, 584, height - 118), message);
      [label setSelectable:NO];
      [label setTextColor:FVDialogTextColor (panel)];
      [content addSubview:label];
      if (value)
        {
          field = [[NSTextField alloc] initWithFrame:NSMakeRect (18, 64, 584, 28)];
          [field setStringValue:value];
          [content addSubview:field];
        }
      NSUInteger i;
      CGFloat width = 584.0 / [buttons count];
      for (i = 0; i < [buttons count]; i++)
        {
          NSButton *button = FVButton (content, [buttons objectAtIndex:i], @selector (choose:),
                                       self, 18 + i * width, width - 6);
          [button setFrameOrigin:NSMakePoint (18 + i * width, 18)];
          [button setTag:i];
          if (i == 0)
            [button setKeyEquivalent:@"\r"];
          else if ([[buttons objectAtIndex:i] isEqual:@"Cancel"])
            [button setKeyEquivalent:@"\e"];
        }
    }
  return self;
}

- (void)choose:(id)sender
{
  [NSApp stopModalWithCode:[sender tag]];
}

- (NSInteger)run
{
  [panel center];
  [panel makeKeyAndOrderFront:nil];
  if (field)
    {
      [panel makeFirstResponder:field];
      [field selectText:nil];
    }
  else if (choices)
    [panel makeFirstResponder:choices];
  return FVRunModalPanel (panel);
}

- (NSString *)value
{
  return [field stringValue];
}

- (BOOL)apply
{
  return [apply state] == NSOnState;
}

- (void)dealloc
{
  RELEASE (panel);
  RELEASE (field);
  RELEASE (apply);
  RELEASE (choices);
  DEALLOC;
}

@end

/* Go to Folder: one path field that completes folder names with Tab, lists
   recent and matching folders in its menu, accepts ~ and paths relative to
   the current folder, and reports a missing folder inside the panel. */
static NSString *const FVGoRecentsKey = @"GoToFolderRecents";

@interface FVGoPanel : NSObject <NSComboBoxDelegate, FVModalDialog>
{
  NSPanel *panel;
  NSComboBox *field;
  NSTextField *problem;
  NSString *base;
  NSString *destination;
}

- (id)initWithFolder:(NSString *)folder;
- (NSInteger)run;
- (NSString *)destination;

@end

@implementation FVGoPanel

- (id)initWithFolder:(NSString *)folder
{
  if ((self = [super init]))
    {
      base = [folder copy];
      panel = [[FVDialogPanel alloc] initWithContentRect:NSMakeRect (0, 0, 520, 150)
                                               styleMask:NSTitledWindowMask
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
      [panel setTitle:@"Go to Folder"];
      NSView *content = [panel contentView];
      NSTextField *label = FVLabel (NSMakeRect (18, 112, 484, 22), @"Go to the folder:");
      [label setSelectable:NO];
      [label setTextColor:FVDialogTextColor (panel)];
      [content addSubview:label];
      field = [[NSComboBox alloc] initWithFrame:NSMakeRect (18, 80, 484, 28)];
      [field setCompletes:NO];
      [field setNumberOfVisibleItems:10];
      [field setStringValue:folder];
      [field setDelegate:self];
      NSArray *recents = [[NSUserDefaults standardUserDefaults] arrayForKey:FVGoRecentsKey];
      NSUInteger i;
      for (i = 0; i < [recents count]; i++)
        if ([[recents objectAtIndex:i] isKindOfClass:[NSString class]])
          [field addItemWithObjectValue:[recents objectAtIndex:i]];
      [content addSubview:field];
      problem = RETAIN (FVLabel (NSMakeRect (18, 52, 484, 22), @""));
      [problem setSelectable:NO];
      [content addSubview:problem];
      NSButton *cancel = FVButton (content, @"Cancel", @selector (cancel:), self, 298, 100);
      [cancel setFrameOrigin:NSMakePoint (298, 14)];
      [cancel setKeyEquivalent:@"\e"];
      NSButton *go = FVButton (content, @"Go", @selector (go:), self, 402, 100);
      [go setFrameOrigin:NSMakePoint (402, 14)];
      [go setKeyEquivalent:@"\r"];
    }
  return self;
}

/* Problems are red; the count of several matches is plain text. */
- (void)showMessage:(NSString *)text error:(BOOL)error
{
  [problem setTextColor:error ? [NSColor colorWithCalibratedRed:.92 green:.32 blue:.26 alpha:1]
                              : FVDialogTextColor (panel)];
  [problem setStringValue:text];
}

- (NSString *)resolve:(NSString *)text
{
  text = [text stringByExpandingTildeInPath];
  if (![text isAbsolutePath])
    text = [base stringByAppendingPathComponent:text];
  return [text stringByStandardizingPath];
}

/* Tab completes the last component to the folders that start with it: all of
   one match (with a trailing slash), or the part several matches share. The
   matches also fill the field's menu. */
- (void)complete
{
  NSString *text = [field stringValue];
  if ([text isEqual:@"~"])
    {
      [field setStringValue:@"~/"];
      return;
    }
  NSRange slash = [text rangeOfString:@"/" options:NSBackwardsSearch];
  NSString *head = slash.location == NSNotFound ? @"" : [text substringToIndex:NSMaxRange (slash)];
  NSString *partial = [text substringFromIndex:[head length]];
  NSString *folder = [head length] ? [self resolve:head] : base;
  NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL]
      sortedArrayUsingSelector:@selector (caseInsensitiveCompare:)];
  NSMutableArray *matches = [NSMutableArray array];
  NSUInteger i;
  for (i = 0; i < [names count]; i++)
    {
      NSString *name = [names objectAtIndex:i];
      BOOL directory = NO;
      if (([name hasPrefix:@"."] && ![partial hasPrefix:@"."])
          || ([partial length]
              && [name rangeOfString:partial options:NSCaseInsensitiveSearch | NSAnchoredSearch]
                         .location
                     == NSNotFound)
          || ![[NSFileManager defaultManager]
                 fileExistsAtPath:[folder stringByAppendingPathComponent:name]
                      isDirectory:&directory]
          || !directory)
        continue;
      [matches addObject:name];
    }
  [field removeAllItems];
  for (i = 0; i < [matches count]; i++)
    [field addItemWithObjectValue:[head stringByAppendingString:[matches objectAtIndex:i]]];
  if (![matches count])
    {
      BOOL directory = NO;
      NSBeep ();
      if (![[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&directory]
          || !directory)
        [self showMessage:[NSString stringWithFormat:@"The folder “%@” can’t be found.",
                                                     [folder lastPathComponent]]
                    error:YES];
      else
        [self showMessage:[NSString stringWithFormat:@"No folder in “%@” starts with “%@”.",
                                                     [folder lastPathComponent], partial]
                    error:YES];
      return;
    }
  NSString *common = [matches objectAtIndex:0];
  for (i = 1; i < [matches count]; i++)
    common = [common commonPrefixWithString:[matches objectAtIndex:i]
                                    options:NSCaseInsensitiveSearch];
  if ([matches count] == 1)
    common = [common stringByAppendingString:@"/"];
  else
    {
      if ([common length] <= [partial length])
        NSBeep ();
      /* Name the matches here too; the menu lists them all. */
      NSString *list = [[matches subarrayWithRange:NSMakeRange (0, MIN ([matches count], 5))]
          componentsJoinedByString:@", "];
      [self showMessage:[matches count] > 5
                            ? [NSString stringWithFormat:@"%@ and %lu more", list,
                                                         (unsigned long)([matches count] - 5)]
                            : list
                  error:NO];
    }
  [field setStringValue:[head stringByAppendingString:common]];
  [[field currentEditor] setSelectedRange:NSMakeRange ([[field stringValue] length], 0)];
}

- (BOOL)control:(NSControl *)control
               textView:(NSTextView *)textView
    doCommandBySelector:(SEL)command
{
  if (!sel_isEqual (command, @selector (insertTab:)))
    return NO;
  [self complete];
  return YES;
}

- (void)controlTextDidChange:(NSNotification *)note
{
  [problem setStringValue:@""];
}

- (void)comboBoxSelectionDidChange:(NSNotification *)note
{
  [problem setStringValue:@""];
}

- (void)go:(id)sender
{
  NSString *text = [field stringValue];
  NSString *target = [self resolve:text];
  BOOL directory = NO;
  if (![text length])
    return;
  if (![[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&directory])
    {
      NSBeep ();
      [self showMessage:[NSString stringWithFormat:@"The folder “%@” can’t be found.",
                                                   [target lastPathComponent]]
                  error:YES];
      return;
    }
  if (!directory)
    {
      NSBeep ();
      [self showMessage:[NSString stringWithFormat:@"“%@” is a file, not a folder.",
                                                   [target lastPathComponent]]
                  error:YES];
      return;
    }
  RELEASE (destination);
  destination = [target copy];
  /* Remember the folder, under ~ when in the home folder, most recent first. */
  text = [target stringByAbbreviatingWithTildeInPath];
  NSMutableArray *recents = [NSMutableArray arrayWithObject:text];
  NSArray *old = [[NSUserDefaults standardUserDefaults] arrayForKey:FVGoRecentsKey];
  NSUInteger i;
  for (i = 0; i < [old count] && [recents count] < 10; i++)
    if (![[old objectAtIndex:i] isEqual:text])
      [recents addObject:[old objectAtIndex:i]];
  [[NSUserDefaults standardUserDefaults] setObject:recents forKey:FVGoRecentsKey];
  [NSApp stopModalWithCode:0];
}

- (void)cancel:(id)sender
{
  [NSApp stopModalWithCode:1];
}

- (NSInteger)run
{
  [panel center];
  [panel makeKeyAndOrderFront:nil];
  [panel makeFirstResponder:field];
  [field selectText:nil];
  return FVRunModalPanel (panel);
}

- (NSString *)destination
{
  return destination;
}

- (void)dealloc
{
  [field setDelegate:nil];
  RELEASE (panel);
  RELEASE (field);
  RELEASE (problem);
  RELEASE (base);
  RELEASE (destination);
  DEALLOC;
}

@end

NSInteger
FVRunAlert (NSString *title, NSString *heading, NSString *message, NSString *defaultButton,
            NSString *alternateButton)
{
  NSPanel *panel = NSGetAlertPanel (heading, @"%@", defaultButton, alternateButton, nil, message);
  [panel setTitle:title];
  NSInteger result = [NSApp runModalForWindow:panel];
  [panel orderOut:nil];
  NSReleaseAlertPanel (panel);
  return result;
}

static NSString *const FVInvalidNameMessage
    = @"A name can’t be empty, contain “/”, or be “.” or “..”.";

@interface FVSidebarView : NSOutlineView

@end

@implementation FVSidebarView

- (NSMenu *)menuForEvent:(NSEvent *)event
{
  NSInteger row = [self rowAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
  if (row < 0)
    return nil;
  NSDictionary *item = [self itemAtRow:row];
  if (![[item objectForKey:@"group"] isEqual:@"favorite"])
    return nil;
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Favorites"]);
  NSMenuItem *remove = AUTORELEASE ([[NSMenuItem alloc] initWithTitle:@"Remove from Favorites"
                                                action:@selector (removeFavorite:)
                                         keyEquivalent:@""]);
  [remove setTarget:[self target]];
  [remove setRepresentedObject:[item objectForKey:@"path"]];
  [menu addItem:remove];
  return menu;
}

@end

/* Keep file-selection gestures consistent despite the native table and
   matrix controls using different modifier conventions. */
static NSEvent *
FVSelectionEvent (NSEvent *event, NSUInteger modifiers)
{
  return [NSEvent mouseEventWithType:[event type] location:[event locationInWindow]
      modifierFlags:modifiers timestamp:[event timestamp] windowNumber:[event windowNumber]
      context:[event context] eventNumber:[event eventNumber]
      clickCount:[event clickCount] pressure:[event pressure]];
}

/* Delay before a slow second click on a selected name starts renaming; a
   quicker second click is a double-click and opens the item instead. */
static const NSTimeInterval FVSlowClickDelay = .7;

static BOOL
FVPlainClick (NSEvent *event)
{
  return [event clickCount] == 1
         && !([event modifierFlags]
              & (NSShiftKeyMask | NSControlKeyMask | NSCommandKeyMask | NSAlternateKeyMask));
}

/* After a click's tracking loop: the button came up where it went down. */
static BOOL
FVClickStayedPut (NSEvent *down)
{
  NSEvent *up = [NSApp currentEvent];
  return [up type] == NSLeftMouseUp
         && fabs ([up locationInWindow].x - [down locationInWindow].x) < 4
         && fabs ([up locationInWindow].y - [down locationInWindow].y) < 4;
}

@interface FVTableView : NSTableView
{
  NSMutableString *typed;
  NSTimeInterval lastTyped;
}

- (void)updateFileTooltips;

@end

@implementation FVTableView

- (void)mouseDown:(NSEvent *)event
{
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  NSInteger row = [self rowAtPoint:point];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  BOOL slowClick = row >= 0 && FVPlainClick (event) && [self numberOfSelectedRows] == 1
                   && [self isRowSelected:row]
                   && [self columnAtPoint:point] == [self columnWithIdentifier:@"name"];
  NSUInteger modifiers = [event modifierFlags];
  if (modifiers & NSShiftKeyMask)
    event = FVSelectionEvent (event,
        (modifiers & ~(NSShiftKeyMask | NSCommandKeyMask)) | NSControlKeyMask);
  else if (modifiers & (NSCommandKeyMask | NSControlKeyMask))
    event = FVSelectionEvent (event,
        (modifiers & ~(NSCommandKeyMask | NSControlKeyMask)) | NSShiftKeyMask);
  /* GNUstep only initiates drags for rows selected before mouseDown. */
  if (row >= 0 && ![self isRowSelected:row]
      && !(modifiers & (NSShiftKeyMask | NSControlKeyMask | NSCommandKeyMask)))
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
  [super mouseDown:event];
  if (slowClick && FVClickStayedPut (event))
    [self performSelector:@selector (renameAfterSlowClick:)
               withObject:[NSNumber numberWithInteger:row]
               afterDelay:FVSlowClickDelay];
}

- (void)renameAfterSlowClick:(NSNumber *)row
{
  if ([self numberOfSelectedRows] == 1 && [self isRowSelected:[row integerValue]]
      && [[self window] firstResponder] == self)
    [NSApp sendAction:@selector (rename:) to:[self target] from:self];
}

- (void)updateFileTooltips
{
  [self removeAllToolTips];
  if (!FVFilenameTooltipsEnabled ())
    return;
  NSInteger row;
  for (row = 0; row < [self numberOfRows]; row++)
    [self addToolTipRect:[self rectOfRow:row] owner:self userData:NULL];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point userData:(void *)data
{
  NSInteger row = [self rowAtPoint:point];
  if (!FVFilenameTooltipsEnabled () || row < 0 || row >= [self numberOfRows])
    return nil;
  return [[self dataSource] tableView:self
      objectValueForTableColumn:[self tableColumnWithIdentifier:@"name"] row:row];
}

- (void)reloadData
{
  [super reloadData];
  [self updateFileTooltips];
}

- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize:size];
  [self updateFileTooltips];
}

- (void)keyDown:(NSEvent *)event
{
  NSString *text = [event charactersIgnoringModifiers];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  if ([text isEqual:@"\r"])
    {
      [NSApp sendAction:[self numberOfSelectedRows] == 1 ? @selector (rename:)
                                                         : [self doubleAction]
                     to:[self target]
                   from:self];
      return;
    }
  if ([text length] && [text characterAtIndex:0] >= 32 && [text characterAtIndex:0] < 0xf700
      && !([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask)))
    {
      if (!typed)
        typed = [[NSMutableString alloc] init];
      if ([event timestamp] - lastTyped > 1)
        [typed setString:@""];
      lastTyped = [event timestamp];
      [typed appendString:text];
      NSInteger i;
      for (i = 0; i < [self numberOfRows]; i++)
        {
          NSString *name = [[self dataSource] tableView:self
                              objectValueForTableColumn:[[self tableColumns] objectAtIndex:0]
                                                    row:i];
          if ([name rangeOfString:typed options:NSCaseInsensitiveSearch | NSAnchoredSearch].location
              == 0)
            {
              [self selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
              [self scrollRowToVisible:i];
              break;
            }
        }
      return;
    }
  [super keyDown:event];
}

- (void)dealloc
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  RELEASE (typed);
  DEALLOC;
}

@end

/* GNUstep 0.32 implements browser drop delegates but does not initiate a
   file drag through writeRowsWithIndexes. Keep native matrix click handling
   and add only the missing drag initiation. */
@interface FVBrowserMatrix : NSMatrix

- (void)updateFileTooltips;

@end

@implementation FVBrowserMatrix

- (void)updateFileTooltips
{
  [self removeAllToolTips];
  if (!FVFilenameTooltipsEnabled ())
    return;
  NSInteger row;
  for (row = 0; row < [self numberOfRows]; row++)
    [self addToolTipRect:[self cellFrameAtRow:row column:0] owner:self userData:NULL];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point userData:(void *)data
{
  NSInteger row, column;
  if (!FVFilenameTooltipsEnabled () || ![self getRow:&row column:&column forPoint:point])
    return nil;
  return [[[self cellAtRow:row column:column] representedObject] lastPathComponent];
}

- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize:size];
  [self updateFileTooltips];
}

- (void)keyDown:(NSEvent *)event
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  if ([[event charactersIgnoringModifiers] isEqual:@"\r"] && [[self selectedCells] count] == 1)
    {
      [NSApp sendAction:@selector (rename:) to:nil from:self];
      return;
    }
  [super keyDown:event];
}

- (void)renameAfterSlowClick:(id)cell
{
  NSArray *cells = [self selectedCells];
  if ([cells count] == 1 && [cells objectAtIndex:0] == cell
      && [[self window] firstResponder] == self)
    [NSApp sendAction:@selector (rename:) to:nil from:self];
}

- (void)dealloc
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  DEALLOC;
}

- (void)mouseDown:(NSEvent *)event
{
  NSInteger row, column;
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  if (![self getRow:&row column:&column forPoint:point])
    {
      [super mouseDown:event];
      return;
    }
  NSEvent *next;
  for (;;)
    {
      next = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask | NSLeftMouseUpMask
                                             untilDate:[NSDate distantFuture]
                                                inMode:NSEventTrackingRunLoopMode
                                               dequeue:NO];
      if ([next type] != NSLeftMouseDragged)
        break;
      NSPoint location = [next locationInWindow];
      NSPoint origin = [event locationInWindow];
      if (fabs (location.x - origin.x) >= 5 || fabs (location.y - origin.y) >= 5)
        break;
      /* Discard click jitter, leaving mouse-up queued for native selection. */
      [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask
                                untilDate:[NSDate distantFuture]
                                   inMode:NSEventTrackingRunLoopMode
                                  dequeue:YES];
    }
  if ([next type] != NSLeftMouseDragged)
    {
      id clicked = [self cellAtRow:row column:column];
      BOOL slowClick = FVPlainClick (event) && [[self selectedCells] count] == 1
                       && [[self selectedCells] objectAtIndex:0] == clicked;
      NSUInteger modifiers = [event modifierFlags];
      if (modifiers & NSShiftKeyMask)
        event = FVSelectionEvent (event,
            (modifiers & ~(NSShiftKeyMask | NSControlKeyMask | NSCommandKeyMask))
                | NSAlternateKeyMask);
      else if (modifiers & (NSControlKeyMask | NSCommandKeyMask))
        event = FVSelectionEvent (event,
            (modifiers & ~(NSControlKeyMask | NSCommandKeyMask | NSAlternateKeyMask))
                | NSShiftKeyMask);
      [super mouseDown:event];
      if (slowClick && FVClickStayedPut (event))
        [self performSelector:@selector (renameAfterSlowClick:)
                   withObject:clicked
                   afterDelay:FVSlowClickDelay];
      return;
    }
  id cell = [self cellAtRow:row column:column];
  if (![[self selectedCells] containsObject:cell])
    {
      [self deselectAllCells];
      [self selectCellAtRow:row column:column];
    }
  [self sendAction:[self action] to:[self target]];
  NSMutableArray *paths = [NSMutableArray array];
  NSArray *cells = [self selectedCells];
  NSUInteger i;
  for (i = 0; i < [cells count]; i++)
    {
      id p = [[cells objectAtIndex:i] representedObject];
      if ([p isKindOfClass:[NSString class]])
        [paths addObject:p];
    }
  if (![paths count])
    return;
  NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSDragPboard];
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [pb setPropertyList:paths forType:NSFilenamesPboardType];
  next = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask];
  NSImage *image = AUTORELEASE ([[[NSWorkspace sharedWorkspace]
      iconForFile:[paths objectAtIndex:0]] copy]);
  [image setScalesWhenResized:YES];
  [image setSize:NSMakeSize (48, 48)];
  [self dragImage:image
               at:point
           offset:NSZeroSize
            event:next
       pasteboard:pb
           source:self
        slideBack:YES];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local
{
  return NSDragOperationCopy;
}

@end

@interface FVMediaBrowserCell : NSBrowserCell
{
  FVWindow *owner;
}

- (void)setOwner:(FVWindow *)controller;

@end

@implementation FVMediaBrowserCell

- (NSAttributedString *)attributedStringValue
{
  NSMutableAttributedString *text = AUTORELEASE ([[super attributedStringValue] mutableCopy]);
  [text addAttribute:NSForegroundColorAttributeName
      value:([self isHighlighted] || [self state]) ? [NSColor selectedControlTextColor]
                                                 : FVViewerTextColor ()
      range:NSMakeRange (0, [text length])];
  return text;
}

- (void)setOwner:(FVWindow *)controller
{
  owner = controller;
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
  NSImage *image = AUTORELEASE ([[owner iconForPath:[self representedObject]] copy]);
  NSSize size = [image size];
  if (size.width > 0 && size.height > 0)
    {
      CGFloat scale = MIN (18 / size.width, 18 / size.height);
      [image setSize:NSMakeSize (size.width * scale, size.height * scale)];
    }
  [self setImage:image];
  [super drawInteriorWithFrame:frame inView:view];
}

@end

@interface FVNameCell : NSTextFieldCell

@end

@implementation FVNameCell

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
  NSImage *image = [self image];
  NSRect text = frame;
  if (image)
    {
      text.origin.x += 23;
      text.size.width -= 23;
    }
  [super drawWithFrame:text inView:view];
  NSSize size = [image size];
  CGFloat scale = size.width > 0 && size.height > 0
                      ? MIN (18 / size.width, 18 / size.height) : 1;
  [image drawInRect:NSMakeRect (frame.origin.x + 2 + (18 - size.width * scale) / 2,
                               frame.origin.y + 1 + (18 - size.height * scale) / 2,
                               size.width * scale, size.height * scale)
            fromRect:NSZeroRect
           operation:NSCompositeSourceOver
            fraction:1
      respectFlipped:YES
               hints:nil];
}

@end

@implementation FVWindow

- (id)initWithPath:(NSString *)value
{
  NSWindow *window =
      [[NSWindow alloc] initWithContentRect:NSMakeRect (120, 120, 980, 640)
                                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                                            | NSMiniaturizableWindowMask | NSResizableWindowMask
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  self = [super initWithWindow:window];
  RELEASE (window);
  if (self)
    {
      [window setDelegate:self];
      [window setMinSize:NSMakeSize (760, 400)];
      [window setFrameAutosaveName:@"File Viewer"];
      cutChangeCount = -1;
      items = [[NSMutableArray alloc] init];
      history = [[NSMutableArray alloc] init];
      historyIndex = -1;
      ascending = YES;
      foldersFirst = ![[NSUserDefaults standardUserDefaults] boolForKey:@"FilesBeforeFolders"];
      sortKey = [@"name" copy];
      errors = [[NSMutableArray alloc] init];
      iconCache = [[NSMutableDictionary alloc] init];
      thumbnailCache = [[NSCache alloc] init];
      [thumbnailCache setCountLimit:256];
      thumbnailRequests = [[NSMutableSet alloc] init];
      thumbnailQueue = [[NSOperationQueue alloc] init];
      [thumbnailQueue setMaxConcurrentOperationCount:2];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (thumbnailPreferencesChanged:)
              name:@"FVThumbnailPreferencesChanged" object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (recentsChanged:) name:@"FVRecentsChanged" object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (filenameTooltipsChanged:) name:@"FVFilenameTooltipsChanged" object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (locationPreferencesChanged:) name:@"FVLocationPreferencesChanged" object:nil];
      browserRows = [[NSMutableDictionary alloc] init];
      hidden = [[NSUserDefaults standardUserDefaults] boolForKey:@"Hidden"];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (hiddenFilesPreferencesChanged:) name:@"FVHiddenFilesChanged" object:nil];
      NSView *content = [window contentView];
      /* Autosave restoration may have changed the content size already. */
      NSSize contentSize = [content bounds].size;
      NSView *bar = AUTORELEASE ([[NSView alloc]
          initWithFrame:NSMakeRect (8, contentSize.height - 40, contentSize.width - 16, 32)]);
      [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
      [content addSubview:bar];
      FVToolbarButton (bar, @"Back", @selector (back:), self, 0, 0);
      FVToolbarButton (bar, @"Forward", @selector (forward:), self, 38, 1);
      FVToolbarButton (bar, @"Up", @selector (parent:), self, 76, 2);
      FVToolbarButton (bar, @"Home", @selector (home:), self, 114, 3);
      FVToolbarButton (bar, @"Refresh", @selector (refresh:), self, 152, 4);
      FVToolbarButton (bar, @"List", @selector (listMode:), self, 204, 5);
      FVToolbarButton (bar, @"Columns", @selector (columnMode:), self, 242, 6);
      FVToolbarButton (bar, @"Icons", @selector (iconMode:), self, 280, 7);
      /* One search field: it filters this folder, or with Subfolders chosen
         searches beneath it by name. */
      filter = [[NSSearchField alloc]
          initWithFrame:NSMakeRect (332, 2, contentSize.width - 358 - 132, 26)];
      [filter setAutoresizingMask:NSViewWidthSizable];
      [filter setTarget:self];
      [filter setAction:@selector (filterChanged:)];
      [filter setDelegate:self];
      [[filter cell] setPlaceholderString:@"Search"];
      [filter setToolTip:@"Type part of a name. Escape clears the search."];
      [bar addSubview:filter];
      searchScope = [[NSPopUpButton alloc]
          initWithFrame:NSMakeRect (contentSize.width - 16 - 128, 2, 120, 26)
                  pullsDown:NO];
      [searchScope addItemWithTitle:@"This Folder"];
      [searchScope addItemWithTitle:@"Subfolders"];
      [searchScope setToolTip:@"Search only this folder, or this folder and all its subfolders"];
      [searchScope setAutoresizingMask:NSViewMinXMargin];
      [searchScope setTarget:self];
      [searchScope setAction:@selector (filterChanged:)];
      [bar addSubview:searchScope];
      modeBeforeSearch = -1;
      breadcrumbs = [[NSPopUpButton alloc]
          initWithFrame:NSMakeRect (180, contentSize.height - 78, contentSize.width - 190, 30)
                                               pullsDown:NO];
      [breadcrumbs setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
      [breadcrumbs setTarget:self];
      [breadcrumbs setAction:@selector (breadcrumb:)];
      [content addSubview:breadcrumbs];
      host = [[NSView alloc]
          initWithFrame:NSMakeRect (180, 34, contentSize.width - 190, contentSize.height - 120)];
      [host setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [content addSubview:host];
      scroll = [[NSScrollView alloc] initWithFrame:[host bounds]];
      [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [scroll setHasVerticalScroller:YES];
      [scroll setHasHorizontalScroller:YES];
      table = [[FVTableView alloc] initWithFrame:[host bounds]];
      [table setGridStyleMask:NSTableViewGridNone];
      [table setAllowsMultipleSelection:YES];
      [table setVerticalMotionCanBeginDrag:YES];
      [table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
      [table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
      [table setRowHeight:MAX (22, [NSFont systemFontSize] + 7)];
      [table setDataSource:self];
      [table setDelegate:self];
      [table setTarget:self];
      [table setDoubleAction:@selector (open:)];
      NSArray *keys = [NSArray
          arrayWithObjects:@"name", @"size", @"kind", @"date", nil];
      NSArray *titles = [NSArray arrayWithObjects:@"Name", @"Size (bytes)", @"Kind", @"Modified", nil];
      NSUInteger i;
      for (i = 0; i < [keys count]; i++)
        {
          NSTableColumn *column =
              AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:[keys objectAtIndex:i]]);
          [[column headerCell] setStringValue:[titles objectAtIndex:i]];
          NSString *key = [keys objectAtIndex:i];
          [column setWidth:[key isEqual:@"name"] ? 250
              : ([key isEqual:@"date"] ? 210 : 110)];
          /* NSTableColumn is editable by default, and a double-click on an
             editable column starts editing instead of sending the double
             action, so nothing opened unless Return was pressed. */
          [column setEditable:NO];
          [[column dataCell] setEditable:NO];
          [[column dataCell] setSelectable:NO];
          [[column dataCell] setBordered:NO];
          if (i == 0)
            {
              FVNameCell *cell = AUTORELEASE ([[FVNameCell alloc] initTextCell:@""]);
              [cell setEditable:NO];
              [cell setSelectable:NO];
              [cell setBordered:NO];
              [column setDataCell:cell];
            }
          [table addTableColumn:column];
        }
      /* Shown only with search results: the folder each one is in. */
      locationColumn = [[NSTableColumn alloc] initWithIdentifier:@"location"];
      [[locationColumn headerCell] setStringValue:@"Location"];
      [locationColumn setWidth:260];
      [locationColumn setEditable:NO];
      [[locationColumn dataCell] setEditable:NO];
      [[locationColumn dataCell] setSelectable:NO];
      [[locationColumn dataCell] setBordered:NO];
      [[locationColumn dataCell] setLineBreakMode:NSLineBreakByTruncatingHead];
      [scroll setDocumentView:table];
      [host addSubview:scroll];
      NSScrollView *sideScroll =
          AUTORELEASE ([[NSScrollView alloc]
              initWithFrame:NSMakeRect (8, 34, 164, contentSize.height - 82)]);
      [sideScroll setAutoresizingMask:NSViewHeightSizable];
      [sideScroll setHasVerticalScroller:YES];
      sidebar = [[FVSidebarView alloc] initWithFrame:[sideScroll bounds]];
      [sidebar setGridStyleMask:NSTableViewGridNone];
      [sidebar setRowHeight:MAX (22, [NSFont systemFontSize] + 7)];
      NSTableColumn *sideColumn = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"place"]);
      [sideColumn setWidth:158];
      [[sideColumn headerCell] setStringValue:@"Locations"];
      [sideColumn setDataCell:AUTORELEASE ([[FVNameCell alloc] initTextCell:@""])];
      [[sideColumn dataCell] setEditable:NO];
      [[sideColumn dataCell] setBordered:NO];
      [sidebar addTableColumn:sideColumn];
      [sidebar setOutlineTableColumn:sideColumn];
      [sidebar setIndentationPerLevel:12];
      [sidebar setDataSource:self];
      [sidebar setDelegate:self];
      [sidebar setTarget:self];
      [sidebar setAction:@selector (sidebarClicked:)];
      [sidebar registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
      [sideScroll setDocumentView:sidebar];
      [content addSubview:sideScroll];
      status = RETAIN (FVLabel (NSMakeRect (10, 5, contentSize.width - 260, 24), @"Loading…"));
      [status setAutoresizingMask:NSViewWidthSizable];
      [[status cell] setLineBreakMode:NSLineBreakByTruncatingTail];
      [content addSubview:status];
      activityStatus = RETAIN (FVLabel (NSMakeRect (contentSize.width - 240, 5, 230, 24), @""));
      [activityStatus setAlignment:NSRightTextAlignment];
      [activityStatus setAutoresizingMask:NSViewMinXMargin];
      [[activityStatus cell] setLineBreakMode:NSLineBreakByTruncatingTail];
      [content addSubview:activityStatus];
      [table registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (appearancePreferencesChanged:) name:@"FVAppearancePreferencesChanged"
          object:nil];
      [self appearancePreferencesChanged:nil];
      [self rebuildPlaces];
      [self navigate:value];
      NSInteger savedMode = [[NSUserDefaults standardUserDefaults] integerForKey:@"ViewMode"];
      if (savedMode == 1)
        [self columnMode:nil];
      else if (savedMode == 2)
        [self iconMode:nil];
      monitor = RETAIN ([NSTimer scheduledTimerWithTimeInterval:1
                                                  target:self
                                                selector:@selector (checkDirectory:)
                                                userInfo:nil
                                                 repeats:YES]);
    }
  return self;
}

- (void)appearancePreferencesChanged:(NSNotification *)notification
{
  NSColor *color = FVViewerBackgroundColor ();
  [scroll setBackgroundColor:color];
  [[scroll contentView] setBackgroundColor:color];
  [table setBackgroundColor:color];
  NSEnumerator *columns = [[table tableColumns] objectEnumerator];
  NSTableColumn *column;
  while ((column = [columns nextObject]))
    [(NSTextFieldCell *)[column dataCell] setTextColor:FVViewerTextColor ()];
  [table setNeedsDisplay:YES];
  [icons setNeedsDisplay:YES];
  NSInteger i;
  for (i = 0; browser && i <= [browser lastColumn]; i++)
    {
      NSMatrix *matrix = [browser matrixInColumn:i];
      [matrix setBackgroundColor:color];
      [[matrix enclosingScrollView] setBackgroundColor:color];
      [[[matrix enclosingScrollView] contentView] setBackgroundColor:color];
      [matrix setNeedsDisplay:YES];
    }
  [browser tile];
  [browser setNeedsDisplay:YES];
}

- (void)locationPreferencesChanged:(NSNotification *)notification
{
  [self rebuildPlaces];
}

- (void)rebuildPlaces
{
  NSMutableArray *p = [NSMutableArray arrayWithObject:NSHomeDirectory ()];
  NSArray *names = [NSArray arrayWithObjects:@"Desktop", @"Documents", @"Downloads",
                                             @"Images", @"Music", @"Videos", nil];
  NSArray *images = [NSArray arrayWithObjects:@"Desktop", @"DocsFolder", @"DownloadFolder",
                                              @"ImageFolder", @"MusicFolder", @"VideoFolder", nil];
  if (!placeIcons)
    placeIcons = [[NSMutableDictionary alloc] init];
  [placeIcons removeAllObjects];
  [placeIcons setObject:@"HomeDirectory" forKey:NSHomeDirectory ()];
  NSUInteger i;
  for (i = 0; i < [names count]; i++)
    {
      NSString *candidate =
          [NSHomeDirectory () stringByAppendingPathComponent:[names objectAtIndex:i]];
      NSString *configRoot =
          [[[NSProcessInfo processInfo] environment] objectForKey:@"XDG_CONFIG_HOME"];
      if (![configRoot isAbsolutePath])
        configRoot = [NSHomeDirectory () stringByAppendingPathComponent:@".config"];
      NSString *config = [NSString
          stringWithContentsOfFile:[configRoot stringByAppendingPathComponent:@"user-dirs.dirs"]
                          encoding:NSUTF8StringEncoding
                             error:NULL];
      NSArray *lines = [config componentsSeparatedByString:@"\n"];
      NSUInteger line;
      NSString *key = [NSString
          stringWithFormat:@"XDG_%@_DIR=\"", [([[names objectAtIndex:i] isEqual:@"Downloads"]
                                                   ? @"DOWNLOAD"
                                                   : [[names objectAtIndex:i] isEqual:@"Images"]
                                                   ? @"PICTURES"
                                                   : [names objectAtIndex:i]) uppercaseString]];
      for (line = 0; line < [lines count]; line++)
        {
          NSString *entry = [lines objectAtIndex:line];
          if ([entry hasPrefix:key] && [entry hasSuffix:@"\""])
            {
              NSString *configured = [[entry
                  substringWithRange:NSMakeRange ([key length], [entry length] - [key length] - 1)]
                  stringByReplacingOccurrencesOfString:@"$HOME"
                                            withString:NSHomeDirectory ()];
              if ([configured isAbsolutePath])
                candidate = configured;
            }
        }
      BOOL dir;
      if ([[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&dir] && dir)
        {
          if (![p containsObject:candidate])
            [p addObject:candidate];
          if (![placeIcons objectForKey:candidate])
            [placeIcons setObject:[images objectAtIndex:i] forKey:candidate];
        }
    }
  NSArray *allNetworkPaths = [FVMounts networkPaths];
  NSArray *allLocalPaths = [[NSWorkspace sharedWorkspace] mountedLocalVolumePaths];
  NSMutableSet *allMounts = [NSMutableSet setWithArray:allLocalPaths];
  [allMounts addObjectsFromArray:allNetworkPaths];
  NSArray *rootVolumes = FVVolumesInMountRoots ();
  [allMounts addObjectsFromArray:rootVolumes];
  ASSIGNCOPY (mountedVolumePaths, allMounts);
  NSArray *networkPaths = FVVisibleLocationPaths (allNetworkPaths);
  NSMutableArray *mounted = [NSMutableArray array];
  NSMutableSet *mountedPaths = [NSMutableSet set];
  NSMutableArray *volumeCandidates = [NSMutableArray arrayWithArray:rootVolumes];
  [volumeCandidates addObjectsFromArray:networkPaths];
  NSArray *volumes = FVVisibleLocationPaths (volumeCandidates);
  for (i = 0; i < [volumes count]; i++)
    {
      NSString *volume = [volumes objectAtIndex:i];
      if (![mountedPaths containsObject:volume])
        {
          [mountedPaths addObject:volume];
          [mounted addObject:[NSDictionary dictionaryWithObjectsAndKeys:
              volume, @"path", @"mounted", @"group", nil]];
        }
    }
  NSString *trash = [[FVOperations homeTrash] stringByAppendingPathComponent:@"files"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:trash])
    [p addObject:trash];
  [p removeObjectsInArray:[mountedPaths allObjects]];
  [p removeObjectsInArray:networkPaths];
  [p setArray:FVVisibleLocationPaths (p)];
  NSMutableArray *common = [NSMutableArray array];
  for (i = 0; i < [p count]; i++)
    [common addObject:[NSDictionary dictionaryWithObjectsAndKeys:
        [p objectAtIndex:i], @"path", @"common", @"group", nil]];
  NSString *applications = [NSHomeDirectory () stringByAppendingPathComponent:@"Applications"];
  BOOL isDirectory = NO;
  if ([[NSFileManager defaultManager] fileExistsAtPath:applications isDirectory:&isDirectory]
      && isDirectory && ![p containsObject:applications])
    [common insertObject:[NSDictionary dictionaryWithObjectsAndKeys:
        applications, @"path", @"common", @"group", nil] atIndex:MIN (1, [common count])];
  NSMutableArray *domains = [NSMutableArray array];
  NSArray *domainPaths = [NSArray arrayWithObjects:@"/Local", @"/Network", @"/System", nil];
  for (i = 0; i < [domainPaths count]; i++)
    if (FVRootHasFolder ([[domainPaths objectAtIndex:i] lastPathComponent]))
      [domains addObject:[NSDictionary dictionaryWithObjectsAndKeys:
          [domainPaths objectAtIndex:i], @"path", @"domain", @"group", nil]];
  NSString *home = NSHomeDirectory ();
  NSString *userTitle = ([home isEqual:@"/Network"] || [home hasPrefix:@"/Network/"])
      ? @"Network User" : @"Local User";
  NSMutableDictionary *volumesGroup = [NSMutableDictionary dictionaryWithObjectsAndKeys:
      @"Volumes", @"title", mounted, @"children", nil];
  if (FVRootHasFolder (@"Volumes"))
    [volumesGroup setObject:@"/Volumes" forKey:@"path"];
  BOOL initial = places == nil;
  BOOL commonExpanded = initial || [sidebar isItemExpanded:[places objectAtIndex:0]];
  BOOL domainsExpanded = initial || [sidebar isItemExpanded:[places objectAtIndex:1]];
  BOOL volumesExpanded = initial || [sidebar isItemExpanded:[places objectAtIndex:2]];
  RELEASE (places);
  places = [[NSArray alloc] initWithObjects:
      [NSDictionary dictionaryWithObjectsAndKeys:userTitle, @"title",
                                                 common, @"children", nil],
      [NSDictionary dictionaryWithObjectsAndKeys:@"Domains", @"title",
                                                 domains, @"children", nil],
      volumesGroup, nil];
  [sidebar reloadData];
  if (commonExpanded)
    [sidebar expandItem:[places objectAtIndex:0]];
  if (domainsExpanded)
    [sidebar expandItem:[places objectAtIndex:1]];
  if (volumesExpanded)
    [sidebar expandItem:[places objectAtIndex:2]];
  [self redrawThumbnails];
}

- (void)navigate:(NSString *)value
{
  BOOL recents = [value isEqual:FVRecentsLocation];
  value = [value stringByExpandingTildeInPath];
  if (!recents && ![value isAbsolutePath])
    value = [path ? path : NSHomeDirectory () stringByAppendingPathComponent:value];
  if (![value isEqual:path])
    {
      while ((NSInteger)[history count] > historyIndex + 1)
        [history removeLastObject];
      [history addObject:value];
      historyIndex = [history count] - 1;
    }
  if (![value isEqual:path])
    {
      RELEASE (revealPath);
      revealPath = nil;
    }
  if (searching && ![value isEqual:path])
    {
      [filter setStringValue:@""];
      [self showSearchResults:NO];
    }
  NSString *newPath = [value copy];
  RELEASE (path);
  path = newPath;
  searching = NO;
  [searchScope setEnabled:!recents];
  [browserRows removeAllObjects];
  [[NSUserDefaults standardUserDefaults] setObject:path forKey:@"LastPath"];
  /* Every viewer is titled File Viewer, as on NeXTSTEP; the path bar shows where it is. */
  [[self window] setTitle:@"File Viewer"];
  [breadcrumbs removeAllItems];
  [[[table tableColumnWithIdentifier:@"date"] headerCell]
      setStringValue:recents ? @"Last Accessed" : @"Modified"];
  if (recents)
    {
      [breadcrumbs addItemWithTitle:@"Recents"];
      RELEASE (sortKey);
      sortKey = [@"date" copy];
      ascending = NO;
      [table moveColumn:[table columnWithIdentifier:@"date"] toColumn:1];
      [table moveColumn:[table columnWithIdentifier:@"path"] toColumn:2];
      if (mode == 1)
        [self listMode:nil];
      RELEASE (spaceDescription);
      spaceDescription = nil;
      [self refresh:nil];
      return;
    }
  [table moveColumn:[table columnWithIdentifier:@"path"] toColumn:[[table tableColumns] count] - 1];
  [table moveColumn:[table columnWithIdentifier:@"date"] toColumn:3];
  NSString *part = path;
  while ([part length])
    {
      [breadcrumbs addItemWithTitle:part];
      if ([part isEqual:@"/"])
        break;
      NSString *next = [part stringByDeletingLastPathComponent];
      if ([next isEqual:part])
        break;
      part = next;
    }
  [self refresh:nil];
}

- (void)recentsChanged:(NSNotification *)notification
{
  if (!closed && [path isEqual:FVRecentsLocation])
    [self refresh:nil];
}

- (void)refresh:(id)sender
{
  [self endEditingName:NO];
  [self invalidateThumbnails];
  NSMutableDictionary *columns = [NSMutableDictionary dictionary];
  NSInteger column;
  for (column = 0; mode == 1 && column <= [browser lastColumn]; column++)
    {
      NSString *folder = [self browserFolder:column];
      if (!folder)
        continue;
      NSMutableArray *selected = [NSMutableArray array];
      NSArray *cells = [[browser matrixInColumn:column] selectedCells];
      NSUInteger i;
      for (i = 0; i < [cells count]; i++)
        {
          id value = [[cells objectAtIndex:i] representedObject];
          if (value)
            [selected addObject:value];
        }
      [columns setObject:selected forKey:folder];
    }
  NSArray *selection = [self selectedPaths];
  if (revealPath)
    {
      selection = [NSArray arrayWithObject:revealPath];
      [columns setObject:selection forKey:[revealPath stringByDeletingLastPathComponent]];
    }
  RELEASE (savedBrowserSelection);
  savedBrowserSelection = [columns copy];
  RELEASE (savedSelection);
  savedSelection = [selection copy];
  savedScroll = [[scroll contentView] bounds].origin;
  [listing cancel];
  RELEASE (listing);
  generation++;
  pendingBrowserLoads = 0;
  [items removeAllObjects];
  [browserRows removeAllObjects];
  [errors removeAllObjects];
  [table reloadData];
  loading = YES;
  [self updateActivity];
  [status setStringValue:searching ? [@"Searching filenames beneath " stringByAppendingString:path]
                                   : @"Loading…"];
  listing = [[FVListing alloc] initWithPath:path
                                      query:[filter stringValue]
                                     hidden:hidden
                                  recursive:searching
                                 generation:generation
                                     target:self];
  [listing start];
}

- (void)listingResult:(NSDictionary *)result
{
  if (closed || [[result objectForKey:@"generation"] unsignedIntegerValue] != generation)
    return;
  [items addObjectsFromArray:[result objectForKey:@"items"]];
  [errors addObjectsFromArray:[result objectForKey:@"errors"]];
  loading = ![[result objectForKey:@"done"] boolValue];
  [self updateActivity];
  if (!loading)
    {
      [self sortItems];
      RELEASE (listing);
      listing = nil;
    }
  [table reloadData];
  [icons reload];
  [status setToolTip:[errors componentsJoinedByString:@"\n"]];
  if (!loading)
    {
      [iconCache removeAllObjects];
      NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
      NSUInteger i;
      for (i = 0; i < [items count]; i++)
        if ([savedSelection containsObject:[[items objectAtIndex:i] path]])
          [indices addIndex:i];
      [table selectRowIndexes:indices byExtendingSelection:NO];
      [icons setSelection:indices];
      [[scroll contentView] scrollToPoint:savedScroll];
      [scroll reflectScrolledClipView:[scroll contentView]];
      [browser loadColumnZero];
      [self restoreBrowserColumn:0];
      [self checkDirectory:nil];
      [self showRevealedItem];
    }
  [status
      setStringValue:[NSString
                         stringWithFormat:@"%lu items%@%@", (unsigned long)[items count],
                                          loading ? @" • loading" : @"",
                                          [errors count]
                                              ? [@" • " stringByAppendingString:
                                                            [errors componentsJoinedByString:@"; "]]
                                              : @""]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)sender
{
  return [items count];
}

- (id)tableView:(NSTableView *)sender
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  FVItem *item = [items objectAtIndex:row];
  if ([[column identifier] isEqual:@"location"])
    {
      /* Relative to the search root, which is named first: "t/dest/Project". */
      NSString *folder = [[item path] stringByDeletingLastPathComponent];
      NSString *root = [path isEqual:@"/"] ? @"" : path;
      if ([folder isEqual:path])
        return [path lastPathComponent];
      if ([folder hasPrefix:[root stringByAppendingString:@"/"]])
        return [[path lastPathComponent]
            stringByAppendingPathComponent:[folder substringFromIndex:[root length] + 1]];
      return folder;
    }
  return [item valueForColumn:[column identifier]];
}

- (NSInteger)outlineView:(NSOutlineView *)sender numberOfChildrenOfItem:(id)item
{
  return item ? [[item objectForKey:@"children"] count] : [places count];
}

- (id)outlineView:(NSOutlineView *)sender child:(NSInteger)index ofItem:(id)item
{
  return [(item ? [item objectForKey:@"children"] : places) objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)sender isItemExpandable:(id)item
{
  return [item objectForKey:@"children"] != nil;
}

- (BOOL)outlineView:(NSOutlineView *)sender shouldSelectItem:(id)item
{
  return [item objectForKey:@"path"] != nil;
}

- (id)outlineView:(NSOutlineView *)sender
    objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
  NSString *p = [item objectForKey:@"path"];
  if (!p)
    return [item objectForKey:@"title"];
  if ([p isEqual:FVRecentsLocation])
    return @"Recents";
  if ([p isEqual:NSHomeDirectory ()])
    return NSUserName ();
  if ([p isEqual:[[FVOperations homeTrash] stringByAppendingPathComponent:@"files"]])
    return @"Trash";
  return [p lastPathComponent];
}

- (void)outlineView:(NSOutlineView *)sender willDisplayCell:(id)cell
    forTableColumn:(NSTableColumn *)column item:(id)item
{
  NSString *p = [item objectForKey:@"path"];
  NSString *name = p ? [placeIcons objectForKey:p] : nil;
  NSImage *image = name ? [NSImage imageNamed:name] : nil;
  if ([item objectForKey:@"children"])
    {
      [cell setImage:nil];
      return;
    }
  if ([[item objectForKey:@"group"] isEqual:@"mounted"]
      || [mountedVolumePaths containsObject:p])
    {
      /* Do not contact a possibly disconnected server just to draw its icon. */
      [cell setImage:[NSImage imageNamed:@"HardDisk"]];
      return;
    }
  if ([p isEqual:FVRecentsLocation])
    {
      [cell setImage:FVToolbarImage (4)];
      return;
    }
  [cell setImage:p ? (image ? image : [self iconForPath:p]) : nil];
}

- (NSArray *)favoritePathsFromPasteboard:(NSPasteboard *)pasteboard
{
  id values = [pasteboard propertyListForType:NSFilenamesPboardType];
  if (![values isKindOfClass:[NSArray class]] || ![values count])
    return nil;
  NSUInteger i;
  for (i = 0; i < [values count]; i++)
    {
      id value = [values objectAtIndex:i];
      if (![value isKindOfClass:[NSString class]] || ![value isAbsolutePath]
          || ![[NSFileManager defaultManager] fileExistsAtPath:value])
        return nil;
    }
  return values;
}

- (BOOL)canCopyToLocation:(id)item
{
  NSString *destination = [item objectForKey:@"path"];
  BOOL directory = NO;
  return !operation && destination && ![destination isEqual:FVRecentsLocation]
      && [[NSFileManager defaultManager] fileExistsAtPath:destination isDirectory:&directory]
      && directory;
}

- (NSDragOperation)outlineView:(NSOutlineView *)sender
    validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item
    proposedChildIndex:(NSInteger)index
{
  if (![self favoritePathsFromPasteboard:[info draggingPasteboard]])
    return NSDragOperationNone;
  if ([item objectForKey:@"path"])
    {
      if (![self canCopyToLocation:item])
        return NSDragOperationNone;
      [sender setDropItem:item dropChildIndex:NSOutlineViewDropOnItemIndex];
      return NSDragOperationCopy;
    }
  return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)sender acceptDrop:(id<NSDraggingInfo>)info
    item:(id)item childIndex:(NSInteger)index
{
  NSArray *paths = [self favoritePathsFromPasteboard:[info draggingPasteboard]];
  if (!paths)
    return NO;
  if ([item objectForKey:@"path"])
    {
      if (![self canCopyToLocation:item])
        return NO;
      [self runOperation:@"copy" paths:paths destination:[item objectForKey:@"path"]];
      return YES;
    }
  return NO;
}

- (NSArray *)items
{
  return items;
}

- (NSArray *)selectedPaths
{
  NSMutableArray *result = [NSMutableArray array];
  if (mode == 1 && [browser selectedColumn] >= 0)
    {
      NSArray *cells = [browser selectedCells];
      NSUInteger j;
      for (j = 0; j < [cells count]; j++)
        {
          id p = [[cells objectAtIndex:j] representedObject];
          if ([p isKindOfClass:[NSString class]])
            [result addObject:p];
        }
      return result;
    }
  NSIndexSet *selection = mode == 2 ? [icons selection] : [table selectedRowIndexes];
  NSUInteger index = [selection firstIndex];
  while (index != NSNotFound)
    {
      if (index < [items count])
        [result addObject:[[items objectAtIndex:index] path]];
      index = [selection indexGreaterThanIndex:index];
    }
  return result;
}

- (void)open:(id)sender
{
  NSArray *selected = [self selectedPaths];
  NSUInteger i;
  for (i = 0; i < [selected count]; i++)
    {
      NSString *p = [selected objectAtIndex:i];
      FVItem *item = [FVItem itemAtPath:p];
      if ([item directory] && ![[NSWorkspace sharedWorkspace] isFilePackageAtPath:p])
        {
          [self navigate:p];
          break;
        }
      [self openPath:p];
    }
}

- (void)openPath:(NSString *)value
{
  if ([value isEqual:FVRecentsLocation])
    {
      [self navigate:value];
      return;
    }
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  BOOL directory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:value isDirectory:&directory])
    {
      FVRunAlert (@"Open", @"Can’t Open",
                  [NSString stringWithFormat:@"“%@” can’t be opened because it no longer exists.",
                                             [value lastPathComponent]],
                  @"OK", nil);
      return;
    }
  NSString *extension = [[value pathExtension] lowercaseString];
  BOOL application = directory && ([extension isEqual:@"app"] || [extension isEqual:@"debug"]
                                    || [extension isEqual:@"profile"]);
  if (application)
    {
      [self launchApplication:value file:nil];
      return;
    }
  if (directory && ![workspace isFilePackageAtPath:value])
    {
      [self navigate:value];
      return;
    }
  NSString *app = [FVLauncher defaultApplicationForFile:value];
  if (!app)
    {
      NSArray *applications = [FVLauncher applicationsForFile:value];
      app = [applications count] == 1 ? [applications objectAtIndex:0]
                                     : [self chooseApplicationForFile:value];
    }
  if (app)
    [self launchApplication:app file:value];
}

- (NSString *)chooseApplicationForFile:(NSString *)value
{
  FVDialog *dialog = AUTORELEASE ([[FVDialog alloc]
      initWithApplications:[FVLauncher applicationsForFile:value] file:value]);
  if ([self runDialog:dialog] != 0)
    return nil;
  NSString *app = [dialog selectedApplication];
  if (app && [dialog apply])
    [FVLauncher setDefaultApplication:app forFile:value];
  return app;
}

- (void)launchApplication:(NSString *)application file:(NSString *)value
{
  pendingLaunches++;
  [self updateActivity];
  [activityStatus displayIfNeeded];
  [status setStringValue:[NSString stringWithFormat:@"Opening %@…",
      [(value ? value : application) lastPathComponent]]];
  [FVLauncher launchApplication:application file:value
               completionTarget:self selector:@selector (launchFinished:)];
}

- (void)launchFinished:(NSDictionary *)result
{
  if (pendingLaunches)
    pendingLaunches--;
  [self updateActivity];
  if ([[result objectForKey:@"success"] boolValue])
    [FVRecents recordPath:[result objectForKey:@"path"]];
  if (closed)
    return;
  if ([[result objectForKey:@"success"] boolValue])
    [self selectionChanged];
  else
    [status setStringValue:[NSString stringWithFormat:@"Cannot open %@ with %@.",
        [result objectForKey:@"path"], [result objectForKey:@"application"]]];
}

- (void)sidebarClicked:(id)sender
{
  if ([sidebar selectedRow] >= 0)
    {
      NSString *p = [[sidebar itemAtRow:[sidebar selectedRow]] objectForKey:@"path"];
      if (p)
        [self openPath:p];
    }
}

- (void)breadcrumb:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  [self navigate:[breadcrumbs titleOfSelectedItem]];
}

- (void)home:(id)sender
{
  [self navigate:NSHomeDirectory ()];
}

- (void)parent:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  [self navigate:[path stringByDeletingLastPathComponent]];
}

- (void)back:(id)sender
{
  if (historyIndex > 0)
    {
      historyIndex--;
      NSString *p = RETAIN ([history objectAtIndex:historyIndex]);
      RELEASE (path);
      path = [p copy];
      [self navigate:p];
      RELEASE (p);
    }
}

- (void)forward:(id)sender
{
  if (historyIndex + 1 < (NSInteger)[history count])
    {
      historyIndex++;
      NSString *p = RETAIN ([history objectAtIndex:historyIndex]);
      RELEASE (path);
      path = [p copy];
      [self navigate:p];
      RELEASE (p);
    }
}

/* The search field filters this folder by name, or with Subfolders chosen
   searches beneath it, showing results in the list with their location. */
- (void)filterChanged:(id)sender
{
  BOOL deep = [searchScope indexOfSelectedItem] == 1 && [[filter stringValue] length]
              && ![path isEqual:FVRecentsLocation];
  [self showSearchResults:deep];
  [self refresh:nil];
}

- (void)showSearchResults:(BOOL)deep
{
  searching = deep;
  BOOL shown = [[table tableColumns] containsObject:locationColumn];
  if (deep && !shown)
    {
      [table addTableColumn:locationColumn];
      [table moveColumn:[table columnWithIdentifier:@"location"] toColumn:1];
      if (mode != 0)
        {
          modeBeforeSearch = mode;
          [self listMode:nil];
          [[self window] makeFirstResponder:filter];
        }
    }
  else if (!deep && shown)
    {
      [table removeTableColumn:locationColumn];
      if (modeBeforeSearch == 1)
        [self columnMode:nil];
      else if (modeBeforeSearch == 2)
        [self iconMode:nil];
      modeBeforeSearch = -1;
    }
}

/* Escape in the search field clears it and returns to the folder. */
- (void)clearSearch
{
  [filter setStringValue:@""];
  [self filterChanged:filter];
}

- (void)toggleHidden:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setBool:!hidden forKey:@"Hidden"];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"FVHiddenFilesChanged" object:self];
}

- (void)hiddenFilesPreferencesChanged:(NSNotification *)notification
{
  BOOL show = [[NSUserDefaults standardUserDefaults] boolForKey:@"Hidden"];
  if (hidden != show)
    {
      hidden = show;
      [self refresh:nil];
    }
}

- (void)windowDidBecomeKey:(NSNotification *)note
{
  [[FVInspector sharedInspector] viewerSelectionChanged:self];
}

- (void)windowWillClose:(NSNotification *)note
{
  [self endEditingName:NO];
  closed = YES;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self invalidateThumbnails];
  [[FVInspector sharedInspector] viewerClosed:self];
  [listing cancel];
  RELEASE (listing);
  listing = nil;
  [operation cancel];
  [monitor invalidate];
  [(FVApplication *)[NSApp delegate] performSelector:@selector (viewerClosed:)
                                          withObject:self
                                          afterDelay:0];
}

- (void)sortItems
{
  NSDictionary *options = [NSDictionary
      dictionaryWithObjectsAndKeys:sortKey, @"key", [NSNumber numberWithBool:ascending],
                                   @"ascending", [NSNumber numberWithBool:foldersFirst], @"folders",
                                   nil];
  [items sortUsingFunction:FVCompare context:options];
}

- (void)tableView:(NSTableView *)sender didClickTableColumn:(NSTableColumn *)column
{
  if (sender != table)
    return;
  if ([sortKey isEqual:[column identifier]])
    ascending = !ascending;
  else
    {
      RELEASE (sortKey);
      sortKey = [[column identifier] copy];
      ascending = YES;
    }
  NSArray *selected = [[self selectedPaths] copy];
  [self sortItems];
  [table reloadData];
  NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
  NSUInteger i;
  for (i = 0; i < [items count]; i++)
    if ([selected containsObject:[[items objectAtIndex:i] path]])
      [indices addIndex:i];
  [table selectRowIndexes:indices byExtendingSelection:NO];
  RELEASE (selected);
}

- (void)toggleFolders:(id)sender
{
  foldersFirst = !foldersFirst;
  [[NSUserDefaults standardUserDefaults] setBool:!foldersFirst forKey:@"FilesBeforeFolders"];
  [self sortItems];
  [table reloadData];
  [icons reload];
}

- (void)selectionChanged
{
  [[FVInspector sharedInspector] viewerSelectionChanged:self];
  if (operation || [errors count])
    return;
  [status setStringValue:[NSString stringWithFormat:@"%lu items • %lu selected%@%@",
                                                    (unsigned long)[items count],
                                                    (unsigned long)[[self selectedPaths] count],
                                                    spaceDescription ? spaceDescription : @"",
                                                    searching ? [@" • Search root: "
                                                                    stringByAppendingString:path]
                                                              : @""]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  if ([note object] == table)
    [self selectionChanged];
}

- (void)updateActivity
{
  if (closed)
    return;
  /* Show nothing while idle. */
  NSString *message = @"";
  if (waitingForInput)
    message = @"Waiting for input…";
  else if (pendingLaunches)
    message = @"Launching application…";
  else if (operation)
    message = operationActivity ? operationActivity : @"Working…";
  else if (loading || pendingBrowserLoads)
    message = searching ? @"Searching…" : @"Loading…";
  else if (pendingThumbnails)
    message = @"Generating thumbnails…";
  if (![[activityStatus stringValue] isEqual:message])
    {
      [activityStatus setStringValue:message];
      [activityStatus setToolTip:[message length] ? message : nil];
    }
}

/* Runs an FVDialog or FVGoPanel, showing "Waiting for input…" meanwhile. */
- (NSInteger)runDialog:(id<FVModalDialog>)dialog
{
  waitingForInput = YES;
  [self updateActivity];
  [activityStatus displayIfNeeded];
  NSInteger result;
  @try
    {
      result = [dialog run];
    }
  @finally
    {
      waitingForInput = NO;
      [self updateActivity];
    }
  return result;
}

- (NSImage *)iconForPath:(NSString *)value
{
  if (!value)
    return nil;
  if ([FVStandardizedPath (value) isEqual:@"/"])
    {
      NSImage *rootIcon = [NSImage imageNamed:@"Root_PC"];
      return rootIcon ? rootIcon : [NSImage imageNamed:@"common_Root_PC"];
    }
  if ([value isEqual:@"/Local"] || [value isEqual:@"/Network"])
    {
      NSImage *domainIcon = [NSImage imageNamed:[value isEqual:@"/Local"]
          ? @"common_LocalFolder" : @"common_NetworkFolder"];
      if (!domainIcon)
        domainIcon = [NSImage imageNamed:@"common_GSFolder"];
      if (domainIcon)
        return domainIcon;
    }
  if ([mountedVolumePaths containsObject:FVStandardizedPath (value)])
    return [NSImage imageNamed:@"HardDisk"];
  if ([FVThumbnailOperation enabled] && [FVThumbnailOperation supportsPath:value])
    {
      NSImage *preview = [thumbnailCache objectForKey:value];
      if (preview)
        return preview;
      if (!closed && ![thumbnailRequests containsObject:value])
        {
          [thumbnailRequests addObject:value];
          pendingThumbnails++;
          [self updateActivity];
          FVThumbnailOperation *job = [[FVThumbnailOperation alloc]
              initWithPath:value generation:thumbnailGeneration target:self];
          [thumbnailQueue addOperation:job];
          RELEASE (job);
        }
    }
  NSImage *image = [iconCache objectForKey:value];
  if (!image)
    {
      if ([iconCache count] >= 256)
        [iconCache removeAllObjects];
      image = [[NSWorkspace sharedWorkspace] iconForFile:value];
      if (image)
        [iconCache setObject:image forKey:value];
    }
  return image;
}

- (void)invalidateThumbnails
{
  thumbnailGeneration++;
  [thumbnailQueue cancelAllOperations];
  [thumbnailCache removeAllObjects];
  [thumbnailRequests removeAllObjects];
  pendingThumbnails = 0;
  [self updateActivity];
}

- (void)thumbnailPreferencesChanged:(NSNotification *)notification
{
  [self invalidateThumbnails];
  [self redrawThumbnails];
}

- (void)filenameTooltipsChanged:(NSNotification *)notification
{
  [(FVTableView *)table updateFileTooltips];
  [icons updateFileTooltips];
  NSInteger column;
  for (column = 0; browser && column <= [browser lastColumn]; column++)
    [(FVBrowserMatrix *)[browser matrixInColumn:column] updateFileTooltips];
}

- (void)redrawThumbnails
{
  [table setNeedsDisplay:YES];
  [icons setNeedsDisplay:YES];
  NSInteger column;
  for (column = 0; browser && column <= [browser lastColumn]; column++)
    [[browser matrixInColumn:column] setNeedsDisplay:YES];
}

- (void)thumbnailLoaded:(NSDictionary *)result
{
  if (closed || ![FVThumbnailOperation enabled]
      || [[result objectForKey:@"generation"] unsignedIntegerValue] != thumbnailGeneration)
    return;
  if (pendingThumbnails)
    pendingThumbnails--;
  [self updateActivity];
  NSData *data = [result objectForKey:@"data"];
  NSImage *preview = data ? AUTORELEASE ([[NSImage alloc] initWithData:data]) : nil;
  if (preview && [preview isValid])
    {
      NSString *file = [result objectForKey:@"path"];
      [thumbnailCache setObject:preview forKey:file];
      [thumbnailRequests removeObject:file];
      [self redrawThumbnails];
    }
}

- (void)tableView:(NSTableView *)sender
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
                row:(NSInteger)row
{
  if (sender == table && [[column identifier] isEqual:@"name"])
    [cell setImage:[self iconForPath:[[items objectAtIndex:row] path]]];
}

- (void)go:(id)sender
{
  [self endEditingName:YES];
  FVGoPanel *panel = AUTORELEASE ([[FVGoPanel alloc]
      initWithFolder:[path isEqual:FVRecentsLocation] ? NSHomeDirectory () : path]);
  if ([self runDialog:panel] == 0 && [panel destination])
    [self navigate:[panel destination]];
}

- (void)openWith:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if (![selected count])
    return;
  NSUInteger i;
  for (i = 0; i < [selected count]; i++)
    {
      NSString *value = [selected objectAtIndex:i];
      NSString *app = [self chooseApplicationForFile:value];
      if (!app)
        break;
      [self launchApplication:app file:value];
    }
}

- (void)resetOpenWith:(id)sender
{
  NSArray *selected = [self selectedPaths];
  NSUInteger i;
  for (i = 0; i < [selected count]; i++)
    [FVLauncher setDefaultApplication:nil forFile:[selected objectAtIndex:i]];
  [status setStringValue:@"Saved Open With choices cleared for the selected file types."];
}

/* New Folder makes "New Folder" (or "New Folder 2"…) at once in the folder the
   view shows, selects it and starts editing its name in place. */
- (void)newFolder:(id)sender
{
  if ([path isEqual:FVRecentsLocation] || operation)
    return;
  [self endEditingName:YES];
  NSString *folder = mode == 1 && browser ? [self browserFolder:[browser lastColumn]] : path;
  if (!folder)
    folder = path;
  NSString *target = [folder stringByAppendingPathComponent:@"New Folder"];
  NSUInteger n = 2;
  struct stat st;
  while (lstat ([target fileSystemRepresentation], &st) == 0)
    target = [folder stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"New Folder %lu", (unsigned long)n++]];
  RELEASE (revealPath);
  revealPath = [target copy];
  editRevealed = YES;
  [self runOperation:@"mkdir" paths:[NSArray arrayWithObject:target] destination:nil];
}

/* Inline name editing lays one text field over the item's name in whichever
   view shows it: a list row, a browser cell or an icon label. */
- (NSView *)nameViewForPath:(NSString *)value rect:(NSRect *)rect
{
  if (mode == 1)
    {
      NSInteger column;
      for (column = 0; browser && column <= [browser lastColumn]; column++)
        {
          NSMatrix *matrix = [browser matrixInColumn:column];
          NSInteger row;
          for (row = 0; matrix && row < [matrix numberOfRows]; row++)
            if ([[[matrix cellAtRow:row column:0] representedObject] isEqual:value])
              {
                NSRect cell = [matrix cellFrameAtRow:row column:0];
                *rect = NSMakeRect (NSMinX (cell) + 22, NSMinY (cell) - 1, NSWidth (cell) - 40,
                                    NSHeight (cell) + 2);
                return matrix;
              }
        }
      return nil;
    }
  NSUInteger i;
  for (i = 0; i < [items count]; i++)
    if ([[[items objectAtIndex:i] path] isEqual:value])
      break;
  if (i == [items count])
    return nil;
  if (mode == 2)
    {
      *rect = [icons labelRectForIndex:i];
      return icons;
    }
  NSRect cell = [table frameOfCellAtColumn:[table columnWithIdentifier:@"name"] row:i];
  *rect = NSMakeRect (NSMinX (cell) + 21, NSMinY (cell) - 1, NSWidth (cell) - 21,
                      NSHeight (cell) + 2);
  return table;
}

- (void)beginEditingName:(NSString *)value
{
  [self endEditingName:NO];
  NSRect rect;
  NSView *view = [self nameViewForPath:value rect:&rect];
  if (!view)
    return;
  [view scrollRectToVisible:rect];
  if (!nameEditor)
    {
      nameEditor = [[NSTextField alloc] initWithFrame:rect];
      [nameEditor setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
      [nameEditor setDelegate:self];
    }
  [nameEditor setFrame:rect];
  NSString *name = [value lastPathComponent];
  [nameEditor setStringValue:name];
  editingPath = [value copy];
  [view addSubview:nameEditor];
  [[self window] makeFirstResponder:nameEditor];
  /* Select the name without its extension, as Finder does for files. */
  NSUInteger length = [name length];
  NSString *base = [name stringByDeletingPathExtension];
  if (![[FVItem itemAtPath:value] directory] && [[name pathExtension] length] && [base length])
    length = [base length];
  [[nameEditor currentEditor] setSelectedRange:NSMakeRange (0, length)];
}

/* Return: rename unless the name is invalid or taken, which is refused in
   place with the editor left open. */
- (BOOL)commitNameEdit
{
  if (!editingPath)
    return YES;
  NSString *source = AUTORELEASE ([editingPath copy]);
  NSString *name = [nameEditor stringValue];
  if ([name isEqual:[source lastPathComponent]])
    {
      [self endEditingName:YES];
      return YES;
    }
  NSString *problem = [self renameProblem:source toName:name];
  if (problem)
    {
      NSBeep ();
      [status setStringValue:problem];
      return NO;
    }
  [self endEditingName:YES];
  [self renamePath:source toName:name];
  return YES;
}

/* Why an item can't take this name now, or nil. */
- (NSString *)renameProblem:(NSString *)source toName:(NSString *)name
{
  NSString *dest = [[source stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
  struct stat a, b;
  if (![FVOperations validName:name])
    return FVInvalidNameMessage;
  if (lstat ([dest fileSystemRepresentation], &b) == 0
      && (lstat ([source fileSystemRepresentation], &a) || a.st_dev != b.st_dev
          || a.st_ino != b.st_ino))
    return [NSString stringWithFormat:@"The name “%@” is already taken. Choose a different name.",
                                      name];
  if (operation)
    return @"Wait for the current operation to finish, then press Return again.";
  return nil;
}

- (NSString *)renamePath:(NSString *)source toName:(NSString *)name
{
  if ([name isEqual:[source lastPathComponent]])
    return nil;
  NSString *problem = [self renameProblem:source toName:name];
  if (problem)
    return problem;
  NSString *dest = [[source stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
  RELEASE (revealPath);
  revealPath = [dest copy];
  editRevealed = NO;
  [self runOperation:@"rename" paths:[NSArray arrayWithObject:source] destination:dest];
  return nil;
}

- (NSString *)currentPath
{
  return path;
}

/* Escape ends editing without renaming; a new folder keeps its default name. */
- (void)endEditingName:(BOOL)refocus
{
  if (!editingPath)
    return;
  NSView *view = [nameEditor superview];
  RELEASE (editingPath);
  editingPath = nil;
  if (refocus && view)
    [[self window] makeFirstResponder:view];
  [nameEditor abortEditing];
  [nameEditor removeFromSuperview];
  [view setNeedsDisplay:YES];
  [self selectionChanged];
}

- (BOOL)control:(NSControl *)control
               textView:(NSTextView *)textView
    doCommandBySelector:(SEL)command
{
  if (control == filter)
    {
      if ((sel_isEqual (command, @selector (cancelOperation:))
           || sel_isEqual (command, @selector (complete:)))
          && [[filter stringValue] length])
        {
          [self clearSearch];
          return YES;
        }
      return NO;
    }
  if (control != nameEditor || !editingPath)
    return NO;
  /* Compare by name: libobjc2 selectors can carry differing type encodings. */
  if (sel_isEqual (command, @selector (insertNewline:)))
    {
      [self commitNameEdit];
      return YES;
    }
  /* GNUstep binds Escape to complete:. */
  if (sel_isEqual (command, @selector (cancelOperation:))
      || sel_isEqual (command, @selector (complete:)))
    {
      [self endEditingName:YES];
      return YES;
    }
  return NO;
}

/* Return (which GNUstep's field editor turns into the end of editing) and
   clicking elsewhere commit. A refused name keeps the editor open after
   Return and is dropped after a click elsewhere. */
- (void)controlTextDidEndEditing:(NSNotification *)note
{
  if ([note object] != nameEditor || !editingPath || [self commitNameEdit])
    return;
  if ([[[note userInfo] objectForKey:@"NSTextMovement"] integerValue] == NSReturnTextMovement)
    [self performSelector:@selector (resumeEditingName) withObject:nil afterDelay:0];
  else
    [self endEditingName:NO];
}

- (void)resumeEditingName
{
  if (!editingPath || ![nameEditor superview])
    return;
  [[self window] makeFirstResponder:nameEditor];
  [[nameEditor currentEditor] selectAll:nil];
}

/* After a refresh, select the item just created or renamed, and edit a new
   folder's name once its row, cell or icon exists. */
- (void)showRevealedItem
{
  NSRect rect;
  if (!revealPath || operation || ![self nameViewForPath:revealPath rect:&rect])
    return;
  NSString *value = AUTORELEASE (revealPath);
  revealPath = nil;
  if (mode == 1)
    {
      NSView *matrix = [self nameViewForPath:value rect:&rect];
      [[self window] makeFirstResponder:matrix];
    }
  if (editRevealed)
    {
      editRevealed = NO;
      [self beginEditingName:value];
    }
}

/* Rename edits the selected item's name in place. Return on a single
   selected item and a slow second click on its name start it too. */
- (void)rename:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if ([selected count] != 1 || operation)
    return;
  [self beginEditingName:[selected objectAtIndex:0]];
}

/* File → Get Info opens the Inspector, which then follows the selection. */
- (void)info:(id)sender
{
  [[FVInspector sharedInspector] showForViewer:self];
}

- (void)openNewWindow:(id)sender
{
  NSArray *selected = [self selectedPaths];
  [(FVApplication *)[NSApp delegate] openPath:[selected count] ? [selected objectAtIndex:0] : path];
}

- (void)packageContents:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if ([selected count] == 1)
    [self navigate:[selected objectAtIndex:0]];
}

- (void)addFavorite:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  NSMutableArray *favorites = [NSMutableArray
      arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"]
                         ? [[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"]
                         : [NSArray array]];
  if (![favorites containsObject:path])
    [favorites addObject:path];
  [[NSUserDefaults standardUserDefaults] setObject:favorites forKey:@"Favorites"];
  [self rebuildPlaces];
}

- (void)removeFavorite:(id)sender
{
  NSMutableArray *favorites = [NSMutableArray
      arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"]
                         ? [[NSUserDefaults standardUserDefaults] arrayForKey:@"Favorites"]
                         : [NSArray array]];
  NSString *selected = [sidebar selectedRow] >= 0
                           ? [[sidebar itemAtRow:[sidebar selectedRow]] objectForKey:@"path"] : nil;
  if ([sender isKindOfClass:[NSMenuItem class]]
      && [[sender representedObject] isKindOfClass:[NSString class]])
    [favorites removeObject:[sender representedObject]];
  else
    [favorites removeObject:selected && [favorites containsObject:selected] ? selected : path];
  [[NSUserDefaults standardUserDefaults] setObject:favorites forKey:@"Favorites"];
  [self rebuildPlaces];
}

- (void)copy:(id)sender
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [pb setPropertyList:[self selectedPaths] forType:NSFilenamesPboardType];
}

- (void)cut:(id)sender
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:[NSArray
                       arrayWithObjects:NSFilenamesPboardType, @"org.nextbsd.Workspace.cut", nil]
             owner:nil];
  [pb setPropertyList:[self selectedPaths] forType:NSFilenamesPboardType];
  [pb setString:@"move" forType:@"org.nextbsd.Workspace.cut"];
  [status setStringValue:@"Cut: files remain in place until a successful Paste move"];
}

- (void)paste:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  NSArray *paths = [pb propertyListForType:NSFilenamesPboardType];
  if (operation)
    return;
  cutChangeCount =
      [[pb types] containsObject:@"org.nextbsd.Workspace.cut"] ? [pb changeCount] : -1;
  [self runOperation:[[pb types] containsObject:@"org.nextbsd.Workspace.cut"] ? @"move" : @"copy"
               paths:paths
         destination:path];
}

- (void)copyPath:(id)sender
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
  NSArray *selected = [self selectedPaths];
  if (![selected count] && [path isEqual:FVRecentsLocation])
    return;
  [pb setString:[selected count] ? [selected componentsJoinedByString:@"\n"] : path
        forType:NSStringPboardType];
}

- (void)duplicate:(id)sender
{
  [self runOperation:@"duplicate" paths:[self selectedPaths] destination:path];
}

/* Move To… picks the destination with a folder chooser that starts in the
   folder holding the selection. */
- (void)moveTo:(id)sender
{
  NSArray *selected = [self selectedPaths];
  if (![selected count] || operation)
    return;
  [self endEditingName:YES];
  NSOpenPanel *chooser = [NSOpenPanel openPanel];
  [chooser setTitle:@"Move To"];
  /* GNUstep's prompt labels the path field; name the OK button "Move". */
  [chooser setNameFieldLabel:@"Folder:"];
  @try
    {
      [[chooser valueForKey:@"_okButton"] setTitle:@"Move"];
    }
  @catch (NSException *exception)
    {
    }
  [chooser setCanChooseDirectories:YES];
  [chooser setCanChooseFiles:NO];
  [chooser setAllowsMultipleSelection:NO];
  [chooser setCanCreateDirectories:YES];
  waitingForInput = YES;
  [self updateActivity];
  [activityStatus displayIfNeeded];
  NSInteger result;
  @try
    {
      result = [chooser runModalForDirectory:[[selected objectAtIndex:0]
                                                 stringByDeletingLastPathComponent]
                                        file:nil
                                       types:nil];
    }
  @finally
    {
      waitingForInput = NO;
      [self updateActivity];
    }
  if (result == NSOKButton && [chooser filename])
    [self runOperation:@"move" paths:selected destination:[chooser filename]];
}

- (void)trash:(id)sender
{
  [self runOperation:@"trash" paths:[self selectedPaths] destination:nil];
}

- (void)deletePermanently:(id)sender
{
  NSArray *selected = [self selectedPaths];
  NSUInteger count = [selected count];
  if (!count)
    return;
  NSString *heading, *message = @"This can’t be undone.";
  if (count == 1)
    heading = [NSString stringWithFormat:@"Delete “%@” permanently?",
                                         [[selected objectAtIndex:0] lastPathComponent]];
  else
    {
      heading = [NSString stringWithFormat:@"Delete %lu items permanently?", (unsigned long)count];
      NSMutableArray *names = [NSMutableArray array];
      NSUInteger i, shown = count > 8 ? 7 : count;
      for (i = 0; i < shown; i++)
        [names addObject:[[selected objectAtIndex:i] lastPathComponent]];
      if (shown < count)
        [names addObject:[NSString stringWithFormat:@"and %lu more", (unsigned long)(count - shown)]];
      message = [NSString stringWithFormat:@"%@\n\n%@", message,
                                           [names componentsJoinedByString:@"\n"]];
    }
  /* Cancel stays the default button. */
  if (FVRunAlert (@"Delete Permanently", heading, message, @"Cancel", @"Delete")
      == NSAlertAlternateReturn)
    [self runOperation:@"delete" paths:selected destination:nil];
}

- (void)runOperation:(NSString *)kind paths:(NSArray *)sources destination:(NSString *)destination
{
  if ([path isEqual:FVRecentsLocation]
      && ([kind isEqual:@"mkdir"] || [kind isEqual:@"duplicate"]
          || (([kind isEqual:@"copy"] || [kind isEqual:@"move"])
              && (!destination || [destination isEqual:FVRecentsLocation]))))
    return;
  if (operation || ![sources isKindOfClass:[NSArray class]] || ![sources count])
    return;
  NSUInteger sourceIndex;
  for (sourceIndex = 0; sourceIndex < [sources count]; sourceIndex++)
    {
      id source = [sources objectAtIndex:sourceIndex];
      if (![source isKindOfClass:[NSString class]] || ![source isAbsolutePath])
        {
          FVRunAlert (@"Workspace", @"Can’t Paste", @"The copied items can’t be pasted here.",
                      @"OK", nil);
          return;
        }
    }
  operation = [[FVOperations alloc] initWithKind:kind
                                         sources:sources
                                     destination:destination ? destination : path
                                          target:self];
  NSDictionary *activities = [NSDictionary dictionaryWithObjectsAndKeys:
      @"Copying…", @"copy", @"Moving…", @"move", @"Deleting…", @"delete",
      @"Duplicating…", @"duplicate",
      @"Moving to Trash…", @"trash", @"Renaming…", @"rename",
      @"Creating folder…", @"mkdir", nil];
  RELEASE (operationActivity);
  operationActivity = [[activities objectForKey:kind] copy];
  [self updateActivity];
  [[FVProgressPanel sharedPanel] beginOperation:operation
                                           kind:kind
                                        sources:sources
                                    destination:destination ? destination : path
                                          owner:self];
  [operation start];
}

/* The progress window shows how far along the operation is; the status
   line names the item being handled. */
- (void)operationProgress:(NSDictionary *)progress
{
  if (![progress isKindOfClass:[NSDictionary class]]
      || [progress objectForKey:@"operation"] != operation)
    return;
  [[FVProgressPanel sharedPanel] updateOperation:operation progress:progress];
  if (closed || [operationActivity isEqual:@"Stopping…"])
    return;
  NSUInteger count = [[progress objectForKey:@"count"] unsignedIntegerValue];
  NSString *name = [progress objectForKey:@"name"];
  NSString *activity = [operationActivity hasSuffix:@"…"]
      ? [operationActivity substringToIndex:[operationActivity length] - 1] : operationActivity;
  if ([[progress objectForKey:@"preparing"] boolValue])
    [status setStringValue:[NSString stringWithFormat:@"Counting “%@”…", name]];
  else if ([name length])
    [status setStringValue:count > 1
        ? [NSString stringWithFormat:@"%@ “%@” (%lu of %lu)…", activity, name,
              (unsigned long)[[progress objectForKey:@"index"] unsignedIntegerValue] + 1,
              (unsigned long)count]
        : [NSString stringWithFormat:@"%@ “%@”…", activity, name]];
}

/* The progress window's Stop button. */
- (void)stopOperation:(id)sender
{
  if (!operation)
    return;
  [operation cancel];
  [[FVProgressPanel sharedPanel] operationStopping:operation];
  RELEASE (operationActivity);
  operationActivity = [@"Stopping…" copy];
  [self updateActivity];
  [status setStringValue:@"Stopping; items already finished stay where they are."];
}

- (void)operationFinished:(NSDictionary *)result
{
  [[FVProgressPanel sharedPanel] endOperation:operation];
  RELEASE (operation);
  operation = nil;
  RELEASE (operationActivity);
  operationActivity = nil;
  [self updateActivity];
  RELEASE (undoRecords);
  undoRecords = [[result objectForKey:@"undo"] copy];
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  if (cutChangeCount >= 0 && [pb changeCount] == cutChangeCount)
    {
      NSMutableArray *remaining =
          [NSMutableArray arrayWithArray:[pb propertyListForType:NSFilenamesPboardType]];
      [remaining removeObjectsInArray:[result objectForKey:@"completed"]];
      [pb declareTypes:[remaining count]
                           ? [NSArray arrayWithObjects:NSFilenamesPboardType,
                                                       @"org.nextbsd.Workspace.cut", nil]
                           : [NSArray array]
                 owner:nil];
      if ([remaining count])
        {
          [pb setPropertyList:remaining forType:NSFilenamesPboardType];
          [pb setString:@"move" forType:@"org.nextbsd.Workspace.cut"];
        }
    }
  cutChangeCount = -1;
  if (closed)
    return;
  /* Report before refreshing: a listing can't finish while the alert is modal. */
  [self selectionChanged];
  [[self window] displayIfNeeded];
  [self reportFailures:[result objectForKey:@"failed"]
                 notes:[result objectForKey:@"notes"]
                  kind:[result objectForKey:@"kind"]];
  if (closed)
    return;
  [self rebuildPlaces];
  [self refresh:nil];
}

/* Success is silent. Failures and notes the user must act on get one alert. */
- (void)reportFailures:(NSArray *)failed notes:(NSArray *)notes kind:(NSString *)kind
{
  if (![failed count] && ![notes count])
    return;
  NSDictionary *verbs = [NSDictionary dictionaryWithObjectsAndKeys:
      @"copied", @"copy", @"moved", @"move", @"duplicated", @"duplicate",
      @"moved to the Trash", @"trash", @"deleted", @"delete", @"renamed", @"rename",
      @"created", @"mkdir", @"put back", @"undo", nil];
  NSDictionary *titles = [NSDictionary dictionaryWithObjectsAndKeys:
      @"Copy", @"copy", @"Move", @"move", @"Duplicate", @"duplicate",
      @"Move to Trash", @"trash", @"Delete Permanently", @"delete", @"Rename", @"rename",
      @"New Folder", @"mkdir", @"Undo", @"undo", nil];
  NSString *verb = [verbs objectForKey:kind] ? [verbs objectForKey:kind] : @"handled";
  NSString *title = [titles objectForKey:kind] ? [titles objectForKey:kind] : @"Workspace";
  NSString *heading;
  NSMutableArray *lines = [NSMutableArray array];
  if ([failed count] == 1)
    {
      NSDictionary *failure = [failed objectAtIndex:0];
      heading = [NSString stringWithFormat:@"“%@” couldn’t be %@.",
                                           [[failure objectForKey:@"path"] lastPathComponent],
                                           verb];
      [lines addObject:[failure objectForKey:@"reason"]];
    }
  else if ([failed count])
    {
      heading = [NSString stringWithFormat:@"%lu items couldn’t be %@.",
                                           (unsigned long)[failed count], verb];
      NSUInteger i, shown = [failed count] > 8 ? 7 : [failed count];
      for (i = 0; i < shown; i++)
        {
          NSDictionary *failure = [failed objectAtIndex:i];
          [lines addObject:[NSString stringWithFormat:@"“%@”: %@",
                                                      [[failure objectForKey:@"path"]
                                                          lastPathComponent],
                                                      [failure objectForKey:@"reason"]]];
        }
      if (shown < [failed count])
        [lines addObject:[NSString stringWithFormat:@"and %lu more",
                                                    (unsigned long)([failed count] - shown)]];
    }
  else
    heading = @"Finished, with something to check.";
  NSString *message = [lines componentsJoinedByString:@"\n"];
  if ([notes count])
    message = [[NSArray arrayWithObjects:message, [notes componentsJoinedByString:@"\n\n"], nil]
        componentsJoinedByString:[message length] ? @"\n\n" : @""];
  FVRunAlert (title, heading, message, @"OK", nil);
}

- (void)resolveConflict:(NSMutableDictionary *)request
{
  if (closed)
    {
      [request setObject:@"cancel" forKey:@"choice"];
      return;
    }
  FVConflictPanel *dialog = AUTORELEASE ([[FVConflictPanel alloc]
      initWithSource:[request objectForKey:@"source"]
         destination:[request objectForKey:@"destination"]
                kind:[request objectForKey:@"kind"]
           remaining:[[request objectForKey:@"remaining"] unsignedIntegerValue]]);
  NSInteger choice = [self runDialog:dialog];
  NSArray *choices = [NSArray arrayWithObjects:@"keep", @"skip", @"replace", @"cancel", nil];
  [request setObject:choice >= 0 && choice < 4 ? [choices objectAtIndex:choice] : @"cancel"
              forKey:@"choice"];
  [request setObject:[NSNumber numberWithBool:[dialog applyToAll]] forKey:@"apply"];
}

- (void)undo:(id)sender
{
  if (operation || ![undoRecords count])
    return;
  operation = [[FVOperations alloc] initWithKind:@"undo"
                                         sources:undoRecords
                                     destination:nil
                                          target:self];
  RELEASE (operationActivity);
  operationActivity = [@"Undoing…" copy];
  [self updateActivity];
  [operation start];
}

- (void)cancel:(id)sender
{
  [listing cancel];
  RELEASE (listing);
  listing = nil;
  generation++;
  pendingBrowserLoads = 0;
  loading = NO;
  if (operation)
    {
      [self stopOperation:sender];
      return;
    }
  [self updateActivity];
  [status setStringValue:@"Stopped loading."];
}

- (void)selectAll:(id)sender
{
  if (mode == 2)
    [icons selectAll:sender];
  else if (mode == 1)
    [browser selectAll:sender];
  else
    [table selectAll:sender];
}

- (BOOL)tableView:(NSTableView *)sender
    writeRowsWithIndexes:(NSIndexSet *)indices
            toPasteboard:(NSPasteboard *)pb
{
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i = [indices firstIndex];
  while (i != NSNotFound)
    {
      [paths addObject:[[items objectAtIndex:i] path]];
      i = [indices indexGreaterThanIndex:i];
    }
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  return [pb setPropertyList:paths forType:NSFilenamesPboardType];
}

- (BOOL)allowsFileDrop
{
  return !operation && ![path isEqual:FVRecentsLocation];
}

- (NSDragOperation)tableView:(NSTableView *)sender
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)op
{
  if (![self allowsFileDrop])
    return NSDragOperationNone;
  if (row >= 0 && row < (NSInteger)[items count] && [(FVItem *)[items objectAtIndex:row] directory])
    [table setDropRow:row dropOperation:NSTableViewDropOn];
  else
    [table setDropRow:-1 dropOperation:NSTableViewDropOn];
  return NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)sender
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)op
{
  if (![self allowsFileDrop])
    return NO;
  NSString *dest = row >= 0 && row < (NSInteger)[items count] &&
                           [(FVItem *)[items objectAtIndex:row] directory]
                       ? [[items objectAtIndex:row] path]
                       : path;
  [self runOperation:@"copy"
               paths:[[info draggingPasteboard] propertyListForType:NSFilenamesPboardType]
         destination:dest];
  return YES;
}

- (void)listMode:(id)sender
{
  [self endEditingName:NO];
  if (mode == 2)
    [table selectRowIndexes:[icons selection] byExtendingSelection:NO];
  mode = 0;
  [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"ViewMode"];
  [browser removeFromSuperview];
  [scroll setDocumentView:table];
  [host addSubview:scroll];
  [[self window] makeFirstResponder:table];
}

- (void)iconMode:(id)sender
{
  [self endEditingName:NO];
  NSIndexSet *selected = [table selectedRowIndexes];
  if (!icons)
    icons = [[FVIconView alloc] initWithOwner:self];
  mode = 2;
  [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"ViewMode"];
  [browser removeFromSuperview];
  /* GNUstep may defer releasing the old header clip view. Clear its document
     before moving the header into another clip view on the next list switch. */
  NSView *header = [table headerView];
  NSView *headerClip = [header superview];
  if ([headerClip isKindOfClass:[NSClipView class]]
      && [(NSClipView *)headerClip documentView] == header)
    [(NSClipView *)headerClip setDocumentView:nil];
  [scroll setDocumentView:icons];
  [host addSubview:scroll];
  [icons setSelection:selected];
  [icons reload];
  [[self window] makeFirstResponder:icons];
}

- (void)largerIcons:(id)sender
{
  [icons resizeIcons:16];
}

- (void)smallerIcons:(id)sender
{
  [icons resizeIcons:-16];
}

- (void)columnMode:(id)sender
{
  [self endEditingName:NO];
  if ([path isEqual:FVRecentsLocation])
    {
      [self listMode:nil];
      return;
    }
  if (!browser)
    {
      browser = [[FVBrowser alloc] initWithFrame:[host bounds]];
      [browser setCellClass:[FVMediaBrowserCell class]];
      [browser setMatrixClass:[FVBrowserMatrix class]];
      [browser setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [browser setDelegate:self];
      [browser registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
      [browser setAllowsMultipleSelection:YES];
      [browser setMinColumnWidth:220];
      [browser setTarget:self];
      [browser setAction:@selector (browserSelected:)];
      [browser setDoubleAction:@selector (open:)];
    }
  mode = 1;
  [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"ViewMode"];
  [scroll removeFromSuperview];
  [host addSubview:browser];
  [browser loadColumnZero];
  [[self window] makeFirstResponder:browser];
}

- (NSString *)browserFolder:(NSInteger)column
{
  if ([path isEqual:FVRecentsLocation])
    return nil;
  if (column <= 0)
    return path;
  return [[browser selectedCellInColumn:column - 1] representedObject];
}

- (void)browser:(NSBrowser *)sender
    createRowsForColumn:(NSInteger)column
               inMatrix:(NSMatrix *)matrix
{
  [matrix setBackgroundColor:FVViewerBackgroundColor ()];
  [[matrix enclosingScrollView] setBackgroundColor:FVViewerBackgroundColor ()];
  [[[matrix enclosingScrollView] contentView] setBackgroundColor:FVViewerBackgroundColor ()];
  NSString *folder = [self browserFolder:column];
  if (!folder)
    return;
  NSArray *rows = column == 0 ? items : [browserRows objectForKey:folder];
  if (!rows)
    {
      pendingBrowserLoads++;
      [self updateActivity];
      [browserRows setObject:[NSArray array] forKey:folder];
      NSDictionary *request = [NSDictionary
          dictionaryWithObjectsAndKeys:folder, @"path", [NSNumber numberWithInteger:column],
                                       @"column", [NSNumber numberWithUnsignedInteger:generation],
                                       @"generation", [NSNumber numberWithBool:hidden], @"hidden",
                                       nil];
      [NSThread detachNewThreadSelector:@selector (loadBrowserFolder:)
                               toTarget:self
                             withObject:request];
      return;
    }
  [matrix renewRows:[rows count] columns:1];
  NSUInteger i;
  for (i = 0; i < [rows count]; i++)
    {
      FVItem *item = [rows objectAtIndex:i];
      NSBrowserCell *cell = [matrix cellAtRow:i column:0];
      [(FVMediaBrowserCell *)cell setOwner:self];
      [cell setStringValue:[item name]];
      [cell setRepresentedObject:[item path]];
      [cell setLeaf:![item directory] ||
                    [[NSWorkspace sharedWorkspace] isFilePackageAtPath:[item path]]];
    }
  [(FVBrowserMatrix *)matrix updateFileTooltips];
}

- (void)loadBrowserFolder:(NSDictionary *)request
{
  CREATE_AUTORELEASE_POOL (pool);
  NSError *error = nil;
  NSString *folder = [request objectForKey:@"path"];
  NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:&error];
  NSMutableArray *rows = [NSMutableArray array];
  NSUInteger i;
  for (i = 0; i < [names count]; i++)
    {
      NSString *name = [names objectAtIndex:i];
      if ([[request objectForKey:@"hidden"] boolValue] || ![name hasPrefix:@"."])
        [rows addObject:[FVItem itemAtPath:[folder stringByAppendingPathComponent:name]]];
    }
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:request];
  [result setObject:rows forKey:@"rows"];
  if (error)
    [result setObject:[error localizedDescription] forKey:@"error"];
  [self performSelectorOnMainThread:@selector (browserLoaded:) withObject:result waitUntilDone:NO];
  RELEASE (pool);
}

- (void)browserLoaded:(NSDictionary *)result
{
  if (closed || [[result objectForKey:@"generation"] unsignedIntegerValue] != generation)
    return;
  if (pendingBrowserLoads)
    pendingBrowserLoads--;
  [self updateActivity];
  NSString *folder = [result objectForKey:@"path"];
  NSMutableArray *rows = [NSMutableArray arrayWithArray:[result objectForKey:@"rows"]];
  NSDictionary *options = [NSDictionary
      dictionaryWithObjectsAndKeys:sortKey, @"key", [NSNumber numberWithBool:ascending],
                                   @"ascending", [NSNumber numberWithBool:foldersFirst], @"folders",
                                   nil];
  [rows sortUsingFunction:FVCompare context:options];
  [browserRows setObject:rows forKey:folder];
  NSInteger column = [[result objectForKey:@"column"] integerValue];
  if ([[self browserFolder:column] isEqual:folder])
    {
      [browser reloadColumn:column];
      [self restoreBrowserColumn:column];
      [self checkDirectory:nil];
      [self showRevealedItem];
    }
  if ([result objectForKey:@"error"])
    [status setStringValue:[result objectForKey:@"error"]];
}

- (void)restoreBrowserColumn:(NSInteger)column
{
  NSString *folder = [self browserFolder:column];
  NSArray *selected = folder ? [savedBrowserSelection objectForKey:folder] : nil;
  if (!selected)
    return;
  NSMatrix *matrix = [browser matrixInColumn:column];
  [matrix deselectAllCells];
  NSInteger row;
  for (row = 0; row < [matrix numberOfRows]; row++)
    if ([selected containsObject:[[matrix cellAtRow:row column:0] representedObject]])
      [matrix setSelectionFrom:row to:row anchor:row highlight:YES];
  NSArray *cells = [matrix selectedCells];
  if ([cells count] == 1)
    {
      NSBrowserCell *cell = [cells objectAtIndex:0];
      if (![cell isLeaf] && [savedBrowserSelection objectForKey:[cell representedObject]])
        [browser addColumn];
    }
}

- (NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column
{
  return [self browserFolder:column];
}

- (BOOL)browser:(NSBrowser *)sender
    writeRowsWithIndexes:(NSIndexSet *)indices
                inColumn:(NSInteger)column
            toPasteboard:(NSPasteboard *)pb
{
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i = [indices firstIndex];
  while (i != NSNotFound)
    {
      NSString *p = [[[sender matrixInColumn:column] cellAtRow:i column:0] representedObject];
      if (p)
        [paths addObject:p];
      i = [indices indexGreaterThanIndex:i];
    }
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  return [pb setPropertyList:paths forType:NSFilenamesPboardType];
}

- (NSDragOperation)browser:(NSBrowser *)sender
              validateDrop:(id<NSDraggingInfo>)info
               proposedRow:(NSInteger *)row
                    column:(NSInteger *)column
             dropOperation:(NSBrowserDropOperation *)dropOperation
{
  return operation ? NSDragOperationNone : NSDragOperationCopy;
}

- (BOOL)browser:(NSBrowser *)sender
       acceptDrop:(id<NSDraggingInfo>)info
            atRow:(NSInteger)row
           column:(NSInteger)column
    dropOperation:(NSBrowserDropOperation)dropOperation
{
  NSString *dest = [self browserFolder:column];
  if (row >= 0)
    {
      NSString *p = [[[sender matrixInColumn:column] cellAtRow:row column:0] representedObject];
      if (p && [[FVItem itemAtPath:p] directory])
        dest = p;
    }
  [self runOperation:@"copy"
               paths:[[info draggingPasteboard] propertyListForType:NSFilenamesPboardType]
         destination:dest];
  return YES;
}

- (void)browserSelected:(id)sender
{
  RELEASE (savedBrowserSelection);
  savedBrowserSelection = nil;
  [self selectionChanged];
}

/* View → Search (Command-F) puts the cursor in the search field. */
- (void)search:(id)sender
{
  if ([path isEqual:FVRecentsLocation])
    return;
  [self endEditingName:YES];
  [[self window] makeFirstResponder:filter];
  [filter selectText:nil];
}

/* Scan metadata off the UI thread, including every expanded browser folder. */
- (void)checkDirectory:(NSTimer *)timer
{
  NSMutableSet *currentMounts = [NSMutableSet setWithArray:
      [[NSWorkspace sharedWorkspace] mountedLocalVolumePaths]];
  [currentMounts addObjectsFromArray:[FVMounts networkPaths]];
  [currentMounts addObjectsFromArray:FVVolumesInMountRoots ()];
  if (!closed && ![currentMounts isEqualToSet:mountedVolumePaths])
    [self rebuildPlaces];
  if (closed || loading || operation || searching || monitorBusy)
    return;
  monitorBusy = YES;
  NSMutableArray *folders = [NSMutableArray arrayWithObject:path];
  NSInteger column;
  for (column = 1; mode == 1 && column <= [browser lastColumn]; column++)
    {
      NSString *folder = [self browserFolder:column];
      if (folder && ![folders containsObject:folder])
        [folders addObject:folder];
    }
  NSDictionary *request = [NSDictionary
      dictionaryWithObjectsAndKeys:path, @"path", [NSNumber numberWithUnsignedInteger:generation],
                                   @"generation", folders, @"folders",
                                   [NSNumber numberWithBool:hidden], @"hidden", nil];
  [NSThread detachNewThreadSelector:@selector (readDirectoryStamp:)
                           toTarget:self
                         withObject:request];
}

- (void)readDirectoryStamp:(NSDictionary *)request
{
  CREATE_AUTORELEASE_POOL (pool);
  NSMutableDictionary *stamp = [NSMutableDictionary dictionaryWithDictionary:request];
  NSArray *folders = [request objectForKey:@"folders"];
  NSMutableDictionary *snapshots = [NSMutableDictionary dictionary];
  NSUInteger i;
  for (i = 0; i < [folders count]; i++)
    {
      NSString *folder = [folders objectAtIndex:i];
      NSMutableDictionary *entries = [NSMutableDictionary dictionary];
      if ([folder isEqual:FVRecentsLocation])
        {
          NSArray *records = [FVRecents records];
          NSUInteger j;
          for (j = 0; j < [records count]; j++)
            {
              NSDictionary *record = [records objectAtIndex:j];
              NSString *file = [record objectForKey:@"path"];
              [entries setObject:[NSArray arrayWithObjects:[record objectForKey:@"accessed"],
                  FVFileStamp (file, YES), nil] forKey:file];
            }
          [snapshots setObject:entries forKey:folder];
          continue;
        }
      [entries setObject:FVFileStamp (folder, YES) forKey:@""];
      /* Only entries that are shown, and never through a symlink: a hidden
         file that changes all the time, such as ~/.xsession-errors, would
         otherwise reload the folder every second, and a symlink into a hung
         mount would stop the monitor. */
      BOOL showHidden = [[request objectForKey:@"hidden"] boolValue];
      NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL];
      NSUInteger j;
      for (j = 0; j < [names count]; j++)
        {
          NSString *name = [names objectAtIndex:j];
          if (!showHidden && [name hasPrefix:@"."])
            continue;
          [entries setObject:FVFileStamp ([folder stringByAppendingPathComponent:name], NO)
                      forKey:name];
        }
      [snapshots setObject:entries forKey:folder];
    }
  [stamp setObject:snapshots forKey:@"snapshots"];
  NSString *folder = [request objectForKey:@"path"];
  struct statvfs space;
  if (!statvfs ([folder fileSystemRepresentation], &space))
    [stamp
        setObject:[NSString stringWithFormat:@" • %.1f GiB available",
                                             (double)space.f_bavail * space.f_frsize / 1073741824.0]
           forKey:@"space"];
  [self performSelectorOnMainThread:@selector (directoryStamp:) withObject:stamp waitUntilDone:NO];
  RELEASE (pool);
}

- (void)directoryStamp:(NSDictionary *)stamp
{
  monitorBusy = NO;
  if (closed || [[stamp objectForKey:@"generation"] unsignedIntegerValue] != generation)
    return;
  /* Keep the old stamp while a name is edited in place; the change is
     picked up once editing ends. */
  if (loading || operation || searching || editingPath)
    return;
  NSDictionary *previous = [[lastStamp objectForKey:@"path"] isEqual:path]
                               ? [lastStamp objectForKey:@"snapshots"] : nil;
  NSDictionary *snapshots = [stamp objectForKey:@"snapshots"];
  BOOL changed = NO;
  NSEnumerator *enumerator = [snapshots keyEnumerator];
  NSString *folder;
  while ((folder = [enumerator nextObject]))
    if ([previous objectForKey:folder]
        && ![[previous objectForKey:folder] isEqual:[snapshots objectForKey:folder]])
      changed = YES;
  /* A shown file that keeps changing, such as a log, still reloads the folder
     at most every few seconds. The old stamp is kept, so the change is
     picked up once the interval has passed. */
  if (changed && [NSDate timeIntervalSinceReferenceDate] - lastAutoRefresh < 5)
    return;
  RELEASE (lastStamp);
  lastStamp = [stamp copy];
  RELEASE (spaceDescription);
  spaceDescription = [[stamp objectForKey:@"space"] copy];
  if (changed)
    {
      lastAutoRefresh = [NSDate timeIntervalSinceReferenceDate];
      [self refresh:nil];
    }
  else
    [self selectionChanged];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = [item action];
  NSUInteger count = [[self selectedPaths] count];
  if ([path isEqual:FVRecentsLocation]
      && (action == @selector (newFolder:) || action == @selector (paste:)
          || action == @selector (duplicate:) || action == @selector (addFavorite:)
          || action == @selector (parent:) || action == @selector (search:)
          || action == @selector (columnMode:) || (action == @selector (info:) && !count)))
    return NO;
  if (action == @selector (toggleHidden:))
    [item setState:hidden ? NSOnState : NSOffState];
  if (action == @selector (toggleFolders:))
    [item setState:foldersFirst ? NSOnState : NSOffState];
  if (action == @selector (undo:))
    return !operation && [undoRecords count] > 0;
  if (action == @selector (back:))
    return historyIndex > 0;
  if (action == @selector (forward:))
    return historyIndex + 1 < (NSInteger)[history count];
  if (action == @selector (packageContents:))
    return count == 1 && [[FVItem itemAtPath:[[self selectedPaths] objectAtIndex:0]] directory];
  if (action == @selector (openNewWindow:))
    return !count
           || (count == 1 &&
               [[FVItem itemAtPath:[[self selectedPaths] objectAtIndex:0]] directory]);
  if (action == @selector (newFolder:))
    return !operation;
  if (action == @selector (rename:))
    return count == 1 && !operation;
  if (action == @selector (openWith:))
    return count > 0;
  if (action == @selector (resetOpenWith:))
    {
      NSArray *selected = [self selectedPaths];
      NSUInteger i;
      for (i = 0; i < [selected count]; i++)
        if ([FVLauncher defaultApplicationForFile:[selected objectAtIndex:i]])
          return YES;
      return NO;
    }
  if (action == @selector (copy:) || action == @selector (cut:) || action == @selector (open:)
      || action == @selector (trash:) || action == @selector (deletePermanently:)
      || action == @selector (duplicate:) || action == @selector (moveTo:))
    return count > 0 && !operation;
  if (action == @selector (paste:))
    return !operation &&
           [[[NSPasteboard generalPasteboard] types] containsObject:NSFilenamesPboardType];
  if (action == @selector (cancel:))
    return loading || operation != nil;
  return YES;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [thumbnailQueue cancelAllOperations];
  RELEASE (thumbnailQueue);
  RELEASE (thumbnailCache);
  RELEASE (thumbnailRequests);
  [monitor invalidate];
  RELEASE (monitor);
  [listing cancel];
  RELEASE (listing);
  [operation cancel];
  RELEASE (operation);
  RELEASE (path);
  RELEASE (items);
  RELEASE (history);
  RELEASE (table);
  RELEASE (sidebar);
  RELEASE (places);
  RELEASE (filter);
  RELEASE (searchScope);
  RELEASE (locationColumn);
  RELEASE (status);
  RELEASE (activityStatus);
  RELEASE (operationActivity);
  RELEASE (breadcrumbs);
  RELEASE (scroll);
  RELEASE (host);
  RELEASE (browser);
  RELEASE (icons);
  RELEASE (browserRows);
  RELEASE (iconCache);
  RELEASE (placeIcons);
  RELEASE (mountedVolumePaths);
  RELEASE (errors);
  RELEASE (savedSelection);
  RELEASE (savedBrowserSelection);
  RELEASE (lastStamp);
  RELEASE (spaceDescription);
  RELEASE (sortKey);
  RELEASE (undoRecords);
  [nameEditor setDelegate:nil];
  RELEASE (nameEditor);
  RELEASE (editingPath);
  RELEASE (revealPath);
  DEALLOC;
}

@end
