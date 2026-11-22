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

#import "FVDockSettings.h"
#import "FVBackground.h"

static NSString *const FVDockDomain = @"Dock";
static NSString *const FVSettingsChangedNotification = @"org.nextbsd.SettingsChanged";
/* The Dock's extras (apps-dock DockExtrasSettings.h). */
static NSString *const FVExtrasHiddenKey = @"DockExtrasHidden";
static NSString *const FVSetExtraHiddenNotification = @"org.nextbsd.Dock.SetExtraHidden";
static NSString *const FVExtrasChangedNotification = @"org.nextbsd.Dock.ExtrasChanged";

/* The Dock's keys (apps-dock DockPreferences.m). */
static NSString *const FVDockScaleKey = @"DockScale";
static NSString *const FVMagnifyKey = @"DockMagnifiesHoveredIcons";
static NSString *const FVHoverScaleKey = @"DockHoverIconScale";
static NSString *const FVDotsKey = @"DockRunningIndicatorMode";
static NSString *const FVBounceLaunchKey = @"DockWigglesOnLaunch";
static NSString *const FVBounceAttentionKey = @"DockWigglesOnAttentionRequest";
static NSString *const FVSingleClickKey = @"DockSingleClickLaunchesApplications";

/* The Dock's defaults for what it hasn't saved. */
static NSDictionary *
FVDockDefaults (void)
{
  static NSDictionary *defaults;
  if (defaults == nil)
    defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSNumber numberWithFloat:1.0], FVDockScaleKey,
        [NSNumber numberWithBool:NO], FVMagnifyKey,
        [NSNumber numberWithFloat:1.2], FVHoverScaleKey,
        [NSNumber numberWithInt:0], FVDotsKey,
        [NSNumber numberWithBool:YES], FVBounceLaunchKey,
        [NSNumber numberWithBool:YES], FVBounceAttentionKey,
        [NSNumber numberWithBool:NO], FVSingleClickKey,
        [NSArray array], FVExtrasHiddenKey, nil];
  return defaults;
}

/* The extras that ship with the Dock, in its order. */
static NSArray *
FVExtras (void)
{
  return [NSArray arrayWithObjects:
      [NSArray arrayWithObjects:@"org.nextbsd.dockextra.wifi", @"Wi-Fi", nil],
      [NSArray arrayWithObjects:@"org.nextbsd.dockextra.bluetooth", @"Bluetooth", nil],
      [NSArray arrayWithObjects:@"org.nextbsd.dockextra.battery", @"Battery", nil],
      [NSArray arrayWithObjects:@"org.nextbsd.dockextra.sound", @"Sound", nil],
      [NSArray arrayWithObjects:@"org.nextbsd.dockextra.input", @"Input source", nil],
      [NSArray arrayWithObjects:@"org.nextbsd.dockextra.clock", @"Clock", nil], nil];
}

static NSTextField *
FVDockLabel (NSRect frame, NSString *text)
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

@implementation FVDockSettings

+ (id)dockValueForKey:(NSString *)key
{
  id value = [FVDefaultsDomainOnDisk (FVDockDomain) objectForKey:key];
  return value ? value : [FVDockDefaults () objectForKey:key];
}

/* A running Dock answers to its name (every GNUstep app registers it). */
+ (BOOL)dockIsRunning
{
  return [NSConnection connectionWithRegisteredName:FVDockDomain host:@""] != nil;
}

/* The Dock saves its whole domain (its kept apps too), so while it runs
   only it writes there: it's told, and saves what it applies. */
+ (void)saveDockValues:(NSDictionary *)values
{
  if ([self dockIsRunning])
    return;
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *dock =
      [NSMutableDictionary dictionaryWithDictionary:FVDefaultsDomainOnDisk (FVDockDomain)];
  [dock addEntriesFromDictionary:values];
  [defaults setPersistentDomain:dock forName:FVDockDomain];
  [defaults synchronize];
}

+ (void)setDockValues:(NSDictionary *)values
{
  [self saveDockValues:values];
  /* The values go along: the Dock may not read back what another
     process saved in its domain. */
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:FVSettingsChangedNotification
                    object:nil
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:FVDockDomain, @"domain",
                                                                      [values allKeys], @"keys",
                                                                      values, @"values", nil]
        deliverImmediately:YES];
}

- (NSButton *)checkboxWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action
{
  NSButton *box = [[NSButton alloc] initWithFrame:frame];
  [box setButtonType:NSSwitchButton];
  [box setTitle:title];
  [box setTarget:self];
  [box setAction:action];
  [view addSubview:box];
  return box;
}

