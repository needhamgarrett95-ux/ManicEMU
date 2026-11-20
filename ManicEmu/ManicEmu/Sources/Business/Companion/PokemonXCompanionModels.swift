//
//  PokemonXCompanionModels.swift
//  ManicEmu
//
//  PokeDaisy-style companion for Pokemon X (Gen 6) — data models and state.
//  LIVE PARTY READ (2026-11-19): the FIELD party read (G1, PROVEN —
//  HUNTS-REPORT-2-2026-11-19.md §2.3) is the Party tab's base data:
//  pointer table 0x08CE1C5C -> wrapper+0x04 -> 232-byte XOR-encrypted
//  PKM blob, validated by sanity (+0x04 == 0) + checksum (+0x06 == sum
//  of u16s over the XOR-decrypted 0x08–0xE7) + species 1...721. Fixed
//  block-A fields: species +0x40, held item +0x42, TID/SID +0x44,
//  EXP +0x48, ability +0x4C, PID +0x50. Level is derived from EXP via
//  the species' growth rate — the blob does not store level. HP IS
//  wired from the field: the wrapper's +0x08 24-byte block (HUNTS-
//  REPORT-3-2026-11-19.md §4), decrypted with the same LCRNG keystream
//  seeded by enc_const, words 0..11 — status +0x00, level +0x04 (cross-
//  checked against the EXP-derived level), HP cur +0x08, HP max +0x0A,
//  Atk +0x0C, Def +0x0E, SpA +0x12. The block is OUTSIDE-BATTLE HP: it
//  holds PRE-BATTLE HP during a battle, so the poll overrides the active
//  slot's HP with the battle struct's live HP. Nickname/moves/PP are
//  shuffle-dependent (only idx 1 + 9 mapped) and are shown only in
//  battle; IVs/EVs/nature are unconfirmed. The BATTLE read (§1.4)
//  is the stat structs at base 0x082059D8 (player +0, enemy +0x244,
//  mirrors +0x488/+0x6CC), validated per struct (species 1...721,
//  level 1...100, HP max > 0, HP cur <= HP max) — the pinned arrays at
//  0x081FD3CC / 0x081FEB14 hold wrappers, NOT structs, and are never
//  read. Both reads have a structural/heap scan fallback (throttled,
//  cached). Battle HP/moves/stats/types come from the battle structs
//  only, and enrich the Party tab's active slot (matched by species).
//  Level is u8 at battle-struct +0x18; +0x08 is the current-level EXP
//  threshold, NOT current EXP, and is never read. Stats are 5 x u16 at
//  +0xF6..+0xFE (ATK/DEF/SPA/SPD/SPE, LEVEL-HUNT-2026-11-19.md §2a/§6a);
//  foe types are two u8 game type ids at +0x100 (audit G15: Froakie
//  10/10 = Water/Water — see the note on PokemonXBattleRead; the
//  battle-data hunt report itself does not document +0x100, so the
//  read validates both bytes 0...17 and yields nil types on failure).
//  MAP LIVE READ (MAP-LIVE-READ-2026-11-19.md): the position chain is
//  re-walked from the singleton slot at VA 0x005AE748 every poll — never
//  cached intermediates — grid X = f32 at position+0x04, grid Z = f32 at
//  position+0x0C (1.0/tile, north = -Z, east = +X). Map ID is u8 at
//  fieldmap-proc+0x0E0, shown RAW as provisional/unconfirmed — the
//  three-sample town table (Aquacorde 8, Vaniville 0, bedroom 2) was
//  DISPROVED by the hunts (HUNTS-REPORT-2026-11-19.md §0d: Route 1 also
//  reads map ID 2), so NO town name is derived from +0x0E0 and the live
//  dot is DISABLED until a confirmed mapping exists. Grid (x, z) is LOCAL
//  to the current map (bedroom is (3,12), Aquacorde is (460,555)).
//  BAG LIVE READ (BAG-VA-HUNT-2026-11-19.md): bag block base VA
//  0x08C67554, pockets Items +0x000 (400 entries), Key +0x640 (96), TM
//  +0x7C0 (106), Medicine +0x968 (64), Berry +0xA68 (72), 4-byte entries
//  (item_id u16 LE, count u16 LE). Guard: u32 at VA+0x640 must equal
//  82 02 01 00 (Prof's Letter, game id 642) or the bag state is "no live
//  bag" — never stale counts. Bag item ids are the GAME's internal ids;
//  names resolve through itemIdMap (game id -> PokeAPI id) into the items
//  table; unmapped ids show "Item #<gameId>", never a guessed name.
//  BATTLE SEND (widescreen layout): the core gets identical top/bottom
//  rects + citra_swap_screen="Bottom", so injected touches pass the
//  IsWithinTouchscreen gate while only the top screen is displayed — the
//  Battle tab buttons send through PokemonXTouchSender (see
//  PokemonXCompanionView.swift). Move slot 3 has no measured centre and
//  stays disabled; Growl / Vine Whip positions are estimated, not
//  lab-measured.
//  NOT BUILT, honestly: G11 Mega (no Mega Stone in the lab, no button
//  centre measured) and G12 multi-target (no target centres measured) —
//  nothing is exposed for them. G9b/G9c/G9f (IVs/EVs, status, nature)
//  stay nil — shuffle-dependent, unconfirmed, no ground truth. G9d held
//  item, G9e ability and G9g EXP ARE wired now, from the field blob's
//  fixed block-A fields (HUNTS-REPORT-2 §2.3). G10 active-battler
//  tracking: the active slot is found by matching the battle struct's
//  species against the field party (no index field is hunted) — when the
//  field read fails, slot 0 stays the assumed active battler, labelled
//  as an assumption. G6 Card data and G2 Dex flags need the trainer-info
//  RAM object (not located — the disk-format save buffer does not exist
//  in RAM); the Card tab is an honest all-unknown placeholder. G7 Boxes,
//  G19 Fly, G21 field items, G26 shiny, G24/G25/G28/G30 are not in this file.
//  Static reference data (type chart, full 721-species enriched Dex,
//  621 moves, 762 items, game-ID item map, 721 growth rates, 374 ability
//  names) comes from PokeAPI (https://pokeapi.co/api/v2/) via
//  PokemonXCompanionData.json, with the generated 26-species/20-move
//  literals in PokemonXCompanionStaticData.swift as fallback — the
//  fallback is the ORIGINAL 26-species/20-move sample only; the JSON is
//  the source of truth and is NOT regenerated into Swift (too big).
//
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
import SwiftUI

// MARK: - STAGE1-X diagnostic holder (temporary, diagnostic build v1)

/// Shared holder for the layout-diagnostic line. PlayViewController updates
/// it on every layout call; the overlay's debug strip (PokemonXDiagStripView,
/// installed by PokemonXCompanionPresenter) reads it, so the decisive values
/// are visible in a screenshot with no log pull. Remove when the layout is
/// proven on the phone.
final class PokemonXDiag: ObservableObject {
    static let shared = PokemonXDiag()
    @Published var shortLine: String = "DIAG: waiting for first layout call"
    @Published var fullLine: String = ""
    func update(short: String, full: String) {
        if Thread.isMainThread {
            self.shortLine = short
            self.fullLine = full
        } else {
            DispatchQueue.main.async {
                self.shortLine = short
                self.fullLine = full
            }
        }
    }
}

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

    enum CodingKeys: String, CodingKey {
        case id, name, type, power, accuracy, pp
        case damageClass = "damage_class"
    }
}

/// One Gen 6 item from the bundled table, keyed by PokeAPI id. The bag
/// read produces GAME ids — resolve them through `itemIdMap` first.
/// `effect` is PokeAPI's English short_effect; it is nil when PokeAPI has
/// none, and empty for exactly one item (Honey, PokeAPI id 94) — that is
/// PokeAPI's data, not an error, so the View shows no effect text for it.
struct PokemonXStaticItem: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let category: String
    let pocket: String
    let effect: String?
}

// MARK: Enriched Dex detail (per species, nested in the bundled JSON)

struct PokemonXAbilityEntry: Decodable, Hashable {
    let name: String
    let isHidden: Bool
    let slot: Int

    enum CodingKeys: String, CodingKey {
        case name, slot
        case isHidden = "is_hidden"
    }
}

struct PokemonXBaseStatEntry: Decodable, Hashable {
    let name: String
    let value: Int
}

struct PokemonXEncounterDetail: Decodable, Hashable {
    let method: String
    let minLevel: Int?
    let maxLevel: Int?
    let chance: Int?
    let conditions: [String]?

    enum CodingKeys: String, CodingKey {
        case method, chance, conditions
        case minLevel = "min_level"
        case maxLevel = "max_level"
    }
}

struct PokemonXEncounterVersion: Decodable, Hashable {
    let version: String
    let encounters: [PokemonXEncounterDetail]
}

struct PokemonXEncounterEntry: Decodable, Hashable {
    let name: String
    let versions: [PokemonXEncounterVersion]
}

struct PokemonXLevelUpMoveEntry: Decodable, Hashable {
    let id: Int
    let name: String
    let level: Int
}

struct PokemonXEvolutionDetail: Decodable, Hashable {
    let trigger: String?
    let minLevel: Int?
    let item: String?
    let heldItem: String?
    let knownMove: String?
    let timeOfDay: String?

    enum CodingKeys: String, CodingKey {
        case trigger, item
        case minLevel = "min_level"
        case heldItem = "held_item"
        case knownMove = "known_move"
        case timeOfDay = "time_of_day"
    }
}

struct PokemonXEvolutionNode: Decodable, Hashable {
    let id: Int
    let name: String
    let evolvesTo: [PokemonXEvolutionNode]
    /// Absent on the chain ROOT node (the species itself has no details
    /// for evolving into itself) — present on every child node.
    let evolutionDetails: [PokemonXEvolutionDetail]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case evolvesTo = "evolves_to"
        case evolutionDetails = "evolution_details"
    }
}

