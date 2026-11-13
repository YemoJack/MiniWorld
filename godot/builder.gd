extends RefCounted

const Catalog = preload("res://godot/catalog.gd")
const Data = Catalog.Data
const Door = preload("res://godot/build_door.gd")
const Seat = preload("res://godot/build_seat.gd")
const GROUND := Catalog.GROUND
const SLAB := Catalog.SLAB
const DIRECTIONS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const TOLERANCE := 0.001
const STAIR_EDGE_INSET := 0.18
const MODULES := ["wall", "halfWall", "floor", "woodRoofSlope", "woodRoofRidge"]
const OPENING_PICK_LAYER := 32
const DOOR_PICK_LAYER := 64

var catalog: Catalog
var container: Node3D
var rim: PackedVector2Array
var has_pond := false
var harbor_water: Rect2
var obstacles: Array[AABB]
var placements: Array
var bodies: Array[StaticBody3D]
var occupied: Dictionary
var interfaces_by_edge: Dictionary
var walk_shape: CollisionShape3D


func _init(assets: Catalog, root: Node3D) -> void:
	catalog = assets
	container = root
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
	occupied.clear()
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


func profile(p: Dictionary) -> Dictionary:
	return Data.PLACEMENT_PROFILES[layer(p)]


func shape_kind(p: Dictionary) -> String:
	return catalog.items[p.item].get("shape", profile(p).shape)


func fine(p: Dictionary) -> bool:
	return catalog.items[p.item].get("fine", false)


func center(p: Dictionary) -> Vector2:
	var result := (Vector2(cell(p)) + (Vector2(width(p)) - Vector2.ONE) / 2) * catalog.cell_size
	if profile(p).anchor == "edge":
		result += Vector2(DIRECTIONS[p.turns]) * catalog.cell_size / 2
	elif fine(p):
		result += Vector2(p.get("offsetX", 0), p.get("offsetZ", 0)) * catalog.cell_size / 5
	return result


func grid_cell(point: Vector2, size := 0.0) -> Vector2i:
	# The browser save uses rounding toward positive infinity on a tie.
	var step := size if size > 0.0 else catalog.cell_size
	return Vector2i(floor(point / step + Vector2(0.5, 0.5)))


func slot(kind: String, location: Vector2i, elevation: int) -> String:
	return "%s:%d:%d,%d" % [kind, elevation, location.x, location.y]


func edge_key(location: Vector2i, turns: int) -> Vector2i:
	return location * 2 + DIRECTIONS[turns]


func slots(p: Dictionary) -> PackedStringArray:
	var kind := layer(p)
	var result := PackedStringArray()
	if fine(p):
		return PackedStringArray([slot("detail", cell(p) * 5 + Vector2i(p.get("offsetX", 0), p.get("offsetZ", 0)), p.elevation)])
	var on_edge: bool = profile(p).anchor == "edge"
	for position in cells(p):
		result.append(slot(kind, edge_key(position, p.turns) if on_edge else position, p.elevation))
	return result


func slab_bounds(p: Dictionary) -> AABB:
	var info: Dictionary = catalog.items[p.item]
	var size := Vector3(info.width * catalog.cell_size, SLAB, info.depth * catalog.cell_size)
	return AABB(Vector3(-size.x / 2.0, 0, -size.z / 2.0), size)


func has_floor(location: Vector2i, elevation: int, ignore: int = -1) -> bool:
	var owner: int = occupied.get(slot("floor", location, elevation), -1)
	return owner >= 0 and owner != ignore and layer(placements[owner]) == "floor"


func floor_center(elevation: int) -> float:
	return GROUND + elevation / 1000.0


func floor_top(elevation: int) -> float:
	return floor_center(elevation) + SLAB / 2.0


static func min_elevation(kind: String, storey_mm: int, surface_ridge := false) -> int:
	# A snapped ridge stores its base below the crest by the standard roof rise.
	return -roundi(storey_mm / 2.0) if kind == "ridge" and not surface_ridge else 0


func world_y(p: Dictionary, ignore: int = -1) -> float:
	var kind := layer(p)
	if kind == "floor":
		return floor_top(p.elevation) - SLAB
	if kind == "ridge":
		var inset := catalog.item_bounds(p.item).position.y if p.get("surfaceRidge", false) else 0.0
		return floor_center(p.elevation) - inset
	if p.item == "harborRope" and p.elevation == 0:
		if has_floor(cell(p), 0, ignore) or has_floor(cell(p) + DIRECTIONS[p.turns], 0, ignore):
			return floor_top(0)
	if p.item == "stairs" and has_floor(stair_end(p, p.turns), p.elevation, ignore):
		return floor_top(p.elevation)
	if p.elevation > 0 or kind in ["edge", "roof", "gable"] or catalog.items[p.item].get("floor_support", false):
		return GROUND + p.elevation / 1000.0
	for position in cells(p):
		if has_floor(position, 0, ignore):
			return floor_top(0)
	return GROUND


func rise(p: Dictionary, ignore: int = -1) -> float:
	return floor_top(p.elevation + catalog.storey_mm) - world_y(p, ignore)


func stair_end(p: Dictionary, side: int) -> Vector2i:
	var direction: Vector2i = DIRECTIONS[side]
	return cell(p) + (width(p) - Vector2i.ONE) * direction.max(Vector2i.ZERO)


func stair_landing(p: Dictionary) -> Vector2i:
	var exit := (int(p.turns) + 2) % 4
	return stair_end(p, exit) + DIRECTIONS[exit]


func placement_transform(p: Dictionary, ignore: int = -1) -> Transform3D:
	var horizontal := center(p)
	if layer(p) in ["edge", "gable"]:
		horizontal -= Vector2(DIRECTIONS[p.turns]) * catalog.item_bounds(p.item).get_center().z
	return Transform3D(Basis(Vector3.UP, p.turns * PI / 2), Vector3(horizontal.x, world_y(p, ignore), horizontal.y))


func placement_bounds(p: Dictionary, ignore: int = -1) -> AABB:
	var local := catalog.item_bounds(p.item)
	if p.item == "stairs":
		var depth := catalog.cell_size * int(catalog.items.stairs.depth)
		local = AABB(Vector3(-catalog.cell_size / 2.0, 0, -depth / 2.0), Vector3(catalog.cell_size, rise(p, ignore), depth))
	elif shape_kind(p) == "slab":
		local = slab_bounds(p)
	elif local.size.length_squared() == 0:
		var info: Dictionary = catalog.items[p.item]
		var size := Vector3(info.width * catalog.cell_size, catalog.wall_height, info.depth * catalog.cell_size if layer(p) == "object" else 0.10)
		local = AABB(Vector3(-size.x / 2, 0, -size.z / 2), size)
	return placement_transform(p, ignore) * local


