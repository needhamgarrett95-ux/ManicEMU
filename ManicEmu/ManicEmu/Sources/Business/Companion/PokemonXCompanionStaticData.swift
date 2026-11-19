//
//  PokemonXCompanionStaticData.swift
//  ManicEmu
//
//  GENERATED 2026-11-19 from PokemonXFullDex-2026-11-19.json (see
//  PokemonXCompanionData.json in the same folder). Static reference data
//  only — no live game data. The companion loads the JSON at runtime when it
//  is bundled; these literals are the fallback so the Dex / type chart work
//  even if the JSON resource is missing. Pokemon list is a small early-game
//  Gen 6 sample (26), NOT the full Pokedex — the full 721 lives in the JSON.
//
//  SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum PokemonXCompanionStaticData {

    // type -> (double damage to, half damage to, no damage to)
    static let typeChartOffense: [String: (double: [String], half: [String], none: [String])] = [
        "bug": (double: ["dark", "grass", "psychic"], half: ["fairy", "fighting", "fire", "flying", "ghost", "poison", "steel"], none: []),
        "dark": (double: ["ghost", "psychic"], half: ["dark", "fairy", "fighting"], none: []),
        "dragon": (double: ["dragon"], half: ["steel"], none: ["fairy"]),
        "electric": (double: ["flying", "water"], half: ["dragon", "electric", "grass"], none: ["ground"]),
        "fairy": (double: ["dark", "dragon", "fighting"], half: ["fire", "poison", "steel"], none: []),
        "fighting": (double: ["dark", "ice", "normal", "rock", "steel"], half: ["bug", "fairy", "flying", "poison", "psychic"], none: ["ghost"]),
        "fire": (double: ["bug", "grass", "ice", "steel"], half: ["dragon", "fire", "rock", "water"], none: []),
        "flying": (double: ["bug", "fighting", "grass"], half: ["electric", "rock", "steel"], none: []),
        "ghost": (double: ["ghost", "psychic"], half: ["dark"], none: ["normal"]),
        "grass": (double: ["ground", "rock", "water"], half: ["bug", "dragon", "fire", "flying", "grass", "poison", "steel"], none: []),
        "ground": (double: ["electric", "fire", "poison", "rock", "steel"], half: ["bug", "grass"], none: ["flying"]),
        "ice": (double: ["dragon", "flying", "grass", "ground"], half: ["fire", "ice", "steel", "water"], none: []),
        "normal": (double: [], half: ["rock", "steel"], none: ["ghost"]),
        "poison": (double: ["fairy", "grass"], half: ["ghost", "ground", "poison", "rock"], none: ["steel"]),
        "psychic": (double: ["fighting", "poison"], half: ["psychic", "steel"], none: ["dark"]),
        "rock": (double: ["bug", "fire", "flying", "ice"], half: ["fighting", "ground", "steel"], none: []),
        "steel": (double: ["fairy", "ice", "rock"], half: ["electric", "fire", "steel", "water"], none: []),
        "water": (double: ["fire", "ground", "rock"], half: ["dragon", "grass", "water"], none: []),
    ]

    // type -> (double damage from, half damage from, no damage from)
    static let typeChartDefense: [String: (double: [String], half: [String], none: [String])] = [
        "bug": (double: ["fire", "flying", "rock"], half: ["fighting", "grass", "ground"], none: []),
        "dark": (double: ["bug", "fairy", "fighting"], half: ["dark", "ghost"], none: ["psychic"]),
        "dragon": (double: ["dragon", "fairy", "ice"], half: ["electric", "fire", "grass", "water"], none: []),
        "electric": (double: ["ground"], half: ["electric", "flying", "steel"], none: []),
        "fairy": (double: ["poison", "steel"], half: ["bug", "dark", "fighting"], none: ["dragon"]),
        "fighting": (double: ["fairy", "flying", "psychic"], half: ["bug", "dark", "rock"], none: []),
        "fire": (double: ["ground", "rock", "water"], half: ["bug", "fairy", "fire", "grass", "ice", "steel"], none: []),
        "flying": (double: ["electric", "ice", "rock"], half: ["bug", "fighting", "grass"], none: ["ground"]),
        "ghost": (double: ["dark", "ghost"], half: ["bug", "poison"], none: ["fighting", "normal"]),
        "grass": (double: ["bug", "fire", "flying", "ice", "poison"], half: ["electric", "grass", "ground", "water"], none: []),
        "ground": (double: ["grass", "ice", "water"], half: ["poison", "rock"], none: ["electric"]),
        "ice": (double: ["fighting", "fire", "rock", "steel"], half: ["ice"], none: []),
        "normal": (double: ["fighting"], half: [], none: ["ghost"]),
        "poison": (double: ["ground", "psychic"], half: ["bug", "fairy", "fighting", "grass", "poison"], none: []),
        "psychic": (double: ["bug", "dark", "ghost"], half: ["fighting", "psychic"], none: []),
        "rock": (double: ["fighting", "grass", "ground", "steel", "water"], half: ["fire", "flying", "normal", "poison"], none: []),
        "steel": (double: ["fighting", "fire", "ground"], half: ["bug", "dragon", "fairy", "flying", "grass", "ice", "normal", "psychic", "rock", "steel"], none: ["poison"]),
        "water": (double: ["electric", "grass"], half: ["fire", "ice", "steel", "water"], none: []),
    ]

    static let pokemon: [PokemonXStaticPokemon] = [
        PokemonXStaticPokemon(id: 650, name: "chespin", types: ["grass"]),
        PokemonXStaticPokemon(id: 651, name: "quilladin", types: ["grass"]),
        PokemonXStaticPokemon(id: 652, name: "chesnaught", types: ["grass", "fighting"]),
        PokemonXStaticPokemon(id: 653, name: "fennekin", types: ["fire"]),
        PokemonXStaticPokemon(id: 654, name: "braixen", types: ["fire"]),
        PokemonXStaticPokemon(id: 655, name: "delphox", types: ["fire", "psychic"]),
        PokemonXStaticPokemon(id: 656, name: "froakie", types: ["water"]),
        PokemonXStaticPokemon(id: 657, name: "frogadier", types: ["water"]),
        PokemonXStaticPokemon(id: 658, name: "greninja", types: ["water", "dark"]),
        PokemonXStaticPokemon(id: 659, name: "bunnelby", types: ["normal"]),
        PokemonXStaticPokemon(id: 660, name: "diggersby", types: ["normal", "ground"]),
        PokemonXStaticPokemon(id: 661, name: "fletchling", types: ["normal", "flying"]),
        PokemonXStaticPokemon(id: 662, name: "fletchinder", types: ["fire", "flying"]),
        PokemonXStaticPokemon(id: 663, name: "talonflame", types: ["fire", "flying"]),
        PokemonXStaticPokemon(id: 664, name: "scatterbug", types: ["bug"]),
        PokemonXStaticPokemon(id: 665, name: "spewpa", types: ["bug"]),
        PokemonXStaticPokemon(id: 666, name: "vivillon", types: ["bug", "flying"]),
        PokemonXStaticPokemon(id: 667, name: "litleo", types: ["fire", "normal"]),
        PokemonXStaticPokemon(id: 668, name: "pyroar-male", types: ["fire", "normal"]),
        PokemonXStaticPokemon(id: 25, name: "pikachu", types: ["electric"]),
        PokemonXStaticPokemon(id: 16, name: "pidgey", types: ["normal", "flying"]),
        PokemonXStaticPokemon(id: 669, name: "flabebe", types: ["fairy"]),
        PokemonXStaticPokemon(id: 670, name: "floette", types: ["fairy"]),
        PokemonXStaticPokemon(id: 671, name: "florges", types: ["fairy"]),
        PokemonXStaticPokemon(id: 672, name: "skiddo", types: ["grass"]),
        PokemonXStaticPokemon(id: 674, name: "pancham", types: ["fighting"]),
    ]

    static let moves: [PokemonXStaticMove] = [
        PokemonXStaticMove(id: 33, name: "tackle", type: "normal", power: 40, accuracy: 100, pp: 35, damageClass: "physical"),
        PokemonXStaticMove(id: 45, name: "growl", type: "normal", power: nil, accuracy: 100, pp: 40, damageClass: "status"),
        PokemonXStaticMove(id: 52, name: "ember", type: "fire", power: 40, accuracy: 100, pp: 25, damageClass: "special"),
        PokemonXStaticMove(id: 55, name: "water-gun", type: "water", power: 40, accuracy: 100, pp: 25, damageClass: "special"),
        PokemonXStaticMove(id: 22, name: "vine-whip", type: "grass", power: 45, accuracy: 100, pp: 25, damageClass: "physical"),
        PokemonXStaticMove(id: 98, name: "quick-attack", type: "normal", power: 40, accuracy: 100, pp: 30, damageClass: "physical"),
        PokemonXStaticMove(id: 10, name: "scratch", type: "normal", power: 40, accuracy: 100, pp: 35, damageClass: "physical"),
        PokemonXStaticMove(id: 1, name: "pound", type: "normal", power: 40, accuracy: 100, pp: 35, damageClass: "physical"),
        PokemonXStaticMove(id: 43, name: "leer", type: "normal", power: nil, accuracy: 100, pp: 30, damageClass: "status"),
        PokemonXStaticMove(id: 145, name: "bubble", type: "water", power: 40, accuracy: 100, pp: 30, damageClass: "special"),
        PokemonXStaticMove(id: 75, name: "razor-leaf", type: "grass", power: 55, accuracy: 95, pp: 25, damageClass: "physical"),
        PokemonXStaticMove(id: 488, name: "flame-charge", type: "fire", power: 50, accuracy: 100, pp: 20, damageClass: "physical"),
        PokemonXStaticMove(id: 104, name: "double-team", type: "normal", power: nil, accuracy: nil, pp: 15, damageClass: "status"),
        PokemonXStaticMove(id: 39, name: "tail-whip", type: "normal", power: nil, accuracy: 100, pp: 30, damageClass: "status"),
        PokemonXStaticMove(id: 44, name: "bite", type: "dark", power: 60, accuracy: 100, pp: 25, damageClass: "physical"),
        PokemonXStaticMove(id: 17, name: "wing-attack", type: "flying", power: 60, accuracy: 100, pp: 35, damageClass: "physical"),
        PokemonXStaticMove(id: 64, name: "peck", type: "flying", power: 35, accuracy: 100, pp: 35, damageClass: "physical"),
        PokemonXStaticMove(id: 81, name: "string-shot", type: "bug", power: nil, accuracy: 95, pp: 40, damageClass: "status"),
        PokemonXStaticMove(id: 106, name: "harden", type: "normal", power: nil, accuracy: nil, pp: 30, damageClass: "status"),
        PokemonXStaticMove(id: 93, name: "confusion", type: "psychic", power: 50, accuracy: 100, pp: 25, damageClass: "special"),
    ]
}