/// Full enriched entry for one species: id/name/types at top level plus
/// abilities, base stats, evolution chain, encounter locations and the
/// level-up learnset nested. Decoded from the same "pokemon" array as the
/// light list — if any entry fails, the whole detail list is empty and the
/// light list (plus the literal fallback) still works.
struct PokemonXEnrichedPokemon: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let types: [String]
    let abilities: [PokemonXAbilityEntry]
    let baseStats: [PokemonXBaseStatEntry]
    let evolutionChain: PokemonXEvolutionNode
    let encounterLocations: [PokemonXEncounterEntry]
    let levelUpMoves: [PokemonXLevelUpMoveEntry]

    enum CodingKeys: String, CodingKey {
        case id, name, types, abilities
        case baseStats = "base_stats"
        case evolutionChain = "evolution_chain"
        case encounterLocations = "encounter_locations"
        case levelUpMoves = "level_up_moves"
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

struct PokemonXStaticDataFile: Decodable {
    let types: [String]
    let typeChart: [String: PokemonXTypeRelations]
    let pokemon: [PokemonXStaticPokemon]
    let moves: [PokemonXStaticMove]
    /// 762 Gen 6 items, keyed by PokeAPI id. Empty when the bundled JSON
    /// is the old shape (or missing) — the Bag tab then has no names.
    let items: [PokemonXStaticItem]
    /// Game-internal item id (as a string key) -> PokeAPI item id.
    /// 753 entries: game ids 723 and 734 are absent — two different unused
    /// PokeAPI items share each index, so no honest single mapping exists.
    let itemIdMap: [String: Int]
    /// Enriched detail per species, decoded from the same "pokemon" array.
    /// Empty when the JSON has no enriched entries — detail views hide.
    let enrichedPokemon: [PokemonXEnrichedPokemon]
    /// Growth rate per species id (as a string key) -> PokeAPI growth-rate
    /// name ("medium-slow" etc.). 721 entries. Drives the field-party
    /// EXP -> level derivation (HUNTS-REPORT-2 §2.3 step 6).
    let growthRates: [String: String]
    /// Ability id (as a string key) -> PokeAPI ability name. 374 entries.
    /// Resolves the field blob's ability id (+0x4C) to a display name.
    let abilities: [String: String]

    enum CodingKeys: String, CodingKey {
        case types, pokemon, moves, items
        case typeChart = "type_chart"
        case itemIdMap = "item_id_map"
        case growthRates = "growth_rates"
        case abilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        types = try container.decode([String].self, forKey: .types)
        typeChart = try container.decode([String: PokemonXTypeRelations].self, forKey: .typeChart)
        pokemon = try container.decode([PokemonXStaticPokemon].self, forKey: .pokemon)
        moves = try container.decode([PokemonXStaticMove].self, forKey: .moves)
        items = try container.decodeIfPresent([PokemonXStaticItem].self, forKey: .items) ?? []
        itemIdMap = try container.decodeIfPresent([String: Int].self, forKey: .itemIdMap) ?? [:]
        growthRates = try container.decodeIfPresent([String: String].self, forKey: .growthRates) ?? [:]
        abilities = try container.decodeIfPresent([String: String].self, forKey: .abilities) ?? [:]
        let enriched: [PokemonXEnrichedPokemon]? = try? container.decode([PokemonXEnrichedPokemon].self, forKey: .pokemon)
        enrichedPokemon = enriched ?? []
    }
}

/// Loads the bundled PokeAPI JSON when it is in the app bundle; otherwise
/// falls back to the generated literals (same data, same source — but only
/// the original 26-species/20-move sample, NOT the full tables).
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

    static let items: [PokemonXStaticItem] = {
        if let file = bundledFile() { return file.items }
        return []
    }()

    static let itemIdMap: [String: Int] = {
        if let file = bundledFile() { return file.itemIdMap }
        return [:]
    }()

    static let enrichedPokemon: [PokemonXEnrichedPokemon] = {
        if let file = bundledFile() { return file.enrichedPokemon }
        return []
    }()

    static let enrichedPokemonById: [Int: PokemonXEnrichedPokemon] = {
        var out: [Int: PokemonXEnrichedPokemon] = [:]
        for detail in enrichedPokemon { out[detail.id] = detail }
        return out
    }()

    /// Growth rate per species id (PokeAPI name). Empty when the bundled
    /// JSON is the old shape — the field party then cannot derive levels.
    static let growthRates: [String: String] = {
        if let file = bundledFile() { return file.growthRates }
        return [:]
    }()

    /// Ability id -> name. Empty when the bundled JSON is the old shape —
    /// the field party then shows the ability id, not a name.
    static let abilities: [String: String] = {
        if let file = bundledFile() { return file.abilities }
        return [:]
    }()

    /// Growth-rate name for a species, or nil when the JSON has none.
    static func growthRate(forSpecies speciesId: Int) -> String? {
        growthRates[String(speciesId)]
    }

    /// Display name for a game ability id (field blob +0x4C), or the
    /// honest placeholder "Ability #<id>" when the table has no name.
    static func displayAbilityName(forId abilityId: Int) -> String {
        if let name = abilities[String(abilityId)] { return name.capitalized }
        return "Ability #\(abilityId)"
    }

    /// Level for a total EXP and a species, via the standard Gen 6
    /// EXP -> level table for that species' growth rate
    /// (HUNTS-REPORT-2-2026-11-19.md §2.3 step 6). The blob stores EXP,
    /// never level. Nil when the growth rate is unknown — never a guessed
    /// level. Chespin (medium-slow): EXP 135 -> Lv5, 179 -> Lv6, 202 -> Lv6.
    static func level(forExp exp: Int, speciesId: Int) -> Int? {
        guard let rate = growthRate(forSpecies: speciesId) else { return nil }
        return PokemonXGrowthRate.level(forExp: exp, growthRate: rate)
    }

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

    /// The items-table entry for a GAME-internal item id, via the
    /// game-ID -> PokeAPI-ID map. Nil when the game id has no mapping
    /// (e.g. 723/734) — the caller shows "Item #<gameId>" then.
    static func item(forGameId gameId: Int) -> PokemonXStaticItem? {
        guard let pokeAPIId = itemIdMap[String(gameId)] else { return nil }
        return items.first(where: { $0.id == pokeAPIId })
    }

    /// Display name for a game-internal item id: the resolved table name,
    /// or the honest placeholder "Item #<gameId>" when unmapped.
    static func displayItemName(forGameId gameId: Int) -> String {
        if let item = item(forGameId: gameId) { return item.name.capitalized }
        return "Item #\(gameId)"
    }

    /// Enriched detail for one species id, if the bundled JSON has it.
    static func pokemonDetail(id: Int) -> PokemonXEnrichedPokemon? {
        enrichedPokemonById[id]
    }

    /// Moves a species learns after `level`, soonest first — the "what to
    /// learn" half of the party detail view (G9a). Empty when the Dex has
    /// no learnset for the species.
    static func nextMovesToLearn(speciesId: Int, level: Int) -> [PokemonXLevelUpMoveEntry] {
        guard let detail = enrichedPokemonById[speciesId] else { return [] }
        return detail.levelUpMoves.filter { $0.level > level }.sorted { $0.level < $1.level }
    }

    /// Encounter-location names carry a "-area" suffix
    /// ("kalos-route-2-area") and sometimes sub-area suffixes — strip the
    /// "-area" suffix and title-case for display ("Kalos Route 2").
    static func displayAreaName(_ raw: String) -> String {
        var stripped = raw
        if stripped.hasSuffix("-area") { stripped = String(stripped.dropLast("-area".count)) }
        return stripped.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    /// Wild encounters for one PokeAPI location-area name (e.g.
    /// "aquacorde-town-area"), one row per (species, method), soonest
    /// species first. Empty when nothing is catchable there.
    static func encounters(inArea rawAreaName: String) -> [PokemonXGuideEncounter] {
        var out: [PokemonXGuideEncounter] = []
        var seen: Set<String> = []
        for detail in enrichedPokemon {
            for location in detail.encounterLocations where location.name == rawAreaName {
                for version in location.versions {
                    for encounter in version.encounters {
                        let key = "\(detail.id)-\(encounter.method)-\(encounter.minLevel ?? -1)-\(encounter.maxLevel ?? -1)"
                        guard !seen.contains(key) else { continue }
                        seen.insert(key)
                        out.append(PokemonXGuideEncounter(
                            speciesId: detail.id,
                            speciesName: detail.name,
                            method: encounter.method,
                            minLevel: encounter.minLevel,
                            maxLevel: encounter.maxLevel,
                            chance: encounter.chance))
                    }
                }
            }
        }
        return out.sorted { $0.speciesName < $1.speciesName }
    }
}

// MARK: - Gen 6 EXP -> level (growth rates)

/// Standard Gen 6 EXP thresholds, per growth rate (Bulbapedia).
/// PokeAPI growth-rate names: "fast", "medium" (= Medium Fast),
/// "medium-slow", "slow", "slow-then-very-fast" (= Erratic),
/// "fast-then-very-slow" (= Fluctuating). All arithmetic is integer and
/// all values are positive for level >= 1, so Swift's truncating division
/// matches the floor division of the reference formulas. Verified in
/// Python before this was written: medium-slow Lv5=135, Lv6=179, Lv7=236;
/// Lv100 anchors fast 800,000 / medium 1,000,000 / medium-slow 1,059,860 /
/// slow 1,250,000 / erratic 600,000 / fluctuating 1,640,000.
enum PokemonXGrowthRate {
    /// EXP needed to reach `level` (1...100) for a growth rate. Level 1
    /// needs 0 by definition (the medium-slow formula goes negative at
    /// level 1, so the result is clamped at 0).
    static func expThreshold(level: Int, growthRate: String) -> Int {
        guard level > 1 else { return 0 }
        let n = level
        let raw: Int
        switch growthRate {
        case "fast":
            raw = (4 * n * n * n) / 5
        case "medium":
            raw = n * n * n
        case "medium-slow":
            raw = (6 * n * n * n) / 5 - 15 * n * n + 100 * n - 140
        case "slow":
            raw = (5 * n * n * n) / 4
        case "slow-then-very-fast": // Erratic
            if n <= 50 { raw = (n * n * n * (100 - n)) / 50 }
            else if n <= 68 { raw = (n * n * n * (150 - n)) / 100 }
            else if n <= 98 { raw = (n * n * n * ((1911 - 10 * n) / 3)) / 500 }
            else { raw = (n * n * n * (160 - n)) / 100 }
        case "fast-then-very-slow": // Fluctuating
            if n <= 15 { raw = (n * n * n * ((n + 1) / 3 + 24)) / 50 }
            else if n <= 35 { raw = (n * n * n * (n + 14)) / 50 }
            else { raw = (n * n * n * (n / 2 + 32)) / 50 }
        default:
            // Unknown growth rate: Medium Fast is the most common
            // (296/721) and the only safe fallback — the caller only
            // reaches here when the JSON has no rate for the species.
            raw = n * n * n
        }
        return max(0, raw)
    }

    /// Highest level (1...100) whose threshold is <= `exp`.
    static func level(forExp exp: Int, growthRate: String) -> Int {
        var level = 1
        for candidate in 2...100 {
            if expThreshold(level: candidate, growthRate: growthRate) <= exp {
                level = candidate
            } else {
                break
            }
        }
        return level
    }
}

// MARK: - Live data models (empty until the memory bridge is wired)

/// The five battle-struct stats, in the struct's order ATK/DEF/SPA/SPD/SPE
/// (5 x u16 at +0xF6..+0xFE). These are the CURRENT in-battle stats, not
/// base stats — they change on level-up (LEVEL-HUNT-2026-11-19.md §6a).
struct PokemonXBattleStats: Hashable {
    let attack: Int
    let defense: Int
    let specialAttack: Int
    let specialDefense: Int
    let speed: Int
}

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
    /// Live in-battle stats (G9a, +0xF6..+0xFE). Nil outside battle.
    var stats: PokemonXBattleStats? = nil
    /// Live types from the battle struct (+0x100). Nil when unreadable.
    var types: [String]? = nil
    /// This slot's live moves (ids + PP), with matchup data filled in by
    /// the poll when the foe's types are known. Empty outside battle.
    var moves: [PokemonXBattleMoveSlot] = []
    // G9b–G9g — PARTLY WIRED from the field blob (HUNTS-REPORT-2 §2.3):
    // held item (+0x42), ability (+0x4C) and current EXP (+0x48) are
    // FIXED block-A offsets and ARE filled by the field party read.
    // IVs/EVs/nature stay nil: their offsets are shuffle-dependent
    // candidates, unconfirmed (stat cross-checks off by 1). Do not wire
    // +0x08 as EXP — it is the level EXP threshold, not current EXP.
    var ivs: [Int]? = nil
    var evs: [Int]? = nil
    var heldItemName: String? = nil
    var abilityName: String? = nil
    var natureName: String? = nil
    var currentExp: Int? = nil
    /// Trainer ID / Secret ID / Personality value from the field blob
    /// (TID/SID u32 +0x44, PID u32 +0x50). Shown in the detail view;
    /// the shiny formula needs them (G26) but no shiny alert is wired —
    /// there is no shiny test case, so a positive alert is unproven.
    var trainerId: Int? = nil
    var secretId: Int? = nil
    var personalityId: Int? = nil
    /// Field stats from the wrapper's +0x08 block (HUNTS-REPORT-3 §4):
    /// Atk +0x0C, Def +0x0E, SpA +0x12. The +0x10/+0x14 pair (Speed vs
    /// Sp. Def) is NOT wired — their order is unproven. Shown in the
    /// detail view when the battle stats are nil (outside battle).
    var fieldAttack: Int? = nil
    var fieldDefense: Int? = nil
    var fieldSpecialAttack: Int? = nil

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
    /// G15 matchup: effectiveness of this move vs the active foe's types.
    /// Nil when the foe's types are unknown (or the move is unknown).
    var effectiveness: Double? = nil
    /// G17 best-pick score: effectiveness x power. Nil for status moves
    /// (no power) and when effectiveness is unknown — status moves are
    /// never the best pick.
    var score: Double? = nil

    static func empty(id: Int) -> PokemonXBattleMoveSlot {
        PokemonXBattleMoveSlot(id: id, name: nil, type: nil, power: nil, currentPP: nil, maxPP: nil)
    }
}

