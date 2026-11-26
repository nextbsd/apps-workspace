/* All Rights reserved */

#include <AppKit/AppKit.h>
#include <Foundation/NSString.h>
#include <Foundation/NSUserDefaults.h>
#include "InnerSpaceController.h"
#include <math.h>

#define TIME 0.10
#define MINIMUM_ANIMATION_DELAY 0.01

/* The main display's screen: the first of +[NSScreen screens] (the one
   with the menu bar). +mainScreen is the key window's, which may be on
   another display. */
static NSScreen *
mainDisplay(void)
{
  NSArray *screens = [NSScreen screens];

  return [screens count] > 0 ? [screens objectAtIndex: 0]
    : [NSScreen mainScreen];
}

/* Draw one frame of a module in its window, as -runAnimation: does. */
static void
stepModule(ModuleView *module, NSWindow *window)
{
  if ([module respondsToSelector: @selector(renderAnimationFrame)]
      && [module renderAnimationFrame])
    {
      /* It presents its own drawable; one whose last frame isn't on
	 its display yet skips this one. */
    }
  else if ([module respondsToSelector: @selector(stepWithOwnFocus)])
    {
      [module stepWithOwnFocus];
    }
  else
    {
      [module lockFocus];
      if ([module respondsToSelector: @selector(didLockFocus)])
	[module didLockFocus];
      [module oneStep];
      [module unlockFocus];
      [window flushWindow];
    }
}

/* Close a saver window and take its module out of it while the window is
   whole. A window released with its module still in it tells the module
   it is leaving (-viewWillMoveToWindow: nil) from -[NSWindow dealloc],
   at the end of a pass through the run loop, after the window's own
   frame view has already left the window: a module that changes its
   views then (Space2View takes its OpenGL view out) has AppKit convert
   between two windows and raise, and InnerSpace stops with a critical
   error. Switching modules quickly releases windows that way all the
   time. Taken out here, the module hears it while the window is whole,
   and it is released (an other display's) or moved to the next window
   (the main display's) as any view is. */
static void
closeSaverWindow(NSWindow *window)
{
  [window close];
  NS_DURING
    [window setContentView: nil];
  NS_HANDLER
    NSLog(@"EXCEPTION while taking a module out of its window: %@",
	  localException);
  NS_ENDHANDLER
}

@implementation InnerSpaceController

// interface callbacks
- (void) selectSaver: (id)sender
{
  id module = nil;
  int row = [moduleList selectedRowInColumn: [moduleList selectedColumn]];

  if(row >= 0)
    {
      module = [[self sortedModuleNames] objectAtIndex: row];
      [defaults setObject: module forKey: @"currentModule"];
      [defaults synchronize];
      ASSIGN(currentModuleName, module);
      [self loadModule: module];
    }

  NSDebugLog(@"Called");
  /* insert your code here */
}

- (void) inBackground: (id)sender
{
  isInBackground = ([inBackground state] == NSOnState);
}

- (void) locker: (id)sender
{
  isLocker = ([locker state] == NSOnState);
}

- (void) saver: (id)sender
{
  isSaver = ([saver state] == NSOnState);
}

- (void) doSaver: (id)sender
{
  [self startSaver];
}

- (void) doSaverInBackground: (id)sender
{
  NSDebugLog(@"Called");
  [self createSaverWindow: YES];
  [self startTimer];
}

- (void) resetTimer
{
  [self stopTimer];
  [self startTimer];
}

- (void) setSpeed: (id)sender
{
  float runSpeed = [sender floatValue];

  if(runSpeed < MINIMUM_ANIMATION_DELAY)
    {
      runSpeed = MINIMUM_ANIMATION_DELAY;
      [sender setFloatValue: runSpeed];
    }

  [defaults setFloat: runSpeed forKey: @"runSpeed"];
  [defaults synchronize];
  [self resetTimer];
}

