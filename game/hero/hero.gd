class_name Hero
extends CharacterBody3D
## A crusader on the battlefield, played by you (HeroInput) or a bot (HeroBot).
## Both just fill in `intent` each tick; everything else here is the same for
## everyone:
##   movement   the action game's Source/Quake-style movement: ground friction
##              and acceleration, air strafing, bunny hopping (hold jump), a gas
##              pack (Shift: thrust along your aim, or toward the hook), and the
##              grappling hook. Jumping costs stamina; empty it and you're
##              exhausted (no jumping, slower) until it recovers.
##   weapons    primary, secondary and melee (WeaponData), switched with 1-3.
##   health     regenerates after a while out of combat; the fountain heals fast.
##   progress   gold (kills, last hits, assists, towers, and a trickle) buys
##              upgrades at your fountain; experience from fights nearby raises
##              your level (more health and damage).
##   death      you respawn at your fountain after a delay that grows with level.
## On the RTS side the hero is represented by a HeroAvatar child.

const EYE_HEIGHT := 1.75
## Hits this far above the feet are headshots.
const HEAD_HEIGHT := 1.6
const MAX_LEVEL := 15
const SHOP_ITEMS: Array[StringName] = [&"damage", &"max_health", &"damage_resist", &"fire_rate", &"move_speed",
		&"magazine", &"reload_speed", &"max_stamina", &"health_regen"]

# Movement: Source engine values converted from Hammer units (1 unit = 0.0254 m).
const MAX_SPEED := 8.0          ## sv_maxspeed 320
const GROUND_ACCEL := 10.0      ## sv_accelerate 10
const FRICTION := 4.0           ## sv_friction 4
const STOP_SPEED := 2.5         ## sv_stopspeed 100
const AIR_ACCEL := 10.0         ## sv_airaccelerate 10
## The "30 units" cap: air acceleration only adds speed up to this along your
## wish direction, so strafing perpendicular to your velocity keeps adding speed.
const AIR_SPEED_CAP := 0.76
const GRAVITY := 20.3           ## sv_gravity 800
const JUMP_VELOCITY := 7.3      ## 289 units/s
const GAS_THRUST := 14.0
const JUMP_STAMINA := 12.0
const EXHAUSTED_SPEED := 0.65

const BASE_HEALTH := 200.0
const HEALTH_PER_LEVEL := 14.0
const BASE_STAMINA := 100.0
const STAMINA_REGEN := 30.0
const STAMINA_REGEN_DELAY := 0.5
const EXHAUSTED_RECOVER := 0.3
const MAX_GAS := 100.0
const GAS_BURN := 20.0
const GAS_REGEN := 16.0
const GAS_REGEN_DELAY := 1.2
const HEALTH_REGEN := 6.0
const HEALTH_REGEN_DELAY := 6.0
## Recent damage from enemy heroes counts toward an assist this long.
const ASSIST_WINDOW := 10.0

var game: RTSGame
var team := 0
var index := 0
var hero_name := ""
var lane := 1
var is_local := false
var intent := HeroIntent.new()
## HeroInput or HeroBot.
var controller: Node
var avatar: HeroAvatar
var upgrades: Upgrades
var grapple: HeroGrapple
var weapons: Array[HeroWeapon] = []
var current := 0
var last_weapon := 0
var camera_rig: HeroCamera
var visual: Node3D

var health := BASE_HEALTH
var max_health := BASE_HEALTH
var stamina := BASE_STAMINA
var gas := MAX_GAS
var exhausted := false
var level := 1
var xp := 0.0
var gold := 0
var kills := 0
var deaths := 0
var assists := 0
var last_hits := 0
var dead := false
var respawn_left := 0.0
var in_fountain := false
## > 0 while this hero has lately been hurting enemy heroes: towers go for it.
var aggro_time := 0.0

var _damagers := {}  # Hero -> game time of their last hit on us
var _last_damager: Object
var _since_damage := 99.0
var _stamina_wait := 0.0
var _since_gas := 99.0
var _hook_was_down := false
var _shape: CollisionShape3D
# Animation
var _limbs: Array = []  # [node, rest rotation, phase offset, is_arm]
var _arm_r: Node3D
var _arm_l: Node3D
var _gun: Node3D
var _blade: MeshInstance3D
var _phase := 0.0
var _swing := 0.0
var _recoil := 0.0


