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
static NSString *const FVDockStyleKey = @"NBDockStyle";

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

/* The Dock keeps its own placement, DockPlacement in its defaults domain,
   as its DockPlacement enumeration: left top, left centre, right top,
   right centre, top, bottom. Its domain is Dock; it was DockWM before
   the Dock was renamed (nextbsd/apps-dock#36). */
static NSString *const FVDockDomain = @"Dock";
static NSString *const FVOldDockDomain = @"DockWM";
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
  FVTagOuterGap,
  FVTagDockStyle
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
  if ([key isEqual:FVDockStyleKey])
    return [NSArray arrayWithObjects:@"nextstep", @"mac", @"tiling", nil];
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
  if ([key isEqual:FVDockStyleKey])
    return [NSArray arrayWithObjects:@"Optimized for NeXT", @"Optimized for Mac",
                                     @"Optimized for Tiling", nil];
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
  if ([key isEqual:FVDockStyleKey])
    return @"nextstep";
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

/* The setting as saved: the user's, else the theme's. */
+ (NSString *)savedValueForKey:(NSString *)key mode:(NSString *)mode
{
  NSString *value;
  if (FVIsPerMode (key))
    value = [self userValueForKey:key mode:mode];
  else
    value = FVValidValue ([[NSUserDefaults standardUserDefaults] objectForKey:key], key);
  return value ? value : [self themeDefaultForKey:key mode:mode];
}

/* As on macOS, the Dock is never at the top with the Mac menu bar, above
   or below it; the NeXT and in-window menu styles keep the top. */
+ (BOOL)dockCanBeAtTopInMode:(NSString *)mode
{
  return ![[self savedValueForKey:FVMenuStyleKey mode:mode] isEqual:@"macmenubar"];
}

/* A Dock position as it is used in a mode: a top Dock goes to the bottom,
   macOS's default, while the Dock can't be at the top. The saved one stays
   top, for the NeXT style. */
+ (NSString *)dockPosition:(NSString *)position inMode:(NSString *)mode
{
  if ([position isEqual:@"top"] && ![self dockCanBeAtTopInMode:mode])
    return @"bottom";
  return position;
}

