class_name RTSMap
extends Node3D
## A symmetric 6v6 battlefield, built with the action game's pieces: its biomes
## (ground colors, trees, sky), heightmap approach and nav grid.
##   - gentle hills (point-symmetric, so neither side has better ground), rising
##     into mountains at the edge, with invisible walls at the play area's rim
##   - two main bases in opposite corners, each with a keep (the team's core),
##     a crystal line, two aether vents, and a fountain where heroes respawn
##   - three lanes between them (two around the edges, one through the middle)
##     that minion waves walk and lane towers guard
##   - two expansions per side in the wilds between the lanes
##   - forests and rock spires everywhere else
## Everything is mirrored through the center: (x, z) <-> (-x, -z).
## Unlike the RTS this came from, heroes walk here: the terrain, trees, rocks
## and walls all have collision.

const FOG_SHADER := preload("res://rts/fogged.gdshader")
const BIOMES: Array[Biome] = [
	preload("res://world/biomes/grasslands.tres"),
	preload("res://world/biomes/snowy_forest.tres"),
	preload("res://world/biomes/desert.tres"),
	preload("res://world/biomes/autumn_woods.tres"),
]
## Team 0's main base (team 1's is this negated). Odd coordinates: that's where
## a keep's 4x4 footprint snaps exactly.
const MAIN := Vector2(-83, -83)
## Team 0's expansions (team 1's are these negated).
const HALF_EXPANSIONS: Array[Vector2] = [Vector2(-71, 13), Vector2(13, -71)]
## Lane 0 from team 0's base to team 1's, around the -x / +z edges. Lane 2 is
## its mirror image (reversed so it also starts at team 0), lane 1 runs straight
## through the middle.
const EDGE_LANE: Array[Vector2] = [Vector2(-83, -83), Vector2(-94, -55), Vector2(-94, 70), Vector2(-70, 94),
		Vector2(55, 94), Vector2(83, 83)]
const MAIN_RADIUS := 22.0
const EXPANSION_RADIUS := 14.0
const FOUNTAIN_DISTANCE := 15.0
const MOUNTAIN_HEIGHT := 30.0
const WALL_HEIGHT := 300.0

var size := 256.0
var cell := 2.0
var play_radius := 110.0
var n := 0
var heights := PackedFloat32Array()
var nav: RTSNav
var biome: Biome
var map_texture: ImageTexture
## Base centers: [team 0 main, team 1 main, then expansions in mirrored pairs
## (team 0's, then its mirror)].
var bases: Array[Vector3] = []
## Lane paths in team 0's direction (index = lane), on the ground.
var lanes: Array[PackedVector3Array] = []
var resources: Array[RTSResource] = []
## Every fogged scenery material, so the fog can hand them its texture.
var fogged_materials: Array[ShaderMaterial] = []

var rng := RandomNumberGenerator.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _dirt := PackedFloat32Array()
## [center: Vector2, radius: float, height: float]
var _pads: Array = []
## [a: Vector2, b: Vector2]
var _roads: Array = []
## [center: Vector2, radius: float]
var _occupied: Array = []
var _material_cache := {}


func generate(map_seed: int) -> void:
	rng.seed = map_seed
	biome = BIOMES[rng.randi() % BIOMES.size()]
	n = int(size / cell) + 1
	for noise: FastNoiseLite in [_hills, _detail, _forest]:
		noise.seed = rng.randi()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.008
	_hills.fractal_octaves = 3
	_detail.frequency = 0.05
	_forest.frequency = 0.014
	_forest.fractal_octaves = 3

	_plan_layout()
	_build_heights()
	_apply_atmosphere()
	_build_terrain()
	_build_boundary()
	_build_nav()
	_scatter_spires()
	_scatter_trees()
	nav.snapshot_static()
	_place_resources()
	for path in lanes:
		for i in path.size():
			path[i] = ground(path[i])


# --- Queries ------------------------------------------------------------------

