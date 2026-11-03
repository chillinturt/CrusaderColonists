class_name RTSUnit
extends RTSEntity
## A unit that walks (or flies), fights, and, for peasants, gathers and builds.
##
## Orders are dictionaries in a queue (shift-click appends), each with a "type"
## from Order plus what it needs:
##   IDLE         stands; fights anything that comes within sight
##   MOVE         pos, spread: goes there, ignoring enemies
##   ATTACK_MOVE  pos, spread: goes there, fighting whatever it meets on the way
##   ATTACK       target: hunts one enemy down
##   HOLD         stays put; fights only what's in range
##   PATROL       pos, from: attack-moves back and forth
##   GATHER       target (crystal or extractor), phase: mines, carries it home, repeats
##   RETURN       carries what it holds home, then goes back to gathering
##   BUILD        kind, pos, resume: walks there and raises the structure (prepaid)
## Walking units follow smoothed nav-grid paths and push each other apart;
## gathering peasants pass through each other (as in StarCraft's mineral walk).

enum Order { IDLE, MOVE, ATTACK_MOVE, ATTACK, HOLD, PATROL, GATHER, RETURN, BUILD }

const ACCEL := 40.0
const TURN_RATE := 10.0

var speed := 5.0
var altitude := 0.0
var attack_range := 0.0
var min_range := 0.0
var is_worker := false
## Lane minions: which lane they push (0-2), or -1 for units the team trained.
## Minions are free, take no supply, and the AI commander leaves them be.
var lane := -1
var orders: Array[Dictionary] = []
## What it's fighting right now (from an order, or picked up on its own).
var target: RTSEntity
var cooldown := 0.0
## Carried resources ("crystal" / "aether") and how much.
var cargo_kind := ""
var cargo := 0
## Where it last gathered, to go back after carrying a load home.
var gather_target: Node3D
var velocity := Vector3.ZERO

var _desired := Vector3.ZERO
var _face_dir := Vector3.ZERO
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF
var _repath := 0.0
var _scan := 0.0
var _best_distance := INF
var _stuck := 0.0
var _work := 0.0
var _working := false
var _inside: RTSStructure
## [node, rest rotation, phase offset, is_arm]
var _limbs: Array = []
var _wings: Array[Node3D] = []
var _rotors: Array[Node3D] = []
var _phase := 0.0
var _swing := 0.0
var _flap := 0.0
var _cargo_visual: MeshInstance3D
var _attack_tween: Tween


func setup(p_game: RTSGame, p_team: int, p_kind: String, p_def: Dictionary) -> void:
	super(p_game, p_team, p_kind, p_def)
	speed = def.speed
	flying = def.get("flying", false)
	altitude = def.get("altitude", 0.0)
	radius = def.radius
	attack_range = def.get("range", 0.0)
	min_range = def.get("min_range", 0.0)
	is_worker = def.get("worker", false)
	visual = RTSModels.unit_visual(kind, team)
	add_child(visual)
	_collect_parts()
	_make_ring()
	Hitbox.for_unit(self, radius * 0.9, def.get("height", 2.0))
	_scan = randf() * 0.3
	_flap = randf() * TAU
	if flying:
		global_position.y = game.map.height_at(global_position.x, global_position.z) + altitude


# --- Orders -------------------------------------------------------------------

func order_type() -> int:
	return orders[0].type if not orders.is_empty() else Order.IDLE


func command(order: Dictionary, queue := false) -> void:
	if dead:
		return
	if not queue or orders.is_empty():
		_cancel_orders()
		orders.append(order)
		_begin_order()
	else:
		orders.append(order)


func stop() -> void:
	_cancel_orders()


## Gathering (or carrying cargo for) anything right now.
func is_gathering() -> bool:
	var t := order_type()
	return t == Order.GATHER or t == Order.RETURN


func is_idle() -> bool:
	return orders.is_empty() and not _inside


func _cancel_orders() -> void:
	for order in orders:
		if order.type == Order.BUILD and not order.get("placed", false):
			game.refund(team, order.kind)
	orders.clear()
	target = null
	_release_claims()
	_path_goal = Vector3.INF
	if _inside:
		_leave_extractor(false)


func _next_order() -> void:
	if not orders.is_empty():
		orders.pop_front()
	target = null
	_release_claims()
	_path_goal = Vector3.INF
	_begin_order()


