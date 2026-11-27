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

#import "FVThumbnails.h"
#import <AppKit/AppKit.h>
#include <signal.h>
#include <unistd.h>

@implementation FVThumbnailOperation

+ (BOOL)enabled
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"ShowThumbnails"];
  return value == nil || [value boolValue];
}

+ (BOOL)supportsPath:(NSString *)value
{
  NSString *extension = [[value pathExtension] lowercaseString];
  NSArray *types = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"png", @"gif", @"bmp",
      @"tif", @"tiff", @"webp", @"avif", @"heic", @"heif", @"ppm", @"pgm",
      @"mp4", @"m4v", @"mov", @"mkv", @"avi", @"webm", @"mpg", @"mpeg",
      @"mts", @"m2ts", @"ts", @"wmv", @"flv", @"ogv", @"3gp",
      @"mp3", @"m4a", @"flac", @"ogg", @"opus", @"wma", nil];
  return [types containsObject:extension];
}

- (id)initWithPath:(NSString *)value generation:(NSUInteger)token target:(id)receiver
{
  if ((self = [super init]))
    {
      path = [value copy];
      generation = token;
      target = RETAIN (receiver);
    }
  return self;
}

/* Still images GNUstep decodes itself (libpng, libjpeg, libtiff, giflib),
   scaled to fit 256 pixels by averaging each block of source pixels:
   NextBSD's ffmpeg is built for video and has no image decoders. */
static const NSUInteger FVThumbnailSide = 256;
static const unsigned long long FVThumbnailMaxBytes = 64ULL * 1024 * 1024;