func setup(p_game: RTSGame, p_team: int, p_index: int, p_name: String, human: bool, loadout: Array, p_lane: int) -> void:
	game = p_game
	team = p_team
	index = p_index
	hero_name = p_name
	is_local = human
	lane = p_lane
	collision_layer = Combat.HERO_LAYERS[team]
	collision_mask = Combat.WORLD | Combat.BOUNDARY
	floor_snap_length = 0.3
	add_to_group(&"heroes")

	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.9
	_shape.shape = capsule
	_shape.position.y = 0.95
	add_child(_shape)

	upgrades = Upgrades.new()
	upgrades.name = "Upgrades"
	add_child(upgrades)
	upgrades.changed.connect(func(_id: StringName) -> void: _refresh_max_health())

	visual = RTSModels.hero_visual(team)
	add_child(visual)
	_collect_parts()

	for id: String in loadout:
		weapons.append(HeroWeapon.create(id, self))
	weapons[0].equip()
	_update_held_visual()
	grapple = HeroGrapple.new(self)

	max_health = _max_health()
	health = max_health
	avatar = HeroAvatar.new()
	avatar.name = "Avatar"
	add_child(avatar)
	avatar.setup_avatar(game, self)

	if human:
		var input := HeroInput.new()
		input.hero = self
		controller = input
	else:
		var bot := HeroBot.new()
		bot.hero = self
		controller = bot
	controller.name = "Controller"
	add_child(controller)
	if human:
		attach_camera()


func attach_camera() -> void:
	if camera_rig:
		return
	camera_rig = HeroCamera.new()
	camera_rig.name = "Camera"
	camera_rig.hero = self
	add_child(camera_rig)


func current_weapon() -> HeroWeapon:
	return weapons[current]


# --- Tick -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not game.started or game.game_over:
		return
	if dead:
		respawn_left -= delta
		if respawn_left <= 0.0:
			respawn()
		return
	aggro_time -= delta
	_since_damage += delta
	controller.update_intent(delta)
	_switch_weapons()
	_move(delta)
	for weapon in weapons:
		weapon.cool(delta)
	weapons[current].tick(delta)
	_vitals(delta)
	avatar.sync()
	if global_position.y < -40.0:
		die(null)


func _process(delta: float) -> void:
	if visible:
		_animate(delta)


func _move(delta: float) -> void:
	rotation.y = intent.yaw
	var wish := _wish_dir()
	if is_on_floor():
		if intent.jump and _spend_stamina(JUMP_STAMINA):
			# Jumping skips this tick's friction, so landing and jumping on the same
			# tick keeps all your momentum. That's what makes bhopping work.
			velocity.y = JUMP_VELOCITY
			_air_accelerate(wish, delta)
		else:
			_apply_friction(delta)
			_accelerate(wish, run_speed() * (EXHAUSTED_SPEED if exhausted else 1.0), GROUND_ACCEL, delta)
	else:
		velocity.y -= GRAVITY * delta
		_air_accelerate(wish, delta)

	if intent.hook and not _hook_was_down and not grapple.hooked:
		grapple.fire()
	_hook_was_down = intent.hook
	var thrusting := intent.gas and _burn_gas(delta)
	if not grapple.apply(delta, thrusting) and thrusting:
		velocity += -aim_basis().z * GAS_THRUST * delta
	move_and_slide()


func _switch_weapons() -> void:
	if intent.weapon_slot >= 0:
		_equip(intent.weapon_slot)
		intent.weapon_slot = -1
	if intent.weapon_cycle != 0:
		_equip(wrapi(current + intent.weapon_cycle, 0, weapons.size()))
		intent.weapon_cycle = 0
	if intent.weapon_last:
		_equip(last_weapon)
		intent.weapon_last = false