- (NSSlider *)sliderWithFrame:(NSRect)frame min:(double)min max:(double)max
{
  NSSlider *slider = [[NSSlider alloc] initWithFrame:frame];
  [slider setMinValue:min];
  [slider setMaxValue:max];
  [slider setTarget:self];
  [slider setAction:@selector (choose:)];
  [view addSubview:slider];
  return slider;
}

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super init]) == nil)
    return nil;
  view = [[NSView alloc] initWithFrame:frame];
  CGFloat y = NSHeight (frame) - 46;
  CGFloat x = 176, width = NSWidth (frame) - x - 20;

  NSTextField *label = FVDockLabel (NSMakeRect (20, y, 148, 22), @"Size:");
  [label setAlignment:NSRightTextAlignment];
  [view addSubview:label];
  sizeSlider = [self sliderWithFrame:NSMakeRect (x, y, width, 22) min:0.5 max:1.5];
  [view addSubview:FVDockLabel (NSMakeRect (x, y - 18, 60, 18), @"Small")];
  NSTextField *large = FVDockLabel (NSMakeRect (x + width - 60, y - 18, 60, 18), @"Large");
  [large setAlignment:NSRightTextAlignment];
  [view addSubview:large];

  y -= 52;
  magnifyCheckbox = [self checkboxWithTitle:@"Magnification:"
                                      frame:NSMakeRect (20, y, 150, 24)
                                     action:@selector (choose:)];
  magnifySlider = [self sliderWithFrame:NSMakeRect (x, y, width, 22) min:1.0 max:1.5];

  y -= 40;
  label = FVDockLabel (NSMakeRect (20, y - 1, 148, 22), @"Dots:");
  [label setAlignment:NSRightTextAlignment];
  [view addSubview:label];
  dotsPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (x, y, width, 26) pullsDown:NO];
  [dotsPopUp addItemWithTitle:@"Under open applications"];
  [dotsPopUp addItemWithTitle:@"Under applications not open"];
  [dotsPopUp setTarget:self];
  [dotsPopUp setAction:@selector (choose:)];
  [view addSubview:dotsPopUp];

  y -= 36;
  bounceLaunchCheckbox = [self checkboxWithTitle:@"Animate opening applications"
                                           frame:NSMakeRect (x, y, width, 24)
                                          action:@selector (choose:)];
  y -= 28;
  bounceAttentionCheckbox = [self checkboxWithTitle:@"Bounce when an application needs attention"
                                              frame:NSMakeRect (x, y, width, 24)
                                             action:@selector (choose:)];
  y -= 28;
  singleClickCheckbox = [self checkboxWithTitle:@"Open applications with a single click"
                                          frame:NSMakeRect (x, y, width, 24)
                                         action:@selector (choose:)];

  /* Status extras: in the Dock, or in the menu bar in the Mac menu style. */
  y -= 40;
  NSTextField *heading = FVDockLabel (NSMakeRect (20, y, 300, 22), @"Status extras");
  [heading setFont:[NSFont boldSystemFontOfSize:0]];
  [view addSubview:heading];
  y -= 24;
  [view addSubview:FVDockLabel (NSMakeRect (20, y, NSWidth (frame) - 40, 22),
                                @"Show in the Dock or menu bar:")];
  extraCheckboxes = [[NSMutableArray alloc] init];
  NSArray *extras = FVExtras ();
  NSUInteger i, rows = ([extras count] + 1) / 2;
  CGFloat column = (NSWidth (frame) - 40) / 2;
  for (i = 0; i < [extras count]; i++)
    {
      NSArray *extra = [extras objectAtIndex:i];
      NSRect box = NSMakeRect (40 + (i / rows) * column, y - 26 * (i % rows + 1), column - 20, 24);
      NSButton *checkbox = [self checkboxWithTitle:[extra objectAtIndex:1]
                                             frame:box
                                            action:@selector (chooseExtra:)];
      [checkbox setTag:i];
      [extraCheckboxes addObject:checkbox];
      RELEASE (checkbox);
    }

  /* The Dock answers every change to its extras, its own included. */
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (extrasDidChange:)
             name:FVExtrasChangedNotification
           object:nil];
  [self refresh];
  return self;
}

- (NSView *)view
{
  return view;
}

