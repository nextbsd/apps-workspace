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

#import "FVEject.h"
#import "FVWindow.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The few DiskArbitration, CoreFoundation and dispatch types and calls
   used, declared here as the libraries export them. */
typedef const void *FVCFTypeRef;
typedef long FVCFIndex;
typedef int32_t FVDAReturn;
typedef void (*FVDACallback) (FVCFTypeRef disk, FVCFTypeRef dissenter, void *context);

enum
{
  FVDAUnmountWhole = 0x00000001,
  FVDAReturnBusy = (int32_t)0xF8DA0002,
  FVDAReturnNotPermitted = (int32_t)0xF8DA0009,
  FVCFStringEncodingUTF8 = 0x08000100
};

static struct
{
  BOOL available;
  void *(*queueCreate) (const char *label, void *attributes);
  FVCFTypeRef (*sessionCreate) (FVCFTypeRef allocator);
  void (*sessionSetQueue) (FVCFTypeRef session, void *queue);
  FVCFTypeRef (*diskFromVolumePath) (FVCFTypeRef allocator, FVCFTypeRef session, FVCFTypeRef url);
  FVCFTypeRef (*wholeDisk) (FVCFTypeRef disk);
  void (*unmount) (FVCFTypeRef disk, uint32_t options, FVDACallback callback, void *context);
  void (*eject) (FVCFTypeRef disk, uint32_t options, FVDACallback callback, void *context);
  FVDAReturn (*dissenterStatus) (FVCFTypeRef dissenter);
  FVCFTypeRef (*dissenterString) (FVCFTypeRef dissenter);
  FVCFTypeRef (*urlFromPath) (FVCFTypeRef allocator, const unsigned char *path, FVCFIndex length,
                              unsigned char directory);
  unsigned char (*stringGetCString) (FVCFTypeRef string, char *buffer, FVCFIndex size,
                                     uint32_t encoding);
  void (*release) (FVCFTypeRef value);
  FVCFTypeRef session;
  void *queue;
} DA;

static void *
FVOpen (const char *name)
{
  char path[256];
  void *handle = dlopen (name, RTLD_NOW | RTLD_GLOBAL);
  if (handle == NULL)
    {
      snprintf (path, sizeof path, "/usr/lib/system/%s", name);
      handle = dlopen (path, RTLD_NOW | RTLD_GLOBAL);
    }
  return handle;
}

static BOOL
FVLoadDiskArbitration (void)
{
  /* Tried again after a failure: the libraries may be fixed meanwhile. */
  if (DA.available)
    return YES;
  void *da = FVOpen ("libDiskArbitration.so.1");
  void *cf = FVOpen ("libCoreFoundation.so.6");
  void *dispatch = FVOpen ("libsystem_dispatch.so.0");
  if (da == NULL || cf == NULL || dispatch == NULL)
    return NO;
  DA.queueCreate = dlsym (dispatch, "dispatch_queue_create");
  DA.sessionCreate = dlsym (da, "DASessionCreate");
  DA.sessionSetQueue = dlsym (da, "DASessionSetDispatchQueue");
  DA.diskFromVolumePath = dlsym (da, "DADiskCreateFromVolumePath");
  DA.wholeDisk = dlsym (da, "DADiskCopyWholeDisk");
  DA.unmount = dlsym (da, "DADiskUnmount");
  DA.eject = dlsym (da, "DADiskEject");
  DA.dissenterStatus = dlsym (da, "DADissenterGetStatus");
  DA.dissenterString = dlsym (da, "DADissenterGetStatusString");
  DA.urlFromPath = dlsym (cf, "CFURLCreateFromFileSystemRepresentation");
  DA.stringGetCString = dlsym (cf, "CFStringGetCString");
  DA.release = dlsym (cf, "CFRelease");
  if (!DA.queueCreate || !DA.sessionCreate || !DA.sessionSetQueue || !DA.diskFromVolumePath
      || !DA.wholeDisk || !DA.unmount || !DA.eject || !DA.dissenterStatus || !DA.urlFromPath
      || !DA.release)
    return NO;
  DA.session = DA.sessionCreate (NULL);
  DA.queue = DA.queueCreate ("org.nextbsd.Workspace.eject", NULL);
  if (DA.session == NULL || DA.queue == NULL)
    return NO;
  DA.sessionSetQueue (DA.session, DA.queue);
  DA.available = YES;
  return YES;
}

BOOL
FVCanEjectPaths (NSArray *paths)
{
  if (![paths count])
    return NO;
  NSArray *volumes = FVVolumesInMountRoots ();
  NSUInteger i;
  for (i = 0; i < [paths count]; i++)
    if (![volumes containsObject:[[paths objectAtIndex:i] stringByStandardizingPath]])
      return NO;
  return YES;
}

