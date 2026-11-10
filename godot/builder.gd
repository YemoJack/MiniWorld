extends RefCounted

const Catalog = preload("res://godot/catalog.gd")
const CELL := Catalog.CELL
const GROUND := Catalog.GROUND
const SLAB := Catalog.SLAB
const STOREY := Catalog.STOREY
const DIRECTIONS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const TOLERANCE := 0.001
const STAIR_EDGE_INSET := 0.10

var catalog: Catalog
var container: Node3D
var rim: PackedVector2Array
var has_pond := false
var obstacles: Array[AABB]
var placements: Array
var bodies: Array[StaticBody3D]
var occupied: Dictionary
var walk_shape: CollisionShape3D


func _init(assets: Catalog, root: Node3D, island_rim: PackedVector2Array) -> void:
	catalog = assets
	container = root
	rim = island_rim
	var walkable := StaticBody3D.new()
	walkable.name = "WalkableSurfaces"
	walkable.collision_layer = 8
	walkable.collision_mask = 0
	walk_shape = CollisionShape3D.new()
	walkable.add_child(walk_shape)
	container.add_child(walkable)


func load_island(values: Array) -> void:
	for body in bodies:
		if body != null:
			body.free()
	bodies.clear()
	placements = values
	for value: Dictionary in placements:
		bodies.append(create_body(value))
	sync()


func cell(p: Dictionary) -> Vector2i:
	return Vector2i(p.x, p.z)


func width(p: Dictionary) -> Vector2i:
	var info: Dictionary = catalog.items[p.item]
	return Vector2i(info.width, info.depth) if int(p.turns) % 2 == 0 else Vector2i(info.depth, info.width)


