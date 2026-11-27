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
#import "FVBackground.h"
#import "FVDesktop.h"
#import "FVBackgroundSettings.h"
#import "FVDockSettings.h"

/* Preferences' tabs are laid out at full height, from the top and from
   the bottom. FVFitPreferencesTab keeps each control where it was laid
   out when the tab gets shorter: one near the bottom (a note) stays at
   the bottom, one that spans the tab (Background's list) stretches, and
   the rest stay at the top. It returns the height the tab needs. */
static const CGFloat FVTabBottomBand = 60;
static const CGFloat FVTabListMinHeight = 260;

static CGFloat
FVFitPreferencesTab (NSView *tab)
{
  CGFloat full = NSHeight ([tab frame]);
  CGFloat topExtent = 0, bottomExtent = 0, spanning = 0;
  NSEnumerator *e = [[tab subviews] objectEnumerator];
  NSView *v;

  while ((v = [e nextObject]) != nil)
    {
      NSRect r = [v frame];
      if (NSMinY (r) < FVTabBottomBand && NSMaxY (r) > full - FVTabBottomBand)
        {
          [v setAutoresizingMask:NSViewHeightSizable];
          spanning = MAX (spanning, NSMinY (r) + FVTabListMinHeight + (full - NSMaxY (r)));
        }
      else if (NSMinY (r) < FVTabBottomBand)
        bottomExtent = MAX (bottomExtent, NSMaxY (r));
      else
        {
          [v setAutoresizingMask:NSViewMinYMargin];
          topExtent = MAX (topExtent, full - NSMinY (r));
        }
    }
  [tab setAutoresizesSubviews:YES];
  return ceil (MAX (topExtent + bottomExtent + 12, spanning));
}

/* The gap between a window and the menu it moves clear of. */
static const CGFloat FVMenuGap = 8;

void
FVPlaceClearOfMenu (NSWindow *window)
{
  NSWindow *menuWindow = [[NSApp mainMenu] window];
  NSScreen *screen = [window screen] ? [window screen] : [NSScreen mainScreen];
  NSRect area = [screen visibleFrame];
  NSRect frame = [window frame];
  NSRect menu;
  NSSize min = [window minSize];
  BOOL resizable = ([window styleMask] & NSResizableWindowMask) != 0;
  CGFloat right, below;

  if (menuWindow == nil || ![menuWindow isVisible])
    return;
  menu = [menuWindow frame];
  if (!NSIntersectsRect (frame, menu))
    return;

  /* To the menu's right, keeping the window's top where it was, inside
     the usable area. Shrink a resizable window to fit if need be. */
  right = NSMaxX (menu) + FVMenuGap;
  if (right + NSWidth (frame) <= NSMaxX (area)
      || (resizable && NSMaxX (area) - right >= min.width))
    {
      frame.origin.x = right;
      if (NSMaxX (frame) > NSMaxX (area))
        frame.size.width = NSMaxX (area) - right;
    }
  else
    {
      /* No room beside it: below the menu, shrinking a resizable window's
         height to fit. */
      below = NSMinY (menu) - FVMenuGap;
      if (NSHeight (frame) > below - NSMinY (area))
        {
          if (!resizable || below - NSMinY (area) < min.height)
            return;
          frame.size.height = below - NSMinY (area);
        }
      frame.origin.y = below - NSHeight (frame);
    }

  /* Inside the usable area top to bottom: a resizable window shrinks to
     it; one that can't keeps its top on screen. */
  if (NSHeight (frame) > NSHeight (area) && resizable
      && NSHeight (area) >= min.height)
    frame.size.height = NSHeight (area);
  if (NSMaxY (frame) > NSMaxY (area))
    frame.origin.y = NSMaxY (area) - NSHeight (frame);
  if (NSMinY (frame) < NSMinY (area))
    frame.origin.y = NSMinY (area);
  [window setFrame:frame display:NO];
}

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

/* At login, links in ~/Applications to Software, Terminal and TextEdit (in
   /System/Applications, by absolute path, so they hold whether the home is
   under /Network or /Local), wherever one is missing. */
