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

#import "FVRewind.h"
#import "FVWindow.h"

/* The schedule's choices: the values the rewind job reads, and titles. */
static NSArray *
FVFreqValues (void)
{
  return [NSArray arrayWithObjects:@"15m", @"hourly", @"daily", @"weekly", nil];
}

static NSArray *
FVFreqTitles (void)
{
  return [NSArray arrayWithObjects:@"Every 15 minutes", @"Every hour", @"Every day",
                                   @"Every week", nil];
}

static NSArray *
FVKeepValues (void)
{
  return [NSArray arrayWithObjects:@"7", @"14", @"30", @"90", nil];
}

static NSArray *
FVKeepTitles (void)
{
  return [NSArray arrayWithObjects:@"1 week", @"2 weeks", @"1 month", @"3 months", nil];
}

static NSTextField *
FVRewindLabel (NSRect frame, NSString *text)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [label setStringValue:text];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  return label;
}

/* "rewind-20261126-041335" as "Today 04:13", "Yesterday 18:00" or
   "Nov 24 09:00"; any other snapshot by its own name. */
static NSString *
FVSnapshotTitle (NSString *name)
{
  if (![name hasPrefix:@"rewind-"] || [name length] != 22)
    return name;
  NSString *stamp = [name substringFromIndex:7];
  NSCalendarDate *date = [NSCalendarDate dateWithString:stamp
                                         calendarFormat:@"%Y%m%d-%H%M%S"];
  if (date == nil)
    return name;
  NSCalendarDate *now = [NSCalendarDate calendarDate];
  NSInteger days = [now dayOfCommonEra] - [date dayOfCommonEra];
  NSString *time = [date descriptionWithCalendarFormat:@"%H:%M"];
  if (days == 0)
    return [@"Today " stringByAppendingString:time];
  if (days == 1)
    return [@"Yesterday " stringByAppendingString:time];
  return [date descriptionWithCalendarFormat:@"%b %e %H:%M"];
}

@implementation FVRewind

- (id)initWithViewer:(FVWindow *)aViewer
{
  if ((self = [super init]) != nil)
    {
      viewer = aViewer;
      home = [[NSHomeDirectory () stringByStandardizingPath] copy];
    }
  return self;
}

- (void)dealloc
{
  [timeline close];
  RELEASE (timeline);
  RELEASE (schedule);
  RELEASE (versions);
  RELEASE (home);
  RELEASE (liveFolder);
  [super dealloc];
}

- (BOOL)isRewinding
{
  return rewinding;
}

- (NSString *)rewindDirectory
{
  return [home stringByAppendingPathComponent:@"Library/Rewind"];
}

- (NSString *)snapshotRoot
{
  return [home stringByAppendingPathComponent:@".zfs/snapshot"];
}

/* Where home's snapshots live: this computer, or the server for a network
   home. */
- (NSString *)sourceName
{
  return [home hasPrefix:@"/Network/"] ? @"the server" : @"this computer";
}

/* ---- the schedule ---- */

- (NSDictionary *)readKeyValues:(NSString *)file
{
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  NSString *text = [NSString stringWithContentsOfFile:
      [[self rewindDirectory] stringByAppendingPathComponent:file]];
  NSEnumerator *e = [[text componentsSeparatedByString:@"\n"] objectEnumerator];
  NSString *line;
  while ((line = [e nextObject]) != nil)
    {
      NSRange eq = [line rangeOfString:@"="];
      if (eq.location == NSNotFound)
        continue;
      [values setObject:[[line substringFromIndex:NSMaxRange (eq)]
                            stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceCharacterSet]]
                 forKey:[[line substringToIndex:eq.location]
                            stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceCharacterSet]]];
    }
  return values;
}

- (BOOL)ensureRewindDirectory
{
  return [[NSFileManager defaultManager] createDirectoryAtPath:[self rewindDirectory]
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:NULL];
}