- (NSData *)renderImage
{
  NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path
                                                                             error:NULL];
  if ([attributes fileSize] == 0 || [attributes fileSize] > FVThumbnailMaxBytes)
    return nil;
  NSData *file = [NSData dataWithContentsOfFile:path];
  NSBitmapImageRep *source = nil;
  NSArray *reps = file ? [NSBitmapImageRep imageRepsWithData:file] : nil;
  NSUInteger i;
  for (i = 0; i < [reps count] && !source; i++)
    if ([[reps objectAtIndex:i] isKindOfClass:[NSBitmapImageRep class]])
      source = [reps objectAtIndex:i];
  NSInteger sw = [source pixelsWide], sh = [source pixelsHigh];
  if (!source || sw <= 0 || sh <= 0 || [self isCancelled])
    return nil;
  CGFloat scale = MIN (1.0, (CGFloat)FVThumbnailSide / MAX (sw, sh));
  NSInteger dw = MAX (1, (NSInteger)floor (sw * scale)), dh = MAX (1, (NSInteger)floor (sh * scale));
  NSBitmapImageRep *thumb = AUTORELEASE ([[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL pixelsWide:dw pixelsHigh:dh bitsPerSample:8
               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:dw * 4 bitsPerPixel:32]);
  unsigned char *out = [thumb bitmapData];
  NSInteger spp = [source samplesPerPixel];
  BOOL fast = [source bitsPerSample] == 8 && ![source isPlanar] && spp >= 1 && spp <= 4
              && [source bitmapData] != NULL;
  BOOL alpha = [source hasAlpha];
  unsigned char *in = [source bitmapData];
  NSInteger row = [source bytesPerRow], bpp = [source bitsPerPixel] / 8;
  NSInteger x, y;
  for (y = 0; y < dh && ![self isCancelled]; y++)
    for (x = 0; x < dw; x++)
      {
        NSInteger x0 = x * sw / dw, x1 = MAX (x0 + 1, (x + 1) * sw / dw);
        NSInteger y0 = y * sh / dh, y1 = MAX (y0 + 1, (y + 1) * sh / dh);
        /* At most 8 by 8 samples a pixel: enough to smooth, quick on big photos. */
        NSInteger stepx = MAX (1, (x1 - x0) / 8), stepy = MAX (1, (y1 - y0) / 8);
        unsigned long r = 0, g = 0, b = 0, a = 0, n = 0;
        NSInteger sx, sy;
        for (sy = y0; sy < y1; sy += stepy)
          for (sx = x0; sx < x1; sx += stepx)
            {
              unsigned int pr, pg, pb, pa;
              if (fast)
                {
                  unsigned char *p = in + sy * row + sx * bpp;
                  if (spp >= 3)
                    {
                      pr = p[0], pg = p[1], pb = p[2];
                      pa = alpha ? p[spp - 1] : 255;
                    }
                  else
                    {
                      pr = pg = pb = p[0];
                      pa = alpha ? p[1] : 255;
                    }
                }
              else
                {
                  NSColor *c = [[source colorAtX:sx y:sy]
                      colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                  pr = 255 * [c redComponent], pg = 255 * [c greenComponent];
                  pb = 255 * [c blueComponent], pa = 255 * [c alphaComponent];
                }
              r += pr, g += pg, b += pb, a += pa, n++;
            }
        unsigned char *q = out + y * dw * 4 + x * 4;
        q[0] = r / n, q[1] = g / n, q[2] = b / n, q[3] = a / n;
      }
  if ([self isCancelled])
    return nil;
  return [thumb representationUsingType:NSPNGFileType properties:nil];
}

- (NSData *)renderWithTool:(NSString *)name arguments:(NSArray *)arguments
                   output:(NSString *)output
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *roots = [NSArray arrayWithObjects:@"/usr/bin", @"/usr/local/bin", nil];
  NSString *executable = nil;
  NSUInteger i;
  for (i = 0; i < [roots count]; i++)
    {
      NSString *candidate = [[roots objectAtIndex:i] stringByAppendingPathComponent:name];
      if ([fm isExecutableFileAtPath:candidate])
        {
          executable = candidate;
          break;
        }
    }
  if (!executable || [self isCancelled])
    return nil;
  NSTask *task = [[NSTask alloc] init];
  NSData *data = nil;
  @try
    {
      [task setLaunchPath:executable];
      [task setArguments:arguments];
      [task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
      [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
      [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
      [task launch];
      NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
      while ([task isRunning] && ![self isCancelled] && [deadline timeIntervalSinceNow] > 0)
        usleep (20000);
      if ([task isRunning])
        {
          [task terminate];
          usleep (100000);
          if ([task isRunning])
            kill ([task processIdentifier], SIGKILL);
        }
      [task waitUntilExit];
      if (![self isCancelled] && [task terminationStatus] == 0)
        data = [NSData dataWithContentsOfFile:output];
    }
  @catch (NSException *exception)
    {
      /* Fall back when the tool cannot decode this media. */
    }
  if ([task isRunning])
    {
      kill ([task processIdentifier], SIGKILL);
      [task waitUntilExit];
    }
  RELEASE (task);
  /* Both tools output PNG. Reject empty or partial output before falling back. */
  const unsigned char signature[] = { 137, 80, 78, 71, 13, 10, 26, 10 };
  if ([data length] < 24 || memcmp ([data bytes], signature, sizeof (signature)) != 0)
    return nil;
  return data;
}

- (void)main
{
  CREATE_AUTORELEASE_POOL (pool);
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *temporary = nil;
  NSData *data = nil;
  BOOL directory = NO;
  if (![self isCancelled] && [fm fileExistsAtPath:path isDirectory:&directory] && !directory)
    {
      char *pattern = strdup ([[NSTemporaryDirectory ()
          stringByAppendingPathComponent:@"fileviewer-thumbnail-XXXXXX"] fileSystemRepresentation]);
      if (pattern && mkdtemp (pattern))
        temporary = [[fm stringWithFileSystemRepresentation:pattern length:strlen (pattern)] copy];
      free (pattern);
      if (temporary)
        {
          NSString *output = [temporary stringByAppendingPathComponent:@"preview.png"];
          NSArray *movies = [NSArray arrayWithObjects:@"mp4", @"m4v", @"mov", @"mkv",
              @"avi", @"webm", @"mpg", @"mpeg", @"mts", @"m2ts", @"ts", @"wmv",
              @"flv", @"ogv", @"3gp", nil];
          NSArray *images = [NSArray arrayWithObjects:@"png", @"jpg", @"jpeg", @"gif",
              @"tif", @"tiff", @"bmp", nil];
          NSString *extension = [[path pathExtension] lowercaseString];
          if ([images containsObject:extension])
            data = [self renderImage];
          if (!data && [movies containsObject:extension])
            data = [self renderWithTool:@"ffmpegthumbnailer"
                arguments:[NSArray arrayWithObjects:@"-i", path, @"-o", output,
                    @"-s", @"256", @"-c", @"png", @"-m", nil] output:output];
          if (!data && ![self isCancelled])
            data = [self renderWithTool:@"ffmpeg"
                arguments:[NSArray arrayWithObjects:@"-nostdin", @"-v", @"error",
                    @"-threads", @"1", @"-filter_threads", @"1",
                    @"-protocol_whitelist", @"file,pipe", @"-i", path,
                    @"-map", @"0:v:0", @"-frames:v", @"1", @"-vf",
                    @"scale=256:256:force_original_aspect_ratio=decrease,thumbnail=30",
                    @"-threads", @"1", @"-y", output, nil] output:output];
        }
    }
  if (temporary)
    [fm removeItemAtPath:temporary error:NULL];
  if (![self isCancelled])
    {
      NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
          path, @"path", [NSNumber numberWithUnsignedInteger:generation], @"generation", nil];
      if (data)
        [result setObject:data forKey:@"data"];
      [target performSelectorOnMainThread:@selector (thumbnailLoaded:)
                              withObject:result waitUntilDone:NO];
    }
  RELEASE (temporary);
  RELEASE (pool);
}

- (void)dealloc
{
  RELEASE (path);
  RELEASE (target);
  DEALLOC;
}

@end
