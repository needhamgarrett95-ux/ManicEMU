//
//  PokemonXCompanionView.swift
//  ManicEmu
//
//  PokeDaisy-style companion overlay for Pokemon X.
//  Party / Bag / Map / Dex / Battle tabs, drawn in Pokemon X's menu style
//  (navy header, white cards, pink battle accent). Party is LIVE (species,
//  level, HP) and the Battle tab shows live moves plus the active opponent,
//  read from the verified battle structs through HUDMemoryBridge — never
//  filled with invented Pokemon, moves or HP. Bag and Map are still
//  placeholders (no verified offsets yet). The Battle tab buttons stay
//  disabled: tapping a move does NOT choose it in battle yet, because the
//  send path (touch synthesis) is blocked in the top-only layout — the
//  core's framebuffer layout has no bottom screen for a tap to land on
//  (see WIRING-REPORT-2026-11-19.md). The Dex tab is the full 721-species
//  Gen 1-6 Pokedex from static PokeAPI reference data.
//
//  MULTI-INPUT (Switch-style, per Garrett):
//  - Controller (GameSir X5 Lite) keeps driving the game — movement, menus,
//    battles — through the emulator's controller path the whole time this
//    overlay is open. The overlay never pauses the game.
//  - Touch (iPhone screen) drives THIS overlay: tap Party / Bag / Map / Dex /
//    Battle and the buttons inside it. These are native SwiftUI buttons on a
//    native layer on top of the game, not the emulated bottom touch screen.
//  - The on-screen emulator controls stay hidden while the overlay is open:
//    presenting this overlay never calls forceFullSkin(false) / showSkinButtons
//    and never touches the skin. Hide Controls (forceFullSkin) hides the skin
//    buttons but leaves the emulator TouchInputView alive — the two touch
//    layers are separate by design (see COMPANION-REPORT-2026-11-18.md).
//
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import SwiftUI
import UIKit

// MARK: - Presenter (native touch layer on top of the game)

enum PokemonXCompanionPresenter {
    private static weak var hostingController: UIHostingController<PokemonXCompanionView>?

    /// Presents the companion overlay on top of the running game.
    /// Deliberately does NOT pause emulation, does NOT change forceFullSkin,
    /// and does NOT show the skin buttons — so the controller keeps working
    /// and hidden on-screen controls stay hidden while the overlay is up.
    static func present() {
        guard let host = PlayViewController.currentPlayViewController else { return }
        guard hostingController == nil else { return }
        installMemoryBridgeIfNeeded()
        let state = PokemonXCompanionState()
        let view = PokemonXCompanionView(state: state, onClose: { dismiss() })
        let hosting = UIHostingController(rootView: view)
        hosting.view.backgroundColor = .clear
        host.addChild(hosting)
        host.view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
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

    /// Dismisses the overlay. Also does not touch the skin or pause state.
    static func dismiss() {
        guard let hosting = hostingController else { return }
        hostingController = nil
        hosting.willMove(toParent: nil)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
    }
}

// MARK: - Overlay view

struct PokemonXCompanionView: View {
    @ObservedObject var state: PokemonXCompanionState
    var onClose: () -> Void

    @State private var dexSearchText = ""
    @State private var selectedDexPokemon: PokemonXStaticPokemon?

    // Pokemon X menu palette: navy header, white cards, pink battle accent.
    private let navy = Color(red: 0.12, green: 0.22, blue: 0.42)
    private let pink = Color(red: 0.96, green: 0.62, blue: 0.78)

    var body: some View {
        ZStack {
            // Dimmed background: tap outside the card to close. This is a
            // native SwiftUI layer — taps here never reach the emulator.
            Color.black.opacity(0.45)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                header
                tabBar
                Divider()
                ScrollView {
                    switch state.selectedTab {
                    case .party: partyTab
                    case .bag: bagTab
                    case .map: mapTab
                    case .dex: dexTab
                    case .battle: battleTab
                    }
                }
                multiInputFooter
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
        }
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

    // MARK: Tab bar (native SwiftUI touch buttons)

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PokemonXCompanionState.Tab.allCases) { tab in
                Button(action: { state.selectedTab = tab }) {
                    Text(tab.title)
                        .font(.subheadline)
                        .fontWeight(state.selectedTab == tab ? .bold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(state.selectedTab == tab ? navy.opacity(0.12) : Color.clear)
                        .foregroundColor(state.selectedTab == tab ? navy : .primary)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Party tab (placeholder until live data)

    private var partyTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            noLiveDataNote(text: state.isLiveDataAvailable
                ? "Live battle data — HP and level update as the battle goes."
                : "Your party will appear here once the companion can read the game. No Pokemon are shown yet — nothing here is real data.")
            ForEach(state.partySlots) { slot in
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
        }
        .padding(12)
    }

    // MARK: Bag tab (placeholder until live data)

    private var bagTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            noLiveDataNote(text: "Bag contents need live game memory. Items, counts and medicine will list here once the bridge is wired — nothing is shown yet.")
            Text("What will be here: Medicine, Poke Balls, Battle Items, Berries, Key Items — the same sections as the in-game Bag.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(12)
    }

    // MARK: Map tab (static Kalos reference; live location needs memory)

    private static let kalosTowns = [
        "Vaniville Town", "Aquacorde Town", "Santalune City", "Lumiose City",
        "Camphrier Town", "Ambrette Town", "Cyllage City", "Geosenge Town",
        "Shalour City", "Coumarine City", "Laverre City", "Dendemille Town",
        "Anistar City", "Couriway Town", "Snowbelle City", "Kiloude City",
        "Pokemon League"
    ]

    private var mapTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            noLiveDataNote(text: "Your current location is not known yet — that needs live game memory. Below is a static Kalos reference map, not your live position.")
            ForEach(Self.kalosTowns, id: \.self) { town in
                Text(town)
                    .font(.subheadline)
                    .padding(.vertical, 4)
                Divider()
            }
        }
        .padding(12)
    }

    // MARK: Dex tab (static PokeAPI sample + type chart)

    private var dexTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Full Gen 1–6 Pokedex — 721 Pokemon from PokeAPI. Tap one to see its type matchups.")
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
            Text("Static type chart (PokeAPI). Not live battle data.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: Battle tab (placeholder until live data — top-screen battle UI)

    private var battleTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            noLiveDataNote(text: state.isLiveDataAvailable
                ? "Live battle — your moves below, opponent above. Tapping a move does not choose it yet: the bottom screen is hidden in top-only mode and the game can't receive taps there. Use the bottom screen for now."
                : "No live battle yet. These four move slots and the Fight / Pokemon / Bag / Run buttons will light up once the companion can read the battle state. They do nothing yet — tapping them sends nothing to the game.")
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
            }
            // Four move slots, 2 x 2, like the bottom-screen move list —
            // but drawn here, on the top screen, so battles stay top-only.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(state.battleMoves) { slot in
                    Button(action: {}) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.name ?? (state.isLiveDataAvailable ? "—" : "Move \(slot.id + 1)"))
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
                            } else if !state.isLiveDataAvailable {
                                Text("No live data yet")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(pink.opacity(0.25))
                        .cornerRadius(10)
                    }
                    .disabled(true)
                }
            }
            HStack(spacing: 10) {
                ForEach(["Fight", "Pokemon", "Bag", "Run"], id: \.self) { action in
                    Button(action: {}) {
                        Text(action)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(navy.opacity(0.15))
                            .cornerRadius(10)
                    }
                    .disabled(true)
                }
            }
            Text("Tapping a move doesn't choose it in battle yet — the send path is blocked while the bottom screen is hidden. Use the bottom screen for now.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
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
