class_name WeaponData
extends RefCounted
## Every hero weapon, as data: the action game's weapons with its numbers,
## so a hero's loadout is three ids (primary, secondary, melee). Every hero
## also has the grappling hook and gas pack, which don't take a slot.
##
## short       optional label for tight spots (the start menu's buttons)
## type        hitscan (rays from the eye), rocket, grenade or melee
## hitscan:    damage per pellet, fire_rate (shots/s), pellet_grid (fixed
##             pattern) or pellets (random), falloff from falloff_start to
##             falloff_end (down to falloff_min x), spread in degrees (base, per
##             shot up to max_bloom, recovering at bloom_recovery/s; extra while
##             airborne or moving), headshot multiplier against heroes
## rocket:     damage and radius of the blast, speed, fire_interval
## grenade:    damage and radius, fuse, throw_speed / throw_lift, throw_interval
## melee:      damage, windup / active / recovery times, reach, thickness of
##             the hit rays, arcs (start yaw, start pitch, end yaw, end pitch in
##             degrees; used in turn), and optionally a ground slam

const SLOT_TITLES: Array[String] = ["Primary", "Secondary", "Melee"]
const DEFAULT_LOADOUT: Array[String] = ["rifle", "revolver", "machete"]

const WEAPONS := {
	"rifle": {
		"name": "Automatic Rifle", "short": "Rifle", "slot": 0, "type": "hitscan",
		"desc": "Fully automatic: 15 damage, 6 shots a second, 25 rounds. Loses accuracy the longer you hold the trigger, and damage past 12 m.",
		"damage": 15.0, "fire_rate": 6.0, "magazine": 25, "reload": 1.8, "deploy": 0.3,
		"falloff_start": 12.0, "falloff_end": 45.0, "falloff_min": 0.4,
		"base_spread": 0.4, "spread_per_shot": 0.35, "max_bloom": 3.0, "bloom_recovery": 6.0, "airborne_spread": 1.5,
		"headshot": 1.4, "range": 250.0, "prefer_range": 16.0,
	},
	"shotgun": {
		"name": "Shotgun", "slot": 0, "type": "hitscan",
		"desc": "9 pellets of 12 in a tight 3x3 grid: 108 up close, weak past 20 m. 6 shells.",
		"damage": 12.0, "pellet_grid": Vector2i(3, 3), "fire_rate": 1.2, "magazine": 6, "reload": 2.2, "deploy": 0.3,
		"falloff_start": 6.0, "falloff_end": 22.0, "falloff_min": 0.25,
		"base_spread": 2.5, "spread_per_shot": 0.0, "max_bloom": 0.0, "airborne_spread": 0.0,
		"headshot": 1.25, "range": 120.0, "prefer_range": 6.0,
	},
	"sniper": {
		"name": "Sniper", "slot": 0, "type": "hitscan",
		"desc": "90 damage at any range, double on a headshot. Pinpoint while standing still, wild on the move or in the air. 5 rounds.",
		"damage": 90.0, "fire_rate": 0.9, "magazine": 5, "reload": 2.6, "deploy": 0.4,
		"falloff_start": 300.0, "falloff_end": 400.0, "falloff_min": 1.0,
		"base_spread": 0.05, "spread_per_shot": 0.0, "max_bloom": 0.0, "airborne_spread": 5.0, "moving_spread": 2.5,
		"headshot": 2.0, "range": 400.0, "prefer_range": 32.0,
	},
	"rocket": {
		"name": "Rocket Launcher", "short": "Rockets", "slot": 0, "type": "rocket",
		"desc": "Rockets: 85 damage in a 4 m blast that walls block. Hurts you a little too: aim at your feet and jump to rocket jump. 3 per reload.",
		"damage": 85.0, "radius": 4.0, "force": 13.0, "speed": 30.0, "fire_interval": 0.8, "self_damage": 0.4,
		"magazine": 3, "reload": 2.6, "deploy": 0.5, "prefer_range": 14.0,
	},
	"revolver": {
		"name": "Revolver", "slot": 1, "type": "hitscan",
		"desc": "45 damage per shot, accurate, quick to draw and reload. 6 rounds. Rapid fire throws your aim off.",
		"damage": 45.0, "fire_rate": 2.5, "magazine": 6, "reload": 1.6, "deploy": 0.2,
		"falloff_start": 18.0, "falloff_end": 55.0, "falloff_min": 0.5,
		"base_spread": 0.3, "spread_per_shot": 1.0, "max_bloom": 3.0, "bloom_recovery": 6.0, "airborne_spread": 1.0,
		"headshot": 1.5, "range": 250.0, "prefer_range": 14.0,
	},
	"grenades": {
		"name": "Grenades", "slot": 1, "type": "grenade",
		"desc": "Bouncing grenades that carry your momentum: 90 damage in a 6 m blast after 2.5 s. Throw 2, then re-arm. One at your feet is a grenade jump.",
		"damage": 90.0, "radius": 6.0, "force": 14.0, "fuse": 2.5, "throw_speed": 16.0, "throw_lift": 3.0,
		"throw_interval": 0.6, "self_damage": 0.35, "magazine": 2, "reload": 3.0, "deploy": 0.25, "prefer_range": 12.0,
	},
	"machete": {
		"name": "Machete", "slot": 2, "type": "melee",
		"desc": "Fast, wide slashes back and forth for 28 that hit everything in front of you. The biggest bonus for swinging at speed.",
		"damage": 28.0, "windup": 0.06, "active": 0.12, "recovery": 0.2, "reach": 2.6, "thickness": 0.8,
		"arcs": [Vector4(62, 8, -62, -22), Vector4(-62, 8, 62, -22)], "push": 2.0, "speed_bonus": 0.08, "deploy": 0.2,
	},
	"axe": {
		"name": "Battle Axe", "slot": 2, "type": "melee",
		"desc": "A long diagonal chop for 75, with the longest reach. Narrow: aim it.",
		"damage": 75.0, "windup": 0.2, "active": 0.14, "recovery": 0.42, "reach": 3.3, "thickness": 0.5,
		"arcs": [Vector4(14, 55, -10, -45)], "push": 6.0, "speed_bonus": 0.05, "deploy": 0.3,
	},
	"sledgehammer": {
		"name": "Sledgehammer", "slot": 2, "type": "melee",
		"desc": "A slow overhead smash for 110. Where it strikes the ground a shockwave hurts and launches enemies within 4 m and bounces you up (hammer jump).",
		"damage": 110.0, "windup": 0.4, "active": 0.16, "recovery": 0.6, "reach": 2.9, "thickness": 0.9,
		"arcs": [Vector4(0, 70, 0, -60)], "push": 10.0, "speed_bonus": 0.05, "deploy": 0.4,
		"slam_radius": 4.0, "slam_damage": 0.5, "slam_force": 12.0, "slam_hop": 7.0,
	},
}


static func get_def(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


static func ids_for_slot(slot: int) -> Array[String]:
	var ids: Array[String] = []
	for id: String in WEAPONS:
		if int(WEAPONS[id].slot) == slot:
			ids.append(id)
	return ids


## One random weapon per slot (for bots).
static func random_loadout() -> Array[String]:
	var loadout: Array[String] = []
	for slot in SLOT_TITLES.size():
		loadout.append(ids_for_slot(slot).pick_random())
	return loadout
