#import "../InnerSpaceController.h"

@interface FrameTestWindow : NSWindow
{
@public
  int flushCalls;
}

@end

@implementation FrameTestWindow

- (void)flushWindow
{
  flushCalls++;
  [super flushWindow];
}

@end

@interface FrameTestView : NSView

- (void)oneStep;

@end

@implementation FrameTestView

- (void)oneStep
{
  [[NSColor redColor] set];
  NSRectFill([self bounds]);
}

@end

@interface StaticFrameTestView : FrameTestView

- (BOOL)isBoringScreenSaver;

@end

@implementation StaticFrameTestView

- (BOOL)isBoringScreenSaver
{
  return YES;
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

int main(void)
{
  CREATE_AUTORELEASE_POOL(pool);
  FrameTestWindow *window;
  InnerSpaceController *controller;
  int i;

  [NSApplication sharedApplication];
  window = [[FrameTestWindow alloc] initWithContentRect: NSMakeRect(0, 0, 320, 200)
    styleMask: NSBorderlessWindowMask backing: NSBackingStoreRetained defer: NO];
  [window setReleasedWhenClosed: NO];
  controller = [[InnerSpaceController alloc] init];
  [controller setValue: window forKey: @"saverWindow"];
  for (i = 0; i < 2; i++)
    {
      FrameTestView *view = [[(i == 0 ? [FrameTestView class] : [StaticFrameTestView class]) alloc]
        initWithFrame: NSMakeRect(0, 0, 320, 200)];
      [window setContentView: view];
      [window orderFront: nil];
      [window display];
      [window flushWindowIfNeeded];
      [controller setValue: view forKey: @"currentModule"];
      window->flushCalls = 0;
      if (i == 0) [controller runAnimation: nil];
      else [controller startTimer];
      Check(window->flushCalls == 1, @"Frame is presented immediately");
      [window flushWindowIfNeeded];
      Check(window->flushCalls == 1, @"Unlocking focus does not queue a duplicate presentation");
      [controller stopTimer];
      [controller setValue: nil forKey: @"currentModule"];
      RELEASE(view);
    }
  [controller setValue: nil forKey: @"saverWindow"];
  RELEASE(controller);
  [window close];
  RELEASE(window);
  NSLog(@"PASS: animated and static frames each flush once, with no pending duplicate");
  RELEASE(pool);
  return 0;
}
