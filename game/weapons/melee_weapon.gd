class_name MeleeWeapon
extends HeroWeapon
## A melee swing, as in the action game:
##   windup    the weapon is drawn back to where its arc starts
##   active    it sweeps the arc: a fan of thick hit rays follows it across, so
##             everyone the arc passes through is hit (once per swing)
##   recovery  it comes back to rest
## Walls stop the rays (and a structure in the way takes the hit). Damage grows
## with how fast you're moving: swing in off a grapple or a bhop chain. The
## sledgehammer's swing ends in a ground slam that hurts and launches enemies
## around the spot and bounces you up.

const RAYS := 14

enum Phase { IDLE, WINDUP, ACTIVE, RECOVER }

var phase := Phase.IDLE
var _time := 0.0
var _arc := Vector4.ZERO
var _next_arc := 0
var _rays_done := 0
var _hit := {}
var _hit_any := false


func unequip() -> void:
	super()
	phase = Phase.IDLE


## 0..1 through the swing (windup 0-0.3, arc 0.3-0.6, recovery 0.6-1), or -1.
func swing_progress() -> float:
	match phase:
		Phase.WINDUP:
			return 0.3 * _time / float(def.windup)
		Phase.ACTIVE:
			return 0.3 + 0.3 * _time / float(def.active)
		Phase.RECOVER:
			return 0.6 + 0.4 * _time / float(def.recovery)
	return -1.0


func current_arc() -> Vector4:
	return _arc


func _fire_tick(delta: float) -> void:
	if phase == Phase.IDLE:
		if hero.intent.fire and can_attack():
			_begin_swing()
		return
	_time += delta
	match phase:
		Phase.WINDUP:
			if _time >= float(def.windup):
				phase = Phase.ACTIVE
				_time = 0.0
		Phase.ACTIVE:
			var t := minf(_time / float(def.active), 1.0)
			while _rays_done < RAYS and float(_rays_done) / (RAYS - 1) <= t:
				_cast_ray(_direction(float(_rays_done) / (RAYS - 1)))
				_rays_done += 1
			if t >= 1.0:
				if def.get("slam_radius", 0.0) > 0.0:
					_slam()
				if _hit_any:
					hero.on_hit_landed(false)
				phase = Phase.RECOVER
				_time = 0.0
		Phase.RECOVER:
			if _time >= float(def.recovery):
				phase = Phase.IDLE


func _begin_swing() -> void:
	var arcs: Array = def.arcs
	_arc = arcs[_next_arc % arcs.size()]
	_next_arc += 1
	phase = Phase.WINDUP
	_time = 0.0
	_rays_done = 0
	_hit.clear()
	_hit_any = false
	cooldown = float(def.windup) + float(def.active) + float(def.recovery)


## World direction of the hit ray at a point along the arc (0 = start, 1 = end).
func _direction(along: float) -> Vector3:
	var angles := Vector2(_arc.x, _arc.y).lerp(Vector2(_arc.z, _arc.w), along)
	var local := Basis.from_euler(Vector3(deg_to_rad(angles.y), deg_to_rad(-angles.x), 0.0)) * Vector3.FORWARD
	return (hero.aim_basis() * local).normalized()


func _cast_ray(direction: Vector3) -> void:
	var space := hero.get_world_3d().direct_space_state
	var from := hero.aim_origin()
	var reach: float = def.reach
	var length := reach
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * reach, Combat.WORLD))
	if wall:
		length = from.distance_to(wall.position)
		_strike(Combat.resolve(wall.collider), wall.position)
	if length < 0.05:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(def.thickness, float(def.thickness) + 0.8, length)
	var up := Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = box
	params.transform = Transform3D(Basis.looking_at(direction, up), from + direction * length * 0.5)
	params.collision_mask = Combat.enemy_bodies(hero.team)
	for result in space.intersect_shape(params, 8):
		var body := result.collider as Node3D
		_strike(Combat.resolve(body), body.global_position + Vector3.UP)


func _strike(target: Object, at: Vector3) -> void:
	if target == null or _hit.has(target):
		return
	_hit[target] = true
	var amount: float = def.damage * hero.damage_multiplier()
	amount *= 1.0 + float(def.get("speed_bonus", 0.05)) * maxf(hero.velocity.length() - 8.0, 0.0)
	if Combat.deal(target, amount, hero, hero.aim_origin()):
		_hit_any = true
		if target is Hero:
			var forward := -hero.aim_basis().z
			var push: float = def.get("push", 3.0)
			(target as Hero).push(Vector3(forward.x, 0.0, forward.z).normalized() * push + Vector3.UP * push * 0.4)
	elif target is Hero:
		_hit.erase(target)  # a teammate: doesn't use up the swing


## Where the swing ends on the ground: hurts and launches enemies around the
## spot (ones the swing itself hit are only launched) and bounces you up.
func _slam() -> void:
	var from := hero.aim_origin()
	var query := PhysicsRayQueryParameters3D.create(from, from + _direction(1.0) * (float(def.reach) + 0.8), Combat.WORLD)
	var ground := hero.get_world_3d().direct_space_state.intersect_ray(query)
	if not ground:
		return
	var center: Vector3 = ground.position
	var slam_radius: float = def.slam_radius
	var power: float = def.damage * float(def.slam_damage) * hero.damage_multiplier()
	var sphere := SphereShape3D.new()
	sphere.radius = slam_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = Combat.enemy_bodies(hero.team)
	for result in hero.get_world_3d().direct_space_state.intersect_shape(params, 16):
		var body := result.collider as Node3D
		var target := Combat.resolve(body)
		if target == null:
			continue
		var offset := body.global_position + Vector3.UP * 0.5 - center
		var falloff := 1.0 - 0.6 * clampf(offset.length() / slam_radius, 0.0, 1.0)
		if not _hit.has(target):
			_hit[target] = true
			if Combat.deal(target, power * falloff, hero, center):
				_hit_any = true
		if target is Hero:
			var away := Vector3(offset.x, 0.0, offset.z).normalized()
			(target as Hero).push((away * 0.6 + Vector3.UP) * float(def.slam_force) * falloff)
	hero.velocity.y = maxf(hero.velocity.y, float(def.slam_hop))
	Explosion.spawn_fx(hero.get_parent(), center + Vector3.UP * 0.2, slam_radius * 0.5)