+ (NSString *)effectiveValueForKey:(NSString *)key mode:(NSString *)mode
{
  NSString *value = [self savedValueForKey:key mode:mode];
  if ([key isEqual:FVDockPositionKey])
    value = [self dockPosition:value inMode:mode];
  return value;
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

/* A small picture of a style's desktop, 120x72: NeXT (a floating menu at
   the top left, the Dock down the right as tiles), Mac (a menu bar, a
   see-through Dock along the bottom) or Tiling (windows side by side,
   menus inside them). */
static NSImage *
FVPresetImage (NSUInteger preset)
{
  NSSize size = NSMakeSize (120, 72);
  NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize:size]);
  NSColor *desk = [NSColor colorWithCalibratedRed:0.10 green:0.22 blue:0.30 alpha:1];
  NSColor *bar = [NSColor colorWithCalibratedWhite:0.10 alpha:1];
  NSColor *window = [NSColor colorWithCalibratedWhite:0.82 alpha:1];
  NSColor *title = [NSColor colorWithCalibratedWhite:0.35 alpha:1];
  NSColor *icon = [NSColor colorWithCalibratedRed:0.30 green:0.70 blue:0.95 alpha:1];
  NSUInteger i;

  [image lockFocus];
  [desk set];
  NSRectFill (NSMakeRect (0, 0, size.width, size.height));
  if (preset == 0)
    {
      [window set];
      NSRectFill (NSMakeRect (30, 14, 56, 40));
      [title set];
      NSRectFill (NSMakeRect (30, 50, 56, 4));
      [bar set];
      NSRectFill (NSMakeRect (4, 46, 18, 22));
      for (i = 0; i < 4; i++)
        {
          [[NSColor colorWithCalibratedWhite:0.30 alpha:1] set];
          NSRectFill (NSMakeRect (102, 56 - i * 16, 14, 14));
          [icon set];
          NSRectFill (NSMakeRect (105, 59 - i * 16, 8, 8));
        }
    }
  else if (preset == 1)
    {
      [[bar colorWithAlphaComponent:0.8] set];
      NSRectFill (NSMakeRect (0, 66, size.width, 6));
      [window set];
      NSRectFill (NSMakeRect (24, 20, 64, 38));
      [title set];
      NSRectFill (NSMakeRect (24, 54, 64, 4));
      [[NSColor colorWithCalibratedWhite:0.12 alpha:0.55] set];
      [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect (34, 2, 52, 13)
                                       xRadius:4 yRadius:4] fill];
      [icon set];
      for (i = 0; i < 4; i++)
        NSRectFill (NSMakeRect (38 + i * 12, 5, 8, 8));
    }
  else
    {
      [window set];
      NSRectFill (NSMakeRect (4, 18, 54, 50));
      NSRectFill (NSMakeRect (62, 44, 54, 24));
      NSRectFill (NSMakeRect (62, 18, 54, 22));
      [title set];
      NSRectFill (NSMakeRect (4, 64, 54, 4));
      NSRectFill (NSMakeRect (62, 64, 54, 4));
      NSRectFill (NSMakeRect (62, 36, 54, 4));
      [icon set];
      for (i = 0; i < 4; i++)
        NSRectFill (NSMakeRect (38 + i * 12, 4, 8, 8));
    }
  [image unlockFocus];
  return image;
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
                  : [key isEqual:FVDockStyleKey]    ? FVTagDockStyle
                                                    : FVTagMode;
  return [self popUpWithTag:tag label:title row:y action:@selector (choose:)];
}

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super init]) == nil)
    return nil;
  view = [[NSView alloc] initWithFrame:frame];
  CGFloat y = NSHeight (frame) - 34;
  CGFloat step = 34;

  /* The style presets, each a picture of its desktop: a starting point
     the settings below can change. */
  [view addSubview:FVLabel (NSMakeRect (20, y, 300, 22), @"Choose your style:")];
  presetButtons = [[NSMutableArray alloc] init];
  NSArray *presetNames = [NSArray arrayWithObjects:@"NeXT", @"Mac", @"Tiling", nil];
  CGFloat column = (NSWidth (frame) - 40) / 3;
  NSUInteger i;
  for (i = 0; i < 3; i++)
    {
      NSButton *button = [[NSButton alloc]
          initWithFrame:NSMakeRect (20 + i * column + (column - 136) / 2, y - 112, 136, 108)];
      [button setButtonType:NSPushOnPushOffButton];
      [button setBordered:YES];
      [button setImage:FVPresetImage (i)];
      [button setImagePosition:NSImageAbove];
      [button setTitle:[presetNames objectAtIndex:i]];
      [button setTag:i];
      [button setTarget:self];
      [button setAction:@selector (choosePreset:)];
      [view addSubview:button];
      [presetButtons addObject:button];
      RELEASE (button);
    }
  y -= 112 + 46;

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
  y -= step;
  /* NBDockStyle, named for the presets: NeXT, a tile behind each icon
     (common_Tile) and no lines between the Dock's sections (the NextBSD
     theme's default); Mac, the lines on a see-through panel, as macOS's
     Dock has; Tiling, clear, with the lines. */
  dockStylePopUp = [self popUpForKey:FVDockStyleKey label:@"Dock style:" row:y];

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
  /* The Dock's own Settings changes its position too. */
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (desktopSettingsDidChange:)
             name:FVDesktopSettingsChangedNotification
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
    case FVTagDockStyle:
      return FVDockStyleKey;
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
  NSString *theme = [[self class] themeDefaultForKey:key mode:mode];
  BOOL dock = [key isEqual:FVDockPositionKey];
  BOOL noTop = dock && ![[self class] dockCanBeAtTopInMode:mode];
  NSUInteger i;
  NSInteger index;

  /* The Dock position as it is used: with the Mac menu bar, Top isn't
     offered and a saved top shows as the bottom, where the Dock is. */
  if (dock)
    {
      user = user ? [[self class] dockPosition:user inMode:mode] : nil;
      theme = [[self class] dockPosition:theme inMode:mode];
    }
  [popUp removeAllItems];
  [popUp addItemWithTitle:[NSString stringWithFormat:@"Use theme default (%@)",
      FVTitleForValue (key, theme)]];
  [[popUp lastItem] setRepresentedObject:nil];
  for (i = 0; i < [values count]; i++)
    {
      if (noTop && [[values objectAtIndex:i] isEqual:@"top"])
        continue;
      [popUp addItemWithTitle:[titles objectAtIndex:i]];
      [[popUp lastItem] setRepresentedObject:[values objectAtIndex:i]];
    }
  index = user ? [popUp indexOfItemWithRepresentedObject:user] : -1;
  [popUp selectItemAtIndex:index < 0 ? 0 : index];
  if (dock)
    [popUp setToolTip:noTop ? @"The Dock can't be at the top with the Mac menu bar." : nil];
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
  [self fillPopUp:dockStylePopUp];

  /* The preset the settings match, if any. */
  NSString *mode = [[self class] windowMode];
  NSString *menu = [[self class] effectiveValueForKey:FVMenuStyleKey];
  NSString *dockStyle = [[self class] effectiveValueForKey:FVDockStyleKey];
  NSInteger preset = -1;
  if ([mode isEqual:@"tiling"] && [dockStyle isEqual:@"tiling"])
    preset = 2;
  else if ([mode isEqual:@"stacking"] && [menu isEqual:@"macmenubar"]
           && [dockStyle isEqual:@"mac"])
    preset = 1;
  else if ([mode isEqual:@"stacking"] && [menu isEqual:@"nextstep"]
           && [dockStyle isEqual:@"nextstep"])
    preset = 0;
  NSEnumerator *buttons = [presetButtons objectEnumerator];
  NSButton *button;
  while ((button = [buttons nextObject]) != nil)
    [button setState:[button tag] == preset ? NSOnState : NSOffState];

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
  /* Tiling forces in-window menus: the picker does not apply. */
  [menuPopUp setEnabled:!tiling];
  [menuPopUp setToolTip:tiling ? @"Tiling always uses in-window menus." : nil];
}

