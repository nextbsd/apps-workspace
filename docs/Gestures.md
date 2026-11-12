# Touchpad gestures and shortcuts

How you move around the NextBSD desktop with a touchpad and the keyboard. WindowServer reads the touchpad (through libinput), so these work in every app. **Today** means it works now; the rest is planned, with its ticket.

Settings live in `org.nextbsd.WindowServer` (see WindowServer's README) and will move into Workspace Preferences ([#21](https://github.com/nextbsd/apps-workspace/issues/21)).

## Pointing and clicking

| Gesture | Does | Status |
|---|---|---|
| One-finger tap | Click | **Today** (`TapToClick`, on by default) |
| Two-finger click or tap | Secondary (right) click | Planned: [apps-windowserver#16](https://github.com/nextbsd/apps-windowserver/issues/16) |
| Tap, then drag | Drag | Planned: #16 |
| Three-finger drag | Drag without holding a click (off by default) | Planned: #16 |

## Scrolling and zooming

| Gesture | Does | Status |
|---|---|---|
| Two-finger scroll | Scroll | **Today** (`NaturalScrolling` setting, off by default) |
| Momentum after lifting | Scroll keeps going and slows down | Planned: [#16](https://github.com/nextbsd/apps-windowserver/issues/16) |
| Pinch with two fingers | Zoom in or out | Planned: [#17](https://github.com/nextbsd/apps-windowserver/issues/17); in File Viewer, icon size ([apps-workspace#20](https://github.com/nextbsd/apps-workspace/issues/20)) |
| Rotate two fingers | Rotate | Planned: #17 |
| Double-tap with two fingers | Smart zoom | Planned: #17 |
| Swipe left or right with two fingers | Back or forward | Planned: #17; in File Viewer ([apps-workspace#20](https://github.com/nextbsd/apps-workspace/issues/20)) |

## Workspaces and windows

| Gesture | Keyboard | Does | Status |
|---|---|---|---|
| Swipe left or right with three fingers | Control+Left / Control+Right | Turn the desktop cube to the next or previous workspace | Planned: [#13](https://github.com/nextbsd/apps-windowserver/issues/13) |
| Swipe up with three fingers | Tap Start, Control+Up, or the Mission Control key (F3 on Apple keyboards) | Show every window (Exposé / Mission Control) | Planned: [#14](https://github.com/nextbsd/apps-windowserver/issues/14) |
| Swipe down with three fingers | Control+Down | Show only the current app's windows (App Exposé) | Planned: #14 |
| Spread thumb and three fingers | F11 / Command+F3 | Show the desktop | Planned: [#18](https://github.com/nextbsd/apps-windowserver/issues/18) |
| Pinch thumb and three fingers | | Open Applications in Workspace | Planned: #18 |
| Double-click a minimized window's tile | | Restore the window | Planned: [#12](https://github.com/nextbsd/apps-windowserver/issues/12) |

## Tiling mode

When tiling is on ([apps-windowserver#20](https://github.com/nextbsd/apps-windowserver/issues/20)), windows are laid out automatically, and the keyboard moves between them: Command+Option+arrows move focus, with shortcuts to swap windows, resize splits and float a window. These are configurable.

## Notes

- **Start key:** on PC keyboards the Start (Windows) key is also the Command key. Tapping it on its own opens the window overview; holding it with another key is a Command shortcut as usual.
- **No console switching:** there are no Control+Alt+F*n* console switches. WindowServer keeps the screen while it runs.
- **Where to try it:** a touchpad is needed for the gestures. A virtual machine usually has none, so test on hardware such as the ThinkPad T460s.
