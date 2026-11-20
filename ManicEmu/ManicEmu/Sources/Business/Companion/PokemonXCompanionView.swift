//
//  PokemonXCompanionView.swift
//  ManicEmu
//
//  PokeDaisy-style floating companion overlay for Pokemon X (v3, Garrett's
//  design, 2026-11-19): the game fills the WHOLE screen and the overlay
//  floats over it — no docked panel, no backgrounds, no headers. Minimal
//  footprint; the game is the star. Layout (from Garrett's PokeDaisy
//  reference screenshot + his 13:47-13:55 refinements):
//  - Minimap widget top-right (small schematic Kalos map + area label).
//  - Party sprite box bottom-left (lead sprite + HP bar, small dark box).
//  - Field buttons spread across the bottom: PARTY / DEX / BAG / BATTLE /
//    GUIDE. BAG is an icon button with a live count badge.
//  - In battle everything else hides and the bottom row swaps to the
//    battle commands FIGHT / BAG / POKEMON / RUN (same spot, same size);
//    FIGHT swaps the row to the four moves + a back arrow. Only ever one
//    slim row on screen in battle.
//  - When a game screen is open, the overlay gets out of the way: only a
//    small back pill shows until the player is back in the field.
//
//  BUTTONS DRIVE THE GAME'S OWN SCREENS (Garrett 2026-11-19): PARTY /
//  DEX / BAG open the game's own party / Pokedex / bag via the lab-verified
//  touch scripts in PokemonXGameDriver (X press + menu pill tap) — not
//  companion popups. BATTLE in the field opens the battle info card;
//  in battle, BAG / POKEMON open the game's in-battle bag / party.
//  GUIDE is the only companion popup (no in-game equivalent). MAP falls
//  back to the companion map card: the in-game Town Map is BLOCKED — the
//  Town Map item (0x001C) is not in the bag at this story point (lab
//  verified 2026-11-19), so no Town Map script exists yet; the button
//  must say so, never ship dead.
//
//  STYLING: Pokemon X's own modern 3DS blue/white UI (sleek, not the
//  chunky GBA pixel look) — white pills with blue borders and dark-blue
//  text, blue card headers. Generic iOS dark-mode styling is wrong here;
//  the overlay must look baked into Pokemon X.
//
//  LIVE DATA: the widgets show live reads at a glance (lead sprite + HP,
//  minimap + live area label, bag count badge) from the same verified
//  reads as before (field party table, battle structs, bag VA, map chain,
//  Dex JSON). The overlay NEVER pauses the game and never touches the
//  skin: the controller (GameSir) keeps driving the game while touch
//  drives the overlay. Each widget is its own small UIHostingController
//  sized to its content, so touches outside the widgets fall through to
//  the game / on-screen controls below.
//
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import SwiftUI
import UIKit
import Combine

// MARK: - Pokemon X UI style (modern 3DS blue/white, not GBA chunky)

/// Pokemon X's own menu palette: sleek blue/white, rounded, bold dark-blue
/// text on white. Everything in the overlay draws from here so it reads
/// as part of the game, not pasted on top.
private enum PokemonXXStyle {
    /// X menu blue (headers, borders, accents).
    static let blue = Color(red: 0.16, green: 0.40, blue: 0.75)
    /// X dark blue (button text, titles).
    static let deepBlue = Color(red: 0.07, green: 0.20, blue: 0.45)
    /// Pale blue tint (card / chip backgrounds).
    static let lightBlue = Color(red: 0.88, green: 0.94, blue: 1.0)
    /// X gold (best-pick highlight, badges).
    static let gold = Color(red: 0.95, green: 0.72, blue: 0.10)
    /// Card white.
    static let panel = Color.white.opacity(0.97)
    /// Rounded bold label font, like X's menu text.
    static func labelFont(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    /// HP bar colour by fraction (green / yellow / red, like the game).
    static func hpColor(fraction: Double) -> Color {
        if fraction > 0.5 { return Color(red: 0.25, green: 0.80, blue: 0.30) }
        if fraction > 0.25 { return Color(red: 0.95, green: 0.80, blue: 0.20) }
        return Color(red: 0.90, green: 0.25, blue: 0.25)
    }
}

// MARK: - Overlay-only UI state (the live game state stays in PokemonXCompanionState)

/// Which companion card is open, if any. GUIDE is the only popup with no
/// in-game equivalent; MAP is the fallback (in-game Town Map blocked);
/// BATTLE is the field battle-info card.
enum PokemonXOverlayCard {
    case guide, map, battle
}

/// Which of the game's own screens the overlay opened, for the back pill.
/// Field screens need 2 B presses to back out (sub-screen -> menu ->
/// field); in-battle bag/party need 1 (back to the battle menu).
enum PokemonXGameScreen {
    case party, bag, dex, battleBag, battleParty
    var backPresses: Int {
        switch self {
        case .party, .bag, .dex: return 2
        case .battleBag, .battleParty: return 1
        }
    }
}

/// Overlay-only UI state, observed by every hosted widget. The presenter
/// owns the single instance; the live game reads live in
/// PokemonXCompanionState.
final class PokemonXOverlayUIState: ObservableObject {
    @Published var openCard: PokemonXOverlayCard?
    @Published var screenOpen: PokemonXGameScreen?
    @Published var showingMoves = false
    @Published var isInBattle = false
    /// True from a move tap until the row returns to commands (~1.8s);
    /// row buttons are disabled meanwhile so a second tap cannot land on
    /// the wrong screen while the FIGHT+move send is still in flight.
    @Published var moveSendPending = false
}

// MARK: - Presenter (small floating hosts on top of the game)

enum PokemonXCompanionPresenter {
    /// Shared state, kept across close/reopen so Nuzlocke runs (and the
    /// remembered last ball) survive dismissing the overlay.
    private static var sharedState: PokemonXCompanionState?
    /// Overlay-only UI state, kept across close/reopen.
    private static let uiState = PokemonXOverlayUIState()
    private static var minimapHost: UIHostingController<AnyView>?
    private static var spriteHost: UIHostingController<AnyView>?
    private static var rowHost: UIHostingController<AnyView>?
    private static var pillHost: UIHostingController<AnyView>?
    private static var cardHost: UIHostingController<AnyView>?
    /// STAGE1-X DIAGNOSTIC (v1): top-edge strip showing the live layout
    /// diagnostic line. Never hidden by updateVisibility.
    private static var diagHost: UIHostingController<AnyView>?
    private static var cancellables = Set<AnyCancellable>()

