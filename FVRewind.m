/*
 * This file is part of Workspace.
 * Copyright (C) 2026 FileViewer contributors
 *
 * Workspace is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3,
 * as published by the Free Software Foundation.
 *
 * Workspace is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Workspace. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import "FVRewind.h"
#import "FVWindow.h"
#import "FVModel.h"
#import "FVPanels.h"
#import "FVDesktopSettings.h"

#include <math.h>

/* The schedule's choices: the values the rewind job reads, and titles. */
static NSArray *
FVFreqValues (void)
{
  return [NSArray arrayWithObjects:@"15m", @"hourly", @"daily", @"weekly", nil];
}

static NSArray *
FVFreqTitles (void)
{
  return [NSArray arrayWithObjects:@"Every 15 minutes", @"Every hour", @"Every day",
                                   @"Every week", nil];
}

static NSArray *
FVKeepValues (void)
{
  return [NSArray arrayWithObjects:@"7", @"14", @"30", @"90", nil];
}

static NSArray *
FVKeepTitles (void)
{
  return [NSArray arrayWithObjects:@"1 week", @"2 weeks", @"1 month", @"3 months", nil];
}

static NSTextField *
FVRewindLabel (NSRect frame, NSString *text)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame:frame]);
  [label setStringValue:text];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  return label;
}

/* When a snapshot named rewind-YYYYMMDD-HHMMSS was taken, or nil. */
static NSCalendarDate *
FVSnapshotStamp (NSString *name)
{
  if (![name hasPrefix:@"rewind-"] || [name length] != 22)
    return nil;
  return [NSCalendarDate dateWithString:[name substringFromIndex:7]
                         calendarFormat:@"%Y%m%d-%H%M%S"];
}

static NSCalendarDate *
FVCalendarDate (NSDate *date)
{
  return [NSCalendarDate dateWithTimeIntervalSinceReferenceDate:
                             [date timeIntervalSinceReferenceDate]];
}

/* A time on the timeline and the frames: "Today 04:13",
   "Yesterday 18:00", "Tue 24 Nov 20:00" in the last week, else
   "17 Nov 09:00" (with the year when it isn't this one). */
static NSString *
FVShortDate (NSDate *value)
{
  NSCalendarDate *date = FVCalendarDate (value);
  NSCalendarDate *now = [NSCalendarDate calendarDate];
  NSInteger days = [now dayOfCommonEra] - [date dayOfCommonEra];
  NSString *time = [date descriptionWithCalendarFormat:@"%H:%M"];
  if (days == 0)
    return [@"Today " stringByAppendingString:time];
  if (days == 1)
    return [@"Yesterday " stringByAppendingString:time];
  if (days > 1 && days < 7)
    return [NSString stringWithFormat:@"%@ %ld %@ %@",
                                      [date descriptionWithCalendarFormat:@"%a"],
                                      (long)[date dayOfMonth],
                                      [date descriptionWithCalendarFormat:@"%b"], time];
  if ([date yearOfCommonEra] != [now yearOfCommonEra])
    return [NSString stringWithFormat:@"%ld %@ %ld %@", (long)[date dayOfMonth],
                                      [date descriptionWithCalendarFormat:@"%b"],
                                      (long)[date yearOfCommonEra], time];
  return [NSString stringWithFormat:@"%ld %@ %@", (long)[date dayOfMonth],
                                    [date descriptionWithCalendarFormat:@"%b"], time];
}

/* "Tuesday 24 November" then joiner and the time: ", 20:00" for the
   window title, " at 20:00" in sentences. */
static NSString *
FVLongDate (NSDate *value, NSString *joiner)
{
  NSCalendarDate *date = FVCalendarDate (value);
  NSCalendarDate *now = [NSCalendarDate calendarDate];
  NSString *day = [NSString stringWithFormat:@"%@ %ld %@",
                                             [date descriptionWithCalendarFormat:@"%A"],
                                             (long)[date dayOfMonth],
                                             [date descriptionWithCalendarFormat:@"%B"]];
  if ([date yearOfCommonEra] != [now yearOfCommonEra])
    day = [day stringByAppendingFormat:@" %ld", (long)[date yearOfCommonEra]];
  return [NSString stringWithFormat:@"%@%@%@", day, joiner,
                                    [date descriptionWithCalendarFormat:@"%H:%M"]];
}

/* When something changed, in a sentence: "today at 14:02",
   "yesterday at 9:40", "on Tuesday 24 November at 20:00". */
static NSString *
FVChangedPhrase (NSDate *value)
{
  NSCalendarDate *date = FVCalendarDate (value);
  NSInteger days = [[NSCalendarDate calendarDate] dayOfCommonEra] - [date dayOfCommonEra];
  NSString *time = [date descriptionWithCalendarFormat:@"%H:%M"];
  if (days == 0)
    return [@"today at " stringByAppendingString:time];
  if (days == 1)
    return [@"yesterday at " stringByAppendingString:time];
  return [@"on " stringByAppendingString:FVLongDate (value, @" at ")];
}

/* "rewind-20261126-041335" as "Today 04:13"; any other snapshot by its
   own name. */
static NSString *
FVSnapshotTitle (NSString *name)
{
  NSCalendarDate *date = FVSnapshotStamp (name);
  return date ? FVShortDate (date) : name;
}

static NSString *
FVItemCount (NSUInteger count)
{
  return [NSString stringWithFormat:count == 1 ? @"%lu item" : @"%lu items",
                                    (unsigned long)count];
}

/* ---- Rewind's look ---- */

/* Rewind draws its own scene, in Dark or Light as NBAppearance says, like
   the rest of Workspace. */
static BOOL
FVRewindDark (void)
{
  return ![[FVDesktopSettings effectiveValueForKey:@"NBAppearance"] isEqual:@"light"];
}

static NSColor *
FVHex (unsigned rgb, CGFloat alpha)
{
  return [NSColor colorWithCalibratedRed:((rgb >> 16) & 0xff) / 255.0
                                   green:((rgb >> 8) & 0xff) / 255.0
                                    blue:(rgb & 0xff) / 255.0
                                   alpha:alpha];
}

typedef enum
{
  FVRewindSkyTop, FVRewindSkyMiddle, FVRewindSkyBottom, FVRewindGhost, FVRewindGhostBar,
  FVRewindLine, FVRewindText, FVRewindDim, FVRewindFaint, FVRewindAccent,
  FVRewindAccentText, FVRewindRemoved, FVRewindChanged, FVRewindPill, FVRewindPanel,
  FVRewindColorCount
} FVRewindColorName;

static NSColor *
FVRewindColor (FVRewindColorName name)
{
  /* The mockup's colours (nextbsd/nextbsd#724), Dark then Light. */
  static const unsigned dark[FVRewindColorCount] = {
    0x2c3a4c, 0x141a23, 0x0a0d12, 0x262a31, 0x2e323a, 0xffffff, 0xe9ebef, 0x9aa0ac,
    0x6b7180, 0x00d4ff, 0x04141a, 0xff8a65, 0xffcc4d, 0xffffff, 0x14171d };
  static const unsigned light[FVRewindColorCount] = {
    0xdfe6ee, 0xaeb8c4, 0x8993a0, 0xeceef2, 0xdfe1e6, 0x000000, 0x1d1f24, 0x5f6470,
    0x8d929c, 0x00a3c7, 0xffffff, 0xd9531e, 0xb07d00, 0x000000, 0xf5f6f8 };
  BOOL isDark = FVRewindDark ();
  CGFloat alpha = 1;
  if (name == FVRewindLine)
    alpha = isDark ? .08 : .10;
  else if (name == FVRewindPill)
    alpha = isDark ? .06 : .05;
  else if (name == FVRewindPanel)
    alpha = isDark ? .82 : .86;
  return FVHex ((isDark ? dark : light)[name], alpha);
}

static NSDictionary *
FVRewindAttributes (CGFloat size, BOOL bold, NSColor *color)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
      bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size],
      NSFontAttributeName, color, NSForegroundColorAttributeName, nil];
}

