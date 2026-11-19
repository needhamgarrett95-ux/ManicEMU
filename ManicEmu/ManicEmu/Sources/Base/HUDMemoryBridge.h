//
//  HUDMemoryBridge.h
//  ManicEmu
//
//  Read-only memory bridge for the Pokemon X companion overlay.
//
//  The bridge exposes ONE thing: an optional callback the emulator core can
//  provide to read bytes from the emulated 3DS guest address space. The
//  callback is nil by default — no core in Manic currently provides one —
//  so every read returns nil and the companion stays on placeholder UI.
//
//  DO NOT hardcode game addresses here. The blueprint addresses that have
//  been suggested for Pokemon X are UNVERIFIED and must NOT be used:
//    0x08CE1CF8 (claimed party base), 0x081FB284 (claimed battle flag),
//    0x003D58A8 / 0x0041A3B4 / 0x00362D68 (claimed widescreen / 60fps /
//    no-outline patches). Stage 0 found no verified party, battle,
//    widescreen or 60fps address. They may only be used after verification
//    via Ghidra disassembly and/or a live Azahar FCRAM dump.
//
//  VERIFIED (2026-11-18, PAGE-TABLE-MAPPING-2026-11-18.md): the DllBattle
//  battle-Pokemon structs. Player base VA 0x081fd418, six slots at +0x1E4
//  stride; BATTLE offsets species u16 +0x0C, HP max u16 +0x0E, HP current
//  u16 +0x10 (LIVE — +0x0E is max, not current), moves 4 x 0xE at +0x116.
//  HP liveness proven by the post-damage test (Chespin 21 -> 18 at +0x10).
//  The verified addresses live in PokemonXCompanionModels.swift
//  (PokemonXBattleRead) and are validated at runtime by a species check
//  (1...721) on every poll — this bridge stays address-agnostic by design.
//
//  The only address range this file asserts is the 3DS FCRAM window
//  0x08000000-0x0FFFFFFF (256 MB, New 3DS), the standard 3DS memory map.
//  That is a validity window, not a game offset.
//
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Callback the emulator core provides. Reads `length` bytes from the guest
/// (emulated 3DS) address space into `outBuffer`. Returns YES on success.
/// Implemented by the core (LibretroCore) once it can expose guest memory.
/// Nil by default: no core currently provides this callback.
typedef BOOL (^EmuGuestReadBytesFn)(uint32_t guestAddress, uint8_t *outBuffer, uint32_t length);

@interface HUDMemoryBridge : NSObject

/// Shared instance. The read callback starts out nil.
+ (instancetype)sharedBridge;

/// Optional guest-memory read callback. Set only by the emulator core.
/// When nil, every read returns nil and the companion shows no live data.
@property (nonatomic, copy, nullable) EmuGuestReadBytesFn readBytesCallback;

/// YES only when a read callback is installed. The companion polls this;
/// it never treats "callback installed" as "live data available" — a read
/// must also succeed before any UI is updated.
@property (nonatomic, readonly) BOOL hasLiveDataSource;

/// Range check only: is [address, address + length) inside the 3DS FCRAM
/// window (0x08000000-0x0FFFFFFF) with no overflow? Says nothing about
/// whether the address holds game data.
- (BOOL)isValidGuestPointer:(uint32_t)address length:(uint32_t)length;

/// Reads `length` bytes at `guestAddress` via the callback.
/// Returns nil when there is no callback, the pointer is invalid, or the
/// callback reports failure. Never returns invented or placeholder bytes.
- (nullable NSData *)readBytesAtAddress:(uint32_t)address length:(uint32_t)length;

@end

NS_ASSUME_NONNULL_END
