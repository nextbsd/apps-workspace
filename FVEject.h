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

#import <Foundation/Foundation.h>

/*
 * Eject, as the Finder does: DiskArbitration unmounts every volume on the
 * disk and then ejects it, asking diskarbitrationd, which does it for any
 * user. libDiskArbitration is opened when first needed, so Workspace
 * builds and runs where it isn't (an X11 desktop, the cross build's SDK).
 */

/* YES when every path is a mounted volume that can be ejected: a disk
   mounted in /Volumes or /media, never the startup disk. */
BOOL FVCanEjectPaths (NSArray *paths);
/* Ejects the disk the volume at path is on. Says why in an alert when it
   can't, such as an app still using it. */
void FVEjectVolume (NSString *path);
