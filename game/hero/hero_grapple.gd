class_name HeroGrapple
extends RefCounted
## Every hero's grappling hook, as in the action game:
##   hook (RMB)   fire at whatever the crosshair is on (terrain, trees, rocks,
##                structures, enemy units and heroes); hold to stay attached.
##                The rope holds its length, so you swing on it like a pendulum
##                (slack is taken up as you get closer). Let go to keep your momentum.
##   reel in (F)  the rope shortens and hauls you toward the hook
##   reel out (C) the rope lengthens, to drop down or widen a swing
##   gas (Shift)  while hooked, thrusts toward the hook, steerable with your aim
## Hooks in moving things move with them. A hook in an enemy is shaken loose
## after LIVE_HOLD_TIME.

const MAX_RANGE := 45.0
const REEL_IN_SPEED := 14.0
const REEL_OUT_SPEED := 10.0
const GAS_ACCELERATION := 30.0
const LIVE_HOLD_TIME := 2.0

var hero: Hero
var hooked := false
var _anchor_body: Node3D
var _anchor_local := Vector3.ZERO
var _rope_length := 0.0
var _hold_left := 0.0
var _rope_mesh := ImmediateMesh.new()
var _rope: MeshInstance3D


func _init(p_hero: Hero) -> void:
	hero = p_hero
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 0.15, 0.15)
	_rope = MeshInstance3D.new()
	_rope.mesh = _rope_mesh
	_rope.material_override = material
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.top_level = true  # vertices are in world space
	hero.add_child(_rope)


func fire() -> void:
	var from := hero.aim_origin()
	var exclude: Array[RID] = [hero.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(from, from - hero.aim_basis().z * MAX_RANGE,
			Combat.shot_mask(hero.team), exclude)
	var hit := hero.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit:
		return
	_anchor_body = hit.collider
	_anchor_local = _anchor_body.to_local(hit.position)
	hooked = true
	_hold_left = LIVE_HOLD_TIME
	_rope_length = _origin().distance_to(hit.position)
	if hero.is_on_floor():
		hero.velocity.y = maxf(hero.velocity.y, 4.0)  # pop off the ground so the swing can start


func detach() -> void:
	hooked = false
	_anchor_body = null
	_rope_mesh.clear_surfaces()


func anchor() -> Vector3:
	return _anchor_body.to_global(_anchor_local)


## Called by the hero every tick before move_and_slide(). `thrusting` is whether
## gas is burning this tick; true if the hook used that thrust.
func apply(delta: float, thrusting: bool) -> bool:
	if hooked and (not hero.intent.hook or not is_instance_valid(_anchor_body) or not _anchor_body.is_inside_tree()):
		detach()
	if not hooked:
		return false

	var to_anchor := anchor() - _origin()
	var dist := to_anchor.length()
	var dir := to_anchor / maxf(dist, 0.01)
	if thrusting:
		var aim := -hero.aim_basis().z
		hero.velocity += (dir * 0.7 + aim * 0.3).normalized() * GAS_ACCELERATION * delta

	if hero.intent.reel_in:
		_rope_length = maxf(_rope_length - REEL_IN_SPEED * delta, 1.5)
	elif hero.intent.reel_out:
		_rope_length = minf(_rope_length + REEL_OUT_SPEED * delta, MAX_RANGE)
	else:
		_rope_length = minf(_rope_length, dist)

	# Taut rope: you can't move away from the anchor, and if it's shorter than
	# the gap (reeling in) you're hauled along it at the reel speed.
	if dist >= _rope_length - 0.05:
		var toward := hero.velocity.dot(dir)
		var needed := minf((dist - _rope_length) / delta, REEL_IN_SPEED) if dist > _rope_length else 0.0
		if toward < needed:
			hero.velocity += dir * (needed - toward)
	if _anchor_body is Hero or _anchor_body is Hitbox and not (_anchor_body as Hitbox).entity.is_structure:
		_hold_left -= delta
		if _hold_left <= 0.0:
			detach()
			return thrusting
	elif dist < 1.5:
		detach()  # arrived
		return thrusting
	_draw_rope()
	return thrusting


## Where the rope leaves the hero: the gun hand.
func _origin() -> Vector3:
	return hero.global_position + hero.global_basis * Vector3(0.35, 1.35, -0.3)


func _draw_rope() -> void:
	_rope_mesh.clear_surfaces()
	_rope_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_rope_mesh.surface_add_vertex(_origin())
	_rope_mesh.surface_add_vertex(anchor())
	_rope_mesh.surface_end()
