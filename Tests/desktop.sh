#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make -s
mkdir -p obj/tests
fixture=$(mktemp -d /tmp/fileviewer-desktop-XXXXXX)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
# A Bud1 allocator with an internal DSDB node, two leaves, and an unreachable
# stale Iloc record. No Python packages are needed by the app or this fixture.
python3 - "$fixture" <<'PY'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
b = bytearray(20484)
def put(offset, data): b[offset:offset + len(data)] = data
def ints(*values): return struct.pack('>' + 'I' * len(values), *values)
def record(name, x, y):
    encoded = name.encode('utf-16be')
    return ints(len(encoded)//2) + encoded + b'Ilocblob' + ints(16, x, y, 0xffffffff, 0xffff0000)
put(0, ints(1) + b'Bud1' + ints(2048, 2048, 2048))
put(2052, ints(6, 0, 2048|11, 32|5, 4096|12, 8192|12, 12288|12, 16384|12))
put(2052 + 1032, ints(1) + bytes([4]) + b'DSDB' + ints(1))
put(36, ints(2, 1, 3, 3, 4096))
put(4100, ints(4, 1, 3) + record('middle.txt', 240, 120))
put(8196, ints(0, 1) + record('alpha.txt', 120, 120))
put(12292, ints(0, 1) + record('résumé.txt', 360, 120))
put(16388, ints(0, 1) + record('deleted.txt', 999, 999))
(root / '.DS_Store').write_bytes(b)
for name in ('alpha.txt', 'middle.txt', 'résumé.txt', 'new.txt', '.hidden'):
    (root / name).write_text('fixture')
(root / 'Folder').mkdir()
# Bad tree: root refers back to itself.
bad = bytearray(b)
bad[4108:4112] = ints(2)
(root / 'cycle').write_bytes(bad)
PY
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. \
  Tests/DesktopSmoke.m FVDesktop.m FVDesktopLayout.m FVModel.m FVApplication.m \
  FVWindow.m FVOperations.m FVIconView.m FVLauncher.m FVThumbnails.m \
  -o obj/tests/desktop $(gnustep-config --gui-libs) -lX11 -lXext -lmount
if [ "${1:-}" = "--with-wm" ]; then
  command -v wmaker >/dev/null
  FV_DESKTOP_FIXTURE="$fixture" FV_DESKTOP_TEST_WM=1 xvfb-run -a timeout -k 2 45 sh -c '
    wmaker --no-dock --no-clip --no-autolaunch --dont-restore --static &
    wm_pid=$!
    trap "kill $wm_pid 2>/dev/null || true" EXIT
    sleep 1
    ./obj/tests/desktop
  '
else
  FV_DESKTOP_FIXTURE="$fixture" xvfb-run -a timeout -k 2 45 ./obj/tests/desktop
fi
