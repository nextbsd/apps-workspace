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

/* libs-gui's current display server (GSDisplayServer.h, whose header
   doesn't build cleanly with -Wextra). */
@class GSDisplayServer;
APPKIT_EXPORT GSDisplayServer *GSCurrentServer (void);

NSString *const FVDesktopSettingsChangedNotification = @"org.nextbsd.DesktopSettingsChanged";

static NSString *const FVMinimizeStyleKey = @"NBMinimizeStyle";
static NSString *const FVDockPositionKey = @"NBDockPosition";
static NSString *const FVMenuStyleKey = @"NBMenuStyle";
static NSString *const FVWindowModeKey = @"NBWindowMode";

/* The per-mode dictionaries, { stacking = {...}; tiling = {...}; }: the
   user's in NSGlobalDomain, the theme's in its Info.plist. */
static NSString *const FVModeSettingsKey = @"NBModeSettings";
static NSString *const FVModeDefaultsKey = @"NBModeDefaults";

/* WindowServer's settings: its defaults domain and the tiling keys. */
static NSString *const FVWindowServerDomain = @"org.nextbsd.WindowServer";
static NSString *const FVWSWindowModeKey = @"WindowMode";
static NSString *const FVWSLayoutKey = @"TilingLayout";
static NSString *const FVWSInnerGapKey = @"TilingGapsInner";
static NSString *const FVWSOuterGapKey = @"TilingGapsOuter";
static NSString *const FVWSBorderKey = @"TilingBorder";

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

/* The pop-up tags. */
enum
{
  FVTagMinimize = 1,
  FVTagDock,
  FVTagMenu,
  FVTagMode,
  FVTagLayout,
  FVTagInnerGap,
  FVTagOuterGap
};

/* The settings shown here: their values (in menu order), the titles for
   them, and the built-in default. */
static NSArray *
FVAllowedValues (NSString *key)
{
  if ([key isEqual:FVMinimizeStyleKey])
    return [NSArray arrayWithObjects:@"nextstep", @"previews", @"dock", nil];
  if ([key isEqual:FVDockPositionKey])
    return [NSArray arrayWithObjects:@"right", @"left", @"top", @"bottom", nil];
  if ([key isEqual:FVMenuStyleKey])
    return [NSArray arrayWithObjects:@"nextstep", @"inwindow", @"macmenubar", nil];
  if ([key isEqual:FVWindowModeKey])
    return [NSArray arrayWithObjects:@"stacking", @"tiling", nil];
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
  if ([key isEqual:FVWindowModeKey])
    return [NSArray arrayWithObjects:@"Stacking", @"Tiling", nil];
  return nil;
}

static NSString *
FVBuiltinValue (NSString *key)
{
  if ([key isEqual:FVMinimizeStyleKey])
    return @"dock";
  if ([key isEqual:FVDockPositionKey])
    return @"right";
  if ([key isEqual:FVMenuStyleKey])
    return @"nextstep";
  if ([key isEqual:FVWindowModeKey])
    return @"stacking";
  return nil;
}

static BOOL
FVIsPerMode (NSString *key)
{
  return [key isEqual:FVDockPositionKey] || [key isEqual:FVMenuStyleKey];
}

static NSString *
FVValidValue (id value, NSString *key)
{
  if ([value isKindOfClass:[NSString class]] && [FVAllowedValues (key) containsObject:value])
    return value;
  return nil;
}

/* modes[mode][key], when both are dictionaries. */
static id
FVModeValue (id modes, NSString *mode, NSString *key)
{
  if (![modes isKindOfClass:[NSDictionary class]])
    return nil;
  id entry = [modes objectForKey:mode];
  return [entry isKindOfClass:[NSDictionary class]] ? [entry objectForKey:key] : nil;
}

static NSString *
FVTitleForValue (NSString *key, NSString *value)
{
  NSUInteger i = [FVAllowedValues (key) indexOfObject:value];
  return i == NSNotFound ? value : [FVValueTitles (key) objectAtIndex:i];
}