/* Text centred in a rect, cut short with an ellipsis if it doesn't fit. */
static void
FVDrawCentered (NSString *text, NSRect rect, NSDictionary *attributes)
{
  NSSize size = [text sizeWithAttributes:attributes];
  while (size.width > NSWidth (rect) && [text length] > 2)
    {
      text = [[text substringToIndex:[text length] - 2] stringByAppendingString:@"…"];
      size = [text sizeWithAttributes:attributes];
    }
  [text drawAtPoint:NSMakePoint (NSMidX (rect) - size.width / 2,
                                 NSMidY (rect) - size.height / 2)
     withAttributes:attributes];
}

/* A marker in the list: "Removed since" or "Changed since", outlined in
   its colour. */
@implementation FVRewindChangeCell

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
  NSString *change = [self stringValue];
  BOOL removed = [change isEqual:@"removed"];
  if (!removed && ![change isEqual:@"changed"])
    return;
  NSColor *color = FVRewindColor (removed ? FVRewindRemoved : FVRewindChanged);
  NSString *text = removed ? @"Removed since" : @"Changed since";
  NSDictionary *attributes = FVRewindAttributes (10, YES, color);
  NSSize size = [text sizeWithAttributes:attributes];
  NSRect pill = NSMakeRect (NSMinX (frame) + 2, floor (NSMidY (frame) - 8),
                            ceil (size.width) + 14, 16);
  NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect (pill, .5, .5)
                                                          xRadius:7.5
                                                          yRadius:7.5];
  [FVRewindColor (FVRewindPill) set];
  [outline fill];
  [color set];
  [outline setLineWidth:1];
  [outline stroke];
  FVDrawCentered (text, pill, attributes);
}

@end

/* Show only changes: a small switch and its label, in the viewer's
   toolbar while rewinding. */
@implementation FVRewindSwitch

/* A cell to hold the target and action. */
+ (Class)cellClass
{
  return [NSActionCell class];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

- (BOOL)isOn
{
  return on;
}

- (void)setOn:(BOOL)flag
{
  on = flag;
  [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
  [self setOn:!on];
  [self sendAction:[self action] to:[self target]];
}

- (void)drawRect:(NSRect)rect
{
  NSRect track = NSMakeRect (2, floor (NSMidY ([self bounds]) - 8.5), 30, 17);
  NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:track xRadius:8.5 yRadius:8.5];
  [(on ? FVRewindColor (FVRewindAccent)
       : [[NSColor secondaryLabelColor] colorWithAlphaComponent:.35]) set];
  [pill fill];
  [[NSColor whiteColor] set];
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect (on ? NSMaxX (track) - 15 : NSMinX (track) + 2,
                                                      NSMinY (track) + 2, 13, 13)] fill];
  NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
      [NSFont systemFontOfSize:12], NSFontAttributeName,
      [NSColor controlTextColor], NSForegroundColorAttributeName, nil];
  NSString *title = @"Show only changes";
  NSSize size = [title sizeWithAttributes:attributes];
  [title drawAtPoint:NSMakePoint (NSMaxX (track) + 7, NSMidY ([self bounds]) - size.height / 2)
      withAttributes:attributes];
}

@end

/* The rest of the screen while rewinding: the backdrop, the older
   snapshots as frames behind the viewer, the timeline and the bar with
   Cancel and Restore. Only the viewer in front is live; the frames are
   drawn, so many snapshots cost no more than a few. */
@interface FVRewind (Stage)
- (NSArray *)versions;
- (NSInteger)currentVersion;
- (NSString *)folderTitle;
- (NSUInteger)selectedCount;
- (void)jumpToVersion:(NSInteger)index;
- (void)leaveRewind:(id)sender;
- (void)restore:(id)sender;
@end

@interface FVRewindStage : NSView
{
  FVRewind *owner;
  NSRect timelineRect, cancelRect, restoreRect;
  NSGradient *sky;
  BOOL skyDark;
}
- (id)initWithFrame:(NSRect)frame owner:(FVRewind *)rewind;
/* Where the viewer stands, in the stage's (flipped) coordinates. */
- (NSRect)frontRect;
@end

@interface FVRewindBackdrop : NSWindow
@end

@implementation FVRewindBackdrop

/* Keys stay with the viewer in front. */
- (BOOL)canBecomeKeyWindow
{
  return NO;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}

@end

@implementation FVRewindStage

- (id)initWithFrame:(NSRect)frame owner:(FVRewind *)rewind
{
  if ((self = [super initWithFrame:frame]) != nil)
    owner = rewind;
  return self;
}

- (void)dealloc
{
  RELEASE (sky);
  [super dealloc];
}

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)isOpaque
{
  return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

/* The layout is the mockup's, drawn for a 1280 by 800 screen, scaled. */
- (CGFloat)sx
{
  return NSWidth ([self bounds]) / 1280.0;
}

- (CGFloat)sy
{
  return NSHeight ([self bounds]) / 800.0;
}

- (NSRect)frontRect
{
  return NSMakeRect (floor (170 * [self sx]), floor (290 * [self sy]),
                     floor (860 * [self sx]), floor (430 * [self sy]));
}

- (void)drawSky
{
  BOOL isDark = FVRewindDark ();
  if (sky == nil || skyDark != isDark)
    {
      RELEASE (sky);
      sky = [[NSGradient alloc] initWithColorsAndLocations:
          FVRewindColor (FVRewindSkyTop), (CGFloat)0,
          FVRewindColor (FVRewindSkyMiddle), (CGFloat).55,
          FVRewindColor (FVRewindSkyBottom), (CGFloat)1, nil];
      skyDark = isDark;
    }
  /* Lit from above the middle, as the mockup's backdrop is. */
  [sky drawInRect:[self bounds] relativeCenterPosition:NSMakePoint (0, .64)];
}

/* Older snapshots, up and back behind the viewer: each a frame with the
   folder's name and its date, smaller and fainter the older it is. */
- (void)drawFrames
{
  NSArray *versions = [owner versions];
  NSInteger current = [owner currentVersion];
  NSInteger behind = MIN (6, (NSInteger)[versions count] - current - 1);
  NSRect front = [self frontRect];
  NSString *folder = [owner folderTitle];
  NSInteger i;
  for (i = behind; i >= 1; i--)
    {
      CGFloat scale = 1 - i * .075, alpha = 1 - i * .13;
      NSRect r = NSMakeRect (0, 0, floor (NSWidth (front) * scale),
                             floor (NSHeight (front) * scale));
      r.origin.x = floor (NSMinX (front) + (NSWidth (front) - NSWidth (r)) / 2);
      r.origin.y = floor (NSMinY (front) - i * 38 * [self sy]);
      NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:r xRadius:10 yRadius:10];
      [[[NSColor blackColor] colorWithAlphaComponent:(FVRewindDark () ? .30 : .12) * alpha] set];
      [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect (NSInsetRect (r, -3, -3), 0, 6)
                                       xRadius:13
                                       yRadius:13] fill];
      [[FVRewindColor (FVRewindGhost) colorWithAlphaComponent:alpha] set];
      [frame fill];
      NSRect bar = NSMakeRect (NSMinX (r), NSMinY (r), NSWidth (r), 26);
      [NSGraphicsContext saveGraphicsState];
      [frame addClip];
      [[FVRewindColor (FVRewindGhostBar) colorWithAlphaComponent:alpha] set];
      [NSBezierPath fillRect:bar];
      [NSGraphicsContext restoreGraphicsState];
      [[FVRewindColor (FVRewindLine) colorWithAlphaComponent:.1 * alpha + .02] set];
      [frame setLineWidth:1];
      [frame stroke];
      NSString *name = [versions objectAtIndex:current + i];
      FVDrawCentered ([NSString stringWithFormat:@"%@ — %@", folder, FVSnapshotTitle (name)],
                      NSInsetRect (bar, 12, 0),
                      FVRewindAttributes (11, YES, [FVRewindColor (FVRewindDim)
                                                 colorWithAlphaComponent:alpha]));
    }
}

