//
//  HUDMemoryBridge.m
//  ManicEmu
//
//  Stub implementation. See HUDMemoryBridge.h: the callback is nil by
//  default, so readBytesAtAddress: returns nil until a core wires it up.
//  No game addresses are referenced anywhere in this file.
//
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

#import "HUDMemoryBridge.h"

// 3DS FCRAM window (New 3DS, 256 MB). Standard 3DS memory map — a validity
// window, not a game offset.
static const uint32_t kFCRAMBase = 0x08000000u;
static const uint32_t kFCRAMEnd  = 0x10000000u; // exclusive

@implementation HUDMemoryBridge

+ (instancetype)sharedBridge {
    static HUDMemoryBridge *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HUDMemoryBridge alloc] init;
    });
    return shared;
}

- (BOOL)hasLiveDataSource {
    return self.readBytesCallback != nil;
}

- (BOOL)isValidGuestPointer:(uint32_t)address length:(uint32_t)length {
    if (length == 0) { return NO; }
    if (address < kFCRAMBase || address >= kFCRAMEnd) { return NO; }
    // Overflow-safe end check: address + length must stay inside FCRAM.
    if (length > kFCRAMEnd - address) { return NO; }
    return YES;
}

- (nullable NSData *)readBytesAtAddress:(uint32_t)address length:(uint32_t)length {
    EmuGuestReadBytesFn callback = self.readBytesCallback;
    if (callback == nil) { return nil; }
    if (![self isValidGuestPointer:address length:length]) { return nil; }
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (data == nil) { return nil; }
    BOOL ok = callback(address, (uint8_t *)data.mutableBytes, length);
    return ok ? [data copy] : nil;
}

@end