- (void) loadDefaults
{
  /* The desktop starts in Solid Color: NeXT slate in Dark, Gershwin's
     grey in Light (nextbsd/libs-innerspace#20). */
  NSDictionary *appDefs = [NSDictionary dictionaryWithObjectsAndKeys:
				      @"SolidColor", @"currentModule",
				      [NSNumber numberWithFloat: TIME], @"runSpeed",
				      nil];
  int row = 0;
  float runSpeed = TIME;

  defaults = [NSUserDefaults standardUserDefaults];
  [defaults registerDefaults: appDefs];
  [self adoptInnerSpaceDefaults];

  runSpeed = [defaults floatForKey: @"runSpeed"];
  if(runSpeed < MINIMUM_ANIMATION_DELAY)
    {
      runSpeed = MINIMUM_ANIMATION_DELAY;
      [defaults setFloat: runSpeed forKey: @"runSpeed"];
      [defaults synchronize];
    }
  [speedSlider setFloatValue: runSpeed];

  ASSIGN(currentModuleName, [defaults stringForKey: @"currentModule"]);
  row = [[self sortedModuleNames] indexOfObject: currentModuleName];  
  if(row < [[self sortedModuleNames] count])
    {
      [moduleList reloadColumn: 0];
      [moduleList selectRow: row inColumn: 0];
    }

  NSDebugLog(@"current module = %@",currentModuleName);
}

- (NSMutableDictionary *) modules
{
  return modules;
}

- (NSArray *) sortedModuleNames
{
  return [[modules allKeys] sortedArrayUsingSelector: @selector(compare:)];
}

- (void) findModulesInDirectory: (NSString *) directory
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *files = [fm directoryContentsAtPath: directory];
  NSEnumerator *en = [files objectEnumerator];
  id item = nil;

  NSDebugLog(@"directory = %@",directory);
  while((item = [en nextObject]) != nil)
    {
      NSDebugLog(@"file = %@",item);
      if([[item pathExtension] isEqualToString: @"InnerSpace"])
	{
	  NSString *fullPath = [directory stringByAppendingPathComponent: item];
	  NSMutableDictionary *infoDict = [NSMutableDictionary dictionary];
	  
	  [infoDict setObject: fullPath forKey: @"Path"];

	  [modules setObject: infoDict forKey: [item stringByDeletingPathExtension]];
	  NSDebugLog(@"modules = %@",modules);
	}
    }
}

/* apps-innerspace installs the modules in a Library's InnerSpace folder;
   the user's come first, so one there replaces the system's. */
- (void) findModules
{
  NSEnumerator *e = [WorkspaceBackgroundModuleDirectories()
		      reverseObjectEnumerator];
  NSString *directory;

  while ((directory = [e nextObject]) != nil)
    {
      [self findModulesInDirectory: directory];
    }
}

- (void) awakeFromNib
{
  modules = RETAIN([NSMutableDictionary dictionary]);
  [self findModules];
  [self loadDefaults];
  [self loadModule: currentModuleName];
  RETAIN(emptyView); // hold on to this.

  /* The desktop window has to follow the screen when its size changes. */
  [[NSNotificationCenter defaultCenter]
    addObserver: self
       selector: @selector(screenParametersDidChange:)
           name: NSApplicationDidChangeScreenParametersNotification
         object: nil];

  /* Workspace Preferences' Background tab. */
  [[NSDistributedNotificationCenter defaultCenter]
    addObserver: self
       selector: @selector(settingsDidChange:)
           name: WorkspaceBackgroundSettingsDidChangeNotification
         object: nil];
  [[NSDistributedNotificationCenter defaultCenter]
    addObserver: self
       selector: @selector(showOptions:)
           name: WorkspaceBackgroundShowOptionsNotification
         object: nil];
}

/* InnerSpace.app's choices carry over the first time. */
- (void) adoptInnerSpaceDefaults
{
  NSDictionary *old;
  NSEnumerator *e;
  NSString *key;

  if ([[defaults persistentDomainForName: WorkspaceBackgroundDomain] count] > 0)
    {
      return;
    }
  old = [defaults persistentDomainForName: @"InnerSpace"];
  e = [[NSArray arrayWithObjects: @"currentModule", @"runSpeed",
		@"moduleOnEveryDisplay", nil] objectEnumerator];
  while ((key = [e nextObject]) != nil)
    {
      if ([old objectForKey: key] != nil)
	{
	  [defaults setObject: [old objectForKey: key] forKey: key];
	}
    }
  [defaults synchronize];
}

