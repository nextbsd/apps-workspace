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

#import "FVApplication.h"
#import "FVWindow.h"
#import "FVThumbnails.h"
#import "FVDesktopSettings.h"

static void
FVMenu (NSMenu *root, NSString *title, NSArray *labels, NSArray *actions, NSArray *keys)
{
  id<NSMenuItem> parent = [root addItemWithTitle:title action:NULL keyEquivalent:@""];
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:title]);
  NSUInteger i;
  for (i = 0; i < [labels count]; i++)
    [menu addItemWithTitle:[labels objectAtIndex:i]
                    action:NSSelectorFromString ([actions objectAtIndex:i])
             keyEquivalent:[keys objectAtIndex:i]];
  [root setSubmenu:menu forItem:parent];
  if ([title isEqual:@"Window"])
    [NSApp setWindowsMenu:menu];
}

/* Workspace starts at login, so make sure the standard home folders exist. */
static void
FVCreateStandardUserFolders (void)
{
  NSArray *names = [NSArray arrayWithObjects:@"Applications", @"Desktop", @"Documents",
      @"Downloads", @"Images", @"Music", @"Public", @"Templates", @"Videos", nil];
  NSUInteger i;
  for (i = 0; i < [names count]; i++)
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[NSHomeDirectory () stringByAppendingPathComponent:[names objectAtIndex:i]]
        withIntermediateDirectories:YES attributes:nil error:NULL];
}

/* Workspace was FileViewer. The first time it starts, bring FileViewer's
   settings over, except the saved main menu position: one saved under an X11
   window manager is offset by its frame. */
static void
FVMigrateFileViewerDefaults (void)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *domainName = [[NSBundle mainBundle] bundleIdentifier];
  NSMutableDictionary *old;
  id frame;

  if (domainName == nil || [[defaults persistentDomainForName:domainName] count] > 0)
    return;
  old = AUTORELEASE ([[defaults persistentDomainForName:@"org.gnustep.FileViewer"] mutableCopy]);
  if ([old count] == 0)
    return;
  [old removeObjectForKey:@"NSMenuLocations"];
  frame = [old objectForKey:@"NSWindow Frame FileViewer"];
  if (frame != nil)
    {
      [old setObject:frame forKey:@"NSWindow Frame File Viewer"];
      [old removeObjectForKey:@"NSWindow Frame FileViewer"];
    }
  [defaults setPersistentDomain:old forName:domainName];
  [defaults synchronize];
}

@implementation FVApplication

