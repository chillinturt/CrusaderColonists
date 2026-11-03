class_name HeroGrenade
extends RigidBody3D
## A bouncing grenade. Bounces off the world and enemy heroes, explodes when
## its fuse runs out (walls block the blast; one at your feet is a grenade jump).

var thrower: Hero
var team := 0
var damage := 90.0
var radius := 6.0
var force := 14.0
var self_damage := 0.35
var fuse := 2.5


func setup(p_thrower: Hero, def: Dictionary, multiplier: float) -> void:
	thrower = p_thrower
	team = thrower.team
	damage = float(def.damage) * multiplier
	radius = def.get("radius", 6.0)
	force = def.get("force", 14.0)
	self_damage = def.get("self_damage", 0.35)
	fuse = def.get("fuse", 2.5)
	collision_layer = 0
	collision_mask = Combat.WORLD | Combat.HERO_LAYERS[1 - team]
	mass = 0.4
	continuous_cd = true
	linear_damp = 0.3
	angular_damp = 2.0
	var bounce := PhysicsMaterial.new()
	bounce.friction = 0.8
	bounce.bounce = 0.35
	physics_material_override = bounce
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	shape.shape = sphere
	add_child(shape)
	var ball := SphereMesh.new()
	ball.radius = 0.12
	ball.height = 0.24
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.25, 0.32, 0.18)
	ball.material = body_material
	var mesh := MeshInstance3D.new()
	mesh.mesh = ball
	add_child(mesh)
	var band := BoxMesh.new()
	band.size = Vector3(0.26, 0.05, 0.26)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = RTSData.TEAM_COLORS[team]
	glow.emission_enabled = true
	glow.emission = RTSData.TEAM_COLORS[team]
	glow.emission_energy_multiplier = 3.0
	band.material = glow
	var band_mesh := MeshInstance3D.new()
	band_mesh.mesh = band
	add_child(band_mesh)


func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse > 0.0:
		return
	var instigator: Hero = thrower if is_instance_valid(thrower) else null
	var exclude: Array[RID] = [get_rid()]
	Combat.explode(self, global_position + Vector3.UP * 0.2, radius, damage, force, instigator, team, self_damage, exclude)
	queue_free()