/* The window the module's inspector shows in, with no menu of its own
   to show: Workspace's Background tab has the rest of the settings. */
- (void) createInterface
{
  NSRect frame = NSMakeRect(0, 0, 420, 300);
  NSTextField *none;

  window = [[NSPanel alloc] initWithContentRect: frame
				      styleMask: NSTitledWindowMask
						 | NSClosableWindowMask
					backing: NSBackingStoreBuffered
					  defer: YES];
  [window setReleasedWhenClosed: NO];
  [window setTitle: @"Background Options"];
  controlsView = [[NSBox alloc] initWithFrame: NSInsetRect(frame, 10, 10)];
  [controlsView setTitlePosition: NSNoTitle];
  [controlsView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [[window contentView] addSubview: controlsView];
  none = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 380, 24)];
  [none setStringValue: @"This background has no options."];
  [none setEditable: NO];
  [none setSelectable: NO];
  [none setBordered: NO];
  [none setBezeled: NO];
  [none setDrawsBackground: NO];
  emptyView = none;
  [controlsView setContentView: emptyView];
  /* Not on screen: it only holds the speed for the timer. */
  speedSlider = [[NSSlider alloc] initWithFrame: NSZeroRect];
  [speedSlider setMinValue: MINIMUM_ANIMATION_DELAY];
  [speedSlider setMaxValue: 1.0];
}

/* The settings come with the notification: another process's change to
   this domain isn't read back while it runs. */
- (void) settingsDidChange: (NSNotification *)notification
{
  NSDictionary *settings = [notification userInfo];
  NSEnumerator *e = [settings keyEnumerator];
  NSString *key;
  NSString *module;
  BOOL everywhere;

  while ((key = [e nextObject]) != nil)
    {
      [defaults setObject: [settings objectForKey: key] forKey: key];
    }
  [defaults synchronize];
  [speedSlider setFloatValue: MAX([defaults floatForKey: @"runSpeed"],
				  MINIMUM_ANIMATION_DELAY)];
  module = [defaults stringForKey: @"currentModule"];
  everywhere = [defaults objectForKey: @"moduleOnEveryDisplay"] == nil
    || [defaults boolForKey: @"moduleOnEveryDisplay"];
  if (![module isEqual: currentModuleName])
    {
      ASSIGN(currentModuleName, module);
      [self loadModule: module];
    }
  else if (everywhere != moduleOnEveryDisplay)
    {
      [self createSaverWindow: YES];
    }
  else
    {
      [self resetTimer];
    }
  moduleOnEveryDisplay = everywhere;
}

- (void) showOptions: (NSNotification *)notification
{
  [window setTitle: [NSString stringWithFormat: @"%@ Options",
			      currentModuleName]];
  [window center];
  [NSApp unhideWithoutActivation];
  [NSApp activateIgnoringOtherApps: YES];
  [window makeKeyAndOrderFront: self];
}

/* Workspace starts the background and keeps it running; without
   Workspace there is no one to stop it, so it stops itself. */
- (void) watchWorkspace: (NSTimer *)atimer
{
  if (getppid() != parentProcess)
    {
      [NSApp terminate: self];
    }
}

- (void) start
{
  parentProcess = getppid();
  [self createInterface];
  [self awakeFromNib];
  moduleOnEveryDisplay = [defaults objectForKey: @"moduleOnEveryDisplay"] == nil
    || [defaults boolForKey: @"moduleOnEveryDisplay"];
  [NSTimer scheduledTimerWithTimeInterval: 2.0
				   target: self
				 selector: @selector(watchWorkspace:)
				 userInfo: nil
				  repeats: YES];
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [self destroySaverWindow];
  [self stopTimer];
  RELEASE(currentModule);
  RELEASE(modules);
  RELEASE(currentModuleName);
  RELEASE(emptyView);
  [super dealloc];
}

/* A hidden app isn't activated when it finishes launching: the desktop
   is Workspace's, so the background mustn't take the menu bar from it.
   Its windows can't hide (-setCanHide: NO), so the desktop still shows. */
- (void) applicationWillFinishLaunching: (NSNotification *)notification
{
  [NSApp hide: self];
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  // The saver is *always* running...
  [self start];
}

