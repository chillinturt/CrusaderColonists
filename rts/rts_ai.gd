class_name RTSAI
extends Node
## The computer opponent. Every think (faster on harder settings) it:
##   1. puts idle peasants to work, and three on each extractor
##   2. builds: farmsteads before it runs out of supply, then a tech path
##      (barracks, extractor, forge, towers, an expansion, aerie, sanctum...)
##      timed by the clock and its worker count, saving up for the next one
##   3. trains peasants up to a target, and a weighted mix of whatever army
##      units its tech allows from every idle production structure
##   4. commands the army: defend when its base is hit, otherwise gather at a
##      staging point and attack-move at your nearest structure once the army
##      is big enough (each wave bigger than the last), pulling back if it's
##      mostly wiped out
## Difficulty: easy thinks slowly, sends small waves and never expands; hard
## thinks fast, mines 30% faster (set by the game) and moves through its build
## order sooner.
## In a match it is a team's commander: it runs either side (or helps you run
## yours). Heroes and lane minions are never its to order; it builds clear of the
## lanes and the fountain, and its army goes for structures that aren't shielded.

const UNIT_WEIGHTS := {"knight": 3, "leaper": 3, "dragoon": 4, "golem": 3, "titan": 2, "wasp": 3, "harpy": 2, "dragon": 2}
const RINGS: Array[float] = [10.0, 13.0, 16.0, 19.0, 22.0, 25.0, 28.0, 31.0]

var game: RTSGame
var team := 1
var difficulty := 1
var main_base := Vector3.ZERO
var natural := Vector3.ZERO
var staging := Vector3.ZERO

var _think := 0.0
var _interval := 1.0
var _wave_size := 12
var _attacking := false
var _threat := Vector3.INF
var _threat_time := 0.0
var _reserve_crystal := 0
var _reserve_aether := 0
var _rng := RandomNumberGenerator.new()

var _workers: Array[RTSUnit] = []
var _army: Array[RTSUnit] = []
var _structures: Array[RTSStructure] = []
## kind -> how many it has, including ones being built or about to be.
var _counts := {}


func setup(p_team: int, p_difficulty: int) -> void:
	team = p_team
	difficulty = p_difficulty
	main_base = game.map.bases[team]
	natural = game.map.bases[2 + team]
	staging = main_base + RTSEntity.flat(-main_base).normalized() * 24.0
	staging = game.map.ground(game.map.nav.nearest_open_point(staging))
	_interval = [2.0, 1.0, 0.6][difficulty]
	_wave_size = [16, 12, 10][difficulty]
	_rng.randomize()


## Something of ours got hit: defend if it's at home.
func on_attacked(entity: RTSEntity, attacker: RTSEntity) -> void:
	for structure in _structures:
		if is_instance_valid(structure) and structure.global_position.distance_to(entity.global_position) < 30.0:
			_threat = attacker.global_position
			_threat_time = 6.0
			return


func _physics_process(delta: float) -> void:
	if not game.started or game.game_over:
		return
	_threat_time -= delta
	_think -= delta
	if _think > 0.0:
		return
	_think = _interval
	_survey()
	_manage_workers()
	_build()
	_train()
	_command_army()


func _survey() -> void:
	_workers.clear()
	_army.clear()
	_structures.clear()
	_counts.clear()
	for entity in game.entities:
		if entity.team != team or entity.dead:
			continue
		_counts[entity.kind] = _counts.get(entity.kind, 0) + 1
		if entity is RTSStructure:
			_structures.append(entity)
			continue
		var unit := entity as RTSUnit
		if unit == null or unit.lane >= 0:
			continue  # heroes and lane minions aren't the commander's to order
		if unit.is_worker:
			_workers.append(unit)
			for order in unit.orders:
				if order.type == RTSUnit.Order.BUILD and not order.get("placed", false):
					_counts[order.kind] = _counts.get(order.kind, 0) + 1
		else:
			_army.append(unit)


