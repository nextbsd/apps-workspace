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

@interface FVLauncher : NSObject

+ (NSArray *)applicationsForFile:(NSString *)path;
+ (NSString *)defaultApplicationForFile:(NSString *)path;
+ (void)setDefaultApplication:(NSString *)application forFile:(NSString *)path;
+ (BOOL)launchApplication:(NSString *)application file:(NSString *)path;
+ (void)launchApplication:(NSString *)application file:(NSString *)path
        completionTarget:(id)target selector:(SEL)selector;

@end
