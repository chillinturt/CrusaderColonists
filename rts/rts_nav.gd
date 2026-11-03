class_name RTSNav
extends WorldNav
## The action game's ground grid, plus what an RTS needs on top: structures that
## open their cells again when destroyed, walkability checks for steering, and
## smoothed paths (string-pulled, so units walk straight across open ground
## instead of zig-zagging cell to cell).

## Cells blocked by the map itself (slopes, trees, rocks, the edge), as opposed
## to structures and resources placed on top.
var _static := PackedByteArray()


## Call once the map's own obstacles are in.
func snapshot_static() -> void:
	_static.resize(n * n)
	for j in n:
		for i in n:
			_static[j * n + i] = 1 if _grid.is_point_solid(Vector2i(i, j)) else 0


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n


func is_solid(c: Vector2i) -> bool:
	return not in_bounds(c) or _grid.is_point_solid(c)


func is_statically_solid(c: Vector2i) -> bool:
	return not in_bounds(c) or _static[c.y * n + c.x] == 1


## Blocks or reopens a cell for something placed on the map. Reopening never
## clears what the map itself blocks.
func set_occupied(c: Vector2i, occupied: bool) -> void:
	if not in_bounds(c):
		return
	var solid := occupied or _static[c.y * n + c.x] == 1
	_grid.set_point_solid(c, solid)
	_wide.set_point_solid(c, solid)


func walkable(pos: Vector3) -> bool:
	var fx := (pos.x + size * 0.5) / cell
	var fz := (pos.z + size * 0.5) / cell
	return not is_solid(Vector2i(roundi(fx), roundi(fz)))


## Closest open spot to `pos` (pos itself when it's open).
func nearest_open_point(pos: Vector3) -> Vector3:
	if walkable(pos):
		return pos
	var c := cell_of(pos)
	for ring in range(1, 24):
		var best := Vector3.INF
		for j in range(-ring, ring + 1):
			for i in range(-ring, ring + 1):
				if maxi(absi(i), absi(j)) != ring:
					continue
				var candidate := c + Vector2i(i, j)
				if is_solid(candidate):
					continue
				var p := point_of(candidate)
				if best == Vector3.INF or p.distance_squared_to(pos) < best.distance_squared_to(pos):
					best = p
		if best != Vector3.INF:
			return best
	return pos


## Waypoints from `from` to `to` around obstacles, smoothed. Ends at `to` when
## it's reachable, else at the closest reachable point.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	if _clear_line(from, to):
		result.append(to)
		return result
	var start := _nearest_open(_grid, cell_of(from))
	var goal := _open_cell_facing(to, from)
	var ids := _grid.get_id_path(start, goal, true)
	var raw := PackedVector3Array()
	for index in range(1, ids.size()):
		raw.append(point_of(ids[index]))
	if ids.size() > 0 and ids[ids.size() - 1] == goal and walkable(to):
		if raw.is_empty():
			raw.append(to)
		else:
			raw[raw.size() - 1] = to
	if raw.is_empty():
		return result
	# String pulling: from each point, jump to the furthest one in a straight line.
	var here := from
	var index := 0
	while index < raw.size():
		var furthest := index
		for ahead in range(index + 1, mini(index + 24, raw.size())):
			if _clear_line(here, raw[ahead]):
				furthest = ahead
		result.append(raw[furthest])
		here = raw[furthest]
		index = furthest + 1
	return result


## An open cell next to `to` when its own cell is blocked (a building, a
## crystal): close to it, and on the side facing `from`, so units walk up to
## the near side of a building instead of around it.
func _open_cell_facing(to: Vector3, from: Vector3) -> Vector2i:
	var c := cell_of(to)
	if not is_solid(c):
		return c
	var first_ring := -1
	var best := c
	var best_score := INF
	for ring in range(1, 16):
		if first_ring >= 0 and ring > first_ring + 1:
			break
		for j in range(-ring, ring + 1):
			for i in range(-ring, ring + 1):
				if maxi(absi(i), absi(j)) != ring:
					continue
				var candidate := c + Vector2i(i, j)
				if is_solid(candidate):
					continue
				if first_ring < 0:
					first_ring = ring
				var p := point_of(candidate)
				var flat_to := Vector2(p.x - to.x, p.z - to.z).length()
				var flat_from := Vector2(p.x - from.x, p.z - from.z).length()
				var score := flat_from + 2.0 * flat_to
				if score < best_score:
					best = candidate
					best_score = score
	return best


## Whether a straight walk from a to b crosses only open cells.
func _clear_line(a: Vector3, b: Vector3) -> bool:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var steps := ceili(flat.length() / (cell * 0.4))
	for s in range(1, steps + 1):
		var t := float(s) / steps
		if not walkable(a.lerp(b, t)):
			return false
	return true