static NSPopUpButton *
FVRewindPopUp (NSView *view, NSRect frame, NSArray *titles)
{
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame:frame
                                                                 pullsDown:NO]);
  [popUp addItemsWithTitles:titles];
  [view addSubview:popUp];
  return popUp;
}

static NSButton *
FVRewindCheckbox (NSView *view, NSRect frame, NSString *title)
{
  NSButton *box = AUTORELEASE ([[NSButton alloc] initWithFrame:frame]);
  [box setButtonType:NSSwitchButton];
  [box setTitle:title];
  [view addSubview:box];
  return box;
}

- (void)buildSchedule
{
  schedule = [[NSPanel alloc] initWithContentRect:NSMakeRect (0, 0, 470, 360)
                                        styleMask:NSTitledWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [schedule setTitle:@"Snapshots"];
  NSView *v = [schedule contentView];
  CGFloat y = 316;
  NSTextField *title = FVRewindLabel (NSMakeRect (20, y, 430, 24),
      [NSString stringWithFormat:@"Snapshots of %@'s home", NSUserName ()]);
  [title setFont:[NSFont boldSystemFontOfSize:0]];
  [v addSubview:title];
  y -= 34;
  [v addSubview:FVRewindLabel (NSMakeRect (20, y, 120, 22), @"Snapshots:")];
  enabledBox = FVRewindCheckbox (v, NSMakeRect (148, y, 60, 22), @"On");
  [enabledBox setTarget:self];
  [enabledBox setAction:@selector (enabledChanged:)];
  statusLabel = FVRewindLabel (NSMakeRect (210, y, 250, 22), @"");
  [statusLabel setTextColor:[NSColor secondaryLabelColor]];
  [v addSubview:statusLabel];
  y -= 36;
  [v addSubview:FVRewindLabel (NSMakeRect (20, y, 120, 22), @"How often:")];
  freqPopUp = FVRewindPopUp (v, NSMakeRect (148, y - 2, 170, 26), FVFreqTitles ());
  [freqPopUp setTarget:self];
  [freqPopUp setAction:@selector (enabledChanged:)];
  NSMutableArray *times = [NSMutableArray array];
  int h;
  for (h = 0; h < 24; h++)
    [times addObject:[NSString stringWithFormat:@"%02d:00", h]];
  atPopUp = FVRewindPopUp (v, NSMakeRect (326, y - 2, 90, 26), times);
  y -= 36;
  [v addSubview:FVRewindLabel (NSMakeRect (20, y, 120, 22), @"Keep for:")];
  keepPopUp = FVRewindPopUp (v, NSMakeRect (148, y - 2, 170, 26), FVKeepTitles ());
  y -= 22;
  NSTextField *hint = FVRewindLabel (NSMakeRect (148, y, 300, 18),
                                     @"Older snapshots are removed automatically.");
  [hint setTextColor:[NSColor secondaryLabelColor]];
  [hint setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [v addSubview:hint];
  y -= 32;
  thinBox = FVRewindCheckbox (v, NSMakeRect (146, y, 310, 22),
                              @"After 2 days, keep one a day");
  y -= 26;
  beforeBox = FVRewindCheckbox (v, NSMakeRect (146, y, 310, 22),
                                @"Take one before each system update");
  y -= 26;
  lowBox = FVRewindCheckbox (v, NSMakeRect (146, y, 310, 22),
                             @"When space runs low, remove the oldest");
  y -= 30;
  NSTextField *where = FVRewindLabel (NSMakeRect (20, y, 430, 18),
      [NSString stringWithFormat:@"Snapshots are kept on %@, in your home folder's dataset.",
                                 [self sourceName]]);
  [where setTextColor:[NSColor secondaryLabelColor]];
  [where setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [v addSubview:where];

  NSButton *now = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (16, 14, 160, 28)]);
  [now setTitle:@"Take Snapshot Now"];
  [now setTarget:self];
  [now setAction:@selector (takeSnapshotNow:)];
  [v addSubview:now];
  NSButton *cancel = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (238, 14, 96, 28)]);
  [cancel setTitle:@"Cancel"];
  [cancel setKeyEquivalent:@"\e"];
  [cancel setTarget:self];
  [cancel setAction:@selector (cancelSchedule:)];
  [v addSubview:cancel];
  NSButton *save = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (342, 14, 112, 28)]);
  [save setTitle:@"Save Schedule"];
  [save setKeyEquivalent:@"\r"];
  [save setTarget:self];
  [save setAction:@selector (saveSchedule:)];
  [v addSubview:save];
}

