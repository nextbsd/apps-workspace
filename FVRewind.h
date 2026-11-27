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

@class FVWindow, FVRewindStage;

/* The list's Rewind column: "Removed since" or "Changed since" for an
   object value of @"removed" or @"changed", else nothing. */
@interface FVRewindChangeCell : NSTextFieldCell
@end

/* Show only changes, as a switch; sends its action when flipped. */
@interface FVRewindSwitch : NSControl
{
  BOOL on;
}
- (BOOL)isOn;
- (void)setOn:(BOOL)flag;
@end

/* The status line's spinner while something is on its way, and a done
   symbol after. */
@interface FVStatusSpinner : NSView
{
  NSTimer *timer;
  CGFloat angle;
  BOOL busy;
}
- (void)setBusy:(BOOL)flag;
@end

/* Snapshots and Rewind for a File Viewer (nextbsd/nextbsd#707, #724).

   The home folder is a ZFS dataset of its own. Snapshots shows its
   schedule, kept in the home itself (~/Library/Rewind/Schedule), and can
   ask for one now (~/Library/Rewind/SnapshotNow); the rewind job takes
   them on the machine that holds the home: this one for a local user,
   the directory server for a network user (nextbsd-userland,
   /usr/libexec/nextbsd/rewind). Take Snapshot Now shows in the viewer's
   status line until the snapshot is there.

   Rewind fills the screen: the viewer stays in front, showing the folder
   as it was in a snapshot, through the home's .zfs/snapshot directory
   (which NFS shows too, so network users get it the same). Older
   snapshots stand behind it as frames with their dates, and a timeline
   on the right picks the time; Up goes back, Down forward, Escape to
   now. Each item says whether it has been removed or changed since,
   compared with the same path in the home now, and Show only changes
   hides the rest. Restore copies only the selected items back into the
   folder they came from, asking Skip, Replace or Keep Both when one of
   the same name is there now. */
@interface FVRewind : NSObject
{
  FVWindow *viewer;
  NSWindow *backdrop;
  FVRewindStage *stage;
  NSArray *versions;
  NSInteger current;
  NSString *home;
  NSString *liveFolder;
  NSString *restoreFolder;
  NSRect liveFrame;
  NSInteger liveLevel;
  BOOL rewinding;
  BOOL restoring;
  BOOL onlyChanges;
  NSMutableDictionary *changes;
  NSUInteger shownCount, removedCount, changedCount;

  NSPanel *schedule;
  NSButton *enabledBox, *thinBox, *beforeBox, *lowBox;
  NSPopUpButton *freqPopUp, *atPopUp, *keepPopUp;
  NSTextField *statusLabel;
  NSTimer *snapshotTimer;
  NSDate *askedAt;
  NSArray *namesBefore;
  NSString *latestBefore;
  NSString *takenName;
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

/* The viewer's side of Rewind. Up, Down and Escape, while rewinding. */
- (BOOL)handleKey:(NSEvent *)event;
- (BOOL)showsOnlyChanges;
- (void)setShowsOnlyChanges:(BOOL)flag;
/* A new listing of the folder starts; its items come through
   -filterItems:, which notes how each differs from now and leaves out
   the unchanged ones with Show only changes. */
- (void)listingWillStart;
- (NSArray *)filterItems:(NSArray *)found;
/* @"removed" or @"changed" for an item in the snapshot, else nil. */
- (NSString *)changeAtPath:(NSString *)value;
/* "8 items as they were on Tuesday 24 November at 20:00 · …" */
- (NSString *)statusLine;
- (void)viewerSelectionChanged;
/* A restored item meets one of the same name now (FVOperations). */
- (void)resolveConflict:(NSMutableDictionary *)request;
- (void)restoreFinished:(NSDictionary *)result;
@end
