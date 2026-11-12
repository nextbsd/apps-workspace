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

#import "FVPanels.h"

NSString *
FVSizeString (unsigned long long bytes)
{
  if (bytes < 1000)
    return [NSString stringWithFormat:bytes == 1 ? @"%llu byte" : @"%llu bytes", bytes];
  NSArray *units = [NSArray arrayWithObjects:@"KB", @"MB", @"GB", @"TB", @"PB", nil];
  double value = bytes / 1000.0;
  NSUInteger unit = 0;
  while (value >= 999.95 && unit + 1 < [units count])
    {
      value /= 1000;
      unit++;
    }
  return [NSString stringWithFormat:value < 10 ? @"%.1f %@" : @"%.0f %@", value,
                                    [units objectAtIndex:unit]];
}

/* 40,001 */
static NSString *
FVCountString (unsigned long long count)
{
  static NSNumberFormatter *formatter = nil;
  if (!formatter)
    {
      formatter = [[NSNumberFormatter alloc] init];
      [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    }
  return [formatter stringFromNumber:[NSNumber numberWithUnsignedLongLong:count]];
}

static NSTextField *
FVPanelLabel (NSRect frame, NSString *text, NSFont *font)
{
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [field setEditable:NO];
  [field setSelectable:NO];
  [field setBezeled:NO];
  [field setBordered:NO];
  [field setDrawsBackground:NO];
  [field setFont:font];
  [[field cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [field setStringValue:text];
  return field;
}

static const CGFloat FVProgressRowHeight = 92, FVProgressWidth = 480;
/* Quick operations finish before the panel would appear. */
static const NSTimeInterval FVProgressDelay = .6;

@interface FVProgressRow : NSObject
{
@public
  id operation;
  id owner;
  NSView *view;
  NSTextField *title;
  NSTextField *detail;
  NSProgressIndicator *bar;
  NSButton *stop;
  BOOL shown;
}
@end

@implementation FVProgressRow

- (void)dealloc
{
  RELEASE (operation);
  RELEASE (view);
  DEALLOC;
}

@end

static NSString *
FVItemsPhrase (NSArray *sources)
{
  if ([sources count] == 1 && [[sources objectAtIndex:0] isKindOfClass:[NSString class]])
    return [NSString stringWithFormat:@"“%@”", [[sources objectAtIndex:0] lastPathComponent]];
  return [NSString stringWithFormat:@"%lu items", (unsigned long)[sources count]];
}

@implementation FVProgressPanel

+ (FVProgressPanel *)sharedPanel
{
  static FVProgressPanel *shared = nil;
  if (!shared)
    shared = [[FVProgressPanel alloc] init];
  return shared;
}

- (id)init
{
  if ((self = [super init]))
    rows = [[NSMutableArray alloc] init];
  return self;
}

- (NSPanel *)panel
{
  return panel;
}

- (FVProgressRow *)rowForOperation:(id)operation
{
  NSUInteger i;
  for (i = 0; i < [rows count]; i++)
    if (((FVProgressRow *)[rows objectAtIndex:i])->operation == operation)
      return [rows objectAtIndex:i];
  return nil;
}

/* Rows stack from the top; the panel keeps its top edge as rows come and go. */
- (void)layout
{
  NSUInteger count = 0, i;
  for (i = 0; i < [rows count]; i++)
    if (((FVProgressRow *)[rows objectAtIndex:i])->shown)
      count++;
  if (!count)
    {
      [panel orderOut:nil];
      return;
    }
  if (!panel)
    {
      panel = [[NSPanel alloc]
          initWithContentRect:NSMakeRect (0, 0, FVProgressWidth, FVProgressRowHeight)
                    styleMask:NSTitledWindowMask
                      backing:NSBackingStoreBuffered
                        defer:NO];
      [panel setTitle:@"Processes"];
      [panel setReleasedWhenClosed:NO];
      [panel setBecomesKeyOnlyIfNeeded:YES];
      [panel setHidesOnDeactivate:NO];
      [panel center];
    }
  BOOL visible = [panel isVisible];
  NSRect frame = [panel frame];
  NSRect content = [panel contentRectForFrameRect:frame];
  CGFloat top = NSMaxY (content);
  content.size = NSMakeSize (FVProgressWidth, count * FVProgressRowHeight);
  content.origin.y = top - content.size.height;
  [panel setFrame:[panel frameRectForContentRect:content] display:NO];
  NSView *contentView = [panel contentView];
  CGFloat y = count * FVProgressRowHeight;
  for (i = 0; i < [rows count]; i++)
    {
      FVProgressRow *row = [rows objectAtIndex:i];
      if (!row->shown)
        continue;
      y -= FVProgressRowHeight;
      [row->view setFrameOrigin:NSMakePoint (0, y)];
      if ([row->view superview] != contentView)
        [contentView addSubview:row->view];
    }
  [contentView setNeedsDisplay:YES];
  if (!visible)
    [panel orderFront:nil];
}

- (void)beginOperation:(id)operation
                  kind:(NSString *)kind
               sources:(NSArray *)sources
           destination:(NSString *)destination
                 owner:(id)owner
{
  NSString *items = FVItemsPhrase (sources);
  NSString *folder = [NSString stringWithFormat:@"“%@”", [destination lastPathComponent]];
  NSString *text;
  if ([kind isEqual:@"copy"])
    text = [NSString stringWithFormat:@"Copying %@ to %@", items, folder];
  else if ([kind isEqual:@"move"])
    text = [NSString stringWithFormat:@"Moving %@ to %@", items, folder];
  else if ([kind isEqual:@"duplicate"])
    text = [NSString stringWithFormat:@"Duplicating %@", items];
  else if ([kind isEqual:@"trash"])
    text = [NSString stringWithFormat:@"Moving %@ to the Trash", items];
  else if ([kind isEqual:@"delete"])
    text = [NSString stringWithFormat:@"Deleting %@", items];
  else
    return;
  FVProgressRow *row = AUTORELEASE ([[FVProgressRow alloc] init]);
  row->operation = RETAIN (operation);
  row->owner = owner;
  row->view = [[NSView alloc] initWithFrame:NSMakeRect (0, 0, FVProgressWidth,
                                                         FVProgressRowHeight)];
  CGFloat inner = FVProgressWidth - 36;
  row->title = FVPanelLabel (NSMakeRect (18, 58, inner, 22), text,
                             [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]);
  [row->view addSubview:row->title];
  row->bar = AUTORELEASE ([[NSProgressIndicator alloc]
      initWithFrame:NSMakeRect (18, 36, inner - 92, 16)]);
  [row->bar setIndeterminate:YES];
  [row->bar setMinValue:0];
  [row->bar setMaxValue:1];
  [row->view addSubview:row->bar];
  row->stop = AUTORELEASE ([[NSButton alloc]
      initWithFrame:NSMakeRect (FVProgressWidth - 18 - 80, 30, 80, 28)]);
  [row->stop setTitle:@"Stop"];
  [row->stop setTarget:owner];
  [row->stop setAction:@selector (stopOperation:)];
  [row->view addSubview:row->stop];
  row->detail = FVPanelLabel (NSMakeRect (18, 8, inner, 20), @"Preparing…",
                              [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
  [row->view addSubview:row->detail];
  [rows addObject:row];
  NSTimer *timer = [NSTimer timerWithTimeInterval:FVProgressDelay
                                           target:self
                                         selector:@selector (showRow:)
                                         userInfo:operation
                                          repeats:NO];
  /* Also while a conflict panel runs modally. */
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
}

- (void)showRow:(NSTimer *)timer
{
  FVProgressRow *row = [self rowForOperation:[timer userInfo]];
  if (!row || row->shown)
    return;
  row->shown = YES;
  [row->bar startAnimation:nil];
  [self layout];
}

- (void)updateOperation:(id)operation progress:(NSDictionary *)progress
{
  FVProgressRow *row = [self rowForOperation:operation];
  if (!row || ![[row->stop title] isEqual:@"Stop"])
    return;
  unsigned long long done = [[progress objectForKey:@"bytesDone"] unsignedLongLongValue];
  unsigned long long total = [[progress objectForKey:@"bytesTotal"] unsignedLongLongValue];
  NSUInteger index = [[progress objectForKey:@"index"] unsignedIntegerValue];
  NSUInteger count = [[progress objectForKey:@"count"] unsignedIntegerValue];
  NSString *name = [progress objectForKey:@"name"];
  if ([[progress objectForKey:@"preparing"] boolValue])
    {
      [row->detail setStringValue:@"Preparing…"];
      return;
    }
  unsigned long long entries = [[progress objectForKey:@"entriesDone"] unsignedLongLongValue];
  unsigned long long entriesTotal = [[progress objectForKey:@"entriesTotal"] unsignedLongLongValue];
  /* Each file costs about as much as 4 KB of data, so a folder of many
     small files still moves the bar. */
  double fraction = total || entriesTotal
      ? (done + 4096.0 * entries) / (total + 4096.0 * entriesTotal)
      : (count ? (double)index / count : 0);
  if ([row->bar isIndeterminate])
    {
      [row->bar stopAnimation:nil];
      [row->bar setIndeterminate:NO];
    }
  [row->bar setDoubleValue:MIN (1, fraction)];
  NSString *position = total
      ? [NSString stringWithFormat:@"%@ of %@", FVSizeString (done), FVSizeString (total)]
      : entriesTotal > count
      ? [NSString stringWithFormat:@"%@ of %@ items", FVCountString (MIN (entries + 1, entriesTotal)),
                                   FVCountString (entriesTotal)]
      : [NSString stringWithFormat:@"%lu of %lu", (unsigned long)MIN (index + 1, count),
                                   (unsigned long)count];
  [row->detail setStringValue:[name length]
      ? [NSString stringWithFormat:@"%@ — %@", name, position] : position];
  if (row->shown)
    [[panel contentView] setNeedsDisplay:YES];
}

- (void)operationStopping:(id)operation
{
  FVProgressRow *row = [self rowForOperation:operation];
  if (!row)
    return;
  [row->stop setTitle:@"Stopping…"];
  [row->stop setEnabled:NO];
  [row->detail setStringValue:@"Stopping. Items already finished stay where they are."];
}

- (void)endOperation:(id)operation
{
  FVProgressRow *row = [self rowForOperation:operation];
  if (!row)
    return;
  [row->view removeFromSuperview];
  [rows removeObjectIdenticalTo:row];
  [self layout];
}

- (void)dealloc
{
  RELEASE (panel);
  RELEASE (rows);
  DEALLOC;
}

@end