/// Tap-for-detail data for one party slot (G9a): stats + moves + what the
/// species learns next. The G9d held item, G9e ability and G9g EXP are
/// filled from the field blob (HUNTS-REPORT-2 §2.3); the field stats
/// (Atk/Def/SpA) come from the wrapper's +0x08 block (HUNTS-REPORT-3 §4)
/// and are shown only when the battle stats are nil (outside battle).
/// IVs/EVs/nature stay nil by design (unconfirmed) — the detail view
/// shows them as unknown, not zero.
struct PokemonXPartyDetail {
    let slotId: Int
    let speciesId: Int?
    let speciesName: String
    let level: Int?
    let currentHP: Int?
    let maxHP: Int?
    let stats: PokemonXBattleStats?
    let types: [String]?
    let moves: [PokemonXBattleMoveSlot]
    let nextMovesToLearn: [PokemonXLevelUpMoveEntry]
    let status: String?
    let heldItemName: String?
    let abilityName: String?
    let currentExp: Int?
    let trainerId: Int?
    let secretId: Int?
    let personalityId: Int?
    let fieldAttack: Int?
    let fieldDefense: Int?
    let fieldSpecialAttack: Int?
}

// MARK: - Map live position (MAP-LIVE-READ-2026-11-19.md)

/// One live position poll. Grid (x, z) is LOCAL to the current map — each
/// map has its own origin (bedroom (3,12), Aquacorde (460,555)) — so the
/// coordinates are never plotted by a global transform. The live dot is
/// DISABLED: the map-ID -> town mapping was disproved (see mapId below).
struct PokemonXMapPosition: Hashable {
    let gridX: Float
    let gridZ: Float
    /// u8 at fieldmap-proc+0x0E0. UNCONFIRMED — do NOT map it to a town.
    /// The three-sample table (Aquacorde 8, Vaniville 0, bedroom 2) was
    /// DISPROVED by the hunts (HUNTS-REPORT-2026-11-19.md §0d): Route 1
    /// also reads map ID 2. The raw value is shown as provisional only
    /// until a fourth map / the game's map table confirms what +0x0E0 is.
    let mapId: Int
    /// u16 at mid+0x01A (secondary: Aquacorde 421, Vaniville 2009,
    /// bedroom 1380 — same three-sample caveat as mapId). Read and
    /// exposed so the phone test can confirm which id tracks the map;
    /// not used for any label.
    let secondaryMapId: Int

    var areaLabel: String { Self.areaLabel(forMapId: mapId) }

    /// No town-name mapping from +0x0E0 (disproved — see mapId comment).
    /// The label is the raw value, marked unconfirmed.
    static func areaLabel(forMapId mapId: Int) -> String {
        "Map \(mapId) (unconfirmed)"
    }

    /// Whether the live dot may be plotted. NEVER true for now: with no
    /// confirmed map-ID -> town mapping there is no town to plot the dot
    /// on (G20 dot rule). Re-enable only when a confirmed mapping lands.
    static func dotVisible(forMapId mapId: Int) -> Bool {
        _ = mapId
        return false
    }

    /// PokeAPI location-area name for the current map, for the Guide tab's
    /// live "what's in this area" list. Always nil until a confirmed
    /// map-ID -> area mapping exists — the Guide then shows no encounter
    /// list, not a wrong area's list.
    static func rawAreaName(forMapId mapId: Int) -> String? {
        _ = mapId
        return nil
    }
}

// MARK: - Bag live counts (BAG-VA-HUNT-2026-11-19.md)

/// One bag entry. `gameId` is the game's internal item id; `resolvedName`
/// is the items-table name via the game-ID map, or nil when unmapped —
/// the View then shows "Item #<gameId>".
struct PokemonXBagEntry: Identifiable, Hashable {
    let gameId: Int
    let count: Int
    let resolvedName: String?
    var id: Int { gameId }
}

struct PokemonXBagPocket: Identifiable, Hashable {
    let id: String
    let title: String
    let entries: [PokemonXBagEntry]
}

// MARK: - Guide tab (G8, static half + live area encounters)

/// One wild encounter in the current area, from the enriched Dex.
struct PokemonXGuideEncounter: Identifiable, Hashable {
    let speciesId: Int
    let speciesName: String
    let method: String
    let minLevel: Int?
    let maxLevel: Int?
    let chance: Int?
    var id: String { "\(speciesId)-\(method)" }
}

/// Static Guide data: gym leader / Elite Four / Champion teams (first
/// battle, from the game's trainer data) and the hand-written STUCK? page
/// covering the blockers the lab already hit. No memory reads here.
enum PokemonXGuideData {
    // NOTE: BossTeam is deliberately NOT Hashable — its team is an array
    // of tuples, and tuples cannot conform to Hashable.
    struct BossTeam {
        let name: String
        let place: String
        let team: [(species: String, level: Int)]
    }

    static let gymLeaders: [BossTeam] = [
        BossTeam(name: "Viola", place: "Santalune City", team: [("Surskit", 10), ("Vivillon", 12)]),
        BossTeam(name: "Grant", place: "Cyllage City", team: [("Amaura", 25), ("Tyrunt", 25)]),
        BossTeam(name: "Korrina", place: "Shalour City", team: [("Mienfoo", 29), ("Machoke", 28), ("Lucario", 32)]),
        BossTeam(name: "Ramos", place: "Coumarine City", team: [("Jumpluff", 30), ("Weepinbell", 31), ("Gogoat", 34)]),
        BossTeam(name: "Clemont", place: "Lumiose City", team: [("Emolga", 35), ("Magneton", 35), ("Heliolisk", 37)]),
        BossTeam(name: "Valerie", place: "Laverre City", team: [("Mawile", 38), ("Mr. Mime", 39), ("Sylveon", 42)]),
        BossTeam(name: "Olympia", place: "Anistar City", team: [("Sigilyph", 44), ("Slowking", 45), ("Meowstic", 48)]),
        BossTeam(name: "Wulfric", place: "Snowbelle City", team: [("Abomasnow", 56), ("Cryogonal", 55), ("Avalugg", 59)]),
    ]

    static let eliteFour: [BossTeam] = [
        BossTeam(name: "Wikstrom", place: "Pokemon League", team: [("Klefki", 63), ("Probopass", 63), ("Scizor", 63), ("Aegislash", 65)]),
        BossTeam(name: "Malva", place: "Pokemon League", team: [("Pyroar", 63), ("Torkoal", 63), ("Chandelure", 63), ("Talonflame", 65)]),
        BossTeam(name: "Drasna", place: "Pokemon League", team: [("Dragalge", 63), ("Altaria", 63), ("Druddigon", 63), ("Noivern", 65)]),
        BossTeam(name: "Siebold", place: "Pokemon League", team: [("Clawitzer", 63), ("Gyarados", 63), ("Barbaracle", 63), ("Starmie", 65)]),
    ]

    static let champion = BossTeam(
        name: "Diantha", place: "Pokemon League",
        team: [("Hawlucha", 64), ("Tyrantrum", 65), ("Aurorus", 65), ("Gourgeist", 65), ("Goodra", 66), ("Gardevoir", 68)])

    struct StuckEntry: Hashable {
        let title: String
        let body: String
    }

    /// Hand-written from the blockers the lab hit in the opening (audit
    /// G8). No dialogue is quoted — only the way through, where known.
    static let stuckEntries: [StuckEntry] = [
        StuckEntry(
            title: "Can't cross the bridge north out of Aquacorde Town",
            body: "The bridge to Route 2 is story-gated. Go home first (your house in Vaniville Town) — after the opening sequence at home, the way north opens."),
        StuckEntry(
            title: "An NPC won't let you past in Aquacorde Town",
            body: "Most Aquacorde blockers are the opening story, not a puzzle: visit home first, then battle Shauna at the south exit of town. The blockers move once the opening sequence is done."),
        StuckEntry(
            title: "Shauna's battle at the south exit",
            body: "Shauna runs up at Aquacorde's south exit (toward Route 1). Her Froakie is Lv 5. Chespin's Vine Whip is 2x against it — the Battle tab's best pick says the same."),
        StuckEntry(
            title: "The fountain in Aquacorde Town square",
            body: "The fountain is scenery, not a path — there is no way through it. The exits are north (Route 2, story-gated, see above) and south (Route 1)."),
    ]
}

// MARK: - Nuzlocke tracker (G27, UI + state only)

struct PokemonXNuzlockeDeath: Identifiable, Hashable {
    let id = UUID()
    let speciesName: String
    let level: Int?
    let areaLabel: String
    let date: Date
}

struct PokemonXNuzlockeCatch: Identifiable, Hashable {
    let id = UUID()
    let speciesName: String
    let areaLabel: String
    let date: Date
}

struct PokemonXNuzlockeRun: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var startedAt = Date()
    var deaths: [PokemonXNuzlockeDeath] = []
    var catches: [PokemonXNuzlockeCatch] = []
    var isActive = true

    func hasCaught(inArea area: String) -> Bool {
        catches.contains { $0.areaLabel == area }
    }
}

// MARK: - Trainer Card (G6, honest placeholder)

/// Trainer Card data. EVERYTHING is unknown until the G2+G6 save-buffer
/// hunt lands (player name, ID, money, play time, badges, Dex seen/caught
/// all live in the save buffer, which is unmapped). No value is ever
/// invented — the View shows the placeholder until the hunt lands.
struct PokemonXTrainerCard {
    var playerName: String? = nil
    var trainerID: String? = nil
    var money: Int? = nil
    var playTimeMinutes: Int? = nil
    var badges: Int? = nil
    var dexSeen: Int? = nil
    var dexCaught: Int? = nil

    static let placeholder = PokemonXTrainerCard()
    static let unavailableNote = "Trainer Card data is unknown until the save-buffer hunt (G2+G6) lands — no values are shown until then."
}

// MARK: - Measured battle touch centres (G13/G14 constants for the View)

/// Lab-measured touch centres at 1280x720 root coordinates. The View
/// must scale these to the phone screen. These are CONSTANTS only — the
/// touch sender itself is another agent's job, and the Battle tab buttons
/// stay disabled until the send path exists.
/// Sources: battle menu FIGHT/POKEMON/BAG/RUN and the Potion flow were
/// measured live in the Azahar lab (BATTLE-SEND-HUNT-2026-11-19.md,
/// BAG-VA-HUNT-2026-11-19.md §7, audit G13/G14). The 4th move-slot centre
/// and the pocket/item/target flows for pockets other than Medicine are
/// UNMEASURED — they are omitted, not estimated.
struct PokemonXTouchPoint: Hashable {
    let x: Int
    let y: Int
}

