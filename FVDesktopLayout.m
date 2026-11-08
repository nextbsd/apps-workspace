/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import "FVDesktopLayout.h"
#include <stdint.h>
#include <string.h>

/* The Bud1 allocator and DSDB B-tree are described by the ds_store project:
 * https://github.com/dmgbuild/ds_store . Only reachable records are read;
 * scanning for Iloc bytes would also resurrect deleted/stale positions. */
typedef struct
{
  const unsigned char *bytes;
  NSUInteger length, position;
  BOOL valid;
} FVLayoutReader;

static const unsigned char *
FVTake (FVLayoutReader *reader, NSUInteger count)
{
  const unsigned char *result;
  if (!reader->valid || count > reader->length - reader->position)
    {
      reader->valid = NO;
      return NULL;
    }
  result = reader->bytes + reader->position;
  reader->position += count;
  return result;
}

static uint32_t
FVRead32 (FVLayoutReader *reader)
{
  const unsigned char *p = FVTake (reader, 4);
  return p ? ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
      | ((uint32_t)p[2] << 8) | p[3] : 0;
}

static FVLayoutReader
FVBlock (NSData *data, NSArray *addresses, uint32_t index)
{
  FVLayoutReader reader = { NULL, 0, 0, NO };
  if (index < [addresses count])
    {
      uint32_t address = [[addresses objectAtIndex:index] unsignedIntValue];
      NSUInteger offset = (NSUInteger)(address & ~31U) + 4;
      NSUInteger size = (NSUInteger)1 << (address & 31);
      if (address && offset <= [data length] && size <= [data length] - offset)
        {
          reader.bytes = (const unsigned char *)[data bytes] + offset;
          reader.length = size;
          reader.valid = YES;
        }
    }
  return reader;
}

static BOOL
FVReadNode (NSData *data, NSArray *addresses, uint32_t index,
            NSMutableSet *visited, NSMutableDictionary *positions, NSUInteger depth)
{
  NSNumber *key = [NSNumber numberWithUnsignedInt:index];
  FVLayoutReader reader;
  uint32_t next, count, i;
  if (depth > 64 || [visited containsObject:key])
    return NO;
  [visited addObject:key];
  reader = FVBlock (data, addresses, index);
  next = FVRead32 (&reader);
  count = FVRead32 (&reader);
  if (!reader.valid || count > reader.length / 12)
    return NO;
  for (i = 0; i < count && reader.valid; i++)
    {
      uint32_t nameLength, code, type, size;
      const unsigned char *bytes;
      NSString *name;
      if (next)
        {
          uint32_t child = FVRead32 (&reader);
          if (!reader.valid || !FVReadNode (data, addresses, child, visited, positions, depth + 1))
            return NO;
        }
      nameLength = FVRead32 (&reader);
      if (nameLength > (reader.length - reader.position) / 2)
        return NO;
      bytes = FVTake (&reader, (NSUInteger)nameLength * 2);
      if (!bytes)
        return NO;
      name = AUTORELEASE ([[NSString alloc] initWithBytes:bytes length:nameLength * 2
                                               encoding:NSUTF16BigEndianStringEncoding]);
      if (!name)
        return NO;
      code = FVRead32 (&reader);
      type = FVRead32 (&reader);
      switch (type)
        {
          case 0x626f6f6c: size = 1; break; /* bool */
          case 0x6c6f6e67: /* long */
          case 0x73686f72: /* shor */
          case 0x74797065: size = 4; break; /* type */
          case 0x636f6d70: /* comp */
          case 0x64757463: size = 8; break; /* dutc */
          case 0x626c6f62: size = FVRead32 (&reader); break; /* blob */
          case 0x75737472: /* ustr */
            size = FVRead32 (&reader);
            if (size > (reader.length - reader.position) / 2)
              return NO;
            size *= 2;
            break;
          default: return NO;
        }
      bytes = FVTake (&reader, size);
      if (!bytes)
        return NO;
      if (code == 0x496c6f63 && type == 0x626c6f62 && size >= 8)
        {
          FVLayoutReader pointReader = { bytes, size, 0, YES };
          int32_t x = (int32_t)FVRead32 (&pointReader);
          int32_t y = (int32_t)FVRead32 (&pointReader);
          if (x >= 0 && y >= 0)
            [positions setObject:[NSValue valueWithPoint:NSMakePoint (x, y)] forKey:name];
        }
    }
  return reader.valid && (!next || FVReadNode (data, addresses, next, visited, positions, depth + 1));
}

NSDictionary *
FVReadDesktopLayout (NSString *path)
{
  NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
  NSData *data;
  FVLayoutReader reader, root, superblock;
  uint32_t offset, size, count, i, tocCount, superIndex = UINT32_MAX;
  NSMutableArray *addresses = [NSMutableArray array];
  NSMutableDictionary *positions = [NSMutableDictionary dictionary];
  /* Bound memory and work for untrusted or accidentally huge metadata. */
  if (!attributes || [attributes fileSize] > 32 * 1024 * 1024)
    return nil;
  data = [NSData dataWithContentsOfFile:path];
  reader.bytes = [data bytes];
  reader.length = [data length];
  reader.position = 0;
  reader.valid = YES;
  if (FVRead32 (&reader) != 1 || FVRead32 (&reader) != 0x42756431)
    return nil;
  offset = FVRead32 (&reader);
  size = FVRead32 (&reader);
  if (FVRead32 (&reader) != offset || !reader.valid
      || (NSUInteger)offset + 4 > [data length]
      || size > [data length] - ((NSUInteger)offset + 4))
    return nil;
  root.bytes = (const unsigned char *)[data bytes] + offset + 4;
  root.length = size;
  root.position = 0;
  root.valid = YES;
  count = FVRead32 (&root);
  FVRead32 (&root);
  if (!root.valid || count > size / 4 || count > 100000)
    return nil;
  for (i = 0; i < count; i++)
    [addresses addObject:[NSNumber numberWithUnsignedInt:FVRead32 (&root)]];
  FVTake (&root, (((NSUInteger)count + 255) & ~(NSUInteger)255) * 4 - count * 4);
  tocCount = FVRead32 (&root);
  if (!root.valid || tocCount > size / 5)
    return nil;
  for (i = 0; i < tocCount; i++)
    {
      const unsigned char *length = FVTake (&root, 1);
      const unsigned char *name;
      unsigned int nameLength;
      uint32_t block;
      if (!length)
        return nil;
      nameLength = *length;
      name = FVTake (&root, nameLength);
      block = FVRead32 (&root);
      if (!root.valid)
        return nil;
      if (nameLength == 4 && memcmp (name, "DSDB", 4) == 0)
        superIndex = block;
    }
  superblock = FVBlock (data, addresses, superIndex);
  i = FVRead32 (&superblock);
  if (!superblock.valid || !FVReadNode (data, addresses, i,
      [NSMutableSet set], positions, 0))
    return nil;
  return positions;
}