/* The tiling settings' choices: WindowServer's values and their titles. */
static NSArray *
FVGapValues (void)
{
  return [NSArray arrayWithObjects:@"0", @"4", @"8", @"12", @"16", @"24", @"32", nil];
}

@implementation FVDesktopSettings

/*
 * The lookup in nextbsd-theme's NBDesktopSettings.h; keep them in step.
 * The theme's default for a mode: NBModeDefaults[mode] (Dock position and
 * menu style only), then the plain key, then the built-in value.
 */
+ (NSString *)themeDefaultForKey:(NSString *)key mode:(NSString *)mode
{
  NSDictionary *info = [[GSTheme theme] infoDictionary];
  NSString *value = nil;
  if (FVIsPerMode (key))
    value = FVValidValue (FVModeValue ([info objectForKey:FVModeDefaultsKey], mode, key), key);
  if (value == nil)
    value = FVValidValue ([info objectForKey:key], key);
  return value ? value : FVBuiltinValue (key);
}

/* The user's choice for a mode, as saved (NSGlobalDomain), or nil. In
   stacking, a plain key from before the settings were kept per mode
   counts. */
+ (NSString *)userValueForKey:(NSString *)key mode:(NSString *)mode
{
  NSDictionary *global = [[NSUserDefaults standardUserDefaults]
      persistentDomainForName:NSGlobalDomain];
  if (!FVIsPerMode (key))
    return FVValidValue ([global objectForKey:key], key);
  NSString *value = FVValidValue (FVModeValue ([global objectForKey:FVModeSettingsKey], mode, key),
                                  key);
  if (value == nil && [mode isEqual:@"stacking"])
    value = FVValidValue ([global objectForKey:key], key);
  return value;
}

+ (NSString *)windowMode
{
  NSString *mode = FVValidValue (
      [[NSUserDefaults standardUserDefaults] objectForKey:FVWindowModeKey], FVWindowModeKey);
  return mode ? mode : [self themeDefaultForKey:FVWindowModeKey mode:nil];
}

+ (NSString *)effectiveValueForKey:(NSString *)key mode:(NSString *)mode
{
  NSString *value;
  if (FVIsPerMode (key))
    value = [self userValueForKey:key mode:mode];
  else
    value = FVValidValue ([[NSUserDefaults standardUserDefaults] objectForKey:key], key);
  return value ? value : [self themeDefaultForKey:key mode:mode];
}

+ (NSString *)themeDefaultForKey:(NSString *)key
{
  return [self themeDefaultForKey:key mode:[self windowMode]];
}

+ (NSString *)userValueForKey:(NSString *)key
{
  return [self userValueForKey:key mode:[self windowMode]];
}

+ (NSString *)effectiveValueForKey:(NSString *)key
{
  if ([key isEqual:FVWindowModeKey])
    return [self windowMode];
  return [self effectiveValueForKey:key mode:[self windowMode]];
}

/* ---- WindowServer ---- */

+ (NSDictionary *)windowServerDefaults
{
  return [[NSUserDefaults standardUserDefaults] persistentDomainForName:FVWindowServerDomain];
}

/* A tiling setting as saved, else WindowServer's built-in value. */
+ (NSString *)windowServerValueForKey:(NSString *)key
{
  id value = [[self windowServerDefaults] objectForKey:key];
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]])
    return [value description];
  if ([key isEqual:FVWSLayoutKey])
    return @"dwindle";
  if ([key isEqual:FVWSBorderKey])
    return @"2";
  if ([key isEqual:FVWSWindowModeKey])
    return @"stacking";
  return @"8"; /* the gaps */
}

/*
 * Keep WindowServer settings in the user's org.nextbsd.WindowServer
 * defaults (the next login sends them) and send them to WindowServer now,
 * through the NextBSD backend (-[NextBSDServer setWindowServerSettings:]).
 * Other backends (X11) only keep them.
 */
