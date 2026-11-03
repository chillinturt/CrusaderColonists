class_name RTSCamera
extends Camera3D
## Top-down battlefield camera for the Command View: pans with the arrow keys,
## the screen edges or a middle-mouse drag, zooms with the wheel, and looks down
## at a fixed angle. Idle while you're playing your hero.

const PITCH := deg_to_rad(56.0)
const MIN_DISTANCE := 15.0
const MAX_DISTANCE := 80.0
const PAN_SPEED := 40.0
const EDGE := 6.0

var game: RTSGame
## Ground point the camera looks at.
var focus := Vector3.ZERO
var distance := 38.0

var _target_distance := 38.0
var _dragging := false


func setup(p_game: RTSGame) -> void:
	game = p_game
	fov = 45.0
	far = 700.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # placed every frame


func focus_on(pos: Vector3) -> void:
	focus = game.map.clamp_to_play_area(pos, 0.0)
	focus.y = game.map.height_at(focus.x, focus.z)
	_place()


## Whether a world point is on screen.
func sees(pos: Vector3) -> bool:
	if is_position_behind(pos):
		return false
	var screen := unproject_position(pos)
	return get_viewport().get_visible_rect().has_point(screen)


## The ground under a screen point (INF if it's sky).
func ground_at(screen_pos: Vector2) -> Vector3:
	return game.map.ray_ground(project_ray_origin(screen_pos), project_ray_normal(screen_pos))


func _process(delta: float) -> void:
	if game.view_mode != "command":
		return
	var pan := Vector2.ZERO
	if not game.hud.is_menu_open():
		if Input.is_key_pressed(KEY_LEFT):
			pan.x -= 1.0
		if Input.is_key_pressed(KEY_RIGHT):
			pan.x += 1.0
		if Input.is_key_pressed(KEY_UP):
			pan.y -= 1.0
		if Input.is_key_pressed(KEY_DOWN):
			pan.y += 1.0
		if DisplayServer.window_is_focused() and not _dragging:
			var mouse := get_viewport().get_mouse_position()
			var view := get_viewport().get_visible_rect().size
			if mouse.x >= 0.0 and mouse.y >= 0.0 and mouse.x <= view.x and mouse.y <= view.y:
				if mouse.x < EDGE:
					pan.x -= 1.0
				elif mouse.x > view.x - EDGE:
					pan.x += 1.0
				if mouse.y < EDGE:
					pan.y -= 1.0
				elif mouse.y > view.y - EDGE:
					pan.y += 1.0
	if pan != Vector2.ZERO:
		var speed := PAN_SPEED * (distance / 46.0)
		focus += Vector3(pan.x, 0.0, pan.y).normalized() * speed * delta
	distance = lerpf(distance, _target_distance, minf(1.0, 10.0 * delta))
	focus = game.map.clamp_to_play_area(focus, 0.0)
	focus.y = lerpf(focus.y, game.map.height_at(focus.x, focus.z), minf(1.0, 4.0 * delta))
	_place()


func _place() -> void:
	global_position = focus + Vector3(0.0, sin(PITCH), cos(PITCH)) * distance
	look_at(focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if game.view_mode != "command":
		return
	var button := event as InputEventMouseButton
	if button:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_target_distance = clampf(_target_distance * 0.88, MIN_DISTANCE, MAX_DISTANCE)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_target_distance = clampf(_target_distance * 1.12, MIN_DISTANCE, MAX_DISTANCE)
		elif button.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = button.pressed
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		var meters_per_pixel := distance * 0.0016
		focus -= Vector3(motion.relative.x, 0.0, motion.relative.y) * meters_per_pixel
