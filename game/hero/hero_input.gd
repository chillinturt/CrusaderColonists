class_name HeroInput
extends Node
## Your hands on your hero: keyboard and mouse into the hero's HeroIntent.
## Only while you're in the hero view with the mouse captured and no menu or
## shop open; otherwise your hero lets go of everything.
##   WASD move, Space jump (hold to bunny hop), Shift gas, LMB fire,
##   RMB grappling hook (F reel in, C reel out), R reload, 1-3 / wheel / Q weapons,
##   B shop (at your fountain), V Command View, Tab scoreboard, Esc menu.
## You can also run your base without leaving your hero (it shares the Command
## View's selection):
##   E            select the unit or structure of yours under the crosshair (tap
##                on nothing to clear); hold E and sweep to add more
##   B            with peasants selected: their build menu (the structure keys
##                from the Command View, so B again is a Barracks; Esc closes
##                it) instead of the shop
##   LMB / RMB    while placing a structure: place it (Shift keeps placing) /
##                cancel. The nearest selected peasant goes and builds it.

var hero: Hero
var mouse_sensitivity := 0.0025
## A click that placed (or cancelled) a structure isn't also a shot / a hook,
## until the button is let go.
var _hold_fire := false
var _hold_hook := false


## Registers default key bindings at runtime so the game works without
## touching the Input Map. Rebinding in Project Settings still takes priority.
static func setup_actions() -> void:
	var bindings := {
		"move_forward": _key(KEY_W),
		"move_back": _key(KEY_S),
		"move_left": _key(KEY_A),
		"move_right": _key(KEY_D),
		"jump": _key(KEY_SPACE),
		"reload": _key(KEY_R),
		"attack": _mouse(MOUSE_BUTTON_LEFT),
		"hook": _mouse(MOUSE_BUTTON_RIGHT),
		"gas": _key(KEY_SHIFT),
		"reel_in": _key(KEY_F),
		"reel_out": _key(KEY_C),
		"weapon_1": _key(KEY_1),
		"weapon_2": _key(KEY_2),
		"weapon_3": _key(KEY_3),
		"weapon_last": _key(KEY_Q),
		"weapon_next": _mouse(MOUSE_BUTTON_WHEEL_DOWN),
		"weapon_prev": _mouse(MOUSE_BUTTON_WHEEL_UP),
		"shop": _key(KEY_B),
		"command_view": _key(KEY_V),
		"scoreboard": _key(KEY_TAB),
		"select_unit": _key(KEY_E),
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		InputMap.action_add_event(action, bindings[action])


static func _key(keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	return ev


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	return ev


## Whether your keys and mouse drive the hero right now.
func _in_control() -> bool:
	var game := hero.game
	return game.started and not game.game_over and game.view_mode == "hero" and not game.menu.is_open() \
			and not game.hero_hud.shop_open and not build_menu_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## The peasants' build menu is up (you stand still while picking from it).
func build_menu_open() -> bool:
	var controller := hero.game.controller
	return controller.menu == "build" and controller.placing == "" and hero.game.view_mode == "hero"


func _close_build_menu() -> void:
	var controller := hero.game.controller
	controller.cancel_modes()
	controller.menu = ""
	controller.selection_changed.emit()


## E: select what's under the crosshair (tap) or add to the selection (hold).
func _process(_delta: float) -> void:
	if not _in_control() or hero.dead:
		return
	var controller := hero.game.controller
	if Input.is_action_just_pressed("select_unit"):
		var picked := controller.pick_ahead()
		controller.set_selection([picked] if picked else [])
	elif Input.is_action_pressed("select_unit"):
		var picked := controller.pick_ahead()
		if picked and not controller.selection.has(picked):
			var list := controller.selection.duplicate()
			list.append(picked)
			controller.set_selection(list)


## Mouse look in _input (not _unhandled_input) so HUD controls under the
## captured cursor can never swallow it.
func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and _in_control():
		hero.intent.yaw = wrapf(hero.intent.yaw - motion.relative.x * mouse_sensitivity, -PI, PI)
		hero.intent.pitch = clampf(hero.intent.pitch - motion.relative.y * mouse_sensitivity, deg_to_rad(-80.0), deg_to_rad(80.0))


func _unhandled_input(event: InputEvent) -> void:
	var game := hero.game
	if not game.started or game.game_over or game.view_mode != "hero":
		return
	var controller := game.controller
	if event.is_action_pressed("ui_cancel"):
		if controller.placing != "" or build_menu_open():
			_close_build_menu()
		elif game.hero_hud.shop_open:
			game.hero_hud.toggle_shop()
		else:
			game.menu.toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if game.menu.is_open():
		return
	if build_menu_open():
		# Structure hotkeys (they'd otherwise be movement or other hero keys;
		# B is the Barracks here, as in the Command View).
		var key := event as InputEventKey
		if key and key.pressed and not key.echo:
			controller.press_card_key(key)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("shop"):
		if controller.placing != "":
			_close_build_menu()
		elif controller.has_workers_selected() and not game.hero_hud.shop_open:
			controller.execute("build_menu")
		else:
			game.hero_hud.toggle_shop()
		get_viewport().set_input_as_handled()
		return
	if game.hero_hud.shop_open:
		return
	if controller.placing != "" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("attack"):
			_hold_fire = true
			controller.try_place(Input.is_key_pressed(KEY_SHIFT))
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("hook"):
			_hold_hook = true
			_close_build_menu()
			get_viewport().set_input_as_handled()
			return
	var button := event as InputEventMouseButton
	if button and button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	for slot in 3:
		if event.is_action_pressed("weapon_%d" % (slot + 1)):
			hero.intent.weapon_slot = slot
	if event.is_action_pressed("weapon_next"):
		hero.intent.weapon_cycle = 1
	elif event.is_action_pressed("weapon_prev"):
		hero.intent.weapon_cycle = -1
	elif event.is_action_pressed("weapon_last"):
		hero.intent.weapon_last = true


## Called by the hero at the start of each physics tick.
func update_intent(_delta: float) -> void:
	var intent := hero.intent
	if not _in_control():
		intent.clear()
		return
	intent.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	intent.jump = Input.is_action_pressed("jump")
	intent.gas = Input.is_action_pressed("gas")
	var placing := hero.game.controller.placing != ""
	_hold_fire = _hold_fire and Input.is_action_pressed("attack")
	_hold_hook = _hold_hook and Input.is_action_pressed("hook")
	intent.fire = Input.is_action_pressed("attack") and not placing and not _hold_fire
	intent.hook = Input.is_action_pressed("hook") and not placing and not _hold_hook
	intent.reel_in = Input.is_action_pressed("reel_in")
	intent.reel_out = Input.is_action_pressed("reel_out")
	intent.reload = Input.is_action_pressed("reload")
	intent.aim_point = hero.camera_rig.aim_point() if hero.camera_rig else Vector3.INF


func on_died() -> void:
	pass