func _begin_order() -> void:
	_best_distance = INF
	_stuck = 0.0
	_work = 0.0
	# Drop the old route: it leads to the previous order's destination.
	_path = PackedVector3Array()
	_path_goal = Vector3.INF
	_repath = 0.0
	if not orders.is_empty() and orders[0].type == Order.ATTACK:
		target = orders[0].target


func _release_claims() -> void:
	for resource: RTSResource in game.map.resources:
		if is_instance_valid(resource) and resource.miner == self:
			resource.miner = null


# --- Update -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	cooldown -= delta
	_desired = Vector3.ZERO
	_face_dir = Vector3.ZERO
	_working = false
	if _inside != null:
		_work -= delta
		if _work <= 0.0 or not is_instance_valid(_inside) or _inside.dead:
			_leave_extractor(true)
		return
	match order_type():
		Order.IDLE:
			_do_idle(delta)
		Order.MOVE:
			_do_move(delta)
		Order.ATTACK_MOVE:
			_do_attack_move(delta)
		Order.ATTACK:
			_do_attack(delta)
		Order.HOLD:
			_do_hold(delta)
		Order.PATROL:
			_do_patrol(delta)
		Order.GATHER:
			_do_gather(delta)
		Order.RETURN:
			_do_return(delta)
		Order.BUILD:
			_do_build(delta)
	_apply_motion(delta)
	_animate(delta)


func _do_idle(delta: float) -> void:
	if target != null:
		if _valid_target(target, true) and edge_distance(target) <= sight * 1.3 and _engage(target, delta, true):
			return
		target = null
	if is_worker or not can_attack():
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.35
		target = game.find_target(self, sight)


func _do_move(delta: float) -> void:
	var order := orders[0]
	if _arrived(order.pos, order.get("spread", 0.4), delta):
		_next_order()


func _do_attack_move(delta: float) -> void:
	var order := orders[0]
	if _fight_on_the_way(delta):
		return
	if _arrived(order.pos, order.get("spread", 0.4), delta):
		_next_order()


func _do_patrol(delta: float) -> void:
	var order := orders[0]
	if _fight_on_the_way(delta):
		return
	if _arrived(order.pos, 1.0, delta):
		var back: Vector3 = order.from
		order.from = order.pos
		order.pos = back
		_begin_order()
		_path_goal = Vector3.INF


## Attack-move and patrol: picks fights within sight. True while fighting.
func _fight_on_the_way(delta: float) -> bool:
	if target != null:
		if _valid_target(target, true) and edge_distance(target) <= sight * 1.2 and _engage(target, delta, true):
			return true
		target = null
		_path_goal = Vector3.INF
		_best_distance = INF
	if not can_attack():
		return false
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.3
		target = game.find_target(self, sight)
		if target != null:
			_best_distance = INF
			return _engage(target, delta, true)
	return false


func _do_attack(delta: float) -> void:
	var order := orders[0]
	var victim: RTSEntity = order.target if is_instance_valid(order.target) else null
	if victim == null or victim.dead or not can_hit(victim):
		_next_order()
		return
	target = victim
	if not _engage(victim, delta, true):
		_next_order()


func _do_hold(delta: float) -> void:
	if target != null and not (_valid_target(target, true) and _engage(target, delta, false)):
		target = null
	if target == null and can_attack():
		_scan -= delta
		if _scan <= 0.0:
			_scan = 0.3
			target = game.find_target(self, attack_range + radius + 0.3)


## Whether it got to `goal` (within `spread`, or as close as the crowd allows).
func _arrived(goal: Vector3, spread: float, delta: float) -> bool:
	if _go(goal, delta, spread):
		return true
	var dist := flat(goal - global_position).length()
	return (_stuck > 1.0 and dist < spread + 2.5) or _stuck > 5.0


# --- Fighting -----------------------------------------------------------------

func _valid_target(other: RTSEntity, need_sight: bool) -> bool:
	if not is_instance_valid(other) or other.dead or not can_hit(other):
		return false
	return not need_sight or game.is_visible_to(team, other)


## Fights `other`: attacks when in range, else closes in (if it may move).
## False when it can't fight it from here.
func _engage(other: RTSEntity, delta: float, may_move: bool) -> bool:
	var d := edge_distance(other)
	if d <= attack_range + 0.3 and d >= min_range:
		_face_dir = flat(other.global_position - global_position)
		if cooldown <= 0.0:
			cooldown = def.cooldown
			_strike(other)
		return true
	if not may_move:
		return false
	if d < min_range:
		_desired = -flat(other.global_position - global_position).normalized() * speed
		return true
	_go(other.global_position, delta, 0.0)
	return true


