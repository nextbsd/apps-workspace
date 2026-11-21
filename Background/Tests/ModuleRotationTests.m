/* Rotate through every module, as clicking quickly down and up the
   Preferences module list does, and fail on any AppKit assertion or
   exception on the way.

   Switching modules closes the saver windows (one per display) and
   releases them. A module that was still in its window when the window
   was deallocated heard -viewWillMoveToWindow: nil from -[NSWindow
   dealloc], after the window's frame view had already left the window;
   Space2View then took its OpenGL view out, and -[NSView
   convertRect:fromView:] raised "Assertion failed in
   GSStandardWindowDecorationView" from the run loop's autorelease pool:
   InnerSpace's critical-error panel, then abort.

   It needs a display server (the session's) and OpenGL for Space2View's
   GPU path. Pass the directory with the built *.InnerSpace bundles
   (InnerSpace.app/Resources by default) and the number of rounds. */

#import "../InnerSpaceController.h"

static int failures = 0;

/* An exception raised while an autorelease pool empties isn't caught on
   the way out (the pool's frames can't be unwound), so AppKit's handler
   would show its critical-error panel and wait: fail instead. */
static void
uncaught(NSException *exception)
{
  NSLog(@"FAIL: uncaught %@", exception);
  exit(1);
}

/* Select a module, then let its timers fire and its windows display for
   a while, as the run loop does between two clicks. */
static void
selectModule(InnerSpaceController *controller, NSString *name,
	     NSTimeInterval dwell)
{
  CREATE_AUTORELEASE_POOL(pool);

  NS_DURING
    {
      [controller loadModule: name];
      [[NSRunLoop currentRunLoop] runUntilDate:
	[NSDate dateWithTimeIntervalSinceNow: dwell]];
    }
  NS_HANDLER
    {
      failures++;
      NSLog(@"FAIL: %@ while selecting %@", localException, name);
    }
  NS_ENDHANDLER
  /* The windows of the module before are released here, as at the end
     of each pass through the application's run loop. */
  NS_DURING
    [pool drain];
  NS_HANDLER
    {
      failures++;
      NSLog(@"FAIL: %@ releasing the windows before %@",
	    localException, name);
    }
  NS_ENDHANDLER
}

int
main(int argc, char **argv)
{
  CREATE_AUTORELEASE_POOL(pool);
  NSString *directory = argc > 1
    ? [NSString stringWithUTF8String: argv[1]] : @"InnerSpace.app/Resources";
  int rounds = argc > 2 ? atoi(argv[2]) : 3;
  /* Clicks a few tens of milliseconds apart, and slow enough that a GPU
     module has started drawing (and its windows have displayed). */
  NSTimeInterval dwells[] = { 0.0, 0.03, 0.4 };
  InnerSpaceController *controller;
  NSSlider *speed;
  NSBox *controls;
  NSView *empty;
  NSArray *names;
  int round, switches = 0;
  NSUInteger i, count;

  [NSApplication sharedApplication];
  NSSetUncaughtExceptionHandler(uncaught);

  controller = [[InnerSpaceController alloc] init];
  speed = AUTORELEASE([[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)]);
  [speed setFloatValue: 0.02];
  controls = AUTORELEASE([[NSBox alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)]);
  empty = AUTORELEASE([[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)]);
  [controller setValue: speed forKey: @"speedSlider"];
  [controller setValue: controls forKey: @"controlsView"];
  [controller setValue: empty forKey: @"emptyView"];
  [controller setValue: [NSUserDefaults standardUserDefaults] forKey: @"defaults"];
  [controller setValue: [NSMutableDictionary dictionary] forKey: @"modules"];
  [controller findModulesInDirectory: directory];
  names = [controller sortedModuleNames];
  count = [names count];
  if (count < 2)
    {
      NSLog(@"FAIL: no modules in %@", directory);
      return 1;
    }
  NSLog(@"%lu modules on %lu displays", (unsigned long)count,
	(unsigned long)[[NSScreen screens] count]);

  for (round = 0; round < rounds; round++)
    {
      NSTimeInterval dwell = dwells[round % 3];

      /* Down the list, then up it, as the arrow keys and clicks go. */
      for (i = 0; i < count; i++, switches++)
	selectModule(controller, [names objectAtIndex: i], dwell);
      for (i = count; i > 0; i--, switches++)
	selectModule(controller, [names objectAtIndex: i - 1], dwell);
      /* And from every module straight to Space2View and back. */
      for (i = 0; i < count; i++, switches += 2)
	{
	  selectModule(controller, [names objectAtIndex: i], 0.4);
	  selectModule(controller, @"Space2View", 0.4);
	}
    }

  {
    CREATE_AUTORELEASE_POOL(inner);
    NS_DURING
      {
	[controller destroySaverWindow];
	RELEASE(controller);
      }
    NS_HANDLER
      {
	failures++;
	NSLog(@"FAIL: %@ at teardown", localException);
      }
    NS_ENDHANDLER
    [inner drain];
  }

  NSLog(@"%d module switches, %d failures", switches, failures);
  [pool drain];
  return failures == 0 ? 0 : 1;
}