+ (void)setWindowServerSettings:(NSDictionary *)settings
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *domain = AUTORELEASE ([[self windowServerDefaults] mutableCopy]);
  if (domain == nil)
    domain = [NSMutableDictionary dictionary];
  [domain addEntriesFromDictionary:settings];
  [defaults setPersistentDomain:domain forName:FVWindowServerDomain];
  [defaults synchronize];

  id server = (id)GSCurrentServer ();
  SEL sel = @selector (setWindowServerSettings:);
  if ([server respondsToSelector:sel])
    [server performSelector:sel withObject:settings];
}

+ (void)syncWindowServer
{
  NSString *mode = [self windowMode];
  if (![[self windowServerValueForKey:FVWSWindowModeKey] isEqual:mode])
    [self setWindowServerSettings:[NSDictionary dictionaryWithObject:mode
                                                              forKey:FVWSWindowModeKey]];
}

/* ---- the tab ---- */

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

- (NSPopUpButton *)popUpWithTag:(NSInteger)tag
                          label:(NSString *)title
                            row:(CGFloat)y
                         action:(SEL)action
{
  NSRect frame = [view frame];
  CGFloat labelWidth = 150;
  CGFloat popUpX = 20 + labelWidth + 8;
  NSTextField *label = FVLabel (NSMakeRect (20, y - 1, labelWidth, 22), title);
  [label setAlignment:NSRightTextAlignment];
  [view addSubview:label];

  NSPopUpButton *popUp = [[NSPopUpButton alloc]
      initWithFrame:NSMakeRect (popUpX, y, NSWidth (frame) - popUpX - 20, 26)
          pullsDown:NO];
  [popUp setTarget:self];
  [popUp setAction:action];
  [popUp setTag:tag];
  [view addSubview:popUp];
  return popUp;
}