enum PokemonXBattleFlow {
    static let fightButton = PokemonXTouchPoint(x: 640, y: 525)
    static let pokemonButton = PokemonXTouchPoint(x: 795, y: 650)
    static let bagButton = PokemonXTouchPoint(x: 505, y: 650)
    static let runButton = PokemonXTouchPoint(x: 650, y: 650)
    /// Move-slot centres, measured only for the first three slots of the
    /// Shauna battle (Tackle, Growl, Vine Whip). Slot 3 is unmeasured.
    static let moveSlotCentres: [PokemonXTouchPoint] = [
        PokemonXTouchPoint(x: 575, y: 470),
        PokemonXTouchPoint(x: 720, y: 470),
        PokemonXTouchPoint(x: 575, y: 545),
    ]
    /// In-battle BAG flow, Medicine pocket only (Potion): pocket button,
    /// item row, USE, target. Other pockets' flows are unmeasured (G14).
    static let bagMedicinePocketButton = PokemonXTouchPoint(x: 565, y: 470)
    static let bagPotionRow = PokemonXTouchPoint(x: 565, y: 455)
    static let bagUseButton = PokemonXTouchPoint(x: 640, y: 635)
    static let bagTargetChespin = PokemonXTouchPoint(x: 565, y: 455)
    // G11 Mega: NOT built — no Mega Stone in the lab, no Mega button
    // centre measured, and the held-item read it depends on (G9d) is
    // unmapped. G12 multi-target: NOT built — no target centres measured
    // for double/horde battles. Nothing is exposed for either.
}

// MARK: - Companion state (ObservableObject, polled from the bridge)

/// UI state for the companion overlay.
///
/// Multi-input note (see COMPANION-REPORT-2026-11-18.md): the GameSir X5 Lite
/// keeps driving the game through the emulator's controller path while this
/// overlay is open, and taps on this overlay are native SwiftUI touch. The
/// two inputs are independent — opening the overlay never re-enables the
/// hidden on-screen skin controls and never pauses the game.
///
/// NOTE on tabs: the Tab enum keeps the five tabs the View already
/// renders (party/bag/map/dex/battle). Guide (G8), Nuzlocke (G27) and Card
/// (G6) state lives in this class, but their tabs are NOT added to the enum
/// here — the View's switch over Tab is exhaustive and the View is owned
/// by another agent. The View agent adds the tabs and wires them to the
/// state below.
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
    /// The active opponent during a battle, from the enemy battle struct
    /// (base+0x244). Nil when no battle is running or the enemy read
    /// fails validation — the Battle tab hides the opponent card then.
    @Published var enemyActive: PokemonXPartySlot?
    /// G16 foe team: only the ACTIVE foe is readable (the battle struct
    /// gives one enemy struct, not a 6-slot array — the old array held
    /// wrappers, not structs). Slots 1-5 stay nil (UNKNOWN) until a
    /// multi-Pokemon foe-team read is proven; never shown as empty.
    @Published var enemyTeam: [PokemonXPartySlot?] = [nil, nil, nil, nil, nil, nil]

    /// G10 active-battler index. Found by matching the battle struct's
    /// species against the field party (no index field is hunted). When
    /// the field party cannot be read, this stays 0 (the Shauna battle's
    /// active battler) — the assumption labelled in `activeBattlerNote`.
    @Published var activeBattlerIndex = 0
    var activeBattlerNote: String {
        "Active battler matched by species against your party — when the party read fails, slot 1 is assumed instead, so after a switch the moves shown may be the wrong Pokemon's."
    }

    /// G15/G17: best-pick state for the active battler's moves. Nil when
    /// there is no live battle, the foe's types are unknown, or no move
    /// has a score (status moves have no power and never score).
    @Published var bestMoveIndex: Int?
    @Published var bestMoveScore: Double?
    /// G17 switch suggestion: the party slot to switch to, only when the
    /// current best move is 1/2x or worse and the switch is 2x or better.
    /// Nil otherwise — no suggestion is shown, not a weak one.
    @Published var switchSuggestionSlot: Int?
    @Published var switchSuggestionNote: String?

    /// G18 last ball: the game id + count of the last Poke Ball used via
    /// the bag flow, remembered for the one-tap replay. The replay itself
    /// is View-side. It only applies in a wild battle with one foe and a
    /// free party slot — the View must check those before offering it.
    @Published var lastBallGameId: Int?
    @Published var lastBallCount: Int?

    /// Records the last ball used (called from the bag flow). The count is
    /// looked up from the most recent live bag poll and may be pre-use.
    func recordLastBall(gameId: Int) {
        lastBallGameId = gameId
        lastBallCount = bagPockets.flatMap { $0.entries }.first(where: { $0.gameId == gameId })?.count
    }

    // MARK: Map state (live position, re-walked every poll)
    @Published var mapPosition: PokemonXMapPosition?
    @Published var mapStatus = "No live position yet — walk around in the field to see where you are."
    var mapAreaLabel: String {
        mapPosition?.areaLabel ?? "No live position"
    }
    var mapDotVisible: Bool {
        guard let position = mapPosition else { return false }
        return PokemonXMapPosition.dotVisible(forMapId: position.mapId)
    }
    /// G8 live half: wild encounters for the current area, from the
    /// enriched Dex. Currently always empty: the map-ID -> area mapping
    /// was disproved (HUNTS-REPORT-2026-11-19.md §0d), so rawAreaName
    /// returns nil for every map rather than a wrong area's list.
    var guideAreaEncounters: [PokemonXGuideEncounter] {
        guard let position = mapPosition,
              let rawArea = PokemonXMapPosition.rawAreaName(forMapId: position.mapId) else { return [] }
        return PokemonXCompanionData.encounters(inArea: rawArea)
    }

    // MARK: Bag state (live counts, guard-checked every poll)
    @Published var bagPockets: [PokemonXBagPocket] = []
    @Published var bagIsLive = false
    @Published var bagStatus = "No live bag yet — the bag read needs a live game session."

    // MARK: Nuzlocke state (G27)
    @Published var nuzlockeRuns: [PokemonXNuzlockeRun] = []
    var activeNuzlockeRun: PokemonXNuzlockeRun? {
        nuzlockeRuns.first(where: { $0.isActive })
    }

    func startNuzlockeRun(name: String) {
        for index in nuzlockeRuns.indices { nuzlockeRuns[index].isActive = false }
        nuzlockeRuns.append(PokemonXNuzlockeRun(name: name))
    }

    func endNuzlockeRun() {
        guard let run = activeNuzlockeRun,
              let index = nuzlockeRuns.firstIndex(where: { $0.id == run.id }) else { return }
        nuzlockeRuns[index].isActive = false
    }

    /// Manual first-catch log for an area (automatic logging needs the G2
    /// Dex flags, which are unmapped — the run's per-area rule is enforced
    /// here: a second catch in the same area is not recorded).
    func recordNuzlockeCatch(speciesName: String, areaLabel: String) {
        guard var run = activeNuzlockeRun,
              !run.hasCaught(inArea: areaLabel),
              let index = nuzlockeRuns.firstIndex(where: { $0.id == run.id }) else { return }
        run.catches.append(PokemonXNuzlockeCatch(speciesName: speciesName, areaLabel: areaLabel, date: Date()))
        nuzlockeRuns[index] = run
    }

    // MARK: Card state (G6, placeholder)
    @Published var trainerCard = PokemonXTrainerCard.placeholder

    /// Tap-for-detail selection (G9a). Nil = no slot selected.
    @Published var selectedPartySlotIndex: Int?
    var selectedPartyDetail: PokemonXPartyDetail? {
        guard let index = selectedPartySlotIndex,
              index < partySlots.count else { return nil }
        let slot = partySlots[index]
        guard let speciesName = slot.speciesName else { return nil }
        let speciesId = PokemonXCompanionData.pokemon.first(where: { $0.name == speciesName.lowercased() })?.id
        let level = slot.level ?? 0
        return PokemonXPartyDetail(
            slotId: index,
            speciesId: speciesId,
            speciesName: speciesName,
            level: slot.level,
            currentHP: slot.currentHP,
            maxHP: slot.maxHP,
            stats: slot.stats,
            types: slot.types,
            moves: slot.moves,
            nextMovesToLearn: speciesId.map { PokemonXCompanionData.nextMovesToLearn(speciesId: $0, level: level) } ?? [],
            status: slot.status,
            heldItemName: slot.heldItemName,
            abilityName: slot.abilityName,
            currentExp: slot.currentExp,
            trainerId: slot.trainerId,
            secretId: slot.secretId,
            personalityId: slot.personalityId,
            fieldAttack: slot.fieldAttack,
            fieldDefense: slot.fieldDefense,
            fieldSpecialAttack: slot.fieldSpecialAttack)
    }

    /// True only once the bridge has a real read callback AND a read returned data.
    @Published var isLiveDataAvailable = false
    /// Human-readable bridge status shown in the overlay header.
    @Published var bridgeStatus = "No live data yet — companion is not connected to the game."

    private var pollTimer: Timer?
    /// Previous battle HP per party slot, for G27 faint detection.
    private var previousBattleHP: [Int: Int] = [:]

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
        // Map + bag are independent of battle: poll them every tick and
        // clear them on any failed validation — never stale data.
        pollMapOnce()
        pollBagOnce()

        // Field party (G1 + field HP, HUNTS-REPORT-2 §2.3 + REPORT-3 §4):
        // the 6 slots' species/level/held/ability/EXP/TID/SID/PID + HP.
        // The Party tab's base data, in the field AND in battle.
        // Fallback: the heap scan (checksum-validated blobs + wrapper
        // search for the HP block). Nil only when the table is unreadable
        // AND the scan finds nothing.
        let fieldSlots = PokemonXFieldPartyReader.readFieldParty()
            ?? PokemonXFieldPartyReader.scanForParty()

        // Battle structs (§1.4): active player + active foe, with live
        // HP / moves / stats / types. Nil when no battle is running.
        let battle = PokemonXBattleStructReader.readBattleStructs()

        // Nothing live at all: clear everything, never stale data.
        guard fieldSlots != nil || battle.player != nil || battle.enemy != nil else {
            if isLiveDataAvailable {
                isLiveDataAvailable = false
                partySlots = (0..<6).map { PokemonXPartySlot.empty(id: $0) }
                battleMoves = (0..<4).map { PokemonXBattleMoveSlot.empty(id: $0) }
                enemyActive = nil
                enemyTeam = [nil, nil, nil, nil, nil, nil]
                bestMoveIndex = nil
                bestMoveScore = nil
                switchSuggestionSlot = nil
                switchSuggestionNote = nil
                previousBattleHP = [:]
            }
            bridgeStatus = "No live data yet — start the game to see your party."
            return
        }
        isLiveDataAvailable = true
        if fieldSlots != nil && battle.player != nil {
            bridgeStatus = "Live — party + battle."
        } else if fieldSlots != nil {
            bridgeStatus = "Live — reading your party from the field."
        } else {
            bridgeStatus = "Live — reading the battle (party read unavailable)."
        }

        // The foe's types drive every matchup (G15/G17). The battle read
        // gives the ACTIVE foe only — the other enemy slots are unknown
        // (the old 6-slot enemy array held wrappers, not structs).
        let foeTypes: [String] = battle.enemy?.types ?? []
        if let foe = battle.enemy {
            var slot = PokemonXPartySlot.empty(id: 0)
            slot.speciesName = PokemonXCompanionData.pokemon.first(where: { $0.id == foe.species })?.name.capitalized ?? "#\(foe.species)"
            slot.level = foe.level
            slot.currentHP = foe.currentHP
            slot.maxHP = foe.maxHP
            slot.stats = foe.stats
            slot.types = foe.types
            enemyActive = slot
            enemyTeam = [slot, nil, nil, nil, nil, nil]
        } else {
            enemyActive = nil
            enemyTeam = [nil, nil, nil, nil, nil, nil]
        }

        // Party slots from the field read; the battle struct enriches the
        // active slot (matched by species) with live HP/moves/stats/types.
        var newPartySlots: [PokemonXPartySlot] = (0..<6).map { PokemonXPartySlot.empty(id: $0) }
        if let fieldSlots {
            for (index, field) in fieldSlots.enumerated() {
                guard let field else {
                    newPartySlots[index].isKnownEmpty = true
                    continue
                }
                var slot = PokemonXPartySlot.empty(id: index)
                slot.speciesName = PokemonXCompanionData.pokemon.first(where: { $0.id == field.species })?.name.capitalized ?? "#\(field.species)"
                slot.level = field.level
                slot.currentHP = field.currentHP
                slot.maxHP = field.maxHP
                // Status 0 = healthy (no status to show). A nonzero code
                // is shown raw — only 0 was observed live, so no condition
                // name is guessed (HUNTS-REPORT-3 §5).
                if let statusCode = field.statusCode, statusCode != 0 {
                    slot.status = "Status #\(statusCode)"
                }
                slot.heldItemName = PokemonXCompanionData.displayItemName(forGameId: field.heldItemGameId)
                slot.abilityName = PokemonXCompanionData.displayAbilityName(forId: field.abilityId)
                slot.currentExp = field.exp
                slot.trainerId = field.trainerId
                slot.secretId = field.secretId
                slot.personalityId = field.personalityId
                slot.fieldAttack = field.fieldAttack
                slot.fieldDefense = field.fieldDefense
                slot.fieldSpecialAttack = field.fieldSpecialAttack
                newPartySlots[index] = slot
            }
        }
        // Battle enrichment (G10 by species match — no index field is
        // hunted). During battle the field block holds PRE-BATTLE HP, so
        // the active slot's HP comes from the battle struct; benched slots
        // keep their field HP (unchanged in battle). When the field read
        // fails entirely, the active battler is slot 0 by assumption
        // (labelled in the View); when the species does not match any
        // field slot, no party slot is enriched — the Battle tab still
        // shows the active battler.
        if let player = battle.player {
            let playerName = PokemonXCompanionData.pokemon.first(where: { $0.id == player.species })?.name.capitalized ?? "#\(player.species)"
            var activeIndex = 0
            if let match = newPartySlots.firstIndex(where: { $0.speciesName == playerName }) {
                activeIndex = match
            } else if fieldSlots == nil {
                var slot = PokemonXPartySlot.empty(id: 0)
                slot.speciesName = playerName
                slot.level = player.level
                newPartySlots[0] = slot
            }
            if newPartySlots[activeIndex].speciesName == playerName {
                var slot = newPartySlots[activeIndex]
                slot.currentHP = player.currentHP
                slot.maxHP = player.maxHP
                slot.stats = player.stats
                slot.types = player.types
                slot.moves = movesWithMatchups(player.moves, foeTypes: foeTypes)
                newPartySlots[activeIndex] = slot
            }
            activeBattlerIndex = activeIndex
            battleMoves = movesWithMatchups(player.moves, foeTypes: foeTypes)
        } else {
            battleMoves = (0..<4).map { PokemonXBattleMoveSlot.empty(id: $0) }
        }
        partySlots = newPartySlots

        // G27 death detection: a party member's HP hitting 0 is a faint.
        // During battle the active slot's HP is the live battle-struct
        // HP, so a faint is caught the poll it happens; benched slots
        // carry field HP (unchanged in battle), so they cannot false-fire.
        for (index, slot) in partySlots.enumerated() {
            if let previous = previousBattleHP[index], previous > 0,
               let current = slot.currentHP, current == 0 {
                recordFaint(slot: slot)
            }
            previousBattleHP[index] = slot.currentHP
        }
        updateBestPick(foeTypes: foeTypes)
    }

    /// Builds Battle tab move slots from a battle struct's moves, with
    /// G15 matchup data (effectiveness vs the foe's types, from the full
    /// G4 move table + the verified type chart) and the G17 score.
    private func movesWithMatchups(_ moves: [(id: Int, pp: Int, maxPP: Int)], foeTypes: [String]) -> [PokemonXBattleMoveSlot] {
        moves.enumerated().map { moveIndex, move in
            var moveSlot = PokemonXBattleMoveSlot.empty(id: moveIndex)
            if move.id != 0 {
                let known = PokemonXCompanionData.moves.first(where: { $0.id == move.id })
                moveSlot.name = known?.name.capitalized ?? "Move #\(move.id)"
                moveSlot.type = known?.type
                moveSlot.power = known?.power
                moveSlot.currentPP = move.pp
                moveSlot.maxPP = move.maxPP
                if let type = known?.type, !foeTypes.isEmpty {
                    let effectiveness = PokemonXCompanionData.effectiveness(attacking: type, defending: foeTypes)
                    moveSlot.effectiveness = effectiveness
                    if let power = known?.power {
                        moveSlot.score = effectiveness * Double(power)
                    }
                }
            }
            return moveSlot
        }
    }

    /// G17 best pick: score = effectiveness x power per move; highlight the
    /// highest. In the Shauna battle the answer must be Vine Whip
    /// (2x45=90) over Tackle (1x50=50). A switch is suggested only when the
    /// current best is 1/2x or worse and a switch is 2x or better.
    private func updateBestPick(foeTypes: [String]) {
        bestMoveIndex = nil
        bestMoveScore = nil
        switchSuggestionSlot = nil
        switchSuggestionNote = nil
        guard !foeTypes.isEmpty else { return }
        guard let best = bestScoredMove(in: battleMoves) else { return }
        if let index = battleMoves.firstIndex(where: { $0.score == best.score && $0.effectiveness == best.effectiveness }) {
            bestMoveIndex = index
            bestMoveScore = best.score
        }
        guard best.effectiveness <= 0.5 else { return }
        var bestSwitch: (slot: Int, score: Double, effectiveness: Double)?
        for (slotIndex, slot) in partySlots.enumerated() where slotIndex != activeBattlerIndex {
            guard !slot.isKnownEmpty, slot.speciesName != nil,
                  let candidate = bestScoredMove(in: slot.moves),
                  candidate.effectiveness >= 2.0 else { continue }
            if bestSwitch == nil || candidate.score > bestSwitch!.score {
                bestSwitch = (slot: slotIndex, score: candidate.score, effectiveness: candidate.effectiveness)
            }
        }
        if let suggestion = bestSwitch, let name = partySlots[suggestion.slot].speciesName {
            switchSuggestionSlot = suggestion.slot
            switchSuggestionNote = "Switch to \(name) — its best move is \(suggestion.effectiveness)x against this foe."
        }
    }

    /// Highest-scoring move in a slot's move list (score + effectiveness
    /// together, so ties on score do not mix up the effectiveness).
    private func bestScoredMove(in moves: [PokemonXBattleMoveSlot]) -> (effectiveness: Double, score: Double)? {
        var best: (effectiveness: Double, score: Double)?
        for move in moves {
            guard let effectiveness = move.effectiveness, let score = move.score else { continue }
            if best == nil || score > best!.score {
                best = (effectiveness: effectiveness, score: score)
            }
        }
        return best
    }

    private func recordFaint(slot: PokemonXPartySlot) {
        guard var run = activeNuzlockeRun,
              let index = nuzlockeRuns.firstIndex(where: { $0.id == run.id }) else { return }
        run.deaths.append(PokemonXNuzlockeDeath(
            speciesName: slot.speciesName ?? "Unknown",
            level: slot.level,
            areaLabel: mapAreaLabel,
            date: Date()))
        nuzlockeRuns[index] = run
    }

    private func pollMapOnce() {
        guard let position = PokemonXLiveMapReader.readMapPosition() else {
            // Singleton 0 (title screen, battle, no field system) or any
            // chain step unreadable: never show a stale dot.
            if mapPosition != nil { mapPosition = nil }
            mapStatus = "No live position — walk around in the field to see where you are."
            return
        }
        mapPosition = position
        mapStatus = "Live — \(position.areaLabel) (\(Int(position.gridX)), \(Int(position.gridZ)))."
    }

    private func pollBagOnce() {
        guard let pockets = PokemonXLiveBagReader.readBag() else {
            // Guard failed (Letter moved) or no callback: never stale counts.
            if bagIsLive {
                bagIsLive = false
                bagPockets = []
            }
            bagStatus = "No live bag — the bag read needs a live game session."
            return
        }
        bagIsLive = true
        bagPockets = pockets
        let total = pockets.flatMap { $0.entries }.reduce(0) { $0 + $1.count }
        bagStatus = "Live — \(total) item(s) across \(pockets.count) pockets."
    }

    deinit { stopPolling() }
}

