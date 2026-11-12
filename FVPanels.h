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

/* A modal panel run through FVWindow's -runDialog:, which returns its button index. */
@protocol FVModalDialog
- (NSInteger)run;
@end

/* Escape presses the panel's button whose key equivalent is Escape. */
@interface FVDialogPanel : NSPanel
@end

/* Dialog text that stays legible and unselected on light and dark themes. */
NSColor *FVDialogTextColor (NSWindow *window);
/* Runs a panel modally; returns the code given to -stopModalWithCode:. */
NSInteger FVRunModalPanel (NSPanel *panel);

/* "12 bytes", "3.4 KB", "12.1 MB": decimal units, as Finder shows them. */
NSString *FVSizeString (unsigned long long bytes);
/* "Nov 12, 2026 at 12:44 AM" */
NSString *FVDateString (NSDate *date);

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

/* Asked when a copy or move meets an item of the same name: shows both items
   (icon, name, kind, size, modified date) with Keep Both, Skip, Replace and
   Stop, and "Apply to all" when more items follow. -run returns 0 Keep Both,
   1 Skip, 2 Replace or 3 Stop. */
@interface FVConflictPanel : NSObject <FVModalDialog>
{
  NSPanel *panel;
  NSButton *applyToAll;
}

- (id)initWithSource:(NSString *)source
         destination:(NSString *)destination
                kind:(NSString *)kind
           remaining:(NSUInteger)remaining;
- (NSInteger)run;
- (BOOL)applyToAll;
- (NSPanel *)panel;

@end

/* File → Open With…: lists applications by name with their icons, those
   that declare the file's type first, then all others. "Always open …
   with this application" saves the choice for the extension, and a saved
   choice is shown with a Reset button. -run returns 0 Open or 1 Cancel. */
@interface FVAppChooser : NSObject <FVModalDialog>
{
  NSPanel *panel;
  NSString *file;
  NSTableView *table;
  NSMutableArray *rows;
  NSButton *always;
  NSButton *openButton;
  NSTextField *savedLabel;
  NSButton *resetButton;
}

/* recommended: the applications that declare the file's type, best first. */
- (id)initWithApplications:(NSArray *)recommended file:(NSString *)path;
- (NSInteger)run;
- (NSString *)selectedApplication;
- (BOOL)selectApplication:(NSString *)application;
- (BOOL)apply;
- (NSPanel *)panel;

@end
