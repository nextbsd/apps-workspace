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
 * value. See nextbsd-theme's README and NBDesktopSettings.h.
 *
 * The Desktop tab of Workspace Preferences.
 */
@interface FVDesktopSettings : NSObject
{
  NSView *view;
  NSPopUpButton *minimizePopUp;
  NSPopUpButton *dockPopUp;
  NSPopUpButton *menuPopUp;
}

/* The effective value of a desktop setting: the user's, else the theme's,
   else the built-in one. */
+ (NSString *)effectiveValueForKey:(NSString *)key;
/* The active theme's default for it, or the built-in one. */
+ (NSString *)themeDefaultForKey:(NSString *)key;

- (id)initWithFrame:(NSRect)frame;
- (NSView *)view;
/* Show the saved choices. */
- (void)refresh;

@end
