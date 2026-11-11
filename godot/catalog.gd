@tool
extends RefCounted

const CELL := 0.85
const SLAB := 0.054
const WALL := 1.12
const STOREY := 1174
const GROUND := 0.009
const WOOD := Color("#af7d48")
const TRIM := Color("#935d35")
const SIDING := Color("#ddbf88")
const GLASS := Color(0.50, 0.76, 0.78, 0.48)

var items: Dictionary = preload("res://assets/catalog.gd").ITEMS
var models: Dictionary
var materials: Dictionary
var bounds: Dictionary


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


func box_shape(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)


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


func visuals(id: String, rise: float = STOREY / 1000.0) -> Node3D:
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
		if id == "picketFence":
			fit.scale *= Vector3(1.0, 2.15, 1.85)
		if layer == "floor":
			fit.scale = Vector3(CELL / original.size.x, SLAB / original.size.y if original.size.y > 0.001 else 1.0, CELL / original.size.z)
			var origin := original.get_center()
			origin.y = original.end.y
			fit.position = Vector3.UP * SLAB - origin * fit.scale
			if id == "flatRoof":
				box(visual, Vector3(CELL, SLAB - 0.001, CELL), Vector3(0, (SLAB - 0.001) / 2, 0), Color("#9b9280"))
		return visual
	match id:
		"floor":
			box(visual, Vector3(CELL, SLAB * 0.68, CELL), Vector3(0, SLAB * 0.34, 0), TRIM)
			for i in range(4):
				var tint := WOOD.lightened(i * 0.045)
				box(visual, Vector3(CELL, SLAB * 0.5, CELL / 4 - 0.008), Vector3(0, SLAB * 0.75, (i - 1.5) * CELL / 4), tint)
		"flatRoof", "skylight":
			box(visual, Vector3(CELL, SLAB, CELL), Vector3.UP * SLAB / 2, GLASS if id == "skylight" else Color("#a69b86"))
		"wall", "doorway", "windowWall", "halfWall":
			var height := WALL * (0.5 if id == "halfWall" else 1.0)
			for side in [-1, 1]:
				box(visual, Vector3(0.055, height, 0.10), Vector3(side * (CELL - 0.055) / 2, height / 2, 0), TRIM)
			box(visual, Vector3(CELL, 0.055, 0.10), Vector3(0, height - 0.0275, 0), TRIM)
			if id == "doorway" or id == "windowWall":
				var width := 0.53 if id == "doorway" else 0.46
				var top := 0.91 if id == "doorway" else 0.88
				for side in [-1, 1]:
					panels(visual, side * (width + CELL) / 4, (CELL - width) / 2, 0, top)
					box(visual, Vector3(0.026, top, 0.096), Vector3(side * width / 2, top / 2, 0), TRIM)
				panels(visual, 0, CELL - 0.11, top, height - 0.055)
				if id == "windowWall":
					panels(visual, 0, width, 0, 0.49)
					box(visual, Vector3(width + 0.04, 0.043, 0.105), Vector3(0, 0.49, 0), TRIM)
			else:
				panels(visual, 0, CELL - 0.11, 0, height - 0.055)
		"stairs":
			stairs_mesh(visual, rise)
	return visual


func panels(parent: Node3D, x: float, width: float, bottom: float, top: float) -> void:
	var count := maxi(1, roundi((top - bottom) / 0.13))
	var size := (top - bottom) / count
	for row in range(count):
		box(parent, Vector3(width, size - 0.004, 0.076), Vector3(x, bottom + (row + 0.5) * size, 0), SIDING.darkened(row % 2 * 0.07))


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
	return path.is_empty() or id in ["halfWall", "flatRoof", "skylight"] or FileAccess.file_exists(path) or ResourceLoader.exists(path)


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
