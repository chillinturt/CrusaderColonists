class_name RTSController
extends Node
## Your hands on the battlefield (StarCraft-style controls):
##   left click / drag       select (shift adds, ctrl or double-click: all of that kind on screen)
##   right click             smart command: move, attack, gather, return cargo, or set a rally point
##   A / M / P / G + click   attack-move (or attack a unit), move, patrol, gather
##   S / H                   stop, hold position
##   B                       a peasant's build menu, then the structure's key, then click to place
##   structure keys          train units (see each button); R sets a rally point; X cancels
##   shift + any order       queue it after the current ones
##   ctrl + 1-0 / 1-0        set / recall a control group (press twice to jump the camera there)
##   F1 / F2                 next idle peasant / your whole army
##   space / backspace       jump to the last alert / to your keep
##   esc                     cancel, back out of a menu, or open the game menu
## The selection and structure placement also work from the hero view (see
## HeroInput): pick_ahead() selects what's under the crosshair, and
## cursor_ground() puts the placement ghost where the crosshair meets the ground.

signal selection_changed

const DRAG_THRESHOLD := 6.0
const DOUBLE_CLICK := 0.35
## Hero view: how far away you can select things and place structures.
const HERO_PICK_RANGE := 90.0
const HERO_PLACE_RANGE := 60.0

var game: RTSGame
var selection: Array[RTSEntity] = []
## A resource clicked on (shown in the HUD; it can't be ordered).
var inspected: RTSResource
## A command waiting for a click: "move", "attack", "patrol", "gather", "rally", or "".
var target_command := ""
## Structure being placed ("" = none).
var placing := ""
## "build" while a peasant's build menu is open.
var menu := ""
var drag_start := Vector2.INF
var dragging := false
## Where the cursor is (from input events, so it's right even over the HUD).
var mouse := Vector2.ZERO

var _groups := {}
var _last_group := -1
var _last_group_time := 0.0
var _last_click_time := 0.0
var _last_click_entity: RTSEntity
var _ghost: MeshInstance3D
var _ghost_ok := false
var _ghost_pos := Vector3.ZERO
var _idle_worker_index := 0
var _keep_index := 0


func _process(_delta: float) -> void:
	if placing != "":
		_update_ghost()  # in either view: the hero view places at the crosshair
	if game.view_mode != "command":
		return
	var shape := Input.CURSOR_CROSS if target_command != "" else Input.CURSOR_ARROW
	if Input.get_current_cursor_shape() != shape:
		Input.set_default_cursor_shape(shape)


# --- Input --------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var pointer := event as InputEventMouse
	if pointer:
		mouse = pointer.position


func _unhandled_input(event: InputEvent) -> void:
	if not game.started or game.game_over or game.hud.is_menu_open() or game.view_mode != "command":
		return
	var button := event as InputEventMouseButton
	if button:
		_on_mouse_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion:
		if drag_start != Vector2.INF and motion.position.distance_to(drag_start) > DRAG_THRESHOLD:
			dragging = true
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if _on_key(key):
			get_viewport().set_input_as_handled()


func _on_mouse_button(button: InputEventMouseButton) -> void:
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			if placing != "":
				try_place(button.shift_pressed)
			elif target_command != "":
				_issue_targeted(button.position, button.shift_pressed)
			else:
				drag_start = button.position
				dragging = false
		elif drag_start != Vector2.INF:
			if dragging:
				_box_select(Rect2(drag_start, Vector2.ZERO).expand(button.position), button.shift_pressed)
			else:
				_click_select(button.position, button.shift_pressed, button.ctrl_pressed)
			drag_start = Vector2.INF
			dragging = false
	elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		if placing != "" or target_command != "":
			cancel_modes()
		else:
			smart_command_at(button.position, button.shift_pressed)


