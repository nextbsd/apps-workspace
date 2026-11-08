/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import <AppKit/AppKit.h>
#import "FVDesktop.h"
#import "FVDesktopLayout.h"
#import <GNUstepGUI/GSDisplayServer.h>
#import <X11/Xlib.h>
#import <X11/extensions/shape.h>

#define CHECK(x) do { if (!(x)) { NSLog (@"FAIL line %d: %s", __LINE__, #x); exit (1); } } while (0)

@interface FVDesktopOpenRecorder : NSObject
{
  NSString *openedPath;
}

- (BOOL)openFile:(NSString *)path withApplication:(NSString *)application andDeactivate:(BOOL)flag;

@end

@implementation FVDesktopOpenRecorder

- (BOOL)openFile:(NSString *)path withApplication:(NSString *)application andDeactivate:(BOOL)flag
{
  ASSIGNCOPY (openedPath, path);
  return YES;
}

- (void)dealloc
{
  RELEASE (openedPath);
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
  [NSApp finishLaunching];
  [defaults setBool:NO forKey:@"Hidden"];
  [defaults removeObjectForKey:@"DesktopIconPositions"];
  desktop = [[FVDesktop alloc] initWithDirectory:directory];
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
    CHECK ([[recorder valueForKey:@"openedPath"] isEqual:
        [directory stringByAppendingPathComponent:@"alpha.txt"]]);
    [NSApp setDelegate:nil];
  }
  menu = [desktop arrangementMenu];
  [desktop arrange:[menu itemAtIndex:0]];
  {
    NSPoint before = [window frame].origin;
    [desktop setEnabled:NO];
    CHECK ([windows count] == 0);
    RELEASE (desktop);
    desktop = [[FVDesktop alloc] initWithDirectory:directory];
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
