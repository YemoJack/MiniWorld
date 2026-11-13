@tool
extends RefCounted

const Data = preload("res://assets/catalog.gd")
const RoofKit = preload("res://godot/roof_kit.gd")
const WoodMesh = preload("res://godot/wood_mesh.gd")
const SLAB := Data.SLAB_THICKNESS
const GROUND := 0.009
const WOOD := Color("#af7d48")
const TRIM := Color("#935d35")
const SIDING := Color("#ddbf88")
const GLASS := Color(0.50, 0.76, 0.78, 0.48)
const DOOR_PANEL_BOTTOM := 0.006
const WALL_DEPTH := Data.WALL_DEPTH
const WOOD_OPENINGS := ["doorway", "woodDoor", "windowWall", "wideWindow"]
const FURNITURE_SCALES := {
	"bench": 0.44, "cafeCounter": 0.42, "cafeChair": 0.0045, "cafeTable": 0.00378, "crate": 0.564,
}

var legacy: bool
var cell_size: float
var wall_height: float
var storey_mm: int
var items: Dictionary
var models: Dictionary
var materials: Dictionary
var bounds: Dictionary
var roof_meshes: Dictionary
var wood_meshes: Dictionary


func _init(legacy_grid := false) -> void:
	legacy = legacy_grid
	cell_size = Data.LEGACY_CELL if legacy else Data.CELL
	wall_height = Data.LEGACY_WALL_HEIGHT if legacy else Data.WALL_HEIGHT
	storey_mm = roundi(wall_height * 1000.0)
	items = Data.ITEMS.duplicate(true)
	if legacy:
		items.stoneLowWall.label = "石矮墙"
		items.stoneLowWall.erase("height_ratio")
		return
	items["stoneLowWallOriginal"] = items.stoneLowWall.duplicate()
	items.stoneLowWallOriginal.label = "旧石矮墙"
	items.stoneLowWallOriginal.erase("height_ratio")
	items.stoneLowWallOriginal.hidden = true
	items.stairs.depth = 2
	for id in FURNITURE_SCALES:
		items[id].scale = FURNITURE_SCALES[id]
		items[id].width = 1
		items[id].fine = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for model in models.values():
			model.free()


func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var result := StandardMaterial3D.new()
		result.albedo_color = color
		result.roughness = 0.88
		if color.a < 1.0:
			result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		materials[color] = result
	return materials[color]