// MARK: - Live party read (verified Pokemon X battle structs)

/// Little-endian guest-memory helpers shared by the party, map and bag
/// readers. All reads go through HUDMemoryBridge and return nil on any
/// failure — never invented bytes.
private enum PokemonXGuestMemory {
    static func u16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    static func u32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    static func f32LE(_ data: Data, _ offset: Int) -> Float {
        Float(bitPattern: u32LE(data, offset))
    }

    /// One 4-byte little-endian read, or nil when the bridge cannot read it.
    static func readU32(at address: UInt32) -> UInt32? {
        guard let data = HUDMemoryBridge.shared().readBytes(atAddress: address, length: 4),
              data.count == 4 else { return nil }
        return u32LE(data, 0)
    }
}

/// Live read for Pokemon X battles — stat structs (HUNTS-REPORT-2 §1.4).
///
/// The battle stat structs live in the 3DS heap as a contiguous 4 x 0x244
/// array at base VA 0x082059D8: player = base+0, enemy = base+0x244, and
/// mirrored copies at +0x488 (player) / +0x6CC (enemy). Both copies are
/// live-mirrored (HUNTS-REPORT-2 §1.3: Tackle damage + PP decrement show
/// in both). The pinned battle ARRAYS at 0x081FD3CC / 0x081FEB14 are NOT
/// the read target — they hold wrapper objects (pointer-structs), not
/// battle structs (HUNTS-REPORT-2 §1.1, re-verified live). Never read them.
///
/// BATTLE struct offsets (NOT PK6), confirmed live in the Shauna battle
/// (HUNTS-REPORT-2 §1.2): species u16 +0x0C, HP max u16 +0x0E, HP current
/// u16 +0x10 (LIVE — +0x0E is max, not current), level u8 +0x18, moves
/// 4 x 0xE at +0x116 (move ID u16 +0, PP cur u8 +8 = +0x11E — the LIVE PP
/// copy per §1.4 — PP max u8 +9; the slot+2/+3 copies hold the same values
/// per LEVEL-HUNT §6c). Stats 5 x u16 at +0xF6..+0xFE (ATK/DEF/SPA/SPD/
/// SPE). Types are two u8 game type ids at +0x100 (audit G15: Froakie
/// 10/10 = Water/Water — the battle-data hunt report does not document
/// +0x100 itself, so both bytes are validated 0...17 and yield nil types
/// on failure). +0x08 is the current-level EXP threshold (179 at Lv6),
/// NOT current EXP, and is never read.
///
/// Validation (every poll, every struct): species 1...721, level 1...100,
/// HP max > 0, HP cur <= HP max. Primary copy first, mirror on failure;
/// both failing means no battle (or the structs moved) — placeholder,
/// never stale data. If the pinned base fails, a structural scan of
/// 0x08200000–0x08210000 (throttled to once per 30 s, result cached)
/// finds the 0x244-strided mirrored pair; the 4-struct layout is the
/// signature, a single struct match is not enough. Fresh-boot stability
/// is UNPROVEN for all VAs — validation + scan fallback is the
/// mitigation; the phone test (G34) is the decider.
private enum PokemonXBattleRead {
    /// Battle stat-struct array base: player = base, enemy = base+0x244.
    static let structBaseVA: UInt32 = 0x082059D8
    /// Stride between the four structs (player, enemy, player mirror,
    /// enemy mirror). Also the read length per struct.
    static let structStride: UInt32 = 0x244
    /// Mirror offset: player mirror = base+0x488, enemy mirror = base+0x6CC.
    static let mirrorOffset: UInt32 = 0x488
    static let partySlotCount = 6

