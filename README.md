# Workspace

Workspace is NextBSD's workspace app, a native GNUstep file manager built with
Foundation and AppKit (formerly FileViewer). Its windows are titled File
Viewer, as on NeXTSTEP. Settings saved by FileViewer (`org.gnustep.FileViewer`)
are copied to Workspace's own domain (`org.nextbsd.Workspace`) the first time it
starts, except the saved main menu position. At launch it sets the global GNUstep workspace application default
(`GSWorkspaceApplication = Workspace`), so `gopen .` opens the directory in
Workspace. On normal quit it removes that default if it still points to
Workspace. Explicit
application choices and file opening continue through NSWorkspace associations.

## Help

Help → Workspace Help opens a help window with `Resources/WorkspaceHelp.rtf`,
which is installed in the app bundle. It covers the views, the Locations list,
copying and moving, Trash and Delete Permanently, Undo, Open With, search, the
Inspector, what the safety checks mean, and the touchpad gestures that work in
File Viewer. Edit the RTF to change it.

## Preferences

Workspace → Preferences has two tabs. **General** holds the file viewer's
settings (thumbnails, hidden files). **Desktop** holds NextBSD's desktop
settings, whose defaults come from the active GNUstep theme
([nextbsd-theme](https://github.com/nextbsd/nextbsd-theme#desktop-defaults)):

- **Window mode:** Stacking (floating windows) or Tiling (WindowServer lays
  the windows out side by side) (`NBWindowMode`: `stacking`, `tiling`; the
  NextBSD theme's default is stacking). Switching sets WindowServer's
  `WindowMode` at once, so the windows tile or go back to their frames, and
  applies the new mode's Dock position and menu style: in the NextBSD theme
  the Dock on the right with NeXT menus while stacking, at the bottom with
  in-window menus while tiling.
- **Minimize windows:** NeXT miniwindows, WindowServer previews or into the
  Dock (`NBMinimizeStyle`: `nextstep`, `previews`, `dock`; the default is
  into the Dock, as live previews in its minimized-windows section). It
  applies to windows minimized from then on.
- **Dock position:** right, left, top or bottom (`NBDockPosition`). Workspace
  also writes the Dock's own `DockPlacement` default.
- **Menu style:** NeXT (floating vertical menus with tear-off), In-window
  (each window carries the menu) or Mac menu bar (one bar along the top for
  the active app) (`NBMenuStyle`: `nextstep`, `inwindow`, `macmenubar`).
  Running apps switch at once: the NextBSD GNUstep backend rebuilds their
  menus when the notification below comes
  ([libs-back#3](https://github.com/nextbsd/libs-back/issues/3)). A Dock on
  the top edge sits below the Mac menu bar.

The Dock position and the menu style are kept for each window mode: a choice
made while tiling is the tiling one, and comes back the next time you tile
([nextbsd-theme#8](https://github.com/nextbsd/nextbsd-theme/issues/8)).

Each menu has "Use theme default", which removes the user's value. The user's
values go in `NSGlobalDomain`: the window mode and minimize style under the
same keys, the Dock position and menu style in `NBModeSettings`, one
dictionary per mode (a plain `NBDockPosition` or `NBMenuStyle` from before
moves into its `stacking` entry). After a change, Workspace posts the
distributed notification `org.nextbsd.DesktopSettingsChanged`, with the `key`
that changed and its effective `value`, once for each setting whose value
changed (switching mode posts `NBWindowMode`, then `NBDockPosition` and
`NBMenuStyle`).

The **Tiling** section, enabled while tiling, has WindowServer's own tiling
settings: the layout (Dwindle, or Master and stack), the gaps between and
around the windows, and a border around the active window (`TilingLayout`,
`TilingGapsInner`, `TilingGapsOuter`, `TilingBorder`). Workspace keeps them,
and `WindowMode`, in the user's `org.nextbsd.WindowServer` defaults (sent at
login) and sends each change to WindowServer at once through the NextBSD
backend. When Workspace starts, it sets `WindowMode` again if the window mode
in effect changed meanwhile (a new theme).

## Gestures and shortcuts

The touchpad gestures and keyboard shortcuts for moving around the desktop, what works today and what's planned, are in [docs/Gestures.md](docs/Gestures.md).

## Credits

Workspace is written and maintained by Joseph Maloney. It is based on
FileViewer by Gregory John Casamento ([gcasa/Finder](https://github.com/gcasa/Finder)).

## Screenshot

<img width="1358" height="1068" alt="Finder" src="https://github.com/user-attachments/assets/5387cd2b-87e4-4f22-8937-ed31e30b71e6" />

## Build and launch

Prerequisites: GNUstep Make, Base and GUI development headers/libraries, an
installed GUI backend, an Objective-C compiler, libmount development headers
(`libmount-dev` on Debian), X11 and Xext development libraries
(`libx11-dev` and `libxext-dev`), and an X display. This version's
filesystem adapter targets NextBSD and Linux (`renameat2` with `RENAME_NOREPLACE`,
the `openat`/`fstatat`/`unlinkat` family with `O_NOFOLLOW`, and POSIX stat
timestamps). Other Unix systems need an equivalent platform adapter; unsupported
atomic rename fails rather than falling back to overwriting rename.

Movie thumbnails use optional `ffmpegthumbnailer` with embedded-artwork preference
(`-m`), falling back to a video frame when artwork is absent. If the thumbnailer
is unavailable or fails, FFmpeg extracts a frame. Image and audio-artwork previews
use FFmpeg. Tools are located in `/usr/bin` or `/usr/local/bin`; unsupported files
retain their normal icons.

From this directory:

```sh
make -j2
./Workspace.app/Workspace
./Workspace.app/Workspace /absolute/path/to/folder
```

If GNUstep is not configured in your shell, source its installed `GNUstep.sh`
first. The GNUmakefile locates Make using `gnustep-config`; no installation or
`sudo` is necessary. The generated application bundle is `Workspace.app`.

Inspected development environment:

- Debian 13.5, Linux 6.12.90, Clang 19.1.7.
- GNUstep Make 2.9.3, Base 1.31.1, GUI 0.32.0, backend 0.32.0 (X11).
- Configured libobjc2 ABI `gnustep-2.2`; runtime source reports version 4.6.
- Manual retain/release and Objective-C 1.0 language style. No blocks, ARC, GCD,
  bindings, or modern collection literal syntax are required by the source.
  The installed `gnustep-config` adds its own runtime and `-fblocks` flags.
- NSBrowser delegates, NSWorkspace opening/icons, NSTableView drag delegates and
  `NSFilenamesPboardType` were checked against installed headers/implementations.
  NSAlert has no accessory-view API here: entry/conflict dialogs use NSPanel.
  The modal helper isolates an opaque-session type-encoding mismatch in this
  libobjc2/GUI combination without changing GNUstep libraries.

## Using Workspace

- Each window has its own directory, selection, navigation history, filter and
  operation. Use File → New Window or Open Folder in New Window.
- Back/Forward, Up, Home, Refresh and the view buttons are in the top navigation
  bar. The path popup contains clickable ancestors. Go to Folder accepts `~`,
  absolute paths and paths relative to the window's folder. Tab completes the
  last folder name (listing the matches when several fit), the field's menu holds
  recent folders and the matches, and a missing folder is reported in the panel.
- The Locations outline has collapsible Local User, Favorites, Domains and
  Volumes groups, with icons and no grid lines. Local User holds Home, existing
  Desktop/Documents/Downloads/Pictures/Music/Videos and the home Trash when it
  exists. Filesystems mounted at `/run` or beneath it are
  excluded by default. Preferences → Exclude filesystems mounted under /run
  remembers your choice and updates all open windows immediately. This applies to
  every Locations section, including Favorites; saved favorites
  are preserved, and you can still browse those paths directly.
  Drop files, folders, or applications onto a folder or drive in Locations to
  copy them into that location, including favorite folders and network volumes.
  Favorites appears once it holds a folder. File → Add to Favorites
  (Command-Control-T) adds the selected folders, or the current folder when
  nothing is selected. Dropping folders onto the Favorites heading or between
  favorites (an insertion line shows where) adds them without copying, and
  dragging a favorite reorders it. A folder is listed once; a favorite whose
  folder is missing is greyed out rather than removed. Click a favorite to
  open it; right-click a favorite and choose Remove from Favorites to remove
  that shortcut. XDG
  `user-dirs.dirs` values using `$HOME` or absolute paths are recognized without
  executing that file. Missing personal directories are never created.
- Network lists mounted remote filesystems using Linux mount information and
  libmount classification, including remote FUSE mounts and mounts marked
  `_netdev`. Entries appear only in Network, respect the `/run` exclusion preference, and
  update automatically as mounts appear or disappear. Click an entry to browse
  it. This lists existing mounts; it does not discover or mount remote servers.
- Recents in Common Locations combines successful file opens in Workspace with
  other applications' shared `recently-used.xbel` history under `XDG_DATA_HOME`
  (normally `~/.local/share`). Files appear newest first, with Last Accessed and
  Full Path columns; duplicate paths, missing files and folders are omitted.
  Workspace's history persists across restarts. Selecting files and generating
  thumbnails do not add history. Apps that do not publish shared history cannot
  be included. Recents supports list/icons, filtering, opening and file actions;
  it is a collection, so it cannot receive pasted files or new folders.
- List view has name/icons, byte size, kind and modification time (the
  Inspector shows the rest). Click headers to sort or reverse sorting. Folders First is optional.
  Arrow keys navigate, typing selects by prefix, Return/double-click opens.
- File backgrounds are a shade darker than the window background in list,
  icon, and column views, following the theme.
- Preferences → Show hidden files and directories reveals dot-prefixed files
  and folders in list, column and icon views. It is off by default, remembers
  your choice, and updates all open windows immediately. The View → Show Hidden
  Files command controls the same setting.
- Hovering over a file in list, column or icon view shows its full filename.
  Preferences → Show full filenames on hover is enabled by default, remembers
  your choice, and updates all open windows immediately. Selecting an icon
  always expands its label to show the full name, with rows below shifted down
  to prevent overlap; this works even when hover tooltips are disabled.
- The bottom-right status indicator shows current activity, such as Loading,
  Searching, Launching application, Waiting for input, file operations and
  thumbnail generation, and is empty when nothing is happening. File counts remain on the left.
- A copy, move, Duplicate, Move to Trash or Delete Permanently still running
  after a moment opens the Processes window, like NeXTSTEP's: one row per
  running operation with what it does ("Copying 3 items to “Documents”"), a
  progress bar driven by bytes and files copied (by items for moves within one
  filesystem, Trash and delete), the item being handled, and a Stop button.
  It closes itself when the last operation finishes. Edit → Cancel Work stops
  the window's operation from the keyboard. Stopping leaves the item in hand as
  it was and keeps the items already finished; it is not reported as a failure.
- Image and movie thumbnails are enabled by default in icon, list and column
  views. Audio files with embedded artwork can also show a preview. Preferences
  → Show thumbnails applies immediately to all open windows and remembers your
  choice. Previews are generated in the background, preserve their proportions,
  and refresh when files change. Unsupported formats, unavailable codecs and
  damaged media keep their ordinary icons.
- Application bundles launch directly. Files use GNUstep's registered type
  associations. When none is saved, or with File → Open With…, the Open With
  chooser lists applications by name with their icons: those that declare the
  file's type (and any saved choice) under Recommended, then every other
  application in the Applications folders. Other… picks a bundle that isn't
  listed. “Always open .txt files with this application” saves the choice for
  that extension and skips the chooser on future opens; the chooser shows the
  saved choice with a Reset button that forgets it. Files without extensions
  cannot save a default.
  Workspace contacts or launches the chosen application directly, without
  delegating file opening to GWorkspace. Open With also uses this direct path.
  Communication with the selected application runs in the background so a slow
  viewer does not block Workspace. Opening progress and failures appear in the
  status bar.
- Columns use the current directory as their root. Single-clicking a folder
  expands a column without adding history; double-clicking it navigates the
  window and adds history. Files are selected, not previewed; double-click opens
  them. The Inspector (Get Info) is the explicit metadata view. Child columns load off-thread.
- All file views support multiple selection: Control-click or Command-click
  toggles individual items, Shift-click extends a range, and Edit → Select All
  selects every item. Icons also support Shift-arrow range selection, keyboard
  navigation, double-click, and View → Larger/Smaller Icons. All views use the
  same operations and directory items; selections persist between list/icons.
- The search field in the toolbar finds items by name. With This Folder chosen
  beside it, it filters the current folder; with Subfolders it searches beneath
  the folder and shows the results in the list with a Location column (the
  window returns to icons or columns afterwards). View → Search (Command-F)
  puts the cursor in the field; Escape, clearing the field or opening another
  folder returns to the folder. Search reports permission failures, delivers
  incremental batches, never searches contents and never recurses through
  symbolic links.
- Open folders update automatically through one-second background polling,
  including expanded browser columns. Added, removed, renamed and modified files
  refresh the view, preserving selection and list/icon scroll position where
  possible. Search results beneath a folder require Refresh.
- Favorites, hidden-file preference, folders-first preference, last directory,
  view mode and window frame use application-local NSUserDefaults. Key equivalents
  use GNUstep's native modifier mapping (often Alt on Unix), not a hard-coded
  Command/Control substitution. Labels and non-editable text fields are borderless.

File → Open uses NSWorkspace associations. Recognized application bundles launch
as packages; Show Package Contents enters them. Open With offers the application
chooser described above.

File → Get Info opens the Inspector, one window like NeXTSTEP's that follows
the selection of the active File Viewer. It shows the item's icon, its name
(type a new one and press Return to rename), kind, size (a folder's total and
item count are counted in the background), location, created and modified
dates, and a symbolic link's target. Owner, group and Read/Write/Execute
checkboxes for owner, group and others apply with Apply (Revert discards).
Only root can change the owner; an item's owner can change its permissions and
pick among their own groups; everyone else sees them disabled, with a note
saying why. A link's own permissions are not offered. Several selected items
get one summary: their count, folders and files, total size and common
location. Linux birth time comes from `statx` when available; GNUstep's
inferred creation-date fallback is not presented as fact.

## Operations and safety semantics

All UI mutation paths converge on `FVOperations`. They never build shell commands.
Only one operation runs per window; other windows remain independent.

- Copy/Paste and all drags **copy**. A directory drop targets that directory;
  dropping on empty space targets the displayed directory. The pasteboard uses
  the installed GNUstep file-list type `NSFilenamesPboardType`.
- Cut does not remove anything initially. Paste moves. Successful entries are
  removed from the cut list only if the clipboard has not since changed; failed
  entries remain available. Move To… picks the destination in a folder chooser
  that starts in the folder holding the selection.
- Rename edits the name in place in the list, column and icon views; Return on a
  single selected item and a slow second click on its name start it too. The name
  is selected without its extension; Return renames and Escape cancels. New Folder creates "New Folder" (or "New Folder 2"…)
  at once in the folder the view shows (in columns, the selected folder), selects it
  and edits its name in place: Return keeps the typed name, Escape keeps the default.
  Empty, `.`/`..`, slash and NUL names and names already taken are refused in
  place, with the reason in the status bar. Duplicate chooses a new sibling name the way Finder does: "notes copy.txt",
  then "notes copy 2.txt". Pasting or dropping a copy into the item's own folder
  does the same; pasting a cut item back into its own folder does nothing.
- When a copy or move meets an item of the same name, a conflict panel shows
  both items side by side (icon, name, kind, size or folder item count, and
  modified date, with the newer one marked) and offers Keep Both (the default),
  Skip, Replace and Stop, plus "Apply to all" when more items follow.
  Replace moves the existing destination aside to a uniquely named
  `Workspace replaced item-…` sibling and reports its path. It does **not** merge
  directories or silently erase the previous destination. Remove the retained
  backup yourself after checking the result.
- Publication and same-filesystem moves use atomic **no-replace** rename. A race
  creating the destination causes an error. Same-file/hard-link aliases and
  directory-into-descendant destinations (including symlink aliases) are rejected.
- Copies use exclusive output creation inside a private staging directory,
  bounded I/O buffers, cancellation checks, regular-file `fsync`, permission and
  timestamp restoration, and before/after source metadata checks. Symbolic links
  remain links; special devices, sockets and FIFOs are refused. Directory reads
  pin open descriptors: each entry is opened, checked and removed relative to its
  already-open parent with the `*at` calls, so a folder renamed or replaced
  mid-copy cannot redirect the walk, and source symlinks are never traversed. Unrepresentable names
  are reported rather than silently omitted.
- On `EXDEV`, the move copies first. It then atomically detaches the source into
  a private recovery directory, verifies the copied tree's source identity and
  metadata again, publishes the destination, and verifies entries during source
  removal. Failure before publication attempts to restore the source path.
  Failure/cancellation during removal reports the complete destination and the
  precise recovery directory containing remaining source data.
- Recursive work is **not transactional** and is not a filesystem snapshot.
  Concurrent writers, including processes holding already-open descriptors, can
  still change data between checks. Avoid moving actively written trees. A
  finished operation shows nothing when every item succeeded; otherwise one alert
  names each failed item with its reason, followed by any note you must act on
  (a retained replaced item, a recovery or leftover staging folder).
  There is no crash-recovery journal and no claim of power-loss durability for
  directory-entry updates. Private staging/recovery directories left after a
  process crash must be inspected manually.
- Copies preserve ordinary rwx permissions and file/directory timestamps. They
  do not preserve ownership, ACLs, extended attributes, security labels, sparse
  allocation, hard-link relationships, or setuid/setgid bits. Symlink timestamps
  are not restored. Hard links that change ctime during cross-filesystem source
  cleanup may cause conservative recovery rather than complete removal.
- Undo Last Safe Operation reverses unchanged same-filesystem regular-file/link
  moves/renames and empty New Folder creation. It validates identity, size and
  timestamps and refuses occupied original paths. It does not undo copies,
  directory moves, replacement, Trash, cross-filesystem moves, or deletion.
  There is no redo or persistent undo history.

Trash implements the freedesktop **home Trash** layout:
`$XDG_DATA_HOME/Trash` (default `~/.local/share/Trash`). It validates private,
owned, non-symlink directories, creates an exclusive `.trashinfo` file with
URL-escaped original filesystem bytes and local deletion time, then renames the
item without replacement. Other filesystems are explicitly refused; there is
no fallback to permanent deletion. Per-volume `.Trash`/`.Trash-uid`, Trash restore
UI and Empty Trash are not implemented. The sidebar shows the raw `files`
directory; original names/locations are in the matching `info/*.trashinfo` files.
Permanent deletion is a separate, explicitly confirmed action. Cancellation of
permanent deletion is between top-level items, not inside NSFileManager removal.

## Architecture

| Source | Responsibility |
| --- | --- |
| `FVApplication` | Menus, startup path delivery, window ownership, application icon |
| `FVWindow` | Window/controller, navigation, sidebar/preferences, adapters, dialogs, info/results panels, polling adapter |
| `FVModel` | File items and cancellable batched background listings/search |
| `FVOperations` | Operation scheduling, progress, conflicts/results, POSIX copying/moving, guarded undo, home Trash |
| `FVInspector` | The Inspector (Get Info): metadata, rename, owner, group and permissions |
| `FVPanels` | The Processes (progress) window, the conflict panel, the Open With chooser, the shared modal panel helpers and size formatting |
| `FVIconView` | Native icon layout, selection, keyboard navigation and drag/drop |
| `FVLauncher` | File-type associations, the installed application list, and direct application activation/launch |
| `main.m` | MRC application lifecycle |
| `Resources/Workspace.png` | The NextBSD cube, from nextbsd-theme's logo without its black square (see `Resources/ICON.txt`) |

Workers own autorelease pools. AppKit callbacks run on the main thread and use
listing generations to discard stale results. Closing a window cancels work;
workers retain their callback target until completion. Icons are loaded lazily
on the main thread with a bounded cache. No listing computes recursive sizes.
The NSBrowser matrix adapter supplies drag initiation missing from the inspected
GNUstep implementation; native matrix selection remains in use for clicks.

## Verification

```sh
./Tests/run.sh
./Tests/gui.sh
sh Tests/locations.sh
sh Tests/launch.sh
sh Tests/thumbnails.sh
sh Tests/recents.sh
sh Tests/filenames.sh
sh Tests/appearance.sh
```

`Tests/run.sh` builds Foundation-only tests and creates all destructive fixtures
in temporary directories. It redirects XDG data for Trash tests. `Tests/gui.sh`
builds the AppKit smoke test and launches it under Xvfb; it needs `xvfb-run` and
`xauth`. In restricted execution environments, compile and launch the test as
separate commands if the wrapper cannot connect to its X server:

```sh
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. \
  Tests/GUISmoke.m FVWindow.m FVApplication.m FVModel.m FVOperations.m FVIconView.m FVLauncher.m FVThumbnails.m \
  -o obj/tests/gui $(gnustep-config --gui-libs) -lmount
xvfb-run -a ./obj/tests/gui
```

See `Tests/MANUAL.md` for the interactive checklist and `VERIFICATION.md` for
observed results and unverified areas. Source builds without application warnings.
Xvfb without a window manager emits harmless `_NET_WORKAREA` diagnostics. The
managed development sandbox may also report that the real user's Defaults lock
directory is not writable; normal desktop execution can persist preferences.
The thumbnail tests require FFmpeg and ffmpegthumbnailer and exercise embedded
movie artwork, frame fallback, damaged media, live invalidation, and Preferences.
Recents tests use isolated shared history to check persistence, merging, ordering,
filtering, navigation and file-action restrictions.

## Remaining limitations

- Filesystem adapter tested on NextBSD and Linux only; other Unix systems are not tested.
- No content search, live preview pane, directory merging or per-volume Trash.
- Polling instead of inotify; large or remote directories can take longer to
  update. Selection of descendants is not translated into a different view's root list.
- Long-running OS calls cannot always be interrupted immediately. Final sorting
  is on the UI thread; enormous directories/search result sets can still pause
  while sorting and consume memory proportional to the number of results.
- The fixed minimum window size is 760×400. Theme fonts are used, but very large
  accessibility fonts and mixed-DPI displays have not been exhaustively tested.
- Real removable-volume disconnects, disk-full faults, real cross-device mounts,
  external-app drag sessions and launching arbitrary associated applications
  require the manual checks; do not infer these passed from compilation.

## References and licensing

Reviewed [GNUstep documentation](https://www.gnustep.org/resources/documentation/),
[NSFileManager](https://www.gnustep.org/resources/documentation/Developer/Base/Reference/NSFileManager.html),
[NSWorkspace](https://www.gnustep.org/resources/documentation/Developer/Gui/Reference/NSWorkspace.html),
[GWorkspace](https://github.com/gnustep/apps-gworkspace), and the
[freedesktop Trash specification](https://specifications.freedesktop.org/trash/1.0/).
GWorkspace's GPL license was inspected before studying its pasteboard integration;
no GWorkspace source or artwork was copied. No Apple artwork is used. New source
is under `LICENSE`. The icon was generated with the built-in image generator;
its complete prompt and provenance are in `Resources/ICON.txt`.