/* The timeline: Now at the bottom, older going up, the shown time in
   the accent. Clicking a time goes there. With more times than fit,
   every one keeps its tick and only some their labels. */
- (void)drawTimeline
{
  CGFloat sx = [self sx], sy = [self sy];
  NSRect r = NSMakeRect (NSWidth ([self bounds]) - floor ((26 + 170) * sx), floor (80 * sy),
                         floor (170 * sx), NSHeight ([self bounds]) - floor (200 * sy));
  timelineRect = r;
  NSBezierPath *panel = [NSBezierPath bezierPathWithRoundedRect:r xRadius:12 yRadius:12];
  [FVRewindColor (FVRewindPanel) set];
  [panel fill];
  [FVRewindColor (FVRewindLine) set];
  [panel stroke];
  NSDictionary *caption = FVRewindAttributes (10, YES, FVRewindColor (FVRewindFaint));
  NSString *older = @"OLDER ↑", *now = @"NOW ↓";
  NSSize size = [older sizeWithAttributes:caption];
  [older drawAtPoint:NSMakePoint (NSMaxX (r) - 12 - size.width, NSMinY (r) + 10)
      withAttributes:caption];
  size = [now sizeWithAttributes:caption];
  [now drawAtPoint:NSMakePoint (NSMaxX (r) - 12 - size.width, NSMaxY (r) - 10 - size.height)
    withAttributes:caption];

  NSArray *versions = [owner versions];
  NSInteger count = [versions count] + 1, current = [owner currentVersion] + 1;
  CGFloat top = NSMinY (r) + 36, bottom = NSMaxY (r) - 36;
  CGFloat step = count > 1 ? (bottom - top) / (count - 1) : 0;
  NSInteger every = step >= 15 ? 1 : (NSInteger)ceil (15 / MAX (step, .5));
  NSInteger i;
  for (i = 0; i < count; i++)
    {
      /* 0 is Now, at the bottom; i is versions[i - 1]. */
      CGFloat y = floor (bottom - i * step) + .5;
      BOOL here = i == current;
      [(here ? FVRewindColor (FVRewindAccent) : FVRewindColor (FVRewindDim)) set];
      [NSBezierPath fillRect:here ? NSMakeRect (NSMaxX (r) - 12 - 22, y - 1.5, 22, 3)
                       : NSMakeRect (NSMaxX (r) - 12 - 12, y - 1, 12, 2)];
      /* Labels for Now, the shown time, and every so many between, but
         none crowding the shown one. */
      if (!here && i && (i % every || labs ((long)(i - current)) < every))
        continue;
      NSString *label = i ? FVSnapshotTitle ([versions objectAtIndex:i - 1]) : @"Now";
      NSDictionary *attributes = FVRewindAttributes (here ? 12 : 11, here,
          here ? FVRewindColor (FVRewindAccent)
               : FVRewindColor (i < 3 ? FVRewindText : FVRewindDim));
      size = [label sizeWithAttributes:attributes];
      [label drawAtPoint:NSMakePoint (NSMaxX (r) - 12 - (here ? 22 : 12) - 10 - size.width,
                                      y - size.height / 2)
          withAttributes:attributes];
    }
}

/* A key in the bar's hints, drawn at *at (unless measuring) and *at moved
   past it. */
static void
FVDrawKey (NSString *key, NSPoint *at, CGFloat middle, BOOL draw)
{
  NSDictionary *attributes = FVRewindAttributes (11, YES, FVRewindColor (FVRewindText));
  NSSize size = [key sizeWithAttributes:attributes];
  NSRect box = NSMakeRect (at->x, floor (middle - 9), MAX (18, ceil (size.width) + 12), 18);
  at->x = NSMaxX (box) + 5;
  if (!draw)
    return;
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect (box, .5, .5)
                                                       xRadius:5
                                                       yRadius:5];
  [FVRewindColor (FVRewindPill) set];
  [path fill];
  [FVRewindColor (FVRewindLine) set];
  [path stroke];
  FVDrawCentered (key, box, attributes);
}

static void
FVDrawWords (NSString *words, NSPoint *at, CGFloat middle, CGFloat gap, BOOL draw)
{
  NSDictionary *attributes = FVRewindAttributes (12, NO, FVRewindColor (FVRewindDim));
  NSSize size = [words sizeWithAttributes:attributes];
  if (draw)
    [words drawAtPoint:NSMakePoint (at->x, middle - size.height / 2) withAttributes:attributes];
  at->x += ceil (size.width) + gap;
}

/* "↑ older  ↓ newer  esc back to now", from at.x; returns where it ends. */
static CGFloat
FVDrawHints (NSPoint at, CGFloat middle, BOOL draw)
{
  FVDrawKey (@"↑", &at, middle, draw);
  FVDrawWords (@"older", &at, middle, 14, draw);
  FVDrawKey (@"↓", &at, middle, draw);
  FVDrawWords (@"newer", &at, middle, 14, draw);
  FVDrawKey (@"esc", &at, middle, draw);
  FVDrawWords (@"back to now", &at, middle, 0, draw);
  return at.x;
}

/* The bar at the bottom: the keys, Cancel, and Restore with how many. */
- (void)drawBar
{
  NSUInteger selected = [owner selectedCount];
  NSString *restore = [NSString stringWithFormat:@"Restore %@",
      selected == 1 ? @"1 Item" : [NSString stringWithFormat:@"%lu Items",
                                                             (unsigned long)selected]];
  NSDictionary *button = FVRewindAttributes (13, YES, FVRewindColor (FVRewindText));
  CGFloat cancelWidth = ceil ([@"Cancel" sizeWithAttributes:button].width) + 36;
  CGFloat restoreWidth = ceil ([restore sizeWithAttributes:button].width) + 36;
  CGFloat hintWidth = FVDrawHints (NSZeroPoint, 0, NO);
  CGFloat width = 20 + hintWidth + 18 + 1 + 18 + cancelWidth + 18 + restoreWidth + 14;
  NSRect bar = NSMakeRect (floor ((NSWidth ([self bounds]) - width) / 2),
                           NSHeight ([self bounds]) - floor (26 * [self sy]) - 50, width, 50);
  NSBezierPath *panel = [NSBezierPath bezierPathWithRoundedRect:bar xRadius:14 yRadius:14];
  [[[NSColor blackColor] colorWithAlphaComponent:.18] set];
  [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect (NSInsetRect (bar, -2, -2), 0, 6)
                                   xRadius:16
                                   yRadius:16] fill];
  [FVRewindColor (FVRewindPanel) set];
  [panel fill];
  [FVRewindColor (FVRewindLine) set];
  [panel stroke];

  CGFloat middle = NSMidY (bar);
  NSPoint at = NSMakePoint (NSMinX (bar) + 20, middle);
  FVDrawHints (at, middle, YES);
  at.x = NSMinX (bar) + 20 + hintWidth + 18;
  [FVRewindColor (FVRewindLine) set];
  [NSBezierPath fillRect:NSMakeRect (at.x, middle - 11, 1, 22)];
  at.x += 19;

  cancelRect = NSMakeRect (at.x, middle - 15, cancelWidth, 30);
  NSBezierPath *cancel = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect (cancelRect, .5, .5)
                                                         xRadius:7
                                                         yRadius:7];
  [FVRewindColor (FVRewindLine) set];
  [cancel stroke];
  FVDrawCentered (@"Cancel", cancelRect, button);

  restoreRect = NSMakeRect (NSMaxX (cancelRect) + 18, middle - 15, restoreWidth, 30);
  CGFloat alpha = selected ? 1 : .4;
  [[FVRewindColor (FVRewindAccent) colorWithAlphaComponent:alpha] set];
  [[NSBezierPath bezierPathWithRoundedRect:restoreRect xRadius:7 yRadius:7] fill];
  FVDrawCentered (restore, restoreRect,
                  FVRewindAttributes (13, YES, [FVRewindColor (FVRewindAccentText)
                                             colorWithAlphaComponent:alpha]));
}

- (void)drawRect:(NSRect)rect
{
  [self drawSky];
  [self drawFrames];
  [self drawTimeline];
  [self drawBar];
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  if (NSPointInRect (p, cancelRect))
    [owner leaveRewind:self];
  else if (NSPointInRect (p, restoreRect))
    {
      if ([owner selectedCount])
        [owner restore:self];
    }
  else if (NSPointInRect (p, timelineRect))
    {
      NSInteger count = [[owner versions] count] + 1;
      CGFloat top = NSMinY (timelineRect) + 36, bottom = NSMaxY (timelineRect) - 36;
      CGFloat step = count > 1 ? (bottom - top) / (count - 1) : 1;
      NSInteger i = (NSInteger)floor ((bottom - p.y) / step + .5);
      i = MAX (0, MIN (count - 1, i));
      if (i == 0)
        [owner leaveRewind:self];
      else
        [owner jumpToVersion:i - 1];
    }
}

@end

/* A restored item meets one of the same name in the folder now: Skip,
   Replace or Keep Both (the default), and Do this for every item when
   more follow. -run returns 0 Skip, 1 Replace or 2 Keep Both. */
@interface FVRestorePanel : NSObject <FVModalDialog>
{
  NSPanel *panel;
  NSButton *everyItem;
}
- (id)initWithSource:(NSString *)source
         destination:(NSString *)destination
               taken:(NSDate *)taken
           remaining:(NSUInteger)remaining
              viewer:(FVWindow *)viewer;
- (BOOL)everyItem;
@end

@implementation FVRestorePanel

- (id)initWithSource:(NSString *)source
         destination:(NSString *)destination
               taken:(NSDate *)taken
           remaining:(NSUInteger)remaining
              viewer:(FVWindow *)viewer
{
  if ((self = [super init]) == nil)
    return nil;
  panel = [[FVDialogPanel alloc] initWithContentRect:NSMakeRect (0, 0, 480, 168)
                                           styleMask:NSTitledWindowMask
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
  [panel setTitle:@"Restore"];
  /* Above the viewer, which stands over the rest while rewinding. */
  [panel setLevel:NSModalPanelWindowLevel];
  NSView *content = [panel contentView];
  NSColor *color = FVDialogTextColor (panel);
  NSString *folder = [[destination stringByDeletingLastPathComponent] lastPathComponent];
  NSImageView *icon = AUTORELEASE ([[NSImageView alloc]
      initWithFrame:NSMakeRect (20, 104, 44, 44)]);
  [icon setImage:[viewer iconForPath:destination]];
  [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
  [icon setEditable:NO];
  [content addSubview:icon];
  NSTextField *heading = FVRewindLabel (NSMakeRect (78, 126, 384, 22),
      [NSString stringWithFormat:@"“%@” is in %@ now, too",
                                 [destination lastPathComponent], folder]);
  [heading setFont:[NSFont boldSystemFontOfSize:14]];
  [[heading cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [heading setTextColor:color];
  [content addSubview:heading];
  NSDate *changed = [[[NSFileManager defaultManager] attributesOfItemAtPath:destination
                                                                      error:NULL]
      fileModificationDate];
  NSTextField *message = FVRewindLabel (NSMakeRect (78, 82, 384, 40),
      [NSString stringWithFormat:@"The one in %@ was changed %@. The one you are "
                                 @"restoring is from %@.",
                                 folder, changed ? FVChangedPhrase (changed) : @"since",
                                 FVLongDate (taken, @" at ")]);
  [[message cell] setWraps:YES];
  [[message cell] setLineBreakMode:NSLineBreakByWordWrapping];
  [message setFont:[NSFont systemFontOfSize:12.5]];
  [message setTextColor:[color colorWithAlphaComponent:.75]];
  [content addSubview:message];
  everyItem = [[NSButton alloc] initWithFrame:NSMakeRect (76, 56, 300, 22)];
  [everyItem setButtonType:NSSwitchButton];
  [everyItem setTitle:@"Do this for every item"];
  if (remaining)
    [content addSubview:everyItem];
  NSArray *titles = [NSArray arrayWithObjects:@"Skip", @"Replace", @"Keep Both", nil];
  CGFloat x = 480 - 20;
  NSInteger i;
  for (i = [titles count] - 1; i >= 0; i--)
    {
      NSButton *button = AUTORELEASE ([[NSButton alloc]
          initWithFrame:NSMakeRect (x - 98, 14, 98, 30)]);
      [button setTitle:[titles objectAtIndex:i]];
      [button setTag:i];
      [button setTarget:self];
      [button setAction:@selector (choose:)];
      if (i == 2)
        [button setKeyEquivalent:@"\r"];
      else if (i == 0)
        [button setKeyEquivalent:@"\e"];
      [content addSubview:button];
      x -= 106;
    }
  /* Over the viewer, near its top, as a sheet would be. */
  NSRect over = [[viewer window] frame], frame = [panel frame];
  frame.origin.x = floor (NSMidX (over) - NSWidth (frame) / 2);
  frame.origin.y = floor (NSMaxY (over) - 60 - NSHeight (frame));
  [panel setFrame:frame display:NO];
  return self;
}

- (void)choose:(id)sender
{
  [NSApp stopModalWithCode:[sender tag]];
}

- (NSInteger)run
{
  [panel makeKeyAndOrderFront:nil];
  NSInteger choice = FVRunModalPanel (panel);
  [panel orderOut:nil];
  return choice;
}

- (BOOL)everyItem
{
  return [everyItem superview] && [everyItem state] == NSOnState;
}

- (void)dealloc
{
  RELEASE (panel);
  RELEASE (everyItem);
  [super dealloc];
}

@end

/* A spinner turning while a snapshot is on its way, then a circle with
   an arrow once it's taken: the viewer's status line shows it. */
@implementation FVStatusSpinner

- (void)setBusy:(BOOL)flag
{
  busy = flag;
  [timer invalidate];
  DESTROY (timer);
  if (busy)
    timer = RETAIN ([NSTimer scheduledTimerWithTimeInterval:.1
                                                     target:self
                                                   selector:@selector (turn:)
                                                   userInfo:nil
                                                    repeats:YES]);
  [self setNeedsDisplay:YES];
}

- (void)turn:(NSTimer *)sender
{
  angle = fmod (angle + 30, 360);
  [self setNeedsDisplay:YES];
}

- (void)viewWillMoveToWindow:(NSWindow *)window
{
  if (window == nil)
    [self setBusy:NO];
}

- (void)drawRect:(NSRect)rect
{
  NSPoint centre = NSMakePoint (NSMidX ([self bounds]), NSMidY ([self bounds]));
  NSBezierPath *path = [NSBezierPath bezierPath];
  [path setLineWidth:2];
  [path setLineCapStyle:NSRoundLineCapStyle];
  [FVRewindColor (FVRewindAccent) set];
  if (busy)
    {
      [path appendBezierPathWithArcWithCenter:centre radius:5
                                   startAngle:-angle
                                     endAngle:-angle + 270];
      [path stroke];
      return;
    }
  [path appendBezierPathWithArcWithCenter:centre radius:5 startAngle:120 endAngle:420];
  [path stroke];
  NSBezierPath *head = [NSBezierPath bezierPath];
  NSPoint tip = NSMakePoint (centre.x + 5 * cos (M_PI * 120 / 180),
                             centre.y + 5 * sin (M_PI * 120 / 180));
  [head moveToPoint:NSMakePoint (tip.x - 3.5, tip.y + .5)];
  [head lineToPoint:tip];
  [head lineToPoint:NSMakePoint (tip.x + .5, tip.y + 3.5)];
  [head setLineWidth:2];
  [head setLineCapStyle:NSRoundLineCapStyle];
  [head stroke];
}

- (void)dealloc
{
  [timer invalidate];
  RELEASE (timer);
  [super dealloc];
}

@end

@implementation FVRewind

+ (BOOL)appliesToPath:(NSString *)folder
{
  NSString *home = [NSHomeDirectory () stringByStandardizingPath];
  folder = [folder stringByStandardizingPath];
  return [folder isEqual:home] || [folder hasPrefix:[home stringByAppendingString:@"/"]];
}

- (id)initWithViewer:(FVWindow *)aViewer
{
  if ((self = [super init]) != nil)
    {
      viewer = aViewer;
      home = [[NSHomeDirectory () stringByStandardizingPath] copy];
    }
  return self;
}

- (void)dealloc
{
  [snapshotTimer invalidate];
  RELEASE (snapshotTimer);
  [backdrop close];
  RELEASE (backdrop);
  RELEASE (stage);
  RELEASE (schedule);
  RELEASE (versions);
  RELEASE (home);
  RELEASE (liveFolder);
  RELEASE (restoreFolder);
  RELEASE (changes);
  RELEASE (askedAt);
  RELEASE (namesBefore);
  RELEASE (latestBefore);
  RELEASE (takenName);
  [super dealloc];
}

- (BOOL)isRewinding
{
  return rewinding;
}

- (NSString *)rewindDirectory
{
  return [home stringByAppendingPathComponent:@"Library/Rewind"];
}

- (NSString *)snapshotRoot
{
  return [home stringByAppendingPathComponent:@".zfs/snapshot"];
}

/* Where home's snapshots live: this computer, or the server for a network
   home. */
- (NSString *)sourceName
{
  return [home hasPrefix:@"/Network/"] ? @"the server" : @"this computer";
}

/* Snapshots need the home folder to be a ZFS dataset of its own: its
   .zfs directory is there then (locally, and over NFS for a network home).
   A home made before homes were datasets is a plain folder, which can't
   have snapshots; say so rather than taking requests nobody answers. */
- (BOOL)homeIsDataset
{
  return [[NSFileManager defaultManager]
      fileExistsAtPath:[home stringByAppendingPathComponent:@".zfs"]];
}

- (BOOL)explainIfNotDataset:(NSString *)title
{
  if ([self homeIsDataset])
    return NO;
  NSRunAlertPanel (title,
                   @"Your home folder is a plain folder, not a dataset of its own, so it "
                   @"can't have snapshots. Homes made before NextBSD gave each person a "
                   @"dataset need converting on %@ first.",
                   @"OK", nil, nil,
                   [home hasPrefix:@"/Network/"] ? @"the directory server" : @"this computer");
  return YES;
}

/* ---- the schedule ---- */

- (NSDictionary *)readKeyValues:(NSString *)file
{
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  NSString *text = [NSString stringWithContentsOfFile:
      [[self rewindDirectory] stringByAppendingPathComponent:file]];
  NSEnumerator *e = [[text componentsSeparatedByString:@"\n"] objectEnumerator];
  NSString *line;
  while ((line = [e nextObject]) != nil)
    {
      NSRange eq = [line rangeOfString:@"="];
      if (eq.location == NSNotFound)
        continue;
      [values setObject:[[line substringFromIndex:NSMaxRange (eq)]
                            stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceCharacterSet]]
                 forKey:[[line substringToIndex:eq.location]
                            stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceCharacterSet]]];
    }
  return values;
}

- (BOOL)ensureRewindDirectory
{
  return [[NSFileManager defaultManager] createDirectoryAtPath:[self rewindDirectory]
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:NULL];
}

static NSPopUpButton *
FVRewindPopUp (NSView *view, NSRect frame, NSArray *titles)
{
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame:frame
                                                                 pullsDown:NO]);
  [popUp addItemsWithTitles:titles];
  [view addSubview:popUp];
  return popUp;
}

static NSButton *
FVRewindCheckbox (NSView *view, NSRect frame, NSString *title)
{
  NSButton *box = AUTORELEASE ([[NSButton alloc] initWithFrame:frame]);
  [box setButtonType:NSSwitchButton];
  [box setTitle:title];
  [view addSubview:box];
  return box;
}

- (void)buildSchedule
{
  schedule = [[NSPanel alloc] initWithContentRect:NSMakeRect (0, 0, 470, 360)
                                        styleMask:NSTitledWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [schedule setTitle:@"Snapshots"];
  NSView *v = [schedule contentView];
  CGFloat y = 316;
  NSTextField *title = FVRewindLabel (NSMakeRect (20, y, 430, 24),
      [NSString stringWithFormat:@"Snapshots of %@'s home", NSUserName ()]);
  [title setFont:[NSFont boldSystemFontOfSize:0]];
  [v addSubview:title];
  y -= 34;
  [v addSubview:FVRewindLabel (NSMakeRect (20, y, 120, 22), @"Snapshots:")];
  enabledBox = FVRewindCheckbox (v, NSMakeRect (148, y, 60, 22), @"On");
  [enabledBox setTarget:self];
  [enabledBox setAction:@selector (enabledChanged:)];
  statusLabel = FVRewindLabel (NSMakeRect (210, y, 250, 22), @"");
  [statusLabel setTextColor:[NSColor secondaryLabelColor]];
  [v addSubview:statusLabel];
  y -= 36;
  [v addSubview:FVRewindLabel (NSMakeRect (20, y, 120, 22), @"How often:")];
  freqPopUp = FVRewindPopUp (v, NSMakeRect (148, y - 2, 170, 26), FVFreqTitles ());
  [freqPopUp setTarget:self];
  [freqPopUp setAction:@selector (enabledChanged:)];
  NSMutableArray *times = [NSMutableArray array];
  int h;
  for (h = 0; h < 24; h++)
    [times addObject:[NSString stringWithFormat:@"%02d:00", h]];
  atPopUp = FVRewindPopUp (v, NSMakeRect (326, y - 2, 90, 26), times);
  y -= 36;
  [v addSubview:FVRewindLabel (NSMakeRect (20, y, 120, 22), @"Keep for:")];
  keepPopUp = FVRewindPopUp (v, NSMakeRect (148, y - 2, 170, 26), FVKeepTitles ());
  y -= 22;
  NSTextField *hint = FVRewindLabel (NSMakeRect (148, y, 300, 18),
                                     @"Older snapshots are removed automatically.");
  [hint setTextColor:[NSColor secondaryLabelColor]];
  [hint setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [v addSubview:hint];
  y -= 32;
  thinBox = FVRewindCheckbox (v, NSMakeRect (146, y, 310, 22),
                              @"After 2 days, keep one a day");
  y -= 26;
  beforeBox = FVRewindCheckbox (v, NSMakeRect (146, y, 310, 22),
                                @"Take one before each system update");
  y -= 26;
  lowBox = FVRewindCheckbox (v, NSMakeRect (146, y, 310, 22),
                             @"When space runs low, remove the oldest");
  y -= 30;
  NSTextField *where = FVRewindLabel (NSMakeRect (20, y, 430, 18),
      [NSString stringWithFormat:@"Snapshots are kept on %@, in your home folder's dataset.",
                                 [self sourceName]]);
  [where setTextColor:[NSColor secondaryLabelColor]];
  [where setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [v addSubview:where];

  NSButton *now = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (16, 14, 160, 28)]);
  [now setTitle:@"Take Snapshot Now"];
  [now setTarget:self];
  [now setAction:@selector (takeSnapshotNow:)];
  [v addSubview:now];
  NSButton *cancel = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (238, 14, 96, 28)]);
  [cancel setTitle:@"Cancel"];
  [cancel setKeyEquivalent:@"\e"];
  [cancel setTarget:self];
  [cancel setAction:@selector (cancelSchedule:)];
  [v addSubview:cancel];
  NSButton *save = AUTORELEASE ([[NSButton alloc] initWithFrame:NSMakeRect (342, 14, 112, 28)]);
  [save setTitle:@"Save Schedule"];
  [save setKeyEquivalent:@"\r"];
  [save setTarget:self];
  [save setAction:@selector (saveSchedule:)];
  [v addSubview:save];
}

- (void)selectValue:(NSString *)value
          inPopUp:(NSPopUpButton *)popUp
           values:(NSArray *)values
         fallback:(NSString *)fallback
{
  NSUInteger i = [values indexOfObject:value ? value : fallback];
  [popUp selectItemAtIndex:i == NSNotFound ? [values indexOfObject:fallback] : i];
}

