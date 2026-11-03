class_name HeroCamera
extends Node3D
## Over-the-shoulder third-person camera for the hero you play. Orbits with
## the hero's yaw and pitch, sits above the right shoulder, and pulls in when
## a wall or the ground gets between it and the hero. The crosshair is the
## middle of this camera's view: HeroInput turns that into the hero's aim point.

const PIVOT_HEIGHT := 1.7
## Right, up, back from the pivot.
const OFFSET := Vector3(0.75, 0.3, 3.6)
const FOV := 80.0

var hero: Hero
var camera: Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # placed every frame
	camera = Camera3D.new()
	camera.fov = FOV
	camera.far = 800.0
	add_child(camera)


func _process(_delta: float) -> void:
	var pivot := hero.get_global_transform_interpolated().origin + Vector3.UP * PIVOT_HEIGHT
	var view := Basis.from_euler(Vector3(hero.intent.pitch, hero.intent.yaw, 0.0))
	var desired := pivot + view * OFFSET
	var exclude: Array[RID] = [hero.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(pivot, desired, Combat.WORLD, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		desired = hit.position + (pivot - desired).normalized() * 0.3
	global_transform = Transform3D(view, desired)


## Where the crosshair points: the first thing past the hero along the middle
## of the view, or far away.
func aim_point() -> Vector3:
	var from := camera.global_position
	var forward := -camera.global_basis.z
	# Start level with the hero, so nothing behind them is picked.
	var skip := maxf((hero.global_position + Vector3.UP * PIVOT_HEIGHT - from).dot(forward), 0.0)
	var exclude: Array[RID] = [hero.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(from + forward * skip, from + forward * 400.0,
			Combat.shot_mask(hero.team), exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit else from + forward * 400.0