## True if the key did something.
func _on_key(key: InputEventKey) -> bool:
	var code := key.keycode
	if code == KEY_ESCAPE:
		if placing != "" or target_command != "":
			cancel_modes()
		elif menu != "":
			menu = ""
			selection_changed.emit()
		else:
			game.hud.toggle_pause_menu()
		return true
	if code == KEY_F10:
		game.hud.toggle_pause_menu()
		return true
	if code >= KEY_0 and code <= KEY_9:
		_on_group_key(code - KEY_0, key.ctrl_pressed, key.shift_pressed)
		return true
	if code == KEY_F1:
		select_idle_worker()
		return true
	if code == KEY_F2:
		select_army()
		return true
	if code == KEY_SPACE:
		if game.hud.last_alert != Vector3.INF:
			game.camera.focus_on(game.hud.last_alert)
		return true
	if code == KEY_BACKSPACE or code == KEY_HOME:
		_jump_to_keep()
		return true
	return press_card_key(key)


## Runs the command card button with this key's letter. True if there was one.
func press_card_key(key: InputEventKey) -> bool:
	var letter := OS.get_keycode_string(key.keycode)
	for card_button in command_card():
		if card_button.key == letter:
			if card_button.enabled:
				execute(card_button.id, key.shift_pressed)
			else:
				game.hud.flash_message(card_button.get("why", "Not available yet."), true)
			return true
	return false


## Whether you have peasants selected (they can build).
func has_workers_selected() -> bool:
	return own_units().any(func(u: RTSUnit) -> bool: return u.is_worker)


## The ground under the cursor: the mouse in the Command View, the crosshair
## in the hero view (up to HERO_PLACE_RANGE away). INF if there's none.
func cursor_ground() -> Vector3:
	if game.view_mode == "command":
		return game.camera.ground_at(mouse)
	var hero := game.local_hero
	if hero == null or hero.camera_rig == null:
		return Vector3.INF
	var eye := hero.camera_rig.camera
	var point := game.map.ray_ground(eye.global_position, -eye.global_basis.z)
	if point == Vector3.INF or RTSEntity.flat(point - hero.global_position).length() > HERO_PLACE_RANGE:
		return Vector3.INF
	return point


