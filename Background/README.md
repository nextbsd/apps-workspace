# WorkspaceBackground

Workspace's desktop background: InnerSpace's host (its controller and saver
window, from apps-innerspace), without the InnerSpace application. It is a
tool, built with Workspace and kept in `Workspace.app/Resources`, and
Workspace starts it at login (`FVBackground`), as macOS's WallpaperAgent
draws under the Finder's desktop. It isn't an app: no bundle, no icon, it
never becomes the active app, and it stops when Workspace does. Its windows
let the pointer through to Workspace's clear desktop windows above
(`FVDesktop`), so clicking the desktop brings Workspace forward.

- **Modules** are apps-innerspace's `.InnerSpace` bundles, installed in a
  Library's `InnerSpace` folder; the user's Library comes first.
- **Settings** are its `WorkspaceBackground` defaults (`currentModule`,
  `runSpeed`, `moduleOnEveryDisplay`); the first time it takes InnerSpace's.
  Workspace Preferences > Background writes them and posts
  `WorkspaceBackgroundSettingsDidChange`; the background applies them at
  once.
- **Options**: `WorkspaceBackgroundShowOptions` shows the module's inspector
  in a small window.
- **Crashes**: a module that crashes takes only the background down.
  Workspace starts it again; after three stops in a minute it switches to
  Black.

## Tests

From this folder, with gnustep-make configured. The first two need no
display; the rotation test needs the session's display server, OpenGL and
the installed modules (a Library's `InnerSpace` folder).

```sh
F="InnerSpaceController.m SaverWindow.m UtilFunctions.c $(pkg-config --cflags --libs x11)"
clang $(gnustep-config --objc-flags) Tests/DirectRenderingTests.m $F -o /tmp/background-direct-tests $(gnustep-config --gui-libs)
clang $(gnustep-config --objc-flags) Tests/StandardResolutionTests.m $F -o /tmp/background-scale-tests $(gnustep-config --gui-libs)
clang $(gnustep-config --objc-flags) Tests/ModuleRotationTests.m $F -o /tmp/background-rotation-tests $(gnustep-config --gui-libs)
/tmp/background-direct-tests
/tmp/background-scale-tests
/tmp/background-rotation-tests ~/Library/InnerSpace 3
```
