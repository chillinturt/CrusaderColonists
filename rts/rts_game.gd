class_name RTSGame
extends Node3D
## Root of a CrusaderClonists match: two teams of six heroes (you and eleven
## bots), each team with its own RTS base on a three-lane map.
##   Heroes (Hero)   third-person crusaders with Crusaders' movement and weapons.
##                   They earn gold and levels, respawn at their fountain, and
##                   stand in the RTS world through a HeroAvatar, so units and
##                   towers fight them like anything else.
##   The base (RTS)  peasants mine crystal and aether into the team's bank;
##                   structures and units cost it. Anyone can spend it from the
##                   Command View (V), and an AI commander (RTSAI) runs the enemy
##                   team and, if you like, yours.
##   The lanes (MOBA) every WAVE_INTERVAL each keep sends a minion wave down each
##                   lane. Waves grow with the team's base: every Barracks adds a
##                   knight, a Forge adds siege golems, an Aerie harpies, a
##                   Sanctum titans. Two towers guard each lane; the inner one is
##                   shielded until the outer falls, and the keep is shielded
##                   until a whole lane is broken.
## Destroy the enemy keep (the team's first, its core) to win.
## Owns the map, the fog, everything on the battlefield, both sides' resources
## and supply, and the rules. Input, menus and HUDs live in their own nodes.

const FOG_INTERVAL := 0.2
const BUCKET := 12.0
const START_CRYSTAL := 200
const START_PEASANTS := 8
const HEROES_PER_TEAM := 6
const WAVE_INTERVAL := 30.0
const FIRST_WAVE := 12.0
## Lane towers stand this far along their lane from the base (inner, outer).
const TOWER_DISTANCES: Array[float] = [38.0, 75.0]
const FOUNTAIN_RADIUS := 6.0
const PASSIVE_GOLD := 2.0
const HERO_KILL_GOLD := 150
const ASSIST_GOLD := 60
const STRUCTURE_GOLD := 120
const BOT_NAMES: Array[String] = ["Aldric", "Brienne", "Cedric", "Dagna", "Edmund", "Freya", "Gareth", "Hilde",
		"Ivo", "Jorun", "Kael", "Lysa", "Merek", "Nessa", "Osric", "Petra", "Roland", "Sigrid", "Tobias", "Ulla"]

## 0 = random.
@export var map_seed := 0

var map: RTSMap
var fog: RTSFog
var camera: RTSCamera
var controller: RTSController
var hud: RTSHud
var hero_hud: HeroHud
var menu: MatchMenu
## The AI commander of each team (null where nobody is assigned).
var ais: Array[RTSAI] = [null, null]
var entities: Array[RTSEntity] = []
var heroes: Array[Hero] = []
var local_hero: Hero
## The team you play (the RTS controls and HUD work for this team).
var local_team := 0
## "hero" (third person) or "command" (the top-down RTS view).
var view_mode := "hero"
var crystal: Array[int] = [START_CRYSTAL, START_CRYSTAL]
var aether: Array[int] = [0, 0]
## Gathering speed per team (the AI's difficulty).
var income_multiplier: Array[float] = [1.0, 1.0]
## Scales construction and training (for testing).
var build_speed := 1.0
var difficulty := 1
var time := 0.0
var started := false
var game_over := false
var winner := -1
## Each team's core keep.
var cores: Array[RTSStructure] = [null, null]
## team -> lane -> [inner tower, outer tower]
var towers: Array = [[[], [], []], [[], [], []]]
var fountains: Array[Vector3] = []
var team_kills: Array[int] = [0, 0]
var wave_timer := FIRST_WAVE
var wave_count := 0
## Minimap pings: [position, time left].
var pings: Array = []
## Bot-only run for testing (command line: -- --autotest). With
## --shots=<folder> it also saves screenshots of both views.
var autotest := false
var _shots_dir := ""

var _entities_root: Node3D
var _effects_root: Node3D
var _heroes_root: Node3D
var _buckets := {}
var _fog_timer := 0.0
var _alert_cooldown := 0.0
var _income_remainder: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _gold_remainder := 0.0
## Stands in for the fog texture in third person (nothing darkened).
var _white: ImageTexture
var _autotest_end := 600.0
var _report_timer := 30.0