- (void)showStatus
{
  NSDictionary *status = [self readKeyValues:@"Status"];
  NSString *count = [status objectForKey:@"count"];
  if ([enabledBox state] != NSOnState && ![count intValue])
    {
      [statusLabel setStringValue:@"Off"];
      return;
    }
  double used = [[status objectForKey:@"used"] doubleValue] / (1024.0 * 1024.0);
  NSString *latest = [status objectForKey:@"latest"];
  [statusLabel setStringValue:
      [NSString stringWithFormat:@"%d kept · %.1f MB%@", [count intValue], used,
                                 [latest length] ? [@" · latest "
                                     stringByAppendingString:FVSnapshotTitle (latest)]
                                                 : @""]];
}

- (void)enabledChanged:(id)sender
{
  BOOL on = [enabledBox state] == NSOnState;
  NSInteger freq = [freqPopUp indexOfSelectedItem];
  [freqPopUp setEnabled:on];
  [atPopUp setEnabled:on && freq >= 2];
  [keepPopUp setEnabled:on];
  [thinBox setEnabled:on];
  [beforeBox setEnabled:on];
  [lowBox setEnabled:on];
}

/* Snapshots: the schedule for this home, with Save Schedule, or Take
   Snapshot Now for one at once. */
- (void)showSnapshots:(id)sender
{
  if ([self explainIfNotDataset:@"Snapshots"])
    return;
  if (schedule == nil)
    [self buildSchedule];
  NSDictionary *s = [self readKeyValues:@"Schedule"];
  [enabledBox setState:[[s objectForKey:@"enabled"] isEqual:@"1"] ? NSOnState : NSOffState];
  [self selectValue:[s objectForKey:@"freq"] inPopUp:freqPopUp
             values:FVFreqValues () fallback:@"hourly"];
  [self selectValue:[s objectForKey:@"keep"] inPopUp:keepPopUp
             values:FVKeepValues () fallback:@"14"];
  NSString *at = [s objectForKey:@"at"];
  [atPopUp selectItemWithTitle:[at length] == 5 ? at : @"02:00"];
  if ([atPopUp indexOfSelectedItem] < 0)
    [atPopUp selectItemWithTitle:@"02:00"];
  [thinBox setState:[[s objectForKey:@"thin"] isEqual:@"0"] ? NSOffState : NSOnState];
  [beforeBox setState:[[s objectForKey:@"before"] isEqual:@"0"] ? NSOffState : NSOnState];
  [lowBox setState:[[s objectForKey:@"low"] isEqual:@"0"] ? NSOffState : NSOnState];
  [self enabledChanged:nil];
  [self showStatus];
  [schedule center];
  [NSApp runModalForWindow:schedule];
  [schedule orderOut:nil];
}

- (void)cancelSchedule:(id)sender
{
  [NSApp stopModal];
}

- (void)saveSchedule:(id)sender
{
  NSString *text = [NSString stringWithFormat:
      @"enabled=%d\nfreq=%@\nat=%@\nkeep=%@\nthin=%d\nbefore=%d\nlow=%d\n",
      [enabledBox state] == NSOnState,
      [FVFreqValues () objectAtIndex:[freqPopUp indexOfSelectedItem]],
      [atPopUp titleOfSelectedItem],
      [FVKeepValues () objectAtIndex:[keepPopUp indexOfSelectedItem]],
      [thinBox state] == NSOnState, [beforeBox state] == NSOnState,
      [lowBox state] == NSOnState];
  if (![self ensureRewindDirectory]
      || ![text writeToFile:[[self rewindDirectory] stringByAppendingPathComponent:@"Schedule"]
                 atomically:YES])
    {
      NSRunAlertPanel (@"Snapshots", @"The schedule couldn't be saved in %@.", @"OK", nil,
                       nil, [self rewindDirectory]);
      return;
    }
  [NSApp stopModal];
  [viewer showNote:[enabledBox state] == NSOnState ? @"Snapshot schedule saved."
                                                   : @"Scheduled snapshots are off."
              busy:NO];
  [viewer performSelector:@selector (clearNote) withObject:nil afterDelay:8];
}

/* Our snapshots of home, as they are listed now. */
- (NSArray *)snapshotNames
{
  NSArray *names = [[NSFileManager defaultManager] directoryContentsAtPath:[self snapshotRoot]];
  return names ? names : [NSArray array];
}

/* Ask for a snapshot now and close: the rewind job takes it within a
   minute, where the home is kept. Until it's there the status line says
   it's on its way; then when it was taken, how many there are and the
   space they use. */
- (void)takeSnapshotNow:(id)sender
{
  if (![self ensureRewindDirectory]
      || ![@"" writeToFile:[[self rewindDirectory] stringByAppendingPathComponent:@"SnapshotNow"]
               atomically:YES])
    {
      NSRunAlertPanel (@"Snapshots", @"A snapshot couldn't be asked for in %@.", @"OK", nil,
                       nil, [self rewindDirectory]);
      return;
    }
  [NSApp stopModal];
  ASSIGN (namesBefore, [self snapshotNames]);
  ASSIGN (latestBefore, [[self readKeyValues:@"Status"] objectForKey:@"latest"]);
  ASSIGN (askedAt, [NSDate date]);
  DESTROY (takenName);
  [NSObject cancelPreviousPerformRequestsWithTarget:viewer selector:@selector (clearNote)
                                             object:nil];
  [viewer showNote:@"Taking a snapshot of your home folder… it appears in Rewind in "
                   @"under a minute."
              busy:YES];
  [snapshotTimer invalidate];
  ASSIGN (snapshotTimer, [NSTimer scheduledTimerWithTimeInterval:2
                                                          target:self
                                                        selector:@selector (checkSnapshot:)
                                                        userInfo:nil
                                                         repeats:YES]);
}

/* Done once the job's Status names a new latest snapshot (its count and
   space are then up to date), or a while after a new one shows in
   .zfs/snapshot if Status lags. */
- (void)checkSnapshot:(NSTimer *)sender
{
  NSDictionary *status = [self readKeyValues:@"Status"];
  NSString *latest = [status objectForKey:@"latest"];
  NSArray *names = [self snapshotNames];
  NSString *name = nil;
  if ([latest hasPrefix:@"rewind-"] && ![latest isEqual:latestBefore])
    name = latest;
  else
    {
      NSEnumerator *e = [names objectEnumerator];
      NSString *each;
      while ((each = [e nextObject]) != nil)
        if ([each hasPrefix:@"rewind-"] && ![namesBefore containsObject:each])
          {
            if (takenName == nil)
              takenName = [each copy];
            if (-[askedAt timeIntervalSinceNow] > 45)
              name = takenName;
          }
    }
  if (name == nil && -[askedAt timeIntervalSinceNow] < 180)
    return;
  [snapshotTimer invalidate];
  DESTROY (snapshotTimer);
  if (name == nil)
    {
      [viewer showNote:[NSString stringWithFormat:@"No snapshot yet: %@ hasn't taken it. "
                                                  @"It appears in Rewind once it's taken.",
                                                  [self sourceName]]
                  busy:NO];
      return;
    }
  NSUInteger count = [[status objectForKey:@"count"] intValue];
  if (![name isEqual:latest])
    {
      count = 0;
      NSEnumerator *e = [names objectEnumerator];
      NSString *each;
      while ((each = [e nextObject]) != nil)
        count += [each hasPrefix:@"rewind-"];
    }
  NSDate *taken = FVSnapshotStamp (name);
  [viewer showNote:[NSString stringWithFormat:@"Snapshot taken: %@. %lu %@, %@.",
                                              taken ? FVShortDate (taken) : name,
                                              (unsigned long)count,
                                              count == 1 ? @"snapshot" : @"snapshots",
                                              FVSizeString ([[status objectForKey:@"used"]
                                                                longLongValue])]
              busy:NO];
  [viewer performSelector:@selector (clearNote) withObject:nil afterDelay:30];
  if (rewinding)
    {
      /* Rewind shows it straight away, keeping the time it shows. */
      NSString *shown = [versions objectAtIndex:current];
      ASSIGN (versions, [self loadVersions]);
      NSUInteger i = [versions indexOfObject:shown];
      current = i == NSNotFound ? 0 : i;
      [stage setNeedsDisplay:YES];
    }
}

