/* All Rights reserved */

#include <AppKit/AppKit.h>

@interface SaverWindow : NSWindow
{
  id  target;
  SEL action;
  BOOL standardResolution;
}
/* standard: draw at 1x on a HiDPI screen (see -backingScaleFactor). */
- (id) initWithContentRect: (NSRect)contentRect
		 styleMask: (NSUInteger)style
		   backing: (NSBackingStoreType)store
		     defer: (BOOL)flag
	standardResolution: (BOOL)standard;
- (void) setAction: (SEL)action forTarget: (id) target;
@end
