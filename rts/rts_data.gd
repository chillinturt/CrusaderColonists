class_name RTSData
extends RefCounted
## Every unit and structure in the RTS: stats, costs, tech requirements, hotkeys,
## and which model / projectile from the action game it reuses.
##
## Distances are meters, times are seconds. "range" is measured edge to edge
## (between the two units' radii), so 0 is melee. "air" / "ground" say what a
## unit's attack can hit. Costs are crystal + aether; supply is what it takes up.

const TEAM_HUES: Array[float] = [0.6, 0.0]
const TEAM_COLORS: Array[Color] = [Color(0.25, 0.55, 1.0), Color(1.0, 0.25, 0.2)]
const TEAM_NAMES: Array[String] = ["Azure Order", "Crimson Host"]

const MAX_SUPPLY := 200
const MAX_QUEUE := 5
## Crystal / aether carried per trip, and how long each takes to gather.
const CRYSTAL_PER_TRIP := 5
const AETHER_PER_TRIP := 4
const MINE_TIME := 2.6
const EXTRACT_TIME := 1.6

const UNITS := {
	"peasant": {
		"name": "Peasant", "desc": "Gathers crystal and aether, and raises structures.",
		"model": "res://enemy/enemy.tscn", "scale": 0.72,
		"hide": ["Blade", "Guard", "Shield", "ShieldRim", "ShieldBoss", "Crest", "Tabard", "TabardBack"],
		"hp": 45.0, "armor": 0.0, "speed": 5.2, "sight": 16.0, "radius": 0.45, "height": 1.7,
		"range": 0.0, "damage": 5.0, "cooldown": 1.3, "air": false, "ground": true,
		"crystal": 50, "aether": 0, "supply": 1, "time": 12.0, "hotkey": "P", "worker": true,
	},
	"knight": {
		"name": "Knight", "desc": "Armored swordsman. Sturdy front line.",
		"model": "res://enemy/enemy.tscn", "scale": 1.0,
		"hp": 150.0, "armor": 1.0, "speed": 4.6, "sight": 18.0, "radius": 0.6, "height": 2.3,
		"range": 0.0, "damage": 14.0, "cooldown": 1.1, "air": false, "ground": true,
		"crystal": 75, "aether": 0, "supply": 2, "time": 20.0, "hotkey": "K",
	},
	"leaper": {
		"name": "Leaper", "desc": "Fast, cheap beast that swarms its prey.",
		"model": "res://enemy/leaper.tscn", "scale": 0.85,
		"hp": 60.0, "armor": 0.0, "speed": 7.6, "sight": 16.0, "radius": 0.5, "height": 1.4,
		"range": 0.0, "damage": 6.0, "cooldown": 0.55, "air": false, "ground": true,
		"crystal": 40, "aether": 0, "supply": 1, "time": 14.0, "hotkey": "L",
	},
	"dragoon": {
		"name": "Dragoon", "desc": "Four-legged walker that spits acid at ground and air.",
		"model": "res://enemy/ranged_enemy.tscn", "scale": 0.85,
		"hp": 150.0, "armor": 1.0, "speed": 4.4, "sight": 20.0, "radius": 0.85, "height": 2.2,
		"range": 9.0, "damage": 16.0, "cooldown": 1.5, "air": true, "ground": true,
		"projectile": "spit",
		"crystal": 100, "aether": 50, "supply": 2, "time": 26.0, "hotkey": "D",
	},
	"golem": {
		"name": "Siege Golem", "desc": "Slow artillery. Long-range shells splash ground targets.",
		"model": "res://enemy/mortar_enemy.tscn", "scale": 1.15,
		"hp": 170.0, "armor": 1.0, "speed": 3.4, "sight": 20.0, "radius": 0.85, "height": 2.4,
		"range": 13.0, "min_range": 2.5, "damage": 32.0, "splash": 2.8, "cooldown": 2.8, "air": false, "ground": true,
		"projectile": "shell",
		"crystal": 150, "aether": 125, "supply": 3, "time": 34.0, "hotkey": "G", "requires": "forge",
	},
	"titan": {
		"name": "Titan", "desc": "Colossal giant. Every blow shakes the earth around it.",
		"model": "res://enemy/titan.tscn", "scale": 0.5,
		"hp": 1100.0, "armor": 3.0, "speed": 4.0, "sight": 20.0, "radius": 1.8, "height": 6.0,
		"range": 0.6, "damage": 55.0, "splash": 3.0, "cooldown": 2.0, "air": false, "ground": true,
		"crystal": 300, "aether": 300, "supply": 6, "time": 55.0, "hotkey": "T", "requires": "sanctum",
	},
	"wasp": {
		"name": "Wasp", "desc": "Gyrocopter gunship. Fires rockets at ground and air.",
		"model": "res://enemy/wasp.tscn", "scale": 1.0, "flying": true, "altitude": 5.5,
		"hp": 120.0, "armor": 0.0, "speed": 6.6, "sight": 20.0, "radius": 0.8, "height": 1.4,
		"range": 7.0, "damage": 10.0, "cooldown": 1.0, "air": true, "ground": true,
		"projectile": "rocket",
		"crystal": 100, "aether": 75, "supply": 2, "time": 28.0, "hotkey": "W",
	},
	"harpy": {
		"name": "Harpy", "desc": "Swift winged hunter. Strikes ground and air up close.",
		"model": "res://enemy/gargoyle.tscn", "scale": 1.0, "flying": true, "altitude": 4.5,
		"hp": 110.0, "armor": 0.0, "speed": 8.6, "sight": 18.0, "radius": 0.7, "height": 1.6,
		"range": 1.0, "damage": 12.0, "cooldown": 0.9, "air": true, "ground": true,
		"crystal": 75, "aether": 75, "supply": 2, "time": 24.0, "hotkey": "H",
	},
	"dragon": {
		"name": "Dragon", "desc": "Ancient terror. Its fire engulfs everything near the target.",
		"model": "res://enemy/dragon.tscn", "scale": 0.45, "flying": true, "altitude": 8.0,
		"hp": 950.0, "armor": 2.0, "speed": 4.6, "sight": 22.0, "radius": 2.2, "height": 3.0,
		"range": 8.0, "damage": 40.0, "splash": 3.0, "cooldown": 2.2, "air": true, "ground": true,
		"projectile": "fire",
		"crystal": 350, "aether": 350, "supply": 6, "time": 60.0, "hotkey": "D", "requires": "sanctum",
	},
}

