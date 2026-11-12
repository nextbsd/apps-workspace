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
@interface FVIconView : NSView
{
  FVWindow *owner;
  NSMutableIndexSet *selection;
  CGFloat tileSize;
  NSInteger anchor;
  NSInteger focusedIndex;
  NSPoint mouseDownPoint;
  NSString *mouseDownPath;
  BOOL dragPending;
  NSMutableArray *rowOffsets;
}

- (id)initWithOwner:(FVWindow *)controller;
- (NSIndexSet *)selection;
- (void)setSelection:(NSIndexSet *)indices;
- (void)reload;
- (void)resizeIcons:(CGFloat)delta;
- (void)updateFileTooltips;
- (NSRect)labelRectForIndex:(NSUInteger)i;

@end
