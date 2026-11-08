/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import "FVDesktop.h"
#import "FVDesktopLayout.h"
#import "FVApplication.h"
#include <math.h>
#ifdef GNUSTEP
#import <GNUstepGUI/GSDisplayServer.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/extensions/shape.h>
#endif

static const CGFloat FVDesktopWidth = 104;
static const CGFloat FVDesktopHeight = 96;

@interface FVDesktopIconWindow : NSWindow

@end

@implementation FVDesktopIconWindow

- (BOOL)canBecomeKeyWindow
{
  return NO;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}

@end

@interface FVDesktopIconView : NSView
{
  FVDesktop *owner;
  NSString *path;
  NSImage *icon;
  NSImage *renderedIcon;
  NSPoint dragStart, windowStart;
  BOOL dragged;
}

- (id)initWithPath:(NSString *)value owner:(FVDesktop *)controller;

@end

@implementation FVDesktopIconView

- (id)initWithPath:(NSString *)value owner:(FVDesktop *)controller
{
  self = [super initWithFrame:NSMakeRect (0, 0, FVDesktopWidth, FVDesktopHeight)];
  if (self)
    {
      owner = controller;
      ASSIGNCOPY (path, value);
      ASSIGN (icon, [[NSWorkspace sharedWorkspace] iconForFile:path]);
      [self setToolTip:[path lastPathComponent]];
    }
  return self;
}

- (BOOL)isOpaque
{
  return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

- (void)drawIcon
{
  NSMutableParagraphStyle *style;
  NSDictionary *attributes;
  NSShadow *shadow;
  [[NSColor clearColor] set];
  NSRectFillUsingOperation ([self bounds], NSCompositeCopy);
  [icon drawInRect:NSMakeRect (28, 40, 48, 48) fromRect:NSZeroRect
        operation:NSCompositeSourceOver fraction:1.0];
  style = AUTORELEASE ([[NSMutableParagraphStyle alloc] init]);
  [style setAlignment:NSCenterTextAlignment];
  [style setLineBreakMode:NSLineBreakByTruncatingMiddle];
  shadow = AUTORELEASE ([[NSShadow alloc] init]);
  [shadow setShadowColor:[NSColor blackColor]];
  [shadow setShadowOffset:NSMakeSize (0, -1)];
  [shadow setShadowBlurRadius:2];
  attributes = [NSDictionary dictionaryWithObjectsAndKeys:
      [NSFont systemFontOfSize:12], NSFontAttributeName,
      [NSColor whiteColor], NSForegroundColorAttributeName,
      style, NSParagraphStyleAttributeName, shadow, NSShadowAttributeName, nil];
  [[path lastPathComponent] drawInRect:NSMakeRect (2, 4, 100, 32) withAttributes:attributes];
}

- (void)drawRect:(NSRect)dirty
{
  if (!renderedIcon)
    {
      renderedIcon = [[NSImage alloc] initWithSize:[self bounds].size];
      [renderedIcon setBackgroundColor:[NSColor clearColor]];
      [renderedIcon lockFocus];
      [self drawIcon];
      [renderedIcon unlockFocus];
#ifdef GNUSTEP
      /* Match apps-dock: alpha-derived shapes also work without a compositor.
       * Do not send X11 requests to other GNUstep display servers. */
      GSDisplayServer *server = GSServerForWindow ([self window]);
      Class xServer = NSClassFromString (@"XGServer");
      if (xServer && [server isKindOfClass:xServer])
        {
          Display *display = (Display *)[server serverDevice];
          Window native = (Window)[[self window] windowRef];
          int eventBase, errorBase;
          NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[renderedIcon TIFFRepresentation]];
          if (display && native && bitmap && XShapeQueryExtension (display, &eventBase, &errorBase))
            {
              NSUInteger width = [bitmap pixelsWide], height = [bitmap pixelsHigh];
              NSUInteger stride = (width + 7) / 8, x, y;
              NSMutableData *maskData = [NSMutableData dataWithLength:stride * height];
              unsigned char *bits = [maskData mutableBytes];
              Pixmap mask;
              for (y = 0; y < height; y++)
                for (x = 0; x < width; x++)
                  if ([[bitmap colorAtX:x y:y] alphaComponent] > 0)
                    bits[y * stride + x / 8] |= 1 << (x % 8);
              mask = XCreateBitmapFromData (display, native, (const char *)bits, width, height);
              XShapeCombineMask (display, native, ShapeBounding, 0, 0, mask, ShapeSet);
              XFreePixmap (display, mask);
              XFlush (display);
            }
        }
#endif
    }
  NSRectFillUsingOperation (dirty, NSCompositeClear);
  [renderedIcon drawInRect:[self bounds] fromRect:NSZeroRect
                operation:NSCompositeSourceOver fraction:1.0];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
  return [owner arrangementMenu];
}

