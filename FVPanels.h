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

/* "12 bytes", "3.4 KB", "12.1 MB": decimal units, as Finder shows them. */
NSString *FVSizeString (unsigned long long bytes);

/* One panel, like NeXTSTEP's Processes panel, with a row for each running
   copy, move, Trash or delete: what it does, a progress bar, the item being
   handled and a Stop button. It appears only when an operation is still
   running after a moment, and closes when the last one finishes. */
@interface FVProgressPanel : NSObject
{
  NSPanel *panel;
  NSMutableArray *rows;
}

+ (FVProgressPanel *)sharedPanel;
/* Stop sends -stopOperation: to owner. */
- (void)beginOperation:(id)operation
                  kind:(NSString *)kind
               sources:(NSArray *)sources
           destination:(NSString *)destination
                 owner:(id)owner;
- (void)updateOperation:(id)operation progress:(NSDictionary *)progress;
- (void)operationStopping:(id)operation;
- (void)endOperation:(id)operation;
- (NSPanel *)panel;

@end