- (void)applicationWillFinishLaunching:(NSNotification *)note
{
  FVMigrateFileViewerDefaults ();
  FVCreateStandardUserFolders ();
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults synchronize];
  NSMutableDictionary *domain = [NSMutableDictionary dictionaryWithDictionary:
      [defaults persistentDomainForName:NSGlobalDomain]];
  [domain setObject:@"Workspace" forKey:@"GSWorkspaceApplication"];
  [defaults setPersistentDomain:domain forName:NSGlobalDomain];
  [defaults synchronize];
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults synchronize];
  NSMutableDictionary *domain = [NSMutableDictionary dictionaryWithDictionary:
      [defaults persistentDomainForName:NSGlobalDomain]];
  if ([[domain objectForKey:@"GSWorkspaceApplication"] isEqual:@"Workspace"])
    {
      [domain removeObjectForKey:@"GSWorkspaceApplication"];
      [defaults setPersistentDomain:domain forName:NSGlobalDomain];
      [defaults synchronize];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  windows = [[NSMutableArray alloc] init];
  NSImage *icon = [NSImage imageNamed:@"Workspace.png"];
  if (icon)
    [NSApp setApplicationIconImage:icon];
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Workspace"]);
  [menu addItemWithTitle:@"About Workspace"
                  action:@selector (orderFrontStandardAboutPanel:)
           keyEquivalent:@""];
  id<NSMenuItem> preferences = [menu addItemWithTitle:@"Preferences…"
      action:@selector (preferences:) keyEquivalent:@","];
  [preferences setTarget:self];
  FVMenu (menu, @"File",
          [NSArray arrayWithObjects:@"New Window", @"Open", @"Open With…",
                                    @"Open Folder in New Window", @"Show Package Contents",
                                    @"New Folder", @"Rename", @"Delete Permanently…", @"Get Info",
                                    @"Add to Favorites", @"Close", nil],
          [NSArray arrayWithObjects:@"newWindow:", @"open:", @"openWith:", @"openNewWindow:",
                                    @"packageContents:", @"newFolder:", @"rename:", @"deletePermanently:", @"info:",
                                    @"addFavorite:", @"performClose:", nil],
          [NSArray arrayWithObjects:@"n", @"o", @"", @"", @"", @"", @"", @"", @"i", @"t", @"w", nil]);
  /* Command-Control-T, as on macOS. */
  [[[[menu itemWithTitle:@"File"] submenu] itemWithTitle:@"Add to Favorites"]
      setKeyEquivalentModifierMask:NSCommandKeyMask | NSControlKeyMask];
  FVMenu (
      menu, @"Edit",
      [NSArray arrayWithObjects:@"Undo Last Safe Operation", @"Cut", @"Copy", @"Paste",
                                @"Select All", @"Copy Path", @"Duplicate", @"Move To…",
                                @"Move to Trash", @"Delete Permanently…", @"Cancel Work", nil],
      [NSArray arrayWithObjects:@"undo:", @"cut:", @"copy:", @"paste:", @"selectAll:", @"copyPath:",
                                @"duplicate:", @"moveTo:", @"trash:", @"deletePermanently:",
                                @"cancel:", nil],
      [NSArray arrayWithObjects:@"z", @"x", @"c", @"v", @"a", @"", @"d", @"", @"", @"", @".", nil]);
  FVMenu (menu, @"View",
          [NSArray arrayWithObjects:@"List", @"Columns", @"Icons", @"Larger Icons",
                                    @"Smaller Icons", @"Show Hidden Files", @"Folders First",
                                    @"Refresh", @"Search", nil],
          [NSArray arrayWithObjects:@"listMode:", @"columnMode:", @"iconMode:", @"largerIcons:",
                                    @"smallerIcons:", @"toggleHidden:", @"toggleFolders:",
                                    @"refresh:", @"search:", nil],
          [NSArray arrayWithObjects:@"1", @"2", @"3", @"+", @"-", @"h", @"", @"r", @"f", nil]);
  FVMenu (menu, @"Go",
          [NSArray arrayWithObjects:@"Back", @"Forward", @"Parent Folder", @"Home",
                                    @"Go to Folder…", nil],
          [NSArray arrayWithObjects:@"back:", @"forward:", @"parent:", @"home:", @"go:", nil],
          [NSArray arrayWithObjects:@"[", @"]", @"u", @"", @"g", nil]);
  FVMenu (menu, @"Window", [NSArray arrayWithObject:@"Minimize"],
          [NSArray arrayWithObject:@"performMiniaturize:"], [NSArray arrayWithObject:@"m"]);
  FVMenu (menu, @"Help", [NSArray arrayWithObject:@"Workspace Help"],
          [NSArray arrayWithObject:@"help:"], [NSArray arrayWithObject:@"?"]);
  [menu addItemWithTitle:@"Quit" action:@selector (terminate:) keyEquivalent:@"q"];
  [NSApp setMainMenu:menu];
  launched = YES;
  if ([pendingPaths count])
    {
      NSUInteger i;
      for (i = 0; i < [pendingPaths count]; i++)
        [self openPath:[pendingPaths objectAtIndex:i]];
    }
  else
    [self openPath:NSHomeDirectory ()];
}

- (void)openPath:(NSString *)value
{
  FVWindow *controller = [[FVWindow alloc] initWithPath:value];
  [windows addObject:controller];
  [controller showWindow:self];
  RELEASE (controller);
}

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
  BOOL directory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&directory]
      || !directory)
    return NO;
  if (launched)
    [self openPath:filename];
  else
    {
      if (!pendingPaths)
        pendingPaths = [[NSMutableArray alloc] init];
      [pendingPaths addObject:filename];
    }
  return YES;
}