- (void)selectValue:(NSString *)value
          inPopUp:(NSPopUpButton *)popUp
           values:(NSArray *)values
         fallback:(NSString *)fallback
{
  NSUInteger i = [values indexOfObject:value ? value : fallback];
  [popUp selectItemAtIndex:i == NSNotFound ? [values indexOfObject:fallback] : i];
}

- (void)showStatus
{
  NSDictionary *status = [self readKeyValues:@"Status"];
  NSString *count = [status objectForKey:@"count"];
  if ([enabledBox state] != NSOnState && ![count intValue])
    {
      [statusLabel setStringValue:@"Off"];
      return;
    }
  double used = [[status objectForKey:@"used"] doubleValue] / (1024.0 * 1024.0);
  NSString *latest = [status objectForKey:@"latest"];
  [statusLabel setStringValue:
      [NSString stringWithFormat:@"%d kept · %.1f MB%@", [count intValue], used,
                                 [latest length] ? [@" · latest "
                                     stringByAppendingString:FVSnapshotTitle (latest)]
                                                 : @""]];
}

- (void)enabledChanged:(id)sender
{
  BOOL on = [enabledBox state] == NSOnState;
  NSInteger freq = [freqPopUp indexOfSelectedItem];
  [freqPopUp setEnabled:on];
  [atPopUp setEnabled:on && freq >= 2];
  [keepPopUp setEnabled:on];
  [thinBox setEnabled:on];
  [beforeBox setEnabled:on];
  [lowBox setEnabled:on];
}

/* Snapshots: the schedule for this home, with Save Schedule, or Take
   Snapshot Now for one at once. */
- (void)showSnapshots:(id)sender
{
  if (schedule == nil)
    [self buildSchedule];
  NSDictionary *s = [self readKeyValues:@"Schedule"];
  [enabledBox setState:[[s objectForKey:@"enabled"] isEqual:@"1"] ? NSOnState : NSOffState];
  [self selectValue:[s objectForKey:@"freq"] inPopUp:freqPopUp
             values:FVFreqValues () fallback:@"hourly"];
  [self selectValue:[s objectForKey:@"keep"] inPopUp:keepPopUp
             values:FVKeepValues () fallback:@"14"];
  NSString *at = [s objectForKey:@"at"];
  [atPopUp selectItemWithTitle:[at length] == 5 ? at : @"02:00"];
  if ([atPopUp indexOfSelectedItem] < 0)
    [atPopUp selectItemWithTitle:@"02:00"];
  [thinBox setState:[[s objectForKey:@"thin"] isEqual:@"0"] ? NSOffState : NSOnState];
  [beforeBox setState:[[s objectForKey:@"before"] isEqual:@"0"] ? NSOffState : NSOnState];
  [lowBox setState:[[s objectForKey:@"low"] isEqual:@"0"] ? NSOffState : NSOnState];
  [self enabledChanged:nil];
  [self showStatus];
  [schedule center];
  [NSApp runModalForWindow:schedule];
  [schedule orderOut:nil];
}

- (void)cancelSchedule:(id)sender
{
  [NSApp stopModal];
}

