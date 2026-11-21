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

/* Another app's defaults domain as saved on disk now. Its own process may
   have saved it since this one last read it, and -persistentDomainForName:
   doesn't read it again. nil if it has none. */
NSDictionary *FVDefaultsDomainOnDisk (NSString *name);

/*
 * The desktop background. WorkspaceBackground (Background/, a tool in
 * Workspace.app's Resources) draws an InnerSpace module behind every
 * window, on every display. It runs as Workspace's child, so a module
 * that crashes takes only the background down: Workspace starts it again,
 * and if it keeps stopping, falls back to the Black module. Its settings
 * are its own defaults domain, which the Background tab of Preferences
 * writes.
 */
@interface FVBackground : NSObject
{
  NSTask *task;
  NSMutableArray *exits;
  BOOL stopping;
}

+ (FVBackground *)sharedBackground;
/* At login, and when Workspace quits. */
- (void)start;
- (void)stop;
- (BOOL)isRunning;

/* The installed modules' names, sorted. */
+ (NSArray *)moduleNames;
/* currentModule, runSpeed (seconds between frames), moduleOnEveryDisplay. */
+ (id)settingForKey:(NSString *)key;
/* The background applies the setting at once and saves it with the
   rest of its domain (its modules' settings too); with no background
   running, it's saved here. */
+ (void)setSetting:(id)value forKey:(NSString *)key;
/* The current module's own settings, in a window of the background's. */
+ (void)showOptions;

@end
