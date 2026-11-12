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

@class FVWindow;

/* File → Get Info: one Inspector window, like NeXTSTEP's, that follows the
   selection of the active File Viewer. It shows the item's icon, an editable
   name, kind, size (a folder's total counted in the background), location,
   dates and link target, with owner, group and permission controls that are
   enabled only where the user may change them. Several selected items get
   one combined summary. */
@interface FVInspector : NSObject
{
  NSPanel *panel;
  FVWindow *viewer;
  NSArray *paths;
  NSImageView *icon;
  NSTextField *nameField;
  NSTextField *kindLabel;
  NSMutableDictionary *values;
  NSPopUpButton *ownerPopUp;
  NSPopUpButton *groupPopUp;
  NSMutableArray *permissionBoxes;
  NSTextField *permissionNote;
  NSButton *applyButton;
  NSButton *revertButton;
  id sizeJob;
  NSUInteger generation;
}

+ (FVInspector *)sharedInspector;
/* Shows the Inspector for the viewer's selection (or its folder). */
- (void)showForViewer:(FVWindow *)controller;
/* Follows a viewer's selection while the Inspector is open. */
- (void)viewerSelectionChanged:(FVWindow *)controller;
- (void)viewerClosed:(FVWindow *)controller;
- (NSPanel *)panel;
- (NSArray *)paths;

@end
