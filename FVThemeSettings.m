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

#import "FVThemeSettings.h"
#import <GNUstepGUI/GSTheme.h>

static NSTextField *
FVTLabel (NSRect frame, NSString *text)
{
  NSTextField *f = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [f setStringValue:text];
  [f setEditable:NO];
  [f setSelectable:NO];
  [f setBordered:NO];
  [f setBezeled:NO];
  [f setDrawsBackground:NO];
  return f;
}

@implementation FVThemeSettings

- (NSArray *)installedThemes
{
  NSMutableArray *names = [NSMutableArray array];
  NSArray *dirs = NSSearchPathForDirectoriesInDomains (NSLibraryDirectory,
                                                       NSAllDomainsMask, YES);
  NSFileManager *fm = [NSFileManager defaultManager];
  NSEnumerator *de = [dirs objectEnumerator];
  NSString *dir;
  while ((dir = [de nextObject]) != nil)
    {
      NSString *themesDir = [dir stringByAppendingPathComponent:@"Themes"];
      NSArray *files = [fm directoryContentsAtPath:themesDir];
      NSEnumerator *fe = [files objectEnumerator];
      NSString *file;
      while ((file = [fe nextObject]) != nil)
        {
          if ([[file pathExtension] isEqual:@"theme"])
            {
              NSString *name = [file stringByDeletingPathExtension];
              if (![names containsObject:name])
                [names addObject:name];
            }
        }
    }
  [names sortUsingSelector:@selector (compare:)];
  return names;
}

- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super init]) == nil)
    return nil;
  view = [[NSView alloc] initWithFrame:frame];
  CGFloat y = NSHeight (frame) - 46;
  CGFloat labelWidth = 150;
  CGFloat popUpX = 20 + labelWidth + 8;

  NSTextField *label = FVTLabel (NSMakeRect (20, y - 1, labelWidth, 22), @"Theme:");
  [label setAlignment:NSRightTextAlignment];
  [view addSubview:label];

  themePopUp = [[NSPopUpButton alloc]
      initWithFrame:NSMakeRect (popUpX, y, NSWidth (frame) - popUpX - 20, 26)
          pullsDown:NO];
  [themePopUp setTarget:self];
  [themePopUp setAction:@selector (choose:)];
  [view addSubview:themePopUp];

  [view addSubview:FVTLabel (NSMakeRect (20, 8, NSWidth (frame) - 40, 36),
      @"The theme sets the system colors, fonts, and window decorations.\n"
      @"Changes apply at once.")];

  [self refresh];
  return self;
}

- (NSView *)view
{
  return view;
}

- (void)refresh
{
  [[NSUserDefaults standardUserDefaults] synchronize];
  NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:@"GSTheme"];
  if ([current length] == 0)
    current = @"GNUstep";

  NSArray *themes = [self installedThemes];
  [themePopUp removeAllItems];
  [themePopUp addItemWithTitle:@"Default (GNUstep)"];
  [[themePopUp lastItem] setRepresentedObject:@"GNUstep"];

  NSEnumerator *e = [themes objectEnumerator];
  NSString *name;
  while ((name = [e nextObject]) != nil)
    {
      [themePopUp addItemWithTitle:name];
      [[themePopUp lastItem] setRepresentedObject:name];
    }

  NSInteger i = [themePopUp indexOfItemWithRepresentedObject:current];
  [themePopUp selectItemAtIndex:i < 0 ? 0 : i];
}

- (void)choose:(id)sender
{
  NSString *name = [[sender selectedItem] representedObject];
  if (name == nil)
    return;
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *global = AUTORELEASE ([[defaults persistentDomainForName:NSGlobalDomain]
      mutableCopy]);
  if (global == nil)
    global = [NSMutableDictionary dictionary];
  if ([name isEqual:@"GNUstep"])
    [global removeObjectForKey:@"GSTheme"];
  else
    [global setObject:name forKey:@"GSTheme"];
  [defaults setPersistentDomain:global forName:NSGlobalDomain];
  [defaults synchronize];
  [GSTheme setTheme:[GSTheme loadThemeNamed:name]];
}

- (void)dealloc
{
  RELEASE (themePopUp);
  RELEASE (view);
  DEALLOC;
}

@end
