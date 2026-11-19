//
//  PokemonXCompanionModels.swift
//  ManicEmu
//
//  PokeDaisy-style companion for Pokemon X (Gen 6) — data models and state.
//  LIVE PARTY READ (2026-11-18): PokemonXLivePartyReader reads the verified
//  DllBattle battle structs through HUDMemoryBridge (see PokemonXBattleRead
//  below and PAGE-TABLE-MAPPING-2026-11-18.md). The structs are reached
//  through the pinned party-pointer arrays (STABLE-CHAIN-HUNT-2026-11-18.md):
//  the reader reads the 6 slot pointers from the player array at
//  0x081FD3CC, then each slot's battle struct at the pointer it holds —
//  never a hardcoded struct base VA. Party and Battle tabs fill from live
//  battle data when a battle is running and the species check passes;
//  otherwise they stay on honest placeholders. Bag stays a placeholder
//  (no verified bag offsets). Static reference data (type chart, sample
//  Pokemon/moves) comes from PokeAPI (https://pokeapi.co/api/v2/) via
//  PokemonXCompanionData.json, with the generated literals in
//  PokemonXCompanionStaticData.swift as fallback.
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
    /// True when a live read proved this slot holds no Pokemon (an empty party
    /// slot), as opposed to "no live data at all". The view shows "Empty" for
    /// these instead of "No live data yet".
    var isKnownEmpty: Bool = false

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
        guard let liveSlots = PokemonXLivePartyReader.readPlayerParty() else {
            // No battle running, or the heap base moved: never show stale data.
            if isLiveDataAvailable {
                isLiveDataAvailable = false
                partySlots = (0..<6).map { PokemonXPartySlot.empty(id: $0) }
                battleMoves = (0..<4).map { PokemonXBattleMoveSlot.empty(id: $0) }
            }
            bridgeStatus = "No live battle right now — open a battle to see your party."
            return
        }
        isLiveDataAvailable = true
        bridgeStatus = "Live — reading your party from the battle."
        partySlots = liveSlots.enumerated().map { index, live in
            guard let live else {
                var slot = PokemonXPartySlot.empty(id: index)
                slot.isKnownEmpty = true
                return slot
            }
            var slot = PokemonXPartySlot.empty(id: index)
            slot.speciesName = PokemonXCompanionData.pokemon.first(where: { $0.id == live.species })?.name.capitalized ?? "#\(live.species)"
            slot.level = nil // Level is not in the verified battle-struct set.
            slot.currentHP = live.currentHP
            slot.maxHP = live.maxHP
            return slot
        }
        // Battle tab: the active battler is slot 0 in the Shauna battle (the
        // first Pokemon sent out). If the player switches mid-battle, slot 0
        // is no longer the active battler — v1 does not track switches.
        if let active = liveSlots[0] {
            battleMoves = active.moves.enumerated().map { index, move in
                var slot = PokemonXBattleMoveSlot.empty(id: index)
                if move.id != 0 {
                    let known = PokemonXCompanionData.moves.first(where: { $0.id == move.id })
                    slot.name = known?.name.capitalized ?? "Move #\(move.id)"
                    slot.type = known?.type
                    slot.power = known?.power
                    slot.currentPP = move.pp
                    slot.maxPP = move.maxPP
                }
                return slot
            }
        } else {
            battleMoves = (0..<4).map { PokemonXBattleMoveSlot.empty(id: $0) }
        }
    }

    deinit { stopPolling() }
}

// MARK: - Live party read (verified Pokemon X battle structs)

/// Verified live read for Pokemon X battles.
///
/// The DllBattle battle-Pokemon structs live in the 3DS heap. They are
/// reached through the party-pointer arrays pinned by the stable-chain hunt
/// (STABLE-CHAIN-HUNT-2026-11-18.md): player array VA 0x081FD3CC, enemy
/// array VA 0x081FEB14, each holding 6 consecutive u32 pointers to the
/// battle structs (slot 0 = Chespin 0x081FD418 / Froakie 0x081FEB60 in the
/// Shauna battle). Both array VAs are stable across the three dumps of that
/// battle, but they are heap-allocated, so EVERY poll validates slot 0's
/// species before trusting anything. Outside battle (or if the heap moved)
/// the read fails the species check and the UI stays on the placeholder —
/// never stale data. No complete stable-global pointer chain to the arrays
/// exists via stored pointers (the two referrer objects that hold the array
/// pointers are themselves referenced by nothing), so the pinned array VAs
/// + species check are the wiring, with a durable-chain hunt as later work.
///
/// BATTLE struct offsets (NOT PK6), verified in three Azahar dumps with HP
/// liveness proven by the post-damage test (see PAGE-TABLE-MAPPING-2026-11-18.md):
/// species u16 +0x0C, HP max u16 +0x0E, HP current u16 +0x10 (LIVE — +0x0E is
/// max, not current; reading +0x0E as "HP" would show a permanently-full bar),
/// moves 4 x 0xE at +0x116 (move ID u16 +0, PP cur u8 +2, PP max u8 +3).
/// Level is NOT in the verified set (the only Lv5 candidate, a 0x05 byte at
/// +0x18, is unproven — both battlers in the test battle are Lv5, so it cannot
/// be distinguished from any other field that happens to be 5) and is left nil.
private enum PokemonXBattleRead {
    /// Player party array: 6 consecutive u32 pointers to battle structs.
    static let playerPartyArrayVA: UInt32 = 0x081FD3CC
    /// Enemy party array: same layout. Pinned, not yet read — no UI consumes
    /// the enemy party in v1 (Party tab is the player's party; Battle tab
    /// shows the player's moves).
    static let enemyPartyArrayVA: UInt32 = 0x081FEB14
    static let partySlotCount = 6
    static let structLength: UInt32 = 0x1E4