## "size" is the footprint in nav cells (2 m each).
const STRUCTURES := {
	"keep": {
		"name": "Keep", "desc": "Trains peasants. Peasants bring resources here. +10 supply. Your first keep is your core: lose it and you lose the match.",
		"size": 4, "hp": 4500.0, "armor": 3.0, "sight": 24.0, "height": 9.0,
		"range": 14.0, "damage": 30.0, "cooldown": 1.0, "air": true, "ground": true, "projectile": "rocket",
		"crystal": 400, "aether": 0, "time": 70.0, "supply": 10, "hotkey": "K",
		"trains": ["peasant"], "dropoff": true,
	},
	## Lane towers: placed at the start, never built. Shielded until the tower
	## in front of them falls (see RTSGame._update_shields).
	"tower": {
		"name": "Lane Tower", "desc": "Guards a lane. Prefers minions, but turns on any hero who attacks a hero nearby.",
		"size": 2, "hp": 2000.0, "armor": 2.0, "sight": 24.0, "height": 9.0,
		"range": 16.0, "damage": 45.0, "cooldown": 1.2, "air": true, "ground": true, "projectile": "rocket",
		"crystal": 0, "aether": 0, "time": 1.0, "hotkey": "",
	},
	"farm": {
		"name": "Farmstead", "desc": "Feeds your army. +8 supply.",
		"size": 2, "hp": 400.0, "armor": 1.0, "sight": 10.0, "height": 4.0,
		"crystal": 100, "aether": 0, "time": 22.0, "supply": 8, "hotkey": "F",
	},
	"barracks": {
		"name": "Barracks", "desc": "Trains knights, leapers and dragoons.",
		"size": 3, "hp": 1000.0, "armor": 1.0, "sight": 12.0, "height": 5.0,
		"crystal": 150, "aether": 0, "time": 45.0, "hotkey": "B",
		"trains": ["knight", "leaper", "dragoon"],
	},
	"extractor": {
		"name": "Extractor", "desc": "Built on an aether vent so peasants can draw aether.",
		"size": 2, "hp": 450.0, "armor": 1.0, "sight": 10.0, "height": 3.5,
		"crystal": 75, "aether": 0, "time": 25.0, "hotkey": "E", "on_vent": true,
	},
	"watchtower": {
		"name": "Watchtower", "desc": "Defensive tower. Fires bolts at ground and air.",
		"size": 2, "hp": 450.0, "armor": 1.0, "sight": 18.0, "height": 8.0,
		"range": 9.0, "damage": 12.0, "cooldown": 1.0, "air": true, "ground": true, "projectile": "rocket",
		"crystal": 100, "aether": 0, "time": 25.0, "hotkey": "T", "requires": "barracks",
	},
	"forge": {
		"name": "Forge", "desc": "Builds siege golems, and titans once you have a sanctum.",
		"size": 3, "hp": 1000.0, "armor": 1.0, "sight": 12.0, "height": 5.5,
		"crystal": 150, "aether": 100, "time": 50.0, "hotkey": "G", "requires": "barracks",
		"trains": ["golem", "titan"],
	},
	"aerie": {
		"name": "Aerie", "desc": "Trains wasps and harpies, and dragons once you have a sanctum.",
		"size": 3, "hp": 1000.0, "armor": 1.0, "sight": 12.0, "height": 8.0,
		"crystal": 150, "aether": 100, "time": 50.0, "hotkey": "A", "requires": "forge",
		"trains": ["wasp", "harpy", "dragon"],
	},
	"sanctum": {
		"name": "Sanctum", "desc": "Ancient knowledge. Unlocks titans and dragons.",
		"size": 3, "hp": 700.0, "armor": 1.0, "sight": 12.0, "height": 7.0,
		"crystal": 150, "aether": 150, "time": 50.0, "hotkey": "S", "requires": "forge",
	},
}

