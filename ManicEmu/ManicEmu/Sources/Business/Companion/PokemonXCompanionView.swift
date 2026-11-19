//
//  PokemonXCompanionView.swift
//  ManicEmu
//
//  PokeDaisy-style companion overlay for Pokemon X — RIGHT-DOCKED side
//  panel (Garrett's design, 2026-11-19): ONE persistent screen, no
//  switching back and forth. The top screen fills the iPhone landscape
//  width minus this 320pt panel; the panel stays open persistently — the
//  only way out is the Close button in the header. No dimmed background,
//  no tap-outside-to-close, opaque system background.
//
//  Tabs: Party / Bag / Map / Dex / Battle / Guide / Nuzlocke / Card.
//  The Tab enum lives in PokemonXCompanionModels.swift and has only the
//  five original tabs (another agent owns that file), so the three new
//  tabs are a VIEW-LOCAL selection (PokemonXPanelTab below) mapped onto
//  state.selectedTab for the five state tabs. Party is LIVE (species,
//  level, HP) and the Battle tab shows live moves plus the active
//  opponent, read from the verified battle structs through
//  HUDMemoryBridge — never filled with invented Pokemon, moves or HP.
//  Bag and Map are LIVE reads too (guard-checked every poll). The Dex is
//  the full 721-species Gen 1-6 Pokedex from static PokeAPI data.
//
//  BATTLE SENDS (via PokemonXTouchSender ONLY — never the 1280x720 lab
//  coords in PokemonXBattleFlow): FIGHT / POKEMON / BAG / RUN send their
//  measured Battle constants. A move tap sends FIGHT first, then the
//  move-slot point after ~1s so the game opens the move list. Move slot
//  3 has NO measured centre — its button is disabled, never a guessed
//  point. Growl / Vine Whip positions are ESTIMATED, not lab-measured.
//  Mega (G11) and multi-target (G12) are NOT built: no buttons, no
//  centres measured. One-tap switch-to-slot is NOT built (party-menu
//  slot centres unmeasured, G13) — the switch suggestion is text only.
//  The last-ball replay sends BAG only: the Poke Balls pocket/item/USE
//  flow is UNMEASURED (only Medicine/Potion was measured), so the rest
//  is finished by the player in the game menu — never faked.
//
//  MULTI-INPUT (Switch-style, per Garrett):
//  - Controller (GameSir X5 Lite) keeps driving the game — movement,
//    menus, battles — through the emulator's controller path the whole
//    time this panel is open. The panel never pauses the game.
//  - Touch (iPhone screen) drives THIS panel: tap Party / Bag / Map /
//    Dex / Battle / Guide / Nuzlocke / Card and the buttons inside it.
//    These are native SwiftUI buttons on a native layer on top of the
//    game, not the emulated bottom touch screen.
//  - The on-screen emulator controls stay hidden while the panel is
//    open: presenting this panel never calls forceFullSkin(false) /
//    showSkinButtons and never touches the skin.
//
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import SwiftUI
import UIKit

// MARK: - Presenter (docked side panel on top of the game)

enum PokemonXCompanionPresenter {
    private static weak var hostingController: UIHostingController<PokemonXCompanionView>?
    /// Shared state, kept across close/reopen so Nuzlocke runs (and the
    /// remembered last ball) survive dismissing the panel.
    private static var sharedState: PokemonXCompanionState?