func _strike(other: RTSEntity) -> void:
	_lunge()
	var projectile: String = def.get("projectile", "")
	if projectile != "":
		game.fire(self, other, projectile)
	else:
		game.impact(self, team, def, other, other.global_position)


func take_damage(amount: float, attacker: RTSEntity) -> void:
	super(amount, attacker)
	if dead or attacker == null or not is_instance_valid(attacker) or attacker.dead:
		return
	if target == null and not is_worker and can_hit(attacker):
		match order_type():
			Order.IDLE, Order.ATTACK_MOVE, Order.PATROL:
				target = attacker
			Order.HOLD:
				if edge_distance(attacker) <= attack_range + 0.3:
					target = attacker


## Joins a fight a nearby ally is in (if it's just standing around).
func help_against(attacker: RTSEntity) -> void:
	if target == null and not is_worker and order_type() == Order.IDLE and can_hit(attacker):
		target = attacker


# --- Gathering ----------------------------------------------------------------

func _do_gather(delta: float) -> void:
	var order := orders[0]
	var source: Node3D = order.target if is_instance_valid(order.target) else null
	var source_kind := "aether" if source is RTSStructure else "crystal"
	if cargo > 0 and order.get("phase", "go") == "go" and cargo_kind != source_kind:
		order.phase = "return"
	if order.get("phase", "go") == "return":
		if _deliver(delta):
			order.phase = "go"
		return
	if source is RTSStructure:
		_gather_aether(order, source as RTSStructure, delta)
	else:
		_gather_crystal(order, source as RTSResource, delta)


func _gather_crystal(order: Dictionary, crystal: RTSResource, delta: float) -> void:
	if crystal == null or crystal.dead:
		var near: Vector3 = order.get("at", global_position)
		crystal = game.free_crystal_near(near, 14.0, self)
		if crystal == null:
			_next_order()
			return
		order.target = crystal
	order.at = crystal.global_position
	var d := flat(crystal.global_position - global_position).length()
	if is_instance_valid(crystal.miner) and crystal.miner != self:
		if d < radius + crystal.radius + 4.0:
			var other := game.free_crystal_near(crystal.global_position, 9.0, self)
			if other != null:
				order.target = other
				_path_goal = Vector3.INF
				return
			_face_dir = flat(crystal.global_position - global_position)
			return  # wait for it to come free
		_go(crystal.global_position, delta, radius + crystal.radius + 1.0)
		return
	if not _touch(crystal, crystal.radius, delta):
		if _stuck > 3.0:  # can't get to this one; another will do
			order.target = game.free_crystal_near(crystal.global_position, 9.0, self)
			_stuck = 0.0
			_path_goal = Vector3.INF
		return
	crystal.miner = self
	_working = true
	_face_dir = flat(crystal.global_position - global_position)
	_work += delta
	if _work >= RTSData.MINE_TIME:
		_work = 0.0
		cargo = crystal.take(RTSData.CRYSTAL_PER_TRIP)
		cargo_kind = "crystal"
		crystal.miner = null
		gather_target = crystal
		order.phase = "return"
		_update_cargo()


func _gather_aether(_order: Dictionary, extractor: RTSStructure, delta: float) -> void:
	if extractor == null or extractor.dead or not extractor.built or extractor.team != team \
			or extractor.vent == null or extractor.vent.is_depleted():
		_next_order()
		return
	if not _touch(extractor, extractor.radius, delta):
		return
	if is_instance_valid(extractor.occupant) and extractor.occupant != self:
		_face_dir = flat(extractor.global_position - global_position)
		return
	_inside = extractor
	extractor.occupant = self
	tucked_away = true
	visible = false
	_work = RTSData.EXTRACT_TIME
	gather_target = extractor


func _leave_extractor(with_cargo: bool) -> void:
	var extractor := _inside
	_inside = null
	tucked_away = false
	visible = game.is_visible_to(0, self)
	if not is_instance_valid(extractor):
		return
	if extractor.occupant == self:
		extractor.occupant = null
	if with_cargo and not extractor.dead and extractor.vent != null:
		cargo = extractor.vent.take(RTSData.AETHER_PER_TRIP)
		cargo_kind = "aether"
		_update_cargo()
		if not orders.is_empty() and orders[0].type == Order.GATHER:
			orders[0].phase = "return"
	# Step out on the side facing home.
	var home := game.nearest_dropoff(team, extractor.global_position)
	var out_dir := flat(home.global_position - extractor.global_position).normalized() if home else Vector3.BACK
	var spot := extractor.global_position + out_dir * (extractor.radius + radius + 0.8)
	global_position = game.map.ground(game.map.nav.nearest_open_point(spot))