func cells(p: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var size := width(p)
	for x in range(size.x):
		for z in range(size.y):
			result.append(cell(p) + Vector2i(x, z))
	return result


func layer(p: Dictionary) -> String:
	return catalog.items[p.item].layer


func fine(p: Dictionary) -> bool:
	return catalog.items[p.item].get("fine", false)


func center(p: Dictionary) -> Vector2:
	var result := (Vector2(cell(p)) + (Vector2(width(p)) - Vector2.ONE) / 2) * CELL
	if layer(p) == "edge":
		result += Vector2(DIRECTIONS[p.turns]) * CELL / 2
	elif fine(p):
		result += Vector2(p.get("offsetX", 0), p.get("offsetZ", 0)) * CELL / 5
	return result


func grid_cell(point: Vector2, size: float = CELL) -> Vector2i:
	# The browser save uses rounding toward positive infinity on a tie.
	return Vector2i(floor(point / size + Vector2(0.5, 0.5)))


func slot(kind: String, location: Vector2i, elevation: int) -> String:
	return "%s:%d:%d,%d" % [kind, elevation, location.x, location.y]


func slots(p: Dictionary) -> PackedStringArray:
	var kind := layer(p)
	var result := PackedStringArray()
	if fine(p):
		return PackedStringArray([slot("detail", cell(p) * 5 + Vector2i(p.get("offsetX", 0), p.get("offsetZ", 0)), p.elevation)])
	for position in cells(p):
		if kind == "edge":
			result.append(slot(kind, position * 2 + DIRECTIONS[p.turns], p.elevation))
		else:
			result.append(slot(kind, position, p.elevation))
	return result


func has_floor(location: Vector2i, elevation: int, ignore: int = -1) -> bool:
	var owner: int = occupied.get(slot("floor", location, elevation), -1)
	return owner >= 0 and owner != ignore


func floor_top(elevation: int) -> float:
	return GROUND + (SLAB if elevation == 0 else elevation / 1000.0)


func world_y(p: Dictionary, ignore: int = -1) -> float:
	if layer(p) == "floor":
		return floor_top(p.elevation) - SLAB
	if p.elevation > 0 or layer(p) == "edge" or p.item == "steelColumn":
		return GROUND + p.elevation / 1000.0
	for position in cells(p):
		if has_floor(position, 0, ignore):
			return floor_top(0)
	return GROUND


func rise(p: Dictionary, ignore: int = -1) -> float:
	return GROUND + (p.elevation + STOREY) / 1000.0 - world_y(p, ignore)


func placement_transform(p: Dictionary, ignore: int = -1) -> Transform3D:
	var horizontal := center(p)
	return Transform3D(Basis(Vector3.UP, p.turns * PI / 2), Vector3(horizontal.x, world_y(p, ignore), horizontal.y))


func placement_bounds(p: Dictionary, ignore: int = -1) -> AABB:
	var local := catalog.item_bounds(p.item)
	if p.item == "stairs":
		local = AABB(Vector3(-CELL / 2, 0, -CELL / 2), Vector3(CELL, rise(p, ignore), CELL))
	elif layer(p) == "floor":
		local = AABB(Vector3(-CELL / 2, 0, -CELL / 2), Vector3(CELL, SLAB, CELL))
	elif local.size.length_squared() == 0:
		var info: Dictionary = catalog.items[p.item]
		var size := Vector3(info.width * CELL, Catalog.WALL, info.depth * CELL if layer(p) == "object" else 0.10)
		local = AABB(Vector3(-size.x / 2, 0, -size.z / 2), size)
	return placement_transform(p, ignore) * local


func touched_cells(p: Dictionary, bounds: AABB) -> Array[Vector2i]:
	if not fine(p):
		return cells(p)
	var result: Array[Vector2i] = []
	var first := grid_cell(Vector2(bounds.position.x, bounds.position.z) + Vector2.ONE * TOLERANCE)
	var last := grid_cell(Vector2(bounds.end.x, bounds.end.z) - Vector2.ONE * TOLERANCE)
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			result.append(Vector2i(x, z))
	return result


func within_island(location: Vector2i) -> bool:
	var midpoint := Vector2(location) * CELL
	var half := Vector2.ONE * CELL / 2
	var pond := Vector2(3.35, 0.35)
	if has_pond and ((pond.clamp(midpoint - half, midpoint + half) - pond) / Vector2(2.15, 1.87)).length_squared() <= 1.0:
		return false
	for bounds in obstacles:
		if Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).intersects(Rect2(midpoint - half, Vector2.ONE * CELL)):
			return false
	for dx in [-0.49, 0.49]:
		for dz in [-0.49, 0.49]:
			if not Geometry2D.is_point_in_polygon((Vector2(location) + Vector2(dx, dz)) * CELL, rim):
				return false
	return true


func supported(p: Dictionary, locations: Array[Vector2i], ignore: int) -> bool:
	if p.elevation == 0 or layer(p) == "floor":
		return true
	var on_floor := true
	for location in locations:
		if not has_floor(location, p.elevation, ignore) and not (
			layer(p) == "edge" and has_floor(location + DIRECTIONS[p.turns], p.elevation, ignore)
		):
			on_floor = false
			break
	if on_floor:
		return true
	if p.item == "stairs":
		for offset in [Vector2i.ZERO, DIRECTIONS[p.turns]]:
			var previous: int = occupied.get(slot("object", cell(p) + offset, p.elevation - STOREY), -1)
			if previous >= 0 and previous != ignore:
				var other: Dictionary = placements[previous]
				var turns := int(p.turns) if offset != Vector2i.ZERO else (int(p.turns) + 2) % 4
				if other.item == "stairs" and int(other.turns) == turns:
					return true
	return false


