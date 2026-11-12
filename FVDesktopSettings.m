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

#import "FVDesktopSettings.h"
#import <GNUstepGUI/GSTheme.h>

NSString *const FVDesktopSettingsChangedNotification = @"org.nextbsd.DesktopSettingsChanged";

static NSString *const FVMinimizeStyleKey = @"NBMinimizeStyle";
static NSString *const FVDockPositionKey = @"NBDockPosition";
static NSString *const FVMenuStyleKey = @"NBMenuStyle";

/* DockWM keeps its own placement, DockPlacement in its defaults domain, as
   its DockPlacement enumeration: left top, left centre, right top, right
   centre, top, bottom. */
static NSString *const FVDockDomain = @"DockWM";
static NSString *const FVDockPlacementKey = @"DockPlacement";
enum
{
  FVDockLeftTop = 0,
  FVDockLeftCenter,
  FVDockRightTop,
  FVDockRightCenter,
  FVDockTop,
  FVDockBottom
};

/* The settings shown here: their values (in menu order), the titles for
   them, and the built-in default. Window mode (NBWindowMode: stacking,
   tiling) joins this tab once tiling exists. */
static NSArray *
FVAllowedValues (NSString *key)
{
  if ([key isEqual:FVMinimizeStyleKey])
    return [NSArray arrayWithObjects:@"nextstep", @"previews", @"dock", nil];
  if ([key isEqual:FVDockPositionKey])
    return [NSArray arrayWithObjects:@"right", @"left", @"top", @"bottom", nil];
  if ([key isEqual:FVMenuStyleKey])
    return [NSArray arrayWithObjects:@"nextstep", @"inwindow", @"macmenubar", nil];
  return nil;
}

static NSArray *
FVValueTitles (NSString *key)
{
  if ([key isEqual:FVMinimizeStyleKey])
    return [NSArray arrayWithObjects:@"NeXT miniwindows", @"WindowServer previews",
                                     @"Into the Dock", nil];
  if ([key isEqual:FVDockPositionKey])
    return [NSArray arrayWithObjects:@"Right", @"Left", @"Top", @"Bottom", nil];
  if ([key isEqual:FVMenuStyleKey])
    return [NSArray arrayWithObjects:@"NeXT", @"In-window", @"Mac menu bar", nil];
  return nil;
}

static NSString *
FVBuiltinValue (NSString *key)
{
  if ([key isEqual:FVMinimizeStyleKey])
    return @"previews";
  if ([key isEqual:FVDockPositionKey])
    return @"right";
  if ([key isEqual:FVMenuStyleKey])
    return @"nextstep";
  return nil;
}

static NSString *
FVValidValue (id value, NSString *key)
{
  if ([value isKindOfClass:[NSString class]] && [FVAllowedValues (key) containsObject:value])
    return value;
  return nil;
}

static NSString *
FVTitleForValue (NSString *key, NSString *value)
{
  NSUInteger i = [FVAllowedValues (key) indexOfObject:value];
  return i == NSNotFound ? value : [FVValueTitles (key) objectAtIndex:i];
}

@implementation FVDesktopSettings

/* The lookup in nextbsd-theme's NBDesktopSettings.h; keep them in step. */
+ (NSString *)themeDefaultForKey:(NSString *)key
{
  NSString *value = FVValidValue ([[[GSTheme theme] infoDictionary] objectForKey:key], key);
  return value ? value : FVBuiltinValue (key);
}

+ (NSString *)userValueForKey:(NSString *)key
{
  NSDictionary *global = [[NSUserDefaults standardUserDefaults]
      persistentDomainForName:NSGlobalDomain];
  return FVValidValue ([global objectForKey:key], key);
}

+ (NSString *)effectiveValueForKey:(NSString *)key
{
  NSString *value = FVValidValue ([[NSUserDefaults standardUserDefaults] objectForKey:key], key);
  return value ? value : [self themeDefaultForKey:key];
}

static NSTextField *
FVLabel (NSRect frame, NSString *text)
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

- (NSPopUpButton *)popUpForKey:(NSString *)key frame:(NSRect)frame
{
  NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
  [popUp setTarget:self];
  [popUp setAction:@selector (choose:)];
  [popUp setTag:[key isEqual:FVMinimizeStyleKey] ? 1 : [key isEqual:FVDockPositionKey] ? 2 : 3];
  [view addSubview:popUp];
  return popUp;
}

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super init]) == nil)
    return nil;
  view = [[NSView alloc] initWithFrame:frame];
  CGFloat top = NSHeight (frame);
  CGFloat labelWidth = 130;
  CGFloat popUpX = 20 + labelWidth + 8;
  CGFloat popUpWidth = NSWidth (frame) - popUpX - 20;

  NSTextField *label = FVLabel (NSMakeRect (20, top - 49, labelWidth, 22), @"Minimize windows:");
  [label setAlignment:NSRightTextAlignment];
  [view addSubview:label];
  minimizePopUp = [self popUpForKey:FVMinimizeStyleKey
                              frame:NSMakeRect (popUpX, top - 48, popUpWidth, 26)];

  label = FVLabel (NSMakeRect (20, top - 89, labelWidth, 22), @"Dock position:");
  [label setAlignment:NSRightTextAlignment];
  [view addSubview:label];
  dockPopUp = [self popUpForKey:FVDockPositionKey
                          frame:NSMakeRect (popUpX, top - 88, popUpWidth, 26)];

  /* NeXT floating menus with tear-off, a menu in every window, or a Mac
     menu bar along the top; running apps switch at once (the NextBSD
     backend, libs-back#3). */
  label = FVLabel (NSMakeRect (20, top - 129, labelWidth, 22), @"Menu style:");
  [label setAlignment:NSRightTextAlignment];
  [view addSubview:label];
  menuPopUp = [self popUpForKey:FVMenuStyleKey
                          frame:NSMakeRect (popUpX, top - 128, popUpWidth, 26)];

  [view addSubview:FVLabel (NSMakeRect (20, 12, NSWidth (frame) - 40, 36),
                            @"The theme sets the defaults. The menu style changes at once\n"
                            @"in running apps; minimize applies to windows minimized from now on.")];

  /* The theme's defaults show in the "Use theme default" items. */
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector (themeDidActivate:)
                                               name:GSThemeDidActivateNotification
                                             object:nil];
  [self refresh];
  return self;
}

