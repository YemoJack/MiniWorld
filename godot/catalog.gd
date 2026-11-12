@tool
extends RefCounted

const Data = preload("res://assets/catalog.gd")
const RoofKit = preload("res://godot/roof_kit.gd")
const WoodMesh = preload("res://godot/wood_mesh.gd")
const CELL := Data.CELL
const SLAB := Data.SLAB_THICKNESS
const WALL := Data.WALL_HEIGHT
const STOREY := roundi(WALL * 1000.0)
const GROUND := 0.009
const WOOD := Color("#af7d48")
const TRIM := Color("#935d35")
const SIDING := Color("#ddbf88")
const GLASS := Color(0.50, 0.76, 0.78, 0.48)
const DOOR_OPENING := 0.504
const DOOR_HEAD := 0.95
const DOOR_PANEL_BOTTOM := 0.006
const DOOR_PANEL_SIZE := Vector3(0.494, DOOR_HEAD - 2.0 * DOOR_PANEL_BOTTOM, 0.056)
const WALL_DEPTH := Data.WALL_DEPTH

var items: Dictionary = Data.ITEMS
var models: Dictionary
var materials: Dictionary
var bounds: Dictionary
var roof_meshes: Dictionary
var wood_meshes: Dictionary


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


func visuals(id: String, rise: float = STOREY / 1000.0, joins := 0) -> Node3D:
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
			fit.scale.x = CELL / original.size.x
			fit.position.x = -original.get_center().x * fit.scale.x
		if id == "harborRope":
			fit_centered(fit, original, Vector3(CELL, 0.46, 0.09))
		if layer == "edge":
			var size := measured(visual)
			var horizontal_fit := Vector3(
				(CELL * info.width) / maxf(size.size.x, 0.001),
				1.0,
				WALL_DEPTH / maxf(size.size.z, 0.001)
			)
			var midpoint := size.get_center()
			midpoint.y = 0.0
			fit.position = (fit.position - midpoint) * horizontal_fit
			fit.scale *= horizontal_fit
		elif layer == "object" and not info.has("fit_size"):
			var midpoint := measured(visual).get_center()
			fit.position -= Vector3(midpoint.x, 0.0, midpoint.z)
		if layer == "floor":
			var deck_scale := fit.scale.y if info.has("deck_y") else (SLAB / original.size.y if original.size.y > 0.001 else 1.0)
			fit.scale = Vector3(CELL * info.width / original.size.x, deck_scale, CELL * info.depth / original.size.z)
			var origin := original.get_center()
			origin.y = info.get("deck_y", original.end.y)
			fit.position = Vector3.UP * SLAB - origin * fit.scale
			if info.has("deck_y"):
				var backing := Vector3(CELL * info.width, 0.025, CELL * info.depth)
				box(visual, backing, Vector3.UP * 0.008, TRIM.darkened(0.35))
			elif id == "flatRoof" or original.size.y <= 0.001:
				box(visual, Vector3(CELL, SLAB - 0.001, CELL), Vector3(0, (SLAB - 0.001) / 2, 0), Color("#9b9280"))
		return visual
	match id:
		"floor":
			var slab := mesh_part(visual, wood_model(id))
			slab.rotation.x = -PI / 2.0
			slab.position = Vector3(0, SLAB / 2.0, CELL / 2.0)
		"flatRoof", "skylight":
			box(visual, Vector3(CELL, SLAB, CELL), Vector3.UP * SLAB / 2, GLASS if id == "skylight" else Color("#a69b86"))
		"harborDock", "harborBridge":
			var width := CELL * float(info.width)
			var depth := CELL * float(info.depth)
			for i in int(info.depth) * 6:
				var z := -depth / 2 + (i + 0.5) * CELL / 6
				box(visual, Vector3(width, SLAB, CELL / 6 - 0.004), Vector3(0, SLAB / 2, z), WOOD.darkened((i % 3) * 0.06))
			for x in [-1, 1]:
				for z in [-1, 1]:
					box(visual, Vector3(0.09, 1.25, 0.09), Vector3(x * (width / 2 - 0.12), -0.61, z * (depth / 2 - 0.12)), TRIM)
		"harborRope":
			for x in [-0.39, 0.39]:
				box(visual, Vector3(0.055, 0.46, 0.055), Vector3(x, 0.23, 0), TRIM)
			for height in [0.18, 0.34]:
				box(visual, Vector3(CELL, 0.022, 0.025), Vector3(0, height, 0), SIDING)
		"harborBarrel":
			box(visual, Vector3(0.34, 0.43, 0.34), Vector3.UP * 0.215, TRIM)
			for height in [0.10, 0.33]:
				box(visual, Vector3(0.35, 0.035, 0.35), Vector3.UP * height, Color("#5c5650"))
		"harborShed":
			box(visual, Vector3(2.10, 1.45, 1.80), Vector3.UP * 0.725, TRIM)
			for side in [-1, 1]:
				box(visual, Vector3(1.26, 0.08, 1.98), Vector3(side * 0.57, 1.66, 0), WOOD).rotation.z = -side * 0.32
		"wall", "doorway", "woodDoor", "windowWall", "halfWall":
			mesh_part(visual, wood_model(id)).name = "WallMesh"
			if id == "woodDoor":
				wood_door_panel(visual)
		"stairs":
			stairs_mesh(visual, rise)
		"woodRoofSlope", "woodRoofRidge", "woodRoofGable":
			mesh_part(visual, roof_model(layer, joins))
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
				wood_meshes[id] = WoodMesh.create(Vector2(CELL, CELL), SLAB, "floor", WOOD, TRIM)
			"doorPanel":
				var size := Vector2(DOOR_PANEL_SIZE.x, DOOR_PANEL_SIZE.y)
				wood_meshes[id] = WoodMesh.create(size, DOOR_PANEL_SIZE.z, "door", WOOD, TRIM)
			_:
				var height := Data.HALF_WALL_HEIGHT if id == "halfWall" else WALL
				wood_meshes[id] = WoodMesh.create(Vector2(CELL, height), WALL_DEPTH, "wall", SIDING, TRIM, wall_opening(id))
	return wood_meshes[id]