## Carries cargo to the nearest keep. True once delivered.
func _deliver(delta: float) -> bool:
	if cargo <= 0:
		return true
	var keep := game.nearest_dropoff(team, global_position)
	if keep == null or not _touch(keep, keep.radius, delta):
		return false
	game.add_income(team, cargo_kind, cargo)
	cargo = 0
	cargo_kind = ""
	_update_cargo()
	return true


func _do_return(delta: float) -> void:
	if _deliver(delta):
		if is_instance_valid(gather_target) and not gather_target.get("dead"):
			orders[0] = {"type": Order.GATHER, "target": gather_target, "phase": "go"}
			_begin_order()
		else:
			_next_order()


func _update_cargo() -> void:
	if _cargo_visual:
		_cargo_visual.queue_free()
		_cargo_visual = null
	if cargo > 0:
		_cargo_visual = RTSModels.cargo(cargo_kind)
		_cargo_visual.position = Vector3(0, 1.75, 0)
		add_child(_cargo_visual)


# --- Building -----------------------------------------------------------------

func _do_build(delta: float) -> void:
	var order := orders[0]
	var pos: Vector3 = order.pos
	var half: float = RTSData.structure(order.kind).size * game.map.cell * 0.5
	var d := flat(pos - global_position).length()
	if d > half + radius + 1.5 and _stuck < 3.0:
		_go(pos, delta, half + radius + 1.0)
		return
	order.placed = true
	var built := game.construct(team, order.kind, pos)
	if built == null:
		game.refund(team, order.kind)
		game.notify(team, "Can't build there.")
	var resume: Variant = order.get("resume")
	_next_order()
	if orders.is_empty() and is_instance_valid(resume):
		command({"type": Order.GATHER, "target": resume, "phase": "go"})


# --- Movement -----------------------------------------------------------------

## Steers toward `goal` along a path around obstacles. True once within `arrive`.
func _go(goal: Vector3, delta: float, arrive: float) -> bool:
	var to := flat(goal - global_position)
	var dist := to.length()
	if dist <= arrive:
		return true
	if dist < _best_distance - 0.3:
		_best_distance = dist
		_stuck = 0.0
	else:
		_stuck += delta
	if flying:
		_desired = to / dist * minf(speed, dist * 3.0 + 1.0)
		return false
	_repath -= delta
	# No route yet (new order, new target): plan one now. Otherwise re-plan when
	# the goal has moved or it's stuck, at most every 0.4 s.
	var no_route := _path_goal == Vector3.INF
	var goal_moved := no_route or _path_goal.distance_squared_to(goal) > 4.0
	if no_route or ((goal_moved or _stuck > 1.0) and _repath <= 0.0):
		_path = game.map.nav.find_path(global_position, goal)
		_path_index = 0
		_path_goal = goal
		_repath = 0.4
	if _path.is_empty():
		return true
	while _path_index < _path.size() - 1 and flat(_path[_path_index] - global_position).length() < 0.9:
		_path_index += 1
	var step := flat(_path[_path_index] - global_position)
	var last := _path_index == _path.size() - 1
	if last and step.length() < 0.35:
		return true  # as close as it can get
	var want := speed
	if last:
		want = minf(speed, step.length() * 3.0 + 0.6)
	_desired = step.normalized() * want
	return false


## Walks up to something that blocks its own cells (a crystal, a building).
## True once close enough to touch it, or as close as the grid lets it get.
func _touch(thing: Node3D, thing_radius: float, delta: float) -> bool:
	var d := flat(thing.global_position - global_position).length()
	var reach := radius + thing_radius + 1.0
	if d <= reach:
		return true
	return _go(thing.global_position, delta, reach - 0.2) and d <= reach + 2.5


## Passes through other units (peasants on their gathering rounds).
func is_ghost() -> bool:
	return is_worker and is_gathering()


