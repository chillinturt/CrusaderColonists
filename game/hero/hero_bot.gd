class_name HeroBot
extends Node
## A computer-controlled hero. Fills in the hero's HeroIntent each tick, the
## same way your keyboard and mouse do, so bots move, aim and shoot by the
## same rules as you. It:
##   LANE     walks its lane behind the front of its own minion wave (or waits
##            at its tower when there's no wave), bunny hopping on long walks
##   FIGHT    picks a target (enemy heroes first, then minions and units, then
##            towers and other structures once its own minions are there to
##            tank them), keeps its weapon's favorite distance, strafes, and
##            fires when its aim is on target. It won't chase a hero under an
##            enemy tower without minions to cover it.
##   RETREAT  low on health: runs to its fountain, heals, shops, and goes back.
## Skill (the match difficulty) sets how fast and how precisely it aims.

enum State { LANE, FIGHT, RETREAT }

const THINK_INTERVAL := 0.25
const HERO_SIGHT := 40.0
const UNIT_SIGHT := 26.0
const TOWER_DANGER := 19.0
## Per skill level (easy, normal, hard).
const TURN_RATE: Array[float] = [4.0, 7.0, 11.0]
const AIM_ERROR: Array[float] = [0.05, 0.028, 0.014]
const REACTION: Array[float] = [0.45, 0.28, 0.15]
const SHOP_PRIORITY: Array[StringName] = [&"damage", &"max_health", &"damage_resist", &"fire_rate", &"move_speed",
		&"damage", &"max_health", &"reload_speed", &"health_regen", &"magazine"]

var hero: Hero
var state := State.LANE
var target: Object
var skill := 1

var _think := 0.0
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath := 0.0
var _strafe := 1.0
var _strafe_time := 0.0
var _error := Vector2.ZERO
var _error_time := 0.0
var _reaction := 0.0
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var _jump_hold := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_think = _rng.randf() * THINK_INTERVAL
	skill = hero.game.difficulty


func state_name() -> String:
	return ["lane", "fight", "retreat"][state]


func on_died() -> void:
	state = State.LANE
	target = null
	_path = PackedVector3Array()
	_path_goal = Vector3.INF


func update_intent(delta: float) -> void:
	var intent := hero.intent
	intent.clear()
	skill = hero.game.difficulty
	_think -= delta
	if _think <= 0.0:
		_think = THINK_INTERVAL
		_decide()
	match state:
		State.RETREAT:
			_travel(hero.game.fountains[hero.team], delta, 1.5)
		State.FIGHT:
			_fight(delta)
		State.LANE:
			_travel(_lane_spot(), delta, 4.0)
	_unstick(delta)


# --- Decisions ----------------------------------------------------------------

func _decide() -> void:
	var game := hero.game
	if hero.in_fountain:
		_shop()
	var ratio := hero.health / hero.max_health
	if state == State.RETREAT:
		if ratio >= 0.95:
			state = State.LANE
		else:
			return
	if ratio < 0.3 and not hero.in_fountain:
		state = State.RETREAT
		target = null
		return
	var picked := _pick_target(game)
	if picked != target:
		_reaction = REACTION[skill]
	target = picked
	state = State.FIGHT if target != null else State.LANE


func _pick_target(game: RTSGame) -> Object:
	var eye := hero.aim_origin()
	var best: Object = null
	var best_score := INF
	var covered := _minions_near(hero.global_position, 15.0) > 0
	for enemy in game.heroes:
		if enemy.team == hero.team or enemy.dead:
			continue
		var d := enemy.global_position.distance_to(hero.global_position)
		if d > HERO_SIGHT or not _can_see(eye, enemy.global_position + Vector3.UP * 1.2, enemy):
			continue
		if _under_enemy_tower(enemy.global_position) and not covered and enemy.health > hero.health * 0.5:
			continue
		var score := d - (1.0 - enemy.health / enemy.max_health) * 15.0
		if score < best_score:
			best = enemy
			best_score = score
	if best:
		return best
	for entity in game.nearby(hero.global_position, UNIT_SIGHT):
		if entity.team == hero.team or entity.dead or entity is HeroAvatar or entity.tucked_away or entity.shielded:
			continue
		var d := RTSEntity.flat(entity.global_position - hero.global_position).length() - entity.radius
		var score := d
		if entity.is_structure:
			var fires := entity.can_attack()
			if fires and _minions_near(entity.global_position, entity.def.get("range", 14.0) + entity.radius) == 0:
				continue  # wait for minions to tank it
			score += 12.0
		elif _under_enemy_tower(entity.global_position) and not covered:
			continue
		if not _can_see(eye, _aim_point_of(entity), entity):
			continue
		if score < best_score:
			best = entity
			best_score = score
	return best