func can_place(p: Dictionary, ignore: int = -1) -> bool:
	if p.is_empty() or p.elevation < 0 or p.elevation > 8000 or (p.item == "stairs" and p.elevation + STOREY > 8000):
		return false
	for key in slots(p):
		if occupied.get(key, ignore) != ignore:
			return false
	var bounds := placement_bounds(p, ignore)
	var locations := touched_cells(p, bounds)
	for location in cells(p) + locations:
		if not within_island(location):
			return false
	if not supported(p, locations, ignore):
		return false
	for i in range(placements.size()):
		if i == ignore:
			continue
		var other: Dictionary = placements[i]
		var a := layer(p)
		var b := layer(other)
		if p.elevation == other.elevation and (a == "floor" or b == "floor" or (a == "edge" and b == "edge")):
			continue
		var overlap := bounds.intersection(placement_bounds(other))
		if overlap.size.x > TOLERANCE and overlap.size.y > TOLERANCE and overlap.size.z > TOLERANCE:
			if p.item == "stairs" and b == "edge" and stair_edge_fits(p, other, overlap, ignore):
				continue
			if other.item == "stairs" and a == "edge" and stair_edge_fits(other, p, overlap, ignore):
				continue
			return false
	return true


func stair_edge_fits(stairs: Dictionary, edge: Dictionary, overlap: AABB, ignore: int) -> bool:
	var edges := slots(edge)
	var turns: int = stairs.turns
	var location := cell(stairs)
	var side_depth := overlap.size.x if turns % 2 == 0 else overlap.size.z
	# A wall is centered on the grid boundary, so its trim can overlap the
	# outer strip of the stairs without getting in the way of the passage.
	if side_depth <= STAIR_EDGE_INSET + TOLERANCE:
		for direction in [(turns + 1) % 4, (turns + 3) % 4]:
			if slot("edge", location * 2 + DIRECTIONS[direction], edge.elevation) in edges:
				return true

	# The wall below an existing landing may touch the upper end of the ramp.
	var exit: Vector2i = DIRECTIONS[(turns + 2) % 4]
	var upper: int = stairs.elevation + STOREY
	var end_depth := overlap.size.z if turns % 2 == 0 else overlap.size.x
	return edge.item in ["wall", "halfWall"] and edge.elevation == stairs.elevation \
		and end_depth <= STAIR_EDGE_INSET + TOLERANCE \
		and slot("edge", location * 2 + exit, edge.elevation) in edges \
		and has_floor(location + exit, upper, ignore) \
		and overlap.end.y <= floor_top(upper) - SLAB + TOLERANCE


func target(item: String, turns: int, hit: Dictionary, viewer: Vector3) -> Dictionary:
	if hit.is_empty():
		return {}
	var point: Vector3 = hit.position
	var horizontal := Vector2(point.x, point.z)
	var p := {"item": item, "turns": turns, "elevation": 0}
	var owner: int = hit.collider.get_meta("placement", -1)
	if owner >= 0:
		var support: Dictionary = placements[owner]
		var bounds := placement_bounds(support)
		if layer(support) == "floor":
			p.elevation = support.elevation
			if layer(p) == "floor":
				var offset := horizontal - center(support)
				if maxf(absf(offset.x), absf(offset.y)) < CELL * 0.275:
					return {}
				horizontal = Vector2(cell(support) + Vector2i(Vector2(signf(offset.x), 0) if absf(offset.x) > absf(offset.y) else Vector2(0, signf(offset.y)))) * CELL
			elif viewer.y <= bounds.end.y or point.y < bounds.end.y - 0.035:
				return {}
		elif support.item == "stairs" and item in ["floor", "flatRoof", "skylight", "stairs"] and bounds.end.y - point.y <= 0.15:
			p.elevation = support.elevation + STOREY
			var location := cell(support)
			if item != "stairs" or turns != (int(support.turns) + 2) % 4:
				location += DIRECTIONS[(int(support.turns) + 2) % 4]
			horizontal = Vector2(location) * CELL
		elif layer(p) == "floor" and (layer(support) == "edge" or support.item == "steelColumn") and bounds.end.y - point.y <= 0.10:
			p.elevation = roundi((bounds.end.y + SLAB - GROUND) * 1000.0)
			var midpoint := center(support)
			if layer(support) == "edge":
				var along_x := int(support.turns) % 2 != 0
				var delta := horizontal.x - midpoint.x if along_x else horizontal.y - midpoint.y
				if absf(delta) < 0.012:
					delta = viewer.x - midpoint.x if along_x else viewer.z - midpoint.y
				var side := 1.0 if delta >= 0.0 else -1.0
				if along_x:
					horizontal.x = midpoint.x + side * CELL / 2
				else:
					horizontal.y = midpoint.y + side * CELL / 2
			else:
				horizontal = midpoint
		else:
			return {}
	var location := grid_cell(horizontal)
	if fine(p):
		var subdivisions := grid_cell(horizontal, CELL / 5)
		location = grid_cell(Vector2(subdivisions), 5)
		var offset := subdivisions - location * 5
		p.offsetX = offset.x
		p.offsetZ = offset.y
	p.x = location.x
	p.z = location.y
	return p