    static let speciesOffset = 0x0C
    static let hpMaxOffset = 0x0E
    static let hpCurrentOffset = 0x10
    static let levelOffset = 0x18
    static let movesOffset = 0x116
    static let moveStride = 0xE
    static let statsOffset = 0xF6
    static let typesOffset = 0x100

    /// Structural-scan region (HUNTS-REPORT-2 §1.4 fallback).
    static let scanRegionStart: UInt32 = 0x08200000
    static let scanRegionLength: UInt32 = 0x10000
    /// Scan chunk size (bridge reads) and minimum seconds between scans.
    static let scanChunkLength: UInt32 = 0x1000
    static let scanThrottleSeconds: TimeInterval = 30

    /// Gen 6 species range (Pokemon X). A species outside this range means the
    /// heap base moved (or no battle is running) — not a real Pokemon.
    static func isPlausibleSpecies(_ species: Int) -> Bool {
        species >= 1 && species <= 721
    }

    /// Level range. A level outside this range means the struct is not a
    /// live battle struct — same fail-safe pattern as the species check.
    static func isPlausibleLevel(_ level: Int) -> Bool {
        level >= 1 && level <= 100
    }

    /// Gen VI internal type numbering (NOT PokeAPI type ids — PokeAPI water
    /// is 11). Water = 10 here, per the audit's Froakie 10/10 reading and
    /// the HUNTS-REPORT-2 §1.2 table (Chespin 11/11 = Grass, Froakie
    /// 10/10 = Water). Nil for any id outside 0...17 — never a guessed type.
    static func gameTypeName(_ gameTypeId: Int) -> String? {
        switch gameTypeId {
        case 0: return "normal"
        case 1: return "fighting"
        case 2: return "flying"
        case 3: return "poison"
        case 4: return "ground"
        case 5: return "rock"
        case 6: return "bug"
        case 7: return "ghost"
        case 8: return "steel"
        case 9: return "fire"
        case 10: return "water"
        case 11: return "grass"
        case 12: return "electric"
        case 13: return "psychic"
        case 14: return "ice"
        case 15: return "dragon"
        case 16: return "dark"
        case 17: return "fairy"
        default: return nil
        }
    }
}

/// One live battler parsed from a battle stat struct (player or foe).
private struct PokemonXLiveSlot {
    let species: Int
    let level: Int
    let currentHP: Int
    let maxHP: Int
    /// (move ID, PP cur, PP max) x 4; move ID 0 = empty move slot.
    let moves: [(id: Int, pp: Int, maxPP: Int)]
    /// Current in-battle stats (ATK/DEF/SPA/SPD/SPE) from +0xF6..+0xFE.
    let stats: PokemonXBattleStats
    /// Types from +0x100 (two u8 game type ids, deduplicated). Nil when
    /// either byte is outside 0...17 — the slot is still trusted, only
    /// its types are unknown.
    let types: [String]?
}

private enum PokemonXBattleStructReader {
    /// Scan-discovered struct base (cached once found; cleared when it
    /// stops validating). Nil until a scan succeeds.
    private static var discoveredBase: UInt32?
    private static var lastScanAttempt: Date?

    /// Reads the active player + enemy battle structs. Fast path is the
    /// pinned base + per-side mirror; the structural scan runs only when
    /// the pinned base fails for BOTH sides (throttled, cached).
    /// Returns (nil, nil) when no battle is running or the structs moved.
    static func readBattleStructs() -> (player: PokemonXLiveSlot?, enemy: PokemonXLiveSlot?) {
        let bridge = HUDMemoryBridge.shared()
        guard bridge.hasLiveDataSource else { return (nil, nil) }
        var result = readPair(at: PokemonXBattleRead.structBaseVA)
        if result.player != nil || result.enemy != nil { return result }
        if let discovered = discoveredBase {
            result = readPair(at: discovered)
            if result.player != nil || result.enemy != nil { return result }
            discoveredBase = nil
        }
        guard let found = scanForStructBase() else { return (nil, nil) }
        discoveredBase = found
        return readPair(at: found)
    }

    /// Reads the player + enemy structs at `base` (player = base,
    /// enemy = base+0x244), falling back to each side's mirror
    /// (player base+0x488, enemy base+0x6CC) when its primary fails.
    private static func readPair(at base: UInt32) -> (player: PokemonXLiveSlot?, enemy: PokemonXLiveSlot?) {
        let player = readOne(primary: base, mirror: base + PokemonXBattleRead.mirrorOffset)
        let enemy = readOne(primary: base + PokemonXBattleRead.structStride,
                            mirror: base + PokemonXBattleRead.structStride + PokemonXBattleRead.mirrorOffset)
        return (player, enemy)
    }

    private static func readOne(primary: UInt32, mirror: UInt32) -> PokemonXLiveSlot? {
        let bridge = HUDMemoryBridge.shared()
        if let data = bridge.readBytes(atAddress: primary, length: PokemonXBattleRead.structStride),
           data.count == Int(PokemonXBattleRead.structStride),
           let slot = parseStruct(data) { return slot }
        if let data = bridge.readBytes(atAddress: mirror, length: PokemonXBattleRead.structStride),
           data.count == Int(PokemonXBattleRead.structStride),
           let slot = parseStruct(data) { return slot }
        return nil
    }

    /// Validates + parses one raw struct (0x244 bytes). Nil when any
    /// check fails: species 1...721, level 1...100, HP max > 0,
    /// HP cur <= HP max.
    static func parseStruct(_ data: Data) -> PokemonXLiveSlot? {
        guard data.count >= Int(PokemonXBattleRead.structStride) else { return nil }
        let species = Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.speciesOffset))
        guard PokemonXBattleRead.isPlausibleSpecies(species) else { return nil }
        let level = Int(data[PokemonXBattleRead.levelOffset])
        guard PokemonXBattleRead.isPlausibleLevel(level) else { return nil }
        let hpMax = Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.hpMaxOffset))
        guard hpMax > 0 else { return nil }
        let hpCur = Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.hpCurrentOffset))
        guard hpCur <= hpMax else { return nil }
        var moves: [(id: Int, pp: Int, maxPP: Int)] = []
        for moveIndex in 0..<4 {
            let base = PokemonXBattleRead.movesOffset + moveIndex * PokemonXBattleRead.moveStride
            let moveID = Int(PokemonXGuestMemory.u16LE(data, base))
            // LIVE PP copy at slot+8 (+0x11E, HUNTS-REPORT-2 §1.4) and
            // its max at slot+9 (LEVEL-HUNT §6c).
            let pp = Int(data[base + 8])
            let maxPP = Int(data[base + 9])
            moves.append((id: moveID, pp: pp, maxPP: maxPP))
        }
        let stats = PokemonXBattleStats(
            attack: Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.statsOffset)),
            defense: Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.statsOffset + 2)),
            specialAttack: Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.statsOffset + 4)),
            specialDefense: Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.statsOffset + 6)),
            speed: Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.statsOffset + 8)))
        let type1 = Int(data[PokemonXBattleRead.typesOffset])
        let type2 = Int(data[PokemonXBattleRead.typesOffset + 1])
        let types: [String]? = {
            guard let first = PokemonXBattleRead.gameTypeName(type1),
                  let second = PokemonXBattleRead.gameTypeName(type2) else { return nil }
            return first == second ? [first] : [first, second]
        }()
        return PokemonXLiveSlot(species: species, level: level, currentHP: hpCur, maxHP: hpMax, moves: moves, stats: stats, types: types)
    }

    /// True when two raw struct blobs agree on every validated field
    /// (species, HP, level, moves, stats, types). The +0x00 back-pointer
    /// is NOT compared — the mirror's back-pointer targets a different
    /// wrapper (HUNTS-REPORT-2 §1.2), so the mirrors are not byte-identical.
    static func structValuesEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count >= Int(PokemonXBattleRead.structStride),
              b.count >= Int(PokemonXBattleRead.structStride) else { return false }
        for off in [PokemonXBattleRead.speciesOffset, PokemonXBattleRead.hpMaxOffset,
                    PokemonXBattleRead.hpCurrentOffset] {
            guard PokemonXGuestMemory.u16LE(a, off) == PokemonXGuestMemory.u16LE(b, off) else { return false }
        }
        guard a[PokemonXBattleRead.levelOffset] == b[PokemonXBattleRead.levelOffset] else { return false }
        for moveIndex in 0..<4 {
            let base = PokemonXBattleRead.movesOffset + moveIndex * PokemonXBattleRead.moveStride
            guard PokemonXGuestMemory.u16LE(a, base) == PokemonXGuestMemory.u16LE(b, base),
                  a[base + 8] == b[base + 8], a[base + 9] == b[base + 9] else { return false }
        }
        for off in stride(from: PokemonXBattleRead.statsOffset, to: PokemonXBattleRead.statsOffset + 10, by: 2) {
            guard PokemonXGuestMemory.u16LE(a, off) == PokemonXGuestMemory.u16LE(b, off) else { return false }
        }
        return a[PokemonXBattleRead.typesOffset] == b[PokemonXBattleRead.typesOffset]
            && a[PokemonXBattleRead.typesOffset + 1] == b[PokemonXBattleRead.typesOffset + 1]
    }

    /// Structural scan (HUNTS-REPORT-2 §1.4 fallback): reads the
    /// 0x08200000–0x08210000 region in 4 KB chunks and finds a base X
    /// where A (X), B (X+0x244) and both mirrors (X+0x488, X+0x6CC) all
    /// validate AND each mirror's values equal its primary. The 4-struct
    /// mirrored layout is the signature — a single struct match is not
    /// enough. Throttled to once per 30 s; nil when nothing is found.
    static func scanForStructBase() -> UInt32? {
        let now = Date()
        if let last = lastScanAttempt,
           now.timeIntervalSince(last) < PokemonXBattleRead.scanThrottleSeconds { return nil }
        lastScanAttempt = now
        let bridge = HUDMemoryBridge.shared()
        guard bridge.hasLiveDataSource else { return nil }
        var region = Data()
        region.reserveCapacity(Int(PokemonXBattleRead.scanRegionLength))
        var address = PokemonXBattleRead.scanRegionStart
        while address < PokemonXBattleRead.scanRegionStart + PokemonXBattleRead.scanRegionLength {
            guard let chunk = bridge.readBytes(atAddress: address, length: PokemonXBattleRead.scanChunkLength),
                  chunk.count == Int(PokemonXBattleRead.scanChunkLength) else { return nil }
            region.append(chunk)
            address += PokemonXBattleRead.scanChunkLength
        }
        let stride = Int(PokemonXBattleRead.structStride)
        var offset = 0
        while offset + 4 * stride <= region.count {
            // Cheap pre-filter: both structs' species must be plausible
            // before the full parse (most offsets fail here).
            let aSpecies = Int(PokemonXGuestMemory.u16LE(region, offset + PokemonXBattleRead.speciesOffset))
            let bSpecies = Int(PokemonXGuestMemory.u16LE(region, offset + stride + PokemonXBattleRead.speciesOffset))
            guard PokemonXBattleRead.isPlausibleSpecies(aSpecies),
                  PokemonXBattleRead.isPlausibleSpecies(bSpecies) else {
                offset += 4
                continue
            }
            let a = region.subdata(in: offset..<(offset + stride))
            let b = region.subdata(in: (offset + stride)..<(offset + 2 * stride))
            let aMirror = region.subdata(in: (offset + 2 * stride)..<(offset + 3 * stride))
            let bMirror = region.subdata(in: (offset + 3 * stride)..<(offset + 4 * stride))
            if parseStruct(a) != nil, parseStruct(b) != nil,
               parseStruct(aMirror) != nil, parseStruct(bMirror) != nil,
               structValuesEqual(a, aMirror), structValuesEqual(b, bMirror) {
                return PokemonXBattleRead.scanRegionStart + UInt32(offset)
            }
            offset += 4
        }
        return nil
    }
}