- (void)saveSchedule:(id)sender
{
  NSString *text = [NSString stringWithFormat:
      @"enabled=%d\nfreq=%@\nat=%@\nkeep=%@\nthin=%d\nbefore=%d\nlow=%d\n",
      [enabledBox state] == NSOnState,
      [FVFreqValues () objectAtIndex:[freqPopUp indexOfSelectedItem]],
      [atPopUp titleOfSelectedItem],
      [FVKeepValues () objectAtIndex:[keepPopUp indexOfSelectedItem]],
      [thinBox state] == NSOnState, [beforeBox state] == NSOnState,
      [lowBox state] == NSOnState];
  if (![self ensureRewindDirectory]
      || ![text writeToFile:[[self rewindDirectory] stringByAppendingPathComponent:@"Schedule"]
                 atomically:YES])
    {
      NSRunAlertPanel (@"Snapshots", @"The schedule couldn't be saved in %@.", @"OK", nil,
                       nil, [self rewindDirectory]);
      return;
    }
  [NSApp stopModal];
  [viewer operationProgress:[enabledBox state] == NSOnState
                                ? @"Snapshot schedule saved."
                                : @"Scheduled snapshots are off."];
}

/* Ask for a snapshot now and close: the rewind job takes it within a
   minute, where the home is kept. */
- (void)takeSnapshotNow:(id)sender
{
  if (![self ensureRewindDirectory]
      || ![@"" writeToFile:[[self rewindDirectory] stringByAppendingPathComponent:@"SnapshotNow"]
               atomically:YES])
    {
      NSRunAlertPanel (@"Snapshots", @"A snapshot couldn't be asked for in %@.", @"OK", nil,
                       nil, [self rewindDirectory]);
      return;
    }
  [NSApp stopModal];
  [viewer operationProgress:
      [NSString stringWithFormat:@"Snapshot on its way: %@ takes it within a minute.",
                                 [home hasPrefix:@"/Network/"] ? @"the server" : @"NextBSD"]];
}

/* ---- Rewind ---- */

/* The folder's path inside home, or nil outside it. */
- (NSString *)relativeInHome:(NSString *)folder
{
  folder = [folder stringByStandardizingPath];
  if ([folder isEqual:home])
    return @"";
  NSString *prefix = [home stringByAppendingString:@"/"];
  if ([folder hasPrefix:prefix])
    return [folder substringFromIndex:[prefix length]];
  return nil;
}

/* A path inside a snapshot as "snapshot" and "relative" parts, or nil. */
- (NSArray *)snapshotPartsOf:(NSString *)folder
{
  NSString *prefix = [[self snapshotRoot] stringByAppendingString:@"/"];
  folder = [folder stringByStandardizingPath];
  if (![folder hasPrefix:prefix])
    return nil;
  NSString *rest = [folder substringFromIndex:[prefix length]];
  NSRange slash = [rest rangeOfString:@"/"];
  if (slash.location == NSNotFound)
    return [NSArray arrayWithObjects:rest, @"", nil];
  return [NSArray arrayWithObjects:[rest substringToIndex:slash.location],
                                   [rest substringFromIndex:NSMaxRange (slash)], nil];
}

- (NSString *)currentRelative
{
  NSArray *parts = [self snapshotPartsOf:[viewer currentPath]];
  return parts ? [parts objectAtIndex:1] : [self relativeInHome:[viewer currentPath]];
}

/* When a snapshot was taken: from its rewind-YYYYMMDD-HHMMSS name, or for
   one named otherwise, when its top folder last changed before it. */
- (NSDate *)dateOfSnapshot:(NSString *)name
{
  if ([name hasPrefix:@"rewind-"] && [name length] == 22)
    {
      NSDate *date = [NSCalendarDate dateWithString:[name substringFromIndex:7]
                                     calendarFormat:@"%Y%m%d-%H%M%S"];
      if (date != nil)
        return date;
    }
  NSDate *changed = [[[NSFileManager defaultManager]
      fileAttributesAtPath:[[self snapshotRoot] stringByAppendingPathComponent:name]
              traverseLink:NO] fileModificationDate];
  return changed ? changed : [NSDate distantPast];
}

static NSInteger
FVNewestFirst (id a, id b, void *context)
{
  return [[(NSDictionary *)context objectForKey:b] compare:
                                [(NSDictionary *)context objectForKey:a]];
}