func create_body(p: Dictionary) -> StaticBody3D:
	if not catalog.available(p.item):
		return null
	var body := StaticBody3D.new()
	body.collision_layer = 16 if layer(p) == "floor" or p.item == "stairs" else 2
	body.collision_mask = 0
	add_parts(body, p)
	container.add_child(body)
	return body


func add_parts(body: StaticBody3D, p: Dictionary) -> void:
	var height := rise(p)
	var visual := catalog.visuals(p.item, height)
	body.add_child(visual)
	if layer(p) == "floor":
		catalog.box_shape(body, Vector3(CELL, SLAB, CELL), Vector3.UP * SLAB / 2)
	elif p.item == "stairs":
		var ramp := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for x in [-CELL / 2, CELL / 2]:
			points.append(Vector3(x, -0.016, CELL / 2))
			points.append(Vector3(x, 0, CELL / 2))
			points.append(Vector3(x, -0.016, -CELL / 2))
			points.append(Vector3(x, height, -CELL / 2))
		ramp.points = points
		var collider := CollisionShape3D.new()
		collider.shape = ramp
		body.add_child(collider)
		body.set_meta("rise", height)
	elif p.item in ["doorway", "windowWall"]:
		var opening := 0.504 if p.item == "doorway" else 0.434
		var top := 0.89 if p.item == "doorway" else 0.88
		var jamb := (CELL - opening) / 2
		for side in [-1, 1]:
			catalog.box_shape(body, Vector3(jamb, Catalog.WALL, 0.10), Vector3(side * (CELL - jamb) / 2, Catalog.WALL / 2, 0))
		catalog.box_shape(body, Vector3(opening, Catalog.WALL - top, 0.10), Vector3(0, (Catalog.WALL + top) / 2, 0))
		if p.item == "windowWall":
			catalog.box_shape(body, Vector3(opening, 0.51, 0.10), Vector3(0, 0.255, 0))
	elif p.item in ["wall", "halfWall"]:
		var bounds := catalog.item_bounds(p.item)
		catalog.box_shape(body, bounds.size, bounds.get_center())
	else:
		catalog.collider_meshes(body, visual)


func sync() -> void:
	occupied.clear()
	for i in range(placements.size()):
		for key in slots(placements[i]):
			occupied[key] = i
	for i in range(placements.size()):
		var body := bodies[i]
		if body == null:
			continue
		var p: Dictionary = placements[i]
		if p.item == "stairs" and not is_equal_approx(body.get_meta("rise"), rise(p)):
			for child in body.get_children():
				child.free()
			add_parts(body, p)
		elif p.item == "wall":
			sync_landing_wall(p, body.get_child(1) as CollisionShape3D)
		body.set_meta("placement", i)
		body.transform = placement_transform(p)
		body.reset_physics_interpolation()
	rebuild_walk_surface()


func sync_landing_wall(wall: Dictionary, collision: CollisionShape3D) -> void:
	var location := cell(wall)
	var turns: int = wall.turns
	var across: Vector2i = location + DIRECTIONS[turns]
	var upper: int = wall.elevation + STOREY
	var bounds := catalog.item_bounds(wall.item)
	# Keep the support wall collision on the landing side of the seam so its
	# upper corner cannot catch the player coming up the sloped collision.
	var front := bounds.end.z
	var back := bounds.position.z
	if is_stair_at(location, (turns + 2) % 4, wall.elevation) and has_floor(across, upper):
		back = 0.0
	if is_stair_at(across, turns, wall.elevation) and has_floor(location, upper):
		front = 0.0
	var size := bounds.size
	size.z = maxf(front - back, 0.01)
	var shape := collision.shape as BoxShape3D
	shape.size = size
	collision.position.z = (front + back) / 2.0


