//
//  PokemonXCompanionModels.swift
//  ManicEmu
//
//  PokeDaisy-style companion for Pokemon X (Gen 6) — data models and state.
//  LIVE PARTY READ (2026-11-18/19): PokemonXLivePartyReader reads the verified
//  DllBattle battle structs through HUDMemoryBridge (see PokemonXBattleRead
//  below and PAGE-TABLE-MAPPING-2026-11-18.md). The structs are reached
//  through the party-pointer arrays at 0x081FD3CC (player) / 0x081FEB14
//  (enemy) — BUT those VAs are SESSION-UNSTABLE (HUNTS-REPORT-2026-11-19.md
//  §0a): after a VM restart + state reload the same VAs hold pointer-structs,
//  not battle structs, and the Lv5 Chespin pattern is absent from live RAM
//  during the visible Shauna battle. This read is a GUARDED FALLBACK ONLY:
//  the per-slot species (1...721) + level (1...100) checks gate it, and any
//  failure shows the placeholder, never stale data. A dynamic-discovery spec
//  (signature scan / pointer chain from a stable global) is pending from a
//  follow-up hunt — swap this implementation when it lands. Party and Battle
//  tabs fill from live battle data when a battle is running and the species
//  check passes; otherwise they stay on honest placeholders. Level is u8 at
//  battle-struct +0x18, PROVEN by the Slot 8 fanfare dump (LEVEL-HUNT-
//  2026-11-19.md: Chespin 6, Froakie 5 in the same dump); +0x08 is the
//  current-level EXP threshold, NOT current EXP, and is never read. The
//  enemy read uses the same path on the enemy array (BATTLE-SEND-HUNT-
//  2026-11-19.md: Froakie HP 20→14 live, Bubble PP 30→29 live). Stats are
//  5 x u16 at +0xF6..+0xFE (ATK/DEF/SPA/SPD/SPE, LEVEL-HUNT-2026-11-19.md
//  §2a/§6a); foe types are two u8 game type ids at +0x100 (audit G15:
//  Froakie 10/10 = Water/Water — see the note on PokemonXBattleRead;
//  the battle-data hunt report itself does not document +0x100, so the
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
//  centre measured, needs the G9d held-item field) and G12 multi-target
//  (no target centres measured) — nothing is exposed for them. G9b–G9g
//  (IVs/EVs, status, held item, ability, nature, EXP) are unmapped fields
//  with no ground truth in the lab; the model fields stay nil. G10
//  active-battler tracking is NOT done (the index field is unhunted) —
//  slot 0 stays the assumed active battler, labelled as an assumption.
//  G6 Card data and G2 Dex flags need the save-buffer hunt (not landed);
//  the Card tab is an honest all-unknown placeholder. G7 Boxes, G19 Fly,
//  G21 field items, G26 shiny, G24/G25/G28/G30 are not in this file.
//  Static reference data (type chart, full 721-species enriched Dex,
//  621 moves, 762 items, game-ID item map) comes from PokeAPI
//  (https://pokeapi.co/api/v2/) via PokemonXCompanionData.json, with the
//  generated 26-species/20-move literals in
//  PokemonXCompanionStaticData.swift as fallback — the fallback is the
//  ORIGINAL 26-species/20-move sample only; the JSON is the source of
//  truth and is NOT regenerated into Swift (too big).
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

    enum CodingKeys: String, CodingKey {
        case types, pokemon, moves, items
        case typeChart = "type_chart"
        case itemIdMap = "item_id_map"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        types = try container.decode([String].self, forKey: .types)
        typeChart = try container.decode([String: PokemonXTypeRelations].self, forKey: .typeChart)
        pokemon = try container.decode([PokemonXStaticPokemon].self, forKey: .pokemon)
        moves = try container.decode([PokemonXStaticMove].self, forKey: .moves)
        items = try container.decodeIfPresent([PokemonXStaticItem].self, forKey: .items) ?? []
        itemIdMap = try container.decodeIfPresent([String: Int].self, forKey: .itemIdMap) ?? [:]
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
    // G9b–G9g — UNMAPPED battle-struct fields. All stay nil: the IV/EV,
    // status, held-item, ability, nature and current-EXP fields have no
    // verified offsets, and the lab has no known-IV/nature ground truth to
    // hunt them against (COMPANION-AUDIT-2026-11-19.md G9b–G9g). Do not
    // wire +0x08 as EXP — it is the level EXP threshold, not current EXP.
    var ivs: [Int]? = nil
    var evs: [Int]? = nil
    var heldItemName: String? = nil
    var abilityName: String? = nil
    var natureName: String? = nil
    var currentExp: Int? = nil

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
/// species learns next. The G9b–G9g fields are nil by design (see
/// PokemonXPartySlot) — the detail view shows them as unknown, not zero.
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
    /// The active opponent (enemy party slot 0) during a battle, from the
    /// enemy array read. Nil when no battle is running or the enemy read
    /// fails validation — the Battle tab hides the opponent card then.
    @Published var enemyActive: PokemonXPartySlot?
    /// G16 foe team: all 6 enemy slots. A nil slot is UNKNOWN — the audit
    /// says it is unverified whether slots 1-5 populate before send-out,
    /// so the View shows unknown for them until a multi-Pokemon battle is
    /// observed populating them. Never shown as empty.
    @Published var enemyTeam: [PokemonXPartySlot?] = [nil, nil, nil, nil, nil, nil]

    /// G10 active-battler index. The hunt for the index field is NOT done,
    /// so this stays 0 (the Shauna battle's active battler) with the
    /// assumption labelled in `activeBattlerNote`. After a switch the moves
    /// shown may be wrong — the View must say so, not hide it.
    @Published var activeBattlerIndex = 0
    var activeBattlerNote: String {
        "Active battler assumed to be slot 1 — switch tracking needs the G10 hunt, so after a switch the moves shown may be the wrong Pokemon's."
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
            nextMovesToLearn: speciesId.map { PokemonXCompanionData.nextMovesToLearn(speciesId: $0, level: level) } ?? [])
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
        guard let liveSlots = PokemonXLivePartyReader.readPlayerParty() else {
            // No battle running, or the heap base moved: never show stale data.
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
            bridgeStatus = "No live battle right now — open a battle to see your party."
            return
        }
        isLiveDataAvailable = true
        bridgeStatus = "Live — reading your party from the battle."
        // Enemy first: the foe's types drive every matchup (G15/G17).
        // Independent read — if it fails validation, hide the opponent
        // card but keep the player party (the arrays are separate reads).
        let enemySlots: [PokemonXLiveSlot?] = PokemonXLivePartyReader.readEnemyParty()
            ?? [nil, nil, nil, nil, nil, nil]
        let foeTypes: [String] = enemySlots[0]?.types ?? []
        enemyTeam = enemySlots.enumerated().map { index, live in
            guard let live else { return nil }
            var slot = PokemonXPartySlot.empty(id: index)
            slot.speciesName = PokemonXCompanionData.pokemon.first(where: { $0.id == live.species })?.name.capitalized ?? "#\(live.species)"
            slot.level = live.level
            slot.currentHP = live.currentHP
            slot.maxHP = live.maxHP
            slot.stats = live.stats
            slot.types = live.types
            return slot
        }
        if let foe = enemySlots[0] {
            var slot = PokemonXPartySlot.empty(id: 0)
            slot.speciesName = PokemonXCompanionData.pokemon.first(where: { $0.id == foe.species })?.name.capitalized ?? "#\(foe.species)"
            slot.level = foe.level
            slot.currentHP = foe.currentHP
            slot.maxHP = foe.maxHP
            slot.stats = foe.stats
            slot.types = foe.types
            enemyActive = slot
        } else {
            enemyActive = nil
        }
        partySlots = liveSlots.enumerated().map { index, live in
            guard let live else {
                var slot = PokemonXPartySlot.empty(id: index)
                slot.isKnownEmpty = true
                return slot
            }
            var slot = PokemonXPartySlot.empty(id: index)
            slot.speciesName = PokemonXCompanionData.pokemon.first(where: { $0.id == live.species })?.name.capitalized ?? "#\(live.species)"
            slot.level = live.level
            slot.currentHP = live.currentHP
            slot.maxHP = live.maxHP
            slot.stats = live.stats
            slot.types = live.types
            slot.moves = live.moves.enumerated().map { moveIndex, move in
                var moveSlot = PokemonXBattleMoveSlot.empty(id: moveIndex)
                if move.id != 0 {
                    let known = PokemonXCompanionData.moves.first(where: { $0.id == move.id })
                    moveSlot.name = known?.name.capitalized ?? "Move #\(move.id)"
                    moveSlot.type = known?.type
                    moveSlot.power = known?.power
                    moveSlot.currentPP = move.pp
                    moveSlot.maxPP = move.maxPP
                    // G15 matchup: effectiveness vs the foe's types, from
                    // the full G4 move table + the verified type chart.
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
            return slot
        }
        // G27 death detection: a party member's HP hitting 0 in battle is
        // a faint. (Out-of-battle faint state needs the field party, G1 —
        // not detectable from the battle read.)
        for (index, slot) in partySlots.enumerated() {
            if let previous = previousBattleHP[index], previous > 0,
               let current = slot.currentHP, current == 0 {
                recordFaint(slot: slot)
            }
            previousBattleHP[index] = slot.currentHP
        }
        // Battle tab: the active battler is slot 0 in the Shauna battle (the
        // first Pokemon sent out). G10 is NOT done — if the player switches
        // mid-battle, slot 0 is no longer the active battler; the View must
        // show `activeBattlerNote` so the moves are not presented as fact.
        if activeBattlerIndex < partySlots.count {
            battleMoves = partySlots[activeBattlerIndex].moves
        } else {
            battleMoves = (0..<4).map { PokemonXBattleMoveSlot.empty(id: $0) }
        }
        updateBestPick(foeTypes: foeTypes)
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

/// Guarded-fallback live read for Pokemon X battles.
///
/// The DllBattle battle-Pokemon structs live in the 3DS heap. They are
/// reached through the party-pointer arrays at VA 0x081FD3CC (player) /
/// 0x081FEB14 (enemy), each holding 6 consecutive u32 pointers to the
/// battle structs (slot 0 = Chespin 0x081FD418 / Froakie 0x081FEB60 in the
/// Shauna battle of the ORIGINAL session). SESSION-UNSTABLE
/// (HUNTS-REPORT-2026-11-19.md §0a): after a VM restart + state reload
/// those VAs hold pointer-structs, not battle structs — the "stable across
/// three dumps" claim held within one session only. So this read is a
/// GUARDED FALLBACK: EVERY poll validates slot 0's species (1...721) and
/// level (1...100) before trusting anything, and any failure shows the
/// placeholder, never stale data. A dynamic-discovery spec (signature scan
/// / pointer chain from a stable global) is pending from a follow-up hunt;
/// swap this implementation when it lands. No complete stable-global
/// pointer chain to the arrays exists via stored pointers (the two
/// referrer objects that hold the array pointers are themselves referenced
/// by nothing).
///
/// BATTLE struct offsets (NOT PK6), verified in three Azahar dumps with HP
/// liveness proven by the post-damage test (see PAGE-TABLE-MAPPING-2026-11-18.md):
/// species u16 +0x0C, HP max u16 +0x0E, HP current u16 +0x10 (LIVE — +0x0E is
/// max, not current; reading +0x0E as "HP" would show a permanently-full bar),
/// level u8 +0x18 (PROVEN — LEVEL-HUNT-2026-11-19.md: Slot 8 fanfare dump,
/// Chespin 6 vs Froakie 5 in the same dump; valid range 1–100), moves 4 x 0xE
/// at +0x116 (move ID u16 +0, PP cur u8 +2, PP max u8 +3; the second live PP
/// copy is at slot+8 and its max at slot+9 per LEVEL-HUNT §6c — the wiring
/// reads slot+2/+3 only). Stats 5 x u16 at +0xF6..+0xFE (ATK/DEF/SPA/SPD/
/// SPE — LEVEL-HUNT §2a/§6a: Lv6 Chespin 13/14/12/10/10). Types are two u8
/// game type ids at +0x100 (audit G15: Froakie 10/10 = Water/Water — the
/// battle-data hunt report does not document +0x100 itself, so both bytes
/// are validated 0...17 and yield nil types on failure). The 7-byte field
/// +0x104 (06x7 consume marker) is unchanged and unread. +0x08 is the
/// current-level EXP threshold (179 at Lv6), NOT current EXP, and is never read.
private enum PokemonXBattleRead {
    /// Player party array: 6 consecutive u32 pointers to battle structs.
    static let playerPartyArrayVA: UInt32 = 0x081FD3CC
    /// Enemy party array: same layout. Read by readEnemyParty(); the Battle
    /// tab shows the active opponent (slot 0) from it.
    static let enemyPartyArrayVA: UInt32 = 0x081FEB14
    static let partySlotCount = 6
    static let structLength: UInt32 = 0x1E4

    static let speciesOffset = 0x0C
    static let hpMaxOffset = 0x0E
    static let hpCurrentOffset = 0x10
    static let levelOffset = 0x18
    static let movesOffset = 0x116
    static let moveStride = 0xE
    static let statsOffset = 0xF6
    static let typesOffset = 0x100

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
    /// is 11). Water = 10 here, per the audit's Froakie 10/10 reading.
    /// Nil for any id outside 0...17 — never a guessed type.
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

/// One live party slot parsed from a battle struct.
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

private enum PokemonXLivePartyReader {
    /// Reads the six player battle structs through the pinned party-pointer
    /// array at 0x081FD3CC.
    static func readPlayerParty() -> [PokemonXLiveSlot?]? {
        readParty(at: PokemonXBattleRead.playerPartyArrayVA)
    }

    /// Reads the six enemy battle structs through the pinned enemy-pointer
    /// array at 0x081FEB14. Same path and same validation as the player
    /// read (BATTLE-SEND-HUNT-2026-11-19.md: Froakie HP 20→14 live,
    /// Bubble PP 30→29 live, byte-matched across Slots 2/3/4).
    static func readEnemyParty() -> [PokemonXLiveSlot?]? {
        readParty(at: PokemonXBattleRead.enemyPartyArrayVA)
    }

    /// Shared array read: read the 6 slot pointers at the given array VA,
    /// then each slot's struct at the pointer it holds. Returns nil when the
    /// read is untrusted as a whole (array unreadable, slot 0 pointer null,
    /// slot 0 struct unreadable, or slot 0's species/level not plausible —
    /// the heap moved or no battle is running). Slots 1-5 that fail to read
    /// or hold no plausible species/level come back as nil (empty slot),
    /// not as a failure of the whole party.
    private static func readParty(at arrayVA: UInt32) -> [PokemonXLiveSlot?]? {
        let bridge = HUDMemoryBridge.shared()
        guard bridge.hasLiveDataSource else { return nil }
        // The array itself: 6 little-endian u32 pointers (24 bytes).
        guard let arrayData = bridge.readBytes(atAddress: arrayVA,
                                               length: UInt32(PokemonXBattleRead.partySlotCount * 4)),
              arrayData.count == PokemonXBattleRead.partySlotCount * 4 else {
            return nil
        }
        var slots: [PokemonXLiveSlot?] = []
        for index in 0..<PokemonXBattleRead.partySlotCount {
            let structVA = PokemonXGuestMemory.u32LE(arrayData, index * 4)
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
            let species = Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.speciesOffset))
            guard PokemonXBattleRead.isPlausibleSpecies(species) else {
                if index == 0 { return nil }
                slots.append(nil)
                continue
            }
            let level = Int(data[PokemonXBattleRead.levelOffset])
            guard PokemonXBattleRead.isPlausibleLevel(level) else {
                if index == 0 { return nil }
                slots.append(nil)
                continue
            }
            let hpMax = Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.hpMaxOffset))
            let hpCur = Int(PokemonXGuestMemory.u16LE(data, PokemonXBattleRead.hpCurrentOffset))
            var moves: [(id: Int, pp: Int, maxPP: Int)] = []
            for moveIndex in 0..<4 {
                let base = PokemonXBattleRead.movesOffset + moveIndex * PokemonXBattleRead.moveStride
                let moveID = Int(PokemonXGuestMemory.u16LE(data, base))
                let pp = Int(data[base + 2])
                let maxPP = Int(data[base + 3])
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
            slots.append(PokemonXLiveSlot(species: species, level: level, currentHP: hpCur, maxHP: hpMax, moves: moves, stats: stats, types: types))
        }
        return slots
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