    /// True while the overlay is installed. Lets the menu Companion
    /// option work as a real toggle (show / hide the overlay bar).
    static var isPresented: Bool { rowHost != nil }

    /// Installs the floating overlay: minimap, sprite box, button row,
    /// back pill and card host — five small hosting controllers, each
    /// sized to its content, so touches outside them fall through to the
    /// game below. Plus the STAGE1-X diagnostic strip (v1, top edge, full
    /// width, non-interactive). Deliberately does NOT pause emulation, does NOT change
    /// forceFullSkin, and does NOT show the skin buttons — so the
    /// controller keeps working while the overlay is up.
    static func present() {
        guard let host = PlayViewController.currentPlayViewController else { return }
        guard rowHost == nil else { return }
        installMemoryBridgeIfNeeded()
        let state: PokemonXCompanionState
        if let existing = sharedState {
            state = existing
        } else {
            let fresh = PokemonXCompanionState()
            sharedState = fresh
            state = fresh
        }
        let safe = host.view.safeAreaLayoutGuide
        rowHost = install(host: host,
                          content: PokemonXOverlayRowView(state: state, uiState: uiState)) { view, _ in
            [view.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
             view.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
             view.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8),
             view.heightAnchor.constraint(equalToConstant: 50)]
        }
        minimapHost = install(host: host,
                              content: PokemonXMinimapWidgetView(state: state, uiState: uiState)) { view, _ in
            [view.topAnchor.constraint(equalTo: safe.topAnchor, constant: 10),
             view.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -10),
             view.widthAnchor.constraint(equalToConstant: 132),
             view.heightAnchor.constraint(equalToConstant: 100)]
        }
        spriteHost = install(host: host,
                             content: PokemonXSpriteBoxView(state: state, uiState: uiState)) { view, _ in
            [view.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 10),
             view.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -72),
             view.widthAnchor.constraint(equalToConstant: 72),
             view.heightAnchor.constraint(equalToConstant: 84)]
        }
        pillHost = install(host: host,
                           content: PokemonXBackPillView(uiState: uiState)) { view, _ in
            [view.topAnchor.constraint(equalTo: safe.topAnchor, constant: 10),
             view.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
             view.widthAnchor.constraint(equalToConstant: 150),
             view.heightAnchor.constraint(equalToConstant: 40)]
        }
        cardHost = install(host: host,
                           content: PokemonXCardHostView(state: state, uiState: uiState)) { view, hostView in
            [view.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
             view.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
             view.topAnchor.constraint(equalTo: hostView.topAnchor),
             view.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)]
        }
        // STAGE1-X DIAGNOSTIC (v1): top-edge strip, live layout values.
        // Non-interactive so taps fall through to the game; never hidden.
        diagHost = install(host: host,
                           content: PokemonXDiagStripView()) { view, _ in
            [view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
             view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
             view.topAnchor.constraint(equalTo: host.view.topAnchor),
             view.heightAnchor.constraint(equalToConstant: 22)]
        }
        diagHost?.view.isUserInteractionEnabled = false
        // Auto-swap watch: the 1s poll sets enemyActive when a battle
        // starts and clears it when the battle ends. Battle hides the
        // widgets and swaps the row; battle end restores the field row.
        // A battle starting also closes any open card (the row takes
        // over) and clears a screen-open state (a game screen cannot be
        // open when a battle starts — the menu blocks encounters).
        state.$enemyActive
            .receive(on: DispatchQueue.main)
            .sink { foe in
                uiState.isInBattle = foe != nil
                if foe != nil {
                    uiState.openCard = nil
                    uiState.screenOpen = nil
                } else {
                    uiState.showingMoves = false
                }
                updateVisibility()
            }
            .store(in: &cancellables)
        Publishers.CombineLatest3(uiState.$isInBattle, uiState.$screenOpen, uiState.$openCard)
            .receive(on: DispatchQueue.main)
            .sink { _, _, _ in updateVisibility() }
            .store(in: &cancellables)
        updateVisibility()
        state.startPolling()
    }

    /// Installs the guest-memory read callback on the shared bridge, once.
    /// The callback reads through the running libretro core's memory maps
    /// (LibretroCore.readGuestMemoryAtAddress:length:intoBuffer: — applied to
    /// the Libretro submodule by patches/libretro-memory-read.patch). It is a
    /// no-op for the native Citra core (no libretro core running, so reads
    /// fail) and outside battle (the heap base holds no battle structs, so
    /// the species check fails) — in both cases the overlay stays on
    /// placeholder UI instead of showing stale data.
    private static func installMemoryBridgeIfNeeded() {
        guard HUDMemoryBridge.shared().readBytesCallback == nil else { return }
        HUDMemoryBridge.shared().readBytesCallback = { address, outBuffer, length in
            LibretroCore.sharedInstance().readGuestMemory(atAddress: address, length: length, intoBuffer: outBuffer)
        }
    }

    /// Which widgets show right now (auto-swap principle): a card open
    /// hides everything else (the card is modal-ish — X / tap-outside
    /// closes it); a game screen open hides everything but the back
    /// pill; in battle the minimap and sprite box hide and the row shows
    /// battle commands. The card host is fullscreen (its dim must
    /// intercept touches) so it is hidden, not removed, when no card is
    /// open — a hidden view intercepts nothing.
    private static func updateVisibility() {
        DispatchQueue.main.async {
            let cardOpen = uiState.openCard != nil
            let screenOpen = uiState.screenOpen != nil
            let inBattle = uiState.isInBattle
            minimapHost?.view.isHidden = cardOpen || screenOpen || inBattle
            spriteHost?.view.isHidden = cardOpen || screenOpen || inBattle
            rowHost?.view.isHidden = cardOpen || screenOpen
            pillHost?.view.isHidden = !screenOpen
            cardHost?.view.isHidden = !cardOpen
        }
    }

    /// Removes the overlay. Also does not touch the skin or pause state.
    /// The shared state is kept (not discarded) so Nuzlocke runs survive
    /// close/reopen; the overlay UI state is reset so a re-show starts
    /// from the field row.
    static func dismiss() {
        guard rowHost != nil else { return }
        for host in [minimapHost, spriteHost, rowHost, pillHost, cardHost, diagHost] {
            host?.willMove(toParent: nil)
            host?.view.removeFromSuperview()
            host?.removeFromParent()
        }
        minimapHost = nil
        spriteHost = nil
        rowHost = nil
        pillHost = nil
        cardHost = nil
        diagHost = nil
        cancellables.removeAll()
        uiState.openCard = nil
        uiState.screenOpen = nil
        uiState.showingMoves = false
        uiState.isInBattle = false
        uiState.moveSendPending = false
        sharedState?.stopPolling()
    }

    private static func install<Content: View>(host: PlayViewController,
                                               content: Content,
                                               constraints: (UIView, UIView) -> [NSLayoutConstraint]) -> UIHostingController<AnyView> {
        let hosting = UIHostingController(rootView: AnyView(content))
        hosting.view.backgroundColor = .clear
        host.addChild(hosting)
        host.view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(constraints(hosting.view, host.view))
        hosting.didMove(toParent: host)
        return hosting
    }
}

