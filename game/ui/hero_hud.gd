class_name HeroHud
extends CanvasLayer
## The screen while you play your hero:
##   center        crosshair with the weapon's spread ring and hit markers,
##                 the respawn countdown while you're dead
##   bottom left   level, health, stamina, gas
##   bottom right  your three weapons and ammo
##   top           game clock, team kills, both keeps' health, the next wave
##   top left      gold and the team's crystal / aether
##   top right     minimap (what your team can see)
##   right         kill feed and messages
##   Tab           scoreboard;  B  the shop (buy at your fountain)
##   bottom        what you've selected with E, the peasants' build menu (B),
##                 and how to place a structure
## Hidden in the Command View, where the RTS HUD takes over.

const FEED_TIME := 5.0
const FEED_MAX := 7
const PANEL := Color(0.05, 0.06, 0.08, 0.78)
const GOLD := Color(1.0, 0.85, 0.3)

var game: RTSGame
var shop_open := false

var _root: Control
var _crosshair: Control
var _flash: ColorRect
var _center_label: Label
var _vitals_label: Label
var _health_bar: ProgressBar
var _xp_bar: ProgressBar
var _stamina_bar: ProgressBar
var _gas_bar: ProgressBar
var _weapons_label: RichTextLabel
var _top_label: Label
var _keep_bars: Array[ProgressBar] = []
var _wealth_label: Label
var _feed_box: VBoxContainer
var _feed: Array = []  # [text, color, time left]
var _scoreboard: PanelContainer
var _score_text: RichTextLabel
var _shop: PanelContainer
var _shop_title: Label
var _shop_buttons := {}
var _help: Label
var _command_panel: PanelContainer
var _command_text: RichTextLabel
var _minimap: Minimap
var _flash_tween: Tween
var _hit_time := 0.0
var _hit_headshot := false


func setup(p_game: RTSGame) -> void:
	game = p_game
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 16
	_root.theme = theme
	add_child(_root)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 0, 0, 0)
	_root.add_child(_flash)

	_crosshair = Control.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	_root.add_child(_crosshair)

	_center_label = _label("", Color.WHITE, 34)
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center_label.offset_left = -400
	_center_label.offset_right = 400
	_center_label.offset_top = 40
	_center_label.offset_bottom = 140
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_center_label)

	_build_vitals()
	_build_weapons()
	_build_top()
	_build_feed()
	_build_command_panel()
	_build_scoreboard()
	_build_shop()

	_minimap = Minimap.new()
	_minimap.game = game
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap.offset_left = -236
	_minimap.offset_right = -16
	_minimap.offset_top = 16
	_minimap.offset_bottom = 236
	_root.add_child(_minimap)

	_help = _label("WASD move · Space jump (hold to bhop) · Shift gas · LMB fire · RMB hook (F/C reel) · R reload · 1-3/Q weapons · E select · B shop / build · V command view · Tab scores · Esc menu",
			Color(1, 1, 1, 0.7), 14)
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_help.offset_left = -600
	_help.offset_right = 600
	_help.offset_top = -30
	_help.offset_bottom = -8
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_help)


## The clock as m:ss.
static func clock(seconds: float) -> String:
	var whole := floori(seconds)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]


func set_commanding(commanding: bool) -> void:
	_root.visible = not commanding
	if commanding and shop_open:
		toggle_shop()


# --- Building -----------------------------------------------------------------