func is_stair_at(location: Vector2i, turns: int, elevation: int) -> bool:
	var index: int = occupied.get(slot("object", location, elevation), -1)
	if index < 0:
		return false
	var p: Dictionary = placements[index]
	return p.item == "stairs" and int(p.turns) == turns


func rebuild_walk_surface() -> void:
	# A shared mesh lets the engine resolve ramp and slab edges as one surface.
	# Per-piece bodies remain available for picking in build mode.
	var faces := PackedVector3Array()
	var landings: Dictionary = {}
	for p: Dictionary in placements:
		if p.item == "stairs":
			var exit: Vector2i = DIRECTIONS[(p.turns + 2) % 4]
			landings[slot("edge", (cell(p) + exit) * 2 - exit, p.elevation + STOREY)] = true
	for p: Dictionary in placements:
		if layer(p) == "floor":
			var midpoint := Vector2(cell(p)) * CELL
			var top := floor_top(p.elevation)
			var transform := Transform3D(Basis.IDENTITY, Vector3(midpoint.x, top - SLAB, midpoint.y))
			var sides: Array[bool] = []
			for side: Vector2i in DIRECTIONS:
				sides.append(not has_floor(cell(p) + side, p.elevation) and not landings.has(slot("edge", cell(p) * 2 + side, p.elevation)))
			append_walk_faces(faces, transform, SLAB, SLAB, 0.0, sides)
		elif p.item == "stairs":
			var landing: Vector2i = cell(p) + DIRECTIONS[(p.turns + 2) % 4]
			var sides: Array[bool] = [true, true, not has_floor(landing, p.elevation + STOREY), true]
			append_walk_faces(faces, placement_transform(p), 0.0, rise(p), -0.016, sides)
	if faces.is_empty():
		walk_shape.shape = null
	else:
		var mesh := ConcavePolygonShape3D.new()
		mesh.set_faces(faces)
		walk_shape.shape = mesh


func append_walk_faces(faces: PackedVector3Array, transform: Transform3D, front: float, back: float, bottom: float, sides: Array[bool]) -> void:
	var half := CELL / 2
	var corners := [
		Vector3(-half, front, half), Vector3(half, front, half),
		Vector3(half, back, -half), Vector3(-half, back, -half),
	]
	var top := PackedVector3Array()
	var base := PackedVector3Array()
	for corner: Vector3 in corners:
		top.append(transform * corner)
		base.append(transform * Vector3(corner.x, bottom, corner.z))
	quad(faces, top[0], top[1], top[2], top[3], Vector3.UP)
	quad(faces, base[0], base[1], base[2], base[3], Vector3.DOWN)
	for i in range(4):
		if sides[i]:
			var next := (i + 1) % 4
			var side: Vector2i = DIRECTIONS[i]
			quad(faces, top[i], top[next], base[next], base[i], transform.basis * Vector3(side.x, 0, side.y))


func quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		faces.append_array(PackedVector3Array([a, b, c, a, c, d]))
	else:
		faces.append_array(PackedVector3Array([a, c, b, a, d, c]))


func put(p: Dictionary, index: int) -> int:
	if not can_place(p, index):
		return -1
	if index < 0:
		placements.append(p)
		bodies.append(create_body(p))
		index = placements.size() - 1
	else:
		if bodies[index] != null:
			bodies[index].free()
		placements[index] = p
		bodies[index] = create_body(p)
	sync()
	return index


func remove(index: int) -> void:
	if bodies[index] != null:
		bodies[index].free()
	bodies.remove_at(index)
	placements.remove_at(index)
	sync()
