#import "../InnerSpaceController.h"
#import "../SaverWindow.h"

@interface StandardResolutionView : NSView
- (BOOL)prefersStandardResolution;
- (void)oneStep;
@end

@implementation StandardResolutionView
- (BOOL)prefersStandardResolution
{
  return YES;
}

- (void)oneStep
{
}
@end

@interface BestResolutionView : NSView
- (void)oneStep;
@end

@implementation BestResolutionView
- (void)oneStep
{
}
@end

static void Check(BOOL condition, NSString *message)
{
  if (!condition)
    {
      NSLog(@"FAIL: %@", message);
      exit(1);
    }
}

/* The saver window of a module answering -prefersStandardResolution YES
   is 1x; others keep the screen's scale. */
int main(void)
{
  CREATE_AUTORELEASE_POOL(pool);
  InnerSpaceController *controller;
  NSView *view;
  CGFloat screenScale;

  [NSApplication sharedApplication];
  screenScale = [[NSScreen mainScreen] backingScaleFactor];
  controller = [[InnerSpaceController alloc] init];

  view = [[StandardResolutionView alloc] initWithFrame: NSMakeRect(0, 0, 320, 200)];
  [controller setValue: view forKey: @"currentModule"];
  [controller createSaverWindow: YES];
  Check([[controller valueForKey: @"saverWindow"] backingScaleFactor] == 1.0,
        @"A module preferring standard resolution gets a 1x window");
  [controller destroySaverWindow];
  RELEASE(view);

  view = [[BestResolutionView alloc] initWithFrame: NSMakeRect(0, 0, 320, 200)];
  [controller setValue: view forKey: @"currentModule"];
  [controller createSaverWindow: YES];
  Check([[controller valueForKey: @"saverWindow"] backingScaleFactor] == screenScale,
        @"Other modules keep the screen's scale");
  [controller destroySaverWindow];
  [controller setValue: nil forKey: @"currentModule"];
  RELEASE(view);

  RELEASE(controller);
  NSLog(@"PASS: standard-resolution modules draw at 1x, others at %g", screenScale);
  RELEASE(pool);
  return 0;
}
