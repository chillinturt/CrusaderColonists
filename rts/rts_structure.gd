class_name RTSStructure
extends RTSEntity
## A building: rises over its build time once placed (health grows with it),
## then trains units from its queue, adds supply, takes resource drop-offs
## (keeps), draws aether (extractors) or shoots (watchtowers). Blocks its
## footprint on the nav grid until destroyed.

var cells := 2
var origin := Vector2i.ZERO
var built := false
## 0..1 while under construction.
var progress := 0.0
var queue: Array[String] = []
## Seconds spent on the unit at the front of the queue.
var train_time := 0.0
## Where trained units go (INF = nowhere): a spot, or a resource to gather.
var rally := Vector3.INF
var rally_target: Node3D
## Extractor: the vent under it, and the peasant inside right now.
var vent: RTSResource
var occupant: RTSUnit

var _target: RTSEntity
var _cooldown := 0.0
var _scan := 0.0
var _spin: Node3D


func setup_structure(p_game: RTSGame, p_team: int, p_kind: String, p_origin: Vector2i, p_built: bool) -> void:
	setup(p_game, p_team, p_kind, RTSData.structure(p_kind))
	is_structure = true
	cells = def.size
	origin = p_origin
	radius = cells * game.map.cell * 0.5
	visual = RTSModels.structure_visual(kind, team, cells * game.map.cell)
	add_child(visual)
	_spin = visual.find_child("Spin", true, false) as Node3D
	_make_ring()
	Hitbox.for_structure(self, cells * game.map.cell - 0.8, bar_height * 0.85)
	for c in game.map.footprint(origin, cells):
		game.map.nav.set_occupied(c, true)
	built = p_built
	if built:
		progress = 1.0
	else:
		progress = 0.0
		hp = max_hp * 0.1
		visual.scale.y = 0.15


## Shielded structures can't be hurt; a translucent dome shows it.
func set_shielded(value: bool) -> void:
	shielded = value
	var dome := get_node_or_null("Shield") as MeshInstance3D
	if value and dome == null:
		dome = RTSModels.shield_dome(radius + 1.2, RTSData.TEAM_COLORS[team])
		dome.name = "Shield"
		add_child(dome)
	elif not value and dome:
		dome.queue_free()


func trains() -> Array:
	return def.get("trains", [])


func supply_provided() -> int:
	return def.get("supply", 0) if built else 0


## Seconds left on the unit being trained.
func train_fraction() -> float:
	if queue.is_empty():
		return 0.0
	return train_time / float(RTSData.unit(queue[0]).time)


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _spin:
		_spin.rotate_y(delta * 0.8)
	if not built:
		var step: float = delta / float(def.time) * game.build_speed
		progress = minf(progress + step, 1.0)
		hp = minf(max_hp, hp + max_hp * 0.9 * step)
		visual.scale.y = lerpf(0.15, 1.0, progress)
		if progress >= 1.0:
			built = true
			visual.scale.y = 1.0
			game.on_structure_built(self)
		return
	if not queue.is_empty():
		train_time += delta * game.build_speed
		if train_time >= float(RTSData.unit(queue[0]).time):
			train_time = 0.0
			var unit_kind: String = queue.pop_front()
			game.spawn_trained(self, unit_kind)
	if def.get("damage", 0.0) > 0.0:
		_turret(delta)


func _turret(delta: float) -> void:
	_cooldown -= delta
	var reach: float = def.range + radius
	if _target != null and (not is_instance_valid(_target) or _target.dead or edge_distance(_target) > def.range + 0.3):
		_target = null
	if _target == null:
		_scan -= delta
		if _scan <= 0.0:
			_scan = 0.3
			_target = game.find_target(self, reach)
	if _target != null and _cooldown <= 0.0:
		_cooldown = def.cooldown
		game.fire(self, _target, def.projectile)


func _on_die() -> void:
	for c in game.map.footprint(origin, cells):
		game.map.nav.set_occupied(c, false)
	if vent:
		vent.extractor = null
	if is_instance_valid(occupant):
		occupant._leave_extractor(false)
	set_physics_process(false)
	Explosion.spawn_fx(get_parent(), global_position + Vector3.UP * 1.5, radius * 1.4)
	var tween := create_tween().set_parallel()
	tween.tween_property(visual, "position:y", -bar_height, 1.2).set_ease(Tween.EASE_IN)
	tween.tween_property(visual, "rotation:z", 0.15, 1.2)
	tween.chain().tween_callback(queue_free)
