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

#import <AppKit/AppKit.h>

/* Posted (distributed, object nil) after a desktop setting changes. The
   userInfo has the "key" that changed and its effective "value". */
extern NSString *const FVDesktopSettingsChangedNotification;

/*
 * NextBSD's desktop settings: the active GNUstep theme declares the
 * defaults (NBDockPosition, NBMinimizeStyle... at the top of its
 * Info.plist), and the user's choice here, saved in NSGlobalDomain under
 * the same key, overrides them. "Use theme default" removes the user's
 * value. The Dock position and the menu style are kept per window mode
 * (the user's in NBModeSettings, the theme's in NBModeDefaults), and the
 * window mode is always stacking: Preferences no longer offers tiling.
 * See nextbsd-theme's README and NBDesktopSettings.h.
 *
 * The Desktop tab of Workspace Preferences.
 */
@interface FVDesktopSettings : NSObject
{
  NSView *view;
  NSPopUpButton *minimizePopUp;
  NSPopUpButton *dockPopUp;
  NSPopUpButton *menuPopUp;
  NSPopUpButton *dockStylePopUp;
  NSPopUpButton *scrollerStylePopUp;
  NSPopUpButton *windowStylePopUp;
  NSPopUpButton *appearancePopUp;
  NSPopUpButton *desktopIconsPopUp;
  NSMutableArray *presetButtons;
}

/* The window mode in effect: always stacking. */
+ (NSString *)windowMode;
/* The effective value of a desktop setting: the user's, else the theme's,
   else the built-in one (in the current window mode for the Dock
   position and the menu style). With the Mac menu bar a top Dock is at
   the bottom, as on macOS: the saved top is kept for the other styles. */
+ (NSString *)effectiveValueForKey:(NSString *)key;
/* The active theme's default for it, or the built-in one. */
+ (NSString *)themeDefaultForKey:(NSString *)key;
/* At login: a saved NBWindowMode of tiling (from before Preferences
   dropped it) goes back to stacking, and WindowServer's WindowMode
   follows, if the user's org.nextbsd.WindowServer defaults say
   otherwise. */
+ (void)syncWindowServer;
+ (void)syncScrollerStyle;
/* Whether the desktop shows the disks beside what's in ~/Desktop (always
   shown): the user's NBDesktopIcons, else the style's default (Mac yes,
   NeXT and Windows no). */
+ (BOOL)desktopShowsDisks;
/* Whether Return renames the one selected item, as on a Mac (the Mac
   window style), rather than opening what's selected, as NeXTSTEP and
   Windows do. Command-O and Command-Down open in every style; F2 and a
   slow second click on the name rename in every style. */
+ (BOOL)returnRenames;
/* WindowServer's focus follows the pointer except with the Mac menu bar. */
+ (void)syncFocusFollowsMouse;

- (id)initWithFrame:(NSRect)frame;
- (NSView *)view;
/* Show the saved choices. */
- (void)refresh;

@end
