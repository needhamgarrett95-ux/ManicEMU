//
//  PokemonXTouchSender.swift
//  ManicEmu
//
//  Sends taps to the Pokemon X bottom (touch) screen through the Azahar
//  libretro core. Works only with the widescreen layout in
//  PlayViewController (identical top/bottom rects + citra_swap_screen =
//  "Bottom"): the core's touch gate (IsWithinTouchscreen) tests the bottom
//  rect, so a zero bottom rect rejects every press, while identical rects
//  pass any point in the buffer. The touch point is computed from
//  AzaharEmulatorBridge.shared.touchInputFrame exactly like the DS/3DS
//  bridge touch path (ThreeDS.swift): frame.min + frame.size * normalized.
//
//  No UI is wired to this sender (the companion View owns the buttons);
//  this is the send path + the measured battle-menu centres only.
//
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import UIKit

/// Sends a tap to the game's bottom screen and releases it after the
/// lab-proven hold (~0.7s; 0.6-0.8s measured for battle-menu taps).
enum PokemonXTouchSender {

    /// How long a sent touch is held before release. Lab-proven 0.6-0.8s
    /// for battle-menu taps (FIGHT / move selection).
    static let holdDuration: TimeInterval = 0.7

    /// How long a sent touch is held for in-game MENU pills (POKEMON /
    /// POKEDEX / BAG). Lab-proven 0.15s — menu pills want QUICK taps; a
    /// 0.7s hold FAILED twice on the POKEMON pill (the opposite of the
    /// battle-menu buttons). See MENU-TOUCH-SCRIPTS-2026-11-19.md.
    static let quickHoldDuration: TimeInterval = 0.15

    /// Measured battle-menu centres in 3DS bottom-screen space (320x240),
    /// with their normalized (0...1) equivalents. Normalized values are
    /// what send() takes; the 3DS pixel values are recorded here so the
    /// mapping stays auditable against the lab measurements.
    enum Battle {
        /// FIGHT button, first battle-menu row. Measured (160,100).
        static let fight = CGPoint(x: 0.500, y: 0.417)
        /// BAG button. Measured (25,225).
        static let bag = CGPoint(x: 0.078, y: 0.938)
        /// RUN button. Measured (170,225).
        static let run = CGPoint(x: 0.531, y: 0.938)
        /// POKEMON button. Measured (315,225).
        static let pokemon = CGPoint(x: 0.984, y: 0.938)
        /// Tackle, first move slot. Measured (95,45).
        static let tackle = CGPoint(x: 0.297, y: 0.188)
        /// Growl, second move slot. ESTIMATED (~240,45) — not lab-measured.
        static let growl = CGPoint(x: 0.750, y: 0.188)
        /// Vine Whip, third move slot. ESTIMATED (~95,120) — not lab-measured.
        static let vineWhip = CGPoint(x: 0.297, y: 0.500)
    }

    /// Measured in-game menu pill centres in 3DS bottom-screen space
    /// (320x240), normalized. Lab-measured (MENU-TOUCH-SCRIPTS-2026-11-19.md):
    /// POKEMON (84,53), POKEDEX (237,53), BAG (84,110). Pills are
    /// ~145x30 with ±10px tolerance. SAVE / OPTIONS / TRAINER were
    /// measured only and are deliberately NOT wired (do not wire SAVE).
    enum Menu {
        /// POKEMON pill. Measured (84,53).
        static let pokemon = CGPoint(x: 0.2625, y: 0.2208)
        /// POKEDEX pill. Measured (237,53).
        static let pokedex = CGPoint(x: 0.7406, y: 0.2208)
        /// BAG pill. Measured (84,110).
        static let bag = CGPoint(x: 0.2625, y: 0.4583)
    }

    /// Generation counter: a delayed release only fires for the press that
    /// scheduled it, so a second tap cannot be cut short by the first
    /// tap's release.
    private static var generation = 0

    /// Sends a touch at the given normalized bottom-screen position
    /// (0...1 in each axis), holds it for holdDuration, then releases.
    /// Does nothing when the touch frame is zero (widescreen layout not
    /// active), so a stray send can never hit a hidden screen.
    static func send(normalizedX: CGFloat, normalizedY: CGFloat) {
        let frame = AzaharEmulatorBridge.shared.touchInputFrame
        guard !frame.isEmpty, frame.width > 0, frame.height > 0 else {
#if DEBUG
            Log.debug("[PokemonXTouchSender] touchInputFrame is empty, ignoring tap (\(normalizedX), \(normalizedY))")
#endif
            return
        }
        let point = CGPoint(x: frame.minX + frame.width * normalizedX,
                            y: frame.minY + frame.height * normalizedY)
        generation += 1
        let myGeneration = generation
        LibretroCore.sharedInstance().sendTouchEventX(point.x, y: point.y)
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
            guard myGeneration == generation else { return }
            LibretroCore.sharedInstance().releaseTouchEvent()
        }
    }

    /// Convenience: sends a touch at a named normalized point
    /// (see Battle.* / Menu.*).
    static func send(point: CGPoint) {
        send(normalizedX: point.x, normalizedY: point.y)
    }

    /// Sends a QUICK touch at the given normalized point (0.15s hold) —
    /// for in-game menu pills, which want quick taps (see
    /// quickHoldDuration). Same frame guard as send().
    static func sendQuick(point: CGPoint) {
        let frame = AzaharEmulatorBridge.shared.touchInputFrame
        guard !frame.isEmpty, frame.width > 0, frame.height > 0 else {
#if DEBUG
            Log.debug("[PokemonXTouchSender] touchInputFrame is empty, ignoring quick tap (\(point.x), \(point.y))")
#endif
            return
        }
        let touchPoint = CGPoint(x: frame.minX + frame.width * point.x,
                                 y: frame.minY + frame.height * point.y)
        generation += 1
        let myGeneration = generation
        LibretroCore.sharedInstance().sendTouchEventX(touchPoint.x, y: touchPoint.y)
        DispatchQueue.main.asyncAfter(deadline: .now() + quickHoldDuration) {
            guard myGeneration == generation else { return }
            LibretroCore.sharedInstance().releaseTouchEvent()
        }
    }

    /// Chained move send: FIGHT first so the game opens the move list,
    /// then the move-slot point after ~1s (after the 0.7s FIGHT hold has
    /// released). Slot 3 has NO measured centre — never sent (the caller
    /// must disable it; this guards it out too).
    static func sendMove(slotId: Int) {
        guard slotId >= 0, slotId < 3 else { return }
        let movePoints: [CGPoint] = [Battle.tackle, Battle.growl, Battle.vineWhip]
        send(point: Battle.fight)
        let point = movePoints[slotId]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            send(point: point)
        }
    }
}