    static let speciesOffset = 0x0C
    static let hpMaxOffset = 0x0E
    static let hpCurrentOffset = 0x10
    static let movesOffset = 0x116
    static let moveStride = 0xE

    /// Gen 6 species range (Pokemon X). A species outside this range means the
    /// heap base moved (or no battle is running) — not a real Pokemon.
    static func isPlausibleSpecies(_ species: Int) -> Bool {
        species >= 1 && species <= 721
    }
}

/// One live party slot parsed from a battle struct.
private struct PokemonXLiveSlot {
    let species: Int
    let currentHP: Int
    let maxHP: Int
    /// (move ID, PP cur, PP max) x 4; move ID 0 = empty move slot.
    let moves: [(id: Int, pp: Int, maxPP: Int)]
}

private enum PokemonXLivePartyReader {
    /// Reads the six player battle structs through the pinned party-pointer
    /// array: read the 6 slot pointers at 0x081FD3CC, then each slot's struct
    /// at the pointer it holds. Returns nil when the read is untrusted as a
    /// whole (array unreadable, slot 0 pointer null, slot 0 struct
    /// unreadable, or slot 0's species not a plausible Pokemon — the heap
    /// moved or no battle is running). Slots 1-5 that fail to read or hold
    /// no plausible species come back as nil (empty slot), not as a failure
    /// of the whole party.
    static func readPlayerParty() -> [PokemonXLiveSlot?]? {
        let bridge = HUDMemoryBridge.shared()
        guard bridge.hasLiveDataSource else { return nil }
        // The array itself: 6 little-endian u32 pointers (24 bytes).
        guard let arrayData = bridge.readBytes(atAddress: PokemonXBattleRead.playerPartyArrayVA,
                                               length: UInt32(PokemonXBattleRead.partySlotCount * 4)),
              arrayData.count == PokemonXBattleRead.partySlotCount * 4 else {
            return nil
        }
        var slots: [PokemonXLiveSlot?] = []
        for index in 0..<PokemonXBattleRead.partySlotCount {
            let structVA = u32LE(arrayData, index * 4)
            guard structVA != 0 else {
                // Null slot pointer = no Pokemon in this slot. Slot 0 null
                // means the array itself is not a live party: trust nothing.
                if index == 0 { return nil }
                slots.append(nil)
                continue
            }
            guard let data = bridge.readBytes(atAddress: structVA, length: PokemonXBattleRead.structLength),
                  data.count == Int(PokemonXBattleRead.structLength) else {
                // Slot 0 unreadable = the array VA is wrong: trust nothing.
                // Any later slot unreadable = that slot is empty.
                if index == 0 { return nil }
                slots.append(nil)
                continue
            }
            let species = Int(u16LE(data, PokemonXBattleRead.speciesOffset))
            guard PokemonXBattleRead.isPlausibleSpecies(species) else {
                if index == 0 { return nil }
                slots.append(nil)
                continue
            }
            let hpMax = Int(u16LE(data, PokemonXBattleRead.hpMaxOffset))
            let hpCur = Int(u16LE(data, PokemonXBattleRead.hpCurrentOffset))
            var moves: [(id: Int, pp: Int, maxPP: Int)] = []
            for moveIndex in 0..<4 {
                let base = PokemonXBattleRead.movesOffset + moveIndex * PokemonXBattleRead.moveStride
                let moveID = Int(u16LE(data, base))
                let pp = Int(data[base + 2])
                let maxPP = Int(data[base + 3])
                moves.append((id: moveID, pp: pp, maxPP: maxPP))
            }
            slots.append(PokemonXLiveSlot(species: species, currentHP: hpCur, maxHP: hpMax, moves: moves))
        }
        return slots
    }

    private static func u16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