- (void)mouseDown:(NSEvent *)event
{
  dragged = NO;
  dragStart = [NSEvent mouseLocation];
  windowStart = [[self window] frame].origin;
  if ([event clickCount] == 2)
    {
      id delegate = [NSApp delegate];
      if ([delegate respondsToSelector:@selector (openFile:withApplication:andDeactivate:)])
        [delegate openFile:path withApplication:nil andDeactivate:YES];
      else
        [[NSWorkspace sharedWorkspace] openFile:path];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint now = [NSEvent mouseLocation];
  if (fabs (now.x - dragStart.x) + fabs (now.y - dragStart.y) < 3 && !dragged)
    return;
  dragged = YES;
  [[self window] setFrameOrigin:NSMakePoint (windowStart.x + now.x - dragStart.x,
                                            windowStart.y + now.y - dragStart.y)];
}

- (void)mouseUp:(NSEvent *)event
{
  if (dragged)
    [owner savePositionForPath:path window:[self window]];
  dragged = NO;
}

- (void)dealloc
{
  RELEASE (path);
  RELEASE (icon);
  RELEASE (renderedIcon);
  DEALLOC;
}

@end

static NSPoint
FVDesktopClamp (NSPoint point, NSRect area)
{
  point.x = MAX (NSMinX (area), MIN (point.x, NSMaxX (area) - FVDesktopWidth));
  point.y = MAX (NSMinY (area), MIN (point.y, NSMaxY (area) - FVDesktopHeight));
  return point;
}

static NSInteger
FVDesktopCompare (id left, id right, void *context)
{
  NSDictionary *options = (NSDictionary *)context;
  NSInteger mode = [[options objectForKey:@"mode"] integerValue];
  NSComparisonResult result = NSOrderedSame;
  if (mode == 2)
    result = [[left pathExtension] caseInsensitiveCompare:[right pathExtension]];
  else if (mode == 3)
    {
      NSString *directory = [options objectForKey:@"directory"];
      NSFileManager *manager = [NSFileManager defaultManager];
      NSDate *a = [[manager attributesOfItemAtPath:[directory stringByAppendingPathComponent:left]
          error:NULL] fileModificationDate];
      NSDate *b = [[manager attributesOfItemAtPath:[directory stringByAppendingPathComponent:right]
          error:NULL] fileModificationDate];
      if (a && b)
        result = [b compare:a];
    }
  if (result == NSOrderedSame)
    result = [left localizedCaseInsensitiveCompare:right];
  if (result == NSOrderedSame)
    result = [left compare:right];
  return result;
}

@implementation FVDesktop

- (id)initWithDirectory:(NSString *)path
{
  self = [super init];
  if (self)
    {
      NSDictionary *saved;
      ASSIGNCOPY (directory, path);
      iconWindows = [[NSMutableDictionary alloc] init];
      saved = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"DesktopIconPositions"]
          objectForKey:directory];
      positions = [[NSMutableDictionary alloc] init];
      if ([saved isKindOfClass:[NSDictionary class]])
        [positions addEntriesFromDictionary:saved];
      ASSIGN (macPositions, FVReadDesktopLayout ([directory stringByAppendingPathComponent:@".DS_Store"]));
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector (refresh:)
          name:@"FVHiddenFilesChanged" object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector (refresh:)
          name:NSApplicationDidChangeScreenParametersNotification object:nil];
    }
  return self;
}

- (void)setEnabled:(BOOL)flag
{
  enabled = flag;
  if (flag)
    {
      [self refresh:nil];
      if (!refreshTimer)
        refreshTimer = RETAIN ([NSTimer scheduledTimerWithTimeInterval:2 target:self
            selector:@selector (refresh:) userInfo:nil repeats:YES]);
    }
  else
    {
      NSEnumerator *enumerator = [iconWindows objectEnumerator];
      NSWindow *window;
      if ([iconWindows count])
        [self persistPositions];
      [refreshTimer invalidate];
      DESTROY (refreshTimer);
      while ((window = [enumerator nextObject]))
        [window close];
      [iconWindows removeAllObjects];
    }
}

- (void)persistPositions
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *all = [NSMutableDictionary dictionary];
  NSDictionary *saved = [defaults dictionaryForKey:@"DesktopIconPositions"];
  if (saved)
    [all addEntriesFromDictionary:saved];
  [all setObject:positions forKey:directory];
  [defaults setObject:all forKey:@"DesktopIconPositions"];
}

