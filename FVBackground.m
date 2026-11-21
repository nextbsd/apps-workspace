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

#import "FVBackground.h"
#import "Background/WorkspaceBackground.h"

/* Three stops within a minute: the module is crashing it. */
static const NSUInteger FVBackgroundMaxExits = 3;
static const NSTimeInterval FVBackgroundExitWindow = 60;

NSDictionary *
FVDefaultsDomainOnDisk (NSString *name)
{
  NSString *file = [[GSDefaultsRootForUser (NSUserName ()) stringByAppendingPathComponent:name]
      stringByAppendingPathExtension:@"plist"];
  return [NSDictionary dictionaryWithContentsOfFile:file];
}

@implementation FVBackground

+ (FVBackground *)sharedBackground
{
  static FVBackground *shared;
  if (shared == nil)
    shared = [[FVBackground alloc] init];
  return shared;
}

+ (NSArray *)moduleNames
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableSet *names = [NSMutableSet set];
  NSEnumerator *e = [WorkspaceBackgroundModuleDirectories () objectEnumerator];
  NSString *directory;
  while ((directory = [e nextObject]) != nil)
    {
      NSEnumerator *files = [[fm directoryContentsAtPath:directory] objectEnumerator];
      NSString *file;
      while ((file = [files nextObject]) != nil)
        if ([[file pathExtension] isEqual:@"InnerSpace"])
          [names addObject:[file stringByDeletingPathExtension]];
    }
  return [[names allObjects] sortedArrayUsingSelector:@selector (caseInsensitiveCompare:)];
}

/* The background's own domain, as it last saved it; InnerSpace.app's
   until the background has saved one (it adopts those on its first
   start). */
+ (NSDictionary *)settings
{
  NSDictionary *domain = FVDefaultsDomainOnDisk (WorkspaceBackgroundDomain);
  if ([domain count] == 0)
    domain = FVDefaultsDomainOnDisk (@"InnerSpace");
  return domain;
}

+ (id)settingForKey:(NSString *)key
{
  return [[self settings] objectForKey:key];
}

+ (void)setSetting:(id)value forKey:(NSString *)key
{
  NSDictionary *change = [NSDictionary dictionaryWithObject:value forKey:key];
  /* While it runs, the background owns its domain, its modules' settings
     included, and saves the change itself: it doesn't read back what
     another process saves there, so the change goes with the
     notification. */
  if (![[self sharedBackground] isRunning])
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSMutableDictionary *domain =
          [NSMutableDictionary dictionaryWithDictionary:[self settings]];
      [domain addEntriesFromDictionary:change];
      [defaults setPersistentDomain:domain forName:WorkspaceBackgroundDomain];
      [defaults synchronize];
    }
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:WorkspaceBackgroundSettingsDidChangeNotification
                    object:nil
                  userInfo:change];
}

+ (void)showOptions
{
  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:WorkspaceBackgroundShowOptionsNotification
                    object:nil];
}

- (id)init
{
  if ((self = [super init]) != nil)
    exits = [[NSMutableArray alloc] init];
  return self;
}

- (BOOL)isRunning
{
  return [task isRunning];
}

- (void)start
{
  if ([task isRunning])
    return;
  NSString *executable = [[NSBundle mainBundle] pathForResource:@"WorkspaceBackground" ofType:nil];
  if (executable == nil)
    {
      NSLog (@"Workspace: no desktop background in %@", [[NSBundle mainBundle] resourcePath]);
      return;
    }
  stopping = NO;
  DESTROY (task);
  task = [[NSTask alloc] init];
  [task setLaunchPath:executable];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector (backgroundDidStop:)
                                               name:NSTaskDidTerminateNotification
                                             object:task];
  NS_DURING
    [task launch];
  NS_HANDLER
    NSLog (@"Workspace: can't start the desktop background: %@", localException);
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:task];
    DESTROY (task);
  NS_ENDHANDLER
}

- (void)stop
{
  stopping = YES;
  if ([task isRunning])
    [task terminate];
}

/* It stopped without being asked: start it again, unless it keeps
   stopping. Then the module is the likely cause: Black, once. */
- (void)backgroundDidStop:(NSNotification *)note
{
  [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:task];
  if (stopping)
    return;
  NSDate *now = [NSDate date];
  [exits addObject:now];
  while ([exits count] > 0
         && [now timeIntervalSinceDate:[exits objectAtIndex:0]] > FVBackgroundExitWindow)
    [exits removeObjectAtIndex:0];
  NSLog (@"Workspace: the desktop background stopped (status %d)", [task terminationStatus]);
  if ([exits count] >= FVBackgroundMaxExits)
    {
      if ([[[self class] settingForKey:@"currentModule"] isEqual:@"Black"])
        {
          NSLog (@"Workspace: the desktop background keeps stopping; leaving it off");
          return;
        }
      NSLog (@"Workspace: the desktop background keeps stopping; switching to Black");
      [[self class] setSetting:@"Black" forKey:@"currentModule"];
      [exits removeAllObjects];
    }
  [self performSelector:@selector (start) withObject:nil afterDelay:1.0];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (task);
  RELEASE (exits);
  DEALLOC;
}

@end
