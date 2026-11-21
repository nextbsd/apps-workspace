#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "InnerSpaceController.h"

#if defined(_WIN32) || defined(WIN32)

#include <windows.h>

#else

#include <errno.h>
#include <sys/resource.h>
#include <string.h>

#endif

#define APP_NAME @"WorkspaceBackground"

static void
InnerSpaceSetLowPriority(void)
{
#if defined(_WIN32) || defined(WIN32)
  SetPriorityClass(GetCurrentProcess(), IDLE_PRIORITY_CLASS);
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_IDLE);
#else
  if (setpriority(PRIO_PROCESS, 0, 19) != 0 && errno != EACCES)
    {
      NSLog(@"Unable to lower InnerSpace priority: %s", strerror(errno));
    }
#endif
}

/*
 * Initialise and go! Workspace starts the background: no app icon, and a
 * menu only for the options window.
 */

int main(int argc, const char *argv[])
{
  CREATE_AUTORELEASE_POOL(pool);
  InnerSpaceController *controller;
  NSMenu *menu;

  InnerSpaceSetLowPriority();
  [[NSUserDefaults standardUserDefaults] registerDefaults:
    [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: YES]
				forKey: @"GSSuppressAppIcon"]];
  [NSApplication sharedApplication];
  menu = AUTORELEASE([[NSMenu alloc] initWithTitle: @"Background"]);
  [menu addItemWithTitle: @"Close"
		  action: @selector(performClose:)
	   keyEquivalent: @"w"];
  [NSApp setMainMenu: menu];
  controller = [[InnerSpaceController alloc] init];
  [NSApp setDelegate: controller];
  [NSApp run];
  RELEASE(controller);
  RELEASE(pool);
  return 0;
}
