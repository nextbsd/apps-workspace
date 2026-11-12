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
#import "FVApplication.h"
#import "FVLauncher.h"

/* Starting Workspace while it already runs (openapp Workspace) reopens
   the running one, as opening a running app does on macOS, instead of
   starting a second copy. Asked to open folders, a new copy hands them
   over through NSWorkspace like any other request. */
static BOOL
FVReopenRunningWorkspace (void)
{
  NSString *name = [[NSProcessInfo processInfo] processName];
  NSArray *arguments = [[NSProcessInfo processInfo] arguments];
  id app = nil;

  if ([arguments count] > 1)
    return NO;
  NS_DURING
    {
      NSConnection *connection = [NSConnection connectionWithRegisteredName:name host:@""];
      [connection setRequestTimeout:5];
      [connection setReplyTimeout:5];
      app = [connection rootProxy];
    }
  NS_HANDLER
    {
      app = nil;
    }
  NS_ENDHANDLER
  if (app == nil)
    return NO;
  [FVLauncher reopenApplication:app];
  return YES;
}

int
main (int argc, const char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  if (FVReopenRunningWorkspace ())
    {
      RELEASE (pool);
      return 0;
    }
  [NSApplication sharedApplication];
  FVApplication *delegate = [[FVApplication alloc] init];
  [NSApp setDelegate:delegate];
  [NSApp run];
  RELEASE (delegate);
  RELEASE (pool);
  return 0;
}