// MARK: - Live field party read (G1, HUNTS-REPORT-2 §2.3)

/// One field party slot, from the XOR-encrypted 232-byte PKM blob.
/// Species / level (derived from EXP) / held item / ability / TID / SID /
/// EXP / PID are the FIXED block-A fields — the only fields wireable from
/// the blob. HP / status / Atk / Def / SpA come from the wrapper's +0x08
/// 24-byte block (HUNTS-REPORT-3 §4); nickname / moves / PP are
/// shuffle-dependent (only idx 1 + 9 mapped); IVs / EVs / nature are
/// unconfirmed. Never guessed, never computed.
private struct PokemonXFieldSlot {
    let species: Int
    let level: Int
    let heldItemGameId: Int
    let abilityId: Int
    let trainerId: Int
    let secretId: Int
    let exp: Int
    let personalityId: Int
    /// OUTSIDE-BATTLE HP/status/stats from the wrapper's +0x08 24-byte
    /// block (HUNTS-REPORT-3 §4). Nil when the block is unreadable or
    /// fails validation — HP unknown, never stale. During a battle the
    /// block holds PRE-BATTLE HP, so the poll overrides the active slot's
    /// HP with the battle struct's live HP instead.
    var currentHP: Int? = nil
    var maxHP: Int? = nil
    /// Status byte (+0x00): 0 = healthy. Only 0 observed live; other
    /// values are standard Gen 6 status codes, unobserved — shown as a
    /// raw code, never a guessed condition name.
    var statusCode: Int? = nil
    /// Atk / Def / SpA from the block (+0x0C / +0x0E / +0x12). The
    /// +0x10 / +0x14 pair (Speed vs Sp. Def) is NOT wired — their order
    /// is unproven (both 10 at Lv6 for this Chespin).
    var fieldAttack: Int? = nil
    var fieldDefense: Int? = nil
    var fieldSpecialAttack: Int? = nil
}

/// HP/status/stats from one slot's +0x08 24-byte block, decrypted and
/// validated (HUNTS-REPORT-3 §4 steps 4–6).
private struct PokemonXFieldHP {
    let statusCode: Int
    let level: Int
    let currentHP: Int
    let maxHP: Int
    let attack: Int
    let defense: Int
    let specialAttack: Int
}

private enum PokemonXFieldPartyReader {
    /// Party pointer table base: 6 wrapper pointers at +0x00..+0x17,
    /// party count (u32) at +0x18. NOT 0x08CE1C58 — a leading 0x0 u32
    /// sits at 0x08CE1C58 (HUNTS-REPORT-2 §2.2).
    static let tableBaseVA: UInt32 = 0x08CE1C5C
    static let slotCount = 6
    /// 232-byte XOR-encrypted PKM blob at the wrapper's +0x04 target.
    static let blobLength = 232
    /// Heap-scan fallback region (bounded; the spec says "scan the heap"
    /// without fixing a region — this 1 MB window covers the bag, party
    /// table and PKM area around the known VAs).
    static let scanRegionStart: UInt32 = 0x08C00000
    static let scanRegionLength: UInt32 = 0x100000
    static let scanChunkLength: UInt32 = 0x1000
    static let scanThrottleSeconds: TimeInterval = 30

    private static var lastScanAttempt: Date?

    /// Reads all 6 party slots through the pinned table. Returns nil when
    /// the table itself is unreadable or its count is not 0...6 (the heap
    /// base moved) — the caller then tries the scan fallback. Per-slot nil
    /// means empty/invalid (null wrapper, null PKM, or a blob failing
    /// sanity/checksum/species — how the shared empty-slot blob is
    /// rejected). An all-nil result with a readable table is a genuine
    /// empty party, not a failure.
    static func readFieldParty() -> [PokemonXFieldSlot?]? {
        let bridge = HUDMemoryBridge.shared()
        guard bridge.hasLiveDataSource else { return nil }
        guard let tableData = bridge.readBytes(atAddress: tableBaseVA, length: UInt32(slotCount * 4)),
              tableData.count == slotCount * 4 else { return nil }
        // Party count (u32) at table+0x18: 0...6 when the table is live.
        // A larger value means the table base moved — trust nothing.
        guard let countData = bridge.readBytes(atAddress: tableBaseVA + 0x18, length: 4),
              countData.count == 4 else { return nil }
        guard PokemonXGuestMemory.u32LE(countData, 0) <= UInt32(slotCount) else { return nil }
        var slots: [PokemonXFieldSlot?] = []
        for index in 0..<slotCount {
            let wrapper = PokemonXGuestMemory.u32LE(tableData, index * 4)
            guard wrapper != 0 else { slots.append(nil); continue }
            guard let pkmVA = PokemonXGuestMemory.readU32(at: wrapper + 0x04), pkmVA != 0 else {
                slots.append(nil)
                continue
            }
            guard let blob = bridge.readBytes(atAddress: pkmVA, length: UInt32(blobLength)),
                  blob.count == blobLength,
                  var slot = parseBlob(blob) else {
                slots.append(nil)
                continue
            }
            // Field HP (HUNTS-REPORT-3 §4): the wrapper's +0x08 block,
            // decrypted with the blob's enc_const. A missing/invalid
            // block leaves the slot valid with HP unknown — never stale.
            let encConst = PokemonXGuestMemory.u32LE(blob, 0x00)
            if let hp = readBlock(wrapper: wrapper, encConst: encConst, expectedLevel: slot.level) {
                slot.currentHP = hp.currentHP
                slot.maxHP = hp.maxHP
                slot.statusCode = hp.statusCode
                slot.fieldAttack = hp.attack
                slot.fieldDefense = hp.defense
                slot.fieldSpecialAttack = hp.specialAttack
            }
            slots.append(slot)
        }
        return slots
    }

    /// Reads + decrypts + validates one slot's +0x08 24-byte block
    /// (HUNTS-REPORT-3 §4). The block is reached through the wrapper
    /// pointer — never a hardcoded VA. Decryption is the same LCRNG
    /// keystream as the blob, seeded by enc_const, words 0..11 (NOT
    /// words 112..123 — H2 failed). Validation: level 1...100, HP max
    /// > 0, HP cur <= HP max, AND the block's level must equal the
    /// EXP-derived level (the cross-check — a mismatch means the block
    /// is stale/inconsistent with the blob, so its HP is untrusted).
    /// Nil when the block pointer is 0, the read fails, or any check
    /// fails — HP unknown, never stale or guessed.
    static func readBlock(wrapper: UInt32, encConst: UInt32, expectedLevel: Int) -> PokemonXFieldHP? {
        guard let blk = PokemonXGuestMemory.readU32(at: wrapper + 0x08), blk != 0 else { return nil }
        guard let raw = HUDMemoryBridge.shared().readBytes(atAddress: blk, length: 24),
              raw.count == 24 else { return nil }
        let decrypted = xorDecryptBlock(raw, encConst: encConst)
        let level = Int(decrypted[0x04])
        guard level >= 1 && level <= 100 else { return nil }
        let hpMax = Int(PokemonXGuestMemory.u16LE(decrypted, 0x0A))
        guard hpMax > 0 else { return nil }
        let hpCur = Int(PokemonXGuestMemory.u16LE(decrypted, 0x08))
        guard hpCur <= hpMax else { return nil }
        guard level == expectedLevel else { return nil }
        return PokemonXFieldHP(
            statusCode: Int(decrypted[0x00]),
            level: level,
            currentHP: hpCur, maxHP: hpMax,
            attack: Int(PokemonXGuestMemory.u16LE(decrypted, 0x0C)),
            defense: Int(PokemonXGuestMemory.u16LE(decrypted, 0x0E)),
            specialAttack: Int(PokemonXGuestMemory.u16LE(decrypted, 0x12)))
    }

    /// XOR-decrypts a 24-byte block with the LCRNG keystream seeded by
    /// enc_const, words 0..11 (high-16 per u16). Same keystream as the
    /// blob (HUNTS-REPORT-3 §0: the empty-slot control proves it — a
    /// seed-0 block decrypts to all zeros, and the raw empty blocks ARE
    /// the seed-0 keystream).
    static func xorDecryptBlock(_ block: Data, encConst: UInt32) -> Data {
        var out = block
        var state = encConst
        for i in 0..<12 {
            state = state &* 0x41C64E6D &+ 0x6073
            let key = UInt16((state >> 16) & 0xFFFF)
            let off = i * 2
            let word = PokemonXGuestMemory.u16LE(out, off) ^ key
            out[off] = UInt8(word & 0xFF)
            out[off + 1] = UInt8((word >> 8) & 0xFF)
        }
        return out
    }

    /// XOR-decrypts bytes 0x08–0xE7 (112 u16 words) with the LCRNG
    /// keystream seeded by enc_const (a=0x41C64E6D, c=0x6073, high-16 per
    /// u16 — pk6_decrypt.py _keystream, PROVEN by the checksum match on a
    /// real PKM, HUNTS-REPORT-2 §3.1). Bytes outside 0x08–0xE7 are
    /// returned unchanged. NO unshuffle: the stored layout is NOT a
    /// standard PK6 56-byte block permutation (exhaustive 24-perm brute
    /// force, §3.2) — only the XOR + fixed block-A offsets are used.
    static func xorDecrypt(_ blob: Data, encConst: UInt32) -> Data {
        var out = blob
        var state = encConst
        for i in 0..<112 {
            state = state &* 0x41C64E6D &+ 0x6073
            let key = UInt16((state >> 16) & 0xFFFF)
            let off = 0x08 + i * 2
            let word = PokemonXGuestMemory.u16LE(out, off) ^ key
            out[off] = UInt8(word & 0xFF)
            out[off + 1] = UInt8((word >> 8) & 0xFF)
        }
        return out
    }