// MARK: - STAGE1-X diagnostic strip (temporary, diagnostic build v1)

/// One-line live readout of the layout diagnostic (see PokemonXDiag):
/// old/new isPokemonX, Azahar, core, title ID, swap, branch that ran.
/// Pinned to the very top edge so it never hides behind the widgets;
/// non-interactive (the hosting view has user interaction disabled) so
/// taps fall through to the game.
struct PokemonXDiagStripView: View {
    @ObservedObject var diag = PokemonXDiag.shared
    var body: some View {
        Text(diag.shortLine)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black.opacity(0.65))
    }
}

// MARK: - Bottom row (field buttons / battle commands / moves)

/// The one slim row along the bottom edge. Field: PARTY / DEX / BAG /
/// BATTLE / GUIDE spread across. Battle: FIGHT / BAG / POKEMON / RUN in
/// the same spot and size; FIGHT swaps to the four moves + back arrow.
/// X-styled white pills with blue borders — the whole overlay must look
/// baked into Pokemon X, like its own battle commands.
struct PokemonXOverlayRowView: View {
    @ObservedObject var state: PokemonXCompanionState
    @ObservedObject var uiState: PokemonXOverlayUIState

    var body: some View {
        if uiState.isInBattle {
            if uiState.showingMoves { moveRow } else { battleCommandRow }
        } else {
            fieldRow
        }
    }

    // MARK: Field row — buttons drive the game's own screens

    private var fieldRow: some View {
        HStack(spacing: 8) {
            rowButton("PARTY") {
                uiState.openCard = nil
                PokemonXGameDriver.openParty()
                uiState.screenOpen = .party
            }
            rowButton("DEX") {
                uiState.openCard = nil
                PokemonXGameDriver.openDex()
                uiState.screenOpen = .dex
            }
            bagButton
            rowButton("BATTLE") {
                uiState.openCard = uiState.openCard == .battle ? nil : .battle
            }
            rowButton("GUIDE") {
                uiState.openCard = uiState.openCard == .guide ? nil : .guide
            }
        }
    }

