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

#import "FVInspector.h"
#import "FVWindow.h"
#import "FVOperations.h"
#import "FVPanels.h"
#include <sys/stat.h>
#include <pwd.h>
#include <grp.h>
#include <unistd.h>

/* Counts the total size of some paths off the main thread. */
@interface FVSizeJob : NSObject
{
@public
  NSArray *paths;
  id target;
  NSUInteger generation;
  volatile BOOL stop;
}
@end

@implementation FVSizeJob

- (void)run
{
  CREATE_AUTORELEASE_POOL (pool);
  unsigned long long total = 0, entries = 0;
  NSUInteger i;
  for (i = 0; i < [paths count] && !stop; i++)
    {
      unsigned long long count = 0;
      total += FVTreeSize ([paths objectAtIndex:i], &count, &stop);
      entries += count;
    }
  if (!stop)
    [target performSelectorOnMainThread:@selector (sizeComputed:)
                             withObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithUnsignedLongLong:total], @"total",
                                 [NSNumber numberWithUnsignedLongLong:entries], @"entries",
                                 [NSNumber numberWithUnsignedInteger:generation], @"generation",
                                 nil]
                          waitUntilDone:NO];
  RELEASE (pool);
}

- (void)dealloc
{
  RELEASE (paths);
  RELEASE (target);
  DEALLOC;
}

@end

static NSString *
FVUserName (uid_t uid)
{
  struct passwd *entry = getpwuid (uid);
  return entry ? [NSString stringWithUTF8String:entry->pw_name]
               : [NSString stringWithFormat:@"%lu", (unsigned long)uid];
}

static NSString *
FVGroupName (gid_t gid)
{
  struct group *entry = getgrgid (gid);
  return entry ? [NSString stringWithUTF8String:entry->gr_name]
               : [NSString stringWithFormat:@"%lu", (unsigned long)gid];
}