- (void)savePositionForPath:(NSString *)path window:(NSWindow *)window
{
  NSRect area = [[[NSScreen screens] objectAtIndex:0] visibleFrame];
  NSPoint point;
  if (NSIsEmptyRect (area))
    area = [[[NSScreen screens] objectAtIndex:0] visibleFrame];
  point = FVDesktopClamp ([window frame].origin, area);
  [window setFrameOrigin:point];
  [positions setObject:NSStringFromPoint (point) forKey:[path lastPathComponent]];
  [self persistPositions];
}

- (void)refresh:(id)sender
{
  NSFileManager *manager = [NSFileManager defaultManager];
  NSArray *contents, *oldNames;
  NSMutableArray *names = [NSMutableArray array];
  NSEnumerator *enumerator;
  NSString *name;
  NSRect area;
  NSUInteger i, slot = 0, rows;
  NSMutableArray *occupied = [NSMutableArray array];
  if (!enabled || ![[NSScreen screens] count]
      || ([sender isKindOfClass:[NSTimer class]] && [NSEvent pressedMouseButtons]))
    return;
  area = [[[NSScreen screens] objectAtIndex:0] visibleFrame];
  rows = MAX (1, (NSUInteger)(NSHeight (area) / FVDesktopHeight));
  contents = [manager contentsOfDirectoryAtPath:directory error:NULL];
  enumerator = [contents objectEnumerator];
  while ((name = [enumerator nextObject]))
    if (![name isEqual:@".DS_Store"] && (![name hasPrefix:@"."]
        || [[NSUserDefaults standardUserDefaults] boolForKey:@"Hidden"]))
      [names addObject:name];
  [names sortUsingSelector:@selector (localizedCaseInsensitiveCompare:)];
  oldNames = [iconWindows allKeys];
  for (i = 0; i < [oldNames count]; i++)
    if (![names containsObject:[oldNames objectAtIndex:i]])
      {
        [[iconWindows objectForKey:[oldNames objectAtIndex:i]] close];
        [iconWindows removeObjectForKey:[oldNames objectAtIndex:i]];
      }
  /* Reserve saved positions first, so new files do not cover imported icons. */
  for (i = 0; i < [names count]; i++)
    {
      NSPoint point;
      id saved;
      name = [names objectAtIndex:i];
      saved = [positions objectForKey:name];
      if ([saved isKindOfClass:[NSString class]])
        point = NSPointFromString (saved);
      else if ([macPositions objectForKey:name])
        {
          NSPoint mac = [[macPositions objectForKey:name] pointValue];
          NSRect screen = [[[NSScreen screens] objectAtIndex:0] frame];
          point = NSMakePoint (NSMinX (screen) + mac.x - FVDesktopWidth / 2,
              NSMaxY (screen) - mac.y - 64);
        }
      else
        continue;
      if (!isfinite (point.x) || !isfinite (point.y))
        continue;
      point = FVDesktopClamp (point, area);
      [positions setObject:NSStringFromPoint (point) forKey:name];
      [occupied addObject:[NSValue valueWithRect:NSMakeRect (point.x, point.y,
          FVDesktopWidth, FVDesktopHeight)]];
    }
  for (i = 0; i < [names count]; i++)
    {
      NSWindow *window;
      NSPoint point;
      NSString *saved;
      name = [names objectAtIndex:i];
      window = [iconWindows objectForKey:name];
      saved = [positions objectForKey:name];
      if (![saved isKindOfClass:[NSString class]] || !isfinite (NSPointFromString (saved).x)
          || !isfinite (NSPointFromString (saved).y))
        {
          BOOL intersects;
          NSUInteger attempts = 0;
          do
            {
              NSEnumerator *rects = [occupied objectEnumerator];
              NSValue *rect;
              NSRect candidate;
              point = FVDesktopClamp (NSMakePoint (NSMaxX (area) - FVDesktopWidth * (1 + slot / rows),
                  NSMaxY (area) - FVDesktopHeight * (1 + slot % rows)), area);
              slot++;
              candidate = NSMakeRect (point.x, point.y, FVDesktopWidth, FVDesktopHeight);
              intersects = NO;
              while ((rect = [rects nextObject]))
                if (NSIntersectsRect (candidate, [rect rectValue]))
                  intersects = YES;
              attempts++;
            }
          while (intersects && attempts < rows * MAX (1, (NSUInteger)(NSWidth (area) / FVDesktopWidth)));
          [positions setObject:NSStringFromPoint (point) forKey:name];
          [occupied addObject:[NSValue valueWithRect:NSMakeRect (point.x, point.y,
              FVDesktopWidth, FVDesktopHeight)]];
        }
      else
        point = NSPointFromString (saved);
      if (!window)
        {
          FVDesktopIconView *view;
          window = AUTORELEASE ([[FVDesktopIconWindow alloc]
              initWithContentRect:NSMakeRect (point.x, point.y, FVDesktopWidth, FVDesktopHeight)
              styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO]);
          [window setReleasedWhenClosed:NO];
          [window setLevel:NSDesktopWindowLevel];
          [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces
              | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle];
          [window setOpaque:NO];
          [window setBackgroundColor:[NSColor clearColor]];
          [window setHasShadow:NO];
          [window setExcludedFromWindowsMenu:YES];
          [window setTitle:name];
          view = AUTORELEASE ([[FVDesktopIconView alloc]
              initWithPath:[directory stringByAppendingPathComponent:name] owner:self]);
          [window setContentView:view];
          [iconWindows setObject:window forKey:name];
#ifdef GNUSTEP
          GSDisplayServer *server = GSServerForWindow (window);
          Class xServer = NSClassFromString (@"XGServer");
          if (xServer && [server isKindOfClass:xServer])
            {
              Display *display = (Display *)[server serverDevice];
              Window native = (Window)[window windowRef];
              Atom type = XInternAtom (display, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
              XChangeProperty (display, native, XInternAtom (display, "_NET_WM_WINDOW_TYPE", False),
                  XA_ATOM, 32, PropModeReplace, (unsigned char *)&type, 1);
            }
#endif
          [window orderFront:nil];
        }
      else if (!NSEqualPoints ([window frame].origin, point))
        [window setFrameOrigin:point];
    }
}

- (NSMenu *)arrangementMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle:@"Desktop"]);
  NSArray *titles = [NSArray arrayWithObjects:@"Arrange by Name", @"Arrange by File Type",
      @"Arrange by Date Modified", nil];
  NSUInteger i;
  id<NSMenuItem> item;
  for (i = 0; i < [titles count]; i++)
    {
      item = [menu addItemWithTitle:[titles objectAtIndex:i] action:@selector (arrange:) keyEquivalent:@""];
      [item setTag:i + 1];
      [item setTarget:self];
    }
  [menu addItem:[NSMenuItem separatorItem]];
  item = [menu addItemWithTitle:@"Reload macOS Desktop Layout" action:@selector (restoreMacLayout:) keyEquivalent:@""];
  [item setTarget:self];
  item = [menu addItemWithTitle:@"Refresh Desktop" action:@selector (refresh:) keyEquivalent:@""];
  [item setTarget:self];
  return menu;
}