func touched_cells(p: Dictionary, bounds: AABB) -> Array[Vector2i]:
	if layer(p) == "gable" and p.get("edgeFacing", p.turns) != p.turns:
		return [cell(p) + DIRECTIONS[p.turns]]
	if not fine(p):
		return cells(p)
	var result: Array[Vector2i] = []
	var first := grid_cell(Vector2(bounds.position.x, bounds.position.z) + Vector2.ONE * TOLERANCE)
	var last := grid_cell(Vector2(bounds.end.x, bounds.end.z) - Vector2.ONE * TOLERANCE)
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			result.append(Vector2i(x, z))
	return result


func within_island(location: Vector2i, allow_water := false, check_scenery := true) -> bool:
	var midpoint := Vector2(location) * catalog.cell_size
	if not allow_water and harbor_water.has_point(midpoint):
		return false
	var half := Vector2.ONE * catalog.cell_size / 2
	var pond := Vector2(3.35, 0.35)
	if has_pond and ((pond.clamp(midpoint - half, midpoint + half) - pond) / Vector2(2.15, 1.87)).length_squared() <= 1.0:
		return false
	if check_scenery:
		for bounds in obstacles:
			if Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).intersects(Rect2(midpoint - half, Vector2.ONE * catalog.cell_size)):
				return false
	for dx in [-0.49, 0.49]:
		for dz in [-0.49, 0.49]:
			if not Geometry2D.is_point_in_polygon((Vector2(location) + Vector2(dx, dz)) * catalog.cell_size, rim):
				return false
	return true


func can_anchor_cell(location: Vector2i, allow_water: bool, ignore: int) -> bool:
	if not within_island(location, true, false):
		return false
	return allow_water or not harbor_water.has_point(Vector2(location) * catalog.cell_size) or has_floor(location, 0, ignore)


func can_place(p: Dictionary, ignore: int = -1) -> bool:
	if p.is_empty() or not catalog.items.get(p.item, {}).has("layer") \
		or p.elevation > 8000 or (p.item == "stairs" and p.elevation + catalog.storey_mm > 8000):
		return false
	var a := layer(p)
	if p.elevation < min_elevation(a, catalog.storey_mm, p.get("surfaceRidge", false)):
		return false
	if p.has("opening") and (p.item != "wall" or ignore < 0 or p.opening != placements[ignore].get("opening")):
		return false
	for key in slots(p):
		if occupied.get(key, ignore) != ignore:
			return false
	var is_edge := a in ["edge", "gable"]
	for shared_slot: String in profile(p).get("conflicts", []):
		for location in cells(p):
			if occupied.get(slot(shared_slot, edge_key(location, p.turns), p.elevation), ignore) != ignore:
				return false
	var bounds := placement_bounds(p, ignore)
	var locations := touched_cells(p, bounds)
	for scenery in obstacles:
		if has_volume(bounds.intersection(scenery)):
			return false
	var harbor_deck: bool = p.elevation == 0 and catalog.items[p.item].has("deck_y")
	var over_water := false
	for location in locations:
		over_water = over_water or harbor_water.has_point(Vector2(location) * catalog.cell_size)
		if can_anchor_cell(location, harbor_deck, ignore):
			continue
		var facing: Vector2i = DIRECTIONS[p.get("edgeFacing", p.turns)]
		if not is_edge or not can_anchor_cell(location + facing, false, ignore):
			return false
	if harbor_deck and over_water and not reaches_shore(locations):
		return false
	if not keeps_water_support(ignore, p):
		return false
	for i in range(placements.size()):
		if i == ignore:
			continue
		var other: Dictionary = placements[i]
		var b := layer(other)
		if (p.item == "stairs" and b == "edge" and stair_entrance_blocked(p, other)) \
			or (other.item == "stairs" and a == "edge" and stair_entrance_blocked(other, p)):
			return false
		var other_bounds := placement_bounds(other)
		var overlap := bounds.intersection(other_bounds)
		if has_volume(overlap) and not allowed_contact(p, other, overlap, ignore):
			return false
	return true


func allowed_contact(p: Dictionary, other: Dictionary, overlap: AABB, ignore: int) -> bool:
	if interfaces_join(p, other):
		return true
	if floor_seam(p, other, overlap) or floor_seam(other, p, overlap):
		return true
	if grid_edge_corner(p, other):
		return true
	if p.item == "stairs" and layer(other) == "edge" and stair_edge_fits(p, other, overlap):
		return true
	if other.item == "stairs" and layer(p) == "edge" and stair_edge_fits(other, p, overlap):
		return true
	var shape := shape_kind(p)
	var other_shape := shape_kind(other)
	if shape == "gable" and not Catalog.RoofKit.gable_overlaps_box(placement_transform(p, ignore), catalog.roof_rise(p.item), overlap, TOLERANCE, catalog.cell_size):
		return true
	if other_shape == "gable" and not Catalog.RoofKit.gable_overlaps_box(placement_transform(other), catalog.roof_rise(other.item), overlap, TOLERANCE, catalog.cell_size):
		return true
	return (shape == "slope" or other_shape == "slope") and not roof_overlap(p, other, overlap, ignore)


func grid_edge_corner(p: Dictionary, other: Dictionary) -> bool:
	if p.get("surfaceRidge", false) or other.get("surfaceRidge", false):
		return false
	var first := layer(p)
	var second := layer(other)
	return first in ["edge", "gable", "ridge"] and second in ["edge", "gable", "ridge"] \
		and (first != "ridge" or second != "ridge") and wall_corner_contact(p, other)


func wall_corner_contact(p: Dictionary, other: Dictionary) -> bool:
	if int(p.turns) % 2 == int(other.turns) % 2:
		return false
	var along_x := int(p.turns) % 2 == 0
	var x_ends := edge_vertices(p if along_x else other)
	var z_ends := edge_vertices(other if along_x else p)
	var vertex := Vector2i(z_ends[0].x, x_ends[0].y)
	return (vertex in x_ends and vertex.y >= mini(z_ends[0].y, z_ends[1].y) and vertex.y <= maxi(z_ends[0].y, z_ends[1].y)) \
		or (vertex in z_ends and vertex.x >= mini(x_ends[0].x, x_ends[1].x) and vertex.x <= maxi(x_ends[0].x, x_ends[1].x))


func edge_vertices(p: Dictionary) -> Array[Vector2i]:
	var midpoint := grid_cell(center(p), catalog.cell_size / 2.0)
	var along: Vector2i = DIRECTIONS[(int(p.turns) + 1) % 4]
	var span: int = catalog.items[p.item].width
	return [midpoint - along * span, midpoint + along * span]


