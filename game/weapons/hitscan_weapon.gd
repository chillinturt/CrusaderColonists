class_name HitscanWeapon
extends HeroWeapon
## Hitscan guns: the rifle, shotgun, sniper and revolver are all this with
## different numbers. Fires rays from the hero's eyes toward the crosshair
## inside a spread cone, through teammates but not walls, and draws tracers
## from the gun. Loses damage at range, gets less accurate with sustained fire,
## while moving (if moving_spread is set) and while airborne. Shots at a hero's
## head deal the weapon's headshot multiplier.

const TRACER_COLOR := Color(1.0, 0.85, 0.4)

static var _tracer_material: StandardMaterial3D

var _bloom := 0.0
var _since_shot := 0.0
var _trigger_released := true


func unequip() -> void:
	super()
	_bloom = 0.0


func _fire_tick(delta: float) -> void:
	_since_shot += delta
	if _since_shot > 0.25:
		_bloom = maxf(_bloom - float(def.get("bloom_recovery", 6.0)) * delta, 0.0)
	var trigger := hero.intent.fire
	if trigger and can_attack() and (def.get("automatic", true) or _trigger_released) and _use_round():
		cooldown = 1.0 / (float(def.fire_rate) * hero.upgrades.fire_rate_multiplier())
		_since_shot = 0.0
		_fire()
	_trigger_released = not trigger


func spread_degrees() -> float:
	var spread: float = def.get("base_spread", 0.0) + _bloom
	if not hero.is_on_floor():
		spread += def.get("airborne_spread", 0.0)
	var speed := Vector2(hero.velocity.x, hero.velocity.z).length()
	spread += float(def.get("moving_spread", 0.0)) * clampf(speed / 8.0, 0.0, 1.5)
	return spread


func _fire() -> void:
	var from := hero.aim_origin()
	var aim := hero.aim_basis()
	var cone := deg_to_rad(spread_degrees())
	var space := hero.get_world_3d().direct_space_state
	var reach: float = def.get("range", 250.0)
	var exclude: Array[RID] = [hero.get_rid()]
	var hit_any := false
	var headshot := false
	for dir in _pellet_directions(aim, cone):
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, Combat.shot_mask(hero.team), exclude)
		var result := space.intersect_ray(query)
		var end := from + dir * reach
		if result:
			end = result.position
			var target := Combat.resolve(result.collider)
			if target:
				var falloff := remap(from.distance_to(end), def.falloff_start, def.falloff_end, 1.0, def.falloff_min)
				var amount: float = def.damage * clampf(falloff, def.falloff_min, 1.0) * hero.damage_multiplier()
				if target is Hero and end.y > (target as Hero).global_position.y + Hero.HEAD_HEIGHT:
					amount *= def.get("headshot", 1.25)
					headshot = true
				if Combat.deal(target, amount, hero, from):
					hit_any = true
			_spawn_effect(_make_impact(end), 0.08)
		_spawn_effect(_make_tracer(hero.muzzle_position(), end), 0.05)
	if hit_any:
		hero.on_hit_landed(headshot)
	_bloom = minf(_bloom + float(def.get("spread_per_shot", 0.0)), float(def.get("max_bloom", 0.0)))
	hero.on_fired(0.12 if def.damage > 40.0 else 0.05)


## One direction per pellet: a fixed grid across the cone, or random scatter.
func _pellet_directions(aim: Basis, cone: float) -> Array[Vector3]:
	var forward := -aim.z
	var directions: Array[Vector3] = []
	var grid: Vector2i = def.get("pellet_grid", Vector2i.ZERO)
	if grid.x > 0 and grid.y > 0:
		var reach := tan(cone)
		for row in grid.y:
			for column in grid.x:
				var u := 2.0 * column / maxf(grid.x - 1, 1) - 1.0 if grid.x > 1 else 0.0
				var v := 2.0 * row / maxf(grid.y - 1, 1) - 1.0 if grid.y > 1 else 0.0
				directions.append((forward + aim.x * u * reach + aim.y * v * reach).normalized())
	else:
		for pellet in int(def.get("pellets", 1)):
			directions.append(_random_in_cone(forward, aim, cone))
	return directions


## Uniform random direction within half-angle `angle` of `forward`.
static func _random_in_cone(forward: Vector3, aim: Basis, angle: float) -> Vector3:
	if angle <= 0.0:
		return forward
	var r := tan(angle) * sqrt(randf())
	var theta := randf() * TAU
	return (forward + aim.x * r * cos(theta) + aim.y * r * sin(theta)).normalized()


static func _material() -> StandardMaterial3D:
	if _tracer_material == null:
		_tracer_material = StandardMaterial3D.new()
		_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_material.albedo_color = TRACER_COLOR
	return _tracer_material


func _make_tracer(a: Vector3, b: Vector3) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material())
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_end()
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


func _make_impact(at: Vector3) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	var inst := MeshInstance3D.new()
	inst.mesh = sphere
	inst.material_override = _material()
	inst.position = at
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst
