/*
 * What Workspace and its desktop background (the WorkspaceBackground
 * tool, in Workspace.app's Resources) share. Workspace starts the
 * background and restarts it if it stops; the Background tab of
 * Workspace Preferences writes its settings and tells it to apply them.
 */

#import <Foundation/Foundation.h>

/* The background's defaults domain (its process name): currentModule,
   runSpeed (seconds between frames), moduleOnEveryDisplay. */
#define WorkspaceBackgroundDomain @"WorkspaceBackground"

/* Distributed notifications, object nil. */
#define WorkspaceBackgroundSettingsDidChangeNotification \
  @"WorkspaceBackgroundSettingsDidChange"
#define WorkspaceBackgroundShowOptionsNotification \
  @"WorkspaceBackgroundShowOptions"

/* Where modules (*.InnerSpace bundles) are installed: each Library's
   InnerSpace folder, the user's first. */
static inline NSArray *
WorkspaceBackgroundModuleDirectories(void)
{
  NSArray *libraries = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
    NSAllDomainsMask, YES);
  NSMutableArray *directories = [NSMutableArray array];
  NSEnumerator *e = [libraries objectEnumerator];
  NSString *library;

  while ((library = [e nextObject]) != nil)
    {
      [directories addObject:
	[library stringByAppendingPathComponent: @"InnerSpace"]];
    }
  return directories;
}
