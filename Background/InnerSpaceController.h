/* All Rights reserved */

#include <AppKit/AppKit.h>
#include <unistd.h>
#include "SaverWindow.h"
#include "ModuleView.h"
#include "WorkspaceBackground.h"

@interface InnerSpaceController : NSObject
{
  // interface vars.
  id window;
  id moduleList;
  id inBackground;
  id locker;
  id saver;
  id run;
  id controlsView;
  id emptyView;
  id lockerPanel;
  id speedSlider;

  // internal vars.
  SaverWindow *saverWindow;	// on the main display
  // the other displays' windows, each with its own instance of the
  // module as its content view (or none: black)
  NSMutableArray *otherWindows;
  NSTimer *timer;
  NSTimeInterval requestedAnimationInterval;
  // frames paced by the display (-setAnimationFrameTarget:action:)
  BOOL displayPaced;
  NSTimeInterval lastDirectFrame;
  ModuleView *currentModule;
  NSMutableDictionary *modules;
  NSUserDefaults *defaults;
  NSString *currentModuleName;

  // booleans...
  BOOL isSaver;
  BOOL isLocker;
  BOOL isInBackground;

  // Workspace's desktop background.
  BOOL moduleOnEveryDisplay;
  pid_t parentProcess;
}
// Workspace's desktop background: build the options window, show the
// saved module on the desktop, and follow Workspace's settings.
- (void) start;
- (void) createInterface;
- (void) adoptInnerSpaceDefaults;
- (void) settingsDidChange: (NSNotification *)notification;
- (void) showOptions: (NSNotification *)notification;

// methods called from interface
- (void) selectSaver: (id)sender;
- (void) inBackground: (id)sender;
- (void) locker: (id)sender;
- (void) saver: (id)sender;
- (void) doSaver: (id)sender;
- (void) doSaverInBackground: (id)sender;
- (void) startSaver; // : (id)sender;
- (void) stopSaver; // : (id)sender;
- (void) stopAndStartSaver; // : (id)sender;

// internal methods
- (NSMutableDictionary *) modules;
- (NSArray *) sortedModuleNames;
- (void) destroySaverWindow;
- (void) screenParametersDidChange: (NSNotification *)notification;
- (void) createSaverWindow: (BOOL)desktop;
- (void) createOtherWindows;
- (void) destroyOtherWindows;
- (void) startTimer;
- (void) stopTimer;
- (void) resetTimer;
- (void) runAnimation: (NSTimer *)atimer;
- (void) displayFrameDue: (id)sender;
- (void) loadModule: (NSString *)moduleName;
- (void) loadDefaults;
- (void) findModulesInDirectory: (NSString *) directory;
- (void) findModules;
@end
