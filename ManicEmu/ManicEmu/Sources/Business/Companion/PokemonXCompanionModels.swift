//
//  PokemonXCompanionModels.swift
//  ManicEmu
//
//  PokeDaisy-style companion for Pokemon X (Gen 6) — data models and state.
//  UI SHELL ONLY: nothing in this file reads live game memory. Party, Bag and
//  Battle data stay empty / placeholder until the memory bridge is wired to
//  verified X offsets (see HUDMemoryBridge.h and COMPANION-REPORT-2026-11-18.md).
//  Static reference data (type chart, sample Pokemon/moves) comes from PokeAPI
//  (https://pokeapi.co/api/v2/) via PokemonXCompanionData.json, with the
//  generated literals in PokemonXCompanionStaticData.swift as fallback.
//
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
import SwiftUI

// MARK: - Static reference data (PokeAPI, bundled JSON with literal fallback)

struct PokemonXStaticPokemon: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let types: [String]
}

struct PokemonXStaticMove: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String
    let power: Int?
    let accuracy: Int?
    let pp: Int?
    let damageClass: String
}

struct PokemonXStaticDataFile: Decodable {
    let types: [String]
    let typeChart: [String: PokemonXTypeRelations]
    let pokemon: [PokemonXStaticPokemon]
    let moves: [PokemonXStaticMove]

    enum CodingKeys: String, CodingKey {
        case types, pokemon, moves
        case typeChart = "type_chart"
    }
}

struct PokemonXTypeRelations: Decodable {
    let doubleDamageTo: [String]
    let halfDamageTo: [String]
    let noDamageTo: [String]
    let doubleDamageFrom: [String]
    let halfDamageFrom: [String]
    let noDamageFrom: [String]

    enum CodingKeys: String, CodingKey {
        case doubleDamageTo = "double_damage_to"
        case halfDamageTo = "half_damage_to"
        case noDamageTo = "no_damage_to"
        case doubleDamageFrom = "double_damage_from"
        case halfDamageFrom = "half_damage_from"
        case noDamageFrom = "no_damage_from"
    }
}

/// Loads the bundled PokeAPI JSON when it is in the app bundle; otherwise
/// falls back to the generated literals (same data, same source).
enum PokemonXCompanionData {
    static let types: [String] = {
        if let file = bundledFile() { return file.types }
        return Array(PokemonXCompanionStaticData.typeChartOffense.keys).sorted()
    }()

    static let pokemon: [PokemonXStaticPokemon] = {
        if let file = bundledFile() { return file.pokemon }
        return PokemonXCompanionStaticData.pokemon
    }()

    static let moves: [PokemonXStaticMove] = {
        if let file = bundledFile() { return file.moves }
        return PokemonXCompanionStaticData.moves
    }()

    static func bundledFile() -> PokemonXStaticDataFile? {
        guard let url = Bundle.main.url(forResource: "PokemonXCompanionData", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PokemonXStaticDataFile.self, from: data)
    }

    /// Attacking-type effectiveness against a list of defending types.
    /// 2.0 / 0.5 / 0.0 per type, multiplied. Returns 1.0 when nothing is known.
    static func effectiveness(attacking: String, defending: [String]) -> Double {
        var result = 1.0
        for defence in defending {
            if let chart = PokemonXCompanionStaticData.typeChartOffense[attacking] {
                if chart.double.contains(defence) { result *= 2.0 }
                else if chart.half.contains(defence) { result *= 0.5 }
                else if chart.none.contains(defence) { result *= 0.0 }
            } else if let file = bundledFile(),
                      let rel = file.typeChart[attacking] {
                if rel.doubleDamageTo.contains(defence) { result *= 2.0 }
                else if rel.halfDamageTo.contains(defence) { result *= 0.5 }
                else if rel.noDamageTo.contains(defence) { result *= 0.0 }
            }
        }
        return result
    }

    /// Types that deal double damage to the given defending type(s).
    static func weaknesses(of defending: [String]) -> [String] {
        types.filter { effectiveness(attacking: $0, defending: defending) > 1.0 }
    }

    /// Types that deal half or no damage to the given defending type(s).
    static func resistances(of defending: [String]) -> [String] {
        types.filter { effectiveness(attacking: $0, defending: defending) < 1.0 }
    }
}

// MARK: - Live data placeholders (empty until the memory bridge is wired)

/// One party slot. Every field is optional because nothing is known until
/// the bridge returns real guest memory. Never filled with invented data.
struct PokemonXPartySlot: Identifiable {
    let id: Int
    var speciesName: String?
    var level: Int?
    var currentHP: Int?
    var maxHP: Int?
    var status: String?

    static func empty(id: Int) -> PokemonXPartySlot {
        PokemonXPartySlot(id: id, speciesName: nil, level: nil, currentHP: nil, maxHP: nil, status: nil)
    }
}

/// One battle move slot. Same rule: nil until live battle data arrives.
struct PokemonXBattleMoveSlot: Identifiable {
    let id: Int
    var name: String?
    var type: String?
    var power: Int?
    var currentPP: Int?
    var maxPP: Int?

    static func empty(id: Int) -> PokemonXBattleMoveSlot {
        PokemonXBattleMoveSlot(id: id, name: nil, type: nil, power: nil, currentPP: nil, maxPP: nil)
    }
}

// MARK: - Companion state (ObservableObject, polled from the bridge)

/// UI state for the companion overlay.
///
/// Multi-input note (see COMPANION-REPORT-2026-11-18.md): the GameSir X5 Lite
/// keeps driving the game through the emulator's controller path while this
/// overlay is open, and taps on this overlay are native SwiftUI touch. The
/// two inputs are independent — opening the overlay never re-enables the
/// hidden on-screen skin controls and never pauses the game.
final class PokemonXCompanionState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case party, bag, map, dex, battle
        var id: String { rawValue }
        var title: String {
            switch self {
            case .party: return "Party"
            case .bag: return "Bag"
            case .map: return "Map"
            case .dex: return "Dex"
            case .battle: return "Battle"
            }
        }
    }

    @Published var selectedTab: Tab = .party
    @Published var partySlots: [PokemonXPartySlot] = (0..<6).map { PokemonXPartySlot.empty(id: $0) }
    @Published var battleMoves: [PokemonXBattleMoveSlot] = (0..<4).map { PokemonXBattleMoveSlot.empty(id: $0) }

    /// True only once the bridge has a real read callback AND a read returned data.
    @Published var isLiveDataAvailable = false
    /// Human-readable bridge status shown in the overlay header.
    @Published var bridgeStatus = "No live data yet — companion is not connected to the game."

    private var pollTimer: Timer?

    /// Starts polling the memory bridge. The UI updates ONLY when the bridge
    /// callback actually returns data. With no callback wired (the current
    /// state), every poll is a no-op and the placeholder UI stays as-is.
    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollBridgeOnce()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollBridgeOnce() {
        // TODO (after token reset): once X party/battle offsets are verified
        // via Ghidra / live Azahar FCRAM and LibretroCore provides the
        // EmuGuestReadBytesFn callback, read the verified addresses here and
        // fill partySlots / battleMoves from the returned bytes. Until then
        // this deliberately does nothing: no invented addresses, no fake data.
        guard HUDMemoryBridge.sharedBridge().hasLiveDataSource else { return }
        // A callback exists but no verified address to read yet — stay on
        // placeholder UI until the offset hunt lands.
        bridgeStatus = "Bridge connected, but no verified Pokemon X addresses yet."
    }

    deinit { stopPolling() }
}