func _built(kind: String) -> Array[RTSStructure]:
	var result: Array[RTSStructure] = []
	for structure in _structures:
		if structure.kind == kind and structure.built:
			result.append(structure)
	return result


# --- Economy ------------------------------------------------------------------

func _manage_workers() -> void:
	var keeps := _built("keep")
	if keeps.is_empty():
		return
	# Three on each extractor (one when aether is piling up).
	var per_extractor := 1 if game.aether[team] > 600 else 3
	for extractor in _built("extractor"):
		if extractor.vent == null or extractor.vent.is_depleted():
			continue
		var assigned := 0
		for worker in _workers:
			if worker.order_type() == RTSUnit.Order.GATHER and worker.orders[0].target == extractor:
				assigned += 1
		if assigned > per_extractor:
			for worker in _workers:
				if assigned > per_extractor and worker.order_type() == RTSUnit.Order.GATHER and worker.orders[0].target == extractor \
						and not worker.tucked_away:
					worker.stop()  # idle: mines crystal at the next think
					assigned -= 1
		for i in per_extractor - assigned:
			var worker := _pick_worker(extractor.global_position)
			if worker == null:
				break
			worker.command({"type": RTSUnit.Order.GATHER, "target": extractor, "phase": "go"})
	# Idle ones mine at the keep with the most free crystal.
	for worker in _workers:
		if not worker.is_idle():
			continue
		var best: RTSResource = null
		for keep in keeps:
			var crystal := game.free_crystal_near(keep.global_position, 18.0, worker)
			if crystal and (best == null or crystal.miner == null):
				best = crystal
		if best:
			worker.command({"type": RTSUnit.Order.GATHER, "target": best, "phase": "go"})


## A crystal miner (not mid-delivery) near `pos`.
func _pick_worker(pos: Vector3) -> RTSUnit:
	var best: RTSUnit = null
	for worker in _workers:
		var mining: bool = worker.order_type() == RTSUnit.Order.GATHER and is_instance_valid(worker.orders[0].target) \
				and worker.orders[0].target is RTSResource and worker.cargo == 0
		if worker.is_idle() or mining:
			if best == null or worker.global_position.distance_to(pos) < best.global_position.distance_to(pos):
				best = worker
	return best


func _worker_target() -> int:
	var keeps := _built("keep").size()
	var target := keeps * 16 + _built("extractor").size() * 3
	return mini(target, [16, 40, 52][difficulty])