/* Reports on the main thread: a failure's alert. */
@interface FVEjectReport : NSObject
+ (void)failedVolume:(NSString *)name status:(NSNumber *)status reason:(NSString *)reason;
@end

@implementation FVEjectReport

+ (void)show:(NSArray *)report
{
  NSString *name = [report objectAtIndex:0];
  int32_t status = [[report objectAtIndex:1] intValue];
  NSString *reason = [report count] > 2 ? [report objectAtIndex:2] : nil;
  NSString *message;
  if (status == FVDAReturnBusy)
    message = [NSString stringWithFormat:@"The disk “%@” wasn’t ejected because one or more "
                                         @"programs may be using it.", name];
  else if (status == FVDAReturnNotPermitted)
    message = [NSString stringWithFormat:@"You don’t have permission to eject “%@”.", name];
  else
    message = [NSString stringWithFormat:@"The disk “%@” wasn’t ejected%@", name,
                   [reason length] ? [NSString stringWithFormat:@": %@.", reason] : @"."];
  FVRunAlert (@"Workspace", @"Disk Not Ejected", message, @"OK", nil);
}

+ (void)failedVolume:(NSString *)name status:(NSNumber *)status reason:(NSString *)reason
{
  NSArray *report = [NSArray arrayWithObjects:name, status, reason, nil];
  [self performSelectorOnMainThread:@selector (show:) withObject:report waitUntilDone:NO];
}

@end

/* One eject: the volume's name, for the alert, and the whole disk, which
   is ours to release. The disk the callbacks are given is DiskArbitration's
   and is never released here. */
struct FVEjectJob
{
  id name;
  FVCFTypeRef whole;
};

static void
FVFinish (struct FVEjectJob *job)
{
  DA.release (job->whole);
  RELEASE (job->name);
  free (job);
}

static void
FVReportDissenter (struct FVEjectJob *job, FVCFTypeRef dissenter)
{
  char buffer[512] = "";
  FVCFTypeRef text = DA.dissenterString ? DA.dissenterString (dissenter) : NULL;
  if (text && DA.stringGetCString)
    DA.stringGetCString (text, buffer, sizeof buffer, FVCFStringEncodingUTF8);
  [FVEjectReport failedVolume:job->name
                       status:[NSNumber numberWithInt:DA.dissenterStatus (dissenter)]
                       reason:[NSString stringWithUTF8String:buffer]];
}

/* After the eject: a disk that can't be ejected (most USB sticks have no
   media to eject) is still safe to remove once unmounted, so that isn't
   reported. */
static void
FVEjected (FVCFTypeRef disk, FVCFTypeRef dissenter, void *context)
{
  GSRegisterCurrentThread ();
  CREATE_AUTORELEASE_POOL (pool);
  FVFinish (context);
  RELEASE (pool);
}

/* The callbacks run on DiskArbitration's queue: a thread GNUstep doesn't
   know until it's registered. */
static void
FVUnmounted (FVCFTypeRef disk, FVCFTypeRef dissenter, void *context)
{
  struct FVEjectJob *job = context;
  if (!dissenter)
    {
      DA.eject (job->whole, 0, FVEjected, job);
      return;
    }
  GSRegisterCurrentThread ();
  CREATE_AUTORELEASE_POOL (pool);
  FVReportDissenter (job, dissenter);
  FVFinish (job);
  RELEASE (pool);
}

void
FVEjectVolume (NSString *path)
{
  NSString *name = [path lastPathComponent];
  if (!FVLoadDiskArbitration ())
    {
      [FVEjectReport failedVolume:name
                           status:[NSNumber numberWithInt:0]
                           reason:@"the disk service isn’t available"];
      return;
    }
  const char *fs = [path fileSystemRepresentation];
  FVCFTypeRef url = DA.urlFromPath (NULL, (const unsigned char *)fs, strlen (fs), 1);
  FVCFTypeRef disk = url ? DA.diskFromVolumePath (NULL, DA.session, url) : NULL;
  if (url)
    DA.release (url);
  FVCFTypeRef whole = disk ? DA.wholeDisk (disk) : NULL;
  if (disk)
    DA.release (disk);
  if (whole == NULL)
    {
      [FVEjectReport failedVolume:name
                           status:[NSNumber numberWithInt:0]
                           reason:@"it isn’t a disk the system manages"];
      return;
    }
  struct FVEjectJob *job = calloc (1, sizeof *job);
  if (job == NULL)
    {
      DA.release (whole);
      return;
    }
  job->name = RETAIN (name);
  job->whole = whole;
  DA.unmount (whole, FVDAUnmountWhole, FVUnmounted, job);
}
