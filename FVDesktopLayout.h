/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import <Foundation/Foundation.h>

/* Read active Iloc records, in macOS top-left coordinates. Invalid stores
 * return nil; a valid store without icon positions returns an empty dictionary. */
NSDictionary *FVReadDesktopLayout (NSString *path);