func _equip(slot: int) -> void:
	if slot == current or slot < 0 or slot >= weapons.size():
		return
	weapons[current].unequip()
	last_weapon = current
	current = slot
	weapons[current].equip()
	_update_held_visual()


func _vitals(delta: float) -> void:
	_stamina_wait -= delta
	if _stamina_wait <= 0.0 and is_on_floor():
		stamina = minf(stamina + STAMINA_REGEN * delta, max_stamina())
		if exhausted and stamina >= max_stamina() * EXHAUSTED_RECOVER:
			exhausted = false
	_since_gas += delta
	if _since_gas >= GAS_REGEN_DELAY:
		gas = minf(gas + GAS_REGEN * delta, MAX_GAS)
	if is_healing():
		heal((HEALTH_REGEN + upgrades.bonus_health_regen()) * delta)


func is_healing() -> bool:
	return _since_damage >= HEALTH_REGEN_DELAY and health < max_health and not dead


func max_stamina() -> float:
	return BASE_STAMINA + upgrades.bonus_stamina()


## Spends stamina if you're not exhausted. The last bit can overdraw to 0 (you
## always get the jump you pressed), which then exhausts you.
func _spend_stamina(amount: float) -> bool:
	if exhausted or stamina <= 0.0:
		return false
	stamina = maxf(stamina - amount, 0.0)
	_stamina_wait = STAMINA_REGEN_DELAY
	if stamina <= 0.0:
		exhausted = true
	return true


func _burn_gas(delta: float) -> bool:
	if gas <= 0.0:
		return false
	gas = maxf(gas - GAS_BURN * delta, 0.0)
	_since_gas = 0.0
	return true


# --- Aim ------------------------------------------------------------------------

func aim_origin() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


func aim_direction() -> Vector3:
	if intent.aim_point != Vector3.INF:
		var to := intent.aim_point - aim_origin()
		if to.length_squared() > 1.0:
			return to.normalized()
	return Basis.from_euler(Vector3(intent.pitch, intent.yaw, 0.0)) * Vector3.FORWARD


## Basis whose -Z is where you're aiming.
func aim_basis() -> Basis:
	var dir := aim_direction()
	var up := Vector3.UP if absf(dir.y) < 0.98 else global_basis.z
	return Basis.looking_at(dir, up)


## Where shots appear to leave the gun (for tracers and rockets).
func muzzle_position() -> Vector3:
	if _gun:
		return _gun.global_position + _gun.global_basis.y * -0.55
	return aim_origin() + aim_basis() * Vector3(0.35, -0.3, -0.6)


# --- Health ---------------------------------------------------------------------

## Damage from anything: an enemy hero (Hero), an RTS unit or structure
## (RTSEntity, a HeroAvatar standing for a hero), or null (the map itself).
func receive_damage(amount: float, attacker: Object, from: Vector3) -> void:
	if dead:
		return
	var by_hero := RTSGame.hero_of(attacker)
	amount *= upgrades.damage_taken_multiplier()
	health -= amount
	_since_damage = 0.0
	if by_hero and by_hero != self:
		_damagers[by_hero] = game.time
		_last_damager = by_hero
		by_hero.aggro_time = 3.0
	elif attacker != null and by_hero == null:
		_last_damager = attacker
	# A small shove away from the hit, a little up so ground friction doesn't eat it.
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() > 0.01 and by_hero != self:
		velocity += away.normalized() * minf(amount / 40.0, 1.0) * 3.0
	if is_local:
		game.hero_hud.damage_flash(amount)
	if health <= 0.0:
		die(attacker)


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)


## Instant velocity change from blasts and heavy hits.
func push(impulse: Vector3) -> void:
	velocity += impulse


