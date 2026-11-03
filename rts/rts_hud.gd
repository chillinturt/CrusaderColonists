class_name RTSHud
extends CanvasLayer
## The screen around the battlefield:
##   top        resources and supply (right), game clock and menu button (left)
##   bottom     minimap | what's selected (stats, training queue, or a portrait
##              per unit) | command card (5x3 buttons with hotkeys)
##   overlay    selection box, health bars, rally lines, hints next to the cursor
## Only shown in the Command View. The start, pause and end menus are the
## match's (MatchMenu); messages also go to the hero HUD while you're playing
## your hero.

const PANEL_HEIGHT := 196.0
const CARD_SIZE := Vector2(64, 56)
const CRYSTAL_COLOR := Color(0.45, 0.8, 1.0)
const AETHER_COLOR := Color(0.4, 1.0, 0.5)

var game: RTSGame
## Where the last "under attack" alert came from (space jumps there).
var last_alert := Vector3.INF

var _root: Control
var _overlay: Control
var _crystal_label: Label
var _aether_label: Label
var _supply_label: Label
var _time_label: Label
var _message: Label
var _message_time := 0.0
var _minimap: RTSMinimap
var _info_title: Label
var _info_text: Label
var _info_bar: ProgressBar
var _queue_row: HBoxContainer
var _queue_buttons: Array[Button] = []
var _portraits: GridContainer
var _card_buttons: Array[Button] = []
var _card: Array[Dictionary] = []
var _card_timer := 0.0


func setup(p_game: RTSGame) -> void:
	game = p_game
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 14
	_root.theme = theme
	add_child(_root)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)

	_build_top_bar()
	_build_bottom_panel()

	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_message.offset_top = -PANEL_HEIGHT - 44.0
	_message.offset_bottom = -PANEL_HEIGHT - 14.0
	_message.offset_left = -400.0
	_message.offset_right = 400.0
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 18)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.add_theme_constant_override("outline_size", 5)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_message)

	game.controller.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func is_menu_open() -> bool:
	return game.menu != null and game.menu.is_open()


func toggle_pause_menu() -> void:
	game.menu.toggle_pause()


func flash_message(text: String, warning: bool) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4) if warning else Color(0.85, 1.0, 0.85))
	_message_time = 3.0
	if game.view_mode != "command" and game.hero_hud:
		game.hero_hud.notify(text, Color(1.0, 0.75, 0.4) if warning else Color(0.85, 1.0, 0.85))


func _process(delta: float) -> void:
	if game == null or not visible:
		return
	_crystal_label.text = "Crystal  %d" % game.crystal[0]
	_aether_label.text = "Aether  %d" % game.aether[0]
	var used := game.supply_used(0)
	var cap := game.supply_cap(0)
	_supply_label.text = "Supply  %d / %d" % [used, cap]
	_supply_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if used >= cap and cap < RTSData.MAX_SUPPLY else Color(0.95, 0.95, 0.9))
	_time_label.text = _clock(game.time)
	_message_time -= delta
	_message.modulate.a = clampf(_message_time, 0.0, 1.0)
	_card_timer -= delta
	if _card_timer <= 0.0:
		_card_timer = 0.25
		_refresh_card()
	_refresh_info()
	_overlay.queue_redraw()


static func _clock(seconds: float) -> String:
	var whole := floori(seconds)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]


# --- Layout -------------------------------------------------------------------

