extends RefCounted

const SAVE := "user://islands.json"
const Catalog = preload("res://godot/catalog.gd")
const Builder = preload("res://godot/builder.gd")
const SLAB_MM := roundi(Catalog.SLAB * 1000.0)
const OLD_STOREY := roundi(Catalog.Data.LEGACY_WALL_HEIGHT * 1000.0) + SLAB_MM
const GOLDEN_GRID := "golden"
const LEGACY_GRID := "legacy"
const STONE_HEIGHT_MM := roundi(Catalog.Data.PREVIOUS_STONE_LOW_HEIGHT * 1000.0)
const BASE_SIZE := Vector2i(14, 10)
const MAX_SIZE := Vector2i(24, 24)
const EXPANSION_SIZES := [Vector2i(17, 14), Vector2i(20, 20), MAX_SIZE]
const SAVE_CELL_LIMIT := Vector2i(
	maxi(16, ceili(MAX_SIZE.x / (2.0 * Catalog.Data.LEGACY_CELL))),
	maxi(16, ceili(MAX_SIZE.y / (2.0 * Catalog.Data.LEGACY_CELL)))
)

var state: Dictionary
var catalog: Catalog
var legacy_catalog: Catalog
var save_path: String


func _init(assets: Catalog, path: String = SAVE) -> void:
	catalog = assets
	legacy_catalog = Catalog.new(true)
	save_path = path
	state = read_file(save_path)
	if state.is_empty():
		state = {
			"activeId": "flat",
			"floorCenters": true,
			"islands": [
				{"id": "flat", "name": "平坦岛", "terrain": "flat", "grid": GOLDEN_GRID, "wallHeightModules": true, "placements": []},
				{"id": "cabin", "name": "木屋岛", "terrain": "cabin", "grid": GOLDEN_GRID, "wallHeightModules": true, "placements": []},
			],
		}
	if state.get("defaultHarborAdded") != true and not state.islands.any(func(island: Dictionary): return island.terrain == "harbor"):
		var id := "harbor"
		while state.islands.any(func(island: Dictionary): return island.id == id):
			id += "-default"
		state.islands.append({
			"id": id, "name": "港口岛", "terrain": "harbor", "grid": GOLDEN_GRID, "wallHeightModules": true,
			"placements": [
				{"item": "harborDock", "x": 2, "z": -2, "turns": 0, "elevation": 0},
				{"item": "harborDock", "x": 2, "z": 2, "turns": 0, "elevation": 0},
				{"item": "harborRope", "x": 3, "z": -1, "turns": 1, "elevation": 0},
				{"item": "harborBarrel", "x": 0, "z": -2, "turns": 0, "elevation": 0},
			],
		})
	state.defaultHarborAdded = true


func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("islands") is Array:
		return {}
	var legacy: bool = parsed.get("floorCenters") != true
	var islands: Array[Dictionary] = []
	var ids: Array[String] = []
	for value in parsed.islands:
		if not value is Dictionary:
			continue
		var id: Variant = value.get("id")
		var title: Variant = value.get("name")
		var terrain: Variant = value.get("terrain")
		if not id is String or id.is_empty() or id in ids or not title is String or terrain not in ["flat", "cabin", "harbor"] or not value.get("placements") is Array:
			continue
		var placements: Array[Dictionary] = []
		var grid := GOLDEN_GRID if value.get("grid") == GOLDEN_GRID else LEGACY_GRID
		var assets := catalog if grid == GOLDEN_GRID else legacy_catalog
		for raw in value.placements:
			var p := read_placement(raw, legacy and grid == LEGACY_GRID, assets)
			if not p.is_empty() and not placements.has(p):
				placements.append(p)
		if legacy and grid == LEGACY_GRID:
			center_legacy_floors(placements)
		if grid == GOLDEN_GRID and value.get("wallHeightModules") != true:
			align_stone_wall_stacks(placements)
		ids.append(id)
		var size := island_size(value)
		islands.append({
			"id": id, "name": title, "terrain": terrain, "grid": grid, "placements": placements,
			"wallHeightModules": grid == GOLDEN_GRID,
			"width": size.x, "depth": size.y,
		})
	if islands.is_empty():
		return {}
	var active_id: Variant = parsed.get("activeId")
	return {
		"activeId": active_id if active_id in ids else ids[0], "islands": islands,
		"floorCenters": true, "defaultHarborAdded": parsed.get("defaultHarborAdded") == true,
	}