/* The snapshots of home, newest first. */
- (NSArray *)loadVersions
{
  NSArray *names = [[NSFileManager defaultManager]
      directoryContentsAtPath:[self snapshotRoot]];
  NSMutableDictionary *dates = [NSMutableDictionary dictionary];
  NSEnumerator *e = [names objectEnumerator];
  NSString *name;
  while ((name = [e nextObject]) != nil)
    [dates setObject:[self dateOfSnapshot:name] forKey:name];
  return [names sortedArrayUsingFunction:FVNewestFirst context:dates];
}

- (void)buildTimeline
{
  timeline = [[NSPanel alloc] initWithContentRect:NSMakeRect (0, 0, 220, 420)
                                        styleMask:NSTitledWindowMask | NSUtilityWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [timeline setTitle:@"Rewind"];
  [timeline setFloatingPanel:YES];
  [timeline setHidesOnDeactivate:NO];
  NSView *v = [timeline contentView];
  [v setAutoresizesSubviews:YES];
  whenLabel = FVRewindLabel (NSMakeRect (12, 388, 196, 22), @"Now");
  [whenLabel setFont:[NSFont boldSystemFontOfSize:0]];
  [whenLabel setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
  [v addSubview:whenLabel];
  NSTextField *from = FVRewindLabel (NSMakeRect (12, 366, 196, 18),
      [@"From " stringByAppendingString:[self sourceName]]);
  [from setTextColor:[NSColor secondaryLabelColor]];
  [from setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [from setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
  [v addSubview:from];

  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc]
      initWithFrame:NSMakeRect (10, 52, 200, 306)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  versionsTable = AUTORELEASE ([[NSTableView alloc]
      initWithFrame:[[scroll contentView] bounds]]);
  NSTableColumn *column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"when"]);
  [column setWidth:180];
  [column setEditable:NO];
  [versionsTable addTableColumn:column];
  [versionsTable setHeaderView:nil];
  [versionsTable setDataSource:(id)self];
  [versionsTable setDelegate:(id)self];
  [versionsTable setAllowsEmptySelection:NO];
  [scroll setDocumentView:versionsTable];
  [v addSubview:scroll];

  restoreButton = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (10, 12, 110, 28)]);
  [restoreButton setTitle:@"Restore"];
  [restoreButton setKeyEquivalent:@"\r"];
  [restoreButton setTarget:self];
  [restoreButton setAction:@selector (restore:)];
  [v addSubview:restoreButton];
  NSButton *done = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (128, 12, 82, 28)]);
  [done setTitle:@"Done"];
  [done setKeyEquivalent:@"\e"];
  [done setTarget:self];
  [done setAction:@selector (toggleRewind:)];
  [v addSubview:done];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return [versions count] + 1;
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  return row == 0 ? @"Now" : FVSnapshotTitle ([versions objectAtIndex:row - 1]);
}

/* Show the folder as it was at the chosen time: the same folder inside
   that snapshot, or the nearest folder above it that existed then. */
- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  NSInteger row = [versionsTable selectedRow];
  NSString *rel = [self currentRelative];
  if (rel == nil)
    rel = @"";
  NSString *target;
  if (row <= 0)
    {
      target = [home stringByAppendingPathComponent:rel];
      [whenLabel setStringValue:@"Now"];
    }
  else
    {
      NSString *snap = [versions objectAtIndex:row - 1];
      NSString *base = [[self snapshotRoot] stringByAppendingPathComponent:snap];
      target = [base stringByAppendingPathComponent:rel];
      BOOL dir = NO;
      while (![[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&dir]
             || !dir)
        {
          if ([target length] <= [base length])
            break;
          target = [target stringByDeletingLastPathComponent];
        }
      [whenLabel setStringValue:FVSnapshotTitle (snap)];
    }
  [restoreButton setEnabled:row > 0];
  [viewer navigate:target];
  [self viewerDidNavigate];
}