func _ready() -> void:
	Combat.game = self
	HeroInput.setup_actions()
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	for arg in args:
		if arg.begins_with("--autotest-seconds="):
			_autotest_end = float(arg.get_slice("=", 1))
		elif arg.begins_with("--shots="):
			_shots_dir = arg.get_slice("=", 1)
	var white_image := Image.create(1, 1, false, Image.FORMAT_L8)
	white_image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(white_image)

	map = RTSMap.new()
	map.name = "Map"
	add_child(map)
	var seed_used := map_seed if map_seed != 0 else randi()
	print("Map seed: %d" % seed_used)
	map.generate(seed_used)

	_entities_root = Node3D.new()
	_entities_root.name = "Entities"
	add_child(_entities_root)
	_heroes_root = Node3D.new()
	_heroes_root.name = "Heroes"
	add_child(_heroes_root)
	_effects_root = Node3D.new()
	_effects_root.name = "Effects"
	add_child(_effects_root)

	fog = RTSFog.new()
	fog.setup(map)

	camera = RTSCamera.new()
	camera.name = "CommandCamera"
	add_child(camera)
	camera.setup(self)
	controller = RTSController.new()
	controller.name = "Controller"
	controller.game = self
	add_child(controller)
	hud = RTSHud.new()
	hud.name = "CommandHUD"
	add_child(hud)
	hud.setup(self)
	hud.visible = false
	hero_hud = HeroHud.new()
	hero_hud.name = "HeroHUD"
	add_child(hero_hud)
	hero_hud.setup(self)
	menu = MatchMenu.new()
	menu.name = "Menu"
	add_child(menu)
	menu.setup(self)

	for team in 2:
		fountains.append(map.fountain(team))
		_spawn_base(team)
	_update_shields()
	_rebuild_buckets()
	fog.update(entities, local_team)
	_set_fog_display(false)
	camera.focus_on(map.bases[local_team])
	get_tree().paused = true
	if autotest:
		Engine.time_scale = 3.0
		begin({"difficulty": 1, "ai_commander": true, "lane": 1, "loadout": ["rifle", "revolver", "machete"]})
	elif args.has("--quickstart"):
		begin({"difficulty": 1, "ai_commander": true, "lane": 1, "loadout": WeaponData.DEFAULT_LOADOUT.duplicate()})
	else:
		menu.show_start()
		for arg in args:
			if arg.begins_with("--menu-shot="):
				# Testing: save the start menu as it looks in this window, then quit.
				for i in 4:
					await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(arg.get_slice("=", 1))
				get_tree().quit()


func _exit_tree() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	RTSModels.clear_cache()


## Called from the start menu. settings: difficulty (0-2), ai_commander (whether
## an AI runs your team's base alongside you), lane (0-2), loadout (weapon ids).
func begin(settings: Dictionary) -> void:
	difficulty = settings.get("difficulty", 1)
	income_multiplier[1 - local_team] = [0.85, 1.0, 1.2][difficulty]
	for team in 2:
		if team != local_team or settings.get("ai_commander", true):
			var ai := RTSAI.new()
			ai.name = "Commander%d" % team
			ai.game = self
			add_child(ai)
			ai.setup(team, difficulty)
			ais[team] = ai
	_spawn_heroes(settings)
	started = true
	get_tree().paused = false
	set_view_mode("hero")
	hero_hud.notify("Push your lane with the minions. Destroy the enemy Keep to win.", Color(1.0, 0.9, 0.6))
	hero_hud.notify("V: Command View (build and train with the team's crystal)   B: shop at your fountain", Color(0.8, 0.9, 1.0))


func _spawn_base(team: int) -> void:
	var base := map.bases[team]
	var keep := spawn_structure("keep", team, map.snap(base, 4), true)
	cores[team] = keep
	for lane in 3:
		var path := map.lane_path(team, lane)
		var pair: Array = []
		for distance in TOWER_DISTANCES:
			var dir := RTSMap.direction_along(path, distance)
			var side := Vector3(dir.z, 0.0, -dir.x)
			var spot := map.snap(RTSMap.point_along(path, distance) + side * 4.5, 2)
			pair.append(spawn_structure("tower", team, spot, true))
		towers[team][lane] = pair
	var away := Vector3(base.x, 0.0, base.z).normalized()
	var side := Vector3(-away.z, 0.0, away.x)
	for i in START_PEASANTS:
		var at := base + away * 6.5 + side * (i - (START_PEASANTS - 1) * 0.5) * 1.3
		var peasant := spawn_unit("peasant", team, at)
		var crystal_node := free_crystal_near(at, 20.0, peasant)
		if crystal_node:
			peasant.command({"type": RTSUnit.Order.GATHER, "target": crystal_node, "phase": "go"})
	_default_rally(keep)
	_build_fountain(team)


## A glowing ring and a beam of light where the team's heroes respawn and heal.
func _build_fountain(team: int) -> void:
	var at := fountains[team]
	var color := RTSData.TEAM_COLORS[team]
	var root := Node3D.new()
	root.name = "Fountain%d" % team
	add_child(root)
	root.global_position = at
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var disc := CylinderMesh.new()
	disc.top_radius = FOUNTAIN_RADIUS
	disc.bottom_radius = FOUNTAIN_RADIUS
	disc.height = 0.15
	var pool := MeshInstance3D.new()
	pool.mesh = disc
	pool.material_override = material
	pool.position.y = 0.1
	root.add_child(pool)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.6
	beam.bottom_radius = 1.2
	beam.height = 30.0
	var pillar := MeshInstance3D.new()
	pillar.mesh = beam
	pillar.material_override = material
	pillar.position.y = 15.0
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pillar)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 10.0
	light.position.y = 2.0
	root.add_child(light)


