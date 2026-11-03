class_name RTSProjectile
extends Node3D
## A shot in flight. Looks like one of the action game's projectiles (its scene,
## with the script taken off), but flies a set course: straight shots follow
## their target, lobbed shells land where the target stood when fired (so they
## can be dodged). Damage happens on arrival.

static var _scenes := {}

var game: RTSGame
var team := 0
var attacker: RTSEntity
var attack_def: Dictionary
var target: RTSEntity
var _start := Vector3.ZERO
var _end := Vector3.ZERO
var _t := 0.0
var _duration := 1.0
var _arc := 0.0


func launch(p_game: RTSGame, p_attacker: RTSEntity, p_target: RTSEntity, kind: String) -> void:
	game = p_game
	attacker = p_attacker
	team = attacker.team
	attack_def = attacker.def
	target = p_target
	var spec: Dictionary = RTSData.PROJECTILES[kind]
	_arc = spec.arc
	_start = attacker.global_position + Vector3.UP * attacker.bar_height * 0.7
	_end = _aim()
	_duration = maxf(_start.distance_to(_end) / float(spec.speed), 0.08)
	global_position = _start
	reset_physics_interpolation()

	if not _scenes.has(spec.scene):
		_scenes[spec.scene] = load(spec.scene)
	var scene: PackedScene = _scenes[spec.scene]
	var look := scene.instantiate() as Node3D
	look.set_script(null)
	var hitbox := look.get_node_or_null("Hitbox")
	if hitbox:
		look.remove_child(hitbox)
		hitbox.free()
	look.scale = Vector3.ONE * float(spec.scale)
	if kind == "fire":
		_recolor(look, Color(1.0, 0.35, 0.05))
	add_child(look)
	_orient(_end - _start)


func _aim() -> Vector3:
	if not is_instance_valid(target) or target.dead:
		return _end
	return target.global_position + Vector3.UP * minf(target.bar_height * 0.5, 2.0)


func _physics_process(delta: float) -> void:
	if _arc <= 0.0:
		_end = _aim()  # straight shots home in
	_t = minf(_t + delta / _duration, 1.0)
	var previous := global_position
	var p := _start.lerp(_end, _t)
	p.y += _arc * 4.0 * _t * (1.0 - _t)
	global_position = p
	_orient(p - previous)
	visible = game.view_mode == "hero" or game.fog_visible(p)
	if _t >= 1.0:
		var by: RTSEntity = attacker if is_instance_valid(attacker) and not attacker.dead else null
		var hit: RTSEntity = target if _arc <= 0.0 and is_instance_valid(target) and not target.dead else null
		var point := _end
		if _arc > 0.0:
			point = game.map.ground(_end)
		game.impact(by, team, attack_def, hit, point)
		queue_free()


func _orient(direction: Vector3) -> void:
	if direction.length_squared() > 0.0001 and absf(direction.normalized().y) < 0.99:
		look_at(global_position + direction, Vector3.UP)


static func _recolor(node: Node, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	for child: Node in node.find_children("*", "", true, false):
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material
		elif child is OmniLight3D:
			(child as OmniLight3D).light_color = color