func read_placement(raw: Variant, legacy: bool, assets: Catalog) -> Dictionary:
	if not raw is Dictionary or not raw.get("item") is String:
		return {}
	var item: String = raw.item
	var opening: Variant = raw.get("opening")
	if item in Catalog.WOOD_OPENINGS:
		opening = item
		item = "wall"
	if not assets.items.has(item) or not assets.items[item].has("layer"):
		return {}
	var result := {"item": item}
	if item == "wall" and opening is String and opening in Catalog.WOOD_OPENINGS and assets.available(opening):
		result.opening = opening
	var fallback_level: Variant = raw.get("level", 1 if item in ["flatRoof", "skylight"] else 0)
	if (not fallback_level is float and not fallback_level is int) or not is_finite(float(fallback_level)) or fallback_level < 0 or fallback_level > 7:
		fallback_level = 0
	for key in ["x", "z", "turns", "elevation"]:
		var value: Variant = raw.get(key, fallback_level * (OLD_STOREY if legacy else assets.storey_mm) if key == "elevation" else null)
		if (not value is int and not value is float) or not is_finite(float(value)) or value != floorf(float(value)) or absf(float(value)) > 8000:
			return {}
		result[key] = int(value)
	var kind: String = assets.items[item].layer
	if result.turns < 0 or result.turns > 3 or result.elevation < Builder.min_elevation(kind, assets.storey_mm, raw.get("surfaceRidge") == true) \
		or absi(result.x) > SAVE_CELL_LIMIT.x or absi(result.z) > SAVE_CELL_LIMIT.y:
		return {}
	if kind == "gable":
		var facing: Variant = raw.get("edgeFacing")
		if (facing is int or facing is float) and (facing == result.turns or facing == (result.turns + 2) % 4):
			result.edgeFacing = int(facing)
	elif kind == "ridge" and raw.get("surfaceRidge") == true:
		result.surfaceRidge = true
	if assets.items[item].get("fine", false):
		for key in ["offsetX", "offsetZ"]:
			var value: Variant = raw.get(key, 0)
			if (value is int or value is float) and absf(float(value)) <= 2 and value == floorf(float(value)):
				result[key] = int(value)
	return result


func align_stone_wall_stacks(placements: Array[Dictionary]) -> void:
	var by_edge := {}
	for p in placements:
		if p.item == "stoneLowWall":
			var edge: Vector2i = Vector2i(p.x, p.z) * 2 + Builder.DIRECTIONS[p.turns]
			if not by_edge.has(edge):
				by_edge[edge] = {}
			by_edge[edge][p.elevation] = p
	var new_height := roundi(catalog.module_height("stoneLowWall") * 1000.0)
	for edge in by_edge:
		var segments: Dictionary = by_edge[edge]
		for base: int in segments:
			if segments.has(base - STONE_HEIGHT_MM):
				continue
			var run: Array[Dictionary] = []
			var height := base
			while segments.has(height):
				run.append(segments[height])
				height += STONE_HEIGHT_MM
			var has_dependents := stone_stack_supports_other_parts(run, placements)
			for i in run.size():
				if has_dependents:
					run[i].item = "stoneLowWallOriginal"
				else:
					run[i].elevation = base + i * new_height


func stone_stack_supports_other_parts(run: Array[Dictionary], placements: Array[Dictionary]) -> bool:
	var wall := run[0]
	var footprint := placement_footprint(wall, "edge", catalog)
	for p in placements:
		if p.item in ["stoneLowWall", "stoneLowWallOriginal"]:
			continue
		var kind: String = catalog.items[p.item].layer
		var bottom: int = p.elevation
		var top := bottom
		if kind in ["roof", "gable", "ridge"]:
			top += roundi(catalog.roof_rise(p.item) * 1000.0)
		if not footprint.grow(0.001).intersects(placement_footprint(p, kind, catalog)):
			continue
		for segment in run:
			var wall_top: int = segment.elevation + STONE_HEIGHT_MM
			if bottom <= wall_top + SLAB_MM / 2 and top >= wall_top:
				return true
	return false