- (void) createSaverWindow: (BOOL)desktop
{
  NSRect frame = [mainDisplay() frame];
  int store = NSBackingStoreRetained;
  BOOL standard = NO;
  
  [self destroySaverWindow];

  // dertermine backing type...
  NS_DURING
  if([currentModule respondsToSelector: @selector(useBufferedWindow)])
    {
      if([currentModule useBufferedWindow])
	{
	  store = NSBackingStoreBuffered;
	}
    }
  NS_HANDLER
    NSLog(@"EXCEPTION: %@",localException);
    store = NSBackingStoreBuffered;
  NS_ENDHANDLER
  NS_DURING
    if([currentModule respondsToSelector: @selector(prefersStandardResolution)])
      {
	standard = [currentModule prefersStandardResolution];
      }
  NS_HANDLER
    NSLog(@"EXCEPTION: %@",localException);
  NS_ENDHANDLER

  // create the window...
  saverWindow = [[SaverWindow alloc] initWithContentRect: frame
				     styleMask: NSBorderlessWindowMask
				     backing: store
				     defer: NO
			     standardResolution: standard];
  [saverWindow setReleasedWhenClosed: NO];

  // set some attributes...
  [saverWindow setAction: @selector(stopAndStartSaver) forTarget: self];
  [saverWindow setAutodisplay: YES];
  [saverWindow makeFirstResponder: saverWindow];
  [saverWindow setExcludedFromWindowsMenu: YES];
  [saverWindow setBackgroundColor: [NSColor blackColor]];
  [saverWindow setOneShot:YES];

  // set up the backing store...
  if(store == NSBackingStoreBuffered)
    {
      [saverWindow useOptimizedDrawing: YES];
      [saverWindow setDynamicDepthLimit: YES];
    }

  // run the saver in on the desktop...
  if(desktop)
    {
      [saverWindow setLevel: NSDesktopWindowLevel];
      [saverWindow setCanHide: NO];
      /* The desktop is Workspace's: its clear windows above take the
	 clicks (FVDesktop), as the Finder's do over the wallpaper. */
      [saverWindow setIgnoresMouseEvents: YES];
    } 
  else
    {
      [saverWindow setLevel: NSScreenSaverWindowLevel];
      [saverWindow setCanHide: YES];
    }

  // load the view from the currently active module, if
  // there is one...
  if(currentModule)
    {
      [saverWindow setContentView: currentModule];
      NS_DURING
	if([currentModule respondsToSelector: @selector(willEnterScreenSaverMode)])
	  {
	    [currentModule willEnterScreenSaverMode];
	  }
      NS_HANDLER
	NSLog(@"EXCEPTION while creating saver window %@",localException);
      NS_ENDHANDLER
    }
  
  [self createOtherWindows];
  [self startTimer];
  if (desktop)
    {
      /* Desktop level is only a hint to a window manager, so without one
         the window has to send itself behind every other window. */
      [saverWindow orderBack: self];
    }
  else
    {
      [saverWindow makeKeyAndOrderFront: self];
    }
}

/*
 * The other displays (NextBSD's several displays, E40): a window of the
 * saver window's kind on each, at its level, with an instance of the
 * current module of its own, so modules with state (Kaleidoscope, Tomorrow
 * Never Knows, Flying Toasters) run one each, and GL modules get a
 * context each. They step with the main display's module (-runAnimation:);
 * a GL module whose last frame isn't on its own display yet skips the
 * step, so none queues frames for a slower display. With the
 * moduleOnEveryDisplay default NO, the others are plain black, which
 * saves the GPU the work on large external displays.
 */