func _shop() -> void:
	for id in SHOP_PRIORITY:
		if hero.gold >= hero.upgrade_cost(id) + 50:
			hero.buy(id)
			return


# --- Fighting -------------------------------------------------------------------

func _fight(delta: float) -> void:
	if not _valid(target):
		target = null
		state = State.LANE
		return
	var intent := hero.intent
	var goal := _aim_point_of(target)
	var to := goal - hero.aim_origin()
	var dist := Vector2(to.x, to.z).length()

	# Weapon: melee up close, otherwise the primary (the secondary while it reloads).
	var want := 0
	if dist < 3.2:
		want = 2
	elif (hero.weapons[0].is_reloading() and hero.weapons[0].reload_left > 0.6 and not hero.weapons[1].is_reloading()) \
			or (dist < 12.0 and hero.weapons[0].id == "sniper"):
		want = 1
	if want != hero.current and hero.weapons[want].cooldown <= 0.0:
		intent.weapon_slot = want

	# Aim, with a little error that drifts.
	var weapon := hero.current_weapon()
	if weapon.def.get("type", "") == "rocket":
		var vel: Vector3 = target.velocity if target is Hero else Vector3.ZERO
		goal += vel * (to.length() / float(weapon.def.get("speed", 30.0)))
		goal.y -= 0.6  # splash at their feet
		to = goal - hero.aim_origin()
	_error_time -= delta
	if _error_time <= 0.0:
		_error_time = 0.4
		_error = Vector2(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0)) * AIM_ERROR[skill]
	var want_yaw := atan2(-to.x, -to.z) + _error.x
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length()) + _error.y
	intent.yaw = rotate_toward(intent.yaw, want_yaw, TURN_RATE[skill] * delta)
	intent.pitch = move_toward(intent.pitch, clampf(want_pitch, -1.3, 1.3), TURN_RATE[skill] * delta)
	var off := absf(angle_difference(intent.yaw, want_yaw)) + absf(intent.pitch - want_pitch)
	var tolerance := maxf(atan2(0.6, maxf(to.length(), 1.0)), 0.02) + AIM_ERROR[skill]
	_reaction -= delta
	intent.fire = _reaction <= 0.0 and off < tolerance and (weapon.is_melee() and dist < 3.4 or not weapon.is_melee())

	# Keep the weapon's favorite distance and strafe.
	var prefer := weapon.prefer_range() if not weapon.is_melee() else 1.0
	var flat_to := Vector3(to.x, 0.0, to.z).normalized()
	var move_dir := Vector3.ZERO
	if dist > prefer + 4.0:
		_travel(goal, delta, prefer, false)
		return
	elif dist < prefer - 4.0:
		move_dir -= flat_to
	_strafe_time -= delta
	if _strafe_time <= 0.0:
		_strafe_time = _rng.randf_range(0.5, 1.4)
		_strafe = -_strafe if _rng.randf() < 0.7 else _strafe
	move_dir += flat_to.cross(Vector3.UP) * _strafe * 0.8
	_set_move(move_dir)
	intent.jump = skill >= 1 and _rng.randf() < 0.02 * skill


# --- Moving -------------------------------------------------------------------

## Walks toward `goal` along a nav path. Faces where it walks when `face` (else
## aim stays where the fight put it).
func _travel(goal: Vector3, delta: float, arrive: float, face := true) -> void:
	var intent := hero.intent
	var flat := Vector3(goal.x - hero.global_position.x, 0.0, goal.z - hero.global_position.z)
	if flat.length() <= arrive:
		_path_goal = Vector3.INF
		if face and state == State.LANE:
			_look_toward(RTSEntity.flat(-hero.game.map.bases[hero.team]), delta)
		return
	_repath -= delta
	if _path_goal == Vector3.INF or _path_goal.distance_to(goal) > 4.0 or _repath <= 0.0:
		_path = hero.game.map.nav.find_path(hero.global_position, goal)
		_path_index = 0
		_path_goal = goal
		_repath = 1.5
	var next := goal
	while _path_index < _path.size() - 1 and RTSEntity.flat(_path[_path_index] - hero.global_position).length() < 1.6:
		_path_index += 1
	if _path_index < _path.size():
		next = _path[_path_index]
	var dir := RTSEntity.flat(next - hero.global_position).normalized()
	_set_move(dir)
	if face:
		_look_toward(dir, delta)
		intent.pitch = move_toward(intent.pitch, 0.0, delta * 2.0)
	# Bunny hop on long walks.
	if flat.length() > 18.0 and hero.stamina > 40.0 and not hero.exhausted:
		intent.jump = true