/* GNUstep sends workspace requests to the application delegate over DO. */
- (BOOL)openFile:(NSString *)path withApplication:(NSString *)application
    andDeactivate:(BOOL)flag
{
  BOOL directory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory])
    return NO;
  if (application == nil && directory
      && ![[NSWorkspace sharedWorkspace] isFilePackageAtPath:path])
    {
      BOOL opened = [self application:NSApp openFile:path];
      if (opened && flag)
        [NSApp activateIgnoringOtherApps:YES];
      return opened;
    }
  /* NSWorkspace bypasses delegation inside the configured workspace itself. */
  return [[NSWorkspace sharedWorkspace] openFile:path
      withApplication:application andDeactivate:flag];
}

- (void)viewerClosed:(id)controller
{
  [windows removeObjectIdenticalTo:controller];
}

- (void)newWindow:(id)sender
{
  [self openPath:NSHomeDirectory ()];
}

/* Help → Workspace Help shows the help document bundled with the app,
   Resources/WorkspaceHelp.rtf, in a window of its own. */
- (void)help:(id)sender
{
  if (!helpWindow)
    {
      NSString *file = [[NSBundle mainBundle] pathForResource:@"WorkspaceHelp" ofType:@"rtf"];
      NSData *data = file ? [NSData dataWithContentsOfFile:file] : nil;
      NSMutableAttributedString *text = data
          ? AUTORELEASE ([[NSMutableAttributedString alloc] initWithRTF:data
                                                    documentAttributes:NULL])
          : nil;
      if (![text length])
        {
          FVRunAlert (@"Workspace Help", @"Help isn’t available.",
                      @"The help document is missing from Workspace.app. Reinstall Workspace.",
                      @"OK", nil);
          return;
        }
      /* Follow the theme's text colour and fonts rather than the document's
         black Helvetica: headings (larger than 13 points) are bold. */
      [text addAttribute:NSForegroundColorAttributeName
                   value:[NSColor textColor]
                   range:NSMakeRange (0, [text length])];
      NSUInteger index = 0;
      while (index < [text length])
        {
          NSRange run;
          NSFont *font = [text attribute:NSFontAttributeName atIndex:index effectiveRange:&run];
          CGFloat size = font ? [font pointSize] : 12;
          [text addAttribute:NSFontAttributeName
                       value:size > 13 ? [NSFont boldSystemFontOfSize:size]
                                       : [NSFont systemFontOfSize:size + 1]
                       range:run];
          index = NSMaxRange (run);
        }
      helpWindow = [[NSWindow alloc]
          initWithContentRect:NSMakeRect (0, 0, 620, 640)
                    styleMask:NSTitledWindowMask | NSClosableWindowMask
                              | NSMiniaturizableWindowMask | NSResizableWindowMask
                      backing:NSBackingStoreBuffered
                        defer:NO];
      [helpWindow setTitle:@"Workspace Help"];
      [helpWindow setReleasedWhenClosed:NO];
      [helpWindow setMinSize:NSMakeSize (360, 240)];
      NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc]
          initWithFrame:[[helpWindow contentView] bounds]]);
      [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [scroll setHasVerticalScroller:YES];
      NSTextView *view = AUTORELEASE ([[NSTextView alloc]
          initWithFrame:NSMakeRect (0, 0, [scroll contentSize].width, [scroll contentSize].height)]);
      [view setEditable:NO];
      [view setSelectable:YES];
      [view setRichText:YES];
      [view setBackgroundColor:[NSColor textBackgroundColor]];
      [view setTextContainerInset:NSMakeSize (16, 16)];
      [view setVerticallyResizable:YES];
      [view setHorizontallyResizable:NO];
      [view setAutoresizingMask:NSViewWidthSizable];
      [[view textContainer] setWidthTracksTextView:YES];
      [[view textStorage] setAttributedString:text];
      [scroll setDocumentView:view];
      [[helpWindow contentView] addSubview:scroll];
      [helpWindow center];
      [helpWindow setFrameAutosaveName:@"Workspace Help"];
    }
  [helpWindow makeKeyAndOrderFront:self];
}

