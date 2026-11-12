#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p obj/tests
clang $(gnustep-config --objc-flags) -Wall -Wextra -Wno-unused-parameter -I. \
  Tests/ThumbnailsSmoke.m FVWindow.m FVApplication.m FVModel.m FVOperations.m \
  FVIconView.m FVLauncher.m FVThumbnails.m FVPanels.m \
  -o obj/tests/thumbnails $(gnustep-config --gui-libs) -lmount -lX11 -lXext
xvfb-run -a timeout -k 2 45 ./obj/tests/thumbnails