static void
FVPlaceApplicationLinks (void)
{
  NSArray *apps = [NSArray arrayWithObjects:@"Software.app", @"Terminal.app",
                                             @"TextEdit.app", nil];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *folder = [NSHomeDirectory () stringByAppendingPathComponent:@"Applications"];
  NSUInteger i;

  for (i = 0; i < [apps count]; i++)
    {
      NSString *name = [apps objectAtIndex:i];
      NSString *link = [folder stringByAppendingPathComponent:name];
      NSString *app = [@"/System/Applications" stringByAppendingPathComponent:name];

      /* Only to an app that is there: no dead link on a system without it. */
      if ([fm fileAttributesAtPath:link traverseLink:NO] == nil
          && [fm fileExistsAtPath:app])
        [fm createSymbolicLinkAtPath:link pathContent:app];
    }
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
  FVPlaceApplicationLinks ();
  /* The apps and the file types they open, read again at each login
     (make_services): an app installed since this account last logged in,
     or since its first login, opens its files and shows their icons, as
     on a Mac. */
  [[NSWorkspace sharedWorkspace] findApplications];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults synchronize];
  NSMutableDictionary *domain = [NSMutableDictionary dictionaryWithDictionary:
      [defaults persistentDomainForName:NSGlobalDomain]];
  [domain setObject:@"Workspace" forKey:@"GSWorkspaceApplication"];
  [defaults setPersistentDomain:domain forName:NSGlobalDomain];
  [defaults synchronize];
}

/* Workspace keeps running with no File Viewer open. libs-gui quits an app
   whose last window closes in the in-window menu style (Windows'
   convention) unless its delegate says otherwise. */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return NO;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  [[FVBackground sharedBackground] stop];
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
                                    @"Add to Favorites", @"Add to Dock", @"Close", nil],
          [NSArray arrayWithObjects:@"newWindow:", @"open:", @"openWith:", @"openNewWindow:",
                                    @"packageContents:", @"newFolder:", @"rename:", @"deletePermanently:", @"info:",
                                    @"addFavorite:", @"addToDock:", @"performClose:", nil],
          [NSArray arrayWithObjects:@"n", @"o", @"", @"", @"", @"", @"", @"", @"i", @"t", @"", @"w",
                                    nil]);
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
                                    @"Go to Folder…", @"Rewind", nil],
          [NSArray arrayWithObjects:@"back:", @"forward:", @"parent:", @"home:", @"go:",
                                    @"rewind:", nil],
          [NSArray arrayWithObjects:@"[", @"]", @"u", @"", @"g", @"r", nil]);
  /* Command-Option-R: Command-R is Refresh. */
  [[[[menu itemWithTitle:@"Go"] submenu] itemWithTitle:@"Rewind"]
      setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
  FVMenu (menu, @"Window", [NSArray arrayWithObject:@"Minimize"],
          [NSArray arrayWithObject:@"performMiniaturize:"], [NSArray arrayWithObject:@"m"]);
  /* Workspace's book, Resources/Workspace.help, in Help.app: NSApplication's
     -showHelp: finds it. The NextBSD theme puts the help search, this book
     and NextBSD Help at the top of the menu. */
  FVMenu (menu, @"Help", [NSArray arrayWithObject:@"Workspace Help"],
          [NSArray arrayWithObject:@"showHelp:"], [NSArray arrayWithObject:@"?"]);
  /* No Quit: Workspace is the session. The NeXT style's menu ends with
     Log Out, Restart and Shut Down instead (the NextBSD theme), the Mac
     style has them in the NextBSD menu, and Windows in Start. */
  [NSApp setMainMenu:menu];
  launched = YES;
  /* WindowServer tiles or stacks as the window mode in effect says. */
  [FVDesktopSettings syncWindowServer];
  /* GNUstep's scroller keys follow the scroller style, the theme's
     default included. */
  [FVDesktopSettings syncScrollerStyle];
  /* The desktop is Workspace's; its background is drawn by a process of
     its own, under the desktop's clear windows. */
  [[FVDesktop sharedDesktop] show];
  [[FVBackground sharedBackground] start];
  /* Like the Finder, Workspace starts with no File Viewer unless it was
     asked to open a folder: the first one comes when Workspace is opened
     again (see -applicationShouldHandleReopen:hasVisibleWindows:). */
  NSUInteger i;
  for (i = 0; i < [pendingPaths count]; i++)
    [self openPath:[pendingPaths objectAtIndex:i]];
}

