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

#import <Foundation/Foundation.h>

/* Bytes in the regular files of a tree, never following links. Counts the
   entries in *entries when given. Stops early, returning what it has, once
   *stop becomes YES. */
unsigned long long FVTreeSize (NSString *path, unsigned long long *entries, volatile BOOL *stop);

/* All mutations use this service. Linux no-replace rename is isolated here. */
@interface FVOperations : NSObject
{
  BOOL cancelled;
  id target;
  NSString *kind;
  NSArray *sources;
  NSString *destination;
  NSString *policy;
  NSMutableArray *notes;
  /* Progress, written by the worker thread only. */
  unsigned long long bytesDone;
  unsigned long long bytesTotal;
  unsigned long long entriesDone;
  unsigned long long entriesTotal;
  NSUInteger itemIndex;
  NSString *currentName;
  NSTimeInterval lastReport;
  BOOL preparing;
}

- (id)initWithKind:(NSString *)action
           sources:(NSArray *)paths
       destination:(NSString *)folder
            target:(id)receiver;
- (void)start;
- (BOOL)undoRecord:(NSDictionary *)record error:(NSError **)error;
- (void)cancel;
- (BOOL)cancelled;
/* Platform seam, also used to inject EXDEV in regression tests. */
- (int)renameSource:(NSString *)source to:(NSString *)dest;
- (BOOL)transfer:(NSString *)source to:(NSString *)dest move:(BOOL)move error:(NSError **)error;
+ (BOOL)validName:(NSString *)name;
+ (NSString *)homeTrash;
+ (BOOL)trashPath:(NSString *)source error:(NSError **)error;
/* Called by the copier as data is written; reports progress at most ten times a second. */
- (void)copiedBytes:(unsigned long long)count;
/* Called by the copier as it reaches each file, folder or link. */
- (void)copyingEntry:(NSString *)path;

@end