/* ---- Rewind ---- */

/* The folder's path inside home, or nil outside it. */
- (NSString *)relativeInHome:(NSString *)folder
{
  folder = [folder stringByStandardizingPath];
  if ([folder isEqual:home])
    return @"";
  NSString *prefix = [home stringByAppendingString:@"/"];
  if ([folder hasPrefix:prefix])
    return [folder substringFromIndex:[prefix length]];
  return nil;
}

/* A path inside a snapshot as "snapshot" and "relative" parts, or nil. */
- (NSArray *)snapshotPartsOf:(NSString *)folder
{
  NSString *prefix = [[self snapshotRoot] stringByAppendingString:@"/"];
  folder = [folder stringByStandardizingPath];
  if (![folder hasPrefix:prefix])
    return nil;
  NSString *rest = [folder substringFromIndex:[prefix length]];
  NSRange slash = [rest rangeOfString:@"/"];
  if (slash.location == NSNotFound)
    return [NSArray arrayWithObjects:rest, @"", nil];
  return [NSArray arrayWithObjects:[rest substringToIndex:slash.location],
                                   [rest substringFromIndex:NSMaxRange (slash)], nil];
}

- (NSString *)currentRelative
{
  NSArray *parts = [self snapshotPartsOf:[viewer currentPath]];
  return parts ? [parts objectAtIndex:1] : [self relativeInHome:[viewer currentPath]];
}

/* When a snapshot was taken: from its rewind-YYYYMMDD-HHMMSS name, or for
   one named otherwise, when its top folder last changed before it. */
- (NSDate *)dateOfSnapshot:(NSString *)name
{
  if ([name hasPrefix:@"rewind-"] && [name length] == 22)
    {
      NSDate *date = [NSCalendarDate dateWithString:[name substringFromIndex:7]
                                     calendarFormat:@"%Y%m%d-%H%M%S"];
      if (date != nil)
        return date;
    }
  NSDate *changed = [[[NSFileManager defaultManager]
      fileAttributesAtPath:[[self snapshotRoot] stringByAppendingPathComponent:name]
              traverseLink:NO] fileModificationDate];
  return changed ? changed : [NSDate distantPast];
}

static NSInteger
FVNewestFirst (id a, id b, void *context)
{
  return [[(NSDictionary *)context objectForKey:b] compare:
                                [(NSDictionary *)context objectForKey:a]];
}

/* The snapshots of home, newest first. */
- (NSArray *)loadVersions
{
  NSArray *names = [[NSFileManager defaultManager]
      directoryContentsAtPath:[self snapshotRoot]];
  NSMutableDictionary *dates = [NSMutableDictionary dictionary];
  NSEnumerator *e = [names objectEnumerator];
  NSString *name;
  while ((name = [e nextObject]) != nil)
    [dates setObject:[self dateOfSnapshot:name] forKey:name];
  return [names sortedArrayUsingFunction:FVNewestFirst context:dates];
}

/* ---- the stage ---- */

- (NSArray *)versions
{
  return versions;
}

- (NSInteger)currentVersion
{
  return current;
}

/* The folder shown, by name: "Documents", or the home's own. */
- (NSString *)folderTitle
{
  NSString *rel = [self currentRelative];
  return [rel length] ? [rel lastPathComponent] : [home lastPathComponent];
}

- (NSUInteger)selectedCount
{
  return rewinding ? [[viewer selectedPaths] count] : 0;
}

- (NSDate *)shownDate
{
  return [self dateOfSnapshot:[versions objectAtIndex:current]];
}

/* The screen Rewind fills: the viewer's. */
- (NSRect)screenFrame
{
  NSScreen *screen = [[viewer window] screen];
  return [(screen ? screen : [NSScreen mainScreen]) frame];
}

