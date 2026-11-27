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

/*
 * With the Mac menu bar the Dock is never at the top: Desktop
 * preferences leaves Top out of the Dock position, shows a saved top as
 * the bottom and tells the Dock "bottom", and keeps the saved top for
 * the NeXT and in-window styles. Every menu style and saved position,
 * and changes between them; windows always stack, and a tiling mode
 * saved before Preferences dropped it goes back to stacking at login.
 * Isolated defaults; nothing is posted to the running session.
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "FVDesktopSettings.h"

@interface NSUserDefaults (IsolatedTestDatabase)
- (id)initWithContentsOfFile:(NSString *)path;
- (void)setSearchList:(NSArray *)list;
@end

@interface FVDesktopSettings (NoTopTesting)
- (void)choose:(id)sender;
@end

/* A pop-up without a backend (NSPopUpButton needs fonts, so a display):
   just what FVDesktopSettings asks of one. */
@interface FakePopUp : NSObject
{
  NSMutableArray *items;
  NSInteger selected;
  NSInteger tag;
  NSString *toolTip;
}
@end

@implementation FakePopUp
- (id)initWithTag:(NSInteger)t
{
  self = [super init];
  items = [NSMutableArray new];
  tag = t;
  selected = -1;
  return self;
}
- (NSInteger)tag { return tag; }
- (void)removeAllItems { [items removeAllObjects]; selected = -1; }
- (void)addItemWithTitle:(NSString *)title
{
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
  [items addObject:item];
  [item release];
}
- (id)lastItem { return [items lastObject]; }
- (NSInteger)numberOfItems { return (NSInteger)[items count]; }
- (id)itemAtIndex:(NSInteger)i { return [items objectAtIndex:(NSUInteger)i]; }
- (NSInteger)indexOfItemWithRepresentedObject:(id)object
{
  NSUInteger i;
  for (i = 0; i < [items count]; i++)
    {
      id r = [[items objectAtIndex:i] representedObject];
      if (r == object || [r isEqual:object])
        return (NSInteger)i;
    }
  return -1;
}
- (void)selectItemAtIndex:(NSInteger)i { selected = i; }
- (id)selectedItem { return selected < 0 ? nil : [items objectAtIndex:(NSUInteger)selected]; }
- (void)setToolTip:(NSString *)t { ASSIGN (toolTip, t); }
- (NSString *)toolTip { return toolTip; }
- (void)setEnabled:(BOOL)flag {}
@end

static NSUserDefaults *testDefaults;
static NSMutableArray *posts;
static int failures;
static unsigned checks;

#define CHECK(cond, ...)                                                        \
  do                                                                           \
    {                                                                          \
      checks++;                                                                \
      if (!(cond))                                                             \
        {                                                                      \
          failures++;                                                          \
          NSLog (@"FAIL: %@", [NSString stringWithFormat:__VA_ARGS__]);        \
        }                                                                      \
    }                                                                          \
  while (0)

static id
isolatedDefaults (id receiver, SEL selector)
{
  return testDefaults;
}

static void
recordPost (id receiver, SEL selector, NSString *name, id object, NSDictionary *info,
            BOOL immediately)
{
  [posts addObject:info ? info : [NSDictionary dictionary]];
}

/* NBWindowMode, and each mode's menu style and Dock position. */
static void
save (NSString *mode, NSString *stackingMenu, NSString *stackingDock, NSString *tilingMenu,
      NSString *tilingDock)
{
  NSDictionary *modes = [NSDictionary dictionaryWithObjectsAndKeys:
      [NSDictionary dictionaryWithObjectsAndKeys:stackingMenu, @"NBMenuStyle", stackingDock,
                                                 @"NBDockPosition", nil],
      @"stacking",
      [NSDictionary dictionaryWithObjectsAndKeys:tilingMenu, @"NBMenuStyle", tilingDock,
                                                 @"NBDockPosition", nil],
      @"tiling", nil];
  [testDefaults setPersistentDomain:[NSDictionary dictionaryWithObjectsAndKeys:mode,
                                        @"NBWindowMode", modes, @"NBModeSettings", nil]
                            forName:NSGlobalDomain];
}

static NSString *
saved (NSString *mode, NSString *key)
{
  return [[[[testDefaults persistentDomainForName:NSGlobalDomain]
      objectForKey:@"NBModeSettings"] objectForKey:mode] objectForKey:key];
}

static NSString *
expected (NSString *position, NSString *menu)
{
  return [position isEqual:@"top"] && [menu isEqual:@"macmenubar"] ? @"bottom" : position;
}

static NSArray *
values (id popUp)
{
  NSMutableArray *a = [NSMutableArray array];
  NSInteger i;
  for (i = 0; i < [popUp numberOfItems]; i++)
    {
      id v = [[popUp itemAtIndex:i] representedObject];
      [a addObject:v ? v : @"theme"];
    }
  return a;
}

static NSString *
lastPosted (NSString *key)
{
  NSEnumerator *e = [posts reverseObjectEnumerator];
  NSDictionary *info;
  while ((info = [e nextObject]) != nil)
    if ([[info objectForKey:@"key"] isEqual:key])
      return [info objectForKey:@"value"];
  return nil;
}

/* Choose `value` (nil: the theme's) in a pop-up, as a click would. */
static void
choose (FVDesktopSettings *settings, id popUp, NSString *value)
{
  NSInteger i = [popUp indexOfItemWithRepresentedObject:value];
  if (value == nil)
    i = 0;
  [popUp selectItemAtIndex:i];
  [settings choose:popUp];
}

int
main (void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *root = [NSTemporaryDirectory ()
      stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSArray *styles = [NSArray arrayWithObjects:@"nextstep", @"inwindow", @"macmenubar", nil];
  /* Only stacking is in effect now; the saved tiling entry must stay
     untouched beside it. */
  NSArray *modes = [NSArray arrayWithObjects:@"stacking", nil];
  NSArray *positions = [NSArray arrayWithObjects:@"left", @"bottom", @"right", @"top", nil];
  NSEnumerator *se, *me, *pe;
  NSString *s, *m, *p;

  [[NSFileManager defaultManager] createDirectoryAtPath:root
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  testDefaults = [[NSUserDefaults alloc]
      initWithContentsOfFile:[root stringByAppendingPathComponent:@"defaults"]];
  [testDefaults setSearchList:[NSArray arrayWithObjects:NSGlobalDomain, NSRegistrationDomain,
                                                        nil]];
  method_setImplementation (
      class_getClassMethod ([NSUserDefaults class], @selector (standardUserDefaults)),
      (IMP)isolatedDefaults);
  posts = [NSMutableArray new];
  method_setImplementation (
      class_getInstanceMethod ([NSDistributedNotificationCenter class],
                               @selector (postNotificationName:object:userInfo:deliverImmediately:)),
      (IMP)(void *)recordPost);

  /* The effective position, for every combination. */
  se = [styles objectEnumerator];
  while ((s = [se nextObject]) != nil)
    {
      me = [modes objectEnumerator];
      while ((m = [me nextObject]) != nil)
        {
          pe = [positions objectEnumerator];
          while ((p = [pe nextObject]) != nil)
            {
              NSString *other = [p isEqual:@"top"] ? @"left" : @"top";
              if ([m isEqual:@"stacking"])
                save (m, s, p, @"nextstep", other);
              else
                save (m, @"nextstep", other, s, p);
              CHECK ([[FVDesktopSettings effectiveValueForKey:@"NBDockPosition"]
                         isEqual:expected (p, s)],
                     @"%@ %@ %@: effective %@", s, m, p,
                     [FVDesktopSettings effectiveValueForKey:@"NBDockPosition"]);
            }
        }
    }

  /* The pop-ups and the changes, without a display: the Desktop tab's
     pop-ups as FakePopUps (tags as FVDesktopSettings.m's). */
  FVDesktopSettings *settings = [[FVDesktopSettings alloc] init];
  FakePopUp *dockPopUp = [[FakePopUp alloc] initWithTag:2];
  FakePopUp *menuPopUp = [[FakePopUp alloc] initWithTag:3];
  object_setIvar (settings, class_getInstanceVariable ([FVDesktopSettings class], "dockPopUp"), dockPopUp);
  object_setIvar (settings, class_getInstanceVariable ([FVDesktopSettings class], "menuPopUp"), menuPopUp);

  se = [styles objectEnumerator];
  while ((s = [se nextObject]) != nil)
    {
      me = [modes objectEnumerator];
      while ((m = [me nextObject]) != nil)
        {
          pe = [positions objectEnumerator];
          while ((p = [pe nextObject]) != nil)
            {
              BOOL mac = [s isEqual:@"macmenubar"];
              NSString *other = [p isEqual:@"top"] ? @"left" : @"top";
              if ([m isEqual:@"stacking"])
                save (m, s, p, @"nextstep", other);
              else
                save (m, @"nextstep", other, s, p);
              [settings refresh];
              CHECK ([values (dockPopUp) containsObject:@"top"] == !mac,
                     @"%@ %@ %@: items %@", s, m, p, values (dockPopUp));
              CHECK ([[[dockPopUp selectedItem] representedObject] isEqual:expected (p, s)],
                     @"%@ %@ %@: shows %@", s, m, p,
                     [[dockPopUp selectedItem] representedObject]);
              CHECK (mac == ([dockPopUp toolTip] != nil), @"%@ %@ %@: tooltip %@", s, m, p,
                     [dockPopUp toolTip]);
            }
        }
    }

  /* Menu style changes in each mode: the Dock is told the effective
     position, the saved one stays. */
  me = [modes objectEnumerator];
  while ((m = [me nextObject]) != nil)
    {
      NSString *otherMode = [m isEqual:@"stacking"] ? @"tiling" : @"stacking";
      pe = [positions objectEnumerator];
      while ((p = [pe nextObject]) != nil)
        {
          NSEnumerator *fe = [styles objectEnumerator];
          NSString *from;
          while ((from = [fe nextObject]) != nil)
            {
              NSEnumerator *te = [styles objectEnumerator];
              NSString *to;
              while ((to = [te nextObject]) != nil)
                {
                  if ([from isEqual:to])
                    continue;
                  if ([m isEqual:@"stacking"])
                    save (m, from, p, @"nextstep", @"top");
                  else
                    save (m, @"nextstep", @"top", from, p);
                  [settings refresh];
                  [posts removeAllObjects];
                  choose (settings, menuPopUp, to);
                  CHECK ([saved (m, @"NBMenuStyle") isEqual:to], @"menu %@ saved", to);
                  CHECK ([saved (m, @"NBDockPosition") isEqual:p] &&
                             [saved (otherMode, @"NBDockPosition") isEqual:@"top"],
                         @"%@ %@ %@->%@: saved %@", m, p, from, to,
                         saved (m, @"NBDockPosition"));
                  if (![expected (p, from) isEqual:expected (p, to)])
                    CHECK ([lastPosted (@"NBDockPosition") isEqual:expected (p, to)],
                           @"%@ %@ %@->%@: posted %@", m, p, from, to,
                           lastPosted (@"NBDockPosition"));
                  CHECK ([[[dockPopUp selectedItem] representedObject]
                             isEqual:expected (p, to)] &&
                             [values (dockPopUp) containsObject:@"top"] ==
                                 ![to isEqual:@"macmenubar"],
                         @"%@ %@ %@->%@: pop-up %@ %@", m, p, from, to,
                         [[dockPopUp selectedItem] representedObject], values (dockPopUp));
                  /* The Dock's DockPlacement (X11's) keeps the saved one:
                     a menu style change doesn't touch it. */
                  CHECK ([testDefaults persistentDomainForName:@"Dock"] == nil,
                         @"%@ %@ %@->%@: DockPlacement written", m, p, from, to);
                }
            }
        }
    }

  /* A tiling mode saved before Preferences dropped it: the stacking
     settings are the ones in effect, and login puts NBWindowMode back to
     stacking (for the Dock and the theme), leaving the tiling entry. */
  save (@"tiling", @"macmenubar", @"left", @"inwindow", @"top");
  CHECK ([[FVDesktopSettings windowMode] isEqual:@"stacking"],
         @"saved tiling: window mode %@", [FVDesktopSettings windowMode]);
  CHECK ([[FVDesktopSettings effectiveValueForKey:@"NBMenuStyle"] isEqual:@"macmenubar"] &&
             [[FVDesktopSettings effectiveValueForKey:@"NBDockPosition"] isEqual:@"left"],
         @"saved tiling: effective %@ %@ not stacking's",
         [FVDesktopSettings effectiveValueForKey:@"NBMenuStyle"],
         [FVDesktopSettings effectiveValueForKey:@"NBDockPosition"]);
  [posts removeAllObjects];
  [FVDesktopSettings syncWindowServer];
  CHECK ([[[testDefaults persistentDomainForName:NSGlobalDomain] objectForKey:@"NBWindowMode"]
             isEqual:@"stacking"],
         @"login: NBWindowMode %@",
         [[testDefaults persistentDomainForName:NSGlobalDomain] objectForKey:@"NBWindowMode"]);
  CHECK ([lastPosted (@"NBWindowMode") isEqual:@"stacking"], @"login: posted %@",
         lastPosted (@"NBWindowMode"));
  CHECK ([saved (@"tiling", @"NBMenuStyle") isEqual:@"inwindow"],
         @"login: tiling entry changed");

  /* Choosing a position with the Mac menu bar saves it for the mode. */
  pe = [positions objectEnumerator];
  while ((p = [pe nextObject]) != nil)
    {
      if ([p isEqual:@"top"])
        continue;
      save (@"stacking", @"macmenubar", @"top", @"nextstep", @"top");
      [settings refresh];
      [posts removeAllObjects];
      choose (settings, dockPopUp, p);
      CHECK ([saved (@"stacking", @"NBDockPosition") isEqual:p] &&
                 [saved (@"tiling", @"NBDockPosition") isEqual:@"top"],
             @"choose %@ with the Mac menu bar: saved %@", p,
             saved (@"stacking", @"NBDockPosition"));
      CHECK ([lastPosted (@"NBDockPosition") isEqual:p], @"choose %@: posted %@", p,
             lastPosted (@"NBDockPosition"));
    }

  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
  if (failures)
    {
      NSLog (@"No-top Dock: %d of %u checks failed", failures, checks);
      return 1;
    }
  NSLog (@"No-top Dock: all %u checks passed", checks);
  [pool release];
  return 0;
}