func center_legacy_floors(placements: Array[Dictionary]) -> void:
	var rows: Array[Dictionary] = []
	var floors := {}
	for p in placements:
		var kind: String = legacy_catalog.items[p.item].layer
		var row := {"part": p, "height": p.elevation, "kind": kind, "rect": placement_footprint(p, kind, legacy_catalog)}
		rows.append(row)
		if kind == "floor":
			if not floors.has(p.elevation):
				floors[p.elevation] = []
			floors[p.elevation].append(row)
	if floors.is_empty():
		return
	var priority := ["floor", "edge", "gable", "object", "roof", "ridge"]
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.height != b.height:
			return a.height < b.height
		return priority.find(a.kind) < priority.find(b.kind)
	)
	var surfaces := {}
	for row in rows:
		var p: Dictionary = row.part
		var old_height: int = row.height
		var kind: String = row.kind
		if kind == "floor":
			if not row.get("aligned", false):
				align_legacy_slab_run(row, floors[old_height], surfaces)
			continue
		var sources := ["floor"]
		if kind in ["edge", "gable", "roof"]:
			sources.append_array(["edge", "column"])
		elif kind == "ridge" and not p.get("surfaceRidge", false):
			sources = ["roof"]
		elif p.item == "stairs":
			sources.append("stairs")
		if old_height > 0:
			var support := legacy_surface(row.rect, surfaces.get(old_height, []), sources)
			if not support.is_empty():
				p.elevation = support.elevation
				if support.kind == "floor" and kind not in ["edge", "gable"] and p.item != "stairs":
					p.elevation += SLAB_MM / 2
		if kind == "edge" or legacy_catalog.items[p.item].get("floor_support", false):
			var top := roundi(legacy_catalog.item_bounds(p.item).end.y * 1000.0)
			add_legacy_surface(surfaces, old_height + top, row.rect, p.elevation + top, "edge" if kind == "edge" else "column")
		elif kind == "roof":
			add_legacy_surface(surfaces, old_height, row.rect, p.elevation, kind)
		elif p.item == "stairs":
			var rect: Rect2 = row.rect
			var exit := rect
			exit.position -= Vector2(Builder.DIRECTIONS[p.turns]) * legacy_catalog.cell_size
			add_legacy_surface(surfaces, old_height + OLD_STOREY, exit.merge(rect), p.elevation + legacy_catalog.storey_mm, "stairs")


func align_legacy_slab_run(first: Dictionary, peers: Array, surfaces: Dictionary) -> void:
	var run: Array[Dictionary] = [first]
	first.aligned = true
	var cursor := 0
	while cursor < run.size():
		var rect: Rect2 = run[cursor].rect
		for peer: Dictionary in peers:
			if not peer.get("aligned", false) and rect.grow(0.001).intersects(peer.rect):
				peer.aligned = true
				run.append(peer)
		cursor += 1
	var old_bottom := maxi(0, first.height - SLAB_MM)
	var elevation := old_bottom
	if first.height > 0:
		var best := 0.0
		for row in run:
			var support := legacy_surface(row.rect, surfaces.get(old_bottom, []), ["edge", "column", "stairs", "floor"])
			if support.get("area", 0.0) > best:
				best = support.area
				elevation = support.elevation + (SLAB_MM if support.kind == "floor" else 0)
	var old_top := maxi(SLAB_MM, first.height)
	for row in run:
		row.part.elevation = elevation
		add_legacy_surface(surfaces, old_top, row.rect, elevation, "floor")


func placement_footprint(p: Dictionary, kind: String, assets: Catalog) -> Rect2:
	var info: Dictionary = assets.items[p.item]
	var span := Vector2(info.width, info.depth) if int(p.turns) % 2 == 0 else Vector2(info.depth, info.width)
	var center := (Vector2(p.x, p.z) + (span - Vector2.ONE) / 2.0) * assets.cell_size
	if kind == "floor" or p.item == "stairs":
		var size := span * assets.cell_size
		return Rect2(center - size / 2.0, size)
	var bounds := assets.item_bounds(p.item)
	if kind in ["edge", "gable", "ridge"]:
		var inset := bounds.get_center().z if kind != "ridge" else 0.0
		center += Vector2(Builder.DIRECTIONS[p.turns]) * (assets.cell_size / 2.0 - inset)
	elif info.get("fine", false):
		center += Vector2(p.get("offsetX", 0), p.get("offsetZ", 0)) * assets.cell_size / 5.0
	var footprint := Transform3D(Basis(Vector3.UP, p.turns * PI / 2.0), Vector3(center.x, 0, center.y)) * bounds
	return Rect2(Vector2(footprint.position.x, footprint.position.z), Vector2(footprint.size.x, footprint.size.z))


func add_legacy_surface(surfaces: Dictionary, height: int, rect: Rect2, elevation: int, kind: String) -> void:
	if not surfaces.has(height):
		surfaces[height] = []
	surfaces[height].append({"rect": rect, "elevation": elevation, "kind": kind})