func _spawn_heroes(settings: Dictionary) -> void:
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var lane_pick: int = settings.get("lane", 1)
	for team in 2:
		var lanes_left: Array[int] = [0, 0, 1, 1, 2, 2]
		if team == local_team:
			lanes_left.erase(lane_pick)
		for i in HEROES_PER_TEAM:
			var is_local := team == local_team and i == 0
			var hero_lane: int = lane_pick if is_local else lanes_left.pop_front()
			var loadout: Array = settings.get("loadout", WeaponData.DEFAULT_LOADOUT) if is_local else WeaponData.random_loadout()
			var hero := Hero.new()
			hero.name = "Hero_%d_%d" % [team, i]
			_heroes_root.add_child(hero)
			var hero_name: String = "You" if is_local and not autotest else names.pop_front()
			hero.setup(self, team, i, hero_name, is_local and not autotest, loadout, hero_lane)
			hero.global_position = spawn_spot(team, i)
			hero.intent.yaw = _facing_yaw(team)
			hero.rotation.y = hero.intent.yaw
			hero.reset_physics_interpolation()
			heroes.append(hero)
			entities.append(hero.avatar)
			if is_local:
				local_hero = hero
				if autotest:
					hero.attach_camera()


func spawn_spot(team: int, index: int) -> Vector3:
	var offset := Vector3.FORWARD.rotated(Vector3.UP, index * TAU / HEROES_PER_TEAM) * 3.0
	return map.ground(fountains[team] + offset) + Vector3.UP * 0.3


## Facing toward the middle of the map from a team's base.
func _facing_yaw(team: int) -> float:
	var to_middle := -map.bases[team]
	return atan2(-to_middle.x, -to_middle.z)


