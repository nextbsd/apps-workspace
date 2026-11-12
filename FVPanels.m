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

/* Escape presses the panel's Cancel button, even while a text field edits. */
@implementation FVDialogPanel

- (void)sendEvent:(NSEvent *)event
{
  if ([event type] == NSKeyDown && [[event charactersIgnoringModifiers] isEqual:@"\e"])
    {
      NSArray *views = [[self contentView] subviews];
      NSUInteger i;
      for (i = 0; i < [views count]; i++)
        {
          id view = [views objectAtIndex:i];
          if ([view isKindOfClass:[NSButton class]] && [[view keyEquivalent] isEqual:@"\e"])
            {
              [view performClick:self];
              return;
            }
        }
    }
  [super sendEvent:event];
}

@end

/* Dialog text stays legible and unselected on light and dark themes: a
   selectable label becomes first responder and is drawn selected. */
NSColor *
FVDialogTextColor (NSWindow *window)
{
  NSColor *background = [[window backgroundColor]
      colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  CGFloat brightness = background ? ([background redComponent] + [background greenComponent]
                                      + [background blueComponent]) / 3 : 1;
  return [NSColor colorWithCalibratedWhite:brightness < .5 ? .94 : .12 alpha:1];
}

/* Bounded modal sessions also observe programmatic completion while no X
   events arrive (GNUstep's blocking modal peek otherwise waits indefinitely). */
NSInteger
FVRunModalPanel (NSPanel *panel)
{
  /* GUI's public session type is opaque, but libobjc2 sees the implementation's
     complete struct encoding. Use untyped selectors with the verified pointer
     ABI to avoid false typed-selector mismatch diagnostics. */
  SEL beginSelector = NSSelectorFromString (@"beginModalSessionForWindow:");
  SEL runSelector = NSSelectorFromString (@"runModalSession:");
  SEL endSelector = NSSelectorFromString (@"endModalSession:");
  NSModalSession (*beginSession) (id, SEL, NSWindow *)
      = (void *)[NSApp methodForSelector:beginSelector];
  NSInteger (*runSession) (id, SEL, NSModalSession) = (void *)[NSApp methodForSelector:runSelector];
  void (*endSession) (id, SEL, NSModalSession) = (void *)[NSApp methodForSelector:endSelector];
  NSModalSession session = beginSession (NSApp, beginSelector, panel);
  NSInteger result = NSRunContinuesResponse;
  while ((result = runSession (NSApp, runSelector, session)) == NSRunContinuesResponse)
    [[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
  endSession (NSApp, endSelector, session);
  [panel orderOut:nil];
  return result;
}


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

static NSString *
FVDateString (NSDate *date)
{
  static NSDateFormatter *formatter = nil;
  if (!date)
    return @"Unknown date";
  if (!formatter)
    {
      formatter = [[NSDateFormatter alloc] init];
      [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
      [formatter setDateStyle:NSDateFormatterMediumStyle];
      [formatter setTimeStyle:NSDateFormatterShortStyle];
    }
  return [formatter stringFromDate:date];
}

/* "Folder, 12 items", "Text document, 3.4 KB" */
static NSString *
FVConflictDescription (NSString *path, NSDictionary *attributes)
{
  NSString *type = [attributes fileType];
  if ([type isEqual:NSFileTypeDirectory])
    {
      NSUInteger count = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:path
                                                                              error:NULL] count];
      return [NSString stringWithFormat:count == 1 ? @"Folder, %lu item" : @"Folder, %lu items",
                                        (unsigned long)count];
    }
  if ([type isEqual:NSFileTypeSymbolicLink])
    return @"Symbolic link";
  NSString *extension = [path pathExtension];
  NSString *kind = [extension length]
      ? [NSString stringWithFormat:@"%@ file", [extension uppercaseString]] : @"File";
  return [NSString stringWithFormat:@"%@, %@", kind, FVSizeString ([attributes fileSize])];
}

@implementation FVConflictPanel

/* One side of the comparison: a caption, the icon, then name, kind and size,
   and the modified date, marked when it is the newer of the two. */
- (void)addItem:(NSString *)path
        caption:(NSString *)caption
     attributes:(NSDictionary *)attributes
          newer:(BOOL)newer
              x:(CGFloat)x
{
  NSView *content = [panel contentView];
  NSColor *color = FVDialogTextColor (panel);
  CGFloat width = 252;
  NSFont *small = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  NSTextField *label = FVPanelLabel (NSMakeRect (x, 214, width, 18),
                                     newer ? [caption stringByAppendingString:@" — newer"] : caption,
                                     small);
  [label setTextColor:color];
  [content addSubview:label];
  NSImageView *icon = AUTORELEASE ([[NSImageView alloc] initWithFrame:NSMakeRect (x, 150, 56, 56)]);
  [icon setImage:[[NSWorkspace sharedWorkspace] iconForFile:path]];
  [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
  [icon setEditable:NO];
  [content addSubview:icon];
  CGFloat textX = x + 64, textWidth = width - 64;
  NSTextField *name = FVPanelLabel (NSMakeRect (textX, 186, textWidth, 20), [path lastPathComponent],
                                    [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]);
  [name setTextColor:color];
  [name setToolTip:path];
  [content addSubview:name];
  NSTextField *kind = FVPanelLabel (NSMakeRect (textX, 166, textWidth, 18),
                                    attributes ? FVConflictDescription (path, attributes)
                                               : @"Unavailable",
                                    small);
  [kind setTextColor:color];
  [content addSubview:kind];
  NSString *modified = [NSString stringWithFormat:@"Modified %@",
                                                  FVDateString ([attributes fileModificationDate])];
  NSTextField *date = FVPanelLabel (NSMakeRect (textX, 146, textWidth, 18), modified, small);
  [date setTextColor:color];
  [date setToolTip:modified];
  [content addSubview:date];
}

- (id)initWithSource:(NSString *)source
         destination:(NSString *)destination
                kind:(NSString *)kind
           remaining:(NSUInteger)remaining
{
  if (!(self = [super init]))
    return nil;
  BOOL move = [kind isEqual:@"move"];
  panel = [[FVDialogPanel alloc] initWithContentRect:NSMakeRect (0, 0, 560, 340)
                                           styleMask:NSTitledWindowMask
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
  [panel setTitle:move ? @"Move" : @"Copy"];
  NSView *content = [panel contentView];
  NSColor *color = FVDialogTextColor (panel);
  NSString *folder = [[destination stringByDeletingLastPathComponent] lastPathComponent];
  NSTextField *heading = FVPanelLabel (
      NSMakeRect (20, 278, 520, 44),
      [NSString stringWithFormat:@"An item named “%@” already exists in “%@”.",
                                 [destination lastPathComponent], folder],
      [NSFont boldSystemFontOfSize:15]);
  [[heading cell] setWraps:YES];
  [[heading cell] setLineBreakMode:NSLineBreakByWordWrapping];
  [heading setTextColor:color];
  [content addSubview:heading];
  NSTextField *question = FVPanelLabel (
      NSMakeRect (20, 250, 520, 22),
      [NSString stringWithFormat:@"Do you want to replace it with the one you’re %@?",
                                 move ? @"moving" : @"copying"],
      [NSFont systemFontOfSize:[NSFont systemFontSize]]);
  [question setTextColor:color];
  [content addSubview:question];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDictionary *existing = [fm attributesOfItemAtPath:destination error:NULL];
  NSDictionary *incoming = [fm attributesOfItemAtPath:source error:NULL];
  NSComparisonResult order = existing && incoming
      ? [[existing fileModificationDate] compare:[incoming fileModificationDate]]
      : NSOrderedSame;
  [self addItem:destination
         caption:@"Existing item"
      attributes:existing
           newer:order == NSOrderedDescending
               x:20];
  [self addItem:source
         caption:move ? @"Item you’re moving" : @"Item you’re copying"
      attributes:incoming
           newer:order == NSOrderedAscending
               x:288];
  NSTextField *note = FVPanelLabel (
      NSMakeRect (20, 96, 520, 36),
      @"Replace keeps the old item beside the new one, named “Workspace replaced item…”. "
      @"Folders are replaced, not merged.",
      [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
  [[note cell] setWraps:YES];
  [[note cell] setLineBreakMode:NSLineBreakByWordWrapping];
  [note setTextColor:color];
  [content addSubview:note];
  applyToAll = [[NSButton alloc] initWithFrame:NSMakeRect (18, 62, 260, 24)];
  [applyToAll setButtonType:NSSwitchButton];
  [applyToAll setTitle:[NSString stringWithFormat:@"Apply to all (%lu more %@)",
                                                  (unsigned long)remaining,
                                                  remaining == 1 ? @"item" : @"items"]];
  if (remaining)
    [content addSubview:applyToAll];
  /* Stop on the left; Skip, Keep Both (the default) and Replace on the right. */
  NSArray *titles = [NSArray arrayWithObjects:@"Keep Both", @"Skip", @"Replace", @"Stop", nil];
  CGFloat xs[] = { 330, 228, 442, 20 };
  NSUInteger i;
  for (i = 0; i < [titles count]; i++)
    {
      NSButton *button = AUTORELEASE ([[NSButton alloc]
          initWithFrame:NSMakeRect (xs[i], 18, 98, 30)]);
      [button setTitle:[titles objectAtIndex:i]];
      [button setTag:i];
      [button setTarget:self];
      [button setAction:@selector (choose:)];
      if (i == 0)
        [button setKeyEquivalent:@"\r"];
      else if (i == 3)
        [button setKeyEquivalent:@"\e"];
      [content addSubview:button];
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
  return FVRunModalPanel (panel);
}

- (BOOL)applyToAll
{
  return [applyToAll superview] && [applyToAll state] == NSOnState;
}

- (NSPanel *)panel
{
  return panel;
}

- (void)dealloc
{
  RELEASE (panel);
  RELEASE (applyToAll);
  DEALLOC;
}

@end