static NSTextField *
FVInspectorLabel (NSView *view, NSRect frame, NSString *text, BOOL bold)
{
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [field setEditable:NO];
  [field setSelectable:NO];
  [field setBezeled:NO];
  [field setBordered:NO];
  [field setDrawsBackground:NO];
  [field setFont:bold ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]
                      : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [[field cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [field setStringValue:text];
  [view addSubview:field];
  return field;
}

static const CGFloat FVInspectorWidth = 380, FVInspectorHeight = 520;

@implementation FVInspector

+ (FVInspector *)sharedInspector
{
  static FVInspector *shared = nil;
  if (!shared)
    shared = [[FVInspector alloc] init];
  return shared;
}

- (NSPanel *)panel
{
  return panel;
}

- (NSArray *)paths
{
  return paths;
}

- (void)buildPanel
{
  panel = [[NSPanel alloc]
      initWithContentRect:NSMakeRect (0, 0, FVInspectorWidth, FVInspectorHeight)
                styleMask:NSTitledWindowMask | NSClosableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [panel setTitle:@"Inspector"];
  [panel setReleasedWhenClosed:NO];
  [panel setHidesOnDeactivate:NO];
  [panel setFloatingPanel:YES];
  NSView *content = [panel contentView];
  NSColor *color = FVDialogTextColor (panel);
  CGFloat top = FVInspectorHeight;
  icon = [[NSImageView alloc] initWithFrame:NSMakeRect (16, top - 80, 64, 64)];
  [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
  [icon setEditable:NO];
  [content addSubview:icon];
  nameField = [[NSTextField alloc] initWithFrame:NSMakeRect (92, top - 48, 272, 26)];
  [nameField setTarget:self];
  [nameField setAction:@selector (rename:)];
  [nameField setToolTip:@"Type a new name and press Return to rename."];
  [content addSubview:nameField];
  kindLabel = RETAIN (FVInspectorLabel (content, NSMakeRect (94, top - 74, 270, 20), @"", NO));
  [kindLabel setTextColor:color];

  values = [[NSMutableDictionary alloc] init];
  NSArray *rows = [NSArray arrayWithObjects:@"Size", @"Location", @"Created", @"Modified",
                                            @"Link to", nil];
  CGFloat y = top - 120;
  NSUInteger i;
  for (i = 0; i < [rows count]; i++, y -= 24)
    {
      NSString *title = [rows objectAtIndex:i];
      NSTextField *label = FVInspectorLabel (content, NSMakeRect (12, y, 84, 20),
                                             [title stringByAppendingString:@":"], YES);
      [label setAlignment:NSRightTextAlignment];
      [label setTextColor:color];
      NSTextField *value = FVInspectorLabel (content, NSMakeRect (104, y, 262, 20), @"", NO);
      [value setTextColor:color];
      [values setObject:value forKey:title];
      [values setObject:label forKey:[title stringByAppendingString:@" label"]];
    }

  y -= 18;
  NSTextField *heading = FVInspectorLabel (content, NSMakeRect (16, y, 340, 20),
                                           @"Ownership and Permissions", YES);
  [heading setTextColor:color];
  y -= 34;
  NSTextField *ownerLabel = FVInspectorLabel (content, NSMakeRect (12, y + 4, 84, 20), @"Owner:", YES);
  [ownerLabel setAlignment:NSRightTextAlignment];
  [ownerLabel setTextColor:color];
  ownerPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (104, y, 200, 26) pullsDown:NO];
  [ownerPopUp setTarget:self];
  [ownerPopUp setAction:@selector (changed:)];
  [content addSubview:ownerPopUp];
  y -= 32;
  NSTextField *groupLabel = FVInspectorLabel (content, NSMakeRect (12, y + 4, 84, 20), @"Group:", YES);
  [groupLabel setAlignment:NSRightTextAlignment];
  [groupLabel setTextColor:color];
  groupPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (104, y, 200, 26) pullsDown:NO];
  [groupPopUp setTarget:self];
  [groupPopUp setAction:@selector (changed:)];
  [content addSubview:groupPopUp];

  /* Read/Write/Execute for Owner, Group and Others, as NeXTSTEP's grid. */
  y -= 34;
  NSArray *columns = [NSArray arrayWithObjects:@"Read", @"Write", @"Execute", nil];
  NSArray *classes = [NSArray arrayWithObjects:@"Owner", @"Group", @"Others", nil];
  for (i = 0; i < [columns count]; i++)
    {
      NSTextField *label = FVInspectorLabel (content, NSMakeRect (104 + i * 80, y, 76, 20),
                                             [columns objectAtIndex:i], YES);
      [label setTextColor:color];
    }
  permissionBoxes = [[NSMutableArray alloc] init];
  NSUInteger row;
  for (row = 0; row < [classes count]; row++)
    {
      y -= 26;
      NSTextField *label = FVInspectorLabel (content, NSMakeRect (12, y + 2, 84, 20),
                                             [classes objectAtIndex:row], YES);
      [label setAlignment:NSRightTextAlignment];
      [label setTextColor:color];
      for (i = 0; i < [columns count]; i++)
        {
          NSButton *box = AUTORELEASE ([[NSButton alloc]
              initWithFrame:NSMakeRect (110 + i * 80, y, 24, 24)]);
          [box setButtonType:NSSwitchButton];
          [box setTitle:@""];
          /* Bit for this class and right: owner read is 0400. */
          [box setTag:(4 >> i) << (3 * (2 - row))];
          [box setTarget:self];
          [box setAction:@selector (changed:)];
          [box setToolTip:[NSString stringWithFormat:@"%@ can %@", [classes objectAtIndex:row],
                              [[columns objectAtIndex:i] lowercaseString]]];
          [content addSubview:box];
          [permissionBoxes addObject:box];
        }
    }
  y -= 44;
  permissionNote = RETAIN (FVInspectorLabel (content, NSMakeRect (16, y, 350, 34), @"", NO));
  [[permissionNote cell] setWraps:YES];
  [[permissionNote cell] setLineBreakMode:NSLineBreakByWordWrapping];
  [permissionNote setTextColor:color];
  revertButton = [[NSButton alloc] initWithFrame:NSMakeRect (FVInspectorWidth - 220, 14, 96, 30)];
  [revertButton setTitle:@"Revert"];
  [revertButton setTarget:self];
  [revertButton setAction:@selector (revert:)];
  [content addSubview:revertButton];
  applyButton = [[NSButton alloc] initWithFrame:NSMakeRect (FVInspectorWidth - 114, 14, 96, 30)];
  [applyButton setTitle:@"Apply"];
  [applyButton setTarget:self];
  [applyButton setAction:@selector (apply:)];
  [content addSubview:applyButton];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector (panelWillClose:)
                                               name:NSWindowWillCloseNotification
                                             object:panel];
  if (![panel setFrameUsingName:@"Inspector"])
    [panel center];
  [panel setFrameAutosaveName:@"Inspector"];
}

- (void)setValue:(NSString *)text forRow:(NSString *)row
{
  NSTextField *field = [values objectForKey:row];
  BOOL show = text != nil;
  [field setStringValue:show ? text : @""];
  [field setToolTip:show ? text : nil];
  [field setHidden:!show];
  [[values objectForKey:[row stringByAppendingString:@" label"]] setHidden:!show];
}

- (void)stopSizeJob
{
  if (sizeJob)
    ((FVSizeJob *)sizeJob)->stop = YES;
  RELEASE (sizeJob);
  sizeJob = nil;
}

- (void)countSizeOf:(NSArray *)folders
{
  FVSizeJob *job = [[FVSizeJob alloc] init];
  job->paths = [folders copy];
  job->target = RETAIN (self);
  job->generation = generation;
  sizeJob = job;
  [NSThread detachNewThreadSelector:@selector (run) toTarget:job withObject:nil];
}

- (void)sizeComputed:(NSDictionary *)result
{
  if ([[result objectForKey:@"generation"] unsignedIntegerValue] != generation)
    return;
  RELEASE (sizeJob);
  sizeJob = nil;
  unsigned long long total = [[result objectForKey:@"total"] unsignedLongLongValue];
  unsigned long long entries = [[result objectForKey:@"entries"] unsignedLongLongValue];
  /* The count includes each folder itself. */
  if ([paths count] == 1 && entries)
    entries--;
  [self setValue:[paths count] == 1
                     ? [NSString stringWithFormat:@"%@ in %llu %@", FVSizeString (total), entries,
                                                  entries == 1 ? @"item" : @"items"]
                     : [NSString stringWithFormat:@"%@ in all", FVSizeString (total)]
          forRow:@"Size"];
}

/* Fills the owner and group menus. Only root may give an item away; its
   owner may choose among the groups they belong to. */
- (void)loadOwner:(uid_t)uid group:(gid_t)gid editable:(BOOL)editable
{
  BOOL root = getuid () == 0;
  [ownerPopUp removeAllItems];
  [groupPopUp removeAllItems];
  NSMutableArray *owners = [NSMutableArray array], *groups = [NSMutableArray array];
  if (root && editable)
    {
      struct passwd *user;
      setpwent ();
      while ((user = getpwent ()))
        [owners addObject:[NSNumber numberWithUnsignedLong:user->pw_uid]];
      endpwent ();
      struct group *entry;
      setgrent ();
      while ((entry = getgrent ()))
        [groups addObject:[NSNumber numberWithUnsignedLong:entry->gr_gid]];
      endgrent ();
    }
  else if (editable)
    {
      gid_t list[NGROUPS_MAX + 1];
      int count = getgroups (NGROUPS_MAX, list), i;
      for (i = 0; i < count; i++)
        [groups addObject:[NSNumber numberWithUnsignedLong:list[i]]];
      [groups addObject:[NSNumber numberWithUnsignedLong:getegid ()]];
    }
  NSNumber *currentOwner = [NSNumber numberWithUnsignedLong:uid];
  NSNumber *currentGroup = [NSNumber numberWithUnsignedLong:gid];
  if (![owners containsObject:currentOwner])
    [owners addObject:currentOwner];
  if (![groups containsObject:currentGroup])
    [groups addObject:currentGroup];
  NSUInteger i;
  for (i = 0; i < [owners count]; i++)
    {
      NSString *title = FVUserName ([[owners objectAtIndex:i] unsignedLongValue]);
      if ([ownerPopUp indexOfItemWithTitle:title] >= 0)
        continue;
      [ownerPopUp addItemWithTitle:title];
      [[ownerPopUp lastItem] setRepresentedObject:[owners objectAtIndex:i]];
    }
  for (i = 0; i < [groups count]; i++)
    {
      NSString *title = FVGroupName ([[groups objectAtIndex:i] unsignedLongValue]);
      if ([groupPopUp indexOfItemWithTitle:title] >= 0)
        continue;
      [groupPopUp addItemWithTitle:title];
      [[groupPopUp lastItem] setRepresentedObject:[groups objectAtIndex:i]];
    }
  [ownerPopUp selectItemWithTitle:FVUserName (uid)];
  [groupPopUp selectItemWithTitle:FVGroupName (gid)];
  [ownerPopUp setEnabled:root && editable];
  [groupPopUp setEnabled:editable && [groupPopUp numberOfItems] > 1];
}

- (void)setPermissionsEnabled:(BOOL)enabled mode:(mode_t)mode
{
  NSUInteger i;
  for (i = 0; i < [permissionBoxes count]; i++)
    {
      NSButton *box = [permissionBoxes objectAtIndex:i];
      [box setState:(mode & [box tag]) ? NSOnState : NSOffState];
      [box setEnabled:enabled];
    }
}

- (void)reload
{
  generation++;
  [self stopSizeJob];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSUInteger count = [paths count];
  [applyButton setEnabled:NO];
  [revertButton setEnabled:NO];
  if (count == 1)
    {
      NSString *item = [paths objectAtIndex:0];
      FVItem *info = [FVItem itemAtPath:item];
      NSDictionary *attributes = [info attributes];
      struct stat st;
      BOOL exists = lstat ([item fileSystemRepresentation], &st) == 0;
      [icon setImage:[viewer iconForPath:item]];
      [nameField setStringValue:[item lastPathComponent]];
      [nameField setEditable:exists && ![item isEqual:@"/"]];
      [nameField setEnabled:exists && ![item isEqual:@"/"]];
      [kindLabel setStringValue:[info kind]];
      if ([info directory])
        {
          [self setValue:@"Calculating…" forRow:@"Size"];
          [self countSizeOf:paths];
        }
      else if (exists)
        [self setValue:st.st_size < 1000 ? FVSizeString (st.st_size)
                                         : [NSString stringWithFormat:@"%@ (%llu bytes)",
                                                FVSizeString (st.st_size),
                                                (unsigned long long)st.st_size]
                forRow:@"Size"];
      else
        [self setValue:@"Unavailable" forRow:@"Size"];
      [self setValue:[item stringByDeletingLastPathComponent] forRow:@"Location"];
      [self setValue:[attributes fileCreationDate] ? FVDateString ([attributes fileCreationDate])
                                                   : @"Unknown"
              forRow:@"Created"];
      [self setValue:FVDateString ([attributes fileModificationDate]) forRow:@"Modified"];
      [self setValue:[info link] ? [fm pathContentOfSymbolicLinkAtPath:item] : nil
              forRow:@"Link to"];
      BOOL mayChange = exists && (getuid () == 0 || st.st_uid == getuid ());
      BOOL link = exists && S_ISLNK (st.st_mode);
      [self loadOwner:exists ? st.st_uid : 0 group:exists ? st.st_gid : 0 editable:mayChange];
      [self setPermissionsEnabled:mayChange && !link mode:exists ? st.st_mode : 0];
      if (!exists)
        [permissionNote setStringValue:@"This item is no longer there."];
      else if (link)
        [permissionNote setStringValue:@"A symbolic link has no permissions of its own; "
                                       @"inspect the item it points to."];
      else if (!mayChange)
        [permissionNote setStringValue:[NSString stringWithFormat:
            @"Only %@ or an administrator can change these.", FVUserName (st.st_uid)]];
      else
        [permissionNote setStringValue:getuid () == 0
            ? @"Changes apply when you click Apply."
            : @"Changes apply when you click Apply. Only an administrator can change the owner."];
      return;
    }
  /* Several items: one combined summary. */
  NSUInteger folders = 0, i;
  NSString *location = nil;
  BOOL sameLocation = YES;
  unsigned long long bytes = 0;
  for (i = 0; i < count; i++)
    {
      NSString *item = [paths objectAtIndex:i];
      FVItem *info = [FVItem itemAtPath:item];
      if ([info directory])
        folders++;
      else
        bytes += [[info attributes] fileSize];
      NSString *parent = [item stringByDeletingLastPathComponent];
      if (!location)
        location = parent;
      else if (![location isEqual:parent])
        sameLocation = NO;
    }
  [icon setImage:[viewer iconForPath:[paths objectAtIndex:0]]];
  [nameField setStringValue:[NSString stringWithFormat:@"%lu items", (unsigned long)count]];
  [nameField setEditable:NO];
  [nameField setEnabled:NO];
  NSUInteger files = count - folders;
  NSMutableArray *kinds = [NSMutableArray array];
  if (folders)
    [kinds addObject:[NSString stringWithFormat:folders == 1 ? @"%lu folder" : @"%lu folders",
                                                (unsigned long)folders]];
  if (files)
    [kinds addObject:[NSString stringWithFormat:files == 1 ? @"%lu file" : @"%lu files",
                                                (unsigned long)files]];
  [kindLabel setStringValue:[kinds componentsJoinedByString:@", "]];
  if (folders)
    {
      [self setValue:@"Calculating…" forRow:@"Size"];
      [self countSizeOf:paths];
    }
  else
    [self setValue:[NSString stringWithFormat:@"%@ in all", FVSizeString (bytes)] forRow:@"Size"];
  [self setValue:sameLocation ? location : @"Several folders" forRow:@"Location"];
  [self setValue:nil forRow:@"Created"];
  [self setValue:nil forRow:@"Modified"];
  [self setValue:nil forRow:@"Link to"];
  [ownerPopUp removeAllItems];
  [groupPopUp removeAllItems];
  [ownerPopUp setEnabled:NO];
  [groupPopUp setEnabled:NO];
  [self setPermissionsEnabled:NO mode:0];
  [permissionNote setStringValue:@"Select one item to see or change its owner and permissions."];
}

- (void)inspectViewer:(FVWindow *)controller
{
  NSArray *selected = [controller selectedPaths];
  if (![selected count] && ![[controller currentPath] isEqual:FVRecentsLocation])
    selected = [NSArray arrayWithObject:[controller currentPath]];
  if (![selected count])
    return;
  if (viewer == controller && [selected isEqual:paths])
    return;
  viewer = controller;
  ASSIGN (paths, selected);
  [self reload];
}

- (void)showForViewer:(FVWindow *)controller
{
  if (!panel)
    [self buildPanel];
  RELEASE (paths);
  paths = nil;
  [self inspectViewer:controller];
  [panel orderFront:nil];
}

- (void)viewerSelectionChanged:(FVWindow *)controller
{
  if ([panel isVisible])
    [self inspectViewer:controller];
}

- (void)viewerClosed:(FVWindow *)controller
{
  if (viewer == controller)
    viewer = nil;
}

- (void)panelWillClose:(NSNotification *)note
{
  generation++;
  [self stopSizeJob];
}

- (void)changed:(id)sender
{
  [applyButton setEnabled:YES];
  [revertButton setEnabled:YES];
}

- (void)revert:(id)sender
{
  [self reload];
}

- (void)apply:(id)sender
{
  if ([paths count] != 1)
    return;
  mode_t mode = 0;
  NSUInteger i;
  for (i = 0; i < [permissionBoxes count]; i++)
    if ([[permissionBoxes objectAtIndex:i] state] == NSOnState)
      mode |= [[permissionBoxes objectAtIndex:i] tag];
  NSError *error = nil;
  if (![FVOperations setOwner:[[[ownerPopUp selectedItem] representedObject] unsignedLongValue]
                        group:[[[groupPopUp selectedItem] representedObject] unsignedLongValue]
                  permissions:mode
                       ofPath:[paths objectAtIndex:0]
                        error:&error])
    FVRunAlert (@"Inspector", @"The change couldn’t be made.", [error localizedDescription],
                @"OK", nil);
  [self reload];
  [viewer refresh:nil];
}

- (void)rename:(id)sender
{
  if ([paths count] != 1 || !viewer)
    return;
  NSString *name = [nameField stringValue];
  NSString *problem = [viewer renamePath:[paths objectAtIndex:0] toName:name];
  if (problem)
    {
      NSBeep ();
      FVRunAlert (@"Inspector", @"The item couldn’t be renamed.", problem, @"OK", nil);
      [nameField setStringValue:[[paths objectAtIndex:0] lastPathComponent]];
    }
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self stopSizeJob];
  RELEASE (panel);
  RELEASE (paths);
  RELEASE (icon);
  RELEASE (nameField);
  RELEASE (kindLabel);
  RELEASE (values);
  RELEASE (ownerPopUp);
  RELEASE (groupPopUp);
  RELEASE (permissionBoxes);
  RELEASE (permissionNote);
  RELEASE (applyButton);
  RELEASE (revertButton);
  DEALLOC;
}

@end
