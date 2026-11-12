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
 * value. The Dock position and the menu style are kept for each window
 * mode (NBWindowMode: stacking, tiling): the user's in NBModeSettings,
 * the theme's in NBModeDefaults. See nextbsd-theme's README and
 * NBDesktopSettings.h.
 *
 * The Desktop tab of Workspace Preferences. Switching the window mode
 * sets WindowServer's WindowMode (its tiling) live and applies that
 * mode's Dock position and menu style; the Tiling settings are
 * WindowServer's own (org.nextbsd.WindowServer defaults).
 */
@interface FVDesktopSettings : NSObject
{
  NSView *view;
  NSPopUpButton *modePopUp;
  NSPopUpButton *minimizePopUp;
  NSPopUpButton *dockPopUp;
  NSPopUpButton *menuPopUp;
  NSPopUpButton *layoutPopUp;
  NSPopUpButton *innerGapPopUp;
  NSPopUpButton *outerGapPopUp;
  NSButton *borderCheckbox;
  NSArray *tilingControls;
}

/* The window mode in effect: stacking or tiling. */
+ (NSString *)windowMode;
/* The effective value of a desktop setting: the user's, else the theme's,
   else the built-in one (in the current window mode for the Dock
   position and the menu style). */
+ (NSString *)effectiveValueForKey:(NSString *)key;
/* The active theme's default for it, or the built-in one. */
+ (NSString *)themeDefaultForKey:(NSString *)key;
/* At login: make WindowServer's WindowMode the window mode in effect, if
   the user's org.nextbsd.WindowServer defaults say otherwise (the theme
   changed, or the defaults were written elsewhere). */
+ (void)syncWindowServer;

- (id)initWithFrame:(NSRect)frame;
- (NSView *)view;
/* Show the saved choices. */
- (void)refresh;

@end
