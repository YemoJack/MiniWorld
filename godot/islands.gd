extends RefCounted

const SAVE := "user://islands.json"
const Catalog = preload("res://godot/catalog.gd")
const BASE_SIZE := Vector2i(14, 10)
const MAX_SIZE := Vector2i(24, 24)
const EXPANSION_SIZES := [Vector2i(17, 14), Vector2i(20, 20), MAX_SIZE]
const SAVE_CELL_LIMIT := Vector2i(
	maxi(16, ceili(MAX_SIZE.x / (2.0 * Catalog.CELL))),
	maxi(16, ceili(MAX_SIZE.y / (2.0 * Catalog.CELL)))
)

var state: Dictionary
var catalog: Catalog
var save_path: String


func _init(assets: Catalog, path: String = SAVE) -> void:
	catalog = assets
	save_path = path
	state = read_file(save_path)
	if state.is_empty():
		state = {
			"activeId": "flat",
			"islands": [
				{"id": "flat", "name": "平坦岛", "terrain": "flat", "placements": []},
				{"id": "cabin", "name": "木屋岛", "terrain": "cabin", "placements": []},
			],
		}
	if not state.islands.any(func(island: Dictionary): return island.terrain == "harbor"):
		var id := "harbor"
		while state.islands.any(func(island: Dictionary): return island.id == id):
			id += "-default"
		state.islands.append({
			"id": id, "name": "港口岛", "terrain": "harbor",
			"placements": [
				{"item": "harborDock", "x": 2, "z": -2, "turns": 0, "elevation": 0},
				{"item": "harborDock", "x": 2, "z": 2, "turns": 0, "elevation": 0},
				{"item": "harborRope", "x": 3, "z": -1, "turns": 1, "elevation": 0},
				{"item": "harborBarrel", "x": 0, "z": -2, "turns": 0, "elevation": 0},
			],
		})


func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("islands") is Array:
		return {}
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
		for raw in value.placements:
			var p := read_placement(raw)
			if not p.is_empty() and not placements.has(p):
				placements.append(p)
		ids.append(id)
		var size := island_size(value)
		islands.append({
			"id": id, "name": title, "terrain": terrain, "placements": placements,
			"width": size.x, "depth": size.y,
		})
	if islands.is_empty():
		return {}
	var active_id: Variant = parsed.get("activeId")
	return {"activeId": active_id if active_id in ids else ids[0], "islands": islands}


func read_placement(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not raw.get("item") is String:
		return {}
	var item: String = raw.item
	if not catalog.items.has(item) or not catalog.items[item].has("layer"):
		return {}
	var result := {"item": item}
	var fallback_level: Variant = raw.get("level", 1 if item in ["flatRoof", "skylight"] else 0)
	if (not fallback_level is float and not fallback_level is int) or not is_finite(float(fallback_level)) or fallback_level < 0 or fallback_level > 7:
		fallback_level = 0
	for key in ["x", "z", "turns", "elevation"]:
		var value: Variant = raw.get(key, fallback_level * Catalog.STOREY if key == "elevation" else null)
		if (not value is int and not value is float) or not is_finite(float(value)) or value != floorf(float(value)) or absf(float(value)) > 8000:
			return {}
		result[key] = int(value)
	if result.turns < 0 or result.turns > 3 or result.elevation < 0 \
		or absi(result.x) > SAVE_CELL_LIMIT.x or absi(result.z) > SAVE_CELL_LIMIT.y:
		return {}
	if catalog.items[item].get("fine", false):
		for key in ["offsetX", "offsetZ"]:
			var value: Variant = raw.get(key, 0)
			if (value is int or value is float) and absf(float(value)) <= 2 and value == floorf(float(value)):
				result[key] = int(value)
	return result


func write(candidate: Dictionary = state) -> bool:
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(candidate))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path)
	) == OK


func active() -> Dictionary:
	for island: Dictionary in state.islands:
		if island.id == state.activeId:
			return island
	return state.islands[0]


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
	if not write(candidate):
		return false
	state = candidate
	return true


func new_island() -> String:
	var id := "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	state.islands.append({"id": id, "name": "平坦岛 %d" % (state.islands.size() - 1), "terrain": "flat", "placements": []})
	return id


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
	if not write(candidate):
		return false
	state = candidate
	return true
