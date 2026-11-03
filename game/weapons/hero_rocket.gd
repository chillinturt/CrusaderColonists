class_name HeroRocket
extends Node3D
## A rocket in flight. Looks like the action game's rocket (its scene, with the
## script taken off). Moves by raycasting each tick so it can't tunnel; flies
## through the shooter's teammates; explodes on the first wall or enemy.

const LOOK := preload("res://combat/rocket.tscn")
const LIFETIME := 6.0

var velocity := Vector3.ZERO
var shooter: Hero
var team := 0
var damage := 85.0
var radius := 4.0
var force := 13.0
var self_damage := 0.4
var _life := LIFETIME


func launch(from: Vector3, direction: Vector3, p_shooter: Hero, def: Dictionary, multiplier: float) -> void:
	shooter = p_shooter
	team = shooter.team
	damage = float(def.damage) * multiplier
	radius = def.get("radius", 4.0)
	force = def.get("force", 13.0)
	self_damage = def.get("self_damage", 0.4)
	velocity = direction.normalized() * float(def.get("speed", 30.0))
	var look := LOOK.instantiate() as Node3D
	look.set_script(null)
	add_child(look)
	global_position = from
	_orient()
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	var next := global_position + velocity * delta
	var exclude: Array[RID] = []
	if is_instance_valid(shooter):
		exclude.append(shooter.get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position, next, Combat.shot_mask(team), exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		var instigator: Hero = shooter if is_instance_valid(shooter) else null
		Combat.explode(self, hit.position - velocity.normalized() * 0.2, radius, damage, force, instigator, team, self_damage)
		queue_free()
	else:
		global_position = next


func _orient() -> void:
	if velocity.length_squared() > 0.01 and absf(velocity.normalized().dot(Vector3.UP)) < 0.99:
		look_at(global_position + velocity, Vector3.UP)
