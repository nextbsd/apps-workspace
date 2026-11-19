#!/bin/sh
# The Dock position with the Mac menu bar; see Tests/NoTopDockSmoke.m.
# Needs no display: -GSBackend names none, so nothing can connect.
set -eu
cd "$(dirname "$0")/.."
mkdir -p obj/tests
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. \
  Tests/NoTopDockSmoke.m FVDesktopSettings.m -o obj/tests/no-top-dock \
  $(gnustep-config --gui-libs)
timeout -k 2 60 ./obj/tests/no-top-dock -GSBackend libgnustep-none
