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

@class FVDesktopSettings;
@class FVBackgroundSettings;
@class FVDockSettings;

/* Moves a window that would open under the application's menu clear of
   it: to the menu's right, or below it, shrinking a resizable window to
   fit when the screen is small. Leaves a window that doesn't touch the
   menu where it is. */
void FVPlaceClearOfMenu (NSWindow *window);

@interface FVApplication : NSObject
{
  NSMutableArray *windows;
  NSMutableArray *pendingPaths;
  BOOL launched;
  NSPanel *preferencesPanel;
  NSButton *thumbnailCheckbox;
  NSButton *hiddenFilesCheckbox;
  FVDesktopSettings *desktopSettings;
  FVDockSettings *dockSettings;
  FVBackgroundSettings *backgroundSettings;
}

- (BOOL)openFile:(NSString *)path withApplication:(NSString *)application
    andDeactivate:(BOOL)flag;
/* NSWorkspace -selectFile:inFileViewerRootedAtPath:, asked over DO. */
- (BOOL)selectFile:(NSString *)fullPath inFileViewerRootedAtPath:(NSString *)rootFullPath;
- (void)newWindow:(id)sender;
- (void)openPath:(NSString *)path;
- (void)viewerBecameKey:(id)controller;
- (void)preferences:(id)sender;
- (void)showBackgroundPreferences:(id)sender;

@end