- (void)preferences:(id)sender
{
  if (!preferencesPanel)
    {
      preferencesPanel = [[NSPanel alloc]
          initWithContentRect:NSMakeRect (0, 0, 540, 230)
                    styleMask:NSTitledWindowMask | NSClosableWindowMask
                      backing:NSBackingStoreBuffered defer:NO];
      [preferencesPanel setTitle:@"Preferences"];
      [preferencesPanel setReleasedWhenClosed:NO];
      /* General: the file viewer's settings. Desktop: NextBSD's desktop
         settings, whose defaults come from the theme. */
      NSTabView *tabs = AUTORELEASE ([[NSTabView alloc]
          initWithFrame:NSMakeRect (10, 10, 520, 210)]);
      [[preferencesPanel contentView] addSubview:tabs];
      NSRect page = [tabs contentRect];
      page.origin = NSZeroPoint;
      NSView *general = AUTORELEASE ([[NSView alloc] initWithFrame:page]);
      CGFloat top = NSHeight (page);
      thumbnailCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect (20, top - 44, 390, 28)];
      [thumbnailCheckbox setButtonType:NSSwitchButton];
      [thumbnailCheckbox setTitle:@"Show thumbnails"];
      [thumbnailCheckbox setTarget:self];
      [thumbnailCheckbox setAction:@selector (toggleThumbnails:)];
      [general addSubview:thumbnailCheckbox];
      hiddenFilesCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect (20, top - 84, 390, 28)];
      [hiddenFilesCheckbox setButtonType:NSSwitchButton];
      [hiddenFilesCheckbox setTitle:@"Show hidden files and directories"];
      [hiddenFilesCheckbox setTarget:self];
      [hiddenFilesCheckbox setAction:@selector (toggleHiddenFiles:)];
      [general addSubview:hiddenFilesCheckbox];
      [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector (hiddenFilesPreferencesChanged:) name:@"FVHiddenFilesChanged" object:nil];
      NSTextField *label = AUTORELEASE ([[NSTextField alloc]
          initWithFrame:NSMakeRect (24, 12, 380, 24)]);
      [label setStringValue:@"Changes apply to all open windows."];
      [label setEditable:NO];
      [label setSelectable:NO];
      [label setBordered:NO];
      [label setBezeled:NO];
      [label setDrawsBackground:NO];
      [general addSubview:label];
      NSTabViewItem *item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"General"]);
      [item setLabel:@"General"];
      [item setView:general];
      [tabs addTabViewItem:item];
      desktopSettings = [[FVDesktopSettings alloc] initWithFrame:page];
      item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"Desktop"]);
      [item setLabel:@"Desktop"];
      [item setView:[desktopSettings view]];
      [tabs addTabViewItem:item];
      [preferencesPanel center];
    }
  [thumbnailCheckbox setState:[FVThumbnailOperation enabled] ? NSOnState : NSOffState];
  [self hiddenFilesPreferencesChanged:nil];
  [desktopSettings refresh];
  [preferencesPanel makeKeyAndOrderFront:self];
}

- (void)toggleThumbnails:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setBool:[sender state] == NSOnState
                                         forKey:@"ShowThumbnails"];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"FVThumbnailPreferencesChanged"
                                                    object:self];
}

- (void)toggleHiddenFiles:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setBool:[sender state] == NSOnState forKey:@"Hidden"];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"FVHiddenFilesChanged" object:self];
}

- (void)hiddenFilesPreferencesChanged:(NSNotification *)notification
{
  [hiddenFilesCheckbox setState:[[NSUserDefaults standardUserDefaults] boolForKey:@"Hidden"]
      ? NSOnState : NSOffState];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  RELEASE (hiddenFilesCheckbox);
  RELEASE (thumbnailCheckbox);
  RELEASE (desktopSettings);
  RELEASE (preferencesPanel);
  RELEASE (helpWindow);
  RELEASE (windows);
  RELEASE (pendingPaths);
  DEALLOC;
}

@end