- (void) createOtherWindows
{
  NSArray *screens = [NSScreen screens];
  BOOL everywhere = YES;
  NSUInteger i;

  [self destroyOtherWindows];
  if (saverWindow == nil || [screens count] < 2)
    {
      return;
    }
  if ([defaults objectForKey: @"moduleOnEveryDisplay"] != nil)
    {
      everywhere = [defaults boolForKey: @"moduleOnEveryDisplay"];
    }
  otherWindows = [[NSMutableArray alloc] init];
  for (i = 1; i < [screens count]; i++)
    {
      NSRect frame = [[screens objectAtIndex: i] frame];
      SaverWindow *other;
      ModuleView *module = nil;

      other = [[SaverWindow alloc] initWithContentRect: frame
					      styleMask: NSBorderlessWindowMask
						backing: [saverWindow backingType]
						  defer: NO];
      [other setReleasedWhenClosed: NO];
      [other setAction: @selector(stopAndStartSaver) forTarget: self];
      [other setAutodisplay: YES];
      [other setExcludedFromWindowsMenu: YES];
      [other setBackgroundColor: [NSColor blackColor]];
      [other setOneShot: YES];
      [other setLevel: [saverWindow level]];
      [other setCanHide: [saverWindow canHide]];
      [other setIgnoresMouseEvents: [saverWindow ignoresMouseEvents]];
      if (everywhere && currentModule != nil)
	{
	  NS_DURING
	    module = [[[currentModule class] alloc]
		       initWithFrame: [[other contentView] bounds]];
	    [other setContentView: module];
	    if ([module respondsToSelector: @selector(willEnterScreenSaverMode)])
	      {
		[module willEnterScreenSaverMode];
	      }
	  NS_HANDLER
	    NSLog(@"EXCEPTION while creating a saver window for display %@: %@",
		  NSStringFromRect(frame), localException);
	  NS_ENDHANDLER
	  RELEASE(module);
	}
      [otherWindows addObject: other];
      RELEASE(other);
      if ([saverWindow level] == NSDesktopWindowLevel)
	{
	  [other orderBack: self];
	}
      else
	{
	  [other orderFront: self];
	}
    }
}

- (void) destroyOtherWindows
{
  NSEnumerator *e = [otherWindows objectEnumerator];
  NSWindow *other;

  while ((other = [e nextObject]) != nil)
    {
      id module = [other contentView];

      if ([module respondsToSelector: @selector(setAnimationFrameTarget:action:)])
	{
	  NS_DURING
	    [module setAnimationFrameTarget: nil action: NULL];
	  NS_HANDLER
	  NS_ENDHANDLER
	}
      closeSaverWindow(other);
    }
  DESTROY(otherWindows);
}

/* Step the other displays' modules with the main one. */
- (void) stepOtherWindows
{
  NSEnumerator *e = [otherWindows objectEnumerator];
  NSWindow *other;

  while ((other = [e nextObject]) != nil)
    {
      ModuleView *module = [other contentView];

      if (currentModule == nil || ![module isKindOfClass: [currentModule class]])
	{
	  continue;	/* black */
	}
      NS_DURING
	stepModule(module, other);
      NS_HANDLER
	NSLog(@"EXCEPTION while in running animation: %@", localException);
      NS_ENDHANDLER
    }
}

/* The other displays' windows match the screens after the main one. */
- (BOOL) otherWindowsMatchScreens
{
  NSArray *screens = [NSScreen screens];
  NSUInteger i, count = [screens count] > 0 ? [screens count] - 1 : 0;

  if ([otherWindows count] != count)
    {
      return NO;
    }
  for (i = 0; i < count; i++)
    {
      if (!NSEqualRects([[otherWindows objectAtIndex: i] frame],
			[[screens objectAtIndex: i + 1] frame]))
	{
	  return NO;
	}
    }
  return YES;
}

- (void) screenParametersDidChange: (NSNotification *)notification
{
  /* Use the full frame, not visibleFrame: the Dock draws over the desktop. */
  NSRect frame = [mainDisplay() frame];

  if(saverWindow == nil)
    {
      return;
    }

  /* Displays came, went or moved: a window for each again. */
  if(![self otherWindowsMatchScreens])
    {
      [self createOtherWindows];
      /* A boring module draws once, when it starts: these start now. */
      if([currentModule respondsToSelector: @selector(isBoringScreenSaver)])
	{
	  [self stepOtherWindows];
	}
    }

  if(NSEqualRects([saverWindow frame], frame))
    {
      return;
    }

  [saverWindow setFrame: frame display: NO];
  if(currentModule != nil)
    {
      [currentModule setFrame: [[saverWindow contentView] bounds]];
      [currentModule setNeedsDisplay: YES];
    }
  [saverWindow display];
  [saverWindow flushWindow];
}