func _style(color: Color, margin := 8.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.5, 0.55, 0.65, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(margin)
	return style


func _label(text: String, color := Color(0.95, 0.95, 0.9), font_size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button


func _build_top_bar() -> void:
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", _style(Color(0.05, 0.06, 0.08, 0.85), 6.0))
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -420.0
	right.offset_right = -8.0
	right.offset_top = 6.0
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(right)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(row)
	_crystal_label = _label("", CRYSTAL_COLOR, 16)
	_aether_label = _label("", AETHER_COLOR, 16)
	_supply_label = _label("", Color(0.95, 0.95, 0.9), 16)
	row.add_child(_crystal_label)
	row.add_child(_aether_label)
	row.add_child(_supply_label)

	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _style(Color(0.05, 0.06, 0.08, 0.85), 4.0))
	left.position = Vector2(8, 6)
	_root.add_child(left)
	var left_row := HBoxContainer.new()
	left_row.add_theme_constant_override("separation", 12)
	left.add_child(left_row)
	left_row.add_child(_button("Menu (F10)", toggle_pause_menu))
	_time_label = _label("0:00", Color(0.95, 0.95, 0.9), 16)
	left_row.add_child(_time_label)


func _build_bottom_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.07, 0.09, 0.94), 6.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -PANEL_HEIGHT
	_root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	_minimap = RTSMinimap.new()
	_minimap.game = game
	_minimap.custom_minimum_size = Vector2(PANEL_HEIGHT - 14.0, PANEL_HEIGHT - 14.0)
	row.add_child(_minimap)

	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _style(Color(0.09, 0.1, 0.13, 1.0), 10.0))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	info.add_child(column)
	_info_title = _label("", Color.WHITE, 18)
	column.add_child(_info_title)
	_info_text = _label("")
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_info_text)
	_info_bar = ProgressBar.new()
	_info_bar.custom_minimum_size = Vector2(0, 14)
	_info_bar.show_percentage = false
	_info_bar.max_value = 1.0
	_info_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_info_bar)
	_queue_row = HBoxContainer.new()
	column.add_child(_queue_row)
	for i in RTSData.MAX_QUEUE:
		var slot := _button("", _on_queue_slot.bind(i))
		slot.custom_minimum_size = Vector2(76, 30)
		slot.tooltip_text = "Click to cancel"
		_queue_row.add_child(slot)
		_queue_buttons.append(slot)
	_portraits = GridContainer.new()
	_portraits.columns = 8
	_portraits.add_theme_constant_override("h_separation", 3)
	_portraits.add_theme_constant_override("v_separation", 3)
	column.add_child(_portraits)

	var card := GridContainer.new()
	card.columns = 5
	card.add_theme_constant_override("h_separation", 4)
	card.add_theme_constant_override("v_separation", 4)
	row.add_child(card)
	for i in 15:
		var button := _button("", _on_card_button.bind(i))
		button.custom_minimum_size = CARD_SIZE
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 12)
		card.add_child(button)
		_card_buttons.append(button)


# --- Selection panel ----------------------------------------------------------

func _on_selection_changed() -> void:
	for child in _portraits.get_children():
		child.queue_free()
	var selection := game.controller.selection
	if selection.size() > 1:
		for entity in selection.slice(0, 32):
			var portrait := _button(_short_name(entity), _on_portrait.bind(entity))
			portrait.custom_minimum_size = Vector2(58, 26)
			portrait.add_theme_font_size_override("font_size", 11)
			portrait.tooltip_text = entity.display_name()
			_portraits.add_child(portrait)
	_refresh_card()


func _short_name(entity: RTSEntity) -> String:
	var text := entity.display_name()
	return text.substr(0, 7)


func _on_portrait(entity: RTSEntity) -> void:
	if not is_instance_valid(entity):
		return
	var controller := game.controller
	if Input.is_key_pressed(KEY_SHIFT):
		var list := controller.selection.duplicate()
		list.erase(entity)
		controller.set_selection(list)
	elif Input.is_key_pressed(KEY_CTRL):
		controller.set_selection(controller.selection.filter(func(e: RTSEntity) -> bool: return e.kind == entity.kind))
	else:
		controller.set_selection([entity])


func _on_queue_slot(index: int) -> void:
	var selection := game.controller.own_selection()
	if selection.size() == 1 and selection[0] is RTSStructure:
		var structure := selection[0] as RTSStructure
		if index < structure.queue.size():
			game.cancel_train(structure, index)


