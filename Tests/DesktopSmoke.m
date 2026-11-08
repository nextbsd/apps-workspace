/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import <AppKit/AppKit.h>
#import "FVDesktop.h"
#import "FVDesktopLayout.h"
#import "FVApplication.h"
#import <GNUstepGUI/GSDisplayServer.h>
#import <X11/Xlib.h>
#import <X11/extensions/shape.h>

#define CHECK(x) do { if (!(x)) { NSLog (@"FAIL line %d: %s", __LINE__, #x); exit (1); } } while (0)

@interface FVDesktopOpenRecorder : NSObject
{
  NSString *openedPath;
  NSString *locationPath;
  NSUInteger locationClicks;
}

- (BOOL)openFile:(NSString *)path withApplication:(NSString *)application andDeactivate:(BOOL)flag;
- (void)showDesktopLocationForPath:(NSString *)path;

@end

@implementation FVDesktopOpenRecorder

- (void)showDesktopLocationForPath:(NSString *)path
{
  ASSIGNCOPY (locationPath, path);
  locationClicks++;
}

- (BOOL)openFile:(NSString *)path withApplication:(NSString *)application andDeactivate:(BOOL)flag
{
  ASSIGNCOPY (openedPath, path);
  return YES;
}

- (void)dealloc
{
  RELEASE (openedPath);
  RELEASE (locationPath);
  DEALLOC;
}

@end

@interface FVTestDesktop : FVDesktop
{
  NSArray *fixtureVolumes;
}

- (void)setFixtureVolumes:(NSArray *)paths;

@end

@implementation FVTestDesktop

- (NSArray *)mountedVolumePaths
{
  return fixtureVolumes ? fixtureVolumes : [NSArray array];
}

- (void)setFixtureVolumes:(NSArray *)paths
{
  ASSIGNCOPY (fixtureVolumes, paths);
}

- (void)dealloc
{
  RELEASE (fixtureVolumes);
  DEALLOC;
}

@end

@interface FVDesktopDrop : NSObject
{
  NSPasteboard *pasteboard;
  NSDragOperation mask;
}

- (void)setPaths:(id)paths mask:(NSDragOperation)operation;
- (NSPasteboard *)draggingPasteboard;
- (NSDragOperation)draggingSourceOperationMask;

@end

@implementation FVDesktopDrop

- (id)init
{
  self = [super init];
  if (self)
    pasteboard = RETAIN ([NSPasteboard pasteboardWithUniqueName]);
  return self;
}