func _label(text: String, color := Color.WHITE, font_size := 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _style(color: Color, margin := 8.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.5, 0.55, 0.65, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(margin)
	return style


func _bar(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.6)
	back.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _panel(preset: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(preset)
	_root.add_child(panel)
	return panel


func _build_vitals() -> void:
	var panel := _panel(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 16
	panel.offset_right = 336
	panel.offset_top = -150
	panel.offset_bottom = -40
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	_vitals_label = _label("", Color.WHITE, 18)
	column.add_child(_vitals_label)
	_health_bar = _bar(Color(0.3, 0.9, 0.35), 18)
	column.add_child(_health_bar)
	_xp_bar = _bar(Color(0.6, 0.5, 1.0), 5)
	column.add_child(_xp_bar)
	_stamina_bar = _bar(Color(0.5, 0.9, 1.0), 7)
	column.add_child(_stamina_bar)
	_gas_bar = _bar(Color(0.95, 0.75, 0.35), 7)
	column.add_child(_gas_bar)


func _build_weapons() -> void:
	var panel := _panel(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -330
	panel.offset_right = -16
	panel.offset_top = -150
	panel.offset_bottom = -40
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_weapons_label = RichTextLabel.new()
	_weapons_label.bbcode_enabled = true
	_weapons_label.fit_content = true
	_weapons_label.scroll_active = false
	_weapons_label.custom_minimum_size = Vector2(290, 0)
	_weapons_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_weapons_label)


func _build_top() -> void:
	var panel := _panel(Control.PRESET_CENTER_TOP)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = 10
	panel.offset_bottom = 90
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	_top_label = _label("", Color.WHITE, 18)
	_top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_top_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	for team in 2:
		var bar := _bar(RTSData.TEAM_COLORS[team], 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END if team == 0 else ProgressBar.FILL_END_TO_BEGIN
		row.add_child(bar)
		_keep_bars.append(bar)

	var wealth := _panel(Control.PRESET_TOP_LEFT)
	wealth.offset_left = 16
	wealth.offset_top = 16
	wealth.offset_right = 300
	wealth.offset_bottom = 70
	_wealth_label = _label("", Color.WHITE, 16)
	wealth.add_child(_wealth_label)


func _build_feed() -> void:
	_feed_box = VBoxContainer.new()
	_feed_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_feed_box.offset_left = -470
	_feed_box.offset_right = -16
	_feed_box.offset_top = -120
	_feed_box.offset_bottom = 120
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed_box)


func _build_command_panel() -> void:
	_command_panel = _panel(Control.PRESET_CENTER_BOTTOM)
	_command_panel.offset_left = -230
	_command_panel.offset_right = 230
	_command_panel.offset_top = -190
	_command_panel.offset_bottom = -40
	_command_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_command_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_command_panel.visible = false
	_command_text = RichTextLabel.new()
	_command_text.bbcode_enabled = true
	_command_text.fit_content = true
	_command_text.scroll_active = false
	_command_text.custom_minimum_size = Vector2(440, 0)
	_command_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_command_text.add_theme_font_size_override("normal_font_size", 14)
	_command_text.add_theme_font_size_override("bold_font_size", 14)
	_command_panel.add_child(_command_text)


## Selection, build menu and placement, as text.
func _refresh_command_panel() -> void:
	var controller := game.controller
	var lines := PackedStringArray()
	if controller.placing != "":
		var def := RTSData.structure(controller.placing)
		lines.append("[b]Placing %s[/b]  (%s)" % [def.name, RTSData.cost_text(def)])
		lines.append("[color=#9aa3ad]Aim at the ground · LMB place (Shift: keep placing) · RMB / Esc cancel[/color]")
	elif controller.menu == "build":
		lines.append("[b]Build[/b]   [color=#9aa3ad]press a structure's key · Esc close[/color]")
		for button in controller.command_card():
			if not str(button.id).begins_with("build:"):
				continue
			var color := "#ffffff"
			var note := RTSData.cost_text(RTSData.structure(button.cost))
			if not button.enabled:
				color = "#7d848c"
				note = button.why
			elif not game.can_afford(game.local_team, button.cost):
				color = "#ff9a80"
			lines.append("[color=%s][b][%s][/b] %s  —  %s[/color]" % [color, button.key, button.label, note])
	var mine := controller.own_selection()
	if not mine.is_empty() and controller.placing == "" and controller.menu != "build":
		var counts := {}
		for entity in mine:
			var entity_name := entity.display_name()
			counts[entity_name] = counts.get(entity_name, 0) + 1
		var parts := PackedStringArray()
		for entity_name: String in counts:
			parts.append("%d %s" % [counts[entity_name], entity_name] if counts[entity_name] > 1 else entity_name)
		lines.append("[b]Selected:[/b] " + ", ".join(parts))
		var hints := "E on nothing: clear · hold E: add more"
		if controller.has_workers_selected():
			hints = "[color=#ffe08a]B: build[/color] · " + hints
		lines.append("[color=#9aa3ad]%s[/color]" % hints)
	_command_panel.visible = not lines.is_empty()
	_command_text.text = "\n".join(lines)


func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.add_theme_stylebox_override("panel", _style(Color(0.04, 0.05, 0.07, 0.92), 16))
	_scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_scoreboard.offset_left = -430
	_scoreboard.offset_right = 430
	_scoreboard.offset_top = -260
	_scoreboard.offset_bottom = 260
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.visible = false
	_root.add_child(_scoreboard)
	_score_text = RichTextLabel.new()
	_score_text.bbcode_enabled = true
	_score_text.scroll_active = false
	_score_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "Liberation Mono", "monospace"])
	var mono_bold := mono.duplicate() as SystemFont
	mono_bold.font_weight = 700
	_score_text.add_theme_font_override("normal_font", mono)
	_score_text.add_theme_font_override("bold_font", mono_bold)
	_score_text.add_theme_font_size_override("normal_font_size", 15)
	_score_text.add_theme_font_size_override("bold_font_size", 15)
	_scoreboard.add_child(_score_text)


func _build_shop() -> void:
	_shop = PanelContainer.new()
	_shop.add_theme_stylebox_override("panel", _style(Color(0.05, 0.06, 0.09, 0.95), 16))
	_shop.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_shop.offset_left = -360
	_shop.offset_right = 360
	_shop.offset_top = -250
	_shop.offset_bottom = 250
	_shop.visible = false
	_root.add_child(_shop)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_shop.add_child(column)
	_shop_title = _label("", GOLD, 22)
	column.add_child(_shop_title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for id in Hero.SHOP_ITEMS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(220, 64)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_buy.bind(id))
		grid.add_child(button)
		_shop_buttons[id] = button
	var close := Button.new()
	close.text = "Close (B)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_shop)
	column.add_child(close)


# --- Events -------------------------------------------------------------------

## A line in the feed (right side).
func notify(text: String, color := Color.WHITE) -> void:
	_feed.append([text, color, FEED_TIME])
	if _feed.size() > FEED_MAX:
		_feed.pop_front()
	_rebuild_feed()


func add_feed(text: String, color: Color) -> void:
	notify(text, color.lightened(0.25))


func _rebuild_feed() -> void:
	for child in _feed_box.get_children():
		child.queue_free()
	for entry: Array in _feed:
		var label := _label(entry[0], entry[1], 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_feed_box.add_child(label)


func damage_flash(amount: float) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash.color = Color(1, 0, 0, clampf(amount / 120.0, 0.12, 0.4))
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, 0.3)


func hitmarker(headshot: bool) -> void:
	_hit_time = 0.18
	_hit_headshot = headshot


func on_local_death(killer: String) -> void:
	notify("You were killed by %s." % killer if killer != "" else "You died.", Color(1.0, 0.5, 0.4))


func toggle_shop() -> void:
	shop_open = not shop_open
	_shop.visible = shop_open
	if game.view_mode == "hero" and not game.autotest:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if shop_open else Input.MOUSE_MODE_CAPTURED


func _buy(id: StringName) -> void:
	var problem := game.local_hero.buy(id)
	if problem != "":
		notify(problem, Color(1.0, 0.6, 0.4))


# --- Update -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _root.visible:
		return
	for entry: Array in _feed:
		entry[2] -= delta
	var before := _feed.size()
	_feed = _feed.filter(func(entry: Array) -> bool: return entry[2] > 0.0)
	if _feed.size() != before:
		_rebuild_feed()
	_hit_time -= delta
	_help.visible = game.time < 90.0 or not game.started

	var hero := game.local_hero
	_top_label.text = "%s     %d  —  %d     next wave %ds" % [clock(game.time), game.team_kills[0], game.team_kills[1], ceili(game.wave_timer)]
	for team in 2:
		var core := game.cores[team]
		_keep_bars[team].max_value = core.max_hp if is_instance_valid(core) else 1.0
		_keep_bars[team].value = core.hp if is_instance_valid(core) and not core.dead else 0.0
		_keep_bars[team].modulate = Color(0.6, 0.8, 1.0, 1.0) if is_instance_valid(core) and core.shielded else Color.WHITE
	_scoreboard.visible = Input.is_action_pressed("scoreboard") and game.started
	if _scoreboard.visible:
		_refresh_scoreboard()
	if hero == null:
		_crosshair.queue_redraw()
		return

	_wealth_label.text = "%d gold\nTeam: %d crystal · %d aether" % [hero.gold, game.crystal[hero.team], game.aether[hero.team]]
	_vitals_label.text = "%s   Level %d" % [hero.hero_name, hero.level]
	_health_bar.max_value = hero.max_health
	_health_bar.value = hero.health
	_health_bar.modulate = Color(0.7, 1.0, 0.7) if hero.is_healing() or hero.in_fountain else Color.WHITE
	_xp_bar.max_value = hero.xp_to_next()
	_xp_bar.value = hero.xp if hero.level < Hero.MAX_LEVEL else hero.xp_to_next()
	_stamina_bar.max_value = hero.max_stamina()
	_stamina_bar.value = hero.stamina
	_stamina_bar.modulate = Color(1.0, 0.4, 0.3) if hero.exhausted else Color.WHITE
	_gas_bar.max_value = Hero.MAX_GAS
	_gas_bar.value = hero.gas

	var lines := PackedStringArray()
	for i in hero.weapons.size():
		var weapon := hero.weapons[i]
		var text := "%d  %s" % [i + 1, weapon.display_name()]
		if weapon.ammo_text() != "":
			text += "   " + weapon.ammo_text()
		lines.append("[b][color=#ffe08a]%s[/color][/b]" % text if i == hero.current else "[color=#9aa3ad]%s[/color]" % text)
	lines.append("[color=#9aa3ad]RMB  Grappling Hook%s[/color]" % ("  (hooked)" if hero.grapple.hooked else ""))
	_weapons_label.text = "\n".join(lines)

	if hero.dead:
		_center_label.text = "Respawning in %d" % ceili(hero.respawn_left)
	elif game.game_over:
		_center_label.text = ""
	else:
		_center_label.text = ""
	if shop_open:
		_refresh_shop(hero)
	_refresh_command_panel()
	_crosshair.queue_redraw()


func _refresh_shop(hero: Hero) -> void:
	var at_fountain := hero.in_fountain or hero.dead
	_shop_title.text = "Shop — %d gold%s" % [hero.gold, "" if at_fountain else "   (go to your fountain to buy)"]
	for id: StringName in _shop_buttons:
		var button: Button = _shop_buttons[id]
		var cost := hero.upgrade_cost(id)
		button.text = "%s\n%s\n%d gold" % [Upgrades.DEFS[id][0], hero.upgrades.describe_gain(id, 1.0).get_slice(": ", 1), cost]
		button.tooltip_text = hero.upgrades.describe(id)
		button.disabled = not at_fountain or hero.gold < cost


func _refresh_scoreboard() -> void:
	var text := "[center][b]%s %d — %d %s[/b]   %s[/center]\n" % [RTSData.TEAM_NAMES[0], game.team_kills[0], game.team_kills[1],
			RTSData.TEAM_NAMES[1], clock(game.time)]
	for team in 2:
		text += "\n[color=#%s][b]%s[/b][/color]\n" % [RTSData.TEAM_COLORS[team].lightened(0.3).to_html(false), RTSData.TEAM_NAMES[team]]
		text += "[color=#9aa3ad]%-12s %5s %4s %4s %4s %5s %6s  %s[/color]\n" % ["Hero", "Lvl", "K", "D", "A", "LH", "Gold", "Lane"]
		for hero in game.heroes:
			if hero.team != team:
				continue
			var row := "%-12s %5d %4d %4d %4d %5d %6d  %s" % [hero.hero_name, hero.level, hero.kills, hero.deaths, hero.assists,
					hero.last_hits, hero.gold, ["Left", "Mid", "Right"][hero.lane]]
			if hero.dead:
				row += "  (%ds)" % ceili(hero.respawn_left)
			text += ("[b]%s[/b]\n" % row) if hero == game.local_hero else row + "\n"
	_score_text.text = text


func _draw_crosshair() -> void:
	var hero := game.local_hero
	if hero == null or hero.dead or not game.started:
		return
	var center := _crosshair.size * 0.5
	var camera := hero.camera_rig.camera if hero.camera_rig else null
	var weapon := hero.current_weapon()
	_crosshair.draw_circle(center, 2.5, Color.WHITE)
	if camera:
		var spread := weapon.spread_degrees()
		var px := tan(deg_to_rad(spread)) / tan(deg_to_rad(camera.fov * 0.5)) * _crosshair.size.y * 0.5
		if px > 3.0:
			_crosshair.draw_arc(center, px, 0.0, TAU, 40, Color(1, 1, 1, 0.45), 1.5)
	if _hit_time > 0.0:
		var color := Color(1.0, 0.25, 0.2) if _hit_headshot else Color.WHITE
		for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_crosshair.draw_line(center + corner * 6.0, center + corner * 13.0, color, 2.0)


## The whole map from above (north up): terrain under your team's fog, lanes,
## structures, units, heroes (enemies only where your team can see them), and
## your hero as an arrow.
class Minimap extends Control:
	var game: RTSGame

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _process(_delta: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func to_map(world: Vector3) -> Vector2:
		var r := game.map.play_radius
		return Vector2((world.x + r) / (2.0 * r) * size.x, (world.z + r) / (2.0 * r) * size.y)

	func _draw() -> void:
		var map := game.map
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.03, 0.03, 0.04))
		var first := (map.size * 0.5 - map.play_radius) / map.cell
		var span := 2.0 * map.play_radius / map.cell
		var source := Rect2(first, first, span, span)
		draw_texture_rect_region(map.map_texture, rect, source)
		draw_texture_rect_region(game.fog.overlay_texture, rect, source, Color(1, 1, 1, 0.6))
		for path in map.lanes:
			var points := PackedVector2Array()
			for p in path:
				points.append(to_map(p))
			draw_polyline(points, Color(0.9, 0.8, 0.6, 0.25), 3.0)
		var px := size.x / (2.0 * map.play_radius)
		var local := game.local_team
		for entity in game.entities:
			if entity.dead or entity is HeroAvatar:
				continue
			if entity.team != local and not (game.fog_visible(entity.global_position) or (entity.is_structure and entity.discovered)):
				continue
			var color := RTSData.TEAM_COLORS[entity.team]
			var at := to_map(entity.global_position)
			if entity.is_structure:
				var half := maxf(entity.radius * px, 2.5)
				draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), color)
				draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), Color(0, 0, 0, 0.6), false, 1.0)
			else:
				draw_circle(at, 1.6, color.lightened(0.2))
		for hero in game.heroes:
			if hero.dead or (hero.team != local and not game.fog_visible(hero.global_position)):
				continue
			var at := to_map(hero.global_position)
			var color := Color.WHITE if hero == game.local_hero else RTSData.TEAM_COLORS[hero.team].lightened(0.35)
			var facing := Vector2(-sin(hero.intent.yaw), -cos(hero.intent.yaw))
			var side := Vector2(-facing.y, facing.x)
			var tip := at + facing * 6.0
			draw_colored_polygon(PackedVector2Array([tip, at - facing * 3.0 + side * 3.5, at - facing * 3.0 - side * 3.5]), color)
		for f in game.fountains:
			draw_arc(to_map(f), 4.0, 0.0, TAU, 16, Color(1, 1, 1, 0.5), 1.0)
		draw_rect(rect, Color(1, 1, 1, 0.35), false, 1.0)