## `cause` is whatever landed the last hit (untyped: it may be freed by now).
func die(cause: Variant) -> void:
	if dead:
		return
	dead = true
	deaths += 1
	health = 0.0
	grapple.detach()
	velocity = Vector3.ZERO
	intent.clear()
	# The kill goes to the last enemy hero who hurt us lately, even if a tower
	# finished the job; the others who hurt us lately get assists.
	var recent := game.time - ASSIST_WINDOW
	var killer: Hero = null
	var killer_time := -INF
	for damager: Hero in _damagers:
		if is_instance_valid(damager) and _damagers[damager] > recent and _damagers[damager] > killer_time:
			killer = damager
			killer_time = _damagers[damager]
	var helpers: Array[Hero] = []
	for damager: Hero in _damagers:
		if is_instance_valid(damager) and damager != killer and _damagers[damager] > recent:
			helpers.append(damager)
	_damagers.clear()
	respawn_left = respawn_time()
	visible = false
	_shape.set_deferred("disabled", true)
	avatar.sync()
	if not is_instance_valid(cause):
		cause = _last_damager if is_instance_valid(_last_damager) else null
	game.on_hero_died(self, killer, helpers, cause)
	controller.on_died()
	if is_local:
		game.hero_hud.on_local_death(killer.hero_name if killer else "")


func respawn() -> void:
	dead = false
	health = max_health
	stamina = max_stamina()
	gas = MAX_GAS
	exhausted = false
	_since_damage = HEALTH_REGEN_DELAY
	_last_damager = null
	global_position = game.spawn_spot(team, index)
	velocity = Vector3.ZERO
	intent.yaw = atan2(game.map.bases[team].x, game.map.bases[team].z)
	intent.pitch = 0.0
	rotation.y = intent.yaw
	reset_physics_interpolation()
	visible = true
	_shape.set_deferred("disabled", false)
	for weapon in weapons:
		weapon.refill()
	avatar.sync()
	game.on_hero_respawned(self)


func respawn_time() -> float:
	return 5.0 + 1.5 * level + minf(game.time / 90.0, 12.0)


# --- Progress -------------------------------------------------------------------

func add_gold(amount: int, reason := "") -> void:
	gold += amount
	if is_local and reason != "":
		game.hero_hud.notify("+%d gold (%s)" % [amount, reason], Color(1.0, 0.85, 0.3))


func add_xp(amount: float) -> void:
	if level >= MAX_LEVEL:
		return
	xp += amount
	while level < MAX_LEVEL and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		_refresh_max_health()
		if is_local:
			game.hero_hud.notify("Level %d! More health and damage." % level, Color(0.6, 1.0, 0.6))


func xp_to_next() -> float:
	return 80.0 + 40.0 * level


func damage_multiplier() -> float:
	return (1.0 + 0.05 * (level - 1)) * upgrades.damage_multiplier()


func run_speed() -> float:
	return MAX_SPEED * upgrades.move_speed_multiplier()


func _max_health() -> float:
	return BASE_HEALTH + HEALTH_PER_LEVEL * (level - 1) + upgrades.bonus_health()


## Any increase arrives filled.
func _refresh_max_health() -> void:
	var new_max := _max_health()
	if new_max > max_health and not dead:
		health += new_max - max_health
	max_health = new_max


func upgrade_cost(id: StringName) -> int:
	return roundi(250.0 * pow(1.3, upgrades.count(id)))


## Buys one stack of an upgrade at the fountain. "" on success, else why not.
func buy(id: StringName) -> String:
	if not in_fountain and not dead:
		return "Shop at your fountain."
	var cost := upgrade_cost(id)
	if gold < cost:
		return "Not enough gold."
	gold -= cost
	upgrades.add(id)
	return ""


## Whether towers should go for this hero (it's been attacking heroes).
func is_aggressive() -> bool:
	return aggro_time > 0.0


func on_hit_landed(headshot: bool) -> void:
	if is_local:
		game.hero_hud.hitmarker(headshot)


func on_fired(kick: float) -> void:
	_recoil = minf(_recoil + kick * 2.0, 0.6)


## One line for test logs.
func status_text() -> String:
	if dead:
		return "dead (%.0fs)" % respawn_left
	var state: String = controller.call("state_name") if controller.has_method("state_name") else "player"
	return "%s hp %d/%d %s" % [state, ceili(health), roundi(max_health), weapons[current].id]


# --- Movement helpers -------------------------------------------------------------