func _refresh_info() -> void:
	var controller := game.controller
	var selection := controller.selection
	_info_bar.visible = false
	_queue_row.visible = false
	_portraits.visible = selection.size() > 1
	if selection.is_empty():
		var resource := controller.inspected
		if is_instance_valid(resource) and not resource.dead:
			_info_title.text = resource.display_name()
			_info_title.add_theme_color_override("font_color", CRYSTAL_COLOR if resource.kind == "crystal" else AETHER_COLOR)
			_info_text.text = "Remaining: %d" % resource.amount
			if resource.kind == "vent":
				_info_text.text += "\nBuild an Extractor on it to draw aether."
		else:
			_info_title.text = RTSData.TEAM_NAMES[0]
			_info_title.add_theme_color_override("font_color", RTSData.TEAM_COLORS[0])
			_info_text.text = "Command View: spend the team's crystal and aether. Each Barracks, Forge, Aerie and Sanctum makes every minion wave stronger.\nLeft-click / drag to select. Right-click to command.  F1: idle peasant  F2: army  V: back to your hero"
		return
	if selection.size() > 1:
		_info_title.text = "%d selected" % selection.size()
		_info_title.add_theme_color_override("font_color", Color.WHITE)
		_info_text.text = ""
		var index := 0
		for child in _portraits.get_children():
			if index < selection.size() and is_instance_valid(selection[index]):
				var member := selection[index]
				var ratio := member.hp / member.max_hp
				(child as Button).modulate = Color(0.5, 1.0, 0.5) if ratio > 0.6 else (Color(1.0, 0.9, 0.4) if ratio > 0.3 else Color(1.0, 0.45, 0.4))
			index += 1
		return
	var entity := selection[0]
	if not is_instance_valid(entity):
		return
	_info_title.text = entity.display_name()
	_info_title.add_theme_color_override("font_color", RTSData.TEAM_COLORS[entity.team].lightened(0.3))
	var lines := PackedStringArray()
	lines.append("Health %d / %d    Armor %d" % [ceili(entity.hp), int(entity.max_hp), int(entity.armor)])
	var def := entity.def
	if entity.can_attack():
		var reach := "melee" if def.get("range", 0.0) < 1.5 else "%d" % int(def.range)
		var hits := "ground & air" if def.get("air", false) and def.get("ground", false) else ("air" if def.get("air", false) else "ground")
		var attack := "Damage %d (%s)    Range %s    Hits %s" % [int(def.damage), "every %.1fs" % def.cooldown, reach, hits]
		if def.get("splash", 0.0) > 0.0:
			attack += "    Splash"
		lines.append(attack)
	var unit := entity as RTSUnit
	if unit:
		if unit.flying:
			lines.append("Flying")
		if unit.cargo > 0:
			lines.append("Carrying %d %s" % [unit.cargo, unit.cargo_kind])
		if entity.team == 0 and unit.is_worker and unit.is_idle():
			lines.append("Idle")
	var structure := entity as RTSStructure
	if structure:
		if not structure.built:
			lines.append("Under construction")
			_info_bar.visible = true
			_info_bar.value = structure.progress
		elif structure.vent:
			lines.append("Aether left in the vent: %d" % structure.vent.amount)
		elif structure.def.get("supply", 0) > 0:
			lines.append("Provides %d supply" % structure.def.supply)
		if structure.built and not structure.queue.is_empty() and structure.team == 0:
			_info_bar.visible = true
			_info_bar.value = structure.train_fraction()
			_queue_row.visible = true
			for i in _queue_buttons.size():
				var slot := _queue_buttons[i]
				slot.visible = i < structure.queue.size()
				if slot.visible:
					slot.text = RTSData.unit(structure.queue[i]).name
	if entity.team != 0:
		lines.append(RTSData.TEAM_NAMES[entity.team])
	_info_text.text = "\n".join(lines)


# --- Command card -------------------------------------------------------------

func _refresh_card() -> void:
	_card = game.controller.command_card()
	for button in _card_buttons:
		button.text = ""
		button.tooltip_text = ""
		button.disabled = true
		button.modulate = Color(1, 1, 1, 0.25)
	for spec in _card:
		var button := _card_buttons[spec.slot]
		var key: String = spec.key
		button.text = "%s\n[%s]" % [spec.label, "Esc" if key == "Escape" else key]
		button.tooltip_text = spec.tip
		button.disabled = false
		var color := Color.WHITE
		if not spec.enabled:
			color = Color(0.55, 0.55, 0.55)
		elif spec.has("cost") and not game.can_afford(0, spec.cost):
			color = Color(1.0, 0.6, 0.5)
		button.modulate = color


