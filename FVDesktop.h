/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import <AppKit/AppKit.h>

@interface FVDesktop : NSObject
{
  NSString *directory;
  NSMutableDictionary *iconWindows;
  NSMutableDictionary *positions;
  NSDictionary *macPositions;
  NSTimer *refreshTimer;
  BOOL enabled;
  BOOL showMountedDrives;
}

- (id)initWithDirectory:(NSString *)path;
- (void)setEnabled:(BOOL)flag;
- (void)setShowMountedDrives:(BOOL)flag;
- (NSArray *)mountedVolumePaths;
- (void)refresh:(id)sender;
- (NSMenu *)arrangementMenu;
- (void)arrange:(id)sender;
- (void)restoreMacLayout:(id)sender;
- (void)savePositionForPath:(NSString *)path window:(NSWindow *)window;

@end