## Your unit or structure under the hero view's crosshair (within reach), or null.
func pick_ahead() -> RTSEntity:
	var hero := game.local_hero
	if hero == null or hero.camera_rig == null:
		return null
	var eye := hero.camera_rig.camera
	var screen := eye.get_viewport().get_visible_rect().size * 0.5
	# Units: the one nearest the middle of the view, with a generous margin
	# (small, moving workers are hard to keep under a crosshair).
	var best: RTSEntity = null
	var best_score := INF
	for entity in game.entities:
		if entity.dead or entity.team != game.local_team or entity.tucked_away or not entity is RTSUnit:
			continue
		if entity.global_position.distance_to(eye.global_position) > HERO_PICK_RANGE:
			continue
		var score := _pick_score(entity, entity.radius * 1.5, entity.bar_height, screen, eye, 32.0)
		if score < best_score:
			best = entity
			best_score = score
	if best:
		return best
	# Structures: only what the crosshair actually hits (they're big, and up
	# close a margin would cover half the screen).
	var from := eye.project_ray_origin(screen)
	var exclude: Array[RID] = [hero.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(from, from + eye.project_ray_normal(screen) * HERO_PICK_RANGE, Combat.WORLD, exclude)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider is Hitbox:
		var structure: RTSEntity = (hit.collider as Hitbox).entity
		if is_instance_valid(structure) and not structure.dead and structure.team == game.local_team:
			return structure
	return null


func cancel_modes() -> void:
	target_command = ""
	if placing != "":
		placing = ""
		if _ghost:
			_ghost.queue_free()
			_ghost = null


# --- Selection ----------------------------------------------------------------

func set_selection(list: Array) -> void:
	for entity in selection:
		if is_instance_valid(entity):
			entity.selected = false
	var kept: Array[RTSEntity] = []
	for entity: Variant in list:
		# Heroes play themselves: they show up here but can't be selected.
		if is_instance_valid(entity) and (entity is RTSUnit or entity is RTSStructure) and not entity.dead:
			kept.append(entity)
	selection = kept
	# Units first, then by kind, so the HUD groups them.
	selection.sort_custom(func(a: RTSEntity, b: RTSEntity) -> bool:
		if a.is_structure != b.is_structure:
			return not a.is_structure
		return a.kind < b.kind)
	for entity in selection:
		entity.selected = true
	inspected = null
	menu = ""
	cancel_modes()
	selection_changed.emit()


func forget(entity: RTSEntity) -> void:
	if selection.has(entity):
		selection.erase(entity)
		if selection.is_empty():
			menu = ""
			cancel_modes()
		selection_changed.emit()
	for group: Array in _groups.values():
		group.erase(entity)


## Your own living selection (empty if you're looking at an enemy).
func own_selection() -> Array[RTSEntity]:
	var result: Array[RTSEntity] = []
	for entity in selection:
		if is_instance_valid(entity) and not entity.dead and entity.team == 0:
			result.append(entity)
	return result


func own_units() -> Array[RTSUnit]:
	var result: Array[RTSUnit] = []
	for entity in own_selection():
		if entity is RTSUnit:
			result.append(entity)
	return result


func _click_select(screen: Vector2, shift: bool, ctrl: bool) -> void:
	var picked := pick(screen)
	var now := Time.get_ticks_msec() / 1000.0
	if picked is RTSResource:
		if not shift:
			set_selection([])
			inspected = picked as RTSResource
			selection_changed.emit()
		return
	var entity := picked as RTSEntity
	if entity == null:
		if not shift:
			set_selection([])
		return
	var double := entity == _last_click_entity and now - _last_click_time < DOUBLE_CLICK
	_last_click_entity = entity
	_last_click_time = now
	if entity.team == 0 and (ctrl or double):
		var same: Array[RTSEntity] = []
		for other in game.entities:
			if other.team == 0 and other.kind == entity.kind and game.camera.sees(other.global_position):
				same.append(other)
		if shift:
			for other in selection:
				if not same.has(other):
					same.append(other)
		set_selection(same)
		return
	if shift and entity.team == 0 and not own_selection().is_empty():
		var list := selection.duplicate()
		if list.has(entity):
			list.erase(entity)
		else:
			list.append(entity)
		set_selection(list)
		return
	set_selection([entity])


func _box_select(rect: Rect2, shift: bool) -> void:
	var units: Array[RTSEntity] = []
	var structures: Array[RTSEntity] = []
	for entity in game.entities:
		if entity.team != 0 or entity.dead or entity.tucked_away:
			continue
		var at := entity.global_position + Vector3.UP * entity.bar_height * 0.4
		if game.camera.is_position_behind(at) or not rect.has_point(game.camera.unproject_position(at)):
			continue
		if entity is RTSUnit:
			units.append(entity)
		else:
			structures.append(entity)
	var picked := units if not units.is_empty() else structures
	if shift:
		for entity in selection:
			if not picked.has(entity):
				picked.append(entity)
	if picked.is_empty() and shift:
		return
	set_selection(picked)


## What's under a screen point: a unit or structure (enemies only if you can
## see them), or a resource. Null if nothing.
func pick(screen: Vector2) -> Node3D:
	var camera := game.camera
	var best: Node3D = null
	var best_score := INF
	var ground := camera.ground_at(screen)
	for entity in game.entities:
		if entity.dead or not entity.visible:
			continue
		var score := _pick_score(entity, entity.radius, entity.bar_height, screen)
		if entity.is_structure and ground != Vector3.INF:
			var offset := ground - entity.global_position
			if absf(offset.x) < entity.radius and absf(offset.z) < entity.radius:
				score = minf(score, 0.9)
		if score < best_score:
			best = entity
			best_score = score
	for resource in game.map.resources:
		if not is_instance_valid(resource) or resource.dead or (resource.extractor != null and not resource.extractor.dead):
			continue
		var score := _pick_score(resource, resource.radius, 1.6, screen)
		if score < best_score:
			best = resource
			best_score = score
	return best


## < 1 when the screen point is on the thing (lower = closer to its middle),
## as seen by `camera` (the Command View's by default).
func _pick_score(node: Node3D, radius: float, height: float, screen: Vector2, camera: Camera3D = null, min_reach := 12.0) -> float:
	if camera == null:
		camera = game.camera
	var center := node.global_position + Vector3.UP * height * 0.5
	if camera.is_position_behind(center):
		return INF
	var at := camera.unproject_position(center)
	var edge := camera.unproject_position(center + camera.global_basis.x * maxf(radius, height * 0.4))
	var reach := maxf(at.distance_to(edge) * 1.15, min_reach)
	var score := at.distance_to(screen) / reach
	return score if score < 1.0 else INF


func select_idle_worker() -> void:
	var idle: Array[RTSUnit] = []
	for entity in game.entities:
		if entity.team == 0 and entity is RTSUnit and (entity as RTSUnit).is_worker and (entity as RTSUnit).is_idle():
			idle.append(entity)
	if idle.is_empty():
		game.hud.flash_message("No idle peasants.", false)
		return
	_idle_worker_index = (_idle_worker_index + 1) % idle.size()
	var worker := idle[_idle_worker_index]
	set_selection([worker])
	game.camera.focus_on(worker.global_position)


func select_army() -> void:
	var army: Array[RTSEntity] = []
	for entity in game.entities:
		if entity.team == 0 and entity is RTSUnit and not (entity as RTSUnit).is_worker:
			army.append(entity)
	set_selection(army)


func _jump_to_keep() -> void:
	var keeps: Array[RTSEntity] = []
	for entity in game.entities:
		if entity.team == 0 and entity.kind == "keep":
			keeps.append(entity)
	if keeps.is_empty():
		return
	_keep_index = (_keep_index + 1) % keeps.size()
	game.camera.focus_on(keeps[_keep_index].global_position)


func _on_group_key(number: int, ctrl: bool, shift: bool) -> void:
	if ctrl or shift:
		var mine := own_selection()
		if mine.is_empty():
			return
		var group: Array = _groups.get(number, []) if shift else []
		for entity in mine:
			if not group.has(entity):
				group.append(entity)
		_groups[number] = group
		game.hud.flash_message("Group %d: %d selected." % [number, group.size()], false)
		return
	var stored: Array = _groups.get(number, [])
	var list: Array[RTSEntity] = []
	for entity in stored:
		if is_instance_valid(entity) and not entity.dead:
			list.append(entity)
	if list.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _last_group == number and now - _last_group_time < 0.4:
		var center := Vector3.ZERO
		for entity in list:
			center += entity.global_position
		game.camera.focus_on(center / list.size())
	_last_group = number
	_last_group_time = now
	set_selection(list)


# --- Commands -----------------------------------------------------------------

## The buttons for what's selected. Each: id, label, key, slot (0-14 on a 5x3
## grid), enabled, tip, and why (when disabled).
func command_card() -> Array[Dictionary]:
	var buttons: Array[Dictionary] = []
	var mine := own_selection()
	if mine.is_empty():
		return buttons
	var units := own_units()
	if not units.is_empty():
		var has_worker := units.any(func(u: RTSUnit) -> bool: return u.is_worker)
		var fighters := units.any(func(u: RTSUnit) -> bool: return u.can_attack())
		if menu == "build" and has_worker:
			for i in RTSData.BUILD_MENU.size():
				var kind: String = RTSData.BUILD_MENU[i]
				var def := RTSData.structure(kind)
				var missing := game.missing_tech(0, kind)
				buttons.append({"id": "build:" + kind, "label": def.name, "key": def.hotkey, "slot": i,
					"enabled": missing == "", "why": "Requires a %s." % missing,
					"tip": "%s\n%s\nCost: %s" % [def.name, def.desc, RTSData.cost_text(def)], "cost": kind})
			buttons.append({"id": "back", "label": "Back", "key": "Escape", "slot": 14, "enabled": true, "tip": "Back (Esc)"})
			return buttons
		buttons.append({"id": "move", "label": "Move", "key": "M", "slot": 0, "enabled": true, "tip": "Move (M)\nGo somewhere, ignoring enemies."})
		buttons.append({"id": "stop", "label": "Stop", "key": "S", "slot": 1, "enabled": true, "tip": "Stop (S)"})
		buttons.append({"id": "hold", "label": "Hold", "key": "H", "slot": 2, "enabled": true, "tip": "Hold Position (H)\nStay put; fight only what's in range."})
		if fighters:
			buttons.append({"id": "attack", "label": "Attack", "key": "A", "slot": 3, "enabled": true, "tip": "Attack (A)\nClick an enemy, or the ground to attack-move."})
			buttons.append({"id": "patrol", "label": "Patrol", "key": "P", "slot": 4, "enabled": true, "tip": "Patrol (P)\nAttack-move back and forth."})
		if has_worker:
			buttons.append({"id": "gather", "label": "Gather", "key": "G", "slot": 5, "enabled": true, "tip": "Gather (G)\nClick a crystal or your extractor."})
			buttons.append({"id": "return", "label": "Return", "key": "C", "slot": 6, "enabled": true, "tip": "Return Cargo (C)"})
			buttons.append({"id": "build_menu", "label": "Build", "key": "B", "slot": 7, "enabled": true, "tip": "Build (B)"})
		return buttons
	var first := mine[0] as RTSStructure
	var same := _selected_structures(first.kind)
	if not first.built:
		buttons.append({"id": "cancel_build", "label": "Cancel", "key": "X", "slot": 14, "enabled": true,
			"tip": "Cancel construction (X)\nRefunds 75%."})
		return buttons
	var trains := first.trains()
	for i in trains.size():
		var kind: String = trains[i]
		var def := RTSData.unit(kind)
		var missing := game.missing_tech(0, kind)
		buttons.append({"id": "train:" + kind, "label": def.name, "key": def.hotkey, "slot": i,
			"enabled": missing == "", "why": "Requires a %s." % missing,
			"tip": "%s\n%s\nCost: %s" % [def.name, def.desc, RTSData.cost_text(def)], "cost": kind})
	if not trains.is_empty():
		buttons.append({"id": "rally", "label": "Rally", "key": "R", "slot": 10, "enabled": true, "tip": "Set Rally Point (R)\nOr right-click the ground."})
	if same.any(func(s: RTSStructure) -> bool: return not s.queue.is_empty()):
		buttons.append({"id": "cancel_train", "label": "Cancel", "key": "X", "slot": 14, "enabled": true, "tip": "Cancel last in queue (X)"})
	return buttons


func execute(id: String, shift := false) -> void:
	match id:
		"move", "attack", "patrol", "gather", "rally":
			target_command = id
		"stop":
			for unit in own_units():
				unit.stop()
		"hold":
			for unit in own_units():
				unit.command({"type": RTSUnit.Order.HOLD}, shift)
		"return":
			for unit in own_units():
				if unit.is_worker and unit.cargo > 0:
					unit.command({"type": RTSUnit.Order.RETURN}, shift)
		"build_menu":
			menu = "build"
			selection_changed.emit()
		"back":
			menu = ""
			selection_changed.emit()
		"cancel_train":
			var structures := _selected_structures((own_selection()[0] as RTSStructure).kind)
			for i in range(structures.size() - 1, -1, -1):
				if not structures[i].queue.is_empty():
					game.cancel_train(structures[i])
					break
		"cancel_build":
			for entity in own_selection():
				if entity is RTSStructure and not (entity as RTSStructure).built:
					game.cancel_construction(entity)
		_:
			if id.begins_with("build:"):
				_start_placing(id.substr(6))
			elif id.begins_with("train:"):
				_train(id.substr(6))


func _selected_structures(kind: String) -> Array[RTSStructure]:
	var result: Array[RTSStructure] = []
	for entity in own_selection():
		if entity is RTSStructure and entity.kind == kind:
			result.append(entity)
	return result


func _train(kind: String) -> void:
	var best: RTSStructure = null
	for entity in own_selection():
		var structure := entity as RTSStructure
		if structure and structure.built and structure.trains().has(kind):
			if best == null or structure.queue.size() < best.queue.size():
				best = structure
	if best == null:
		return
	var problem := game.queue_train(best, kind)
	if problem != "":
		game.hud.flash_message(problem, true)


## Right click: whatever makes sense for what's under the cursor.
func smart_command_at(screen: Vector2, queue: bool) -> void:
	var picked := pick(screen)
	var ground := game.camera.ground_at(screen)
	if picked == null and ground == Vector3.INF:
		return
	smart_command(picked, ground if ground != Vector3.INF else picked.global_position, queue)


func smart_command(picked: Node3D, point: Vector3, queue: bool) -> void:
	var mine := own_selection()
	if mine.is_empty():
		return
	var units := own_units()
	if units.is_empty():
		_set_rally(picked, point)
		return
	var enemy := picked as RTSEntity if picked is RTSEntity and picked.team == 1 else null
	var center := Vector3.ZERO
	for unit in units:
		center += unit.global_position
	center /= units.size()
	var tight := units.all(func(u: RTSUnit) -> bool: return u.global_position.distance_to(center) < 10.0)
	var spread := sqrt(units.size()) * 0.9
	var attacked := false
	for unit in units:
		if enemy != null:
			if unit.can_hit(enemy):
				unit.command({"type": RTSUnit.Order.ATTACK, "target": enemy}, queue)
				attacked = true
			else:
				unit.command({"type": RTSUnit.Order.MOVE, "pos": enemy.global_position, "spread": spread}, queue)
			continue
		if unit.is_worker and _worker_job(unit, picked, queue):
			continue
		_move(unit, point, center, tight, spread, RTSUnit.Order.MOVE, queue)
	_marker(enemy.global_position if enemy else point, Color(1.0, 0.3, 0.25) if attacked else Color(0.35, 1.0, 0.45))


## Gather / return-cargo orders for a peasant clicking on something. False if
## there's no job there.
func _worker_job(unit: RTSUnit, picked: Node3D, queue: bool) -> bool:
	if picked is RTSResource:
		var resource := picked as RTSResource
		if resource.kind == "crystal":
			unit.command({"type": RTSUnit.Order.GATHER, "target": resource, "phase": "go"}, queue)
			return true
		if resource.extractor != null and resource.extractor.team == 0:
			picked = resource.extractor
	if picked is RTSStructure and picked.team == 0:
		var structure := picked as RTSStructure
		if structure.kind == "extractor" and structure.built:
			unit.command({"type": RTSUnit.Order.GATHER, "target": structure, "phase": "go"}, queue)
			return true
		if structure.def.get("dropoff", false) and structure.built and unit.cargo > 0:
			unit.command({"type": RTSUnit.Order.RETURN}, queue)
			return true
	return false


## Moves keep the group's shape when it's bunched up, else everyone converges.
func _move(unit: RTSUnit, point: Vector3, center: Vector3, tight: bool, spread: float, type: int, queue: bool) -> void:
	var destination := point
	var arrive := spread
	if tight:
		destination = point + RTSEntity.flat(unit.global_position - center).limit_length(6.0)
		arrive = 0.5
	unit.command({"type": type, "pos": destination, "spread": arrive}, queue)


func _set_rally(picked: Node3D, point: Vector3) -> void:
	for entity in own_selection():
		var structure := entity as RTSStructure
		if structure == null or structure.trains().is_empty():
			continue
		structure.rally = point
		structure.rally_target = null
		if picked is RTSResource and (picked as RTSResource).kind == "crystal":
			structure.rally_target = picked
			structure.rally = picked.global_position
		elif picked is RTSStructure and picked.kind == "extractor" and picked.team == 0:
			structure.rally_target = picked
			structure.rally = picked.global_position
	_marker(point, Color(1.0, 0.85, 0.3))


func _issue_targeted(screen: Vector2, queue: bool) -> void:
	var picked := pick(screen)
	var ground := game.camera.ground_at(screen)
	if ground == Vector3.INF:
		if picked == null:
			return
		ground = picked.global_position
	var command := target_command
	if not queue:
		target_command = ""
	var units := own_units()
	match command:
		"rally":
			_set_rally(picked, ground)
		"gather":
			for unit in units:
				if unit.is_worker:
					_worker_job(unit, picked, queue)
			_marker(ground, Color(0.35, 1.0, 0.45))
		"move", "attack", "patrol":
			if units.is_empty():
				return
			var enemy := picked as RTSEntity if picked is RTSEntity and picked.team == 1 else null
			var center := Vector3.ZERO
			for unit in units:
				center += unit.global_position
			center /= units.size()
			var tight := units.all(func(u: RTSUnit) -> bool: return u.global_position.distance_to(center) < 10.0)
			var spread := sqrt(units.size()) * 0.9
			for unit in units:
				if command == "attack" and enemy != null and unit.can_hit(enemy):
					unit.command({"type": RTSUnit.Order.ATTACK, "target": enemy}, queue)
				elif command == "patrol":
					unit.command({"type": RTSUnit.Order.PATROL, "pos": ground, "from": unit.global_position}, queue)
				elif command == "attack":
					_move(unit, ground, center, tight, spread, RTSUnit.Order.ATTACK_MOVE, queue)
				else:
					_move(unit, ground, center, tight, spread, RTSUnit.Order.MOVE, queue)
			_marker(ground, Color(1.0, 0.3, 0.25) if command == "attack" else Color(0.35, 1.0, 0.45))


# --- Placing structures -------------------------------------------------------

func _start_placing(kind: String) -> void:
	var missing := game.missing_tech(0, kind)
	if missing != "":
		game.hud.flash_message("Requires a %s." % missing, true)
		return
	var problem := game.afford_problem(0, kind)
	if problem != "":
		game.hud.flash_message(problem, true)
		return
	cancel_modes()
	placing = kind
	_ghost = RTSModels.ghost(RTSData.structure(kind).size * game.map.cell)
	game.add_child(_ghost)
	_update_ghost()


func _update_ghost() -> void:
	if _ghost == null:
		return
	var ground := cursor_ground()
	if ground == Vector3.INF:
		_ghost.visible = false
		_ghost_ok = false
		return
	_ghost.visible = true
	_ghost_pos = game.snap_placement(placing, ground)
	_ghost_ok = game.can_place(0, placing, _ghost_pos)
	_ghost.global_position = _ghost_pos + Vector3.UP * 1.0
	var material := _ghost.material_override as StandardMaterial3D
	material.albedo_color = Color(0.3, 1.0, 0.4, 0.35) if _ghost_ok else Color(1.0, 0.25, 0.2, 0.35)


func try_place(shift: bool) -> void:
	if not _ghost_ok:
		game.hud.flash_message("Can't build there.", true)
		return
	var problem := game.afford_problem(0, placing)
	if problem != "":
		game.hud.flash_message(problem, true)
		return
	var builder: RTSUnit = null
	for unit in own_units():
		if unit.is_worker and (builder == null or unit.global_position.distance_to(_ghost_pos) < builder.global_position.distance_to(_ghost_pos)):
			builder = unit
	if builder == null:
		cancel_modes()
		return
	var resume: Node3D = null
	if builder.order_type() == RTSUnit.Order.GATHER and is_instance_valid(builder.orders[0].target):
		resume = builder.orders[0].target
	game.spend(0, placing)
	builder.command({"type": RTSUnit.Order.BUILD, "kind": placing, "pos": _ghost_pos, "resume": resume}, shift)
	_marker(_ghost_pos, Color(0.35, 1.0, 0.45))
	if not shift:
		menu = ""
		cancel_modes()
		selection_changed.emit()


## A ring that shrinks away where an order was given.
func _marker(at: Vector3, color: Color) -> void:
	var ring := RTSModels.ring(1.0, color)
	game.add_child(ring)
	ring.global_position = game.map.ground(at) + Vector3.UP * 0.15
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(0.2, 0.2, 0.2), 0.45)
	tween.tween_callback(ring.queue_free)