func _apply_motion(delta: float) -> void:
	var push := Vector3.ZERO
	var moving := _desired.length_squared() > 0.01
	var holding := order_type() == Order.HOLD
	if not is_ghost():
		for other: RTSEntity in game.nearby(global_position, radius + 2.0):
			if other == self or other.is_structure or other.dead or other.flying != flying or other.tucked_away:
				continue
			var unit := other as RTSUnit
			if unit == null or unit.is_ghost():
				continue  # heroes move themselves
			var offset := flat(global_position - other.global_position)
			var min_d := radius + other.radius
			var d := offset.length()
			if d >= min_d:
				continue
			if d < 0.01:
				offset = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
				d = maxf(offset.length(), 0.01)
			var share := 0.5
			var they_move := unit._desired.length_squared() > 0.01
			if holding:
				share = 0.0
			elif unit.order_type() == Order.HOLD:
				share = 1.0
			elif moving and not they_move:
				share = 0.25
			elif they_move and not moving:
				share = 0.75
			push += offset / d * (min_d - d) * share

	velocity = velocity.move_toward(_desired, ACCEL * delta)
	var next := global_position + velocity * delta + push * minf(1.0, 10.0 * delta)
	var map := game.map
	if not flying:
		var nav := map.nav
		if not nav.walkable(next) and nav.walkable(global_position):
			var slide_x := Vector3(next.x, global_position.y, global_position.z)
			var slide_z := Vector3(global_position.x, global_position.y, next.z)
			if nav.walkable(slide_x):
				next = slide_x
			elif nav.walkable(slide_z):
				next = slide_z
			else:
				next = global_position
	next = map.clamp_to_play_area(next)
	var ground := map.height_at(next.x, next.z)
	if flying:
		next.y = lerpf(global_position.y, ground + altitude, minf(1.0, 2.5 * delta))
	else:
		next.y = ground
	global_position = next
	if _ring:
		_ring.position.y = ground - next.y + 0.08

	var face := _face_dir
	if face.length_squared() < 0.01 and velocity.length() > 0.5:
		face = velocity
	if face.length_squared() > 0.01:
		var yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, TURN_RATE * delta))


# --- Looks --------------------------------------------------------------------

## Finds the model's pivots to animate: legs and arms swing, wings flap, rotors spin.
func _collect_parts() -> void:
	for node: Node in visual.find_children("*", "Node3D", true, false):
		if node.get_class() != "Node3D":
			continue
		var part := node as Node3D
		var part_name := String(part.name)
		if part_name.begins_with("Wing"):
			_wings.append(part)
		elif part_name.contains("Rotor"):
			_rotors.append(part)
		elif part_name.begins_with("Leg") or part_name.begins_with("Hip") or part_name.begins_with("Arm"):
			var right := part_name.ends_with("R")
			var back := part_name.length() >= 2 and part_name[part_name.length() - 2] == "B"
			var arm := part_name.begins_with("Arm")
			var offset := (PI if right != back else 0.0) + (PI if arm else 0.0)
			_limbs.append([part, part.rotation, offset, arm])


func _animate(delta: float) -> void:
	var moving := velocity.length() > 0.5
	_swing = move_toward(_swing, 1.0 if moving else 0.0, delta * 4.0)
	_phase += delta * (3.0 + speed * 1.1)
	for limb: Array in _limbs:
		var node: Node3D = limb[0]
		var rest: Vector3 = limb[1]
		var r := rest
		r.x += sin(_phase + limb[2]) * 0.55 * _swing
		if _working and limb[3] and String(node.name) == "ArmR":
			r.x = rest.x + 0.5 + sin(_phase * 2.2) * 0.9
		node.rotation = r
	_flap += delta * (4.5 if kind == "dragon" else 14.0)
	for wing in _wings:
		wing.rotation.z = sin(_flap) * 0.6 * signf(wing.position.x)
	for rotor in _rotors:
		rotor.rotate_object_local(Vector3.UP if rotor.name == &"Rotor" else Vector3.RIGHT, delta * 25.0)
	if flying:
		visual.position.y = sin(_flap * 0.2) * 0.2


func _lunge() -> void:
	if _attack_tween:
		_attack_tween.kill()
	_attack_tween = create_tween()
	_attack_tween.tween_property(visual, "rotation:x", 0.3, 0.07)
	_attack_tween.tween_property(visual, "rotation:x", 0.0, 0.25)


func _on_die() -> void:
	_cancel_orders()
	set_physics_process(false)
	if _attack_tween:
		_attack_tween.kill()
	if def.get("supply", 0) >= 3:
		Explosion.spawn_fx(get_parent(), global_position + Vector3.UP * bar_height * 0.5, radius * 2.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(visual, "scale", visual.scale * 0.01, 0.35)
	if flying:
		tween.tween_property(self, "global_position:y", game.map.height_at(global_position.x, global_position.z), 0.35)
	tween.chain().tween_callback(queue_free)