- (BOOL)validateMenuItem:(id<NSMenuItem>)item
{
  return enabled;
}

- (void)arrange:(id)sender
{
  NSDictionary *options;
  NSArray *names;
  NSRect area;
  NSUInteger i, rows, columns;
  if (!enabled || ![[NSScreen screens] count])
    return;
  [self refresh:nil];
  options = [NSDictionary dictionaryWithObjectsAndKeys:directory, @"directory",
      [NSNumber numberWithInteger:[sender tag]], @"mode", nil];
  names = [[iconWindows allKeys] sortedArrayUsingFunction:FVDesktopCompare context:options];
  area = [[[NSScreen screens] objectAtIndex:0] visibleFrame];
  rows = MAX (1, (NSUInteger)(NSHeight (area) / FVDesktopHeight));
  columns = MAX (1, (NSUInteger)(NSWidth (area) / FVDesktopWidth));
  for (i = 0; i < [names count]; i++)
    {
      NSString *name = [names objectAtIndex:i];
      NSPoint point = FVDesktopClamp (NSMakePoint (
          NSMaxX (area) - FVDesktopWidth * (1 + (i / rows) % columns),
          NSMaxY (area) - FVDesktopHeight * (1 + i % rows)), area);
      [[iconWindows objectForKey:name] setFrameOrigin:point];
      [positions setObject:NSStringFromPoint (point) forKey:name];
    }
  [self persistPositions];
}

- (void)restoreMacLayout:(id)sender
{
  NSDictionary *layout = FVReadDesktopLayout ([directory stringByAppendingPathComponent:@".DS_Store"]);
  if (!layout)
    {
      NSRunAlertPanel (@"Desktop Layout", @"The Desktop .DS_Store file is missing or invalid.", @"OK", nil, nil);
      return;
    }
  ASSIGN (macPositions, layout);
  [positions removeAllObjects];
  [self refresh:nil];
  [self persistPositions];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self setEnabled:NO];
  RELEASE (directory);
  RELEASE (iconWindows);
  RELEASE (positions);
  RELEASE (macPositions);
  DEALLOC;
}

@end