- (NSPopUpButton *)popUpForKey:(NSString *)key label:(NSString *)title row:(CGFloat)y
{
  NSInteger tag = [key isEqual:FVMinimizeStyleKey] ? FVTagMinimize
                  : [key isEqual:FVDockPositionKey] ? FVTagDock
                  : [key isEqual:FVMenuStyleKey]    ? FVTagMenu
                                                    : FVTagMode;
  return [self popUpWithTag:tag label:title row:y action:@selector (choose:)];
}

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super init]) == nil)
    return nil;
  view = [[NSView alloc] initWithFrame:frame];
  CGFloat y = NSHeight (frame) - 46;
  CGFloat step = 34;

  /* Stacking (floating windows, NeXT menus) or tiling (WindowServer lays
     the windows out side by side); each mode keeps its own Dock position
     and menu style. */
  modePopUp = [self popUpForKey:FVWindowModeKey label:@"Window mode:" row:y];
  y -= step;
  dockPopUp = [self popUpForKey:FVDockPositionKey label:@"Dock position:" row:y];
  y -= step;
  /* NeXT floating menus with tear-off, a menu in every window, or a Mac
     menu bar along the top; running apps switch at once (the NextBSD
     backend, libs-back#3). */
  menuPopUp = [self popUpForKey:FVMenuStyleKey label:@"Menu style:" row:y];
  y -= step;
  minimizePopUp = [self popUpForKey:FVMinimizeStyleKey label:@"Minimize windows:" row:y];

  /* Tiling: WindowServer's own settings (apps-windowserver, "Window
     tiling"), used in the tiling mode. */
  y -= step + 6;
  NSTextField *heading = FVLabel (NSMakeRect (20, y, 300, 22), @"Tiling");
  [heading setFont:[NSFont boldSystemFontOfSize:0]];
  [view addSubview:heading];
  y -= step - 4;
  layoutPopUp = [self popUpWithTag:FVTagLayout
                             label:@"Layout:"
                               row:y
                            action:@selector (chooseTiling:)];
  [layoutPopUp addItemWithTitle:@"Dwindle"];
  [[layoutPopUp lastItem] setRepresentedObject:@"dwindle"];
  [layoutPopUp addItemWithTitle:@"Master and stack"];
  [[layoutPopUp lastItem] setRepresentedObject:@"master"];
  y -= step;
  innerGapPopUp = [self popUpWithTag:FVTagInnerGap
                               label:@"Gap between windows:"
                                 row:y
                              action:@selector (chooseTiling:)];
  y -= step;
  outerGapPopUp = [self popUpWithTag:FVTagOuterGap
                               label:@"Gap around windows:"
                                 row:y
                              action:@selector (chooseTiling:)];
  NSEnumerator *e = [FVGapValues () objectEnumerator];
  NSString *gap;
  while ((gap = [e nextObject]) != nil)
    {
      NSString *title = [gap isEqual:@"0"] ? @"None" : [NSString stringWithFormat:@"%@ pixels", gap];
      [innerGapPopUp addItemWithTitle:title];
      [[innerGapPopUp lastItem] setRepresentedObject:gap];
      [outerGapPopUp addItemWithTitle:title];
      [[outerGapPopUp lastItem] setRepresentedObject:gap];
    }
  y -= step;
  borderCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect (176, y, 300, 24)];
  [borderCheckbox setButtonType:NSSwitchButton];
  [borderCheckbox setTitle:@"Border around the active window"];
  [borderCheckbox setTarget:self];
  [borderCheckbox setAction:@selector (chooseTiling:)];
  [view addSubview:borderCheckbox];
  tilingControls = [[NSArray alloc]
      initWithObjects:layoutPopUp, innerGapPopUp, outerGapPopUp, borderCheckbox, nil];

  [view addSubview:FVLabel (NSMakeRect (20, 8, NSWidth (frame) - 40, 36),
                            @"The theme sets the defaults. Stacking and tiling each keep\n"
                            @"their own Dock position and menu style; changes apply at once.")];

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
    case FVTagMinimize:
      return FVMinimizeStyleKey;
    case FVTagDock:
      return FVDockPositionKey;
    case FVTagMode:
      return FVWindowModeKey;
    default:
      return FVMenuStyleKey;
    }
}

/* "Use theme default (…)" first, then each value; the Dock position and
   menu style for the current window mode. */
- (void)fillPopUp:(NSPopUpButton *)popUp
{
  NSString *key = [self keyForPopUp:popUp];
  NSString *mode = [[self class] windowMode];
  NSArray *values = FVAllowedValues (key);
  NSArray *titles = FVValueTitles (key);
  NSString *user = [[self class] userValueForKey:key mode:mode];
  NSUInteger i;

  [popUp removeAllItems];
  [popUp addItemWithTitle:[NSString stringWithFormat:@"Use theme default (%@)",
      FVTitleForValue (key, [[self class] themeDefaultForKey:key mode:mode])]];
  [[popUp lastItem] setRepresentedObject:nil];
  for (i = 0; i < [values count]; i++)
    {
      [popUp addItemWithTitle:[titles objectAtIndex:i]];
      [[popUp lastItem] setRepresentedObject:[values objectAtIndex:i]];
    }
  i = user ? [values indexOfObject:user] : NSNotFound;
  [popUp selectItemAtIndex:i == NSNotFound ? 0 : (NSInteger)i + 1];
}

- (void)selectValue:(NSString *)value inPopUp:(NSPopUpButton *)popUp
{
  NSInteger i = [popUp indexOfItemWithRepresentedObject:value];
  if (i < 0)
    {
      /* A value set elsewhere (wsctl, a plist): show it as it is. */
      [popUp addItemWithTitle:[NSString stringWithFormat:@"%@ pixels", value]];
      [[popUp lastItem] setRepresentedObject:value];
      i = [popUp numberOfItems] - 1;
    }
  [popUp selectItemAtIndex:i];
}

