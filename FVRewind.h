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

/* Snapshots and Rewind for a File Viewer (nextbsd/nextbsd#707).

   The home folder is a ZFS dataset of its own. Snapshots shows its
   schedule, kept in the home itself (~/Library/Rewind/Schedule), and can
   ask for one now (~/Library/Rewind/SnapshotNow); the rewind job takes
   them on the machine that holds the home: this one for a local user,
   the directory server for a network user (nextbsd-userland,
   /usr/libexec/nextbsd/rewind).

   Rewind browses the folder as it was in each snapshot, through the
   home's .zfs/snapshot directory, which NFS shows too, so it works the
   same for network users. A timeline beside the viewer picks the time;
   the viewer itself shows that version of the folder, and Restore copies
   the selected items (or the whole folder) back with File Viewer's own
   copy, so conflicts offer Keep Both, Skip and Replace, and Undo works. */
@interface FVRewind : NSObject
{
  FVWindow *viewer;
  NSPanel *timeline;
  NSTableView *versionsTable;
  NSTextField *whenLabel;
  NSButton *restoreButton;
  NSArray *versions;
  NSString *home;
  NSString *liveFolder;
  BOOL rewinding;

  NSPanel *schedule;
  NSButton *enabledBox, *thinBox, *beforeBox, *lowBox;
  NSPopUpButton *freqPopUp, *atPopUp, *keepPopUp;
  NSTextField *statusLabel;
}
/* Whether Snapshots and Rewind apply to a folder: the home folder and
   anything in it (its snapshots included). */
+ (BOOL)appliesToPath:(NSString *)folder;
- (id)initWithViewer:(FVWindow *)aViewer;
- (BOOL)isRewinding;
- (void)showSnapshots:(id)sender;
- (void)toggleRewind:(id)sender;
- (void)viewerDidNavigate;
- (void)viewerWillClose;
@end