func _look_toward(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.001:
		return
	hero.intent.yaw = rotate_toward(hero.intent.yaw, atan2(-dir.x, -dir.z), TURN_RATE[skill] * delta)


## World direction -> the hero's local move input.
func _set_move(world_dir: Vector3) -> void:
	var local := Basis(Vector3.UP, -hero.intent.yaw) * world_dir
	hero.intent.move = Vector2(local.x, local.z).limit_length(1.0)


func _unstick(delta: float) -> void:
	if hero.intent.move.length_squared() < 0.01:
		_stuck = 0.0
		_last_pos = hero.global_position
		return
	if RTSEntity.flat(hero.global_position - _last_pos).length() > 0.6:
		_stuck = 0.0
		_last_pos = hero.global_position
		return
	_stuck += delta
	if _stuck > 0.8:
		_jump_hold = 0.3
		_repath = 0.0
		_stuck = 0.0
	if _jump_hold > 0.0:
		_jump_hold -= delta
		hero.intent.jump = true
		hero.intent.move = Vector2(_strafe * 0.7, -0.7)


## Where to stand in its lane: a few meters behind its own furthest minion,
## or by its furthest standing tower when there's no wave out.
func _lane_spot() -> Vector3:
	var game := hero.game
	var path := game.map.lane_path(hero.team, hero.lane)
	var front := -1.0
	for entity in game.entities:
		var unit := entity as RTSUnit
		if unit and unit.team == hero.team and unit.lane == hero.lane and not unit.dead:
			var progress := RTSMap.progress_on(path, unit.global_position)
			if progress.y < 20.0:
				front = maxf(front, progress.x)
	if front < 0.0:
		front = RTSGame.TOWER_DISTANCES[0]
		for tower: Variant in game.towers[hero.team][hero.lane]:
			if tower != null:
				front = maxf(front, RTSMap.progress_on(path, (tower as RTSStructure).global_position).x)
		front += 4.0
	else:
		front -= 6.0
	var spot := RTSMap.point_along(path, clampf(front, 0.0, RTSMap.path_length(path)))
	var side := RTSMap.direction_along(path, front).cross(Vector3.UP)
	return spot + side * ((hero.index % 2) * 2.0 - 1.0) * 2.5


# --- Senses -------------------------------------------------------------------

func _valid(thing: Object) -> bool:
	if thing == null or not is_instance_valid(thing):
		return false
	if thing is Hero:
		return not (thing as Hero).dead
	if thing is RTSEntity:
		return not (thing as RTSEntity).dead and not (thing as RTSEntity).shielded
	return false


func _aim_point_of(thing: Object) -> Vector3:
	if thing is Hero:
		return (thing as Hero).global_position + Vector3.UP * 1.25
	var entity := thing as RTSEntity
	return entity.global_position + Vector3.UP * minf(entity.bar_height * 0.5, 1.6)


## Line of sight from `eye` to `point`, ignoring what's being looked at.
func _can_see(eye: Vector3, point: Vector3, thing: Object) -> bool:
	var exclude: Array[RID] = [hero.get_rid()]
	if thing is Hero:
		exclude.append((thing as Hero).get_rid())
	elif thing is RTSEntity and (thing as RTSEntity).hitbox:
		exclude.append((thing as RTSEntity).hitbox.get_rid())
	var query := PhysicsRayQueryParameters3D.create(eye, point, Combat.WORLD, exclude)
	return hero.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _minions_near(pos: Vector3, reach: float) -> int:
	var total := 0
	for entity in hero.game.nearby(pos, reach):
		if entity.team == hero.team and entity is RTSUnit and not entity.dead and not (entity as RTSUnit).is_worker:
			total += 1
	return total


func _under_enemy_tower(pos: Vector3) -> bool:
	for entity in hero.game.nearby(pos, TOWER_DANGER):
		if entity.team != hero.team and entity.is_structure and entity.can_attack() and not entity.dead:
			return true
	return false