func _build() -> void:
	_reserve_crystal = 0
	_reserve_aether = 0
	var pace: float = [0.8, 1.0, 1.3][difficulty]
	var t := game.time * pace
	var workers := _workers.size()
	var keeps: int = _counts.get("keep", 0)
	var cap := game.supply_cap(team)
	var used := game.supply_used(team)
	var producers: int = keeps + _counts.get("barracks", 0) + _counts.get("forge", 0) + _counts.get("aerie", 0)
	# Farms being built or about to be.
	var farms_coming: int = _counts.get("farm", 0) - _built("farm").size()
	var wants: Array = []
	if cap < RTSData.MAX_SUPPLY and used + 2 + producers * 2 >= cap + farms_coming * 8:
		wants.append(["farm", _counts.get("farm", 0) + 1])
	wants.append(["barracks", 1 if workers >= 9 else 0])
	wants.append(["extractor", 1 if workers >= 12 else 0])
	wants.append(["barracks", 2 if t > 200.0 and difficulty >= 1 else 0])
	wants.append(["forge", 1 if t > 240.0 else 0])
	wants.append(["watchtower", 1 if t > 260.0 else 0])
	wants.append(["keep", 2 if t > 330.0 and difficulty >= 1 and workers >= 16 else 0])
	wants.append(["extractor", 2 if workers >= 18 else 0])
	wants.append(["aerie", 1 if t > 400.0 else 0])
	wants.append(["watchtower", 2 if t > 420.0 else 0])
	wants.append(["sanctum", 1 if t > 560.0 else 0])
	wants.append(["barracks", 3 if t > 600.0 and difficulty == 2 else 0])
	wants.append(["extractor", 3 if keeps >= 2 else 0])
	wants.append(["forge", 2 if t > 700.0 else 0])
	wants.append(["watchtower", 3 if keeps >= 2 and t > 500.0 else 0])
	wants.append(["aerie", 2 if t > 800.0 and difficulty == 2 else 0])
	# Money piling up: more places to spend it.
	if difficulty >= 1 and game.crystal[team] > 450:
		var barracks: int = _counts.get("barracks", 0)
		if barracks < 5:
			wants.append(["barracks", barracks + 1])
	if difficulty >= 1 and game.aether[team] > 500 and _counts.get("forge", 0) + _counts.get("aerie", 0) < 4:
		wants.append(["aerie" if _counts.get("aerie", 0) <= _counts.get("forge", 0) else "forge", 9])
	for want: Array in wants:
		var kind: String = want[0]
		if _counts.get(kind, 0) >= int(want[1]) or game.missing_tech(team, kind) != "":
			continue
		var def := RTSData.structure(kind)
		if not game.can_afford(team, kind):
			_reserve_crystal = def.crystal
			_reserve_aether = def.aether
			return  # save up for it
		var spot := _find_spot(kind)
		if spot == Vector3.INF:
			continue
		var builder := _pick_worker(spot)
		if builder == null:
			return
		var resume: Node3D = null
		if builder.order_type() == RTSUnit.Order.GATHER and is_instance_valid(builder.orders[0].target):
			resume = builder.orders[0].target
		game.spend(team, kind)
		builder.command({"type": RTSUnit.Order.BUILD, "kind": kind, "pos": spot, "resume": resume})
		return  # one at a time


func _find_spot(kind: String) -> Vector3:
	if kind == "extractor":
		for keep in _built("keep"):
			for resource in game.map.resources:
				if is_instance_valid(resource) and resource.kind == "vent" and resource.extractor == null \
						and resource.global_position.distance_to(keep.global_position) < 20.0 \
						and game.can_place(team, kind, resource.global_position) and not _vent_claimed(resource):
					return resource.global_position
		return Vector3.INF
	if kind == "keep":
		var options: Array[Vector3] = []
		for index in range(2, game.map.bases.size()):
			options.append(game.map.bases[index])
		options.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(main_base) < b.distance_to(main_base))
		for base in options:
			var spot := game.map.snap(base, 4)
			if game.can_place(team, kind, spot):
				return spot
		return Vector3.INF
	var home := main_base
	var keeps := _built("keep")
	if kind == "watchtower" and keeps.size() >= 2 and _rng.randf() < 0.5:
		home = keeps[_rng.randi() % keeps.size()].global_position
	var away := Vector2(home.x, home.z).normalized()
	var offset := _rng.randf() * TAU
	for r in RINGS:
		for k in 16:
			var direction := Vector2.from_angle(offset + k * TAU / 16.0)
			if direction.dot(away) > 0.3:
				continue  # keep the mineral line clear
			var spot := game.snap_placement(kind, home + Vector3(direction.x, 0.0, direction.y) * r)
			if game.can_place(team, kind, spot) and _leaves_room(spot, RTSData.structure(kind).size * game.map.cell * 0.5):
				return spot
	return Vector3.INF


## Gaps between buildings, so nothing gets walled in.
func _leaves_room(spot: Vector3, half: float) -> bool:
	if game.map.near_lane(spot, half + 5.0) or RTSEntity.flat(spot - game.map.fountain(team)).length() < half + 8.0:
		return false
	for structure in _structures:
		if RTSEntity.flat(structure.global_position - spot).length() < half + structure.radius + 2.5:
			return false
	for resource in game.map.resources:
		if is_instance_valid(resource) and RTSEntity.flat(resource.global_position - spot).length() < half + 4.0:
			return false
	return true