func _physics_process(delta: float) -> void:
	if not started or game_over:
		_rebuild_buckets()
		return
	time += delta
	_alert_cooldown -= delta
	_rebuild_buckets()
	_fog_timer -= delta
	if _fog_timer <= 0.0:
		_fog_timer = FOG_INTERVAL
		fog.update(entities, local_team)
		_apply_visibility()
	for ping: Array in pings:
		ping[1] -= delta
	pings = pings.filter(func(ping: Array) -> bool: return ping[1] > 0.0)
	_update_waves(delta)
	_update_fountains(delta)
	_gold_remainder += PASSIVE_GOLD * delta
	if _gold_remainder >= 1.0:
		var whole := floori(_gold_remainder)
		_gold_remainder -= whole
		for hero in heroes:
			hero.gold += whole
	if autotest:
		_autotest_tick(delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("command_view") and started and not game_over and not menu.is_open() and local_hero \
			and not autotest:
		set_view_mode("hero" if view_mode == "command" else "command")
		get_viewport().set_input_as_handled()


## Switches between playing your hero and the top-down Command View. Your hero
## stands still (and can be hit) while you command.
func set_view_mode(mode: String) -> void:
	if mode == "command" and local_hero == null:
		return
	view_mode = mode
	var commanding := mode == "command"
	camera.current = commanding
	if local_hero and local_hero.camera_rig:
		local_hero.camera_rig.camera.current = not commanding
	hud.visible = commanding
	hero_hud.set_commanding(commanding)
	controller.cancel_modes()
	if not commanding:
		controller.menu = ""  # the build menu would freeze your hero
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if commanding else Input.MOUSE_MODE_CAPTURED
	if commanding and local_hero:
		camera.focus_on(local_hero.global_position)
	_set_fog_display(commanding)
	_apply_visibility()


## The fog of war darkens the ground only in the Command View; in third person
## there's distance haze instead.
func _set_fog_display(commanding: bool) -> void:
	for material in map.fogged_materials:
		material.set_shader_parameter(&"fog_tex", fog.texture if commanding else _white)
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		world_env.environment.fog_enabled = not commanding
		world_env.environment.fog_density = map.biome.fog_density * 0.6


# --- Lanes --------------------------------------------------------------------

func _update_waves(delta: float) -> void:
	wave_timer -= delta
	if wave_timer > 0.0:
		return
	wave_timer = WAVE_INTERVAL
	wave_count += 1
	for team in 2:
		if cores[team] == null or cores[team].dead:
			continue
		for lane in 3:
			_spawn_wave(team, lane)


## What a team's next wave is made of: three knights and a dragoon, plus
## whatever its base adds.
func wave_kinds(team: int, lane: int) -> Array[String]:
	var kinds: Array[String] = ["knight", "knight", "knight", "dragoon"]
	var barracks := 0
	for entity in entities:
		if entity.team == team and entity.kind == "barracks" and (entity as RTSStructure).built:
			barracks += 1
	for i in mini(barracks, 3):
		kinds.append("knight" if i != 1 else "dragoon")
	if has_built(team, "forge") and wave_count % 2 == 0:
		kinds.append("golem")
	if has_built(team, "aerie"):
		kinds.append("harpy")
	if has_built(team, "sanctum") and lane == 1 and wave_count % 4 == 0:
		kinds.append("titan")
	if time > 900.0:
		kinds.append("knight")
	return kinds


func _spawn_wave(team: int, lane: int) -> void:
	var path := map.lane_path(team, lane)
	var core := cores[team]
	var out := RTSEntity.flat(path[1] - path[0]).normalized()
	var side := Vector3(-out.z, 0.0, out.x)
	var kinds := wave_kinds(team, lane)
	for i in kinds.size():
		var at := core.global_position + out * (core.radius + 2.5 + floori(i / 3.0) * 1.6) + side * ((i % 3) - 1) * 1.4
		var unit := spawn_unit(kinds[i], team, at)
		unit.lane = lane
		for p in range(1, path.size()):
			unit.command({"type": RTSUnit.Order.ATTACK_MOVE, "pos": path[p], "spread": 3.0}, p > 1)


func _update_fountains(delta: float) -> void:
	for hero in heroes:
		hero.in_fountain = false
		if hero.dead:
			continue
		for team in 2:
			var offset := hero.global_position - fountains[team]
			if RTSEntity.flat(offset).length() > FOUNTAIN_RADIUS or absf(offset.y) > 8.0:
				continue
			if hero.team == team:
				hero.in_fountain = true
				hero.heal(hero.max_health * 0.3 * delta)
			else:
				Combat.deal(hero, 300.0 * delta, null, fountains[team])


## Inner towers are shielded while the outer one in their lane stands; the
## keep is shielded until some lane has lost both.
func _update_shields() -> void:
	for team in 2:
		var lane_broken := false
		for lane in 3:
			var pair: Array = towers[team][lane]
			var outer_alive: bool = pair[1] != null and not pair[1].dead
			var inner_alive: bool = pair[0] != null and not pair[0].dead
			if inner_alive:
				(pair[0] as RTSStructure).set_shielded(outer_alive)
			if not inner_alive and not outer_alive:
				lane_broken = true
		if is_instance_valid(cores[team]) and not cores[team].dead:
			cores[team].set_shielded(not lane_broken)


# --- Spawning -----------------------------------------------------------------

func spawn_unit(kind: String, team: int, at: Vector3) -> RTSUnit:
	var unit := RTSUnit.new()
	unit.name = kind.capitalize()
	_entities_root.add_child(unit)
	var def := RTSData.unit(kind)
	var spot := at if def.get("flying", false) else map.nav.nearest_open_point(at)
	unit.global_position = map.ground(map.clamp_to_play_area(spot))
	unit.setup(self, team, kind, def)
	unit.reset_physics_interpolation()
	entities.append(unit)
	_refresh_visibility(unit)
	return unit


func spawn_structure(kind: String, team: int, center: Vector3, built: bool) -> RTSStructure:
	var cells: int = RTSData.structure(kind).size
	var origin := map.footprint_origin(center, cells)
	var structure := RTSStructure.new()
	structure.name = kind.capitalize()
	_entities_root.add_child(structure)
	structure.global_position = map.footprint_center(origin, cells)
	structure.setup_structure(self, team, kind, origin, built)
	structure.reset_physics_interpolation()
	if RTSData.structure(kind).get("on_vent", false):
		var vent := vent_at(structure.global_position)
		if vent:
			vent.extractor = structure
			structure.vent = vent
	entities.append(structure)
	_refresh_visibility(structure)
	return structure


## Places a (prepaid) structure for construction. Null if the spot isn't free.
func construct(team: int, kind: String, center: Vector3) -> RTSStructure:
	if not can_place(team, kind, center):
		return null
	var structure := spawn_structure(kind, team, center, false)
	# Shove anyone standing on the footprint out of the way.
	for entity in nearby(structure.global_position, structure.radius + 1.0):
		if entity is RTSUnit and not entity.flying and not entity.dead:
			if not map.nav.walkable(entity.global_position):
				entity.global_position = map.ground(map.nav.nearest_open_point(entity.global_position))
	return structure


func spawn_trained(structure: RTSStructure, kind: String) -> void:
	var toward := Vector3.BACK
	if structure.rally != Vector3.INF:
		toward = RTSEntity.flat(structure.rally - structure.global_position).normalized()
	var at := structure.global_position + toward * (structure.radius + 1.2)
	var unit := spawn_unit(kind, structure.team, at)
	var target := structure.rally_target
	if is_instance_valid(target) and unit.is_worker and not target.get("dead"):
		unit.command({"type": RTSUnit.Order.GATHER, "target": target, "phase": "go"})
	elif structure.rally != Vector3.INF:
		var order_type := RTSUnit.Order.ATTACK_MOVE if structure.team != local_team or ais[local_team] else RTSUnit.Order.MOVE
		unit.command({"type": order_type, "pos": structure.rally, "spread": 2.0})
	if structure.team == local_team and view_mode == "command":
		hud.flash_message("%s ready." % unit.display_name(), false)


func _default_rally(keep: RTSStructure) -> void:
	var crystal_node := free_crystal_near(keep.global_position, 18.0, null)
	if crystal_node:
		keep.rally_target = crystal_node
		keep.rally = crystal_node.global_position


# --- Rules --------------------------------------------------------------------

func supply_cap(team: int) -> int:
	var total := 0
	for entity in entities:
		if entity.team == team and entity is RTSStructure:
			total += (entity as RTSStructure).supply_provided()
	return mini(total, RTSData.MAX_SUPPLY)


## Units alive plus units in production (lane minions are free).
func supply_used(team: int) -> int:
	var total := 0
	for entity in entities:
		if entity.team != team:
			continue
		if entity is RTSUnit:
			if (entity as RTSUnit).lane < 0:
				total += int(entity.def.supply)
		elif entity is RTSStructure:
			for kind in (entity as RTSStructure).queue:
				total += int(RTSData.unit(kind).supply)
	return total


func has_built(team: int, kind: String) -> bool:
	for entity in entities:
		if entity.team == team and entity.kind == kind and entity is RTSStructure and (entity as RTSStructure).built:
			return true
	return false


func count(team: int, kind: String) -> int:
	var total := 0
	for entity in entities:
		if entity.team == team and entity.kind == kind:
			total += 1
	return total


## "" if it's unlocked, else what's missing.
func missing_tech(team: int, kind: String) -> String:
	var requires: String = RTSData.any(kind).get("requires", "")
	if requires == "" or has_built(team, requires):
		return ""
	return RTSData.structure(requires).name


func can_afford(team: int, kind: String) -> bool:
	var def := RTSData.any(kind)
	return crystal[team] >= int(def.get("crystal", 0)) and aether[team] >= int(def.get("aether", 0))


## "" if `team` can pay for `kind` now, else why not.
func afford_problem(team: int, kind: String) -> String:
	var def := RTSData.any(kind)
	if crystal[team] < int(def.get("crystal", 0)):
		return "Not enough crystal."
	if aether[team] < int(def.get("aether", 0)):
		return "Not enough aether."
	return ""


func spend(team: int, kind: String) -> void:
	var def := RTSData.any(kind)
	crystal[team] -= int(def.get("crystal", 0))
	aether[team] -= int(def.get("aether", 0))


func refund(team: int, kind: String, fraction := 1.0) -> void:
	var def := RTSData.any(kind)
	crystal[team] += roundi(int(def.get("crystal", 0)) * fraction)
	aether[team] += roundi(int(def.get("aether", 0)) * fraction)


func add_income(team: int, kind: String, amount: int) -> void:
	var slot := team * 2 + (0 if kind == "crystal" else 1)
	var total := amount * income_multiplier[team] + _income_remainder[slot]
	var whole := floori(total)
	_income_remainder[slot] = total - whole
	if kind == "crystal":
		crystal[team] += whole
	else:
		aether[team] += whole


## Queues a unit. "" on success, else why not.
func queue_train(structure: RTSStructure, kind: String) -> String:
	var team := structure.team
	var def := RTSData.unit(kind)
	if not structure.built:
		return "Still under construction."
	if structure.queue.size() >= RTSData.MAX_QUEUE:
		return "The queue is full."
	var missing := missing_tech(team, kind)
	if missing != "":
		return "Requires a %s." % missing
	if supply_used(team) + int(def.supply) > supply_cap(team):
		return "Supply limit reached." if supply_cap(team) >= RTSData.MAX_SUPPLY else "Not enough supply: build more Farmsteads."
	var problem := afford_problem(team, kind)
	if problem != "":
		return problem
	spend(team, kind)
	structure.queue.append(kind)
	return ""


func cancel_train(structure: RTSStructure, index := -1) -> void:
	if structure.queue.is_empty():
		return
	if index < 0:
		index = structure.queue.size() - 1
	refund(structure.team, structure.queue[index])
	structure.queue.remove_at(index)
	if index == 0:
		structure.train_time = 0.0


## Cancelling a structure under construction gives back 75%.
func cancel_construction(structure: RTSStructure) -> void:
	if structure.built or structure.dead:
		return
	refund(structure.team, structure.kind, 0.75)
	structure.die()


## Snaps a spot to where `kind` would go (extractors jump onto the nearest vent).
func snap_placement(kind: String, pos: Vector3) -> Vector3:
	if RTSData.structure(kind).get("on_vent", false):
		var vent := vent_at(pos, 6.0)
		if vent:
			return vent.global_position
	return map.snap(pos, RTSData.structure(kind).size)


func can_place(team: int, kind: String, center: Vector3) -> bool:
	var def := RTSData.structure(kind)
	if team == local_team and not fog.is_explored(center):
		return false
	if def.get("on_vent", false):
		var vent := vent_at(center, 0.5)
		return vent != null and vent.extractor == null
	var cells: int = def.size
	var origin := map.footprint_origin(center, cells)
	if not map.in_play_area(center, cells * map.cell * 0.5 + 2.0) or not map.footprint_clear(origin, cells):
		return false
	var snapped := map.footprint_center(origin, cells)
	if kind == "keep":
		for resource in map.resources:
			if is_instance_valid(resource) and not resource.dead and RTSEntity.flat(resource.global_position - snapped).length() < 9.0:
				return false
	var half := cells * map.cell * 0.5
	for f in fountains:
		if RTSEntity.flat(f - snapped).length() < FOUNTAIN_RADIUS + half:
			return false
	for entity in nearby(snapped, half + 1.5):
		if entity.team != team and entity is RTSUnit and not entity.flying:
			var offset := entity.global_position - snapped
			if absf(offset.x) < half + entity.radius and absf(offset.z) < half + entity.radius:
				return false
	for hero in heroes:
		var offset := hero.global_position - snapped
		if not hero.dead and absf(offset.x) < half + 0.5 and absf(offset.z) < half + 0.5 and absf(offset.y) < 4.0:
			return false
	return true


func vent_at(pos: Vector3, within := 3.0) -> RTSResource:
	var best: RTSResource = null
	var best_distance := within
	for resource in map.resources:
		if is_instance_valid(resource) and resource.kind == "vent":
			var d := RTSEntity.flat(resource.global_position - pos).length()
			if d <= best_distance:
				best = resource
				best_distance = d
	return best


func nearest_dropoff(team: int, pos: Vector3) -> RTSStructure:
	var best: RTSStructure = null
	var best_distance := INF
	for entity in entities:
		if entity.team == team and entity is RTSStructure and entity.def.get("dropoff", false) and (entity as RTSStructure).built:
			var d := entity.global_position.distance_squared_to(pos)
			if d < best_distance:
				best = entity
				best_distance = d
	return best


## The closest crystal to `pos` (within `within`) that nobody else is mining,
## or failing that the closest one at all.
func free_crystal_near(pos: Vector3, within: float, asker: Node3D) -> RTSResource:
	var best: RTSResource = null
	var best_score := INF
	for resource in map.resources:
		if not is_instance_valid(resource) or resource.dead or resource.kind != "crystal":
			continue
		var d := RTSEntity.flat(resource.global_position - pos).length()
		if d > within:
			continue
		var busy := is_instance_valid(resource.miner) and resource.miner != asker
		var score := d + (20.0 if busy else 0.0)
		if score < best_score:
			best = resource
			best_score = score
	return best


# --- Combat -------------------------------------------------------------------

## The enemy `seeker` would most like to attack within `reach` of its center
## (to the target's edge): ones that fight back first, then the nearest.
## Towers and keeps leave heroes alone unless they've been attacking heroes.
func find_target(seeker: RTSEntity, reach: float) -> RTSEntity:
	var best: RTSEntity = null
	var best_score := INF
	for entity in nearby(seeker.global_position, reach):
		if entity.dead or entity.team == seeker.team or entity.tucked_away or not seeker.can_hit(entity):
			continue
		if not is_visible_to(seeker.team, entity):
			continue
		var d := RTSEntity.flat(entity.global_position - seeker.global_position).length() - entity.radius
		if d > reach:
			continue
		var score := d
		if entity is HeroAvatar:
			if seeker.is_structure and not (entity as HeroAvatar).hero.is_aggressive():
				score += 25.0
		elif entity.is_structure:
			score += 30.0 if not entity.can_attack() else 5.0
		elif not entity.can_attack() or (entity as RTSUnit).is_worker:
			score += 8.0
		if score < best_score:
			best = entity
			best_score = score
	return best


func fire(attacker: RTSEntity, target: RTSEntity, kind: String) -> void:
	var projectile := RTSProjectile.new()
	_effects_root.add_child(projectile)
	projectile.launch(self, attacker, target, kind)


## An attack lands: on its target, or on everything nearby with splash.
func impact(attacker: RTSEntity, team: int, attack_def: Dictionary, target: RTSEntity, point: Vector3) -> void:
	var damage: float = attack_def.damage
	var splash: float = attack_def.get("splash", 0.0)
	if splash > 0.0:
		for entity in nearby(point, splash):
			if entity.dead or entity.team == team or entity.tucked_away:
				continue
			if (entity.flying and not attack_def.get("air", false)) or (not entity.flying and not attack_def.get("ground", false)):
				continue
			var d := RTSEntity.flat(entity.global_position - point).length() - entity.radius
			if d > splash:
				continue
			var share := 1.0 if entity == target or d <= splash * 0.4 else 0.5
			entity.take_damage(maxf(0.5, damage * share - entity.armor), attacker)
		Explosion.spawn_fx(_effects_root, point + Vector3.UP * 0.4, splash * 0.6)
	elif target != null and is_instance_valid(target) and not target.dead:
		target.take_damage(maxf(0.5, damage - target.armor), attacker)


func on_damaged(entity: RTSEntity, attacker: RTSEntity) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.dead:
		return
	# Idle friends nearby join in.
	for friend in nearby(entity.global_position, 10.0):
		if friend.team == entity.team and friend is RTSUnit and friend != entity:
			(friend as RTSUnit).help_against(attacker)
	# Alerts are for the base (lanes are always under attack).
	var base_hit := (entity is RTSStructure and entity.kind != "tower") or (entity is RTSUnit and (entity as RTSUnit).is_worker)
	if entity.team == local_team and base_hit and _alert_cooldown <= 0.0 and not (view_mode == "command" and camera.sees(entity.global_position)):
		_alert_cooldown = 15.0
		pings.append([entity.global_position, 3.0])
		hud.flash_message("Your base is under attack!", true)
		hud.last_alert = entity.global_position
	var ai := ais[entity.team]
	if ai:
		ai.on_attacked(entity, attacker)


## Whoever's behind an attack, if it's a hero. (Untyped: the attacker may
## have been freed since.)
static func hero_of(attacker: Variant) -> Hero:
	if not is_instance_valid(attacker):
		return null
	if attacker is HeroAvatar:
		return (attacker as HeroAvatar).hero
	if attacker is Hero:
		return attacker as Hero
	return null


func on_entity_died(entity: RTSEntity) -> void:
	entities.erase(entity)
	controller.forget(entity)
	var killer := hero_of(entity.last_attacker)
	if entity is RTSUnit:
		if killer:
			killer.last_hits += 1
			killer.add_gold(RTSData.bounty(entity.kind))
		# Experience for every enemy hero close by.
		var xp := 10.0 + 8.0 * float(entity.def.get("supply", 1))
		for hero in heroes:
			if hero.team != entity.team and not hero.dead and hero.global_position.distance_to(entity.global_position) < 25.0:
				hero.add_xp(xp)
	elif entity.is_structure:
		var structure := entity as RTSStructure
		if structure == cores[entity.team]:
			cores[entity.team] = null
			_end(1 - entity.team)
			return
		# Forget dead towers (so nothing reads them once they're freed).
		for lane in 3:
			var pair: Array = towers[entity.team][lane]
			for i in pair.size():
				if pair[i] == structure:
					pair[i] = null
		if structure.kind == "tower" or structure.built:
			for hero in heroes:
				if hero.team != entity.team:
					hero.add_gold(STRUCTURE_GOLD if structure.kind == "tower" else STRUCTURE_GOLD / 3)
			var by := killer.hero_name if killer else RTSData.TEAM_NAMES[1 - entity.team]
			hero_hud.add_feed("%s destroyed a %s %s" % [by, RTSData.TEAM_NAMES[entity.team], structure.display_name()],
					RTSData.TEAM_COLORS[1 - entity.team])
		_update_shields()


func on_structure_built(structure: RTSStructure) -> void:
	if structure.kind == "keep":
		_default_rally(structure)
	if structure.team == local_team and view_mode == "command":
		hud.flash_message("%s complete." % structure.display_name(), false)


## A hero fell. `killer` is the hero who finished them (if any), `assists` the
## others who hurt them lately, `cause` whatever landed the last hit.
func on_hero_died(victim: Hero, killer: Hero, assists: Array[Hero], cause: Variant) -> void:
	entities.erase(victim.avatar)
	team_kills[1 - victim.team] += 1
	var text := ""
	if killer:
		killer.kills += 1
		killer.add_gold(HERO_KILL_GOLD + 10 * victim.level, "kill")
		killer.add_xp(60.0 + 20.0 * victim.level)
		text = "%s killed %s" % [killer.hero_name, victim.hero_name]
	elif is_instance_valid(cause) and cause is RTSEntity:
		text = "%s was slain by a %s" % [victim.hero_name, (cause as RTSEntity).display_name()]
	else:
		text = "%s died" % victim.hero_name
	for helper in assists:
		helper.assists += 1
		helper.add_gold(ASSIST_GOLD, "assist")
		helper.add_xp(30.0 + 10.0 * victim.level)
	hero_hud.add_feed(text, RTSData.TEAM_COLORS[1 - victim.team])


func on_hero_respawned(hero: Hero) -> void:
	if not entities.has(hero.avatar):
		entities.append(hero.avatar)


func notify(team: int, text: String) -> void:
	if team == local_team:
		hud.flash_message(text, true)


# --- Visibility ---------------------------------------------------------------

func fog_visible(pos: Vector3) -> bool:
	return game_over or fog.is_visible(pos)


## Whether `team` can see `entity` (the AI sees what its units are near anyway).
func is_visible_to(team: int, entity: RTSEntity) -> bool:
	if team != local_team or entity.team == local_team:
		return true
	return fog_visible(entity.global_position)


func _apply_visibility() -> void:
	for entity in entities:
		_refresh_visibility(entity)
	for hero in heroes:
		hero.visible = not hero.dead and (view_mode == "hero" or hero.team == local_team or fog_visible(hero.global_position))


func _refresh_visibility(entity: RTSEntity) -> void:
	if entity is HeroAvatar:
		return
	if entity.tucked_away:
		entity.visible = false
	elif entity.team == local_team or view_mode == "hero":
		entity.visible = true
		if entity.is_structure and fog_visible(entity.global_position):
			entity.discovered = true
	elif entity.is_structure:
		if fog_visible(entity.global_position):
			entity.discovered = true
		entity.visible = entity.discovered
	else:
		entity.visible = fog_visible(entity.global_position)


# --- Spatial lookup -------------------------------------------------------------

func _rebuild_buckets() -> void:
	_buckets.clear()
	for entity in entities:
		var key := Vector2i(floori(entity.global_position.x / BUCKET), floori(entity.global_position.z / BUCKET))
		if _buckets.has(key):
			_buckets[key].append(entity)
		else:
			_buckets[key] = [entity]


## Entities whose footprint comes within `reach` of `pos` (on the ground plane).
func nearby(pos: Vector3, reach: float) -> Array[RTSEntity]:
	var result: Array[RTSEntity] = []
	var span := reach + 5.0
	var x0 := floori((pos.x - span) / BUCKET)
	var x1 := floori((pos.x + span) / BUCKET)
	var z0 := floori((pos.z - span) / BUCKET)
	var z1 := floori((pos.z + span) / BUCKET)
	for bx in range(x0, x1 + 1):
		for bz in range(z0, z1 + 1):
			var bucket: Variant = _buckets.get(Vector2i(bx, bz))
			if bucket == null:
				continue
			for entity: RTSEntity in bucket:
				if not is_instance_valid(entity):
					continue
				var dx := entity.global_position.x - pos.x
				var dz := entity.global_position.z - pos.z
				var limit := reach + entity.radius
				if dx * dx + dz * dz <= limit * limit:
					result.append(entity)
	return result


# --- End of the game ------------------------------------------------------------

func _end(winning_team: int) -> void:
	if game_over:
		return
	game_over = true
	winner = winning_team
	fog.reveal_all()
	if view_mode == "command":
		_set_fog_display(true)
	_apply_visibility()
	hero_hud.add_feed("The %s keep has fallen!" % RTSData.TEAM_NAMES[1 - winning_team], RTSData.TEAM_COLORS[winning_team])
	if autotest:
		_autotest_report()
		print("AUTOTEST: %s won at %s" % [RTSData.TEAM_NAMES[winning_team], HeroHud.clock(time)])
		get_tree().quit()
		return
	menu.show_end(winning_team == local_team)


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# --- Testing ------------------------------------------------------------------

func _autotest_tick(delta: float) -> void:
	if _shots_dir != "":
		for at: float in [20.0, 45.0, 75.0]:
			if time - delta < at and time >= at:
				_take_shots(int(at))
	_report_timer -= delta
	if _report_timer <= 0.0:
		_report_timer = 30.0
		_autotest_report()
	if time >= _autotest_end:
		_autotest_report()
		print("AUTOTEST: time limit reached, no winner")
		get_tree().quit()


## Saves what the hero view and the Command View look like right now.
func _take_shots(tag: int) -> void:
	for mode: String in ["hero", "command"]:
		set_view_mode(mode)
		if mode == "command":
			camera.focus_on(local_hero.global_position)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := "%s/%s_%03d.png" % [_shots_dir, mode, tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved ", path)
	set_view_mode("hero")


func _autotest_report() -> void:
	var lines := PackedStringArray()
	lines.append("--- %s  wave %d  kills %d-%d  entities %d" % [HeroHud.clock(time), wave_count, team_kills[0], team_kills[1], entities.size()])
	for team in 2:
		var standing := 0
		for lane in 3:
			for tower: Variant in towers[team][lane]:
				if tower != null:
					standing += 1
		lines.append("  %s: crystal %d aether %d supply %d/%d towers %d keep %d%s" % [RTSData.TEAM_NAMES[team], crystal[team],
				aether[team], supply_used(team), supply_cap(team), standing, ceili(cores[team].hp) if is_instance_valid(cores[team]) else 0,
				" (shielded)" if is_instance_valid(cores[team]) and cores[team].shielded else ""])
	for hero in heroes:
		lines.append("  [%d] %-8s lane %d lvl %d gold %d  K/D/A %d/%d/%d  LH %d  %s" % [hero.team, hero.hero_name, hero.lane, hero.level,
				hero.gold, hero.kills, hero.deaths, hero.assists, hero.last_hits, hero.status_text()])
	print("\n".join(lines))