// MARK: - Game driver (overlay buttons -> the game's own screens)

/// Drives the game's own screens from the overlay (Garrett 2026-11-19):
/// the overlay buttons open the game's menu screens instead of companion
/// popups. Lab-verified in MENU-TOUCH-SCRIPTS-2026-11-19.md (Azahar lab,
/// bottom-screen 320x240 coords). Touch alone CANNOT open the menu — the
/// field bottom screen is PSS (Friends/Acquaintances/Passersby), and a
/// centre tap there is a no-op — so the menu is opened with the 3DS X
/// button through LibretroCore.press(.X) / release(.X), the same
/// virtual-joypad API Manic itself uses (X = 9, the same joypad bit the
/// GameSir's X button feeds). Waits are the lab waits shortened for phone
/// speed (the lab ran at 40-85% speed: 3s after X, 2-3s after a pill,
/// 6-8s after POKEDEX). ~1 in 10 quick taps were dropped in the lab —
/// a script is never blind-retried (a retry could act on the newly opened
/// screen); the player re-taps the overlay button if nothing opens.
/// One script at a time: a second button tap while a script is running
/// is ignored until the script finishes.
enum PokemonXGameDriver {

    /// True while a menu script is in flight.
    private(set) static var isScriptRunning = false

    /// Presses a 3DS face button for `hold` seconds, then releases it.
    /// Completion fires after the release.
    static func pressButton(_ button: LibretroButton, hold: TimeInterval, completion: (() -> Void)? = nil) {
        LibretroCore.sharedInstance().press(button, playerIndex: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            LibretroCore.sharedInstance().release(button, playerIndex: 0)
            completion?()
        }
    }

    /// X (0.3s hold), then 1.0s for the menu slide-in at phone speed.
    private static func openMenu(_ then: @escaping () -> Void) {
        pressButton(.X, hold: 0.3) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: then)
        }
    }

    /// Opens the game's own Pokemon party screen. VERIFIED twice in the
    /// lab: X, quick-tap POKEMON (84,53) -> party screen (Chespin Lv6
    /// HP 23/23).
    static func openParty() {
        guard !isScriptRunning else { return }
        isScriptRunning = true
        openMenu {
            PokemonXTouchSender.sendQuick(point: PokemonXTouchSender.Menu.pokemon)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isScriptRunning = false
            }
        }
    }

    /// Opens the game's own Bag screen. VERIFIED in the lab: X,
    /// quick-tap BAG (84,110) -> bag open (ITEMS pocket empty).
    static func openBag() {
        guard !isScriptRunning else { return }
        isScriptRunning = true
        openMenu {
            PokemonXTouchSender.sendQuick(point: PokemonXTouchSender.Menu.bag)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                isScriptRunning = false
            }
        }
    }

    /// Opens the game's own Pokedex. VERIFIED WITH CAVEAT in the lab: X,
    /// quick-tap POKEDEX (237,53) -> Dex splash ("POKÉDEX / CENTRAL
    /// KALOS POKEDEX 1"); the entry list needs one A press, which this
    /// sends 2.0s after the pill tap. Touch does NOT advance the splash
    /// (a centre tap is a no-op; the blue arrow at (295,224) EXITS the
    /// Dex, so it is never tapped).
    static func openDex() {
        guard !isScriptRunning else { return }
        isScriptRunning = true
        openMenu {
            PokemonXTouchSender.sendQuick(point: PokemonXTouchSender.Menu.pokedex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                pressButton(.A, hold: 0.3) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isScriptRunning = false
                    }
                }
            }
        }
    }

    /// Backs out of a game screen the overlay opened, one B press per
    /// level (0.3s hold, 0.7s apart). Field screens need 2 presses
    /// (sub-screen -> menu -> field); in-battle bag/party need 1 (back to
    /// the battle menu). B does nothing in the field, so extra presses
    /// are harmless if the player already closed the screen with the
    /// controller.
    static func backOut(levels: Int, completion: (() -> Void)? = nil) {
        guard !isScriptRunning else { return }
        isScriptRunning = true
        func pressLevel(_ remaining: Int) {
            guard remaining > 0 else {
                isScriptRunning = false
                completion?()
                return
            }
            pressButton(.B, hold: 0.3) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    pressLevel(remaining - 1)
                }
            }
        }
        pressLevel(levels)
    }
}