## Ground height at a world XZ position.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + size * 0.5) / cell, 0.0, n - 1.001)
	var fz := clampf((z + size * 0.5) / cell, 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * n + i]
	var h10 := heights[j * n + i + 1]
	var h01 := heights[(j + 1) * n + i]
	var h11 := heights[(j + 1) * n + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func ground(pos: Vector3) -> Vector3:
	return Vector3(pos.x, height_at(pos.x, pos.z), pos.z)


func in_play_area(pos: Vector3, margin := 0.0) -> bool:
	return maxf(absf(pos.x), absf(pos.z)) <= play_radius - margin


func clamp_to_play_area(pos: Vector3, margin := 2.0) -> Vector3:
	var limit := play_radius - margin
	return Vector3(clampf(pos.x, -limit, limit), pos.y, clampf(pos.z, -limit, limit))


## Where a ray (from the camera) meets the ground. Marches the heightmap, so no
## physics is needed. INF if it never comes down.
func ray_ground(origin: Vector3, direction: Vector3) -> Vector3:
	if direction.y >= -0.001:
		return Vector3.INF
	var step := 1.0
	var p := origin
	var prev := origin
	for i in 600:
		prev = p
		p += direction * step
		if p.y <= height_at(p.x, p.z):
			# Refine between the last point above and this one below.
			var lo := prev
			var hi := p
			for k in 8:
				var mid := (lo + hi) * 0.5
				if mid.y <= height_at(mid.x, mid.z):
					hi = mid
				else:
					lo = mid
			return hi
	return Vector3.INF


## A lane's path for `team`: from its own base to the enemy's.
func lane_path(team: int, lane: int) -> PackedVector3Array:
	var path := lanes[lane].duplicate()
	if team == 1:
		path.reverse()
	return path


## The point `distance` meters along a path (its end if the path is shorter).
static func point_along(path: PackedVector3Array, distance: float) -> Vector3:
	for i in range(1, path.size()):
		var segment := path[i].distance_to(path[i - 1])
		if distance <= segment:
			return path[i - 1].lerp(path[i], distance / maxf(segment, 0.001))
		distance -= segment
	return path[path.size() - 1]


## Direction of travel along a path at `distance` meters in (flat).
static func direction_along(path: PackedVector3Array, distance: float) -> Vector3:
	for i in range(1, path.size()):
		var segment := path[i].distance_to(path[i - 1])
		if distance <= segment or i == path.size() - 1:
			var d := path[i] - path[i - 1]
			return Vector3(d.x, 0.0, d.z).normalized()
		distance -= segment
	return Vector3.FORWARD


## How far along a path the point nearest to `pos` is, and how far off it `pos` is.
static func progress_on(path: PackedVector3Array, pos: Vector3) -> Vector2:
	var best_off := INF
	var best_along := 0.0
	var walked := 0.0
	var p := Vector2(pos.x, pos.z)
	for i in range(1, path.size()):
		var a := Vector2(path[i - 1].x, path[i - 1].z)
		var b := Vector2(path[i].x, path[i].z)
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		var off := closest.distance_to(p)
		if off < best_off:
			best_off = off
			best_along = walked + a.distance_to(closest)
		walked += a.distance_to(b)
	return Vector2(best_along, best_off)


static func path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	return total


## Where `team`'s heroes respawn and heal: beside the keep.
func fountain(team: int) -> Vector3:
	var main := Vector2(bases[team].x, bases[team].z)
	var spot := main + main.normalized().rotated(PI * 0.5) * FOUNTAIN_DISTANCE
	return ground(Vector3(spot.x, 0.0, spot.y))


func near_lane(pos: Vector3, margin: float) -> bool:
	return _near_road(Vector2(pos.x, pos.z), margin)


# --- Footprints (structures and vents snap to the nav grid) --------------------

## Top-left nav cell of a square footprint `cells` wide centered near `center`.
func footprint_origin(center: Vector3, cells: int) -> Vector2i:
	var offset := (cells - 1) * 0.5
	return Vector2i(roundi((center.x + size * 0.5) / cell - offset), roundi((center.z + size * 0.5) / cell - offset))


func footprint_center(origin: Vector2i, cells: int) -> Vector3:
	var x := -size * 0.5 + (origin.x + (cells - 1) * 0.5) * cell
	var z := -size * 0.5 + (origin.y + (cells - 1) * 0.5) * cell
	return Vector3(x, height_at(x, z), z)


func snap(pos: Vector3, cells: int) -> Vector3:
	return footprint_center(footprint_origin(pos, cells), cells)


func footprint(origin: Vector2i, cells: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for j in cells:
		for i in cells:
			result.append(origin + Vector2i(i, j))
	return result


## Whether a footprint is on open, flat ground (ignores units).
func footprint_clear(origin: Vector2i, cells: int) -> bool:
	var low := INF
	var high := -INF
	for c in footprint(origin, cells):
		if nav.is_solid(c):
			return false
		var h := heights[c.y * n + c.x]
		low = minf(low, h)
		high = maxf(high, h)
	return high - low <= 1.6


# --- Materials ----------------------------------------------------------------

## A scenery material that darkens under the fog (shared per color).
func fogged_material(color: Color, emission := Color.BLACK, roughness := 0.9, vertex_color := false) -> ShaderMaterial:
	var key := "%s|%s|%s|%s" % [color.to_html(), emission.to_html(), roughness, vertex_color]
	if _material_cache.has(key):
		return _material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = FOG_SHADER
	material.set_shader_parameter(&"albedo", color)
	material.set_shader_parameter(&"emission", emission)
	material.set_shader_parameter(&"roughness", roughness)
	material.set_shader_parameter(&"use_vertex_color", vertex_color)
	_material_cache[key] = material
	fogged_materials.append(material)
	return material


# --- Layout -------------------------------------------------------------------

func _plan_layout() -> void:
	bases.clear()
	lanes.clear()
	_pads.clear()
	_roads.clear()
	_occupied.clear()
	for p: Vector2 in [MAIN, -MAIN]:
		bases.append(Vector3(p.x, 0.0, p.y))
		_occupied.append([p, MAIN_RADIUS + 2.0])
	for p in HALF_EXPANSIONS:
		for q: Vector2 in [p, -p]:
			bases.append(Vector3(q.x, 0.0, q.y))
			_occupied.append([q, EXPANSION_RADIUS + 3.0])
			# A road from the nearer main.
			var main := MAIN if q.distance_to(MAIN) < q.distance_to(-MAIN) else -MAIN
			_roads.append([main, q])

	var edge := PackedVector3Array()
	var mirrored := PackedVector3Array()
	for p in EDGE_LANE:
		edge.append(Vector3(p.x, 0.0, p.y))
		mirrored.append(Vector3(-p.x, 0.0, -p.y))
	mirrored.reverse()
	lanes.append(edge)
	lanes.append(PackedVector3Array([Vector3(MAIN.x, 0.0, MAIN.y), Vector3.ZERO, Vector3(-MAIN.x, 0.0, -MAIN.y)]))
	lanes.append(mirrored)
	for path in lanes:
		for i in range(1, path.size()):
			_roads.append([Vector2(path[i - 1].x, path[i - 1].z), Vector2(path[i].x, path[i].z)])
	for team in 2:
		var main := MAIN if team == 0 else -MAIN
		var spot := main + main.normalized().rotated(PI * 0.5) * FOUNTAIN_DISTANCE
		_occupied.append([spot, 7.0])


func _base_2d(index: int) -> Vector2:
	return Vector2(bases[index].x, bases[index].z)


func _raw_height(x: float, z: float) -> float:
	return _hills.get_noise_2d(x, z) * biome.hill_height * 0.6 + _detail.get_noise_2d(x, z) * 0.4


func _base_height(x: float, z: float) -> float:
	var h := (_raw_height(x, z) + _raw_height(-x, -z)) * 0.5
	var edge := maxf(absf(x), absf(z))
	var mountains := smoothstep(play_radius + 2.0, size * 0.5 - 6.0, edge)
	h += mountains * MOUNTAIN_HEIGHT * (0.75 + 0.25 * _detail.get_noise_2d(x * 0.3, z * 0.3))
	return h


func _build_heights() -> void:
	heights.resize(n * n)
	_dirt.resize(n * n)
	_dirt.fill(0.0)
	for j in n:
		for i in n:
			heights[j * n + i] = _base_height(-size * 0.5 + i * cell, -size * 0.5 + j * cell)
	for index in bases.size():
		var p := _base_2d(index)
		_pads.append([p, MAIN_RADIUS if index < 2 else EXPANSION_RADIUS, _base_height(p.x, p.y)])
	_apply_pads()
	for index in bases.size():
		bases[index].y = height_at(bases[index].x, bases[index].z)


## Flattens the ground under each base, blending back over 10 m (as the action
## game's world generator does for its sites).
func _apply_pads() -> void:
	var best_weight := PackedFloat32Array()
	var best_height := PackedFloat32Array()
	best_weight.resize(n * n)
	best_height.resize(n * n)
	best_weight.fill(0.0)
	for pad in _pads:
		var center: Vector2 = pad[0]
		var r: float = pad[1]
		var reach := r + 10.0
		for j in n:
			var z := -size * 0.5 + j * cell
			if absf(z - center.y) > reach:
				continue
			for i in n:
				var x := -size * 0.5 + i * cell
				var d := Vector2(x, z).distance_to(center)
				if d >= reach:
					continue
				var k := j * n + i
				var weight := 1.0 - smoothstep(r, reach, d)
				if weight > best_weight[k]:
					best_weight[k] = weight
					best_height[k] = pad[2]
				_dirt[k] = maxf(_dirt[k], 1.0 - smoothstep(r * 0.4, r + 2.0, d))
	# Lanes are worn into dirt tracks.
	for j in n:
		for i in n:
			var p := Vector2(-size * 0.5 + i * cell, -size * 0.5 + j * cell)
			for road in _roads:
				var d := Geometry2D.get_closest_point_to_segment(p, road[0], road[1]).distance_to(p)
				if d < 5.0:
					_dirt[j * n + i] = maxf(_dirt[j * n + i], 0.7 * (1.0 - d / 5.0))
	for k in n * n:
		if best_weight[k] > 0.0:
			heights[k] = lerpf(heights[k], best_height[k], best_weight[k])


func _apply_atmosphere() -> void:
	var world_env := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		var env := world_env.environment
		env.fog_light_color = biome.fog_color
		var sky_material := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
		if sky_material:
			sky_material.sky_top_color = biome.sky_top
			sky_material.sky_horizon_color = biome.sky_horizon
			sky_material.ground_horizon_color = biome.sky_horizon
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_color = biome.sun_color


func _build_terrain() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var map_pixels := PackedByteArray()
	map_pixels.resize(n * n * 3)
	var map_light := Vector3(-0.5, 0.75, -0.45).normalized()

	for j in n:
		for i in n:
			var k := j * n + i
			var x := -size * 0.5 + i * cell
			var z := -size * 0.5 + j * cell
			var h := heights[k]
			verts[k] = Vector3(x, h, z)
			var hl := heights[j * n + maxi(i - 1, 0)]
			var hr := heights[j * n + mini(i + 1, n - 1)]
			var hd := heights[maxi(j - 1, 0) * n + i]
			var hu := heights[mini(j + 1, n - 1) * n + i]
			var normal := Vector3((hl - hr) / (2.0 * cell), 1.0, (hd - hu) / (2.0 * cell)).normalized()
			normals[k] = normal
			var c := biome.ground_a.lerp(biome.ground_b, clampf(_detail.get_noise_2d(x * 0.4, z * 0.4) * 0.8 + 0.5, 0.0, 1.0))
			c = c.lerp(biome.dirt, _dirt[k] * 0.6)
			c = c.lerp(biome.rock, clampf((1.0 - normal.y) * 4.0 - 0.4, 0.0, 1.0))
			c = c.lerp(biome.peak, smoothstep(14.0, 24.0, h))
			colors[k] = c
			var shade := clampf(0.3 + 0.9 * normal.dot(map_light), 0.25, 1.15)
			map_pixels[k * 3] = clampi(roundi(c.r * shade * 255.0), 0, 255)
			map_pixels[k * 3 + 1] = clampi(roundi(c.g * shade * 255.0), 0, 255)
			map_pixels[k * 3 + 2] = clampi(roundi(c.b * shade * 255.0), 0, 255)
	map_texture = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, map_pixels))

	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh
	terrain.material_override = fogged_material(Color.WHITE, Color.BLACK, 1.0, true)
	add_child(terrain)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = Combat.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