func floor_seam(floor_part: Dictionary, other: Dictionary, overlap: AABB) -> bool:
	if layer(floor_part) != "floor":
		return false
	var kind := layer(other)
	if overlap.size.y <= SLAB / 2.0 + TOLERANCE and catalog.items[other.item].get("floor_support", false):
		var bounds := placement_bounds(other)
		var datum := floor_center(floor_part.elevation)
		if absf(bounds.end.y - datum) <= TOLERANCE or absf(bounds.position.y - datum) <= TOLERANCE:
			return true
	if floor_part.elevation != other.elevation:
		return false
	if floor_part.item not in MODULES and other.item not in MODULES:
		return kind not in ["roof", "ridge", "gable"]
	if floor_part.elevation != 0 or overlap.size.y > SLAB + TOLERANCE:
		return false
	if kind == "object":
		# Ground-level props and stairs use the top of a newly placed slab.
		return true
	if kind == "edge":
		var facing: Vector2i = DIRECTIONS[other.turns]
		var floor_cells := cells(floor_part)
		for location in cells(other):
			if (location in floor_cells) != (location + facing in floor_cells):
				return true
	return false


func roof_overlap(p: Dictionary, other: Dictionary, overlap: AABB, ignore: int) -> bool:
	var slope := p if shape_kind(p) == "slope" else other
	var neighbor := other if slope == p else p
	var transform := placement_transform(slope, ignore if slope == p else -1)
	var slope_rise := catalog.roof_rise(slope.item)
	if shape_kind(neighbor) == "slope":
		var other_transform := placement_transform(neighbor, ignore if neighbor == p else -1)
		return Catalog.RoofKit.slopes_overlap(transform, slope_rise, other_transform, catalog.roof_rise(neighbor.item), overlap, TOLERANCE, catalog.cell_size)
	if roof_side_seam(slope, neighbor, overlap):
		return false
	return Catalog.RoofKit.slope_overlaps_box(transform, slope_rise, overlap, TOLERANCE, catalog.cell_size)


func roof_side_seam(slope: Dictionary, wall: Dictionary, overlap: AABB) -> bool:
	var kind := layer(wall)
	if kind not in ["edge", "gable"]:
		return false
	var half_depth := catalog.item_bounds(wall.item).size.z / 2.0
	var across := overlap.size.z if int(wall.turns) % 2 == 0 else overlap.size.x
	if across > half_depth + TOLERANCE:
		return false
	var wall_edges := slots(wall)
	for port in edge_interfaces(slope, "roof_pitch"):
		if slot(kind, port.edge, wall.elevation) not in wall_edges:
			continue
		if kind == "edge":
			return true
		# The crest can meet the base of a gable on the level above.
		var crest: float = maxf(port.heights.x, port.heights.y)
		if absf(floor_center(wall.elevation) - crest) <= TOLERANCE and overlap.size.y <= Catalog.RoofKit.HALF_THICKNESS + TOLERANCE:
			return true
	return false


func has_volume(bounds: AABB) -> bool:
	return bounds.size.x > TOLERANCE and bounds.size.y > TOLERANCE and bounds.size.z > TOLERANCE


func support_at(key: String, ignore: int = -1) -> Dictionary:
	var index: int = occupied.get(key, -1)
	return placements[index] if index >= 0 and index != ignore and bodies[index] != null else {}


func interface_side(spec: Array, turns: int) -> int:
	return (maxi(0, spec[1]) + turns) % 4


func interface_heights(p: Dictionary, spec: Array) -> Vector2:
	if spec.size() == 2:
		var bounds := catalog.item_bounds(p.item)
		return Vector2.ONE * (bounds.end.y if spec[0] == "wall_top" else bounds.position.y)
	# Order endpoint heights along the positive world axis on this edge.
	var local_tangent := 1 if maxi(0, spec[1]) % 2 == 0 else 0
	var tangent: Vector2i = DIRECTIONS[(local_tangent + int(p.turns)) % 4]
	var heights: Vector2 = spec[2] * catalog.roof_rise(p.item)
	return heights if tangent.x + tangent.y > 0 else Vector2(heights.y, heights.x)


