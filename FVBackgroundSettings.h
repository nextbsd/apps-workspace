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
 * The Background tab of Workspace Preferences: the desktop background's
 * module (see FVBackground), its speed, whether it shows on every
 * display, and the module's own options.
 */
@interface FVBackgroundSettings : NSObject
{
  NSView *view;
  NSTableView *moduleTable;
  NSSlider *speedSlider;
  NSButton *everyDisplayCheckbox;
  NSButton *optionsButton;
  NSArray *modules;
  BOOL refreshing;
}

- (id)initWithFrame:(NSRect)frame;
- (NSView *)view;
/* Show the installed modules and the saved choices. */
- (void)refresh;

@end
