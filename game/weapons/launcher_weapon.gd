class_name LauncherWeapon
extends HeroWeapon
## Weapons that throw something: the rocket launcher (rockets fly straight at
## whatever the crosshair is on) and grenades (bouncing, on a fuse, carrying
## your momentum). Hold to keep firing.


func _fire_tick(_delta: float) -> void:
	if not (hero.intent.fire and can_attack() and _use_round()):
		return
	if def.type == "rocket":
		cooldown = float(def.fire_interval) / hero.upgrades.fire_rate_multiplier()
		_fire_rocket()
	else:
		cooldown = float(def.throw_interval) / hero.upgrades.fire_rate_multiplier()
		_throw_grenade()


func _fire_rocket() -> void:
	var from := hero.aim_origin()
	var forward := -hero.aim_basis().z
	var exclude: Array[RID] = [hero.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * 500.0, Combat.shot_mask(hero.team), exclude)
	var hit := hero.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = hit.position if hit else from + forward * 500.0
	# Very close targets (rocket jumps): fire from the eyes so it can't start past the floor.
	var start := hero.muzzle_position() if from.distance_to(target) > 3.0 else from
	var rocket := HeroRocket.new()
	hero.get_parent().add_child(rocket)
	rocket.launch(start, target - start, hero, def, hero.damage_multiplier())
	hero.on_fired(0.15)


func _throw_grenade() -> void:
	var grenade := HeroGrenade.new()
	grenade.setup(hero, def, hero.damage_multiplier())
	hero.get_parent().add_child(grenade)
	var aim := hero.aim_basis()
	grenade.global_position = hero.aim_origin() + aim * Vector3(0.3, -0.1, -0.6)
	grenade.reset_physics_interpolation()
	grenade.linear_velocity = -aim.z * float(def.throw_speed) + Vector3.UP * float(def.throw_lift) + hero.velocity
	grenade.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
	grenade.add_collision_exception_with(hero)
	hero.on_fired(0.08)