- (void)themeDidActivate:(NSNotification *)note
{
  [self refresh];
}

/* Another app (the Dock's Settings) changed the Dock position, the menu
   style or the window mode: show it. */
- (void)desktopSettingsDidChange:(NSNotification *)note
{
  id key = [[note userInfo] objectForKey:@"key"];
  if ([key isEqual:FVDockPositionKey] || [key isEqual:FVMenuStyleKey]
      || [key isEqual:FVWindowModeKey] || [key isEqual:FVModeSettingsKey])
    [self refresh];
}

/* Tell the Dock where to go: it reads DockPlacement. Keep its centring
   along the left and right edges. A Dock not yet renamed still reads the
   DockWM domain: that one follows too, where it exists. */
- (void)updateDockPlacement:(NSString *)position
{
  [self updateDockPlacement:position inDomain:FVDockDomain];
  if ([[NSUserDefaults standardUserDefaults] persistentDomainForName:FVOldDockDomain] != nil)
    [self updateDockPlacement:position inDomain:FVOldDockDomain];
}

- (void)updateDockPlacement:(NSString *)position inDomain:(NSString *)name
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *dock = AUTORELEASE ([[defaults persistentDomainForName:name]
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
  [defaults setPersistentDomain:dock forName:name];
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
  id value = [[sender selectedItem] representedObject];
  [self applyValues:[NSDictionary dictionaryWithObject:value ? value : (id)[NSNull null]
                                                forKey:[self keyForPopUp:sender]]];
}

/*
 * Save desktop settings together (a value, or NSNull for the theme's)
 * and apply them: a pop-up's one, or a style preset's several. The
 * window mode goes first, so a Dock position or menu style given with
 * it is saved for the new mode.
 */
- (void)applyValues:(NSDictionary *)values
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *oldMode = [[self class] windowMode];
  NSString *oldDock = [[self class] effectiveValueForKey:FVDockPositionKey];
  NSString *oldSavedDock = [[self class] savedValueForKey:FVDockPositionKey mode:oldMode];
  NSString *oldMenu = [[self class] effectiveValueForKey:FVMenuStyleKey];
  NSMutableArray *keys = [NSMutableArray arrayWithArray:[values allKeys]];
  NSEnumerator *e;
  NSString *key;

  if ([keys containsObject:FVWindowModeKey])
    {
      [keys removeObject:FVWindowModeKey];
      [keys insertObject:FVWindowModeKey atIndex:0];
    }
  e = [keys objectEnumerator];
  while ((key = [e nextObject]) != nil)
    {
      id value = [values objectForKey:key];
      NSMutableDictionary *global = AUTORELEASE ([[defaults persistentDomainForName:NSGlobalDomain]
          mutableCopy]);
      if (global == nil)
        global = [NSMutableDictionary dictionary];
      if (value == [NSNull null])
        value = nil;
      if (FVIsPerMode (key))
        [self setModeValue:value forKey:key inDomain:global];
      else if (value)
        [global setObject:value forKey:key];
      else
        [global removeObjectForKey:key];
      [defaults setPersistentDomain:global forName:NSGlobalDomain];
    }

  NSString *mode = [[self class] windowMode];
  /* Tiling forces in-window menus: apply it immediately when switching in. */
  if (![mode isEqual:oldMode] && [mode isEqual:@"tiling"])
    {
      NSMutableDictionary *g = AUTORELEASE ([[defaults persistentDomainForName:NSGlobalDomain]
          mutableCopy]);
      if (g == nil)
        g = [NSMutableDictionary dictionary];
      [self setModeValue:@"inwindow" forKey:FVMenuStyleKey inDomain:g];
      [defaults setPersistentDomain:g forName:NSGlobalDomain];
    }
  NSString *dock = [[self class] effectiveValueForKey:FVDockPositionKey];
  NSString *savedDock = [[self class] savedValueForKey:FVDockPositionKey mode:mode];
  NSString *menu = [[self class] effectiveValueForKey:FVMenuStyleKey];
  /* The Dock's own DockPlacement (X11's) keeps the saved position: a top
     Dock is only at the bottom while the Mac menu bar is in use. */
  if (![savedDock isEqual:oldSavedDock] || [values objectForKey:FVDockPositionKey])
    [self updateDockPlacement:savedDock];
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
  if ([values objectForKey:FVDockPositionKey] || ![dock isEqual:oldDock])
    [self postChangeOfKey:FVDockPositionKey value:dock];
  if ([values objectForKey:FVMenuStyleKey] || ![menu isEqual:oldMenu])
    [self postChangeOfKey:FVMenuStyleKey value:menu];
  if ([values objectForKey:FVMinimizeStyleKey])
    [self postChangeOfKey:FVMinimizeStyleKey
                    value:[[self class] effectiveValueForKey:FVMinimizeStyleKey]];
  if ([values objectForKey:FVDockStyleKey])
    [self postChangeOfKey:FVDockStyleKey
                    value:[[self class] effectiveValueForKey:FVDockStyleKey]];
  if (modeChanged && ![mode isEqual:@"tiling"])
    [self performSelector:@selector (sendWindowMode:) withObject:mode afterDelay:0.75];
  /* The menu style decides whether the Dock can be at the top. */
  if ([values objectForKey:FVWindowModeKey] || [values objectForKey:FVMenuStyleKey])
    [self refresh];
}

/* The style presets: what each sets (NSNull: the theme's default). NeXT:
   floating menus, the theme's Dock (NeXTSTEP's tiles). Mac: the menu
   bar, a see-through Dock along the bottom. Tiling: windows side by
   side, in-window menus (tiling's), a clear Dock. */
- (void)choosePreset:(id)sender
{
  NSInteger preset = [sender tag];
  NSNull *theme = [NSNull null];
  NSDictionary *values;
  if (preset == 0)
    values = [NSDictionary dictionaryWithObjectsAndKeys:
        @"stacking", FVWindowModeKey, @"nextstep", FVMenuStyleKey,
        theme, FVDockPositionKey, theme, FVMinimizeStyleKey,
        theme, FVDockStyleKey, nil];
  else if (preset == 1)
    values = [NSDictionary dictionaryWithObjectsAndKeys:
        @"stacking", FVWindowModeKey, @"macmenubar", FVMenuStyleKey,
        @"bottom", FVDockPositionKey, @"dock", FVMinimizeStyleKey,
        @"mac", FVDockStyleKey, nil];
  else
    values = [NSDictionary dictionaryWithObjectsAndKeys:
        @"tiling", FVWindowModeKey, theme, FVDockPositionKey,
        theme, FVMinimizeStyleKey, @"tiling", FVDockStyleKey, nil];
  [self applyValues:values];
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
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (modePopUp);
  RELEASE (minimizePopUp);
  RELEASE (dockPopUp);
  RELEASE (menuPopUp);
  RELEASE (dockStylePopUp);
  RELEASE (presetButtons);
  RELEASE (layoutPopUp);
  RELEASE (innerGapPopUp);
  RELEASE (outerGapPopUp);
  RELEASE (borderCheckbox);
  RELEASE (tilingControls);
  RELEASE (view);
  DEALLOC;
}

@end