    /// Presents the companion as a right-docked 320pt panel. Deliberately
    /// does NOT pause emulation, does NOT change forceFullSkin, and does
    /// NOT show the skin buttons — so the controller keeps working and
    /// hidden on-screen controls stay hidden while the panel is up.
    /// Shrinks the game view FIRST (setCompanionPanelOpen), then docks
    /// the panel into the freed space.
    static func present() {
        guard let host = PlayViewController.currentPlayViewController else { return }
        guard hostingController == nil else { return }
        installMemoryBridgeIfNeeded()
        let state: PokemonXCompanionState
        if let existing = sharedState {
            state = existing
        } else {
            let fresh = PokemonXCompanionState()
            sharedState = fresh
            state = fresh
        }
        host.setCompanionPanelOpen(true)
        let view = PokemonXCompanionView(state: state, onClose: { dismiss() })
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .systemBackground
        host.addChild(hosting)
        host.view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            hosting.view.widthAnchor.constraint(equalToConstant: PokemonXCompanionPanelWidth),
            hosting.view.topAnchor.constraint(equalTo: host.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        hosting.didMove(toParent: host)
        hostingController = hosting
        state.startPolling()
    }

    /// Installs the guest-memory read callback on the shared bridge, once.
    /// The callback reads through the running libretro core's memory maps
    /// (LibretroCore.readGuestMemoryAtAddress:length:intoBuffer: — applied to
    /// the Libretro submodule by patches/libretro-memory-read.patch). It is a
    /// no-op for the native Citra core (no libretro core running, so reads
    /// fail) and outside battle (the heap base holds no battle structs, so
    /// the species check fails) — in both cases the companion stays on
    /// placeholder UI instead of showing stale data.
    private static func installMemoryBridgeIfNeeded() {
        guard HUDMemoryBridge.shared().readBytesCallback == nil else { return }
        HUDMemoryBridge.shared().readBytesCallback = { address, outBuffer, length in
            LibretroCore.sharedInstance().readGuestMemory(atAddress: address, length: length, intoBuffer: outBuffer)
        }
    }

    /// Dismisses the panel and restores the game view to full width.
    /// Also does not touch the skin or pause state. The shared state is
    /// kept (not discarded) so Nuzlocke runs survive close/reopen.
    static func dismiss() {
        guard let hosting = hostingController else { return }
        hostingController = nil
        sharedState?.stopPolling()
        hosting.willMove(toParent: nil)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
        PlayViewController.currentPlayViewController?.setCompanionPanelOpen(false)
    }
}

// MARK: - Panel tabs (view-local; Models.swift owns only the five state tabs)

/// All eight panel tabs. The five original tabs map onto
/// PokemonXCompanionState.Tab (state.selectedTab); guide / nuzlocke /
/// card exist ONLY here — the Tab enum in Models.swift cannot gain cases
/// without editing that file, which is another agent's. The tab bar sets
/// both this selection and state.selectedTab for the five mapped tabs.
private enum PokemonXPanelTab: String, CaseIterable, Identifiable {
    case party, bag, map, dex, battle, guide, nuzlocke, card
    var id: String { rawValue }
    var title: String {
        switch self {
        case .party: return "Party"
        case .bag: return "Bag"
        case .map: return "Map"
        case .dex: return "Dex"
        case .battle: return "Battle"
        case .guide: return "Guide"
        case .nuzlocke: return "Nuzlocke"
        case .card: return "Card"
        }
    }
    /// The matching state tab, or nil for the three view-local tabs.
    var stateTab: PokemonXCompanionState.Tab? {
        switch self {
        case .party: return .party
        case .bag: return .bag
        case .map: return .map
        case .dex: return .dex
        case .battle: return .battle
        case .guide, .nuzlocke, .card: return nil
        }
    }
}

// MARK: - Panel view

struct PokemonXCompanionView: View {
    @ObservedObject var state: PokemonXCompanionState
    var onClose: () -> Void

    @State private var panelTab: PokemonXPanelTab = .party
    @State private var dexSearchText = ""
    @State private var selectedDexPokemon: PokemonXStaticPokemon?
    @State private var selectedMapTown: String?
    @State private var newRunName = ""
    @State private var catchSpecies = ""
    @State private var catchArea = ""
    @State private var lastBallNote: String?

    // Pokemon X menu palette: navy header, white cards, pink battle accent.
    private let navy = Color(red: 0.12, green: 0.22, blue: 0.42)
    private let pink = Color(red: 0.96, green: 0.62, blue: 0.78)

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            ScrollView {
                switch panelTab {
                case .party: partyTab
                case .bag: bagTab
                case .map: mapTab
                case .dex: dexTab
                case .battle: battleTab
                case .guide: guideTab
                case .nuzlocke: nuzlockeTab
                case .card: cardTab
                }
            }
            multiInputFooter
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Companion — Pokemon X")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(state.bridgeStatus)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            Button(action: onClose) {
                Text("Close")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(navy)
    }