- (void)placeTimeline
{
  NSRect frame = [[viewer window] frame];
  NSRect screen = [[[viewer window] screen] visibleFrame];
  NSRect t = [timeline frame];
  t.size.height = NSHeight (frame);
  t.origin.y = NSMinY (frame);
  t.origin.x = NSMaxX (frame) + 8;
  if (NSMaxX (t) > NSMaxX (screen))
    {
      /* No room on the right: on the left, below the NeXT menu that
         sits in the top left corner. */
      t.origin.x = MAX (NSMinX (screen), NSMinX (frame) - NSWidth (t) - 8);
      if (NSMinX (t) < 220)
        t.size.height = MAX (260, MIN (NSHeight (frame),
                                       NSMaxY (screen) - 230 - NSMinY (frame)));
    }
  [timeline setFrame:t display:YES];
}

- (void)toggleRewind:(id)sender
{
  if (rewinding)
    {
      rewinding = NO;
      [timeline orderOut:nil];
      NSString *rel = [self currentRelative];
      NSString *back = rel ? [home stringByAppendingPathComponent:rel] : liveFolder;
      BOOL dir = NO;
      while (![[NSFileManager defaultManager] fileExistsAtPath:back isDirectory:&dir] || !dir)
        {
          if ([back length] <= [home length])
            {
              back = home;
              break;
            }
          back = [back stringByDeletingLastPathComponent];
        }
      [viewer navigate:back];
      [[viewer window] setTitle:@"File Viewer"];
      return;
    }
  if ([self relativeInHome:[viewer currentPath]] == nil)
    {
      NSRunAlertPanel (@"Rewind", @"Rewind shows earlier versions of folders in your home folder.",
                       @"OK", nil, nil);
      return;
    }
  ASSIGN (versions, [self loadVersions]);
  if (![versions count])
    {
      NSRunAlertPanel (@"Rewind",
                       @"There are no snapshots of your home folder yet. Use Snapshots to "
                       @"turn them on, or to take one now.",
                       @"OK", nil, nil);
      return;
    }
  ASSIGN (liveFolder, [viewer currentPath]);
  if (timeline == nil)
    [self buildTimeline];
  rewinding = YES;
  [versionsTable reloadData];
  [self placeTimeline];
  [timeline orderFront:nil];
  /* Start one step back: the most recent snapshot. */
  [versionsTable selectRow:1 byExtendingSelection:NO];
  [self tableViewSelectionDidChange:nil];
}

/* The window title says which time the viewer shows. */
- (void)viewerDidNavigate
{
  if (!rewinding)
    return;
  NSArray *parts = [self snapshotPartsOf:[viewer currentPath]];
  [[viewer window] setTitle:parts ? [NSString stringWithFormat:@"File Viewer — %@",
                                                FVSnapshotTitle ([parts objectAtIndex:0])]
                                  : @"File Viewer"];
}

/* Restore: the selected items, or the whole folder, copied back into the
   folder as it is now, through File Viewer's copy (Keep Both, Skip or
   Replace on a conflict; Undo afterwards). */
- (void)restore:(id)sender
{
  NSArray *parts = [self snapshotPartsOf:[viewer currentPath]];
  if (parts == nil)
    return;
  NSString *rel = [parts objectAtIndex:1];
  NSString *destination = [home stringByAppendingPathComponent:rel];
  NSArray *sources = [viewer selectedPaths];
  if (![sources count])
    {
      NSArray *names = [[NSFileManager defaultManager]
          directoryContentsAtPath:[viewer currentPath]];
      NSMutableArray *all = [NSMutableArray array];
      NSEnumerator *e = [names objectEnumerator];
      NSString *name;
      while ((name = [e nextObject]) != nil)
        [all addObject:[[viewer currentPath] stringByAppendingPathComponent:name]];
      sources = all;
      if (![sources count])
        return;
    }
  [[NSFileManager defaultManager] createDirectoryAtPath:destination
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  [self toggleRewind:nil];
  [viewer runOperation:@"copy" paths:sources destination:destination];
}

- (void)viewerWillClose
{
  rewinding = NO;
  [timeline orderOut:nil];
  [schedule orderOut:nil];
}

@end