func box(parent: Node3D, size: Vector3, center: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material(color)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = center
	parent.add_child(part)
	return part


func box_shape(body: StaticBody3D, size: Vector3, center: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	return collision


func measured(node: Node3D, space: Transform3D = Transform3D.IDENTITY) -> AABB:
	var local := space * node.transform
	var result := AABB()
	if node is MeshInstance3D:
		result = local * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := measured(child, local)
			if child_bounds.size.length_squared() > 0.0:
				result = result.merge(child_bounds) if result.size.length_squared() > 0.0 else child_bounds
	return result


func imported(id: String) -> Node3D:
	if not models.has(id):
		var info: Dictionary = items.get(id, {})
		var path: String = info.get("asset", "")
		if path.is_empty():
			return null
		var model: Node3D
		if ResourceLoader.exists(path, "PackedScene"):
			var packed := load(path) as PackedScene
			model = packed.instantiate() as Node3D
		elif FileAccess.file_exists(path):
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			if doc.append_from_file(ProjectSettings.globalize_path(path), state) == OK:
				model = doc.generate_scene(state) as Node3D
		if model == null:
			return null
		models[id] = model
	return models[id].duplicate() as Node3D


func visuals(id: String, rise := 0.0, joins := 0) -> Node3D:
	var visual := Node3D.new()
	var info: Dictionary = items[id]
	var layer: String = info.get("layer", "")
	var model := imported(id)
	if model != null:
		var fit := Node3D.new()
		visual.add_child(fit)
		fit.add_child(model)
		var original := measured(model)
		fit.scale = Vector3.ONE * float(info.get("scale", 1.0))
		if info.has("fit_size"):
			fit_centered(fit, original, info.fit_size)
		if id == "picketFence":
			fit.scale *= Vector3(1.0, 2.15, 1.85)
			fit.scale.x = cell_size / original.size.x
			fit.position.x = -original.get_center().x * fit.scale.x
		if id == "harborRope":
			fit_centered(fit, original, Vector3(cell_size, 0.46, 0.09))
		if not legacy and (info.has("height_ratio") or id in ["brickWall", "brickWindow", "glassWall", "glassDoor", "shopWindow", "rollerShutter", "shopfront", "steelColumn", "stoneColumn", "stoneArch"]):
			var size := measured(visual).size
			size.y = module_height(id)
			fit_centered(fit, original, size)
		if not legacy and id in ["picketFence", "timberFence", "stoneRailing"]:
			var size := measured(visual).size
			size.y = 0.57
			fit_centered(fit, original, size)
		if layer == "edge":
			var size := measured(visual)
			var horizontal_fit := Vector3(
				(cell_size * info.width) / maxf(size.size.x, 0.001),
				1.0,
				WALL_DEPTH / maxf(size.size.z, 0.001)
			)
			var midpoint := size.get_center()
			midpoint.y = 0.0
			fit.position = (fit.position - midpoint) * horizontal_fit
			fit.scale *= horizontal_fit
		elif layer == "object" and not info.has("fit_size"):
			var model_bounds := measured(visual)
			var midpoint := model_bounds.get_center()
			var bottom := model_bounds.position.y if not legacy and info.category == "furniture" else 0.0
			fit.position -= Vector3(midpoint.x, bottom, midpoint.z)
		if layer == "floor":
			var deck_scale := fit.scale.y if info.has("deck_y") else (SLAB / original.size.y if original.size.y > 0.001 else 1.0)
			fit.scale = Vector3(cell_size * info.width / original.size.x, deck_scale, cell_size * info.depth / original.size.z)
			var origin := original.get_center()
			origin.y = info.get("deck_y", original.end.y)
			fit.position = Vector3.UP * SLAB - origin * fit.scale
			if info.has("deck_y"):
				var backing := Vector3(cell_size * info.width, 0.025, cell_size * info.depth)
				box(visual, backing, Vector3.UP * 0.008, TRIM.darkened(0.35))
			elif id == "flatRoof" or original.size.y <= 0.001:
				box(visual, Vector3(cell_size, SLAB - 0.001, cell_size), Vector3(0, (SLAB - 0.001) / 2, 0), Color("#9b9280"))
		return visual
	match id:
		"floor":
			var slab := mesh_part(visual, wood_model(id))
			slab.rotation.x = -PI / 2.0
			slab.position = Vector3(0, SLAB / 2.0, cell_size / 2.0)
		"flatRoof", "skylight":
			box(visual, Vector3(cell_size, SLAB, cell_size), Vector3.UP * SLAB / 2, GLASS if id == "skylight" else Color("#a69b86"))
		"harborDock", "harborBridge":
			var width := cell_size * float(info.width)
			var depth := cell_size * float(info.depth)
			for i in int(info.depth) * 6:
				var z := -depth / 2 + (i + 0.5) * cell_size / 6
				box(visual, Vector3(width, SLAB, cell_size / 6 - 0.004), Vector3(0, SLAB / 2, z), WOOD.darkened((i % 3) * 0.06))
			for x in [-1, 1]:
				for z in [-1, 1]:
					box(visual, Vector3(0.09, 1.25, 0.09), Vector3(x * (width / 2 - 0.12), -0.61, z * (depth / 2 - 0.12)), TRIM)
		"harborRope":
			for x in [-0.39, 0.39]:
				box(visual, Vector3(0.055, 0.46, 0.055), Vector3(x, 0.23, 0), TRIM)
			for height in [0.18, 0.34]:
				box(visual, Vector3(cell_size, 0.022, 0.025), Vector3(0, height, 0), SIDING)
		"harborBarrel":
			box(visual, Vector3(0.34, 0.43, 0.34), Vector3.UP * 0.215, TRIM)
			for height in [0.10, 0.33]:
				box(visual, Vector3(0.35, 0.035, 0.35), Vector3.UP * height, Color("#5c5650"))
		"harborShed":
			box(visual, Vector3(2.10, 1.45, 1.80), Vector3.UP * 0.725, TRIM)
			for side in [-1, 1]:
				box(visual, Vector3(1.26, 0.08, 1.98), Vector3(side * 0.57, 1.66, 0), WOOD).rotation.z = -side * 0.32
		"wall", "doorway", "woodDoor", "windowWall", "wideWindow", "quarterWall", "halfWall", "twoThirdsWall":
			mesh_part(visual, wood_model(id)).name = "WallMesh"
			if id == "woodDoor":
				wood_door_panel(visual)
		"stairs":
			stairs_mesh(visual, rise if rise > 0.0 else wall_height)
		"stool", "bench":
			var width := 0.91 if id == "bench" else 0.28
			var depth := 0.28 if id == "bench" else 0.26
			box(visual, Vector3(width, 0.036, depth), Vector3.UP * 0.212, WOOD)
			for x in [-1, 1]:
				for z in [-1, 1]:
					var foot := Vector3(x * (width / 2.0 - 0.048), 0.097, z * (depth / 2.0 - 0.045))
					box(visual, Vector3(0.046, 0.194, 0.046), foot, TRIM)
		_:
			if layer in ["roof", "ridge", "gable"]:
				mesh_part(visual, roof_model(id, joins))
	return visual


func fit_centered(fit: Node3D, original: AABB, size: Vector3) -> void:
	fit.scale = size / original.size
	var origin := original.get_center()
	origin.y = original.position.y
	fit.position = -origin * fit.scale


func mesh_part(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	parent.add_child(part)
	return part


func wood_model(id: String) -> Mesh:
	if not wood_meshes.has(id):
		match id:
			"floor":
				wood_meshes[id] = WoodMesh.create(Vector2(cell_size, cell_size), SLAB, "floor", WOOD, TRIM)
			"doorPanel":
				var panel_size := door_panel_size()
				var size := Vector2(panel_size.x, panel_size.y)
				wood_meshes[id] = WoodMesh.create(size, panel_size.z, "door", WOOD, TRIM)
			_:
				wood_meshes[id] = WoodMesh.create(Vector2(cell_size, module_height(id)), WALL_DEPTH, "wall", SIDING, TRIM, wall_opening(id))
	return wood_meshes[id]


func module_height(id: String, default_ratio := 1.0) -> float:
	return wall_height * float(items[id].get("height_ratio", default_ratio))


func roof_rise(id: String) -> float:
	return module_height(id, Data.HALF)


func roof_model(id: String, joins := 0) -> Mesh:
	var key := "%s:%d" % [id, joins]
	if not roof_meshes.has(key):
		roof_meshes[key] = RoofKit.mesh(items[id].layer, roof_rise(id), cell_size, joins)
	return roof_meshes[key]


func wall_opening(id: String) -> Rect2:
	if not legacy:
		match id:
			"doorway", "woodDoor":
				return Rect2(-0.25, 0, 0.50, 1.05 + SLAB / 2.0)
			"windowWall":
				return Rect2(-0.225, 0.50 + SLAB / 2.0, 0.45, 0.55)
			"wideWindow":
				return Rect2(-0.35, 0.48 + SLAB / 2.0, 0.70, 0.65)
	match id:
		"doorway":
			return Rect2(-0.252, 0, 0.504, 0.89)
		"woodDoor":
			return Rect2(-0.252, 0, 0.504, 0.95)
		"windowWall":
			return Rect2(-0.217, 0.51, 0.434, 0.37)
	return Rect2()


func door_panel_size() -> Vector3:
	var opening := wall_opening("woodDoor")
	return Vector3(opening.size.x - 0.010, opening.size.y - 2.0 * DOOR_PANEL_BOTTOM, 0.056)


func wood_door_panel(parent: Node3D) -> void:
	var panel_size := door_panel_size()
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(-panel_size.x / 2.0, DOOR_PANEL_BOTTOM, 0)
	parent.add_child(hinge)
	mesh_part(hinge, wood_model("doorPanel")).position.x = panel_size.x / 2.0
	for side in [-1, 1]:
		box(hinge, Vector3(0.042, 0.060, 0.010), Vector3(panel_size.x - 0.05, 0.46, side * 0.031), Color("#3c3933"))
		box(hinge, Vector3(0.054, 0.018, 0.022), Vector3(panel_size.x - 0.062, 0.46, side * 0.039), Color("#645947"))


func stairs_mesh(parent: Node3D, rise: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material(WOOD))
	var half := cell_size / 2.0
	var depth := cell_size * int(items.stairs.depth)
	var steps := 10 if legacy else 14
	for i in range(steps):
		var front := depth / 2.0 - i * depth / steps
		var back := front - depth / steps
		var top := rise * (i + 1) / steps
		var bottom := rise * i / steps
		var underside := maxf(0.0, bottom - rise / steps)
		stair_face(surface, Vector3(-half, top, front), Vector3(-half, top, back),
			Vector3(half, top, back), Vector3(half, top, front))
		stair_face(surface, Vector3(-half, bottom, front), Vector3(-half, top, front),
			Vector3(half, top, front), Vector3(half, bottom, front))
		stair_face(surface, Vector3(-half, underside, front), Vector3(-half, bottom, back),
			Vector3(-half, top, back), Vector3(-half, top, front))
		stair_face(surface, Vector3(half, bottom, back), Vector3(half, underside, front),
			Vector3(half, top, front), Vector3(half, top, back))
		stair_face(surface, Vector3(-half, bottom, back), Vector3(-half, underside, front),
			Vector3(half, underside, front), Vector3(half, bottom, back))
	stair_face(surface, Vector3(-half, rise, -depth / 2.0), Vector3(-half, rise * (steps - 1) / steps, -depth / 2.0),
		Vector3(half, rise * (steps - 1) / steps, -depth / 2.0), Vector3(half, rise, -depth / 2.0))
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	parent.add_child(instance)


func stair_face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		surface.add_vertex(point)


func available(id: String) -> bool:
	if id in WOOD_OPENINGS:
		return id != "wideWindow" or not legacy
	if not items.has(id) or not items[id].has("layer"):
		return false
	var path: String = items[id].get("asset", "")
	return path.is_empty() or id in ["bench", "halfWall", "flatRoof", "skylight", "harborDock", "harborBridge", "harborRope", "harborBarrel"] or FileAccess.file_exists(path) or ResourceLoader.exists(path)


func item_bounds(id: String) -> AABB:
	if not bounds.has(id):
		var visual := visuals(id)
		bounds[id] = measured(visual)
		visual.free()
	return bounds[id]


func collider_meshes(body: StaticBody3D, visual: Node3D, space: Transform3D = Transform3D.IDENTITY) -> void:
	var transform := space * visual.transform
	if visual is MeshInstance3D and visual.mesh != null:
		var collision := CollisionShape3D.new()
		collision.shape = visual.mesh.create_trimesh_shape()
		collision.transform = transform
		body.add_child(collision)
	for child in visual.get_children():
		if child is Node3D:
			collider_meshes(body, child, transform)