func _vent_claimed(vent: RTSResource) -> bool:
	for worker in _workers:
		for order in worker.orders:
			if order.type == RTSUnit.Order.BUILD and order.kind == "extractor" and order.pos.distance_to(vent.global_position) < 1.0:
				return true
	return false


func _train() -> void:
	var queued_workers := 0
	for keep in _built("keep"):
		queued_workers += keep.queue.size()
	for keep in _built("keep"):
		if keep.queue.is_empty() and _workers.size() + queued_workers < _worker_target():
			if game.queue_train(keep, "peasant") == "":
				queued_workers += 1
	var depth := 2 if difficulty == 2 else 1
	for structure in _structures:
		if not structure.built or structure.trains().is_empty() or structure.kind == "keep" or structure.queue.size() >= depth:
			continue
		if structure.rally == Vector3.INF:
			structure.rally = staging
		var kind := _pick_unit(structure)
		if kind != "":
			game.queue_train(structure, kind)


func _pick_unit(structure: RTSStructure) -> String:
	var options: Array[String] = []
	var weights: Array[int] = []
	var total := 0
	var aether_rich: bool = game.aether[team] > 300
	for kind: String in structure.trains():
		var def := RTSData.unit(kind)
		if game.missing_tech(team, kind) != "":
			continue
		if game.crystal[team] - int(def.crystal) < _reserve_crystal or game.aether[team] - int(def.aether) < _reserve_aether:
			continue
		if not game.can_afford(team, kind):
			continue
		var weight: int = UNIT_WEIGHTS.get(kind, 1)
		if aether_rich and int(def.aether) > 0:
			weight *= 3  # spend the aether that's piling up
		options.append(kind)
		weights.append(weight)
		total += weight
	if options.is_empty():
		return ""
	var roll := _rng.randi_range(1, total)
	for i in options.size():
		roll -= weights[i]
		if roll <= 0:
			return options[i]
	return options[0]


# --- Army ---------------------------------------------------------------------

func _command_army() -> void:
	var strength := 0
	for unit in _army:
		strength += int(unit.def.supply)
	if _threat_time > 0.0 and _threat != Vector3.INF:
		for unit in _army:
			if unit.target == null:
				unit.command({"type": RTSUnit.Order.ATTACK_MOVE, "pos": _threat, "spread": 4.0})
		return
	if _attacking:
		if strength < maxi(4, roundi(_wave_size * 0.3)):
			_attacking = false
			for unit in _army:
				unit.command({"type": RTSUnit.Order.MOVE, "pos": staging, "spread": 5.0})
			return
		var goal := _attack_goal()
		for unit in _army:
			var heading_there: bool = unit.order_type() == RTSUnit.Order.ATTACK_MOVE and unit.orders[0].pos.distance_to(goal) < 12.0
			if unit.target == null and not heading_there:
				unit.command({"type": RTSUnit.Order.ATTACK_MOVE, "pos": goal, "spread": 5.0})
		return
	if strength >= _wave_size:
		_attacking = true
		_wave_size = mini(_wave_size + [4, 6, 8][difficulty], 90)
		return
	for unit in _army:
		if unit.is_idle() and unit.global_position.distance_to(staging) > 12.0:
			unit.command({"type": RTSUnit.Order.ATTACK_MOVE, "pos": staging, "spread": 5.0})


## Your structure nearest its base (it knows where you live), else your units.
func _attack_goal() -> Vector3:
	var best := Vector3.INF
	for entity in game.entities:
		if entity.team == team or entity.dead:
			continue
		var better: bool = best == Vector3.INF or entity.global_position.distance_to(main_base) < best.distance_to(main_base)
		if entity.is_structure and not entity.shielded and better:
			best = entity.global_position
	if best == Vector3.INF:
		for entity in game.entities:
			if entity.team != team and not entity.dead:
				return entity.global_position
		return game.map.bases[1 - team]
	return best
