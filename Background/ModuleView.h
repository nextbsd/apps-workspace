#include <AppKit/AppKit.h>

@interface ModuleView : NSView
{
}
// animation methods...
- (void) oneStep;
/* Optional: YES means the module presented directly, without AppKit focus. */
- (BOOL) renderAnimationFrame;
- (NSTimeInterval) animationDelayTime;
/* Optional pacing with motion compensation for reduced drawing frequency. */
- (NSTimeInterval)animationIntervalForRequestedInterval:(NSTimeInterval)interval;
- (void)setAnimationStepScale:(double)scale;
/* Optional, for modules that present directly: YES means the module
   will send action to target (with itself as the argument) whenever the
   display is ready for its next frame (e.g. when the frame it presented
   is on screen), and the host draws a frame each time instead of on its
   timer. NO, or a later -renderAnimationFrame answering NO, keeps or
   puts back the timer. A nil target stops the messages. */
- (BOOL)setAnimationFrameTarget:(id)target action:(SEL)action;
- (void) didLockFocus;
/* Optional, instead of -oneStep: the module steps and draws itself,
   locking focus on and flushing only the parts that change
   (-lockFocusInRect:, -unlockFocus, -[NSWindow flushWindow] for each),
   so a few moving sprites don't cost a whole screen per frame. */
- (void) stepWithOwnFocus;
/* Optional: YES draws the module at 1x on a HiDPI screen and leaves the
   scaling to the window server, for a module that redraws the whole
   screen on the CPU every frame and needn't be sharp. */
- (BOOL) prefersStandardResolution;

// inspector methods...
- (NSView *) inspector: (id)sender;
- (void) inspectorInstalled;
- (void) inspectorWillBeRemoved;

// window methods...
- (BOOL) useBufferedWindow;
- (BOOL) isBoringScreenSaver;
- (BOOL) ignoreMouseMovement;
- (NSString *) windowTitle;

// notification methods..
- (void) willEnterScreenSaverMode;
- (void) enteredScreenSaverMode;
- (void) willExitScreenSaverMode;
@end