/* The File Viewer most recently used, preferring one on screen to a
   minimized one; nil when none is open. */
- (FVWindow *)recentViewer
{
  NSUInteger i;

  for (i = [windows count]; i > 0; i--)
    {
      NSWindow *candidate = [[windows objectAtIndex:i - 1] window];
      if ([candidate isVisible] && ![candidate isMiniaturized])
        return [windows objectAtIndex:i - 1];
    }
  for (i = [windows count]; i > 0; i--)
    if ([[[windows objectAtIndex:i - 1] window] isMiniaturized])
      return [windows objectAtIndex:i - 1];
  return nil;
}

- (void)bringViewerForward:(FVWindow *)controller
{
  NSWindow *window = [controller window];

  if ([window isMiniaturized])
    [window deminiaturize:self];
  [window makeKeyAndOrderFront:self];
}

/* Opening Workspace while it runs (its Dock tile, openapp Workspace, or
   Workspace.app opened from a File Viewer) reopens it, as on macOS: bring
   the most recently used File Viewer forward, restoring it if every one
   is minimized, or open a new one at the home folder if none is open.
   The senders reach the delegate over Distributed Objects (GSListener
   forwards the message), so Workspace counts its own File Viewers rather
   than trusting the flag. */
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag
{
  FVWindow *controller = [self recentViewer];

  [NSApp activateIgnoringOtherApps:YES];
  if (controller == nil)
    [self openPath:NSHomeDirectory ()];
  else
    [self bringViewerForward:controller];
  return NO;
}

/* NSWorkspace -selectFile:inFileViewerRootedAtPath: (the Dock's Show In
   File Viewer, an app's reveal) reaches the delegate over Distributed
   Objects. Workspace comes forward with the file selected in its folder,
   as the Finder does: a File Viewer already showing that folder is
   reused; otherwise a root path asks for a new File Viewer, and an empty
   one for the most recently used (or a new one if none is open). An
   empty file path just shows the root. */
- (BOOL)selectFile:(NSString *)fullPath inFileViewerRootedAtPath:(NSString *)rootFullPath
{
  NSString *file = [fullPath length] ? [fullPath stringByStandardizingPath] : nil;
  NSString *folder;
  FVWindow *controller = nil;
  NSUInteger i;

  if (file == nil)
    {
      BOOL directory = NO;
      if (![rootFullPath length]
          || ![[NSFileManager defaultManager] fileExistsAtPath:rootFullPath
                                                   isDirectory:&directory]
          || !directory)
        return NO;
      folder = [rootFullPath stringByStandardizingPath];
    }
  else
    {
      if (![[NSFileManager defaultManager] fileExistsAtPath:file])
        return NO;
      folder = [file stringByDeletingLastPathComponent];
    }
  if (!launched)
    {
      /* Asked before the menus exist: answer once launching is done. */
      [self performSelector:@selector (revealLater:)
                 withObject:[NSArray arrayWithObjects:fullPath ? fullPath : @"",
                                                      rootFullPath ? rootFullPath : @"", nil]
                 afterDelay:0];
      return YES;
    }
  for (i = [windows count]; i > 0 && controller == nil; i--)
    if ([[[windows objectAtIndex:i - 1] currentPath] isEqual:folder])
      controller = [windows objectAtIndex:i - 1];
  if (controller == nil && file != nil && ![rootFullPath length])
    controller = [self recentViewer];
  [NSApp activateIgnoringOtherApps:YES];
  if (controller == nil)
    {
      [self openPath:folder];
      controller = [windows lastObject];
    }
  else
    [self bringViewerForward:controller];
  if (file != nil)
    [controller selectFile:file];
  return YES;
}

- (void)revealLater:(NSArray *)request
{
  [self selectFile:[request objectAtIndex:0]
      inFileViewerRootedAtPath:[request objectAtIndex:1]];
}

