class_name RTSResource
extends Node3D
## A crystal formation (peasants mine it directly, one at a time) or an aether
## vent (needs an extractor built on top; peasants draw from that). Blocks its
## nav cells; a mined-out crystal crumbles and frees them.

var kind := "crystal"
var amount := 1500
var start_amount := 1500
var radius := 1.0
var map: RTSMap
var cells: Array[Vector2i] = []
## Crystal: the peasant mining it right now.
var miner: Node3D
## Vent: the extractor built on it.
var extractor: Node3D
## Neutral things have team -1 (for picking and the HUD).
var team := -1
var dead := false

var _visual: Node3D
var _glow: MeshInstance3D
var _time := 0.0


func setup(p_map: RTSMap, p_kind: String, p_amount: int, p_cells: Array[Vector2i]) -> void:
	map = p_map
	kind = p_kind
	amount = p_amount
	start_amount = p_amount
	cells = p_cells
	radius = 1.0 if kind == "crystal" else 1.8
	for c in cells:
		map.nav.set_occupied(c, true)
	_visual = Node3D.new()
	add_child(_visual)
	if kind == "crystal":
		_build_crystal()
		# Solid for heroes (it's world, so shots stop on it too).
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = Combat.WORLD
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.75
		cylinder.height = 2.2
		shape.shape = cylinder
		shape.position.y = 1.1
		body.add_child(shape)
		add_child(body)
	else:
		_build_vent()


func display_name() -> String:
	return "Crystal" if kind == "crystal" else "Aether Vent"


func is_depleted() -> bool:
	return amount <= 0


## Takes up to `want` from it; returns how much it gave.
func take(want: int) -> int:
	var got := mini(want, amount)
	amount -= got
	if kind == "crystal":
		_visual.scale = Vector3.ONE * lerpf(0.45, 1.0, float(amount) / start_amount)
		if amount <= 0:
			_crumble()
	return got


func _process(delta: float) -> void:
	if _glow:
		_time += delta
		var pulse := 0.8 + 0.2 * sin(_time * 2.0)
		_glow.scale = Vector3(pulse, 1.0, pulse)


func _crumble() -> void:
	dead = true
	var body := get_node_or_null("Body")
	if body:
		body.queue_free()
	for c in cells:
		map.nav.set_occupied(c, false)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.4)
	tween.tween_callback(queue_free)


func _build_crystal() -> void:
	var material := map.fogged_material(Color(0.35, 0.75, 1.0), Color(0.15, 0.55, 1.0) * 1.6, 0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position) if is_inside_tree() else hash(cells)
	for i in 4:
		var prism := CylinderMesh.new()
		prism.top_radius = 0.04
		prism.bottom_radius = rng.randf_range(0.25, 0.4)
		prism.height = rng.randf_range(1.2, 2.4)
		prism.radial_segments = 5
		prism.rings = 1
		var mesh := MeshInstance3D.new()
		mesh.mesh = prism
		mesh.material_override = material
		var offset := Vector2.from_angle(i * TAU / 4.0 + rng.randf()) * (0.0 if i == 0 else 0.55)
		var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35)))
		mesh.transform = Transform3D(tilt, Vector3(offset.x, prism.height * 0.4, offset.y))
		_visual.add_child(mesh)


func _build_vent() -> void:
	var rock := map.fogged_material(Color(0.25, 0.24, 0.23))
	for i in 7:
		var angle := i * TAU / 7.0
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.7, 0.7)
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		mesh.material_override = rock
		mesh.transform = Transform3D(Basis(Vector3.UP, -angle), Vector3(cos(angle) * 1.5, 0.2, sin(angle) * 1.5))
		_visual.add_child(mesh)
	var pool := CylinderMesh.new()
	pool.top_radius = 1.2
	pool.bottom_radius = 1.2
	pool.height = 0.1
	_glow = MeshInstance3D.new()
	_glow.mesh = pool
	_glow.material_override = map.fogged_material(Color(0.3, 1.0, 0.4), Color(0.3, 1.0, 0.35) * 2.0, 0.1)
	_glow.position.y = 0.15
	_visual.add_child(_glow)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.5)
	light.light_energy = 1.2
	light.omni_range = 5.0
	light.position.y = 1.0
	_visual.add_child(light)
