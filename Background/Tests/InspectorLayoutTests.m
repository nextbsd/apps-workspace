#import "../InnerSpaceController.h"

@interface InspectorTestController : InnerSpaceController

- (void)createSaverWindow:(BOOL)desktop;

@end

@implementation InspectorTestController

- (void)createSaverWindow:(BOOL)desktop
{
  /* Exercise the real inspector installation without starting animation. */
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

int main(int argc, char **argv)
{
  CREATE_AUTORELEASE_POOL(pool);
  InspectorTestController *controller;
  NSWindow *window;
  NSBox *box;
  NSScrollView *scroll;
  NSView *scene, *document;
  NSBitmapImageRep *rep;
  NSRect original;
  NSUInteger i;
  Class cls;

  Check(argc == 2, @"Pass module bundle");
  [NSApplication sharedApplication];
  cls = [[NSBundle bundleWithPath: [NSString stringWithUTF8String: argv[1]]] principalClass];
  Check(cls != Nil, @"Module loads");
  scene = [[cls alloc] initWithFrame: NSMakeRect(0, 0, 640, 360)];
  document = [scene performSelector: @selector(inspector:) withObject: nil];
  original = [document frame];
  controller = [[InspectorTestController alloc] init];
  window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 230)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [window setReleasedWhenClosed: NO];
  box = AUTORELEASE([[NSBox alloc] initWithFrame: NSMakeRect(10, 10, 380, 210)]);
  [box setTitle: @"Controls"];
  [[window contentView] addSubview: box];
  [controller setValue: box forKey: @"controlsView"];
  [controller performSelector: @selector(_startModule:) withObject: scene];
  scroll = [box contentView];
  Check([scroll isKindOfClass: [NSScrollView class]], @"Inspector has a scrolling viewport");
  Check(NSEqualSizes([document frame].size, original.size), @"Natural inspector size preserved");
  for (i = 0; i < [[document subviews] count]; i++)
    Check(NSContainsRect([document bounds], [[[document subviews] objectAtIndex: i] frame]),
          @"Every control fits inside the document");
  Check(fabs(NSMaxY([document visibleRect]) - NSMaxY([document bounds])) < 1,
        @"Inspector starts at the top");
  [window orderFront: nil];
  [window display];
  rep = [[window contentView] bitmapImageRepForCachingDisplayInRect: [[window contentView] bounds]];
  [[window contentView] cacheDisplayInRect: [[window contentView] bounds] toBitmapImageRep: rep];
  [[rep representationUsingType: NSPNGFileType properties: [NSDictionary dictionary]]
    writeToFile: @"/tmp/innerspace-controls-top.png" atomically: YES];
  [[scroll contentView] scrollToPoint: NSZeroPoint];
  [scroll reflectScrolledClipView: [scroll contentView]];
  Check(NSMinY([document visibleRect]) == 0, @"Bottom GPU status can be reached");
  [window display];
  rep = [[window contentView] bitmapImageRepForCachingDisplayInRect: [[window contentView] bounds]];
  [[window contentView] cacheDisplayInRect: [[window contentView] bounds] toBitmapImageRep: rep];
  [[rep representationUsingType: NSPNGFileType properties: [NSDictionary dictionary]]
    writeToFile: @"/tmp/innerspace-controls-bottom.png" atomically: YES];
  [window close];
  RELEASE(window);
  RELEASE(controller);
  RELEASE(scene);
  NSLog(@"PASS: inspector bounds, initial top, and scrolling to bottom");
  RELEASE(pool);
  return 0;
}