## Invisible walls around the play area (heroes only: shots and hooks pass).
func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = Combat.BOUNDARY
	body.collision_mask = 0
	add_child(body)
	var limit := play_radius + 1.0
	for side in 4:
		var box := BoxShape3D.new()
		var along_x := side < 2
		box.size = Vector3(limit * 2.0 + 4.0, WALL_HEIGHT, 2.0) if along_x else Vector3(2.0, WALL_HEIGHT, limit * 2.0 + 4.0)
		var shape := CollisionShape3D.new()
		shape.shape = box
		var side_sign := 1.0 if side % 2 == 0 else -1.0
		shape.position = Vector3(0.0, WALL_HEIGHT * 0.5 - 40.0, side_sign * (limit + 1.0)) if along_x \
				else Vector3(side_sign * (limit + 1.0), WALL_HEIGHT * 0.5 - 40.0, 0.0)
		body.add_child(shape)


## Blocks the edge and anything too steep to walk.
func _build_nav() -> void:
	nav = RTSNav.new()
	nav.setup(size, cell, n, heights)
	var limit := play_radius
	for j in n:
		var z := -size * 0.5 + j * cell
		for i in n:
			var x := -size * 0.5 + i * cell
			if absf(x) > limit or absf(z) > limit:
				nav.block_cell(Vector2i(i, j))
				continue
			var dx := (heights[j * n + mini(i + 1, n - 1)] - heights[j * n + maxi(i - 1, 0)]) / (2.0 * cell)
			var dz := (heights[mini(j + 1, n - 1) * n + i] - heights[maxi(j - 1, 0) * n + i]) / (2.0 * cell)
			if dx * dx + dz * dz > 0.81:
				nav.block_cell(Vector2i(i, j))