func legacy_surface(rect: Rect2, surfaces: Array, kinds: Array) -> Dictionary:
	var result := {}
	var best := 0.0001
	for surface: Dictionary in surfaces:
		if surface.kind not in kinds:
			continue
		var area := rect.intersection(surface.rect).get_area()
		if area > best:
			best = area
			result = surface.duplicate()
			result.area = area
	return result


func write(candidate: Dictionary = state) -> bool:
	return write_file(save_path, candidate)


func write_file(path: String, snapshot: Dictionary) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(snapshot))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)
	) == OK


func find_island(id: String) -> Dictionary:
	for island: Dictionary in state.islands:
		if island.id == id:
			return island
	return {}


func active() -> Dictionary:
	return find_island(state.activeId)


func select_island(id: String) -> bool:
	if find_island(id).is_empty():
		return false
	var candidate := state.duplicate()
	candidate.activeId = id
	return commit(candidate)


func commit(candidate: Dictionary) -> bool:
	if not write(candidate):
		return false
	state = candidate
	return true


func active_catalog() -> Catalog:
	return catalog if active().get("grid") == GOLDEN_GRID else legacy_catalog


static func island_size(data: Dictionary) -> Vector2i:
	var width: Variant = data.get("width")
	var depth: Variant = data.get("depth")
	var size := BASE_SIZE
	if (width is int or width is float) and is_finite(float(width)):
		size.x = int(clampf(float(width), BASE_SIZE.x, MAX_SIZE.x))
	if (depth is int or depth is float) and is_finite(float(depth)):
		size.y = int(clampf(float(depth), BASE_SIZE.y, MAX_SIZE.y))
	return size


static func next_size(current: Vector2i) -> Vector2i:
	for size: Vector2i in EXPANSION_SIZES:
		if size.x >= current.x and size.y >= current.y and size != current:
			return size
	return current


func expand_active(size: Vector2i) -> bool:
	var current := active()
	var previous := island_size(current)
	if size == previous or size.x < previous.x or size.y < previous.y or size.x > MAX_SIZE.x or size.y > MAX_SIZE.y:
		return false
	var candidate := state.duplicate()
	candidate.islands = state.islands.duplicate()
	var expanded := current.duplicate()
	expanded.width = size.x
	expanded.depth = size.y
	candidate.islands[candidate.islands.find(current)] = expanded
	return commit(candidate)


func new_island(title: String) -> bool:
	if title.strip_edges().is_empty():
		return false
	var id := "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	while not find_island(id).is_empty():
		id += "-new"
	var candidate := state.duplicate()
	candidate.islands = state.islands.duplicate()
	candidate.islands.append({
		"id": id, "name": title.strip_edges(), "terrain": "flat",
		"grid": GOLDEN_GRID, "wallHeightModules": true, "placements": [],
	})
	candidate.activeId = id
	return commit(candidate)


func rename_island(id: String, title: String) -> bool:
	var island := find_island(id)
	var name := title.strip_edges()
	if island.is_empty() or name.is_empty():
		return false
	var candidate := state.duplicate()
	candidate.islands = state.islands.duplicate()
	candidate.islands[candidate.islands.find(island)] = island.merged({"name": name}, true)
	return commit(candidate)


func delete_island(id: String) -> bool:
	var island := find_island(id)
	if island.is_empty() or state.islands.size() <= 1:
		return false
	var candidate := state.duplicate()
	candidate.islands = state.islands.duplicate()
	var index: int = candidate.islands.find(island)
	candidate.islands.remove_at(index)
	if id == state.activeId:
		candidate.activeId = candidate.islands[mini(index, candidate.islands.size() - 1)].id
	return commit(candidate)


func export_island(id: String, path: String) -> bool:
	var island := find_island(id)
	if island.is_empty():
		return false
	var destination := ProjectSettings.globalize_path(path).simplify_path()
	var autosave := ProjectSettings.globalize_path(save_path).simplify_path()
	if destination.to_lower() in [autosave.to_lower(), (autosave + ".tmp").to_lower()]:
		return false
	return write_file(destination, {"activeId": id, "floorCenters": true, "islands": [island]})


func merge_import(path: String) -> bool:
	var incoming := read_file(path)
	if incoming.is_empty():
		return false
	var candidate := state.duplicate(true)
	var used: Array[String] = []
	for island: Dictionary in candidate.islands:
		used.append(island.id)
	for island: Dictionary in incoming.islands:
		var original: String = island.id
		while island.id in used:
			island.id += "-import"
		if island.id != original:
			island.name += "（导入）"
		used.append(island.id)
		candidate.islands.append(island)
		if incoming.activeId == original:
			candidate.activeId = island.id
	return commit(candidate)