    /// BAG is an icon button (like PokeDaisy's bottom-right BAG): a small
    /// bag glyph + "BAG" label, with a live count badge (total items in
    /// the bag, when the bag read is live).
    private var bagButton: some View {
        Button(action: {
            uiState.openCard = nil
            PokemonXGameDriver.openBag()
            uiState.screenOpen = .bag
        }) {
            HStack(spacing: 4) {
                PokemonXBagGlyph()
                    .frame(width: 18, height: 18)
                Text("BAG")
                    .font(PokemonXXStyle.labelFont(15))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(PokemonXXStyle.panel)
            .foregroundColor(PokemonXXStyle.deepBlue)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PokemonXXStyle.blue, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            .overlay(alignment: .topTrailing) {
                if state.bagIsLive {
                    Text("\(bagTotalCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -6)
                }
            }
        }
    }

    private var bagTotalCount: Int {
        state.bagPockets.flatMap { $0.entries }.reduce(0) { $0 + $1.count }
    }

    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(PokemonXXStyle.labelFont(15))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(PokemonXXStyle.panel)
                .foregroundColor(PokemonXXStyle.deepBlue)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(PokemonXXStyle.blue, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: Battle command row — one slim row, nothing over the battle scene

    private var battleCommandRow: some View {
        HStack(spacing: 8) {
            rowButton("FIGHT") { uiState.showingMoves = true }
                .disabled(uiState.moveSendPending)
            rowButton("BAG") {
                PokemonXTouchSender.send(point: PokemonXTouchSender.Battle.bag)
                uiState.screenOpen = .battleBag
            }
            .disabled(uiState.moveSendPending)
            rowButton("POKEMON") {
                PokemonXTouchSender.send(point: PokemonXTouchSender.Battle.pokemon)
                uiState.screenOpen = .battleParty
            }
            .disabled(uiState.moveSendPending)
            rowButton("RUN") {
                PokemonXTouchSender.send(point: PokemonXTouchSender.Battle.run)
            }
            .disabled(uiState.moveSendPending)
        }
    }

    // MARK: Move row — four live moves + back arrow, same slim row

    private var moveRow: some View {
        HStack(spacing: 6) {
            Button(action: { uiState.showingMoves = false }) {
                Text("‹")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(width: 36, height: 46)
                    .background(PokemonXXStyle.panel)
                    .foregroundColor(PokemonXXStyle.deepBlue)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(PokemonXXStyle.blue, lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            }
            .disabled(uiState.moveSendPending)
            ForEach(state.battleMoves) { slot in
                moveChip(for: slot)
            }
        }
    }

    /// Move chip: live name + PP, driven by the battle read. Slot 3 has
    /// NO measured centre — shown greyed and disabled, never a guessed
    /// point. The best pick gets the gold highlight.
    private func moveChip(for slot: PokemonXBattleMoveSlot) -> some View {
        let isSlot3 = slot.id == 3
        let isBest = state.bestMoveIndex == slot.id
        return Button(action: {
            guard slot.name != nil, !isSlot3 else { return }
            uiState.moveSendPending = true
            PokemonXTouchSender.sendMove(slotId: slot.id)
            // After a move is picked the row goes back to commands for
            // the next turn (~1.8s: the move tap fires at +1.0s).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                uiState.showingMoves = false
                uiState.moveSendPending = false
            }
        }) {
            VStack(spacing: 1) {
                Text(slot.name ?? "—")
                    .font(PokemonXXStyle.labelFont(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let pp = slot.currentPP, let maxPP = slot.maxPP {
                    Text("PP \(pp)/\(maxPP)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(PokemonXXStyle.deepBlue.opacity(0.7))
                } else {
                    Text(isSlot3 ? "unmeasured" : "PP —")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(PokemonXXStyle.deepBlue.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(isBest ? PokemonXXStyle.gold.opacity(0.85) : PokemonXXStyle.panel)
            .foregroundColor(PokemonXXStyle.deepBlue)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isBest ? PokemonXXStyle.gold : PokemonXXStyle.blue, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            .opacity(isSlot3 || slot.name == nil ? 0.55 : 1.0)
        }
        .disabled(isSlot3 || slot.name == nil || uiState.moveSendPending)
    }
}

// MARK: - Minimap widget (top-right)

/// Small minimap in the top-right corner, like PokeDaisy's: a schematic
/// Kalos map with a small area label under it. Tap to expand to the full
/// map card (the in-game Town Map is blocked — see the file header).
struct PokemonXMinimapWidgetView: View {
    @ObservedObject var state: PokemonXCompanionState
    @ObservedObject var uiState: PokemonXOverlayUIState

    var body: some View {
        Button(action: { uiState.openCard = .map }) {
            VStack(spacing: 2) {
                ZStack {
                    Color(red: 0.72, green: 0.84, blue: 0.94)
                    KalosLandmassShape()
                        .fill(Color(red: 0.55, green: 0.75, blue: 0.55))
                    ForEach(Array(PokemonXCompanionCardView.kalosTowns.enumerated()), id: \.offset) { _, town in
                        Circle()
                            .fill(PokemonXXStyle.deepBlue)
                            .frame(width: 4, height: 4)
                            .position(x: 124 * town.x, y: 72 * town.y)
                    }
                }
                .frame(width: 124, height: 72)
                .cornerRadius(8)
                Text(state.mapPosition?.areaLabel ?? "Kalos")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(PokemonXXStyle.deepBlue)
                    .lineLimit(1)
                    .frame(width: 124)
            }
            .padding(4)
            .background(PokemonXXStyle.panel)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PokemonXXStyle.blue, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Party sprite box (bottom-left)

/// Small dark rounded square with the lead Pokemon's sprite + HP bar,
/// like PokeDaisy's. Tap to open the game's own party screen. Shows a
/// Pokeball placeholder until the party read goes live — never a
/// placeholder Pokemon.
struct PokemonXSpriteBoxView: View {
    @ObservedObject var state: PokemonXCompanionState
    @ObservedObject var uiState: PokemonXOverlayUIState

    private var leadSlot: PokemonXPartySlot? {
        state.partySlots.first(where: { $0.speciesName != nil })
    }

    /// Dex id for the lead Pokemon's sprite, via the same name lookup
    /// the party detail used. Nil when there is no live party yet.
    private var leadSpeciesId: Int? {
        guard let name = leadSlot?.speciesName else { return nil }
        return PokemonXCompanionData.pokemon.first(where: { $0.name == name.lowercased() })?.id
    }

    var body: some View {
        Button(action: {
            uiState.openCard = nil
            PokemonXGameDriver.openParty()
            uiState.screenOpen = .party
        }) {
            VStack(spacing: 2) {
                PokemonXSpriteView(speciesId: leadSpeciesId)
                    .frame(width: 48, height: 48)
                if let hp = leadSlot?.currentHP, let max = leadSlot?.maxHP, max > 0 {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(PokemonXXStyle.hpColor(fraction: Double(hp) / Double(max)))
                            .frame(width: geo.size.width * CGFloat(hp) / CGFloat(max))
                    }
                    .frame(width: 56, height: 5)
                    .background(Color.white.opacity(0.25))
                    .cornerRadius(2.5)
                    Text("Lv. \(leadSlot?.level ?? 0)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                } else {
                    Text("No party yet")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(width: 72, height: 84)
            .background(Color(red: 0.13, green: 0.13, blue: 0.16).opacity(0.92))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Back pill (a game screen is open)

/// Tiny pill while one of the game's own screens is open: the overlay
/// got out of the way, and this is the way back. Tapping it sends B
/// presses to back out of the in-game screen (2 for field screens, 1
/// for in-battle bag/party) and restores the field / battle row.
struct PokemonXBackPillView: View {
    @ObservedObject var uiState: PokemonXOverlayUIState

    var body: some View {
        Button(action: {
            guard let screen = uiState.screenOpen else { return }
            uiState.screenOpen = nil
            PokemonXGameDriver.backOut(levels: screen.backPresses)
        }) {
            HStack(spacing: 4) {
                Text("‹")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Back to game")
                    .font(PokemonXXStyle.labelFont(14))
            }
            .frame(width: 150, height: 40)
            .background(PokemonXXStyle.panel)
            .foregroundColor(PokemonXXStyle.deepBlue)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(PokemonXXStyle.blue, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Popup cards (GUIDE / MAP fallback / BATTLE info)

/// Fullscreen host for the one open card: a light dim (tap outside to
/// close) with a small centered X-styled card over the game — the game
/// stays visible around it. Only one card ever opens; opening a card
/// hides the row and widgets until it closes.
struct PokemonXCardHostView: View {
    @ObservedObject var state: PokemonXCompanionState
    @ObservedObject var uiState: PokemonXOverlayUIState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .onTapGesture { uiState.openCard = nil }
                if let card = uiState.openCard {
                    PokemonXCompanionCardView(state: state, uiState: uiState, card: card)
                        .frame(maxWidth: min(520, geo.size.width - 48), maxHeight: geo.size.height * 0.78)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// The card itself: X-blue header strip with title + close, white body
/// with the reused tab content. Party / Bag / Dex have no card — those
/// buttons open the game's own screens instead.
struct PokemonXCompanionCardView: View {
    @ObservedObject var state: PokemonXCompanionState
    @ObservedObject var uiState: PokemonXOverlayUIState
    var card: PokemonXOverlayCard

    @State private var selectedMapTown: String?
    @State private var lastBallNote: String?

    private var title: String {
        switch card {
        case .guide: return "Guide"
        case .map: return "Map"
        case .battle: return "Battle"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(PokemonXXStyle.labelFont(17))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { uiState.openCard = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(PokemonXXStyle.blue)
            ScrollView {
                switch card {
                case .map: mapCard
                case .battle: battleCard
                case .guide: guideCard
                }
            }
        }
        .background(PokemonXXStyle.panel)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PokemonXXStyle.blue, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.30), radius: 12, x: 0, y: 4)
    }

    // MARK: Map card (fallback — the in-game Town Map is blocked)

    /// Town coordinates from KALOS-MAP-COORDS.md (normalized 0.0–1.0,
    /// x = east, y = south). Schematic reference positions, not ROM art.
    static let kalosTowns: [(name: String, short: String, x: CGFloat, y: CGFloat)] = [
        ("Vaniville Town", "VA", 0.30, 0.82),
        ("Aquacorde Town", "AQ", 0.36, 0.76),
        ("Santalune City", "SA", 0.36, 0.60),
        ("Lumiose City", "LU", 0.50, 0.55),
        ("Camphrier Town", "CA", 0.38, 0.55),
        ("Ambrette Town", "AM", 0.28, 0.68),
        ("Cyllage City", "CY", 0.24, 0.50),
        ("Geosenge Town", "GE", 0.30, 0.38),
        ("Shalour City", "SH", 0.22, 0.30),
        ("Coumarine City", "CO", 0.33, 0.48),
        ("Laverre City", "LA", 0.55, 0.32),
        ("Dendemille Town", "DE", 0.68, 0.30),
        ("Anistar City", "AN", 0.70, 0.48),
        ("Couriway Town", "CU", 0.66, 0.66),
        ("Snowbelle City", "SN", 0.84, 0.42),
        ("Kiloude City", "KI", 0.58, 0.88),
        ("Pokemon League", "PL", 0.42, 0.28),
    ]

    /// Whether this town is the live position. ALWAYS false for now: the
    /// map-ID -> town mapping was DISPROVED (HUNTS-REPORT-2026-11-19.md
    /// §0d — Route 1 also reads map ID 2, so the old 0=Vaniville /
    /// 8=Aquacorde table is untrusted), so there is no town to plot the
    /// dot on. The grid coords are local to each map, never global.
    /// Re-enable only when a confirmed mapping lands.
    private func isLiveTown(_ town: (name: String, short: String, x: CGFloat, y: CGFloat)) -> Bool {
        _ = town
        return false
    }

    private var kalosMapDrawing: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.72, green: 0.84, blue: 0.94)
                KalosLandmassShape()
                    .fill(Color(red: 0.55, green: 0.75, blue: 0.55))
                ForEach(Array(Self.kalosTowns.enumerated()), id: \.offset) { _, town in
                    Button(action: { selectedMapTown = town.name }) {
                        HStack(spacing: 2) {
                            Circle()
                                .fill(isLiveTown(town) ? PokemonXXStyle.gold : PokemonXXStyle.deepBlue)
                                .frame(width: isLiveTown(town) ? 11 : 7, height: isLiveTown(town) ? 11 : 7)
                            Text(town.short)
                                .font(.system(size: 9))
                                .fontWeight(isLiveTown(town) ? .bold : .regular)
                                .foregroundColor(.primary)
                        }
                    }
                    .position(x: geo.size.width * town.x, y: geo.size.height * town.y)
                }
            }
        }
        .frame(height: 280)
        .cornerRadius(10)
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            noLiveDataNote(text: "The in-game Town Map opens here for now: the Town Map item is not in your bag yet at this point in the story, so the map button cannot drive the game's own Town Map yet. It will once the item is obtained.")
            noLiveDataNote(text: state.mapStatus)
            kalosMapDrawing
            if let position = state.mapPosition {
                Text("\(position.areaLabel) — tile (\(Int(position.gridX)), \(Int(position.gridZ)))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Map id \(position.mapId) (unconfirmed) · secondary id \(position.secondaryMapId).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !state.mapDotVisible {
                    Text("No dot for this map — the map-id-to-town mapping is unconfirmed (Route 1 also reads map id 2).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No live position yet — walk around in the field to see where you are.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let town = selectedMapTown {
                Text(town)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text("Towns")
                .font(.headline)
            ForEach(Array(Self.kalosTowns.enumerated()), id: \.offset) { _, town in
                Button(action: { selectedMapTown = town.name }) {
                    Text(town.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                Divider()
            }
        }
        .padding(12)
    }

    // MARK: Battle card (live battle info; sends only during a live battle)

    private var battleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Guarded on enemyActive, not just isLiveDataAvailable: the
            // field party read makes isLiveDataAvailable true outside
            // battle, and a FIGHT tap sent to the field bottom screen
            // (PSS) would be a live-but-wrong send. The card is closed
            // automatically when a battle starts, so this live branch is
            // for a battle that began while the card was already open.
            if let foe = state.enemyActive {
                HStack {
                    Text("Opponent")
                        .font(.headline)
                    Spacer()
                    if let name = foe.speciesName { Text(name) }
                    if let level = foe.level { Text("Lv. \(level)") }
                    if let hp = foe.currentHP, let max = foe.maxHP {
                        Text("HP \(hp)/\(max)")
                    }
                }
                .padding(12)
                .background(PokemonXXStyle.lightBlue)
                .cornerRadius(10)
                Text("Foe team")
                    .font(.headline)
                ForEach(Array(state.enemyTeam.enumerated()), id: \.offset) { index, slot in
                    HStack {
                        Text("Slot \(index + 1)")
                            .font(.subheadline)
                        Spacer()
                        if let foeSlot = slot {
                            if let name = foeSlot.speciesName { Text(name) }
                            if let level = foeSlot.level { Text("Lv. \(level)") }
                        } else {
                            Text("unknown")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text(state.activeBattlerNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let bestIndex = state.bestMoveIndex,
                   bestIndex < state.battleMoves.count,
                   let score = state.bestMoveScore {
                    Text("Best pick: \(state.battleMoves[bestIndex].name ?? "Move \(bestIndex + 1)") (score \(Int(score)))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                // Four move slots, 2 x 2, like the bottom-screen move list.
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(state.battleMoves) { slot in
                        moveButton(for: slot)
                    }
                }
                Text("Growl and Vine Whip positions are estimated, not lab-measured.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    battleActionButton(title: "Fight", point: PokemonXTouchSender.Battle.fight)
                    battleActionButton(title: "Pokemon", point: PokemonXTouchSender.Battle.pokemon)
                    battleActionButton(title: "Bag", point: PokemonXTouchSender.Battle.bag)
                    battleActionButton(title: "Run", point: PokemonXTouchSender.Battle.run)
                }
                if let slot = state.switchSuggestionSlot,
                   let note = state.switchSuggestionNote {
                    Text(note)
                        .font(.subheadline)
                    Text("To switch: tap POKEMON, then tap slot \(slot + 1) in the game menu. One-tap switch is not built — party-menu slot centres are unmeasured (G13).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let lastBall = lastBallAvailable {
                    let ballName = PokemonXCompanionData.displayItemName(forGameId: lastBall.gameId)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last ball: \(ballName)" + (lastBall.count.map { " ×\($0)" } ?? ""))
                            .font(.headline)
                        Text("Wild battles only — the game refuses it against a trainer.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(action: { sendLastBall(gameId: lastBall.gameId) }) {
                            Text("Use \(ballName) again")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(PokemonXXStyle.gold.opacity(0.35))
                                .cornerRadius(10)
                        }
                        if let note = lastBallNote {
                            Text(note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                // G11 Mega / G12 multi-target: NOT built — no Mega button
                // centre measured, no target centres measured for double /
                // horde battles. No buttons for either.
            } else {
                noLiveDataNote(text: "No live battle yet. The four move slots and the Fight / Pokemon / Bag / Run buttons will light up once the companion can read the battle state. They do nothing yet — tapping them sends nothing to the game.")
            }
        }
        .padding(12)
    }

    /// Effectiveness of one move vs the active foe's types, computed live
    /// from the move's type and enemyActive.types. Falls back to the
    /// model-computed value when the foe's types are unknown.
    private func moveEffectiveness(_ move: PokemonXBattleMoveSlot) -> Double? {
        guard let type = move.type,
              let foeTypes = state.enemyActive?.types,
              !foeTypes.isEmpty else { return move.effectiveness }
        return PokemonXCompanionData.effectiveness(attacking: type, defending: foeTypes)
    }

    private func effectivenessLabel(_ value: Double) -> String {
        switch value {
        case 0: return "0x"
        case 0.25: return "0.25x"
        case 0.5: return "0.5x"
        case 1: return "1x"
        case 2: return "2x"
        case 4: return "4x"
        default: return String(format: "%.2gx", value)
        }
    }

    private func moveButton(for slot: PokemonXBattleMoveSlot) -> some View {
        // Slot 3 (id 3) has NO measured centre — disabled with honest text.
        // Never send a guessed point for it. Also disabled outside a live
        // battle (see battleCard) so no tap ever goes to the field screen.
        let isSlot3 = slot.id == 3
        let inBattle = state.enemyActive != nil
        return Button(action: {
            guard inBattle else { return }
            PokemonXTouchSender.sendMove(slotId: slot.id)
        }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name ?? "Move \(slot.id + 1)")
                    .font(.headline)
                Text(slot.type?.capitalized ?? "Type: —")
                    .font(.caption)
                if let power = slot.power {
                    Text("Power \(power)")
                        .font(.caption)
                }
                if let pp = slot.currentPP, let maxPP = slot.maxPP {
                    Text("PP \(pp)/\(maxPP)")
                        .font(.caption)
                }
                if let effectiveness = moveEffectiveness(slot) {
                    Text("vs foe: \(effectivenessLabel(effectiveness))")
                        .font(.caption)
                        .fontWeight(effectiveness >= 2 ? .bold : .regular)
                }
                if state.bestMoveIndex == slot.id {
                    Text("Best pick")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                if isSlot3 {
                    Text("Position unmeasured — disabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(state.bestMoveIndex == slot.id ? PokemonXXStyle.gold.opacity(0.35) : PokemonXXStyle.lightBlue)
            .cornerRadius(10)
        }
        .disabled(isSlot3 || slot.name == nil || !inBattle)
    }

    private func battleActionButton(title: String, point: CGPoint) -> some View {
        Button(action: { PokemonXTouchSender.send(point: point) }) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(PokemonXXStyle.blue.opacity(0.12))
                .cornerRadius(10)
        }
        .disabled(state.enemyActive == nil)
    }

    /// The last ball is offered ONLY when lastBallGameId != nil, the foe
    /// team has exactly one populated slot (one foe), and the party has a
    /// free slot — wild battles only, with room to catch.
    private var lastBallAvailable: (gameId: Int, count: Int?)? {
        guard let gameId = state.lastBallGameId else { return nil }
        guard state.enemyTeam.compactMap({ $0 }).count == 1 else { return nil }
        guard state.partySlots.contains(where: { $0.isKnownEmpty || $0.speciesName == nil }) else { return nil }
        return (gameId, state.lastBallCount)
    }

    private func sendLastBall(gameId: Int) {
        // Only BAG is sent: the Poke Balls pocket / item-row / USE / target
        // flow is UNMEASURED (only the Medicine/Potion flow was measured),
        // so the rest is finished by the player in the game menu. Do not
        // fake the unmeasured steps.
        PokemonXTouchSender.send(point: PokemonXTouchSender.Battle.bag)
        let ballName = PokemonXCompanionData.displayItemName(forGameId: gameId)
        lastBallNote = "Sent BAG. In the game menu tap Poke Balls, then \(ballName), then USE."
        // Re-record the same ball so the remembered ball and its count
        // refresh from the latest live bag poll; the actual in-game USE is
        // the player's tap in the game menu, not this button.
        state.recordLastBall(gameId: gameId)
    }

    // MARK: Guide card (static bosses + STUCK? + live area encounters)

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.guideAreaEncounters.isEmpty {
                Text("What's in this area — \(state.mapAreaLabel)")
                    .font(.headline)
                ForEach(state.guideAreaEncounters) { encounter in
                    HStack {
                        Text(encounter.speciesName.capitalized)
                            .font(.subheadline)
                        Spacer()
                        Text(encounterSummary(encounter))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            Text("Gym Leaders")
                .font(.headline)
            ForEach(Array(PokemonXGuideData.gymLeaders.enumerated()), id: \.offset) { _, leader in
                bossTeamView(leader)
            }
            Text("Elite Four")
                .font(.headline)
            ForEach(Array(PokemonXGuideData.eliteFour.enumerated()), id: \.offset) { _, member in
                bossTeamView(member)
            }
            Text("Champion")
                .font(.headline)
            bossTeamView(PokemonXGuideData.champion)
            Text("Stuck?")
                .font(.headline)
            ForEach(PokemonXGuideData.stuckEntries, id: \.self) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(entry.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
    }

    private func bossTeamView(_ team: PokemonXGuideData.BossTeam) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(team.name) — \(team.place)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(team.team.map { "\($0.species) Lv. \($0.level)" }.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PokemonXXStyle.lightBlue)
        .cornerRadius(8)
    }

    private func encounterSummary(_ encounter: PokemonXGuideEncounter) -> String {
        var parts: [String] = [encounter.method]
        if let min = encounter.minLevel, let max = encounter.maxLevel {
            parts.append(min == max ? "Lv. \(min)" : "Lv. \(min)–\(max)")
        } else if let min = encounter.minLevel {
            parts.append("Lv. \(min)+")
        }
        if let chance = encounter.chance { parts.append("\(chance)%") }
        return parts.joined(separator: " · ")
    }

    // MARK: Shared bits

    private func noLiveDataNote(text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PokemonXXStyle.lightBlue)
            .cornerRadius(8)
    }
}

// MARK: - Sprites (real PokeAPI X/Y sprites, cached)

/// Loads one Pokemon sprite from PokeAPI (the X/Y sprite set first,
/// then the default front sprite), cached in memory + on disk. Shows
/// nothing until the load succeeds — the caller draws a Pokeball
/// placeholder meanwhile.
private final class PokemonXSpriteLoader: ObservableObject {
    @Published var image: UIImage?
    private static let memoryCache = NSCache<NSNumber, UIImage>()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024,
                                   diskCapacity: 100 * 1024 * 1024,
                                   diskPath: "pokemon-x-sprites")
        return URLSession(configuration: config)
    }()

    func load(id: Int) {
        if let cached = Self.memoryCache.object(forKey: NSNumber(value: id)) {
            image = cached
            return
        }
        let xyURL = URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-vi/x-y/\(id).png")!
        let fallbackURL = URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(id).png")!
        Self.session.dataTask(with: xyURL) { [weak self] data, _, _ in
            if let data, let loaded = UIImage(data: data) {
                self?.finish(id: id, image: loaded)
            } else {
                Self.session.dataTask(with: fallbackURL) { [weak self] fallbackData, _, _ in
                    guard let fallbackData, let loaded = UIImage(data: fallbackData) else { return }
                    self?.finish(id: id, image: loaded)
                }.resume()
            }
        }.resume()
    }

    private func finish(id: Int, image: UIImage) {
        Self.memoryCache.setObject(image, forKey: NSNumber(value: id))
        DispatchQueue.main.async { [weak self] in
            self?.image = image
        }
    }
}

/// A Pokemon sprite by Dex id, or a Pokeball placeholder while it loads
/// / when there is no Pokemon yet. Nearest-neighbour scaling keeps the
/// pixel art crisp.
struct PokemonXSpriteView: View {
    let speciesId: Int?
    @StateObject private var loader = PokemonXSpriteLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                PokemonXPokeballGlyph()
            }
        }
        .onAppear {
            if let id = speciesId { loader.load(id: id) }
        }
        .onChange(of: speciesId) { id in
            loader.image = nil
            if let id { loader.load(id: id) }
        }
    }
}

/// Simple Pokeball glyph (red top, white bottom, black band + button).
struct PokemonXPokeballGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
            Circle()
                .fill(Color(red: 0.90, green: 0.20, blue: 0.20))
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        Spacer()
                    }
                )
            Rectangle()
                .fill(Color.black)
                .frame(height: 3)
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.black, lineWidth: 2))
        }
        .clipShape(Circle())
    }
}

/// Simple backpack glyph for the BAG button (brown body, top handle,
/// front pocket, clasp) — the bag icon from the game's own menu.
struct PokemonXBagGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.55, green: 0.35, blue: 0.15))
                .frame(width: 16, height: 14)
                .offset(y: 2)
            Path { path in
                path.move(to: CGPoint(x: 5, y: 7))
                path.addQuadCurve(to: CGPoint(x: 13, y: 7), control: CGPoint(x: 9, y: 0))
            }
            .stroke(Color(red: 0.55, green: 0.35, blue: 0.15), lineWidth: 2.5)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.72, green: 0.50, blue: 0.25))
                .frame(width: 10, height: 7)
                .offset(y: 5)
            Circle()
                .fill(Color(red: 0.95, green: 0.80, blue: 0.30))
                .frame(width: 3, height: 3)
                .offset(y: 2)
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - Schematic Kalos landmass (hand-built, not ROM art)

private struct KalosLandmassShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.24, y: h * 0.34))
        path.addQuadCurve(to: CGPoint(x: w * 0.40, y: h * 0.14), control: CGPoint(x: w * 0.26, y: h * 0.18))
        path.addQuadCurve(to: CGPoint(x: w * 0.66, y: h * 0.16), control: CGPoint(x: w * 0.52, y: h * 0.10))
        path.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.34), control: CGPoint(x: w * 0.82, y: h * 0.18))
        path.addQuadCurve(to: CGPoint(x: w * 0.80, y: h * 0.58), control: CGPoint(x: w * 0.90, y: h * 0.48))
        path.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.80), control: CGPoint(x: w * 0.74, y: h * 0.72))
        path.addQuadCurve(to: CGPoint(x: w * 0.52, y: h * 0.94), control: CGPoint(x: w * 0.58, y: h * 0.90))
        path.addQuadCurve(to: CGPoint(x: w * 0.34, y: h * 0.88), control: CGPoint(x: w * 0.40, y: h * 0.96))
        path.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.62), control: CGPoint(x: w * 0.24, y: h * 0.78))
        path.addQuadCurve(to: CGPoint(x: w * 0.24, y: h * 0.34), control: CGPoint(x: w * 0.18, y: h * 0.48))
        path.closeSubpath()
        return path
    }
}