- (NSView *)view
{
  return view;
}

- (NSString *)keyForPopUp:(NSPopUpButton *)popUp
{
  switch ([popUp tag])
    {
    case 1:
      return FVMinimizeStyleKey;
    case 2:
      return FVDockPositionKey;
    default:
      return FVMenuStyleKey;
    }
}

/* "Use theme default (…)" first, then each value. */
- (void)fillPopUp:(NSPopUpButton *)popUp
{
  NSString *key = [self keyForPopUp:popUp];
  NSArray *values = FVAllowedValues (key);
  NSArray *titles = FVValueTitles (key);
  NSString *user = [[self class] userValueForKey:key];
  NSUInteger i;

  [popUp removeAllItems];
  [popUp addItemWithTitle:[NSString stringWithFormat:@"Use theme default (%@)",
      FVTitleForValue (key, [[self class] themeDefaultForKey:key])]];
  [[popUp lastItem] setRepresentedObject:nil];
  for (i = 0; i < [values count]; i++)
    {
      [popUp addItemWithTitle:[titles objectAtIndex:i]];
      [[popUp lastItem] setRepresentedObject:[values objectAtIndex:i]];
    }
  i = user ? [values indexOfObject:user] : NSNotFound;
  [popUp selectItemAtIndex:i == NSNotFound ? 0 : (NSInteger)i + 1];
}

- (void)refresh
{
  [[NSUserDefaults standardUserDefaults] synchronize];
  [self fillPopUp:minimizePopUp];
  [self fillPopUp:dockPopUp];
  [self fillPopUp:menuPopUp];
}

- (void)themeDidActivate:(NSNotification *)note
{
  [self refresh];
}

/* Tell the Dock where to go: DockWM reads DockPlacement. Keep its
   centring along the left and right edges. */
- (void)updateDockPlacement:(NSString *)position
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *dock = AUTORELEASE ([[defaults persistentDomainForName:FVDockDomain]
      mutableCopy]);
  if (dock == nil)
    dock = [NSMutableDictionary dictionary];
  id old = [dock objectForKey:FVDockPlacementKey];
  BOOL centred = [old respondsToSelector:@selector (integerValue)]
      && ([old integerValue] == FVDockLeftCenter || [old integerValue] == FVDockRightCenter);
  NSInteger placement;
  if ([position isEqual:@"left"])
    placement = centred ? FVDockLeftCenter : FVDockLeftTop;
  else if ([position isEqual:@"top"])
    placement = FVDockTop;
  else if ([position isEqual:@"bottom"])
    placement = FVDockBottom;
  else
    placement = centred ? FVDockRightCenter : FVDockRightTop;
  [dock setObject:[NSNumber numberWithInteger:placement] forKey:FVDockPlacementKey];
  [defaults setPersistentDomain:dock forName:FVDockDomain];
}

- (void)choose:(id)sender
{
  NSString *key = [self keyForPopUp:sender];
  NSString *value = [[sender selectedItem] representedObject];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *global = AUTORELEASE ([[defaults persistentDomainForName:NSGlobalDomain]
      mutableCopy]);

  if (global == nil)
    global = [NSMutableDictionary dictionary];
  if (value)
    [global setObject:value forKey:key];
  else
    [global removeObjectForKey:key];
  [defaults setPersistentDomain:global forName:NSGlobalDomain];

  NSString *effective = [[self class] effectiveValueForKey:key];
  if ([key isEqual:FVDockPositionKey])
    [self updateDockPlacement:effective];
  [defaults synchronize];

  NS_DURING
    {
      [[NSDistributedNotificationCenter defaultCenter]
          postNotificationName:FVDesktopSettingsChangedNotification
                        object:nil
                      userInfo:[NSDictionary dictionaryWithObjectsAndKeys:key, @"key",
                                                                          effective, @"value", nil]
            deliverImmediately:YES];
    }
  NS_HANDLER
    {
      NSLog (@"Workspace: can't post %@: %@", FVDesktopSettingsChangedNotification,
             [localException reason]);
    }
  NS_ENDHANDLER
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (minimizePopUp);
  RELEASE (dockPopUp);
  RELEASE (menuPopUp);
  RELEASE (view);
  DEALLOC;
}

@end