func _near_road(p: Vector2, margin: float) -> bool:
	for road in _roads:
		var closest := Geometry2D.get_closest_point_to_segment(p, road[0], road[1])
		if closest.distance_to(p) < margin:
			return true
	return false


func _is_free(p: Vector2, radius: float) -> bool:
	for o in _occupied:
		if p.distance_to(o[0]) < radius + o[1]:
			return false
	return true


## Rock spires in mirrored pairs: landmarks, cover, and something to grapple.
func _scatter_spires() -> void:
	var scenery := Node3D.new()
	scenery.name = "Spires"
	add_child(scenery)
	var rock := fogged_material(biome.rock.darkened(0.1), Color.BLACK, 1.0)
	var placed := 0
	for attempt in 400:
		if placed >= 9:
			break
		var p := Vector2(rng.randf_range(-play_radius + 12.0, play_radius - 12.0), rng.randf_range(-play_radius + 12.0, play_radius - 12.0))
		if p.length() < 12.0 or not _is_free(p, 6.0) or not _is_free(-p, 6.0) or _near_road(p, 9.0) or _near_road(-p, 9.0):
			continue
		placed += 1
		var height := rng.randf_range(8.0, 18.0)
		var top_radius := rng.randf_range(1.4, 2.6)
		var bottom_radius := top_radius * rng.randf_range(1.4, 2.0)
		var yaw := rng.randf() * TAU
		var spire := CylinderMesh.new()
		spire.top_radius = top_radius
		spire.bottom_radius = bottom_radius
		spire.height = height + 3.0
		spire.radial_segments = 7
		var spire_shape := spire.create_convex_shape()
		for q: Vector2 in [p, -p]:
			_occupied.append([q, bottom_radius + 2.0])
			var at := Vector3(q.x, height_at(q.x, q.y) + height * 0.5 - 1.5, q.y)
			var body := StaticBody3D.new()
			body.collision_layer = Combat.WORLD
			body.collision_mask = 0
			body.transform = Transform3D(Basis(Vector3.UP, yaw), at)
			var mesh := MeshInstance3D.new()
			mesh.mesh = spire
			mesh.material_override = rock
			body.add_child(mesh)
			var shape := CollisionShape3D.new()
			shape.shape = spire_shape
			body.add_child(shape)
			scenery.add_child(body)
			nav.block_circle(Vector3(q.x, 0.0, q.y), bottom_radius, 0.0)