- (void)showHiddenExtras:(NSArray *)hidden
{
  NSEnumerator *e = [extraCheckboxes objectEnumerator];
  NSButton *checkbox;
  while ((checkbox = [e nextObject]) != nil)
    [checkbox setState:[hidden containsObject:[[FVExtras () objectAtIndex:[checkbox tag]]
                                                  objectAtIndex:0]]
                           ? NSOffState
                           : NSOnState];
}

- (void)refresh
{
  Class c = [self class];
  [sizeSlider setDoubleValue:[[c dockValueForKey:FVDockScaleKey] doubleValue]];
  BOOL magnifies = [[c dockValueForKey:FVMagnifyKey] boolValue];
  [magnifyCheckbox setState:magnifies ? NSOnState : NSOffState];
  [magnifySlider setDoubleValue:[[c dockValueForKey:FVHoverScaleKey] doubleValue]];
  [magnifySlider setEnabled:magnifies];
  [dotsPopUp selectItemAtIndex:[[c dockValueForKey:FVDotsKey] intValue] == 1 ? 1 : 0];
  [bounceLaunchCheckbox setState:[[c dockValueForKey:FVBounceLaunchKey] boolValue] ? NSOnState
                                                                                   : NSOffState];
  [bounceAttentionCheckbox setState:[[c dockValueForKey:FVBounceAttentionKey] boolValue]
                                        ? NSOnState
                                        : NSOffState];
  [singleClickCheckbox setState:[[c dockValueForKey:FVSingleClickKey] boolValue] ? NSOnState
                                                                                 : NSOffState];
  [self showHiddenExtras:[c dockValueForKey:FVExtrasHiddenKey]];
}

- (void)choose:(id)sender
{
  NSString *key = nil;
  id value = nil;
  if (sender == sizeSlider)
    key = FVDockScaleKey, value = [NSNumber numberWithFloat:[sender floatValue]];
  else if (sender == magnifyCheckbox)
    {
      key = FVMagnifyKey, value = [NSNumber numberWithBool:[sender state] == NSOnState];
      [magnifySlider setEnabled:[sender state] == NSOnState];
    }
  else if (sender == magnifySlider)
    key = FVHoverScaleKey, value = [NSNumber numberWithFloat:[sender floatValue]];
  else if (sender == dotsPopUp)
    key = FVDotsKey, value = [NSNumber numberWithInt:[sender indexOfSelectedItem]];
  else if (sender == bounceLaunchCheckbox)
    key = FVBounceLaunchKey, value = [NSNumber numberWithBool:[sender state] == NSOnState];
  else if (sender == bounceAttentionCheckbox)
    key = FVBounceAttentionKey, value = [NSNumber numberWithBool:[sender state] == NSOnState];
  else if (sender == singleClickCheckbox)
    key = FVSingleClickKey, value = [NSNumber numberWithBool:[sender state] == NSOnState];
  if (key)
    [[self class] setDockValues:[NSDictionary dictionaryWithObject:value forKey:key]];
}

/* Ask the Dock, which owns the list; with no Dock running, the list is
   saved here and read when the Dock starts. */
- (void)chooseExtra:(id)sender
{
  BOOL hidden = [sender state] != NSOnState;
  NSString *identifier = [[FVExtras () objectAtIndex:[sender tag]] objectAtIndex:0];
  NSMutableArray *list = [NSMutableArray arrayWithArray:
      [[self class] dockValueForKey:FVExtrasHiddenKey]];
  [list removeObject:identifier];
  if (hidden)
    [list addObject:identifier];
  [[self class] saveDockValues:[NSDictionary dictionaryWithObject:list forKey:FVExtrasHiddenKey]];
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:FVSetExtraHiddenNotification
                    object:nil
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:identifier, @"identifier",
                                                                      [NSNumber numberWithBool:hidden],
                                                                      @"hidden", nil]
        deliverImmediately:YES];
}

- (void)extrasDidChange:(NSNotification *)note
{
  id hidden = [[note userInfo] objectForKey:@"hidden"];
  if ([hidden isKindOfClass:[NSArray class]])
    [self showHiddenExtras:hidden];
}

- (void)dealloc
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (sizeSlider);
  RELEASE (magnifyCheckbox);
  RELEASE (magnifySlider);
  RELEASE (dotsPopUp);
  RELEASE (bounceLaunchCheckbox);
  RELEASE (bounceAttentionCheckbox);
  RELEASE (singleClickCheckbox);
  RELEASE (extraCheckboxes);
  RELEASE (view);
  DEALLOC;
}

@end
