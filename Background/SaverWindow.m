/* All Rights reserved */

#include <AppKit/AppKit.h>
#include "SaverWindow.h"
#if !defined(__APPLE__)
#include <GNUstepGUI/GSDisplayServer.h>
#include <X11/Xlib.h>
#endif

@implementation SaverWindow
- (id) initWithContentRect: (NSRect)contentRect
		 styleMask: (NSUInteger)style
		   backing: (NSBackingStoreType)store
		     defer: (BOOL)flag
	standardResolution: (BOOL)standard
{
  /* Set before NSWindow's initializer: the backend asks for the scale
     while it makes the window's backing store. */
  standardResolution = standard;
  return [self initWithContentRect: contentRect
			 styleMask: style
			   backing: store
			     defer: flag];
}

/* At 1x a module drawing the whole screen on the CPU has a quarter of
   the pixels to draw, and the window server scales the window up (the
   NextBSD backend gives a window the scale its -backingScaleFactor
   answers). */
- (CGFloat) backingScaleFactor
{
  return standardResolution ? 1.0 : [super backingScaleFactor];
}

- (void) setAction: (SEL)a forTarget: (id)t
{
  action = a;
  target = t;
}

- (void) _triggerAction
{
  if([self level] != NSDesktopWindowLevel)
    {
      [NSApp sendAction: action to: target from: self];
    }
}

- (void) keyDown: (NSEvent *)theEvent
{
  [self _triggerAction];
}

- (void) mouseMoved: (NSEvent *)theEvent
{
  [self _triggerAction];
}

- (void) mouseUp: (NSEvent *)theEvent
{
  [self _triggerAction];
}

/* Clicking the desktop makes the workspace app (GSWorkspaceApplication,
   Workspace on NextBSD) the active app, as clicking the desktop brings
   the Finder forward on macOS: the desktop is the workspace's, even
   though InnerSpace draws it. */
- (void) mouseDown: (NSEvent *)theEvent
{
  NSString *name;

  if ([self level] != NSDesktopWindowLevel)
    {
      return;
    }
  name = [[NSUserDefaults standardUserDefaults]
	   stringForKey: @"GSWorkspaceApplication"];
  if ([name length] == 0
      || [name isEqualToString: [[NSProcessInfo processInfo] processName]])
    {
      return;
    }
  NS_DURING
    {
      NSConnection *connection;
      id app;

      connection = [NSConnection connectionWithRegisteredName: name host: @""];
      [connection setRequestTimeout: 2.0];
      [connection setReplyTimeout: 2.0];
      app = [connection rootProxy];
      [app activateIgnoringOtherApps: YES];
    }
  NS_HANDLER
    {
    }
  NS_ENDHANDLER
}

/* Under X, desktop level is only a hint to a window manager, so without one
   this window has to send itself behind the others whenever it is ordered.
   Other backends (the NextBSD WindowServer) keep desktop-level windows at
   the bottom themselves, and their serverDevice isn't an X Display. */
- (void) orderWindow: (NSWindowOrderingMode)place relativeTo: (NSInteger)number
{
  [super orderWindow: place relativeTo: number];
#if !defined(__APPLE__)
  if ([self level] == NSDesktopWindowLevel && place != NSWindowOut
      && [GSServerForWindow(self) isKindOfClass: NSClassFromString(@"XGServer")])
    {
      Display *display = (Display *)[GSServerForWindow(self) serverDevice];
      XLowerWindow(display, (Window)[self windowRef]);
      XFlush(display);
    }
#endif
}

- (BOOL) canBecomeKeyWindow
{
  return YES;
}

/* Never the main window: it only shows the saver, and in the in-window
   menu style (NBMenuStyle inwindow) GNUstep puts the main menu in every
   window that can become main, which put a menu bar along the top of
   the desktop, behind the other apps' windows and under a top Dock.
   Being key is enough for the keys and clicks that stop the saver. */
- (BOOL) canBecomeMainWindow
{
  return NO;
}

- (void) hide: (id)sender
{
  // Don't react to hide.  This window cannot be hidden.
}

@end