## The biome's trees in forests (mirrored pairs), off the lanes and bases.
func _scatter_trees() -> void:
	var nature := Node3D.new()
	nature.name = "Trees"
	add_child(nature)
	var limit := play_radius - 3.0
	for attempt in 1400:
		var p := Vector2(rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var density := (_forest.get_noise_2d(p.x, p.y) + _forest.get_noise_2d(-p.x, -p.y)) * 0.5
		if density < biome.forest_threshold + 0.02 and rng.randf() > 0.03:
			continue
		if not _is_free(p, 1.5) or not _is_free(-p, 1.5) or _near_road(p, 8.0) or _near_road(-p, 8.0):
			continue
		var slope_ok := true
		for q: Vector2 in [p, -p]:
			if nav.is_solid(nav.cell_of(Vector3(q.x, 0.0, q.y))):
				slope_ok = false
		if not slope_ok:
			continue
		var yaw := rng.randf() * TAU
		for q: Vector2 in [p, -p]:
			_occupied.append([q, 1.3])
			var tree: Node3D = biome.tree_scene.instantiate()
			tree.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, height_at(q.x, q.y) - 0.1, q.y))
			_fog_scenery(tree)
			nature.add_child(tree)
			nav.block_cell(nav.cell_of(Vector3(q.x, 0.0, q.y)))


