class_name RTSModels
extends RefCounted
## Looks for units and structures.
##   Units reuse the action game's enemy models: the scene's "Visual" subtree is
##   taken out, its colored parts are recolored to the team's hue (steel, eyes
##   and other neutral parts keep their colors), and it's cached as a template
##   that each new unit duplicates.
##   Structures are built from boxes and cylinders with the action game's grid
##   shader for stone, and team-colored roofs and banners.

const GRID_SHADER := preload("res://level/grid.gdshader")

static var _templates := {}
static var _tinted := {}
static var _materials := {}


## Frees cached templates (call when leaving the RTS).
static func clear_cache() -> void:
	for template: Node in _templates.values():
		if is_instance_valid(template):
			template.free()
	_templates.clear()
	_tinted.clear()
	_materials.clear()


static func unit_visual(kind: String, team: int) -> Node3D:
	var key := "%s:%d" % [kind, team]
	if not _templates.has(key):
		_templates[key] = _build_unit_template(kind, team)
	var template: Node3D = _templates[key]
	return template.duplicate() as Node3D


static func _build_unit_template(kind: String, team: int) -> Node3D:
	var def := RTSData.unit(kind)
	var visual := _extract_visual(def.model, def.get("hide", []))
	_tint(visual, team)
	if kind == "peasant":
		_add_pick(visual)
	visual.scale = Vector3.ONE * float(def.scale)
	visual.name = "Visual"
	return visual


## Takes the "Visual" subtree out of one of the action game's enemy scenes,
## minus the named parts.
static func _extract_visual(model_path: String, hide: Array) -> Node3D:
	var scene: PackedScene = load(model_path)
	var instance := scene.instantiate()
	var visual := instance.get_node("Visual") as Node3D
	for node: Node in visual.find_children("*", "", true, false):
		node.owner = null
	visual.owner = null
	instance.remove_child(visual)
	instance.free()
	for part_name: String in hide:
		var part := visual.find_child(part_name, true, false)
		if part:
			part.get_parent().remove_child(part)
			part.free()
	return visual


## A hero: the action game's knight without sword and shield, in team colors,
## a gun in its right hand (a "Gun" node at the end of ArmR) and a plume.
static func hero_visual(team: int) -> Node3D:
	var key := "hero:%d" % team
	if not _templates.has(key):
		var visual := _extract_visual("res://enemy/enemy.tscn", ["Blade", "Guard", "Shield", "ShieldRim", "ShieldBoss"])
		_tint(visual, team)
		var arm := visual.find_child("ArmR", true, false) as Node3D
		var gun := Node3D.new()
		gun.name = "Gun"
		gun.position = Vector3(0, -0.68, 0)
		arm.add_child(gun)
		var metal := _standard("gunmetal", Color(0.15, 0.16, 0.18), 0.6)
		_box(gun, Vector3(0.09, 0.62, 0.11), Vector3(0, -0.22, -0.02), metal)
		_box(gun, Vector3(0.07, 0.08, 0.16), Vector3(0, 0.02, 0.08), metal)
		var crest := visual.find_child("Crest", true, false) as MeshInstance3D
		if crest:
			crest.material_override = _team_glow(team)
			crest.scale = Vector3(1.4, 1.6, 1.2)
		visual.name = "Visual"
		_templates[key] = visual
	return (_templates[key] as Node3D).duplicate() as Node3D