- (void)setPaths:(id)paths mask:(NSDragOperation)operation
{
  [pasteboard declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [pasteboard setPropertyList:paths forType:NSFilenamesPboardType];
  mask = operation;
}

- (NSPasteboard *)draggingPasteboard
{
  return pasteboard;
}

- (NSDragOperation)draggingSourceOperationMask
{
  return mask;
}

- (void)dealloc
{
  [pasteboard releaseGlobally];
  RELEASE (pasteboard);
  DEALLOC;
}

@end

static void
Pump (void)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:0.15];
  while ([end timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

int
main (int argc, char **argv)
{
  CREATE_AUTORELEASE_POOL (pool);
  NSString *directory = [[[NSProcessInfo processInfo] environment] objectForKey:@"FV_DESKTOP_FIXTURE"];
  NSString *storePath = [directory stringByAppendingPathComponent:@".DS_Store"];
  NSData *original = [NSData dataWithContentsOfFile:storePath];
  NSDictionary *layout = FVReadDesktopLayout (storePath);
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  FVDesktop *desktop;
  NSDictionary *windows;
  NSWindow *window;
  NSMenu *menu;
  NSEnumerator *enumerator;
  NSUInteger i;
  id oldHidden = RETAIN ([defaults objectForKey:@"Hidden"]);
  id oldPositions = RETAIN ([defaults objectForKey:@"DesktopIconPositions"]);
  CHECK ([layout count] == 3);
  CHECK (NSEqualPoints ([[layout objectForKey:@"résumé.txt"] pointValue], NSMakePoint (360, 120)));
  CHECK (![layout objectForKey:@"deleted.txt"]);
  CHECK (!FVReadDesktopLayout ([directory stringByAppendingPathComponent:@"cycle"]));
  [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:@"cycle"] error:NULL];
  /* Every truncated prefix must fail safely rather than read past its buffer. */
  for (i = 0; i < [original length]; i += 97)
    {
      NSString *truncated = [directory stringByAppendingPathComponent:@"truncated"];
      [[original subdataWithRange:NSMakeRange (0, i)] writeToFile:truncated atomically:YES];
      FVReadDesktopLayout (truncated);
    }
  [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:@"truncated"] error:NULL];
  [NSApplication sharedApplication];
  NSImage *driveIcon = AUTORELEASE ([[NSImage alloc]
      initWithContentsOfFile:@"FileViewer.app/Resources/HardDisk.tiff"]);
  CHECK (driveIcon != nil);
  [driveIcon setName:@"HardDisk"];
  NSImage *rootIcon = [NSImage imageNamed:@"Root_PC"];
  if (!rootIcon)
    rootIcon = [NSImage imageNamed:@"common_Root_PC"];
  CHECK (rootIcon != nil);
  [NSApp finishLaunching];
  [defaults setBool:NO forKey:@"Hidden"];
  [defaults removeObjectForKey:@"DesktopIconPositions"];
  desktop = [[FVTestDesktop alloc] initWithDirectory:directory];
  windows = [desktop valueForKey:@"iconWindows"];
  CHECK ([windows count] == 0);
  [desktop setEnabled:YES];
  Pump ();
  CHECK ([windows count] == 5);
  window = [windows objectForKey:@"alpha.txt"];
  CHECK (window && [window isVisible]);
  CHECK (![window isOpaque] && ![[window contentView] isOpaque]);
  CHECK ([window level] == NSDesktopWindowLevel);
  CHECK ([[window contentView] valueForKey:@"icon"] != nil);
  CHECK (![window canBecomeKeyWindow]);
  /* A refresh must restore icons ordered out by application/window management. */
  [window orderOut:nil];
  CHECK (![window isVisible]);
  [desktop refresh:nil];
  CHECK ([window isVisible]);
  CHECK (![window canHide]);
  CHECK (![window hidesOnDeactivate]);
  CHECK (fabs ([window frame].origin.x - 68) < 1);
  [window display];
  {
    NSImage *rendered = [[window contentView] valueForKey:@"renderedIcon"];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[rendered TIFFRepresentation]];
    CHECK ([[bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
        writeToFile:@"obj/tests/desktop-icon.png" atomically:YES]);
  }
  {
    Display *display = (Display *)[GSServerForWindow (window) serverDevice];
    int count, ordering, j;
    unsigned long pixels = 0;
    XRectangle *rects = XShapeGetRectangles (display, (Window)[window windowRef],
        ShapeBounding, &count, &ordering);
    CHECK (count > 1);
    for (j = 0; j < count; j++)
      pixels += rects[j].width * rects[j].height;
    CHECK (pixels > 0 && pixels < 104 * 96);
    XFree (rects);
  }
  {
    FVDesktopOpenRecorder *recorder = AUTORELEASE ([[FVDesktopOpenRecorder alloc] init]);
    NSEvent *event = [NSEvent mouseEventWithType:NSLeftMouseDown location:NSMakePoint (40, 60)
        modifierFlags:0 timestamp:0 windowNumber:[window windowNumber] context:nil
        eventNumber:1 clickCount:2 pressure:1];
    [NSApp setDelegate:recorder];
    [[window contentView] mouseDown:event];
    CHECK ([recorder valueForKey:@"openedPath"] == nil);
    [[window contentView] mouseUp:event];
    CHECK ([[recorder valueForKey:@"openedPath"] isEqual:
        [directory stringByAppendingPathComponent:@"alpha.txt"]]);
    NSView *folderView = [[windows objectForKey:@"Folder"] contentView];
    NSEvent *click = [NSEvent mouseEventWithType:NSLeftMouseUp location:NSMakePoint (40, 60)
        modifierFlags:0 timestamp:0 windowNumber:[[folderView window] windowNumber] context:nil
        eventNumber:2 clickCount:1 pressure:0];
    [folderView mouseDown:click];
    CHECK ([[recorder valueForKey:@"locationClicks"] unsignedIntegerValue] == 0);
    [folderView mouseUp:click];
    CHECK ([[recorder valueForKey:@"locationClicks"] unsignedIntegerValue] == 0);
    [folderView mouseDown:event];
    [folderView mouseUp:event];
    CHECK ([[recorder valueForKey:@"locationPath"] isEqual:
        [directory stringByAppendingPathComponent:@"Folder"]]);
    CHECK ([[recorder valueForKey:@"locationClicks"] unsignedIntegerValue] == 1);
    [folderView mouseDown:event];
    [folderView setValue:[NSNumber numberWithBool:YES] forKey:@"dragged"];
    [folderView mouseUp:event];
    CHECK ([[recorder valueForKey:@"locationClicks"] unsignedIntegerValue] == 1);
    [recorder setValue:nil forKey:@"openedPath"];
    [[window contentView] mouseDown:click];
    [[window contentView] mouseUp:click];
    CHECK ([recorder valueForKey:@"openedPath"] == nil);
    CHECK ([[recorder valueForKey:@"locationClicks"] unsignedIntegerValue] == 1);
    [NSApp setDelegate:nil];
  }
  {
    FVApplication *application = AUTORELEASE ([[FVApplication alloc] init]);
    FVDesktopDrop *drop = AUTORELEASE ([[FVDesktopDrop alloc] init]);
    id<NSDraggingInfo> info = (id<NSDraggingInfo>)drop;
    NSView *folder = [[windows objectForKey:@"Folder"] contentView];
    NSArray *sources = [NSArray arrayWithObjects:
        [directory stringByAppendingPathComponent:@"alpha.txt"],
        [directory stringByAppendingPathComponent:@"middle.txt"], nil];
    [NSApp setDelegate:application];
    CHECK ([[folder registeredDraggedTypes] containsObject:NSFilenamesPboardType]);
    [drop setPaths:sources mask:NSDragOperationMove];
    CHECK ([folder draggingEntered:info] == NSDragOperationNone);
    [drop setPaths:@"invalid" mask:NSDragOperationCopy];
    CHECK (![folder prepareForDragOperation:info]);
    [drop setPaths:[NSArray arrayWithObject:@"relative.txt"] mask:NSDragOperationCopy];
    CHECK (![folder performDragOperation:info]);
    [drop setPaths:[NSArray arrayWithObject:directory] mask:NSDragOperationCopy];
    CHECK ([folder draggingEntered:info] == NSDragOperationNone);
    [drop setPaths:[NSArray arrayWithObject:[directory stringByAppendingPathComponent:@"Folder"]]
        mask:NSDragOperationCopy];
    CHECK (![folder performDragOperation:info]);
    [drop setPaths:sources mask:NSDragOperationCopy];
    CHECK ([[window contentView] draggingEntered:info] == NSDragOperationNone);
    CHECK ([folder draggingEntered:info] == NSDragOperationCopy);
    CHECK ([[folder valueForKey:@"dropHighlighted"] boolValue]);
    [folder draggingExited:info];
    CHECK (![[folder valueForKey:@"dropHighlighted"] boolValue]);
    CHECK ([folder draggingUpdated:info] == NSDragOperationCopy);
    [[folder window] display];
    NSImage *highlight = [folder valueForKey:@"renderedIcon"];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[highlight TIFFRepresentation]];
    CHECK ([[bitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
        writeToFile:@"obj/tests/desktop-drop.png" atomically:YES]);
    CHECK ([folder prepareForDragOperation:info]);
    CHECK ([folder performDragOperation:info]);
    CHECK (![[folder valueForKey:@"dropHighlighted"] boolValue]);
    NSArray *viewers = [application valueForKey:@"windows"];
    CHECK ([viewers count] == 1);
    id viewer = [viewers objectAtIndex:0];
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:5];
    while ([viewer valueForKey:@"operation"] && [end timeIntervalSinceNow] > 0)
      Pump ();
    CHECK (![viewer valueForKey:@"operation"]);
    NSUInteger sourceIndex;
    for (sourceIndex = 0; sourceIndex < [sources count]; sourceIndex++)
      {
        NSString *source = [sources objectAtIndex:sourceIndex];
        NSString *destination = [[directory stringByAppendingPathComponent:@"Folder"]
            stringByAppendingPathComponent:[source lastPathComponent]];
        CHECK ([[NSData dataWithContentsOfFile:source] isEqual:[NSData dataWithContentsOfFile:destination]]);
      }
    [application showDesktopLocationForPath:directory];
    CHECK ([[application valueForKey:@"windows"] count] == 1);
    CHECK ([[viewer valueForKey:@"path"] isEqual:directory]);
    [application showDesktopLocationForPath:[directory stringByAppendingPathComponent:@"Folder"]];
    CHECK ([[viewer valueForKey:@"path"] isEqual:[directory stringByAppendingPathComponent:@"Folder"]]);
    [application showDesktopLocationForPath:[directory stringByAppendingPathComponent:@"alpha.txt"]];
    CHECK ([[viewer valueForKey:@"path"] isEqual:directory]);
    [[viewer window] close];
    [NSApp setDelegate:nil];
  }
  menu = [desktop arrangementMenu];
  [desktop arrange:[menu itemAtIndex:0]];
  {
    NSPoint before = [window frame].origin;
    [desktop setEnabled:NO];
    CHECK ([windows count] == 0);
    RELEASE (desktop);
    desktop = [[FVTestDesktop alloc] initWithDirectory:directory];
    windows = [desktop valueForKey:@"iconWindows"];
    [desktop setEnabled:YES];
    window = [windows objectForKey:@"alpha.txt"];
    CHECK (NSEqualPoints (before, [window frame].origin));
  }
  menu = [desktop arrangementMenu];
  [desktop arrange:[menu itemAtIndex:1]];
  CHECK ([windows objectForKey:@"Folder"] != nil);
  CHECK (NSEqualPoints ([[windows objectForKey:@"Folder"] frame].origin,
      NSMakePoint (NSMaxX ([[[NSScreen screens] objectAtIndex:0] visibleFrame]) - 104,
                   NSMaxY ([[[NSScreen screens] objectAtIndex:0] visibleFrame]) - 96)));
  [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:
      [NSDate dateWithTimeIntervalSinceNow:3600] forKey:NSFileModificationDate]
      ofItemAtPath:[directory stringByAppendingPathComponent:@"résumé.txt"] error:NULL];
  [desktop arrange:[menu itemAtIndex:2]];
  CHECK ([[windows objectForKey:@"résumé.txt"] frame].origin.y >= [window frame].origin.y);
  [desktop restoreMacLayout:nil];
  CHECK (fabs ([window frame].origin.x - 68) < 1);
  [@"new file" writeToFile:[directory stringByAppendingPathComponent:@"created.txt"]
                atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  [desktop refresh:nil];
  CHECK ([windows objectForKey:@"created.txt"]);
  [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:@"created.txt"] error:NULL];
  [desktop refresh:nil];
  CHECK (![windows objectForKey:@"created.txt"]);
  [defaults setBool:YES forKey:@"Hidden"];
  [[NSNotificationCenter defaultCenter] postNotificationName:@"FVHiddenFilesChanged" object:nil];
  CHECK ([windows objectForKey:@".hidden"]);
  CHECK (![windows objectForKey:@".DS_Store"]);
  [window setFrameOrigin:NSMakePoint (-9999, -9999)];
  [desktop savePositionForPath:[directory stringByAppendingPathComponent:@"alpha.txt"] window:window];
  CHECK (NSContainsRect ([[[NSScreen screens] objectAtIndex:0] visibleFrame], [window frame]));
  enumerator = [windows objectEnumerator];
  while ((window = [enumerator nextObject]))
    CHECK ([window level] == NSDesktopWindowLevel);
  CHECK ([original isEqualToData:[NSData dataWithContentsOfFile:storePath]]);
  [desktop setEnabled:NO];
  {
    NSString *drive = [directory stringByAppendingPathComponent:@"Folder"];
    NSPoint saved;
    id oldRun = RETAIN ([defaults objectForKey:@"ExcludeRunFilesystems"]);
    [defaults setBool:YES forKey:@"ExcludeRunFilesystems"];
    [(FVTestDesktop *)desktop setFixtureVolumes:[NSArray arrayWithObjects:
        drive, drive, @"/", @"/proc", @"/sys/kernel", @"/dev/pts", @"/run/media/USB", nil]];
    [desktop refresh:nil];
    CHECK ([windows count] == 0);
    [desktop setShowMountedDrives:YES];
    CHECK ([windows count] == 2);
    CHECK ([windows objectForKey:drive]);
    FVApplication *dropApplication = AUTORELEASE ([[FVApplication alloc] init]);
    FVDesktopDrop *driveDrop = AUTORELEASE ([[FVDesktopDrop alloc] init]);
    [NSApp setDelegate:dropApplication];
    [driveDrop setPaths:[NSArray arrayWithObject:[directory stringByAppendingPathComponent:@"new.txt"]]
        mask:NSDragOperationCopy];
    CHECK ([[[windows objectForKey:drive] contentView] draggingEntered:(id<NSDraggingInfo>)driveDrop]
        == NSDragOperationCopy);
    [[[windows objectForKey:drive] contentView] draggingExited:(id<NSDraggingInfo>)driveDrop];
    [NSApp setDelegate:nil];
    CHECK ([[[windows objectForKey:drive] contentView] valueForKey:@"icon"] == driveIcon);
    CHECK ([[[windows objectForKey:@"/"] title] isEqual:@"File System"]);
    CHECK ([[[windows objectForKey:@"/"] contentView] valueForKey:@"icon"]
        == rootIcon);
    CHECK ([[[[windows objectForKey:drive] contentView] valueForKey:@"path"] isEqual:drive]);
    NSWindow *rootWindow = [windows objectForKey:@"/"];
    [rootWindow display];
    NSImage *rootRendering = [[rootWindow contentView] valueForKey:@"renderedIcon"];
    NSBitmapImageRep *rootBitmap = [NSBitmapImageRep imageRepWithData:[rootRendering TIFFRepresentation]];
    CHECK ([[rootBitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
        writeToFile:@"obj/tests/desktop-root.png" atomically:YES]);
    [desktop setEnabled:YES];
    CHECK ([windows objectForKey:@"Folder"] && [windows objectForKey:drive]);
    window = [windows objectForKey:drive];
    [window display];
    NSImage *driveRendering = [[window contentView] valueForKey:@"renderedIcon"];
    NSBitmapImageRep *driveBitmap = [NSBitmapImageRep imageRepWithData:[driveRendering TIFFRepresentation]];
    CHECK ([[driveBitmap representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
        writeToFile:@"obj/tests/desktop-drive.png" atomically:YES]);
    [window setFrameOrigin:NSMakePoint (400, 300)];
    [desktop savePositionForPath:drive window:window];
    saved = [window frame].origin;
    CHECK (NSEqualPoints (NSPointFromString ([[desktop valueForKey:@"positions"] objectForKey:drive]), saved));
    [desktop setEnabled:NO];
    CHECK ([windows count] == 2);
    [defaults setBool:NO forKey:@"ExcludeRunFilesystems"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"FVLocationPreferencesChanged" object:nil];
    CHECK ([windows objectForKey:@"/run/media/USB"]);
    [(FVTestDesktop *)desktop setFixtureVolumes:[NSArray arrayWithObject:@"/"]];
    [[[NSWorkspace sharedWorkspace] notificationCenter] postNotificationName:NSWorkspaceDidUnmountNotification object:nil];
    Pump ();
    CHECK ([windows count] == 1 && ![windows objectForKey:drive]);
    [(FVTestDesktop *)desktop setFixtureVolumes:[NSArray arrayWithObjects:@"/", drive, nil]];
    [[[NSWorkspace sharedWorkspace] notificationCenter] postNotificationName:NSWorkspaceDidMountNotification object:nil];
    Pump ();
    CHECK (NSEqualPoints ([[windows objectForKey:drive] frame].origin, saved));
    [desktop arrange:[[desktop arrangementMenu] itemAtIndex:0]];
    CHECK ([windows count] == 2);
    [desktop setShowMountedDrives:NO];
    CHECK ([windows count] == 0);
    CHECK ([desktop valueForKey:@"refreshTimer"] == nil);
    /* Exercise the actual preference action, independently of file icons. */
    id oldDrives = RETAIN ([defaults objectForKey:@"ShowMountedDrives"]);
    [defaults setBool:NO forKey:@"ShowMountedDrives"];
    FVApplication *preferencesApplication = [[FVApplication alloc] init];
    [preferencesApplication setValue:desktop forKey:@"desktop"];
    [preferencesApplication preferences:nil];
    NSButton *drivesCheckbox = [preferencesApplication valueForKey:@"mountedDrivesCheckbox"];
    CHECK ([drivesCheckbox state] == NSOffState);
    [drivesCheckbox performClick:nil];
    Pump ();
    CHECK ([defaults boolForKey:@"ShowMountedDrives"]);
    CHECK ([windows count] == 2);
    CHECK ([[windows objectForKey:drive] isVisible]);
    CHECK ([[windows objectForKey:@"/"] isVisible]);
    CHECK (![windows objectForKey:@"alpha.txt"]);
    [drivesCheckbox performClick:nil];
    CHECK (![defaults boolForKey:@"ShowMountedDrives"]);
    CHECK ([windows count] == 0);
    [[preferencesApplication valueForKey:@"preferencesPanel"] close];
    [preferencesApplication setValue:nil forKey:@"desktop"];
    RELEASE (preferencesApplication);
    if (oldDrives) [defaults setObject:oldDrives forKey:@"ShowMountedDrives"];
    else [defaults removeObjectForKey:@"ShowMountedDrives"];
    RELEASE (oldDrives);
    if (oldRun) [defaults setObject:oldRun forKey:@"ExcludeRunFilesystems"];
    else [defaults removeObjectForKey:@"ExcludeRunFilesystems"];
    RELEASE (oldRun);
  }
  RELEASE (desktop);
  if (oldHidden) [defaults setObject:oldHidden forKey:@"Hidden"];
  else [defaults removeObjectForKey:@"Hidden"];
  if (oldPositions) [defaults setObject:oldPositions forKey:@"DesktopIconPositions"];
  else [defaults removeObjectForKey:@"DesktopIconPositions"];
  RELEASE (oldHidden);
  RELEASE (oldPositions);
  NSLog (@"Desktop layout and GUI smoke passed");
  RELEASE (pool);
  return 0;
}