## Swaps a scenery scene's materials for fogged ones. Its collision stays (on
## the world layer): heroes bump into trunks and can hook them.
func _fog_scenery(node: Node3D) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = Combat.WORLD
		(node as CollisionObject3D).collision_mask = 0
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var material := mesh_instance.get_active_material(0) as StandardMaterial3D
		var color := material.albedo_color if material else Color(0.5, 0.5, 0.5)
		if mesh_instance.name == "Leaves":
			color = biome.leaf_color
		mesh_instance.material_override = fogged_material(color)


## A crystal line behind each base (away from the middle of the map) and aether
## vents: two at the mains (out to the sides), one at each expansion.
func _place_resources() -> void:
	var holder := Node3D.new()
	holder.name = "Resources"
	add_child(holder)
	for index in bases.size():
		var center := bases[index]
		var away := Vector2(center.x, center.z).normalized()
		var main := index < 2
		if not main:
			# Expansions: crystals face away from the nearest lane.
			away = (Vector2(center.x, center.z) - _nearest_road_point(Vector2(center.x, center.z))).normalized()
		var used := {}
		for k in 8:
			var angle := lerpf(-1.05, 1.05, k / 7.0)
			var dist := 11.0 + (1.4 if k % 2 == 1 else 0.0)
			if not main:
				dist -= 2.0
			var dir := away.rotated(angle)
			var at := center + Vector3(dir.x, 0.0, dir.y) * dist
			var c := nav.cell_of(at)
			if used.has(c) or nav.is_solid(c):
				continue
			used[c] = true
			var crystal := RTSResource.new()
			crystal.name = "Crystal"
			holder.add_child(crystal)
			crystal.position = nav.point_of(c)
			var crystal_cells: Array[Vector2i] = [c]
			crystal.setup(self, "crystal", 1500, crystal_cells)
			resources.append(crystal)
		var vent_angles: Array = [2.0, -2.0] if main else [1.75]
		for angle in vent_angles:
			var dir := away.rotated(angle)
			var origin := footprint_origin(center + Vector3(dir.x, 0.0, dir.y) * (12.0 if main else 10.0), 2)
			var cells := footprint(origin, 2)
			var vent := RTSResource.new()
			vent.name = "Vent"
			holder.add_child(vent)
			vent.position = footprint_center(origin, 2)
			vent.setup(self, "vent", 2500, cells)
			resources.append(vent)


func _nearest_road_point(p: Vector2) -> Vector2:
	var best := p + Vector2.ONE
	for road in _roads:
		var closest := Geometry2D.get_closest_point_to_segment(p, road[0], road[1])
		if closest.distance_to(p) < best.distance_to(p) and closest.distance_to(p) > 0.5:
			best = closest
	return best
