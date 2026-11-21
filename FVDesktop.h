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
 * The desktop is Workspace's, as it is the Finder's on macOS: a clear
 * window on every display, just above the desktop background (whose
 * windows let the pointer through), takes the clicks on the desktop.
 * Clicking it brings Workspace forward; right-clicking it shows
 * Workspace's menu. Desktop icons will go here.
 */
@interface FVDesktop : NSObject
{
  NSMutableArray *windows;
}

+ (FVDesktop *)sharedDesktop;
/* A window on each display, following the displays as they change. */
- (void)show;

@end
