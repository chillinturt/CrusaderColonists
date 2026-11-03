class_name MatchMenu
extends CanvasLayer
## The match's menus: the start screen (difficulty, who runs your base, your
## lane and loadout), the pause menu, and victory / defeat. Keeps running while
## the game is paused.

const TITLE := "CRUSADER CLONISTS"
## Width of the menu's contents (the window scrolls them if they're taller).
const BOX_WIDTH := 540.0

var game: RTSGame

var _layer: ColorRect
var _box: VBoxContainer
var _open := false
var _difficulty := 1
var _ai_commander := true
var _lane := 1
var _loadout: Array[String] = WeaponData.DEFAULT_LOADOUT.duplicate()
var _weapon_info: Label


func setup(p_game: RTSGame) -> void:
	game = p_game
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_layer = ColorRect.new()
	_layer.color = Color(0, 0, 0, 0.6)
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.visible = false
	add_child(_layer)
	# The panel fills the window (minus a margin) and scrolls, so the menus fit
	# however small the window is.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_layer.add_child(margin)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.97)
	style.border_color = Color(0.5, 0.55, 0.65, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(BOX_WIDTH, 0)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	# Esc closes the pause menu (the hero / command input opens it).
	if _open and game.started and not game.game_over and event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()


# --- Building blocks ----------------------------------------------------------

func _clear() -> void:
	for child in _box.get_children():
		child.queue_free()
	_layer.visible = true
	_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.controller.cancel_modes()


func _close() -> void:
	_layer.visible = false
	_open = false
	if game.view_mode == "hero" and not game.autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _title(text: String, color: Color, font_size := 30) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	_box.add_child(label)


func _paragraph(text: String, color := Color(0.85, 0.87, 0.9), font_size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(BOX_WIDTH - 20.0, 0)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	_box.add_child(label)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback)
	_box.add_child(button)
	return button


## A row of mutually exclusive choices.
func _choice(caption: String, options: Array, selected: int, on_pick: Callable, tips: Array = []) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_box.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(100, 0)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	var group := ButtonGroup.new()
	for i in options.size():
		var button := Button.new()
		button.text = options[i]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == selected
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 13)
		if i < tips.size():
			button.tooltip_text = tips[i]
		button.pressed.connect(on_pick.bind(i))
		row.add_child(button)


# --- Screens --------------------------------------------------------------------

func show_start() -> void:
	_clear()
	_title(TITLE, RTSData.TEAM_COLORS[0].lightened(0.35), 26)
	_paragraph("6 v 6 on the %s: you and five crusaders of the %s against six of the %s. Push the lanes with your minions, break the towers, destroy the enemy Keep. V opens the Command View to build with your team's crystal; B shops at your fountain." %
			[game.map.biome.display_name, RTSData.TEAM_NAMES[0], RTSData.TEAM_NAMES[1]], Color(0.8, 0.84, 0.9), 13)
	_choice("Difficulty", ["Easy", "Normal", "Hard"], _difficulty, func(i: int) -> void: _difficulty = i)
	_choice("Your base", ["AI commander helps", "I command it alone"], 0 if _ai_commander else 1,
			func(i: int) -> void: _ai_commander = i == 0,
			["An AI commander builds and trains for your team; you can still take over in the Command View any time.",
			"Only you spend your team's crystal and aether (the peasants still mine on their own)."])
	_choice("Your lane", ["Left", "Middle", "Right"], _lane, func(i: int) -> void: _lane = i)
	for slot in WeaponData.SLOT_TITLES.size():
		var ids := WeaponData.ids_for_slot(slot)
		var names: Array = []
		var tips: Array = []
		for id in ids:
			names.append(WeaponData.get_def(id).get("short", WeaponData.get_def(id).name))
			tips.append(WeaponData.get_def(id).desc)
		_choice(WeaponData.SLOT_TITLES[slot], names, ids.find(_loadout[slot]), _pick_weapon.bind(slot, ids), tips)
	_weapon_info = _paragraph("", Color(0.65, 0.7, 0.76), 12)
	_update_weapon_info()
	_paragraph("Every hero also has the grappling hook (RMB, F/C to reel) and a gas pack (Shift).", Color(0.65, 0.7, 0.76), 12)
	var start := _button("Start the match", _start)
	start.custom_minimum_size.y = 36
	_button("Quit", get_tree().quit)


func _pick_weapon(index: int, slot: int, ids: Array[String]) -> void:
	_loadout[slot] = ids[index]
	_update_weapon_info()


func _update_weapon_info() -> void:
	var lines := PackedStringArray()
	for id in _loadout:
		var def := WeaponData.get_def(id)
		lines.append("%s: %s" % [def.name, def.desc])
	_weapon_info.text = "\n".join(lines)


func _start() -> void:
	_close()
	game.begin({"difficulty": _difficulty, "ai_commander": _ai_commander, "lane": _lane, "loadout": _loadout.duplicate()})


func toggle_pause() -> void:
	if not game.started or game.game_over:
		return
	if _open:
		_close()
		get_tree().paused = false
		return
	_clear()
	get_tree().paused = true
	_title("Paused", Color.WHITE)
	_paragraph("Hero: WASD move, Space jump (hold to bunny hop), Shift gas, LMB fire, RMB grappling hook (F reel in, C reel out), R reload, 1-3 / wheel / Q weapons, B shop at your fountain, Tab scoreboard, V Command View. E selects your unit under the crosshair (hold to add more); with peasants selected, B opens their build menu: press a structure's key, aim, LMB to place.",
			Color(0.75, 0.79, 0.85))
	_paragraph("Command View: left-click / drag to select, right-click to move, attack or gather. A attack-move, S stop, H hold, P patrol, B build (with a peasant). Shift queues orders, Ctrl+1-0 sets groups. Arrow keys, screen edges or middle-drag pan; the wheel zooms.",
			Color(0.75, 0.79, 0.85))
	_button("Resume", toggle_pause)
	_button("Restart (new map)", game.restart)
	_button("Quit", get_tree().quit)


func show_end(won: bool) -> void:
	_clear()
	if won:
		_title("VICTORY", Color(0.5, 1.0, 0.55), 42)
		_paragraph("The %s keep has fallen. The %s holds the field." % [RTSData.TEAM_NAMES[1 - game.local_team], RTSData.TEAM_NAMES[game.local_team]])
	else:
		_title("DEFEAT", Color(1.0, 0.4, 0.35), 42)
		_paragraph("Your keep has fallen.")
	_paragraph("Game time %s   ·   Kills %d — %d" % [HeroHud.clock(game.time), game.team_kills[0], game.team_kills[1]], Color(0.7, 0.74, 0.8))
	var hero := game.local_hero
	if hero:
		_paragraph("You: level %d, %d kills, %d deaths, %d assists, %d last hits." % [hero.level, hero.kills, hero.deaths, hero.assists, hero.last_hits],
				Color(0.7, 0.74, 0.8))
	_button("Play again (new map)", game.restart)
	_button("Keep watching", _close)
	_button("Quit", get_tree().quit)