- (void)buildBackdrop
{
  NSRect frame = [self screenFrame];
  backdrop = [[FVRewindBackdrop alloc] initWithContentRect:frame
                                                 styleMask:NSBorderlessWindowMask
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  [backdrop setReleasedWhenClosed:NO];
  [backdrop setExcludedFromWindowsMenu:YES];
  [backdrop setHidesOnDeactivate:NO];
  /* Over the other windows and the Dock, as a screen of its own; the
     viewer stands one level higher, sheets and alerts higher still. */
  [backdrop setLevel:NSDockWindowLevel + 1];
  stage = [[FVRewindStage alloc] initWithFrame:NSMakeRect (0, 0, NSWidth (frame),
                                                           NSHeight (frame))
                                         owner:self];
  [backdrop setContentView:stage];
}

/* The viewer in front, where the stage leaves room for it. */
- (void)placeViewer
{
  NSRect screen = [self screenFrame];
  NSRect front = [stage frontRect];
  [[viewer window] setFrame:NSMakeRect (NSMinX (screen) + NSMinX (front),
                                        NSMaxY (screen) - NSMaxY (front),
                                        NSWidth (front), NSHeight (front))
                    display:YES];
}

/* Show the folder as it was in versions[index]: the same folder inside
   that snapshot, or the nearest folder above it that existed then. */
- (void)showVersion:(NSInteger)index
{
  NSString *rel = [self currentRelative];
  if (rel == nil)
    rel = @"";
  current = index;
  NSString *base = [[self snapshotRoot]
      stringByAppendingPathComponent:[versions objectAtIndex:index]];
  NSString *target = [base stringByAppendingPathComponent:rel];
  BOOL dir = NO;
  while (![[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&dir] || !dir)
    {
      if ([target length] <= [base length])
        break;
      target = [target stringByDeletingLastPathComponent];
    }
  [viewer navigate:target];
  [stage setNeedsDisplay:YES];
}

- (void)jumpToVersion:(NSInteger)index
{
  if (rewinding && index >= 0 && index < (NSInteger)[versions count] && index != current)
    [self showVersion:index];
  [[viewer window] makeKeyAndOrderFront:nil];
}

- (void)enterRewind
{
  if ([self explainIfNotDataset:@"Rewind"])
    return;
  if ([self relativeInHome:[viewer currentPath]] == nil)
    {
      NSRunAlertPanel (@"Rewind", @"Rewind shows earlier versions of folders in your home folder.",
                       @"OK", nil, nil);
      return;
    }
  ASSIGN (versions, [self loadVersions]);
  if (![versions count])
    {
      NSRunAlertPanel (@"Rewind",
                       @"There are no snapshots of your home folder yet. Use Snapshots to "
                       @"turn them on, or to take one now.",
                       @"OK", nil, nil);
      return;
    }
  ASSIGN (liveFolder, [viewer currentPath]);
  NSWindow *window = [viewer window];
  liveFrame = [window frame];
  liveLevel = [window level];
  if (backdrop == nil)
    [self buildBackdrop];
  else
    {
      NSRect frame = [self screenFrame];
      [backdrop setFrame:frame display:NO];
      [stage setFrame:NSMakeRect (0, 0, NSWidth (frame), NSHeight (frame))];
    }
  rewinding = YES;
  current = 0;
  [stage setNeedsDisplay:YES];
  [backdrop orderFront:nil];
  [window setLevel:NSDockWindowLevel + 2];
  [self placeViewer];
  [window makeKeyAndOrderFront:nil];
  [viewer rewindDidChange];
  /* Start one step back: the most recent snapshot. */
  [self showVersion:0];
}

/* Back to now: the viewer where and as it was, showing the folder it
   was showing in the snapshot, as it is now (or the nearest one above
   that still exists). */
- (void)leaveRewindReturning:(BOOL)back
{
  if (!rewinding)
    return;
  NSString *rel = [self currentRelative];
  rewinding = NO;
  [backdrop orderOut:nil];
  NSWindow *window = [viewer window];
  [window setLevel:liveLevel];
  [window setFrame:liveFrame display:YES];
  [viewer rewindDidChange];
  if (back)
    {
      NSString *folder = rel ? [home stringByAppendingPathComponent:rel] : liveFolder;
      BOOL dir = NO;
      while (![[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&dir] || !dir)
        {
          if ([folder length] <= [home length])
            {
              folder = home;
              break;
            }
          folder = [folder stringByDeletingLastPathComponent];
        }
      [viewer navigate:folder];
    }
  [[viewer window] setTitle:@"File Viewer"];
  [window makeKeyAndOrderFront:nil];
}

- (void)leaveRewind:(id)sender
{
  [self leaveRewindReturning:YES];
}

- (void)toggleRewind:(id)sender
{
  if (rewinding)
    [self leaveRewindReturning:YES];
  else
    [self enterRewind];
}

/* Up for older, Down for newer, Escape for now. The viewer's other keys
   (Return to open a folder, typing to select) work as usual. */
- (BOOL)handleKey:(NSEvent *)event
{
  if (!rewinding)
    return NO;
  NSString *text = [event charactersIgnoringModifiers];
  unichar key = [text length] ? [text characterAtIndex:0] : 0;
  if ([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask))
    return NO;
  if (key == NSUpArrowFunctionKey)
    {
      if (current + 1 < (NSInteger)[versions count])
        [self showVersion:current + 1];
      return YES;
    }
  if (key == NSDownArrowFunctionKey)
    {
      if (current > 0)
        [self showVersion:current - 1];
      return YES;
    }
  if (key == '\e')
    {
      [self leaveRewindReturning:YES];
      return YES;
    }
  return NO;
}

/* The title says which folder and which time the viewer shows. A folder
   reached outside the snapshots while rewinding (the sidebar, Back) is
   shown as it was in the same snapshot, if it's in the home; anywhere
   else ends Rewind. */
- (void)viewerDidNavigate
{
  if (!rewinding)
    return;
  NSArray *parts = [self snapshotPartsOf:[viewer currentPath]];
  NSUInteger index = parts ? [versions indexOfObject:[parts objectAtIndex:0]] : NSNotFound;
  if (index == NSNotFound)
    {
      NSString *rel = [self relativeInHome:[viewer currentPath]];
      if (rel != nil && ![rel isEqual:@".zfs"] && ![rel hasPrefix:@".zfs/"])
        [self performSelector:@selector (followIntoSnapshot) withObject:nil afterDelay:0];
      else
        [self leaveRewindReturning:NO];
      return;
    }
  current = index;
  [[viewer window] setTitle:[NSString stringWithFormat:@"%@ — %@", [self folderTitle],
                                                       FVLongDate ([self shownDate], @", ")]];
  [stage setNeedsDisplay:YES];
}

- (void)followIntoSnapshot
{
  if (rewinding && [self snapshotPartsOf:[viewer currentPath]] == nil)
    [self showVersion:current];
}

/* ---- what changed since ---- */

- (BOOL)showsOnlyChanges
{
  return onlyChanges;
}

- (void)setShowsOnlyChanges:(BOOL)flag
{
  onlyChanges = flag;
  if (rewinding)
    [viewer refresh:nil];
}

- (void)listingWillStart
{
  if (changes == nil)
    changes = [[NSMutableDictionary alloc] init];
  [changes removeAllObjects];
  shownCount = removedCount = changedCount = 0;
}

/* How an item in a snapshot differs from the same path in the home now:
   gone (removed), or there with another modification time or size
   (changed). Folders compare by modification time, which changes as
   their contents come and go. */
- (NSString *)changeOfItem:(FVItem *)item
{
  NSArray *parts = [self snapshotPartsOf:[item path]];
  if (parts == nil)
    return @"";
  NSString *live = [home stringByAppendingPathComponent:[parts objectAtIndex:1]];
  NSDictionary *now = [[NSFileManager defaultManager] attributesOfItemAtPath:live error:NULL];
  if (now == nil)
    return @"removed";
  NSDictionary *then = [item attributes];
  NSDate *a = [then fileModificationDate], *b = [now fileModificationDate];
  if (![[then fileType] isEqual:[now fileType]]
      || (a && b && fabs ([a timeIntervalSinceDate:b]) >= 1)
      || (![item directory] && [then fileSize] != [now fileSize]))
    return @"changed";
  return @"";
}

- (NSArray *)filterItems:(NSArray *)found
{
  if (!rewinding)
    return found;
  NSMutableArray *kept = [NSMutableArray arrayWithCapacity:[found count]];
  NSEnumerator *e = [found objectEnumerator];
  FVItem *item;
  while ((item = [e nextObject]) != nil)
    {
      NSString *change = [self changeOfItem:item];
      [changes setObject:change forKey:[item path]];
      if ([change isEqual:@"removed"])
        removedCount++;
      else if ([change isEqual:@"changed"])
        changedCount++;
      else if (onlyChanges)
        continue;
      [kept addObject:item];
    }
  shownCount += [kept count];
  return kept;
}

- (NSString *)changeAtPath:(NSString *)value
{
  NSString *change = [changes objectForKey:value];
  return [change length] ? change : nil;
}

- (NSString *)statusLine
{
  return [NSString stringWithFormat:@"%@ as they were on %@ · %lu removed since, "
                                    @"%lu changed since",
                                    FVItemCount (shownCount), FVLongDate ([self shownDate], @" at "),
                                    (unsigned long)removedCount, (unsigned long)changedCount];
}

- (void)viewerSelectionChanged
{
  if (rewinding)
    [stage setNeedsDisplay:YES];
}

/* ---- restoring ---- */

/* Restore: the selected items, copied back into the folder they came
   from in the home as it is now (made again if it's gone), through File
   Viewer's copy. Rewind ends once they're back. */
- (void)restore:(id)sender
{
  NSArray *parts = [self snapshotPartsOf:[viewer currentPath]];
  NSArray *sources = [viewer selectedPaths];
  if (parts == nil || ![sources count] || restoring)
    return;
  NSString *destination = [home stringByAppendingPathComponent:[parts objectAtIndex:1]];
  [[NSFileManager defaultManager] createDirectoryAtPath:destination
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  ASSIGN (restoreFolder, destination);
  restoring = YES;
  [viewer runOperation:@"restore" paths:sources destination:destination];
  if (![viewer hasOperation])
    restoring = NO;
}

- (void)resolveConflict:(NSMutableDictionary *)request
{
  NSString *source = [request objectForKey:@"source"];
  NSArray *parts = [self snapshotPartsOf:source];
  NSDate *taken = parts ? [self dateOfSnapshot:[parts objectAtIndex:0]] : [NSDate date];
  FVRestorePanel *dialog = AUTORELEASE ([[FVRestorePanel alloc]
      initWithSource:source
         destination:[request objectForKey:@"destination"]
               taken:taken
           remaining:[[request objectForKey:@"remaining"] unsignedIntegerValue]
              viewer:viewer]);
  NSInteger choice = [viewer runDialog:dialog];
  NSArray *choices = [NSArray arrayWithObjects:@"skip", @"replace", @"keep", nil];
  [request setObject:choice >= 0 && choice < 3 ? [choices objectAtIndex:choice] : @"skip"
              forKey:@"choice"];
  [request setObject:[NSNumber numberWithBool:[dialog everyItem]] forKey:@"apply"];
}

/* Back to now, with what came back selected. */
- (void)restoreFinished:(NSDictionary *)result
{
  if (!restoring)
    return;
  restoring = NO;
  NSArray *done = [result objectForKey:@"placed"];
  if (rewinding)
    [self leaveRewindReturning:NO];
  [viewer navigate:restoreFolder];
  if ([done count])
    [viewer selectPaths:done];
  NSUInteger count = [done count];
  if (count)
    {
      [viewer showNote:[NSString stringWithFormat:@"Restored %@.", FVItemCount (count)] busy:NO];
      [viewer performSelector:@selector (clearNote) withObject:nil afterDelay:8];
    }
}

- (void)viewerWillClose
{
  [snapshotTimer invalidate];
  DESTROY (snapshotTimer);
  rewinding = NO;
  [backdrop orderOut:nil];
  [schedule orderOut:nil];
}

@end