- (void)refresh
{
  [[NSUserDefaults standardUserDefaults] synchronize];
  [self fillPopUp:modePopUp];
  [self fillPopUp:dockPopUp];
  [self fillPopUp:menuPopUp];
  [self fillPopUp:minimizePopUp];

  [self selectValue:[[self class] windowServerValueForKey:FVWSLayoutKey] inPopUp:layoutPopUp];
  [self selectValue:[[self class] windowServerValueForKey:FVWSInnerGapKey] inPopUp:innerGapPopUp];
  [self selectValue:[[self class] windowServerValueForKey:FVWSOuterGapKey] inPopUp:outerGapPopUp];
  [borderCheckbox setState:[[[self class] windowServerValueForKey:FVWSBorderKey] intValue] > 0
                               ? NSOnState
                               : NSOffState];

  BOOL tiling = [[[self class] windowMode] isEqual:@"tiling"];
  NSEnumerator *e = [tilingControls objectEnumerator];
  NSControl *control;
  while ((control = [e nextObject]) != nil)
    [control setEnabled:tiling];
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

- (void)postChangeOfKey:(NSString *)key value:(NSString *)value
{
  NS_DURING
    {
      [[NSDistributedNotificationCenter defaultCenter]
          postNotificationName:FVDesktopSettingsChangedNotification
                        object:nil
                      userInfo:[NSDictionary dictionaryWithObjectsAndKeys:key, @"key", value,
                                                                          @"value", nil]
            deliverImmediately:YES];
    }
  NS_HANDLER
    {
      NSLog (@"Workspace: can't post %@: %@", FVDesktopSettingsChangedNotification,
             [localException reason]);
    }
  NS_ENDHANDLER
}

/*
 * Save the user's choice for the Dock position or menu style in the
 * current mode's NBModeSettings entry (nil: use the theme's). A plain key
 * from before settings were kept per mode was the stacking choice: it
 * moves there first.
 */
- (void)setModeValue:(NSString *)value forKey:(NSString *)key inDomain:(NSMutableDictionary *)global
{
  NSMutableDictionary *modes = [NSMutableDictionary dictionary];
  id saved = [global objectForKey:FVModeSettingsKey];
  if ([saved isKindOfClass:[NSDictionary class]])
    {
      NSEnumerator *e = [saved keyEnumerator];
      id mode;
      while ((mode = [e nextObject]) != nil)
        if ([[saved objectForKey:mode] isKindOfClass:[NSDictionary class]])
          [modes setObject:AUTORELEASE ([[saved objectForKey:mode] mutableCopy]) forKey:mode];
    }
  NSMutableDictionary *stacking = [modes objectForKey:@"stacking"];
  NSString *legacy = FVValidValue ([global objectForKey:key], key);
  if (legacy != nil)
    {
      if (stacking == nil)
        [modes setObject:(stacking = [NSMutableDictionary dictionary]) forKey:@"stacking"];
      if ([stacking objectForKey:key] == nil)
        [stacking setObject:legacy forKey:key];
    }
  [global removeObjectForKey:key];

  NSString *mode = [[self class] windowMode];
  NSMutableDictionary *entry = [modes objectForKey:mode];
  if (entry == nil)
    [modes setObject:(entry = [NSMutableDictionary dictionary]) forKey:mode];
  if (value)
    [entry setObject:value forKey:key];
  else
    [entry removeObjectForKey:key];
  if ([entry count] == 0)
    [modes removeObjectForKey:mode];
  if ([modes count] > 0)
    [global setObject:modes forKey:FVModeSettingsKey];
  else
    [global removeObjectForKey:FVModeSettingsKey];
}

- (void)choose:(id)sender
{
  NSString *key = [self keyForPopUp:sender];
  NSString *value = [[sender selectedItem] representedObject];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *global = AUTORELEASE ([[defaults persistentDomainForName:NSGlobalDomain]
      mutableCopy]);
  NSString *oldMode = [[self class] windowMode];
  NSString *oldDock = [[self class] effectiveValueForKey:FVDockPositionKey];
  NSString *oldMenu = [[self class] effectiveValueForKey:FVMenuStyleKey];

  if (global == nil)
    global = [NSMutableDictionary dictionary];
  if (FVIsPerMode (key))
    [self setModeValue:value forKey:key inDomain:global];
  else if (value)
    [global setObject:value forKey:key];
  else
    [global removeObjectForKey:key];
  [defaults setPersistentDomain:global forName:NSGlobalDomain];

  NSString *mode = [[self class] windowMode];
  NSString *dock = [[self class] effectiveValueForKey:FVDockPositionKey];
  NSString *menu = [[self class] effectiveValueForKey:FVMenuStyleKey];
  if (![dock isEqual:oldDock] || [key isEqual:FVDockPositionKey])
    [self updateDockPlacement:dock];
  [defaults synchronize];

  /*
   * A new window mode. Into tiling: WindowServer tiles the windows first,
   * so it keeps their frames as they are now, then the Dock goes to the
   * mode's edge and running apps take its menu style (in-window menus go
   * inside the tiles). Back to stacking: the apps change their menus
   * while the windows are still tiles, then WindowServer gives the
   * windows back their frames from before, which had the stacking
   * menus.
   */
  BOOL modeChanged = ![mode isEqual:oldMode];
  if (modeChanged)
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
  if (modeChanged && [mode isEqual:@"tiling"])
    [self sendWindowMode:mode];
  if ([key isEqual:FVDockPositionKey] || ![dock isEqual:oldDock])
    [self postChangeOfKey:FVDockPositionKey value:dock];
  if ([key isEqual:FVMenuStyleKey] || ![menu isEqual:oldMenu])
    [self postChangeOfKey:FVMenuStyleKey value:menu];
  if ([key isEqual:FVMinimizeStyleKey])
    [self postChangeOfKey:key value:[[self class] effectiveValueForKey:key]];
  if (modeChanged && ![mode isEqual:@"tiling"])
    [self performSelector:@selector (sendWindowMode:) withObject:mode afterDelay:0.75];
  if ([key isEqual:FVWindowModeKey])
    [self refresh];
}

/* Switch WindowServer's tiling, and tell the Dock and apps the mode. */
- (void)sendWindowMode:(NSString *)mode
{
  [[self class] setWindowServerSettings:[NSDictionary dictionaryWithObject:mode
                                                                    forKey:FVWSWindowModeKey]];
  [self postChangeOfKey:FVWindowModeKey value:mode];
  /* The windows WindowServer stops tiling come forward among the
     floating ones; keep Preferences in front. */
  if ([[view window] isVisible])
    [[view window] orderFront:nil];
}

/* The Tiling section: WindowServer's settings, sent at once. */
- (void)chooseTiling:(id)sender
{
  NSString *key, *value;
  if (sender == borderCheckbox)
    {
      key = FVWSBorderKey;
      value = [sender state] == NSOnState ? @"2" : @"0";
    }
  else
    {
      key = [sender tag] == FVTagLayout     ? FVWSLayoutKey
            : [sender tag] == FVTagInnerGap ? FVWSInnerGapKey
                                            : FVWSOuterGapKey;
      value = [[sender selectedItem] representedObject];
    }
  if (value == nil)
    return;
  id setting = [key isEqual:FVWSLayoutKey] ? (id)value
                                          : (id)[NSNumber numberWithInt:[value intValue]];
  [[self class] setWindowServerSettings:[NSDictionary dictionaryWithObject:setting forKey:key]];
}

- (void)dealloc
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (modePopUp);
  RELEASE (minimizePopUp);
  RELEASE (dockPopUp);
  RELEASE (menuPopUp);
  RELEASE (layoutPopUp);
  RELEASE (innerGapPopUp);
  RELEASE (outerGapPopUp);
  RELEASE (borderCheckbox);
  RELEASE (tilingControls);
  RELEASE (view);
  DEALLOC;
}

@end