    /// Checksum = sum of u16s over the decrypted 0x08–0xE7, mod 0x10000.
    static func checksum(_ decrypted: Data) -> UInt16 {
        var total: UInt32 = 0
        for off in stride(from: 0x08, to: 0xE8, by: 2) {
            total = (total + UInt32(PokemonXGuestMemory.u16LE(decrypted, off))) & 0xFFFF
        }
        return UInt16(total)
    }

    /// Validates + parses one 232-byte blob. Nil when sanity (+0x04) is
    /// not 0, the checksum (+0x06) does not match the decrypted bytes,
    /// the species is outside 1...721, or the level cannot be derived.
    /// Reads the FIXED block-A fields (same offsets in both known blobs,
    /// §3.2): species u16 +0x40, held u16 +0x42, TID/SID u32 +0x44
    /// (TID = low u16, SID = high u16), EXP u32 +0x48, ability u8 +0x4C,
    /// PID u32 +0x50. Level is derived from EXP via the species' growth
    /// rate — the blob does not store level.
    static func parseBlob(_ blob: Data) -> PokemonXFieldSlot? {
        guard blob.count == blobLength else { return nil }
        let encConst = PokemonXGuestMemory.u32LE(blob, 0x00)
        guard PokemonXGuestMemory.u16LE(blob, 0x04) == 0 else { return nil }
        let storedChecksum = PokemonXGuestMemory.u16LE(blob, 0x06)
        let decrypted = xorDecrypt(blob, encConst: encConst)
        guard checksum(decrypted) == storedChecksum else { return nil }
        let species = Int(PokemonXGuestMemory.u16LE(decrypted, 0x40))
        guard PokemonXBattleRead.isPlausibleSpecies(species) else { return nil }
        let held = Int(PokemonXGuestMemory.u16LE(decrypted, 0x42))
        let tidSid = PokemonXGuestMemory.u32LE(decrypted, 0x44)
        let exp = Int(PokemonXGuestMemory.u32LE(decrypted, 0x48))
        let ability = Int(decrypted[0x4C])
        let pid = PokemonXGuestMemory.u32LE(decrypted, 0x50)
        guard let level = PokemonXCompanionData.level(forExp: exp, speciesId: species) else { return nil }
        return PokemonXFieldSlot(
            species: species, level: level, heldItemGameId: held, abilityId: ability,
            trainerId: Int(tidSid & 0xFFFF), secretId: Int(tidSid >> 16),
            exp: exp, personalityId: Int(pid))
    }

    /// Heap-scan fallback (HUNTS-REPORT-2 §2.3 step 7): reads the 1 MB
    /// region around the known party VAs in 4 KB chunks and finds 232-byte
    /// blobs passing sanity+checksum+species. The checksum is the strong
    /// validator (1/65536 false-positive rate per candidate); the sanity
    /// (+0x04 == 0, plaintext) and a nonzero enc_const pre-filter most
    /// offsets before the full decrypt. Found blobs are assigned to slots
    /// in address order (which matches slot order in the known layout) —
    /// the scan cannot tell which slot a blob belongs to. Throttled to
    /// once per 30 s; nil when nothing is found.
    static func scanForParty() -> [PokemonXFieldSlot?]? {
        let now = Date()
        if let last = lastScanAttempt,
           now.timeIntervalSince(last) < scanThrottleSeconds { return nil }
        lastScanAttempt = now
        let bridge = HUDMemoryBridge.shared()
        guard bridge.hasLiveDataSource else { return nil }
        var region = Data()
        region.reserveCapacity(Int(scanRegionLength))
        var address = scanRegionStart
        while address < scanRegionStart + scanRegionLength {
            guard let chunk = bridge.readBytes(atAddress: address, length: scanChunkLength),
                  chunk.count == Int(scanChunkLength) else { return nil }
            region.append(chunk)
            address += scanChunkLength
        }
        var found: [(slot: PokemonXFieldSlot, blobVA: UInt32, encConst: UInt32)] = []
        var offset = 0
        while offset + blobLength <= region.count && found.count < slotCount {
            // Cheap pre-filter on the PLAINTEXT header: sanity must be 0
            // and the encryption constant nonzero (rejects zero regions).
            if PokemonXGuestMemory.u16LE(region, offset + 0x04) == 0,
               PokemonXGuestMemory.u32LE(region, offset) != 0 {
                let blob = region.subdata(in: offset..<(offset + blobLength))
                if let slot = parseBlob(blob) {
                    found.append((slot: slot,
                                  blobVA: scanRegionStart + UInt32(offset),
                                  encConst: PokemonXGuestMemory.u32LE(blob, 0x00)))
                    offset += blobLength
                    continue
                }
            }
            offset += 4
        }
        guard !found.isEmpty else { return nil }
        // Field HP for scanned slots (HUNTS-REPORT-3 §4 step 8): find
        // each blob's wrapper in the region (vtable 0x00598A50 at +0x00,
        // blob pointer at +0x04) and follow its +0x08 block pointer.
        // A slot whose wrapper is not found keeps HP unknown — honest.
        var slots: [PokemonXFieldSlot?] = []
        for entry in found {
            var slot = entry.slot
            if let wrapper = wrapperForBlob(entry.blobVA, in: region),
               let hp = readBlock(wrapper: wrapper, encConst: entry.encConst, expectedLevel: slot.level) {
                slot.currentHP = hp.currentHP
                slot.maxHP = hp.maxHP
                slot.statusCode = hp.statusCode
                slot.fieldAttack = hp.attack
                slot.fieldDefense = hp.defense
                slot.fieldSpecialAttack = hp.specialAttack
            }
            slots.append(slot)
        }
        while slots.count < slotCount { slots.append(nil) }
        return slots
    }

    /// Finds a PKM blob's wrapper in the scanned region: the wrapper's
    /// +0x00 is the vtable 0x00598A50 and its +0x04 is the blob pointer
    /// (HUNTS-REPORT-2 §2.2). Searches for the 8-byte pattern
    /// [vtable][blob VA]; the hit must be 4-aligned. Nil when no wrapper
    /// is found — the caller then shows the slot without HP.
    static func wrapperForBlob(_ blobVA: UInt32, in region: Data) -> UInt32? {
        var pattern = Data([0x50, 0x8A, 0x59, 0x00])
        var le = blobVA.littleEndian
        pattern.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        var searchRange = region.startIndex..<region.endIndex
        while let found = region.range(of: pattern, options: [], in: searchRange) {
            let offset = region.distance(from: region.startIndex, to: found.lowerBound)
            if offset % 4 == 0 {
                return scanRegionStart + UInt32(offset)
            }
            searchRange = found.upperBound..<region.endIndex
        }
        return nil
    }
}

// MARK: - Live map position read (MAP-LIVE-READ-2026-11-19.md)

/// Re-walks the position chain from the fixed singleton slot EVERY poll.
/// Intermediates are never cached: fieldmap-proc/mid/player change when
/// the map changes (the bedroom run proved it) — only the singleton slot
/// VA and the offsets are fixed. Any step unreadable, or the singleton
/// reading 0 (title screen, battle, no field system), means "no live
/// position" — never a stale dot.
private enum PokemonXLiveMapReader {
    /// Singleton slot VA: FUN_003DCFC8 returns the u32 stored here.
    static let singletonVA: UInt32 = 0x005AE748
    /// Position struct: 8 floats + 3 u32s (0x2C bytes) at player+0xBC.
    static let positionStructLength: UInt32 = 0x2C

    static func readMapPosition() -> PokemonXMapPosition? {
        let bridge = HUDMemoryBridge.shared()
        guard bridge.hasLiveDataSource else { return nil }
        guard let singleton = PokemonXGuestMemory.readU32(at: singletonVA), singleton != 0 else { return nil }
        guard let fieldSystem = PokemonXGuestMemory.readU32(at: singleton + 0xC), fieldSystem != 0 else { return nil }
        guard let fieldmapProc = PokemonXGuestMemory.readU32(at: fieldSystem + 0x48), fieldmapProc != 0 else { return nil }
        guard let mid = PokemonXGuestMemory.readU32(at: fieldmapProc + 0x158), mid != 0 else { return nil }
        guard let player = PokemonXGuestMemory.readU32(at: mid + 0xC), player != 0 else { return nil }
        guard let positionData = bridge.readBytes(atAddress: player + 0xBC, length: positionStructLength),
              positionData.count == Int(positionStructLength) else { return nil }
        let gridX = PokemonXGuestMemory.f32LE(positionData, 0x04)
        let gridZ = PokemonXGuestMemory.f32LE(positionData, 0x0C)
        guard gridX.isFinite && gridZ.isFinite else { return nil }
        guard let mapIdData = bridge.readBytes(atAddress: fieldmapProc + 0xE0, length: 1),
              mapIdData.count == 1 else { return nil }
        guard let midData = bridge.readBytes(atAddress: mid + 0x1A, length: 2),
              midData.count == 2 else { return nil }
        return PokemonXMapPosition(
            gridX: gridX,
            gridZ: gridZ,
            mapId: Int(mapIdData[0]),
            secondaryMapId: Int(PokemonXGuestMemory.u16LE(midData, 0)))
    }
}

// MARK: - Live bag read (BAG-VA-HUNT-2026-11-19.md)

/// Reads the whole bag block (0xB88 bytes) in one bridge read and parses
/// the five pockets. The Prof's Letter guard runs on every poll: if the
/// u32 at VA+0x640 is not 82 02 01 00, the VA moved and the whole read is
/// untrusted — "no live bag", never stale counts. Stability across a fresh
/// boot is UNPROVEN (stable across save-state loads in one session only),
/// which is exactly why the guard exists.
private enum PokemonXLiveBagReader {
    static let bagBaseVA: UInt32 = 0x08C67554
    static let bagBlockLength: UInt32 = 0xB88
    static let letterGuardOffset = 0x640
    /// Bytes 82 02 01 00 as a little-endian u32 (Prof's Letter, game id 642).
    static let letterGuardValue: UInt32 = 0x00010282
    /// (key, title, block offset, entry count). Counts are entry counts,
    /// verified against the pocket spans: Items 0x640/4, Key 0x180/4, TM
    /// 0x1A8/4, Medicine 0x100/4, Berry 0x120/4; 738 entries x 4 = 0xB88.
    static let pockets: [(key: String, title: String, offset: Int, entryCount: Int)] = [
        ("items", "Items", 0x000, 400),
        ("key", "Key Items", 0x640, 96),
        ("tm", "TMs & HMs", 0x7C0, 106),
        ("medicine", "Medicine", 0x968, 64),
        ("berry", "Berries", 0xA68, 72),
    ]

    static func readBag() -> [PokemonXBagPocket]? {
        let bridge = HUDMemoryBridge.shared()
        guard bridge.hasLiveDataSource else { return nil }
        guard let data = bridge.readBytes(atAddress: bagBaseVA, length: bagBlockLength),
              data.count == Int(bagBlockLength) else { return nil }
        guard PokemonXGuestMemory.u32LE(data, letterGuardOffset) == letterGuardValue else { return nil }
        return pockets.map { pocket in
            var entries: [PokemonXBagEntry] = []
            for index in 0..<pocket.entryCount {
                let offset = pocket.offset + index * 4
                let itemId = Int(PokemonXGuestMemory.u16LE(data, offset))
                let count = Int(PokemonXGuestMemory.u16LE(data, offset + 2))
                guard itemId != 0, count > 0 else { continue }
                entries.append(PokemonXBagEntry(
                    gameId: itemId,
                    count: count,
                    resolvedName: PokemonXCompanionData.item(forGameId: itemId)?.name.capitalized))
            }
            return PokemonXBagPocket(id: pocket.key, title: pocket.title, entries: entries)
        }
    }
}