- (void) destroySaverWindow
{
  [self stopTimer];
  [self destroyOtherWindows];
  if(saverWindow != nil)
    {
      closeSaverWindow(saverWindow);
      RELEASE(saverWindow);
      saverWindow = nil;
    }
}

- (void) startSaver
{
  [self destroySaverWindow];
  [self createSaverWindow: NO];
  [saverWindow setLevel: NSScreenSaverWindowLevel];
}

- (void) stopSaver
{
  [self destroySaverWindow];
}

- (void) stopAndStartSaver
{
  [self stopSaver];
  [self doSaverInBackground: self];
  [saverWindow setLevel: NSDesktopWindowLevel];
}

// timer managment
- (void) startTimer
{
  NSTimeInterval runSpeed = [speedSlider floatValue];
  NSTimeInterval time = runSpeed;

  [self stopTimer];

  if(currentModule == nil || saverWindow == nil)
    {
      return;
    }

  NS_DURING
    {
      // Some modules may FORCE us to run at a given speed.
      if([currentModule respondsToSelector: @selector(animationDelayTime)])
	{
	  time = [currentModule animationDelayTime];
	}
    }
  NS_HANDLER
    {
      NSLog(@"EXCEPTION: %@", localException);
      time = runSpeed;
    }
  NS_ENDHANDLER

  if(time < MINIMUM_ANIMATION_DELAY)
    {
      time = MINIMUM_ANIMATION_DELAY;
    }
    
  requestedAnimationInterval = time;
  if ([currentModule respondsToSelector: @selector(animationIntervalForRequestedInterval:)]
      && [currentModule respondsToSelector: @selector(setAnimationStepScale:)])
    {
      time = MAX(time, [currentModule animationIntervalForRequestedInterval: time]);
      [currentModule setAnimationStepScale: time / requestedAnimationInterval];
    }

  if(![currentModule respondsToSelector: @selector(isBoringScreenSaver)])
    {
      timer = [NSTimer scheduledTimerWithTimeInterval: time
		       target: self
		       selector: @selector(runAnimation:)
		       userInfo: nil
		       repeats: YES];
    }
  else
    {
      // if the screen saver is "boring" it should only run oneStep
      // once.   This means that it will not waste CPU cycles spinning and
      // doing nothing...
      NS_DURING
        if ([currentModule respondsToSelector: @selector(renderAnimationFrame)]
            && [currentModule renderAnimationFrame])
          {
            /* Direct renderers present their own drawable. */
          }
        else
          {
            [currentModule lockFocus];
            if ([currentModule respondsToSelector: @selector(didLockFocus)])
              [currentModule didLockFocus];
            [currentModule oneStep];
            /* Unlock first: GNUstep marks the drawn area for flushing here.
               Flushing before unlocking queues a second presentation. */
            [currentModule unlockFocus];
            [saverWindow flushWindow];
          }
        [self stepOtherWindows];
      NS_HANDLER
	NSLog(@"EXCEPTION: %@",localException);
      NS_ENDHANDLER      
    }
  if(timer != nil)
    {
      RETAIN(timer);
    }
}

- (void) stopDisplayPacing
{
  if(!displayPaced)
    {
      return;
    }
  displayPaced = NO;
  NS_DURING
    [currentModule setAnimationFrameTarget: nil action: NULL];
  NS_HANDLER
    NSLog(@"EXCEPTION: %@", localException);
  NS_ENDHANDLER
}

- (void) stopTimer
{
  [self stopDisplayPacing];
  if(timer != nil)
    {
      [timer invalidate];
      RELEASE(timer);
      timer = nil;
    }
}

/* A module that presents directly can be paced by the display instead
   of the timer: it says when the display is ready for its next frame
   (on WindowServer's frame-done, after the last one is on screen), so
   it draws at most a frame per refresh, and nothing while its frames
   aren't being shown. */
- (void) startDisplayPacing
{
  BOOL paced = NO;

  if(displayPaced || ![currentModule respondsToSelector:
			 @selector(setAnimationFrameTarget:action:)])
    {
      return;
    }
  NS_DURING
    paced = [currentModule setAnimationFrameTarget: self
					    action: @selector(displayFrameDue:)];
  NS_HANDLER
    NSLog(@"EXCEPTION: %@", localException);
  NS_ENDHANDLER
  if(!paced)
    {
      return;
    }
  displayPaced = YES;
  if(timer != nil)
    {
      [timer invalidate];
      RELEASE(timer);
    }
  /* Only a watchdog now, in case a frame never comes back. */
  timer = RETAIN([NSTimer scheduledTimerWithTimeInterval: 1.0
		  target: self
		  selector: @selector(displayWatchdog:)
		  userInfo: nil
		  repeats: YES]);
}

