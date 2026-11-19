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

/// Width of the docked Pokemon X companion side panel, in points.
/// PlayViewController shrinks the game view by this amount when the panel
/// is open (see setCompanionPanelOpen / companionAdjustedGameFrame).
let PokemonXCompanionPanelWidth: CGFloat = 320

/// Sends a tap to the game's bottom screen and releases it after the
/// lab-proven hold (~0.7s; 0.6-0.8s measured for battle-menu taps).
enum PokemonXTouchSender {

    /// How long a sent touch is held before release. Lab-proven 0.6-0.8s
    /// for battle-menu taps (FIGHT / move selection).
    static let holdDuration: TimeInterval = 0.7

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
    /// (see Battle.*).
    static func send(point: CGPoint) {
        send(normalizedX: point.x, normalizedY: point.y)
    }
}
