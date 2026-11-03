class_name RTSMinimap
extends Control
## The whole battlefield from above (north up): terrain under the fog, crystal
## and vents, both sides' forces (enemies only where you can see them, their
## structures once found), alert pings, and the camera's view.
## Left click / drag moves the camera; right click orders the selection there.

var game: RTSGame

var _dragging := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


func to_map(world: Vector3) -> Vector2:
	var r := game.map.play_radius
	return Vector2((world.x + r) / (2.0 * r) * size.x, (world.z + r) / (2.0 * r) * size.y)


func to_world(local: Vector2) -> Vector3:
	var r := game.map.play_radius
	var x := local.x / size.x * 2.0 * r - r
	var z := local.y / size.y * 2.0 * r - r
	return Vector3(x, game.map.height_at(x, z), z)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if button.pressed:
				game.camera.focus_on(to_world(button.position))
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			game.controller.smart_command(null, to_world(button.position), button.shift_pressed)
		accept_event()
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		game.camera.focus_on(to_world(motion.position))
		accept_event()


func _draw() -> void:
	if game == null or game.map == null:
		return
	var map := game.map
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.03, 0.03, 0.04))
	var first := (map.size * 0.5 - map.play_radius) / map.cell
	var span := 2.0 * map.play_radius / map.cell
	var source := Rect2(first, first, span, span)
	draw_texture_rect_region(map.map_texture, rect, source)
	draw_texture_rect_region(game.fog.overlay_texture, rect, source)

	var px := size.x / (2.0 * map.play_radius)
	for resource in map.resources:
		if not is_instance_valid(resource) or resource.dead or not game.fog.is_explored(resource.global_position):
			continue
		var color := Color(0.4, 0.8, 1.0) if resource.kind == "crystal" else Color(0.35, 1.0, 0.45)
		draw_rect(Rect2(to_map(resource.global_position) - Vector2(1.5, 1.5), Vector2(3, 3)), color)

	for entity in game.entities:
		if entity.dead or not entity.visible:
			continue
		var color := RTSData.TEAM_COLORS[entity.team]
		if entity.selected:
			color = Color.WHITE
		var at := to_map(entity.global_position)
		if entity.is_structure:
			var half := maxf(entity.radius * px, 2.5)
			draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), color)
			draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), Color(0, 0, 0, 0.6), false, 1.0)
		else:
			draw_circle(at, maxf(entity.radius * px * 1.5, 1.8), color)

	for ping: Array in game.pings:
		var t: float = ping[1]
		var at := to_map(ping[0])
		draw_arc(at, 4.0 + (3.0 - t) * 6.0, 0.0, TAU, 20, Color(1.0, 0.2, 0.15, clampf(t, 0.0, 1.0)), 2.0)

	_draw_view()
	draw_rect(rect, Color(1, 1, 1, 0.35), false, 1.0)


## The camera's footprint on the ground.
func _draw_view() -> void:
	var camera := game.camera
	var view := camera.get_viewport().get_visible_rect().size
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(0, 0), Vector2(view.x, 0), Vector2(view.x, view.y), Vector2(0, view.y)]:
		var origin := camera.project_ray_origin(corner)
		var normal := camera.project_ray_normal(corner)
		var hit := Vector3.INF
		if normal.y < -0.01:
			var t := (camera.focus.y - origin.y) / normal.y
			hit = origin + normal * t
		else:
			hit = origin + normal * 300.0
		points.append(to_map(hit))
	points.append(points[0])
	draw_polyline(points, Color(1, 1, 1, 0.85), 1.0)