## Order of the peasant's build menu.
const BUILD_MENU: Array[String] = ["keep", "farm", "barracks", "extractor", "watchtower", "forge", "aerie", "sanctum"]

## Projectile looks (scenes from the action game, with their scripts stripped).
## arc = peak height of a lobbed shot; tint recolors it.
const PROJECTILES := {
	"spit": {"scene": "res://combat/spit.tscn", "speed": 24.0, "arc": 0.0, "scale": 0.7},
	"rocket": {"scene": "res://combat/rocket.tscn", "speed": 30.0, "arc": 0.0, "scale": 1.0},
	"shell": {"scene": "res://combat/mortar_shell.tscn", "speed": 16.0, "arc": 6.0, "scale": 1.0},
	"fire": {"scene": "res://combat/mortar_shell.tscn", "speed": 22.0, "arc": 0.0, "scale": 1.8},
}


## Gold a hero gets for landing the killing blow on a unit (lane minions included).
static func bounty(kind: String) -> int:
	var def := unit(kind)
	return 12 + roundi((int(def.get("crystal", 0)) + int(def.get("aether", 0))) * 0.2)


static func unit(kind: String) -> Dictionary:
	return UNITS.get(kind, {})


static func structure(kind: String) -> Dictionary:
	return STRUCTURES.get(kind, {})


## Units or structures.
static func any(kind: String) -> Dictionary:
	if UNITS.has(kind):
		return UNITS[kind]
	return STRUCTURES.get(kind, {})


static func cost_text(def: Dictionary) -> String:
	var text := "%d crystal" % def.get("crystal", 0)
	if def.get("aether", 0) > 0:
		text += ", %d aether" % def.aether
	if def.get("supply", 0) > 0 and UNITS.values().has(def):
		text += ", %d supply" % def.supply
	return text