func _wish_dir() -> Vector3:
	var move := intent.move.limit_length(1.0)
	return (transform.basis * Vector3(move.x, 0.0, move.y)).normalized() if move.length_squared() > 0.0001 else Vector3.ZERO


## Quake/Source Accelerate(): only adds speed if your velocity projected onto
## wish_dir is below wish_speed. Doesn't cap total speed.
func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var add_speed := wish_speed - velocity.dot(wish_dir)
	if add_speed <= 0.0:
		return
	velocity += wish_dir * minf(accel * wish_speed * delta, add_speed)


## Source AirAccelerate(): as above, but the projected-speed target is capped at
## AIR_SPEED_CAP while the accel rate still uses the full running speed.
func _air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var add_speed := minf(MAX_SPEED, AIR_SPEED_CAP) - velocity.dot(wish_dir)
	if add_speed <= 0.0:
		return
	velocity += wish_dir * minf(AIR_ACCEL * run_speed() * delta, add_speed)


func _apply_friction(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	# Below STOP_SPEED, friction acts as if you were going that fast, for a crisp stop.
	var drop := maxf(speed, STOP_SPEED) * FRICTION * delta
	var factor := maxf(speed - drop, 0.0) / speed
	velocity.x *= factor
	velocity.z *= factor


# --- Looks ------------------------------------------------------------------------

func _collect_parts() -> void:
	for node: Node in visual.find_children("*", "Node3D", true, false):
		if node.get_class() != "Node3D":
			continue
		var part := node as Node3D
		var part_name := String(part.name)
		if part_name == "ArmR":
			_arm_r = part
		elif part_name == "ArmL":
			_arm_l = part
		elif part_name == "Gun":
			_gun = part
		elif part_name.begins_with("Leg"):
			_limbs.append([part, part.rotation, PI if part_name.ends_with("R") else 0.0])
	if _arm_r:
		_blade = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.05, 0.9, 0.12)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.8, 0.82, 0.86)
		steel.metallic = 0.9
		steel.roughness = 0.2
		box.material = steel
		_blade.mesh = box
		_blade.position = Vector3(0, -1.1, 0)
		_arm_r.add_child(_blade)


## Gun in hand for guns, a blade for melee.
func _update_held_visual() -> void:
	var melee := weapons[current].is_melee()
	if _gun:
		_gun.visible = not melee
	if _blade:
		_blade.visible = melee


func _animate(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor()
	_swing = move_toward(_swing, clampf(hspeed / MAX_SPEED, 0.0, 1.0) if grounded else 0.0, delta * 5.0)
	_phase += delta * (4.0 + hspeed * 1.1)
	for limb: Array in _limbs:
		var node: Node3D = limb[0]
		var rest: Vector3 = limb[1]
		var r := rest
		r.x += sin(_phase + limb[2]) * 0.7 * _swing
		if not grounded:
			r.x = rest.x - 0.5 if limb[2] == 0.0 else rest.x + 0.3
		node.rotation = r
	_recoil = move_toward(_recoil, 0.0, delta * 3.0)
	var pitch := intent.pitch
	var weapon := weapons[current]
	if _arm_r:
		var aim_x := PI * 0.5 + pitch + _recoil
		if weapon is MeleeWeapon and (weapon as MeleeWeapon).swing_progress() >= 0.0:
			var t := (weapon as MeleeWeapon).swing_progress()
			var arc := (weapon as MeleeWeapon).current_arc()
			var along := clampf((t - 0.3) / 0.3, 0.0, 1.0)
			var swing_pitch := deg_to_rad(lerpf(arc.y, arc.w, along))
			var swing_yaw := deg_to_rad(lerpf(arc.x, arc.z, along))
			var raise := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
			_arm_r.rotation = Vector3(lerpf(aim_x, PI * 0.5 + swing_pitch + 0.4, raise), -swing_yaw * raise, 0.0)
		else:
			_arm_r.rotation = Vector3(aim_x, 0.0, 0.0)
	if _arm_l:
		_arm_l.rotation = Vector3(PI * 0.4 + pitch * 0.6, -0.5, 0.0) if not weapon.is_melee() else Vector3(0.6, 0.0, 0.0)