- (void)openPath:(NSString *)value
{
  FVWindow *controller = [[FVWindow alloc] initWithPath:value];
  [windows addObject:controller];
  FVPlaceClearOfMenu ([controller window]);
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

/* Keep the File Viewers in the order they were last used, most recent
   last, for reopening. */
- (void)viewerBecameKey:(id)controller
{
  NSUInteger index = [windows indexOfObjectIdenticalTo:controller];
  if (index == NSNotFound || index + 1 == [windows count])
    return;
  RETAIN (controller);
  [windows removeObjectAtIndex:index];
  [windows addObject:controller];
  RELEASE (controller);
}

/* The tab shown gets the tab view's whole content area. */
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item
{
  [[item view] setFrame:[tabView contentRect]];
}

- (void)newWindow:(id)sender
{
  [self openPath:NSHomeDirectory ()];
}

- (void)preferences:(id)sender
{
  if (!preferencesPanel)
    {
      preferencesPanel = [[NSPanel alloc]
          initWithContentRect:NSMakeRect (0, 0, 540, 724)
                    styleMask:NSTitledWindowMask | NSClosableWindowMask
                      backing:NSBackingStoreBuffered defer:NO];
      [preferencesPanel setTitle:@"Preferences"];
      [preferencesPanel setReleasedWhenClosed:NO];
      /* General: the file viewer's settings. Desktop: NextBSD's desktop
         settings, whose defaults come from the theme. Dock: the Dock's
         size, behavior and status extras. Background: the desktop
         background's module. */
      NSTabView *tabs = AUTORELEASE ([[NSTabView alloc]
          initWithFrame:NSMakeRect (10, 10, 520, 704)]);
      [tabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
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
      dockSettings = [[FVDockSettings alloc] initWithFrame:page];
      item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"Dock"]);
      [item setLabel:@"Dock"];
      [item setView:[dockSettings view]];
      [tabs addTabViewItem:item];
      backgroundSettings = [[FVBackgroundSettings alloc] initWithFrame:page];
      item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier:@"Background"]);
      [item setLabel:@"Background"];
      [item setView:[backgroundSettings view]];
      [tabs addTabViewItem:item];

      /* One size for every tab, so switching doesn't jump: the tallest
         tab's height. Then the middle of the screen's usable area (clear
         of the Dock), out from under the menu on a small screen. The
         panel keeps where the user moves it after that. */
      CGFloat tallest = 0;
      NSEnumerator *e = [[tabs tabViewItems] objectEnumerator];
      while ((item = [e nextObject]) != nil)
        tallest = MAX (tallest, FVFitPreferencesTab ([item view]));
      [tabs setDelegate:self];
      NSRect content = [[preferencesPanel contentView] frame];
      content.size.height += tallest - NSHeight ([tabs contentRect]);
      NSRect frame = [preferencesPanel frameRectForContentRect:content];
      NSScreen *screen = [preferencesPanel screen] ? [preferencesPanel screen]
                                                   : [NSScreen mainScreen];
      NSRect area = [screen visibleFrame];
      frame.origin.x = floor (NSMidX (area) - NSWidth (frame) / 2);
      frame.origin.y = floor (NSMidY (area) - NSHeight (frame) / 2);
      [preferencesPanel setFrame:frame display:NO];
      [[[tabs selectedTabViewItem] view] setFrame:[tabs contentRect]];
      FVPlaceClearOfMenu (preferencesPanel);
    }
  [thumbnailCheckbox setState:[FVThumbnailOperation enabled] ? NSOnState : NSOffState];
  [self hiddenFilesPreferencesChanged:nil];
  [desktopSettings refresh];
  [dockSettings refresh];
  [backgroundSettings refresh];
  [preferencesPanel makeKeyAndOrderFront:self];
}

/* The desktop's Change Background…: Preferences, at its Background tab. */
- (void)showBackgroundPreferences:(id)sender
{
  [self preferences:sender];
  NSEnumerator *e = [[[preferencesPanel contentView] subviews] objectEnumerator];
  id view;
  while ((view = [e nextObject]) != nil)
    if ([view isKindOfClass:[NSTabView class]])
      [view selectTabViewItemWithIdentifier:@"Background"];
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
  RELEASE (dockSettings);
  RELEASE (backgroundSettings);
  RELEASE (preferencesPanel);
  RELEASE (windows);
  RELEASE (pendingPaths);
  DEALLOC;
}

@end