- (void) displayFrameDue: (id)sender
{
  if(displayPaced && saverWindow != nil)
    {
      [self runAnimation: nil];
    }
}

- (void) displayWatchdog: (NSTimer *)atimer
{
  if(displayPaced
     && [NSDate timeIntervalSinceReferenceDate] - lastDirectFrame > 1.0)
    {
      [self runAnimation: nil];
    }
}

- (void) runAnimation: (NSTimer *)atimer
{
  if(!saverWindow)
    {
      return;
    }
  else
    {
      NS_DURING
        if ([currentModule respondsToSelector: @selector(renderAnimationFrame)]
            && [currentModule renderAnimationFrame])
          {
            /* Direct renderers present their own drawable, and may be
               paced by the display from now on. */
            lastDirectFrame = [NSDate timeIntervalSinceReferenceDate];
            [self startDisplayPacing];
            if (displayPaced)
              atimer = nil;	/* no cadence to keep; the timer is gone */
          }
        else
          {
            if (displayPaced)
              {
                /* Back on the CPU: back on the timer. */
                [self startTimer];
                atimer = nil;
              }
            if ([currentModule respondsToSelector: @selector(stepWithOwnFocus)])
              {
                /* It draws and flushes only what changed: a whole-view
                   lockFocus would flush the whole screen every frame. */
                [currentModule stepWithOwnFocus];
              }
            else
              {
                [currentModule lockFocus];
                if ([currentModule respondsToSelector: @selector(didLockFocus)])
                  [currentModule didLockFocus];
                [currentModule oneStep];
                /* Unlock first: GNUstep marks the drawn area for flushing
                   here. Flushing before unlocking queues a second
                   presentation. */
                [currentModule unlockFocus];
                [saverWindow flushWindow];
              }
          }
        [self stepOtherWindows];
        /* GPU activation/fallback can change the preferred cadence. Recreate
           the timer only when that cadence actually changes. */
        if (atimer != nil && requestedAnimationInterval > 0
            && [currentModule respondsToSelector: @selector(animationIntervalForRequestedInterval:)]
            && [currentModule respondsToSelector: @selector(setAnimationStepScale:)])
          {
            NSTimeInterval desired = MAX(requestedAnimationInterval,
              [currentModule animationIntervalForRequestedInterval: requestedAnimationInterval]);
            if (fabs(desired - [atimer timeInterval]) > 0.000001) [self startTimer];
          }
      NS_HANDLER
	NSLog(@"EXCEPTION while in running animation: %@",localException);
      NS_ENDHANDLER
    }
}