    // MARK: Tab bar (8 tabs in 320pt — horizontally scrollable, compact)

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(PokemonXPanelTab.allCases) { tab in
                    Button(action: { selectTab(tab) }) {
                        Text(tab.title)
                            .font(.subheadline)
                            .fontWeight(panelTab == tab ? .bold : .regular)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(panelTab == tab ? navy.opacity(0.12) : Color.clear)
                            .foregroundColor(panelTab == tab ? navy : .primary)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
    }

    private func selectTab(_ tab: PokemonXPanelTab) {
        panelTab = tab
        if let stateTab = tab.stateTab { state.selectedTab = stateTab }
    }

    // MARK: Party tab (live battle party; tap a slot for detail)

    private var partyTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let detail = state.selectedPartyDetail {
                partyDetailView(detail)
            } else {
                noLiveDataNote(text: state.isLiveDataAvailable
                    ? "Live battle data — HP and level update as the battle goes. Tap a Pokemon for stats, moves and what it learns next."
                    : "Your party will appear here once the companion can read the game. No Pokemon are shown yet — nothing here is real data.")
                ForEach(state.partySlots) { slot in
                    Button(action: {
                        if slot.speciesName != nil { state.selectedPartySlotIndex = slot.id }
                    }) {
                        HStack {
                            Text("Slot \(slot.id + 1)")
                                .font(.headline)
                            Spacer()
                            if let name = slot.speciesName {
                                Text(name)
                                if let level = slot.level { Text("Lv. \(level)") }
                                if let hp = slot.currentHP, let max = slot.maxHP {
                                    Text("HP \(hp)/\(max)")
                                }
                            } else if slot.isKnownEmpty {
                                Text("Empty")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No live data yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .padding(12)
    }

    /// Tap-for-detail for one party slot (G9a): stats from +0xF6, types,
    /// moves with PP, next moves to learn. G9b–G9g (IVs/EVs, status, held
    /// item, ability, nature, EXP) stay unshown — the model fields are
    /// nil and nothing is invented for them.
    private func partyDetailView(_ detail: PokemonXPartyDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: { state.selectedPartySlotIndex = nil }) {
                Text("‹ Back to party")
                    .font(.headline)
                    .foregroundColor(navy)
            }
            Text(detail.speciesName)
                .font(.title3)
                .fontWeight(.bold)
            HStack(spacing: 12) {
                if let level = detail.level { Text("Lv. \(level)") }
                if let hp = detail.currentHP, let max = detail.maxHP {
                    Text("HP \(hp)/\(max)")
                }
            }
            .font(.subheadline)
            if let types = detail.types {
                Text("Types: \(types.map { $0.capitalized }.joined(separator: ", "))")
                    .font(.subheadline)
            }
            if let stats = detail.stats {
                Text("Stats (in battle)")
                    .font(.headline)
                Text("Atk \(stats.attack) · Def \(stats.defense) · SpA \(stats.specialAttack) · SpD \(stats.specialDefense) · Spe \(stats.speed)")
                    .font(.subheadline)
            }
            Text("Moves")
                .font(.headline)
            ForEach(detail.moves) { move in
                HStack {
                    Text(move.name ?? "Move \(move.id + 1)")
                        .font(.subheadline)
                    Spacer()
                    if let pp = move.currentPP, let maxPP = move.maxPP {
                        Text("PP \(pp)/\(maxPP)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            if !detail.nextMovesToLearn.isEmpty {
                Text("Learns next")
                    .font(.headline)
                ForEach(detail.nextMovesToLearn, id: \.self) { entry in
                    Text("Lv. \(entry.level) — \(entry.name.capitalized)")
                        .font(.subheadline)
                }
            }
            Text("IVs, EVs, status, held item, ability, nature and EXP are unknown — those fields are not yet mapped (G9b–G9g), so they are not shown.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: Bag tab (live pockets; no use/give flows in the field)

    private var bagTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            noLiveDataNote(text: state.bagStatus)
            if state.bagIsLive {
                ForEach(state.bagPockets) { pocket in
                    Text(pocket.title)
                        .font(.headline)
                    if pocket.entries.isEmpty {
                        Text("Empty")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(pocket.entries) { entry in
                            HStack {
                                Text(entry.resolvedName ?? "Item #\(entry.gameId)")
                                    .font(.subheadline)
                                Spacer()
                                Text("×\(entry.count)")
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Text("Items can't be used or given from here yet — using an item in the field needs the G7 write path, which is not proven. Use the Bag in the game menu.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No live bag yet — the bag read needs a live game session. Nothing is shown until the read passes its guard check.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: Map tab (schematic Kalos; live dot DISABLED — map-id mapping unconfirmed)

    /// Town coordinates from KALOS-MAP-COORDS.md (normalized 0.0–1.0,
    /// x = east, y = south). Schematic reference positions, not ROM art.
    private static let kalosTowns: [(name: String, short: String, x: CGFloat, y: CGFloat)] = [
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
                                .fill(isLiveTown(town) ? pink : navy)
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

    private var mapTab: some View {
        VStack(alignment: .leading, spacing: 10) {
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

    // MARK: Dex tab (full 721-species Dex + type matchups + locations)

    private var dexTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Full Gen 1–6 Pokedex — 721 Pokemon from PokeAPI. Tap one to see its type matchups and where it is found.")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Search Pokemon", text: $dexSearchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            ForEach(filteredDex) { pokemon in
                Button(action: {
                    selectedDexPokemon = (selectedDexPokemon?.id == pokemon.id) ? nil : pokemon
                }) {
                    HStack {
                        Text("#\(pokemon.id) \(pokemon.name.capitalized)")
                            .font(.subheadline)
                        Spacer()
                        ForEach(pokemon.types, id: \.self) { type in
                            Text(type.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(navy.opacity(0.12))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .foregroundColor(.primary)
                if selectedDexPokemon?.id == pokemon.id {
                    typeMatchupView(for: pokemon)
                }
                Divider()
            }
        }
        .padding(12)
    }

    private var filteredDex: [PokemonXStaticPokemon] {
        let query = dexSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return PokemonXCompanionData.pokemon }
        return PokemonXCompanionData.pokemon.filter {
            $0.name.lowercased().contains(query) || String($0.id) == query
        }
    }

    private func typeMatchupView(for pokemon: PokemonXStaticPokemon) -> some View {
        let weak = PokemonXCompanionData.weaknesses(of: pokemon.types)
        let resistant = PokemonXCompanionData.resistances(of: pokemon.types)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Weak to: \(weak.isEmpty ? "none" : weak.map { $0.capitalized }.joined(separator: ", "))")
                .font(.caption)
            Text("Resistant to: \(resistant.isEmpty ? "none" : resistant.map { $0.capitalized }.joined(separator: ", "))")
                .font(.caption)
            if let detail = PokemonXCompanionData.pokemonDetail(id: pokemon.id),
               !detail.encounterLocations.isEmpty {
                Text("Found in:")
                    .font(.caption)
                    .fontWeight(.semibold)
                ForEach(detail.encounterLocations, id: \.name) { location in
                    Text(PokemonXCompanionData.displayAreaName(location.name))
                        .font(.caption)
                }
            }
            Text("Static type chart (PokeAPI). Not live battle data.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: Battle tab (live battle + sends via PokemonXTouchSender only)

    private var battleTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.isLiveDataAvailable {
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
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                } else {
                    Text("Opponent: no live data yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
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
                // Four move slots, 2 x 2, like the bottom-screen move list —
                // but drawn here, in the panel, so battles stay top-only.
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
                                .background(pink.opacity(0.35))
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
        // Never send a guessed point for it.
        let isSlot3 = slot.id == 3
        return Button(action: { sendMove(slot: slot) }) {
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
            .background(state.bestMoveIndex == slot.id ? pink.opacity(0.55) : pink.opacity(0.25))
            .cornerRadius(10)
        }
        .disabled(isSlot3 || slot.name == nil)
    }

    private func battleActionButton(title: String, point: CGPoint) -> some View {
        Button(action: { PokemonXTouchSender.send(point: point) }) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(navy.opacity(0.15))
                .cornerRadius(10)
        }
        .disabled(!state.isLiveDataAvailable)
    }

    /// Chained send: FIGHT first so the game opens the move list, then the
    /// move-slot point after ~1s (after the 0.7s FIGHT hold has released).
    /// Slot 3 is guarded out — the button is disabled, so this should never
    /// run for it, but no guessed point is ever sent.
    private func sendMove(slot: PokemonXBattleMoveSlot) {
        guard slot.name != nil, slot.id >= 0, slot.id < 3 else { return }
        let movePoints: [CGPoint] = [
            PokemonXTouchSender.Battle.tackle,
            PokemonXTouchSender.Battle.growl,
            PokemonXTouchSender.Battle.vineWhip,
        ]
        PokemonXTouchSender.send(point: PokemonXTouchSender.Battle.fight)
        let point = movePoints[slot.id]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            PokemonXTouchSender.send(point: point)
        }
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

    // MARK: Guide tab (static bosses + STUCK? + live area encounters)

    private var guideTab: some View {
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
        .background(Color(UIColor.secondarySystemBackground))
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

    // MARK: Nuzlocke tab (runs, manual catch log, honest faint limits)

    private var nuzlockeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Faints are detected from battle HP. A faint outside battle needs the field party read (G1) — not detected yet.")
                .font(.caption)
                .foregroundColor(.secondary)
            if let run = state.activeNuzlockeRun {
                Text("Active run: \(run.name)")
                    .font(.headline)
                Text("Catches: \(run.catches.count) · Deaths: \(run.deaths.count)")
                    .font(.subheadline)
                TextField("Species caught", text: $catchSpecies)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Area (e.g. Aquacorde Town)", text: $catchArea)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: {
                    let species = catchSpecies.trimmingCharacters(in: .whitespacesAndNewlines)
                    let area = catchArea.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !species.isEmpty, !area.isEmpty else { return }
                    state.recordNuzlockeCatch(speciesName: species, areaLabel: area)
                    catchSpecies = ""
                    catchArea = ""
                }) {
                    Text("Log catch")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(navy.opacity(0.15))
                        .cornerRadius(10)
                }
                Text("One catch per area — a second catch in the same area is not recorded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !run.catches.isEmpty {
                    Text("Catches")
                        .font(.headline)
                    ForEach(run.catches) { caught in
                        HStack {
                            Text(caught.speciesName)
                                .font(.subheadline)
                            Spacer()
                            Text(caught.areaLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                if !run.deaths.isEmpty {
                    Text("Deaths")
                        .font(.headline)
                    ForEach(run.deaths) { death in
                        HStack {
                            Text(death.speciesName)
                                .font(.subheadline)
                            if let level = death.level { Text("Lv. \(level)") }
                            Spacer()
                            Text(death.areaLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Button(action: { state.endNuzlockeRun() }) {
                    Text("End run")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                }
            } else {
                TextField("Run name", text: $newRunName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: {
                    let name = newRunName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    state.startNuzlockeRun(name: name)
                    newRunName = ""
                }) {
                    Text("Start run")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(navy.opacity(0.15))
                        .cornerRadius(10)
                }
                Text("No active run. Start one to log catches and deaths.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !state.nuzlockeRuns.isEmpty {
                Text("All runs")
                    .font(.headline)
                ForEach(state.nuzlockeRuns) { run in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.name + (run.isActive ? " (active)" : ""))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Catches \(run.catches.count) · Deaths \(run.deaths.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
    }

    // MARK: Card tab (honest all-unknown placeholder)

    private var cardTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            noLiveDataNote(text: PokemonXTrainerCard.unavailableNote)
            cardRow(label: "Player name", value: state.trainerCard.playerName)
            cardRow(label: "Trainer ID", value: state.trainerCard.trainerID)
            cardRow(label: "Money", value: state.trainerCard.money.map { "\($0)" })
            cardRow(label: "Play time", value: state.trainerCard.playTimeMinutes.map { "\($0) min" })
            cardRow(label: "Badges", value: state.trainerCard.badges.map { "\($0)" })
            cardRow(label: "Dex seen", value: state.trainerCard.dexSeen.map { "\($0)" })
            cardRow(label: "Dex caught", value: state.trainerCard.dexCaught.map { "\($0)" })
        }
        .padding(12)
    }

    private func cardRow(label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value ?? "unknown")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: Shared bits

    private func noLiveDataNote(text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.18))
            .cornerRadius(8)
    }

    private var multiInputFooter: some View {
        Text("Controller: keep playing with your GameSir — it still drives the game. Touch: tap here in the companion. On-screen controls stay hidden.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(12)
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
