#import "../InnerSpaceController.h"

@interface TestDirectModule : NSObject
{
@public
  BOOL handlesFrame;
  int directCalls, focusCalls, stepCalls, unlockCalls;
  double stepScale;
}

- (NSTimeInterval)animationIntervalForRequestedInterval:(NSTimeInterval)interval;
- (void)setAnimationStepScale:(double)scale;
- (BOOL)renderAnimationFrame;
- (void)lockFocus;
- (void)unlockFocus;
- (void)oneStep;

@end

@implementation TestDirectModule

- (NSTimeInterval)animationIntervalForRequestedInterval:(NSTimeInterval)interval
{
  return handlesFrame ? interval : MAX(0.1, interval);
}

- (void)setAnimationStepScale:(double)scale
{
  stepScale = scale;
}

- (BOOL)renderAnimationFrame
{
  directCalls++;
  return handlesFrame;
}

- (void)lockFocus
{
  focusCalls++;
}

- (void)unlockFocus
{
  unlockCalls++;
}

- (void)oneStep
{
  stepCalls++;
}

@end

/* A module paced by the display: it says when the next frame is due. */
@interface TestPacedModule : TestDirectModule
{
@public
  id frameTarget;
  SEL frameAction;
  int targetCalls;
}

- (BOOL)setAnimationFrameTarget:(id)target action:(SEL)action;

@end

@implementation TestPacedModule

- (BOOL)setAnimationFrameTarget:(id)target action:(SEL)action
{
  targetCalls++;
  frameTarget = target;
  frameAction = action;
  return YES;
}

@end

@interface TestPresentationWindow : NSObject
{
@public
  int flushCalls;
}

- (void)flushWindow;
- (void)close;

@end

@implementation TestPresentationWindow

- (void)flushWindow
{
  flushCalls++;
}

- (void)close
{
}

@end

@interface TestSpeed : NSObject

- (float)floatValue;

@end

@implementation TestSpeed

- (float)floatValue
{
  return 0.05;
}

@end

int main(void)
{
  CREATE_AUTORELEASE_POOL(pool);
  InnerSpaceController *controller = [[InnerSpaceController alloc] init];
  TestDirectModule *module = [[TestDirectModule alloc] init];
  TestPresentationWindow *window = [[TestPresentationWindow alloc] init];

  /* Controller owns these allocated objects and releases them during teardown. */
  [controller setValue: module forKey: @"currentModule"];
  [controller setValue: window forKey: @"saverWindow"];
  module->handlesFrame = YES;
  [controller runAnimation: nil];
  if (module->directCalls != 1 || module->focusCalls != 0 || module->stepCalls != 0 || window->flushCalls != 0)
    return 1;
  module->handlesFrame = NO;
  [controller runAnimation: nil];
  if (module->directCalls != 2 || module->focusCalls != 1 || module->stepCalls != 1
      || module->unlockCalls != 1 || window->flushCalls != 1) return 1;
  {
    TestSpeed *speed = [[TestSpeed alloc] init];
    [controller setValue: speed forKey: @"speedSlider"];
    [controller startTimer];
    if (fabs([[controller valueForKey: @"timer"] timeInterval] - 0.1) > 0.000001
        || fabs(module->stepScale - 2.0) > 0.000001) return 1;
    module->handlesFrame = YES;
    [controller runAnimation: [controller valueForKey: @"timer"]];
    if (fabs([[controller valueForKey: @"timer"] timeInterval] - 0.05) > 0.000001
        || fabs(module->stepScale - 1.0) > 0.000001) return 1;
    [controller stopTimer];
    RELEASE(speed);
  }
  RELEASE(controller);

  /* Display pacing: after a direct frame the module drives the frames,
     the host's timer is only a watchdog, and a CPU fallback puts the
     timer back. */
  {
    TestSpeed *speed = [[TestSpeed alloc] init];
    TestPacedModule *paced = [[TestPacedModule alloc] init];
    TestPresentationWindow *pacedWindow = [[TestPresentationWindow alloc] init];

    controller = [[InnerSpaceController alloc] init];
    [controller setValue: paced forKey: @"currentModule"];
    [controller setValue: pacedWindow forKey: @"saverWindow"];
    [controller setValue: speed forKey: @"speedSlider"];
    paced->handlesFrame = YES;
    [controller startTimer];
    if (paced->frameTarget != nil) return 1;
    [controller runAnimation: [controller valueForKey: @"timer"]];
    if (paced->frameTarget != controller || paced->directCalls != 1
        || fabs([[controller valueForKey: @"timer"] timeInterval] - 1.0) > 0.000001)
      return 1;
    [paced->frameTarget performSelector: paced->frameAction withObject: paced];
    [paced->frameTarget performSelector: paced->frameAction withObject: paced];
    if (paced->directCalls != 3 || paced->targetCalls != 1 || paced->stepCalls != 0)
      return 1;
    paced->handlesFrame = NO;
    [paced->frameTarget performSelector: paced->frameAction withObject: paced];
    if (paced->frameTarget != nil || paced->stepCalls != 1 || pacedWindow->flushCalls != 1
        || fabs([[controller valueForKey: @"timer"] timeInterval] - 0.1) > 0.000001)
      return 1;
    paced->handlesFrame = YES;
    [controller runAnimation: [controller valueForKey: @"timer"]];
    if (paced->frameTarget != controller) return 1;
    [controller stopTimer];
    if (paced->frameTarget != nil || [controller valueForKey: @"timer"] != nil) return 1;
    RELEASE(controller);
    RELEASE(speed);
  }
  NSLog(@"PASS: direct rendering bypasses AppKit; fallback preserves legacy drawing; pacing compensates motion and restores GPU cadence; display pacing replaces the timer and falls back to it");
  RELEASE(pool);
  return 0;
}