- (void) _startModule: (ModuleView *)moduleView
{
  NSView *inspectorView = nil;
  NS_DURING
    if([moduleView respondsToSelector: @selector(inspector:)])
      {
	inspectorView = [moduleView inspector: self];
	RETAIN(inspectorView);
	// NSLog(@"inspectorView %@",inspectorView);
	[(NSBox *)controlsView setBorderType: NSGrooveBorder];
        /* NSBox resizes its content view, which clipped taller inspectors.
           Keep the document's natural size inside a scrolling viewport. */
        {
          NSScrollView *scroll = AUTORELEASE([[NSScrollView alloc]
            initWithFrame: [[(NSBox *)controlsView contentView] frame]]);
          NSSize naturalSize = [inspectorView frame].size;
          NSSize visibleSize;

          [scroll setBorderType: NSNoBorder];
          [scroll setHasVerticalScroller: YES];
          [scroll setHasHorizontalScroller: YES];
          [scroll setAutohidesScrollers: YES];
          [scroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
          [scroll setDocumentView: inspectorView];
          [(NSBox *)controlsView setContentView: scroll];
          visibleSize = [[scroll contentView] bounds].size;
          [inspectorView setFrameSize: naturalSize];
          [[scroll contentView] scrollToPoint: NSMakePoint(0,
            MAX(0, naturalSize.height - visibleSize.height))];
          [scroll reflectScrolledClipView: [scroll contentView]];
        }
	RELEASE(inspectorView);
	if([moduleView respondsToSelector: @selector(inspectorInstalled)])
	  {
	    NSLog(@"installed");
	    [moduleView inspectorInstalled];
	  }
      }
    if(moduleView != nil)
      {
	[self createSaverWindow: YES];
      }
  NS_HANDLER
    NSLog(@"EXCEPTION: %@",localException);
  NS_ENDHANDLER
}

- (void) _stopModule: (ModuleView *)moduleView
{
  NS_DURING
    if([moduleView respondsToSelector: @selector(inspectorWillBeRemoved)])
      {
	[moduleView inspectorWillBeRemoved];
      }
    [self stopSaver];
  NS_HANDLER
    NSLog(@"EXCEPTION while in _stopModule: %@",localException);
  NS_ENDHANDLER
 
  // Remove the view...
  [(NSBox *)controlsView setContentView: emptyView];
  [(NSBox *)controlsView setBorderType: NSGrooveBorder];
}

- (NSString *) _pathForModule: (NSString *) moduleName
{
  NSString *result = nil;
  NSMutableDictionary *dict;

  if((dict = [modules objectForKey: moduleName]) != nil)
    {
      result = [dict objectForKey: @"Path"];
    }
  return result;
}

- (void) loadModule: (NSString *)moduleName
{
  id newModule = nil;

  if(moduleName)
    {
      NSBundle *bundle = nil;
      Class    theViewClass;
      NSString *bundlePath = [self _pathForModule: moduleName];
      
      NSDebugLog(@"Bundle path = %@",bundlePath);
      bundle = [NSBundle bundleWithPath: bundlePath];
      if(bundle != nil)
	{
	  NSDebugLog(@"Bundle loaded");
	  theViewClass = [bundle principalClass];
	  if(theViewClass != nil)
	    {
	      newModule = [[theViewClass alloc] initWithFrame: [mainDisplay() frame]];
	    }
	}
    }
  
  if(newModule != currentModule)
    {
      if(currentModule)
	{
	  [self _stopModule: currentModule];
	}
      
      ASSIGN(currentModule, (ModuleView *)newModule);
      RELEASE(newModule);
      [self _startModule: currentModule];
      [controlsView display];
    }
}
@end

// delegate
@interface InnerSpaceController(BrowserDelegate)
- (BOOL) browser: (NSBrowser*)sender selectRow: (int)row inColumn: (int)column;

- (void) browser: (NSBrowser *)sender createRowsForColumn: (int)column
	inMatrix: (NSMatrix *)matrix;

- (NSString*) browser: (NSBrowser*)sender titleOfColumn: (int)column;

- (void) browser: (NSBrowser *)sender 
 willDisplayCell: (id)cell 
	   atRow: (int)row 
	  column: (int)column;

- (BOOL) browser: (NSBrowser *)sender isColumnValid: (int)column;
@end

@implementation InnerSpaceController(BrowserDelegate)
- (BOOL) browser: (NSBrowser*)sender selectRow: (int)row inColumn: (int)column
{
  return YES;
}

- (void) browser: (NSBrowser *)sender createRowsForColumn: (int)column
	inMatrix: (NSMatrix *)matrix
{
  NSEnumerator     *e = [[self sortedModuleNames] objectEnumerator];
  NSString    *module = nil;
  NSBrowserCell *cell = nil;
  int i = 0;

  while((module = [e nextObject]) != nil)
    {
      [matrix insertRow: i withCells: nil];
      cell = [matrix cellAtRow: i column: 0];
      [cell setLeaf: YES];
      i++;
      [cell setStringValue: module];
    }
}

- (NSString*) browser: (NSBrowser*)sender titleOfColumn: (int)column
{
  NSLog(@"Delegate called....");
  return @"Modules";
}

- (void) browser: (NSBrowser *)sender 
 willDisplayCell: (id)cell 
	   atRow: (int)row 
	  column: (int)column
{
}

- (BOOL) browser: (NSBrowser *)sender isColumnValid: (int)column
{
  return NO;
}
@end