func _on_card_button(slot: int) -> void:
	for spec in _card:
		if spec.slot == slot:
			if spec.enabled:
				game.controller.execute(spec.id, Input.is_key_pressed(KEY_SHIFT))
			else:
				flash_message(spec.get("why", "Not available yet."), true)
			_refresh_card()
			return


# --- Overlay ------------------------------------------------------------------

func _draw_overlay() -> void:
	if game == null or not game.started:
		return
	var camera := game.camera
	var controller := game.controller
	for entity in game.entities:
		if entity.dead or not entity.visible:
			continue
		var damaged := entity.hp < entity.max_hp - 0.5
		var building := entity is RTSStructure and not (entity as RTSStructure).built
		if not (entity.selected or damaged or building):
			continue
		var top := entity.global_position + Vector3.UP * (entity.bar_height + 0.3)
		if camera.is_position_behind(top):
			continue
		var at := camera.unproject_position(top)
		var edge := camera.unproject_position(top + camera.global_basis.x * entity.radius)
		var width := clampf(at.distance_to(edge) * 2.0, 22.0, 110.0)
		var bar := Rect2(at - Vector2(width * 0.5, 3.0), Vector2(width, 5.0))
		if not _overlay.get_rect().grow(20.0).has_point(at):
			continue
		var ratio := clampf(entity.hp / entity.max_hp, 0.0, 1.0)
		var color := Color(0.3, 0.95, 0.35) if ratio > 0.6 else (Color(1.0, 0.85, 0.25) if ratio > 0.3 else Color(1.0, 0.3, 0.25))
		_overlay.draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.75))
		_overlay.draw_rect(Rect2(bar.position, Vector2(width * ratio, bar.size.y)), color)
		if building:
			var progress := (entity as RTSStructure).progress
			_overlay.draw_rect(Rect2(bar.position + Vector2(0, 7), Vector2(width, 3)).grow(1.0), Color(0, 0, 0, 0.75))
			_overlay.draw_rect(Rect2(bar.position + Vector2(0, 7), Vector2(width * progress, 3)), Color(0.4, 0.7, 1.0))

	# Rally points of selected structures.
	for entity in controller.own_selection():
		var structure := entity as RTSStructure
		if structure == null or structure.rally == Vector3.INF or structure.trains().is_empty():
			continue
		var from := structure.global_position + Vector3.UP * 0.5
		var to := game.map.ground(structure.rally) + Vector3.UP * 0.3
		if camera.is_position_behind(from) or camera.is_position_behind(to):
			continue
		var a := camera.unproject_position(from)
		var b := camera.unproject_position(to)
		_overlay.draw_dashed_line(a, b, Color(1.0, 0.85, 0.3, 0.8), 2.0, 8.0)
		_overlay.draw_circle(b, 5.0, Color(1.0, 0.85, 0.3))

	# Selection box.
	if controller.dragging and controller.drag_start != Vector2.INF:
		var rect := Rect2(controller.drag_start, Vector2.ZERO).expand(controller.mouse)
		_overlay.draw_rect(rect, Color(0.35, 1.0, 0.45, 0.12))
		_overlay.draw_rect(rect, Color(0.35, 1.0, 0.45, 0.9), false, 1.5)

	# What the next click will do.
	var hint := ""
	if controller.placing != "":
		hint = "Place %s: left-click (shift: keep placing), right-click to cancel" % RTSData.structure(controller.placing).name
	elif controller.target_command != "":
		hint = {"move": "Move: click the ground", "attack": "Attack: click an enemy or the ground",
			"patrol": "Patrol: click the far end", "gather": "Gather: click a crystal or your extractor",
			"rally": "Rally point: click the ground or a resource"}.get(controller.target_command, "")
	if hint != "":
		var font := _overlay.get_theme_default_font()
		var at: Vector2 = controller.mouse + Vector2(18, 28)
		_overlay.draw_string_outline(font, at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
		_overlay.draw_string(font, at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.95, 0.7))

