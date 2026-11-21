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

#import "FVBackgroundSettings.h"
#import "FVBackground.h"

/* Seconds between frames: the slider's ends, and the background's
   default (InnerSpace's). Modules that need a pace of their own keep it. */
static const double FVFastestFrames = 0.01;
static const double FVSlowestFrames = 0.5;
static const double FVDefaultFrames = 0.1;

static NSTextField *
FVBackgroundLabel (NSRect frame, NSString *text)
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

@implementation FVBackgroundSettings

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super init]) == nil)
    return nil;
  view = [[NSView alloc] initWithFrame:frame];
  CGFloat top = NSHeight (frame) - 20;

  [view addSubview:FVBackgroundLabel (NSMakeRect (20, top - 22, 220, 22),
                                      @"Desktop background:")];
  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc]
      initWithFrame:NSMakeRect (20, 56, 220, top - 22 - 56 - 4)]);
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  moduleTable = [[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]];
  NSTableColumn *column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier:@"name"]);
  [column setWidth:NSWidth ([[scroll contentView] bounds])];
  [column setEditable:NO];
  [moduleTable addTableColumn:column];
  [moduleTable setHeaderView:nil];
  [moduleTable setAllowsEmptySelection:NO];
  [moduleTable setDataSource:self];
  [moduleTable setDelegate:self];
  [scroll setDocumentView:moduleTable];
  [view addSubview:scroll];

  CGFloat x = 262, width = NSWidth (frame) - x - 20;
  [view addSubview:FVBackgroundLabel (NSMakeRect (x, top - 22, width, 22), @"Speed:")];
  speedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect (x, top - 50, width, 22)];
  /* Faster to the right: the slider runs over the negated delay. */
  [speedSlider setMinValue:-FVSlowestFrames];
  [speedSlider setMaxValue:-FVFastestFrames];
  [speedSlider setTarget:self];
  [speedSlider setAction:@selector (chooseSpeed:)];
  [view addSubview:speedSlider];
  [view addSubview:FVBackgroundLabel (NSMakeRect (x, top - 72, 60, 18), @"Slow")];
  NSTextField *fast = FVBackgroundLabel (NSMakeRect (x + width - 60, top - 72, 60, 18), @"Fast");
  [fast setAlignment:NSRightTextAlignment];
  [view addSubview:fast];

  everyDisplayCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect (x, top - 112, width, 24)];
  [everyDisplayCheckbox setButtonType:NSSwitchButton];
  [everyDisplayCheckbox setTitle:@"Show on every display"];
  [everyDisplayCheckbox setTarget:self];
  [everyDisplayCheckbox setAction:@selector (chooseEveryDisplay:)];
  [view addSubview:everyDisplayCheckbox];

  optionsButton = [[NSButton alloc] initWithFrame:NSMakeRect (x, top - 152, 140, 28)];
  [optionsButton setTitle:@"Options…"];
  [optionsButton setTarget:self];
  [optionsButton setAction:@selector (showOptions:)];
  [view addSubview:optionsButton];

  [view addSubview:FVBackgroundLabel (NSMakeRect (20, 8, NSWidth (frame) - 40, 36),
                                      @"Backgrounds are InnerSpace modules, installed in\n"
                                      @"Library/InnerSpace. Changes apply at once.")];
  return self;
}

- (NSView *)view
{
  return view;
}

- (void)refresh
{
  /* Showing the saved module selects its row: that's no choice to save. */
  refreshing = YES;
  ASSIGN (modules, [FVBackground moduleNames]);
  [moduleTable reloadData];
  NSString *current = [FVBackground settingForKey:@"currentModule"];
  NSUInteger row = [modules indexOfObject:current ? current : @"Black"];
  if (row != NSNotFound)
    {
      [moduleTable selectRow:row byExtendingSelection:NO];
      [moduleTable scrollRowToVisible:row];
    }
  id speed = [FVBackground settingForKey:@"runSpeed"];
  [speedSlider setDoubleValue:-(speed ? [speed doubleValue] : FVDefaultFrames)];
  id everywhere = [FVBackground settingForKey:@"moduleOnEveryDisplay"];
  [everyDisplayCheckbox setState:(everywhere == nil || [everywhere boolValue]) ? NSOnState
                                                                               : NSOffState];
  refreshing = NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return [modules count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  return [modules objectAtIndex:row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
  NSInteger row = [moduleTable selectedRow];
  if (refreshing || row < 0 || row >= (NSInteger)[modules count])
    return;
  NSString *module = [modules objectAtIndex:row];
  if (![module isEqual:[FVBackground settingForKey:@"currentModule"]])
    [FVBackground setSetting:module forKey:@"currentModule"];
}

- (void)chooseSpeed:(id)sender
{
  [FVBackground setSetting:[NSNumber numberWithFloat:-[sender doubleValue]]
                    forKey:@"runSpeed"];
}

- (void)chooseEveryDisplay:(id)sender
{
  [FVBackground setSetting:[NSNumber numberWithBool:[sender state] == NSOnState]
                    forKey:@"moduleOnEveryDisplay"];
}

- (void)showOptions:(id)sender
{
  [FVBackground showOptions];
}

- (void)dealloc
{
  RELEASE (moduleTable);
  RELEASE (speedSlider);
  RELEASE (everyDisplayCheckbox);
  RELEASE (optionsButton);
  RELEASE (modules);
  RELEASE (view);
  DEALLOC;
}

@end