func roof_model(kind: String, joins := 0) -> Mesh:
	var key := "%s:%d" % [kind, joins]
	if not roof_meshes.has(key):
		roof_meshes[key] = RoofKit.mesh(kind, joins)
	return roof_meshes[key]


func wall_opening(id: String) -> Rect2:
	match id:
		"doorway":
			return Rect2(-DOOR_OPENING / 2.0, 0, DOOR_OPENING, 0.89)
		"woodDoor":
			return Rect2(-DOOR_OPENING / 2.0, 0, DOOR_OPENING, DOOR_HEAD)
		"windowWall":
			return Rect2(-0.217, 0.51, 0.434, 0.37)
	return Rect2()


func wood_door_panel(parent: Node3D) -> void:
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(-DOOR_PANEL_SIZE.x / 2.0, DOOR_PANEL_BOTTOM, 0)
	parent.add_child(hinge)
	mesh_part(hinge, wood_model("doorPanel")).position.x = DOOR_PANEL_SIZE.x / 2.0
	for side in [-1, 1]:
		box(hinge, Vector3(0.042, 0.060, 0.010), Vector3(DOOR_PANEL_SIZE.x - 0.05, 0.46, side * 0.031), Color("#3c3933"))
		box(hinge, Vector3(0.054, 0.018, 0.022), Vector3(DOOR_PANEL_SIZE.x - 0.062, 0.46, side * 0.039), Color("#645947"))


func stairs_mesh(parent: Node3D, rise: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material(WOOD))
	var half := CELL / 2
	for i in range(10):
		var front := half - i * CELL / 10.0
		var back := front - CELL / 10
		var top := rise * (i + 1) / 10
		var bottom := rise * i / 10
		var underside := maxf(0.0, bottom - rise / 10)
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
	stair_face(surface, Vector3(-half, rise, -half), Vector3(-half, rise * 0.9, -half),
		Vector3(half, rise * 0.9, -half), Vector3(half, rise, -half))
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	parent.add_child(instance)


func stair_face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		surface.add_vertex(point)


func available(id: String) -> bool:
	if not items.has(id) or not items[id].has("layer"):
		return false
	var path: String = items[id].get("asset", "")
	return path.is_empty() or id in ["halfWall", "flatRoof", "skylight", "harborDock", "harborBridge", "harborRope", "harborBarrel"] or FileAccess.file_exists(path) or ResourceLoader.exists(path)


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
