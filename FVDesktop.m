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

#import "FVDesktop.h"

/* Above the background (NSDesktopWindowLevel), below every app's
   windows: macOS's desktop icon level. */
static const NSInteger FVDesktopLevel = NSDesktopWindowLevel + 20;

/* Key, so Workspace's shortcuts work after a click on the desktop, but
   never main: in the in-window menu style GNUstep would put the menu
   along the top of the desktop. */
@interface FVDesktopWindow : NSWindow
@end

@implementation FVDesktopWindow

- (BOOL)canBecomeKeyWindow
{
  return YES;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}

@end

@implementation FVDesktop

+ (FVDesktop *)sharedDesktop
{
  static FVDesktop *shared;
  if (shared == nil)
    shared = [[FVDesktop alloc] init];
  return shared;
}

- (id)init
{
  if ((self = [super init]) != nil)
    windows = [[NSMutableArray alloc] init];
  return self;
}

- (void)show
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (screensDidChange:)
             name:NSApplicationDidChangeScreenParametersNotification
           object:nil];
  [self screensDidChange:nil];
}

/* A window for each display again, at its full frame: the Dock and the
   menu bar are above it. */
- (void)screensDidChange:(NSNotification *)note
{
  NSArray *screens = [NSScreen screens];
  NSUInteger i;

  while ([windows count] > [screens count])
    {
      [[windows lastObject] close];
      [windows removeLastObject];
    }
  for (i = 0; i < [screens count]; i++)
    {
      NSRect frame = [[screens objectAtIndex:i] frame];
      if (i < [windows count])
        {
          [[windows objectAtIndex:i] setFrame:frame display:NO];
          continue;
        }
      NSWindow *window = [[FVDesktopWindow alloc] initWithContentRect:frame
                                                            styleMask:NSBorderlessWindowMask
                                                              backing:NSBackingStoreBuffered
                                                                defer:NO];
      [window setReleasedWhenClosed:NO];
      [window setOpaque:NO];
      [window setBackgroundColor:[NSColor clearColor]];
      [window setLevel:FVDesktopLevel];
      [window setCanHide:NO];
      [window setExcludedFromWindowsMenu:YES];
      [window setHasShadow:NO];
      [window orderBack:self];
      [windows addObject:window];
      RELEASE (window);
    }
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (windows);
  DEALLOC;
}

@end
