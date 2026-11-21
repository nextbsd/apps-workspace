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

/*
 * The Dock tab of Workspace Preferences, as macOS's Desktop & Dock: the
 * Dock's size, magnification, running-app dots, bouncing and single
 * click, and which status extras show (in the Dock, or in the menu bar
 * in the Mac menu style). The Dock (nextbsd/apps-dock) keeps these in
 * its defaults domain, Dock; a change goes to it with the settings
 * apps' distributed notification org.nextbsd.SettingsChanged (domain,
 * keys, values), and an extra is shown or hidden by asking the Dock
 * (org.nextbsd.Dock.SetExtraHidden). The Dock's per-app settings stay
 * out of here.
 */
@interface FVDockSettings : NSObject
{
  NSView *view;
  NSSlider *sizeSlider;
  NSButton *magnifyCheckbox;
  NSSlider *magnifySlider;
  NSPopUpButton *dotsPopUp;
  NSButton *bounceLaunchCheckbox;
  NSButton *bounceAttentionCheckbox;
  NSButton *singleClickCheckbox;
  NSMutableArray *extraCheckboxes;
}

/* A Dock setting, or the Dock's default for it. */
+ (id)dockValueForKey:(NSString *)key;
/* Save Dock settings; a running Dock applies them at once. */
+ (void)setDockValues:(NSDictionary *)values;

- (id)initWithFrame:(NSRect)frame;
- (NSView *)view;
/* Show the saved choices. */
- (void)refresh;

@end
