class_name RTSFog
extends RefCounted
## Fog of war for one team, on the map's nav grid (one texel per cell):
##   unexplored  black: never seen
##   explored    grey: seen before (terrain shows, enemies don't)
##   visible     clear: inside something's sight right now
## The texture feeds the fogged scenery shader; overlay_texture darkens the minimap.

var n := 0
var cell := 2.0
var size := 0.0
var texture: ImageTexture
var overlay_texture: ImageTexture

var _visible := PackedByteArray()
var _explored := PackedByteArray()
var _bytes := PackedByteArray()
var _overlay := PackedByteArray()
## Sight radius (in cells) -> flat [di, dj, di, dj, ...] offsets inside it.
var _stamps := {}


func setup(map: RTSMap) -> void:
	n = map.n
	cell = map.cell
	size = map.size
	_visible.resize(n * n)
	_explored.resize(n * n)
	_bytes.resize(n * n)
	_overlay.resize(n * n * 4)
	_visible.fill(0)
	_explored.fill(0)
	_bytes.fill(0)
	texture = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_L8, _bytes))
	_build_overlay()
	overlay_texture = ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, _overlay))
	# Texel i is centered on nav point i, which sits at -size/2 + i * cell.
	var corner := -size * 0.5 - cell * 0.5
	var rect := Vector4(corner, corner, 1.0 / (n * cell), 1.0 / (n * cell))
	for material: ShaderMaterial in map.fogged_materials:
		material.set_shader_parameter(&"fog_tex", texture)
		material.set_shader_parameter(&"fog_rect", rect)


func update(entities: Array, team: int) -> void:
	_visible.fill(0)
	for entity: RTSEntity in entities:
		if entity.team == team and not entity.dead:
			_stamp(entity.global_position, entity.sight)
	for k in n * n:
		if _visible[k] == 1:
			_bytes[k] = 255
		elif _explored[k] == 1:
			_bytes[k] = 120
		else:
			_bytes[k] = 0
	texture.update(Image.create_from_data(n, n, false, Image.FORMAT_L8, _bytes))
	_build_overlay()
	overlay_texture.update(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, _overlay))


func is_visible(pos: Vector3) -> bool:
	var k := _index(pos)
	return k >= 0 and _visible[k] == 1


func is_explored(pos: Vector3) -> bool:
	var k := _index(pos)
	return k >= 0 and _explored[k] == 1


## Reveals everything (for the end of the game).
func reveal_all() -> void:
	_explored.fill(1)
	_visible.fill(1)
	_bytes.fill(255)
	texture.update(Image.create_from_data(n, n, false, Image.FORMAT_L8, _bytes))
	_build_overlay()
	overlay_texture.update(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, _overlay))


func _index(pos: Vector3) -> int:
	var i := roundi((pos.x + size * 0.5) / cell)
	var j := roundi((pos.z + size * 0.5) / cell)
	if i < 0 or j < 0 or i >= n or j >= n:
		return -1
	return j * n + i


func _stamp(pos: Vector3, sight: float) -> void:
	var r := maxi(roundi(sight / cell), 1)
	if not _stamps.has(r):
		var offsets := PackedInt32Array()
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if di * di + dj * dj <= r * r:
					offsets.append(di)
					offsets.append(dj)
		_stamps[r] = offsets
	var stamp: PackedInt32Array = _stamps[r]
	var ci := roundi((pos.x + size * 0.5) / cell)
	var cj := roundi((pos.z + size * 0.5) / cell)
	for s in range(0, stamp.size(), 2):
		var i := ci + stamp[s]
		var j := cj + stamp[s + 1]
		if i >= 0 and j >= 0 and i < n and j < n:
			var k := j * n + i
			_visible[k] = 1
			_explored[k] = 1


func _build_overlay() -> void:
	for k in n * n:
		var b := _bytes[k]
		_overlay[k * 4 + 3] = 0 if b == 255 else (110 if b > 0 else 215)