func edge_interfaces(p: Dictionary, role := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if p.get("surfaceRidge", false):
		return result
	for spec: Array in profile(p).get("interfaces", []):
		if not role.is_empty() and spec[0] != role:
			continue
		var side := interface_side(spec, p.turns)
		var datum := world_y(p) if spec.size() == 2 else floor_center(p.elevation)
		var heights := interface_heights(p, spec) + Vector2.ONE * datum
		for location in cells(p):
			result.append({"role": spec[0], "edge": edge_key(location, side), "side": side, "heights": heights})
	return result


func compatible_interfaces(first: String, second: String) -> bool:
	return second in Data.INTERFACE_PAIRS.get(first, []) or first in Data.INTERFACE_PAIRS.get(second, [])


func interface_matches(port: Dictionary, neighbor: Dictionary) -> bool:
	if port.edge != neighbor.edge or not compatible_interfaces(port.role, neighbor.role):
		return false
	var delta: Vector2 = (port.heights - neighbor.heights).abs()
	return maxf(delta.x, delta.y) <= TOLERANCE


func interfaces_join(p: Dictionary, other: Dictionary) -> bool:
	if not profile(p).has("interfaces") or not profile(other).has("interfaces"):
		return false
	var neighbors := edge_interfaces(other)
	for port in edge_interfaces(p):
		for neighbor in neighbors:
			if interface_matches(port, neighbor):
				return true
	return false


func interface_target(item: String, turns: int, support: Dictionary, role: String, required_side := -1) -> Dictionary:
	if not compatible_interfaces(support.role, role):
		return {}
	var p := {"item": item, "turns": turns}
	for spec: Array in profile(p).interfaces:
		if spec[0] != role:
			continue
		var side := interface_side(spec, turns)
		if required_side >= 0 and side != required_side:
			continue
		var doubled_cell: Vector2i = support.edge - DIRECTIONS[side]
		if doubled_cell.x % 2 != 0 or doubled_cell.y % 2 != 0:
			continue
		var base: Vector2 = support.heights - interface_heights(p, spec)
		var minimum := min_elevation(layer(p), catalog.storey_mm)
		if absf(base.x - base.y) <= TOLERANCE and base.x >= floor_center(minimum) - TOLERANCE:
			var elevation := maxi(minimum, roundi((base.x - GROUND) * 1000.0))
			return {"turns": turns, "location": doubled_cell / 2, "elevation": elevation}
	return {}


func edge_distance(edge: Vector2i, point: Vector2) -> float:
	var offset := (point - Vector2(edge) * catalog.cell_size / 2.0).abs()
	if edge.x % 2 == 0:
		return Vector2(maxf(0.0, offset.x - catalog.cell_size / 2.0), offset.y).length()
	return Vector2(offset.x, maxf(0.0, offset.y - catalog.cell_size / 2.0)).length()


func roof_connections(p: Dictionary, ignore: int) -> int:
	var score := 0
	for port in edge_interfaces(p):
		for neighbor: Dictionary in interfaces_by_edge.get(port.edge, []):
			if neighbor.owner != ignore and interface_matches(port, neighbor):
				score += 3 if port.role in ["roof_pitch", "gable_pitch", "crest"] else 1
				break
	return score


func roof_edge_targets(item: String, hit: Dictionary, ignore: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if hit.is_empty():
		return result
	var owner: int = hit.collider.get_meta("placement", -1)
	if owner < 0 or owner == ignore:
		return result
	var support: Dictionary = placements[owner]
	var kind: String = catalog.items[item].layer
	var support_kind := layer(support)
	var point: Vector3 = hit.position
	var horizontal := Vector2(point.x, point.z)
	var focus := cell(support)
	var min_height := 0
	var max_height := 8000
	var edges: Array[Vector2i] = []
	var roof_cells: Array[Vector2i] = []
	if support_kind == "floor":
		if point.y < floor_top(support.elevation) - 0.035:
			return result
		focus = grid_cell(horizontal).clamp(focus, focus + width(support) - Vector2i.ONE)
		min_height = support.elevation
		max_height = min_height
		roof_cells.append(focus)
		for side in 4:
			edges.append(edge_key(focus, side))
	elif support_kind == "edge":
		var tops := edge_interfaces(support, "wall_top")
		var top: Dictionary = tops[0]
		if point.y < top.heights.x - 0.24:
			return result
		for port in tops:
			if edge_distance(port.edge, horizontal) < edge_distance(top.edge, horizontal):
				top = port
		max_height = surface_elevation(top.heights.x)
		min_height = max_height
		edges.append(top.edge)
		if kind == "roof":
			min_height -= roundi(catalog.roof_rise(item) * 1000.0)
			var first: Vector2i = (top.edge - DIRECTIONS[top.side]) / 2
			roof_cells = [first, top.edge - first]
			for location in roof_cells:
				for side in 4:
					var edge := edge_key(location, side)
					if edge not in edges:
						edges.append(edge)
	elif support_kind in ["roof", "gable", "ridge"]:
		if support_kind == "gable" and support.get("edgeFacing", support.turns) != support.turns:
			focus += DIRECTIONS[support.turns]
		var roles := ["roof_pitch", "crest", "gable_pitch", "ridge"] if kind == "roof" else ["roof_pitch"]
		for port in edge_interfaces(support):
			if port.role in roles and (support_kind != "roof" or kind == "gable" or edge_distance(port.edge, horizontal) <= catalog.cell_size * 0.225 + TOLERANCE):
				edges.append(port.edge)
	else:
		return result
	var ranked: Array[Dictionary] = []
	for edge in edges:
		for port: Dictionary in interfaces_by_edge.get(edge, []):
			if port.owner == ignore:
				continue
			for spec: Array in Data.PLACEMENT_PROFILES[kind].interfaces:
				var role: String = spec[0]
				if not compatible_interfaces(port.role, role):
					continue
				for side in [port.side, (int(port.side) + 2) % 4]:
					var turns := posmod(int(side) - maxi(0, spec[1]), 4)
					var snap := interface_target(item, turns, port, role, side)
					if snap.is_empty() or snap.elevation < min_height or snap.elevation > max_height:
						continue
					var location: Vector2i = snap.location
					if kind == "roof" and not roof_cells.is_empty() and location not in roof_cells:
						continue
					if kind == "roof" and support_kind == "roof" and location == focus:
						continue
					var p := {"item": item, "x": location.x, "z": location.y, "turns": turns, "elevation": snap.elevation}
					if kind == "gable":
						p.edgeFacing = (turns + 2) % 4 if location + DIRECTIONS[turns] == focus else turns
					if p in result:
						continue
					result.append(p)
					ranked.append({
						"placement": p, "score": roof_connections(p, ignore),
						"distance": edge_distance(edge, horizontal),
						"preferred": kind == "roof" and support_kind == "gable" and location == focus,
					})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.preferred != b.preferred:
			return a.preferred
		if kind == "gable" and support_kind in ["floor", "roof"] and not is_equal_approx(a.distance, b.distance):
			return a.distance < b.distance
		if a.score != b.score:
			return a.score > b.score
		return a.distance < b.distance
	)
	result.clear()
	for candidate in ranked:
		result.append(candidate.placement)
	return result


func reaches_shore(locations: Array[Vector2i]) -> bool:
	for location in locations:
		if within_island(location):
			return true
		for direction: Vector2i in DIRECTIONS:
			if within_island(location + direction):
				return true
	return false


func keeps_water_support(index: int, replacement: Dictionary = {}) -> bool:
	if index < 0 or not harbor_water.has_area():
		return true
	var previous: Dictionary = placements[index]
	if layer(previous) != "floor" or previous.elevation != 0:
		return true
	var vacated: Array[Vector2i] = []
	var kept: Array[Vector2i] = []
	if not replacement.is_empty() and replacement.elevation == 0 and layer(replacement) == "floor":
		kept = cells(replacement)
	for location in cells(previous):
		if harbor_water.has_point(Vector2(location) * catalog.cell_size) and location not in kept:
			vacated.append(location)
	if vacated.is_empty():
		return true
	for i in placements.size():
		if i == index:
			continue
		var other: Dictionary = placements[i]
		var edge := layer(other) in ["edge", "gable"]
		var facing: Vector2i = DIRECTIONS[other.get("edgeFacing", other.turns)]
		for location in touched_cells(other, placement_bounds(other)):
			if edge:
				var across := location + facing
				if location not in vacated and across not in vacated:
					continue
				if location in kept or across in kept or can_anchor_cell(location, false, index) or can_anchor_cell(across, false, index):
					continue
			elif location not in vacated:
				continue
			return false
	return true


func stair_entrance_blocked(stairs: Dictionary, edge: Dictionary) -> bool:
	var entrance := edge_key(stair_end(stairs, stairs.turns), stairs.turns)
	return edge.elevation == stairs.elevation and slot("edge", entrance, stairs.elevation) in slots(edge)


func stair_edge_fits(stairs: Dictionary, edge: Dictionary, overlap: AABB) -> bool:
	var edges := slots(edge)
	var turns: int = stairs.turns
	var side_depth := overlap.size.x if turns % 2 == 0 else overlap.size.z
	# Side walls can occupy the outer strip of the stair without blocking passage.
	if side_depth <= STAIR_EDGE_INSET + TOLERANCE:
		for location in cells(stairs):
			for side in [(turns + 1) % 4, (turns + 3) % 4]:
				if slot("edge", edge_key(location, side), edge.elevation) in edges:
					return true

	# The end wall can meet the ramp below the landing height.
	var exit := (turns + 2) % 4
	var upper: int = stairs.elevation + catalog.storey_mm
	var end_depth := overlap.size.z if turns % 2 == 0 else overlap.size.x
	return edge.item in ["wall", "halfWall", "brickWall"] and edge.elevation == stairs.elevation \
		and end_depth <= STAIR_EDGE_INSET + TOLERANCE \
		and slot("edge", edge_key(stair_end(stairs, exit), exit), edge.elevation) in edges \
		and overlap.end.y <= floor_center(upper) + TOLERANCE


func connection_snap(item: String, hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return {}
	var kind: String = catalog.items[item].layer
	var point: Vector3 = hit.position
	var owner: int = hit.collider.get_meta("placement", -1)
	if owner < 0:
		return {}
	var support: Dictionary = placements[owner]
	var support_kind := layer(support)
	if kind == "edge":
		if support_kind == "edge":
			return wall_snap(support, hit)
		if support_kind == "roof":
			return wall_under_roof(item, support, point)
		if support_kind == "ridge" and not support.get("surfaceRidge", false):
			var ridge: Dictionary = edge_interfaces(support, "ridge")[0]
			for port: Dictionary in interfaces_by_edge.get(ridge.edge, []):
				if interface_matches(ridge, port):
					var snap := wall_under_roof(item, placements[port.owner], point)
					if not snap.is_empty():
						return snap
		if support_kind == "gable":
			return wall_snap(support, hit, true)
	return {}


func wall_under_roof(item: String, roof: Dictionary, point: Vector3) -> Dictionary:
	var local := placement_transform(roof).affine_inverse() * point
	var closest := catalog.cell_size * 0.225 + TOLERANCE
	var result := {}
	for port in edge_interfaces(roof):
		if not compatible_interfaces(port.role, "wall_top"):
			continue
		var side: int = (port.side - int(roof.turns) + 4) % 4
		var distance := absf(Vector2(local.x, local.z).dot(Vector2(DIRECTIONS[side])) - catalog.cell_size / 2.0)
		if distance >= closest:
			continue
		var snap := interface_target(item, port.side, port, "wall_top")
		if snap.is_empty():
			continue
		var span := width({"item": item, "turns": port.side})
		var horizontal := Vector2(point.x, point.z) - Vector2(span - Vector2i.ONE + DIRECTIONS[port.side]) * catalog.cell_size / 2.0
		var first: Vector2i = snap.location
		var last := first + Vector2i.ONE - span
		snap.location = grid_cell(horizontal).clamp(first.min(last), first.max(last))
		snap.reversible = true
		closest = distance
		result = snap
	return result


func wall_snap(wall: Dictionary, hit: Dictionary, corner_only := false) -> Dictionary:
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var turns: int = wall.turns
	var along: Vector2i = DIRECTIONS[(turns + 1) % 4]
	var facing: Vector2i = DIRECTIONS[turns]
	var span: int = catalog.items[wall.item].width
	var horizontal := Vector2(point.x, point.z)
	var midpoint := center(wall)
	var offset := (horizontal - midpoint).dot(Vector2(along))
	var at_end := absf(offset) >= (span / 2.0 - 0.18) * catalog.cell_size
	var hits_end_face := absf(Vector2(normal.x, normal.z).dot(Vector2(along))) > 0.5
	var top: float = edge_interfaces(wall, "wall_top")[0].heights.x if not corner_only else point.y
	if not corner_only and point.y >= top - 0.10 and not (at_end and hits_end_face):
		return {"turns": turns, "wall": wall, "top": top, "point": horizontal}
	if at_end:
		var end_direction := along if offset > 0.0 else -along
		return {
			"turns": turns, "wall": wall, "endDirection": end_direction,
			"endpoint": grid_cell(midpoint, catalog.cell_size / 2) + end_direction * span,
			"inside": -facing, "cornerOnly": corner_only,
		}
	return {}


func wall_snap_target(p: Dictionary, snap: Dictionary) -> Dictionary:
	var direction: Vector2i = DIRECTIONS[p.turns]
	var span := width(p)
	var wall: Dictionary = snap.wall
	var location: Vector2i
	if snap.has("top"):
		if p.turns % 2 != snap.turns % 2:
			return {}
		var horizontal: Vector2 = snap.point - (Vector2(span - Vector2i.ONE + direction) * catalog.cell_size / 2.0)
		var first := cell(wall)
		if p.turns != snap.turns:
			first += DIRECTIONS[snap.turns]
		var last := first + width(wall) - span
		location = grid_cell(horizontal).clamp(first.min(last), first.max(last))
		p.elevation = surface_elevation(snap.top)
	else:
		var extension: Vector2i
		if p.turns % 2 == snap.turns % 2:
			if snap.get("cornerOnly", false):
				return {}
			extension = snap.endDirection
		elif direction == snap.endDirection:
			extension = snap.inside
		else:
			extension = -snap.inside
		var length: int = catalog.items[p.item].width
		var midpoint: Vector2i = snap.endpoint + extension * length
		location = (midpoint - direction - (span - Vector2i.ONE)) / 2
		p.elevation = wall.elevation
	p.x = location.x
	p.z = location.y
	return p


func target(item: String, turns: int, hit: Dictionary, viewer: Vector3, snap: Dictionary = {}) -> Dictionary:
	if hit.is_empty():
		return {}
	var point: Vector3 = hit.position
	var horizontal := Vector2(point.x, point.z)
	var p := {"item": item, "turns": turns, "elevation": 0}
	if not snap.is_empty():
		if snap.has("location"):
			var location: Vector2i = snap.location
			if turns != snap.turns:
				if not snap.get("reversible", false) or turns % 2 != snap.turns % 2:
					return {}
				location += DIRECTIONS[snap.turns]
			p.x = location.x
			p.z = location.y
			p.elevation = snap.elevation
			return p
		return wall_snap_target(p, snap)
	var kind := layer(p)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var owner: int = hit.collider.get_meta("placement", -1)
	if owner >= 0:
		var support: Dictionary = placements[owner]
		var support_kind := layer(support)
		var bounds := placement_bounds(support)
		if kind == "edge" and (support_kind in ["roof", "gable"] or (support_kind == "ridge" and not support.get("surfaceRidge", false))):
			return {}
		if kind == "ridge" and snap_ridge(p, support):
			return p
		if (kind == "roof" or kind == "gable") and support_kind in ["roof", "gable", "ridge"]:
			return {}
		if support_kind == "floor":
			if kind == "floor":
				var side := floor_side(support, horizontal)
				if side >= 0:
					var adjacent := adjacent_floor(p, support, grid_cell(horizontal), DIRECTIONS[side])
					p.x = adjacent.x
					p.z = adjacent.y
					p.elevation = support.elevation
					return p
			if viewer.y <= bounds.end.y or point.y < bounds.end.y - 0.035:
				return {}
			if kind in ["edge", "gable", "roof"] or item == "stairs":
				p.elevation = support.elevation
			else:
				p.elevation = surface_elevation(bounds.end.y + (SLAB / 2.0 if kind == "floor" else 0.0))
			if kind == "gable":
				# Reversing the triangle keeps it on the same floor edge.
				var floor_cell := grid_cell(horizontal).clamp(cell(support), cell(support) + width(support) - Vector2i.ONE)
				var direction: Vector2i = DIRECTIONS[turns]
				horizontal = Vector2(floor_cell) * catalog.cell_size
				var offset := Vector2(point.x, point.z) - horizontal
				var edge_distance := maxf(absf(offset.x), absf(offset.y))
				if edge_distance >= catalog.cell_size * 0.275:
					var distance := offset.dot(Vector2(direction))
					if absf(distance) + TOLERANCE < edge_distance:
						return {}
					p.edgeFacing = turns if distance > 0.0 else (turns + 2) % 4
					if distance < 0.0:
						horizontal -= Vector2(direction) * catalog.cell_size
		elif support.item == "stairs" and (kind == "floor" or item == "stairs") and bounds.end.y - point.y <= 0.15:
			p.elevation = support.elevation + catalog.storey_mm
			var landing := stair_landing(support)
			if item == "stairs":
				if turns == (int(support.turns) + 2) % 4:
					landing = stair_end(support, turns)
				var anchor := landing - stair_end({"item": item, "turns": turns, "x": 0, "z": 0}, turns)
				p.x = anchor.x
				p.z = anchor.y
				return p
			horizontal = Vector2(landing) * catalog.cell_size
		elif kind == "floor" and (support_kind == "edge" or catalog.items[support.item].get("floor_support", false)) and bounds.end.y - point.y <= 0.10:
			p.elevation = surface_elevation(bounds.end.y)
			var midpoint := center(support)
			if support_kind == "edge":
				var along_x := int(support.turns) % 2 != 0
				var delta := horizontal.x - midpoint.x if along_x else horizontal.y - midpoint.y
				if absf(delta) < 0.012:
					delta = viewer.x - midpoint.x if along_x else viewer.z - midpoint.y
				var side := 1.0 if delta >= 0.0 else -1.0
				if along_x:
					horizontal.x = midpoint.x + side * catalog.cell_size / 2
				else:
					horizontal.y = midpoint.y + side * catalog.cell_size / 2
			else:
				horizontal = midpoint
		elif normal.y > 0.5:
			p.elevation = surface_elevation(point.y + (SLAB / 2.0 if kind == "floor" else 0.0))
		else:
			return {}
	elif hit.collider.has_meta("scenery"):
		if normal.y <= 0.5:
			return {}
		p.elevation = surface_elevation(point.y + (SLAB / 2.0 if kind == "floor" else 0.0))
	if kind == "ridge":
		p.surfaceRidge = true
	if kind == "gable" and not p.has("edgeFacing"):
		p.edgeFacing = turns
	if kind in ["floor", "object", "roof"] and not fine(p):
		horizontal -= (Vector2(width(p)) - Vector2.ONE) * catalog.cell_size / 2.0
	var location := grid_cell(horizontal)
	if fine(p):
		var subdivisions := grid_cell(horizontal, catalog.cell_size / 5)
		location = grid_cell(Vector2(subdivisions), 5)
		var offset := subdivisions - location * 5
		p.offsetX = offset.x
		p.offsetZ = offset.y
	p.x = location.x
	p.z = location.y
	return p


func nearby_edge_targets(item: String, hit: Dictionary, viewer: Vector3) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if hit.is_empty() or catalog.items[item].layer != "edge":
		return candidates
	var point: Vector3 = hit.position
	var horizontal := Vector2(point.x, point.z)
	var aim_cell := grid_cell(horizontal)
	var elevation := 0
	var owner: int = hit.collider.get_meta("placement", -1)
	if owner >= 0:
		var support: Dictionary = placements[owner]
		if layer(support) != "floor" or absf(point.y - floor_top(support.elevation)) > SLAB + TOLERANCE:
			return candidates
		aim_cell = aim_cell.clamp(cell(support), cell(support) + width(support) - Vector2i.ONE)
		elevation = support.elevation
	elif hit.collider.has_meta("scenery"):
		return candidates
	for side in 4:
		var facing: Vector2i = DIRECTIONS[side]
		var along: Vector2i = DIRECTIONS[(side + 1) % 4]
		var length: int = catalog.items[item].width
		var first := grid_cell(horizontal - Vector2(facing + along.abs() * (length - 1)) * catalog.cell_size / 2.0)
		if along.x != 0:
			first.y = aim_cell.y
		else:
			first.x = aim_cell.x
		for turns in [side, (side + 2) % 4]:
			var location := first if turns == side else first + facing
			candidates.append({"item": item, "x": location.x, "z": location.y, "turns": turns, "elevation": elevation})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return edge_target_score(a, point, viewer) < edge_target_score(b, point, viewer)
	)
	return candidates


func opening_edge_targets(item: String, viewer: Vector3, ray_end: Vector3, ignore: int = -1) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var info: Dictionary = catalog.items[item]
	if not ray_end.is_finite() or info.subcategory not in ["walls", "openings"] or info.width != 1 or info.depth != 1:
		return candidates
	var wall_bounds := catalog.item_bounds(item)
	var openings := {}
	for support: Dictionary in placements:
		if layer(support) not in ["roof", "gable"]:
			continue
		# A wall can extend down from the roof, and across the grid line by half its thickness.
		var search := placement_bounds(support).grow(wall_bounds.size.z / 2.0 + TOLERANCE)
		search.position.y -= wall_bounds.size.y
		search.size.y += wall_bounds.size.y
		if search.intersects_segment(viewer, ray_end) == null:
			continue
		for port in edge_interfaces(support):
			if port.role not in ["eave", "crest", "gable_base"]:
				continue
			var snap := interface_target(item, port.side, port, "wall_top")
			if snap.is_empty():
				continue
			var key := slot("edge", port.edge, snap.elevation)
			if openings.has(key) or occupied.get(key, ignore) != ignore:
				continue
			var location: Vector2i = snap.location
			var across: Vector2i = location + DIRECTIONS[snap.turns]
			var has_near_floor := has_floor(location, snap.elevation, ignore)
			var has_far_floor := has_floor(across, snap.elevation, ignore)
			if not has_near_floor and not has_far_floor:
				continue
			var p := {"item": item, "x": location.x, "z": location.y, "turns": snap.turns, "elevation": snap.elevation}
			var point: Variant = placement_bounds(p, ignore).intersects_segment(viewer, ray_end)
			if point == null:
				continue
			var reverse := {"item": item, "x": across.x, "z": across.y, "turns": (int(snap.turns) + 2) % 4, "elevation": snap.elevation}
			var prefer_reverse := has_far_floor and (not has_near_floor or edge_target_score(reverse, point, viewer) < edge_target_score(p, point, viewer))
			openings[key] = {"distance": viewer.distance_squared_to(point), "placements": [reverse, p] if prefer_reverse else [p, reverse]}
	var ranked := openings.values()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	for opening: Dictionary in ranked:
		candidates.append_array(opening.placements)
	return candidates


func edge_target_score(p: Dictionary, point: Vector3, viewer: Vector3) -> float:
	var facing := Vector2(DIRECTIONS[p.turns])
	var delta := Vector2(point.x, point.z) - center(p)
	var along := Vector2(-facing.y, facing.x)
	var half_length: float = catalog.items[p.item].width * catalog.cell_size / 2.0
	var distance := Vector2(delta.dot(facing), maxf(0.0, absf(delta.dot(along)) - half_length)).length()
	var away := Vector2(point.x - viewer.x, point.z - viewer.z).normalized()
	return distance - facing.dot(away) * 0.012


func surface_elevation(y: float) -> int:
	return maxi(0, roundi((y - GROUND) * 1000.0))


func snap_ridge(p: Dictionary, support: Dictionary) -> bool:
	if layer(support) != "roof":
		return false
	var crest := edge_interfaces(support, "crest")[0]
	var snap := interface_target(p.item, p.turns, crest, "ridge")
	if snap.is_empty():
		return false
	var location: Vector2i = snap.location
	p.x = location.x
	p.z = location.y
	p.elevation = snap.elevation
	return true


func floor_side(support: Dictionary, point: Vector2) -> int:
	return nearest_edge(point - center(support), Vector2(width(support)) * catalog.cell_size / 2.0)


func nearest_edge(offset: Vector2, half: Vector2) -> int:
	var closest := catalog.cell_size * 0.225 + TOLERANCE
	var side := -1
	for turns in 4:
		var direction := Vector2(DIRECTIONS[turns])
		var distance := half.dot(direction.abs()) - offset.dot(direction)
		if distance < closest:
			closest = distance
			side = turns
	return side


func adjacent_floor(p: Dictionary, support: Dictionary, hit_cell: Vector2i, direction: Vector2i) -> Vector2i:
	var origin := cell(support)
	var span := width(support)
	var size := width(p)
	if direction.x != 0:
		return Vector2i(
			origin.x + (span.x if direction.x > 0 else -size.x),
			clampi(hit_cell.y, origin.y, origin.y + maxi(0, span.y - size.y))
		)
	return Vector2i(
		clampi(hit_cell.x, origin.x, origin.x + maxi(0, span.x - size.x)),
		origin.y + (span.y if direction.y > 0 else -size.y)
	)


func create_body(p: Dictionary) -> StaticBody3D:
	if not catalog.available(p.item):
		return null
	var body: StaticBody3D
	var info: Dictionary = catalog.items[p.item]
	var seat_count: int = info.get("seats", 0)
	if seat_count > 0:
		var seat := Seat.new()
		seat.seat_count = seat_count
		seat.seat_bounds = catalog.item_bounds(p.item)
		seat.seat_height = seat.seat_bounds.position.y + seat.seat_bounds.size.y * float(info.get("seat_height_ratio", 1.0))
		seat.front_side = info.get("seat_front", 0.0)
		body = seat
	elif p.get("opening") == "woodDoor":
		body = Door.new()
	else:
		body = StaticBody3D.new()
	body.collision_layer = 16 if layer(p) == "floor" or p.item == "stairs" else 2
	body.collision_mask = 0
	add_parts(body, p)
	container.add_child(body)
	return body


func add_parts(body: StaticBody3D, p: Dictionary) -> void:
	var height := rise(p)
	var visual := catalog.visuals(p.get("opening", p.item), height)
	body.add_child(visual)
	var shape := shape_kind(p)
	if shape == "slab":
		var bounds := slab_bounds(p)
		catalog.box_shape(body, bounds.size, bounds.get_center())
	elif p.item == "stairs":
		var ramp := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		var half_depth := catalog.cell_size * int(catalog.items.stairs.depth) / 2.0
		for x in [-catalog.cell_size / 2, catalog.cell_size / 2]:
			points.append(Vector3(x, -0.016, half_depth))
			points.append(Vector3(x, 0, half_depth))
			points.append(Vector3(x, -0.016, -half_depth))
			points.append(Vector3(x, height, -half_depth))
		ramp.points = points
		var collider := CollisionShape3D.new()
		collider.shape = ramp
		body.add_child(collider)
		body.set_meta("rise", height)
	elif p.has("opening"):
		add_wall_opening_shapes(body, catalog.wall_opening(p.opening))
		if body is Door:
			body.setup_panel(catalog, visual)
	elif shape == "box":
		var bounds := catalog.item_bounds(p.item)
		catalog.box_shape(body, bounds.size, bounds.get_center())
	else:
		catalog.collider_meshes(body, visual)


func add_wall_opening_shapes(body: StaticBody3D, opening: Rect2) -> void:
	var sections := [
		Rect2(-catalog.cell_size / 2.0, 0, opening.position.x + catalog.cell_size / 2.0, catalog.wall_height),
		Rect2(opening.end.x, 0, catalog.cell_size / 2.0 - opening.end.x, catalog.wall_height),
		Rect2(opening.position.x, opening.end.y, opening.size.x, catalog.wall_height - opening.end.y),
	]
	if opening.position.y > 0.0:
		sections.append(Rect2(opening.position.x, 0, opening.size.x, opening.position.y))
	for section: Rect2 in sections:
		var midpoint := section.get_center()
		var size := Vector3(section.size.x, section.size.y, Catalog.WALL_DEPTH)
		var collision := catalog.box_shape(body, size, Vector3(midpoint.x, midpoint.y, 0))
		collision.set_meta("wall_span", Vector2(section.position.y, section.end.y))

	# Build mode can select any opening. Interaction can also target an open door.
	var pick := StaticBody3D.new()
	pick.name = "OpeningPick"
	pick.collision_layer = OPENING_PICK_LAYER | DOOR_PICK_LAYER if body is Door else OPENING_PICK_LAYER
	pick.collision_mask = 0
	body.add_child(pick)
	var midpoint := opening.get_center()
	var size := Vector3(opening.size.x, opening.size.y, Catalog.WALL_DEPTH)
	catalog.box_shape(pick, size, Vector3(midpoint.x, midpoint.y, 0))


func sync() -> void:
	occupied.clear()
	interfaces_by_edge.clear()
	for i in range(placements.size()):
		for key in slots(placements[i]):
			occupied[key] = i
	for i in range(placements.size()):
		var body := bodies[i]
		if body == null:
			continue
		var p: Dictionary = placements[i]
		if layer(p) == "gable" and not p.has("edgeFacing"):
			# Older saves inferred the inset from the wall on this edge.
			var edge: Vector2i = cell(p) * 2 + DIRECTIONS[p.turns]
			var wall := support_at(slot("edge", edge, p.elevation - catalog.storey_mm))
			p.edgeFacing = wall.get("turns", p.turns)
		if p.item == "stairs" and not is_equal_approx(body.get_meta("rise"), rise(p)):
			for child in body.get_children():
				child.free()
			add_parts(body, p)
		elif shape_kind(p) == "box":
			sync_landing_wall(p, body)
		body.set_meta("placement", i)
		body.transform = placement_transform(p)
		body.reset_physics_interpolation()
		for port in edge_interfaces(p):
			port.owner = i
			if not interfaces_by_edge.has(port.edge):
				interfaces_by_edge[port.edge] = []
			interfaces_by_edge[port.edge].append(port)
	for i in placements.size():
		var p: Dictionary = placements[i]
		if bodies[i] != null and layer(p) in ["roof", "ridge"]:
			var mesh := bodies[i].get_child(0).get_child(0) as MeshInstance3D
			mesh.mesh = catalog.roof_model(p.item, visual_joins(p))
	rebuild_walk_surface()


func visual_joins(p: Dictionary, ignore: int = -1) -> int:
	if layer(p) in ["roof", "ridge"]:
		return roof_joins(p, ignore)
	return 0


func roof_joins(p: Dictionary, ignore: int) -> int:
	var kind := layer(p)
	var mask := 0
	var turns: int = p.turns
	var direction: Vector2i = DIRECTIONS[turns]
	for side in 2:
		var along: Vector2i = DIRECTIONS[(turns + (3 if side == 0 else 1)) % 4]
		var location := cell(p) + along
		if kind == "ridge":
			location = location * 2 + direction
		var neighbor := support_at(slot(kind, location, p.elevation), ignore)
		if neighbor.is_empty():
			continue
		var same_profile: bool = neighbor.item == p.item and neighbor.turns == turns if kind == "roof" else neighbor.get("surfaceRidge", false) == p.get("surfaceRidge", false)
		if same_profile:
			mask |= Catalog.RoofKit.OMIT_LEFT if side == 0 else Catalog.RoofKit.OMIT_RIGHT
	if kind == "roof":
		var crest: Dictionary = edge_interfaces(p, "crest")[0]
		for port: Dictionary in interfaces_by_edge.get(crest.edge, []):
			if port.owner != ignore and port.side != crest.side and port.role == "crest" and interface_matches(crest, port):
				mask |= Catalog.RoofKit.OMIT_HIGH
				break
	return mask


func sync_landing_wall(wall: Dictionary, body: StaticBody3D) -> void:
	var location := cell(wall)
	var turns: int = wall.turns
	var bounds := catalog.item_bounds(wall.item)
	var top := bounds.end.y
	# The centered wall crosses the stair exit from either adjoining cell.
	if is_stair_at(location, (turns + 2) % 4, wall.elevation) \
		or is_stair_at(location + DIRECTIONS[turns], turns, wall.elevation):
		var depth := catalog.cell_size * int(catalog.items.stairs.depth)
		var ramp_at_wall := catalog.wall_height * (1.0 - bounds.size.z / (2.0 * depth))
		top = clampf(ramp_at_wall - 0.01, bounds.position.y + 0.01, top)
	if not wall.has("opening"):
		resize_wall_collision(body.get_child(1) as CollisionShape3D, bounds.position.y, top)
		return
	for child in body.get_children():
		if child.has_meta("wall_span"):
			var span: Vector2 = child.get_meta("wall_span")
			resize_wall_collision(child as CollisionShape3D, span.x, minf(span.y, top))


func resize_wall_collision(collision: CollisionShape3D, bottom: float, top: float) -> void:
	collision.disabled = top <= bottom
	if collision.disabled:
		return
	var shape := collision.shape as BoxShape3D
	shape.size.y = top - bottom
	collision.position.y = (bottom + top) / 2.0


func is_stair_at(location: Vector2i, turns: int, elevation: int) -> bool:
	var index: int = occupied.get(slot("object", location, elevation), -1)
	if index < 0:
		return false
	var p: Dictionary = placements[index]
	return p.item == "stairs" and int(p.turns) == turns \
		and stair_end(p, (turns + 2) % 4) == location


func rebuild_walk_surface() -> void:
	# A shared mesh lets the engine resolve ramp and slab edges as one surface.
	# Per-piece bodies remain available for picking in build mode.
	var faces := PackedVector3Array()
	var landings: Dictionary = {}
	for p: Dictionary in placements:
		if p.item == "stairs":
			var exit: Vector2i = DIRECTIONS[(p.turns + 2) % 4]
			landings[slot("edge", stair_landing(p) * 2 - exit, p.elevation + catalog.storey_mm)] = true
	for p: Dictionary in placements:
		if layer(p) == "floor":
			var top := floor_top(p.elevation)
			for location in cells(p):
				var midpoint := Vector2(location) * catalog.cell_size
				var transform := Transform3D(Basis.IDENTITY, Vector3(midpoint.x, top - SLAB, midpoint.y))
				var sides: Array[bool] = []
				for side: Vector2i in DIRECTIONS:
					sides.append(not has_floor(location + side, p.elevation) and not landings.has(slot("edge", location * 2 + side, p.elevation)))
				append_walk_faces(faces, transform, SLAB, SLAB, 0.0, sides, catalog.cell_size)
		elif p.item == "stairs":
			var sides: Array[bool] = [true, true, not has_floor(stair_landing(p), p.elevation + catalog.storey_mm), true]
			var depth := catalog.cell_size * int(catalog.items.stairs.depth)
			append_walk_faces(faces, placement_transform(p), 0.0, rise(p), -0.016, sides, depth)
	if faces.is_empty():
		walk_shape.shape = null
	else:
		var mesh := ConcavePolygonShape3D.new()
		mesh.set_faces(faces)
		walk_shape.shape = mesh


func append_walk_faces(faces: PackedVector3Array, transform: Transform3D, front: float, back: float, bottom: float, sides: Array[bool], depth: float) -> void:
	var half := catalog.cell_size / 2.0
	var half_depth := depth / 2.0
	var corners := [
		Vector3(-half, front, half_depth), Vector3(half, front, half_depth),
		Vector3(half, back, -half_depth), Vector3(-half, back, -half_depth),
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
		replace_body(index, p)
	sync()
	return index


func replace_body(index: int, p: Dictionary) -> void:
	if bodies[index] != null:
		bodies[index].free()
	placements[index] = p
	bodies[index] = create_body(p)


func can_set_wall_opening(index: int, opening: String) -> bool:
	if index < 0 or index >= placements.size() or bodies[index] == null:
		return false
	var wall: Dictionary = placements[index]
	return wall.item == "wall" and wall.get("opening", "") != opening \
		and (opening.is_empty() or (opening in Catalog.WOOD_OPENINGS and catalog.available(opening)))


func set_wall_opening(index: int, opening: String) -> bool:
	if not can_set_wall_opening(index, opening):
		return false
	var wall: Dictionary = placements[index].duplicate()
	if opening.is_empty():
		wall.erase("opening")
	else:
		wall.opening = opening
	replace_body(index, wall)
	sync()
	return true


func remove(index: int) -> bool:
	if not keeps_water_support(index):
		return false
	if bodies[index] != null:
		bodies[index].free()
	bodies.remove_at(index)
	placements.remove_at(index)
	sync()
	return true