## A see-through dome over a shielded structure.
static func shield_dome(radius: float, color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.is_hemisphere = true
	var key := "dome:" + color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(color.r, color.g, color.b, 0.12)
		_materials[key] = material
	sphere.material = _materials[key]
	var instance := MeshInstance3D.new()
	instance.mesh = sphere
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _tint(root: Node, team: int) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		if mesh_instance.material_override is StandardMaterial3D:
			mesh_instance.material_override = _tinted_material(mesh_instance.material_override, team)
			continue
		for s in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_surface_override_material(s)
			if material == null:
				material = mesh_instance.mesh.surface_get_material(s)
			if material is StandardMaterial3D:
				mesh_instance.set_surface_override_material(s, _tinted_material(material, team))


## Strongly colored, unlit-by-itself materials take the team's hue.
static func _tinted_material(material: StandardMaterial3D, team: int) -> StandardMaterial3D:
	var key := "%d:%d" % [material.get_instance_id(), team]
	if _tinted.has(key):
		return _tinted[key]
	var result := material
	var c := material.albedo_color
	if c.s > 0.4 and c.v > 0.28 and not material.emission_enabled:
		result = material.duplicate() as StandardMaterial3D
		result.albedo_color = Color.from_hsv(RTSData.TEAM_HUES[team], clampf(c.s, 0.6, 0.9), clampf(c.v * 1.1, 0.4, 0.85), c.a)
	_tinted[key] = result
	return result


## A pickaxe in the peasant's sword hand.
static func _add_pick(visual: Node3D) -> void:
	var arm := visual.find_child("ArmR", true, false) as Node3D
	if arm == null:
		return
	var wood := _standard("wood", Color(0.45, 0.3, 0.16))
	var iron := _standard("iron", Color(0.55, 0.56, 0.6), 0.8)
	_box(arm, Vector3(0.06, 0.75, 0.06), Vector3(0, -0.95, 0), wood)
	_box(arm, Vector3(0.07, 0.07, 0.6), Vector3(0, -1.28, 0.05), iron)


# --- Structures ---------------------------------------------------------------

## Builds a structure's look, sized to its footprint (meters), origin at ground
## level in the middle.
static func structure_visual(kind: String, team: int, width: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	var team_mat := _team_material(team)
	var team_glow := _team_glow(team)
	var stone := _stone("stone", Color(0.55, 0.53, 0.5))
	var dark_stone := _stone("dark_stone", Color(0.36, 0.36, 0.38))
	var wood := _standard("wood", Color(0.45, 0.3, 0.16))
	var dark := _standard("dark", Color(0.08, 0.08, 0.09))
	var w := width - 0.6
	match kind:
		"keep":
			_box(root, Vector3(w, 0.6, w), Vector3(0, 0.3, 0), dark_stone)
			_box(root, Vector3(w - 1.2, 3.4, w - 1.2), Vector3(0, 2.0, 0), stone)
			_box(root, Vector3(w * 0.5, 3.0, w * 0.5), Vector3(0, 5.0, 0), stone)
			_cyl(root, 0.0, w * 0.36, 2.4, Vector3(0, 7.7, 0), team_mat, 4, PI * 0.25)
			for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var at := corner * (w * 0.5 - 0.7)
				_cyl(root, 0.85, 0.95, 5.6, Vector3(at.x, 2.8, at.y), stone, 8)
				_cyl(root, 0.0, 1.15, 1.8, Vector3(at.x, 6.5, at.y), team_mat, 8)
			_box(root, Vector3(1.8, 2.4, 0.2), Vector3(0, 1.2, w * 0.5 - 0.5), dark)
			_box(root, Vector3(1.6, 2.2, 0.08), Vector3(0, 4.4, w * 0.25 + 0.05), team_mat)
		"farm":
			_box(root, Vector3(w * 0.8, 1.8, w * 0.6), Vector3(0, 0.9, 0), wood)
			_roof(root, Vector3(w * 0.9, 1.1, w * 0.7), Vector3(0, 2.35, 0), team_mat)
			_cyl(root, 0.45, 0.45, 0.9, Vector3(w * 0.38, 0.45, w * 0.35), _standard("hay", Color(0.85, 0.72, 0.3)), 10)
			_box(root, Vector3(0.6, 1.1, 0.1), Vector3(0, 0.55, w * 0.3 + 0.01), dark)
		"barracks":
			_box(root, Vector3(w, 0.4, w), Vector3(0, 0.2, 0), dark_stone)
			_box(root, Vector3(w - 0.6, 2.8, w - 1.4), Vector3(0, 1.8, 0), stone)
			_roof(root, Vector3(w - 0.2, 1.6, w - 1.0), Vector3(0, 4.0, 0), team_mat)
			_box(root, Vector3(1.6, 2.0, 0.2), Vector3(0, 1.4, w * 0.5 - 0.6), dark)
			for x: float in [-w * 0.32, w * 0.32]:
				_cyl(root, 0.1, 0.1, 1.8, Vector3(x, 0.9, w * 0.5 - 0.1), wood, 6)
				_box(root, Vector3(0.6, 0.12, 0.12), Vector3(x, 1.4, w * 0.5 - 0.1), wood)
			_box(root, Vector3(0.08, 1.4, 0.9), Vector3(w * 0.5 - 0.25, 2.3, 0), team_mat)
		"extractor":
			_cyl(root, w * 0.5, w * 0.55, 1.2, Vector3(0, 0.6, 0), dark_stone, 10)
			_cyl(root, w * 0.32, w * 0.4, 1.6, Vector3(0, 2.0, 0), stone, 10)
			_cyl(root, w * 0.22, w * 0.22, 0.3, Vector3(0, 2.9, 0), _glow("aether", Color(0.3, 1.0, 0.4)), 10)
			_cyl(root, 0.15, 0.15, 2.2, Vector3(w * 0.38, 1.6, 0), _standard("iron", Color(0.55, 0.56, 0.6), 0.8), 6)
			_box(root, Vector3(0.1, 0.8, 0.6), Vector3(-w * 0.5 - 0.02, 0.8, 0), team_mat)
		"watchtower", "tower":
			if kind == "tower":
				_box(root, Vector3(w, 1.0, w), Vector3(0, 0.5, 0), dark_stone)
				_cyl(root, 0.0, 0.5, 1.2, Vector3(0, 9.4, 0), team_glow, 6)
			_box(root, Vector3(w * 0.8, 6.0, w * 0.8), Vector3(0, 3.0, 0), stone)
			_box(root, Vector3(w, 0.3, w), Vector3(0, 6.1, 0), dark_stone)
			for side in 4:
				var b := Basis(Vector3.UP, side * PI * 0.5)
				var parapet := _box(root, Vector3(w, 0.8, 0.2), b * Vector3(0, 6.6, w * 0.5 - 0.1), stone)
				parapet.basis = b
			_cyl(root, 0.0, w * 0.55, 1.6, Vector3(0, 8.0, 0), team_mat, 4, PI * 0.25)
			_box(root, Vector3(0.12, 1.2, 0.7), Vector3(w * 0.4 + 0.07, 4.2, 0), team_mat)
		"forge":
			_box(root, Vector3(w, 0.4, w), Vector3(0, 0.2, 0), dark_stone)
			_box(root, Vector3(w - 0.6, 2.6, w - 0.6), Vector3(0, 1.7, 0), dark_stone)
			_box(root, Vector3(w - 0.2, 0.3, w - 0.2), Vector3(0, 3.1, 0), team_mat)
			_cyl(root, 0.55, 0.7, 3.0, Vector3(w * 0.25, 4.5, -w * 0.2), stone, 8)
			_box(root, Vector3(1.6, 1.2, 0.2), Vector3(0, 1.0, w * 0.5 - 0.25), _glow("furnace", Color(1.0, 0.45, 0.1)))
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.55, 0.2)
			light.light_energy = 1.5
			light.omni_range = 4.0
			light.position = Vector3(0, 1.2, w * 0.5 + 0.6)
			root.add_child(light)
		"aerie":
			_cyl(root, w * 0.42, w * 0.48, 0.6, Vector3(0, 0.3, 0), dark_stone, 10)
			_cyl(root, 1.1, 1.5, 5.4, Vector3(0, 3.0, 0), stone, 10)
			_cyl(root, w * 0.48, w * 0.4, 0.4, Vector3(0, 5.9, 0), dark_stone, 12)
			_cyl(root, 0.0, 1.4, 1.8, Vector3(0, 7.0, 0), team_mat, 10)
			for side in 3:
				var angle := side * TAU / 3.0
				var at := Vector3(cos(angle), 0, sin(angle)) * (w * 0.42)
				_cyl(root, 0.15, 0.2, 5.6, at + Vector3(0, 2.8, 0), wood, 6)
				var banner := _box(root, Vector3(0.08, 1.0, 0.7), at + Vector3(0, 4.6, 0), team_mat)
				banner.rotation.y = -angle
		"sanctum":
			_box(root, Vector3(w, 0.8, w), Vector3(0, 0.4, 0), stone)
			_box(root, Vector3(w * 0.72, 0.8, w * 0.72), Vector3(0, 1.2, 0), stone)
			_box(root, Vector3(w * 0.45, 0.8, w * 0.45), Vector3(0, 2.0, 0), stone)
			for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var at := corner * (w * 0.5 - 0.35)
				_box(root, Vector3(0.5, 3.0, 0.5), Vector3(at.x, 1.5, at.y), dark_stone)
			var crystal := Node3D.new()
			crystal.name = "Spin"
			crystal.position = Vector3(0, 4.4, 0)
			root.add_child(crystal)
			_cyl(crystal, 0.0, 0.8, 1.4, Vector3(0, 0.7, 0), team_glow, 4)
			_cyl(crystal, 0.8, 0.0, 1.4, Vector3(0, -0.7, 0), team_glow, 4)
	return root


## A see-through box the size of a footprint, for placing structures.
static func ghost(width: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width - 0.2, 2.0, width - 0.2)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.3, 1.0, 0.4, 0.35)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Flat ring for selections and command markers (always drawn on top).
static func ring(radius: float, color: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + maxf(0.08, radius * 0.1)
	torus.rings = 32
	torus.ring_segments = 4
	var key := "ring:" + color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color
		material.render_priority = 1
		_materials[key] = material
	torus.material = _materials[key]
	var instance := MeshInstance3D.new()
	instance.mesh = torus
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.scale = Vector3(1.0, 0.2, 1.0)
	return instance


## Something carried by a peasant: a crystal shard or an aether orb.
static func cargo(kind: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if kind == "crystal":
		var prism := CylinderMesh.new()
		prism.top_radius = 0.02
		prism.bottom_radius = 0.18
		prism.height = 0.5
		prism.radial_segments = 5
		instance.mesh = prism
		instance.material_override = _glow("crystal", Color(0.35, 0.75, 1.0))
	else:
		var orb := SphereMesh.new()
		orb.radius = 0.18
		orb.height = 0.36
		instance.mesh = orb
		instance.material_override = _glow("aether", Color(0.3, 1.0, 0.4))
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# --- Helpers ------------------------------------------------------------------

static func _box(parent: Node3D, box_size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


## A gable roof: ridge along Z, sloping down to the sides.
static func _roof(parent: Node3D, roof_size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = roof_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


static func _cyl(parent: Node3D, top: float, bottom: float, height: float, at: Vector3, material: Material,
		segments := 12, yaw := 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation.y = yaw
	parent.add_child(instance)
	return instance


static func _stone(key: String, color: Color) -> ShaderMaterial:
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = GRID_SHADER
		material.set_shader_parameter(&"color_a", color)
		material.set_shader_parameter(&"color_b", color.darkened(0.06))
		material.set_shader_parameter(&"cell_size", 0.75)
		_materials[key] = material
	return _materials[key]


static func _standard(key: String, color: Color, metallic := 0.0) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metallic
		material.roughness = 0.8
		_materials[key] = material
	return _materials[key]


static func _glow(key: String, color: Color) -> StandardMaterial3D:
	key = "glow:" + key
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.5
		_materials[key] = material
	return _materials[key]


static func _team_material(team: int) -> StandardMaterial3D:
	var key := "team:%d" % team
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = RTSData.TEAM_COLORS[team].darkened(0.15)
		material.roughness = 0.7
		_materials[key] = material
	return _materials[key]


static func _team_glow(team: int) -> StandardMaterial3D:
	return _glow("team%d" % team, RTSData.TEAM_COLORS[team])
