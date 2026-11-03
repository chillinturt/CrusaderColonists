class_name HeroWeapon
extends RefCounted
## One of a hero's three weapons, made from a WeaponData entry. The hero calls
## cool() on all of them every tick and tick() on the one in hand; subclasses
## fire in _fire_tick() when the hero's intent says so.
##
## Ammo is unlimited, but weapons with a magazine must reload: on the reload
## button, or by themselves when emptied. A reload carries on while the weapon
## is holstered, so swapping to your secondary while the primary reloads works.

var id := ""
var def: Dictionary = {}
var hero: Hero
var rounds := 0
var cooldown := 0.0
var reload_left := 0.0


static func create(weapon_id: String, owner: Hero) -> HeroWeapon:
	var weapon_def := WeaponData.get_def(weapon_id)
	var weapon: HeroWeapon
	match weapon_def.get("type", "hitscan"):
		"rocket", "grenade":
			weapon = LauncherWeapon.new()
		"melee":
			weapon = MeleeWeapon.new()
		_:
			weapon = HitscanWeapon.new()
	weapon.id = weapon_id
	weapon.def = weapon_def
	weapon.hero = owner
	weapon.rounds = weapon.capacity()
	return weapon


func display_name() -> String:
	return def.get("name", id)


func is_melee() -> bool:
	return def.get("type", "") == "melee"


func equip() -> void:
	cooldown = maxf(cooldown, def.get("deploy", 0.3))
	if magazine() > 0 and rounds <= 0:
		start_reload()


func unequip() -> void:
	pass


## Every tick, held or not.
func cool(delta: float) -> void:
	cooldown -= delta
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			rounds = capacity()


## Every tick while held.
func tick(delta: float) -> void:
	if reload_left <= 0.0 and magazine() > 0 and (rounds <= 0 or (rounds < capacity() and hero.intent.reload)):
		start_reload()
	_fire_tick(delta)


func _fire_tick(_delta: float) -> void:
	pass


func can_attack() -> bool:
	return cooldown <= 0.0 and reload_left <= 0.0


func is_reloading() -> bool:
	return reload_left > 0.0


func magazine() -> int:
	return int(def.get("magazine", 0))


## Magazine size including Extended Magazines upgrades.
func capacity() -> int:
	return ceili(magazine() * hero.upgrades.magazine_multiplier()) if magazine() > 0 else 0


func start_reload() -> void:
	if magazine() > 0 and reload_left <= 0.0 and rounds < capacity():
		reload_left = float(def.get("reload", 1.8)) / hero.upgrades.reload_speed_multiplier()


## Full magazine, nothing pending (on respawn).
func refill() -> void:
	rounds = capacity()
	reload_left = 0.0
	cooldown = 0.0


## Takes one round for a shot. Firing the last one starts the reload.
func _use_round() -> bool:
	if magazine() <= 0:
		return true
	if rounds <= 0:
		start_reload()
		return false
	rounds -= 1
	if rounds == 0:
		start_reload()
	return true


func ammo_text() -> String:
	if magazine() <= 0:
		return ""
	return "reloading..." if is_reloading() else "%d / %d" % [rounds, capacity()]


## Current inaccuracy cone (degrees), for the crosshair. 0 = none.
func spread_degrees() -> float:
	return 0.0


## How far a bot likes to stand from what it's shooting with this.
func prefer_range() -> float:
	return def.get("prefer_range", 1.5)


## Effects live in the world (not under the hero) and remove themselves.
func _spawn_effect(node: Node3D, lifetime: float) -> void:
	hero.get_parent().add_child(node)
	hero.get_tree().create_timer(lifetime, false).timeout.connect(node.queue_free)
