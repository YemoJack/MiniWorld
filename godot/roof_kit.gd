@tool
extends RefCounted

const Data = preload("res://assets/catalog.gd")
const HALF := Data.CELL / 2.0
const RISE := Data.HALF_WALL_HEIGHT
const GRADE := RISE / Data.CELL
const THICKNESS := Data.ROOF_THICKNESS
const HALF_THICKNESS := THICKNESS / 2.0
const RIDGE_HALF := 0.065
const WALL_HALF := Data.WALL_DEPTH / 2.0
const OMIT_LEFT := 1
const OMIT_RIGHT := 2
const OMIT_HIGH := 4


static func slope_profile(inset := 0.0) -> PackedVector3Array:
	var half_thickness := HALF_THICKNESS - inset
	return PackedVector3Array([
		Vector3(0, RISE - half_thickness, -HALF), Vector3(0, RISE + half_thickness, -HALF),
		Vector3(0, half_thickness, HALF), Vector3(0, -half_thickness, HALF),
	])


static func slope_overlaps_box(roof: Transform3D, box: AABB, tolerance: float) -> bool:
	var local := roof.affine_inverse() * box
	var height := slope_height_range(local.position.z, local.end.z)
	return minf(height.y, local.end.y) - maxf(height.x, local.position.y) > tolerance


static func gable_overlaps_box(gable: Transform3D, box: AABB, tolerance: float) -> bool:
	var local := gable.affine_inverse() * box
	var top := clampf(local.end.x + HALF, 0.0, Data.CELL) * GRADE
	return minf(top, local.end.y) - maxf(0.0, local.position.y) > tolerance


static func slope_height_range(low_z: float, high_z: float) -> Vector2:
	return Vector2((HALF - high_z) * GRADE - HALF_THICKNESS, (HALF - low_z) * GRADE + HALF_THICKNESS)


static func slopes_overlap(first: Transform3D, second: Transform3D, overlap: AABB, tolerance: float) -> bool:
	if absf(first.basis.z.dot(second.basis.z)) < 0.5:
		# Each perpendicular slope varies along a different horizontal axis.
		var a := first.affine_inverse() * overlap
		var b := second.affine_inverse() * overlap
		var range_a := slope_height_range(a.position.z, a.end.z) + Vector2.ONE * first.origin.y
		var range_b := slope_height_range(b.position.z, b.end.z) + Vector2.ONE * second.origin.y
		return minf(range_a.y, range_b.y) - maxf(range_a.x, range_b.x) > tolerance
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	var relative := first.affine_inverse() * second
	for vertex in slope_profile(tolerance / 2.0):
		a.append(Vector2(vertex.z, vertex.y))
		var point := relative * vertex
		b.append(Vector2(point.z, point.y))
	var local := first.affine_inverse() * overlap
	var clip := PackedVector2Array([
		Vector2(local.position.z, local.position.y), Vector2(local.end.z, local.position.y),
		Vector2(local.end.z, local.end.y), Vector2(local.position.z, local.end.y),
	])
	for polygon in Geometry2D.intersect_polygons(a, b):
		if not Geometry2D.intersect_polygons(polygon, clip).is_empty():
			return true
	return false


static func mesh(kind: String, joins := 0) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	surface.set_material(material)
	match kind:
		"roof":
			prism(surface, slope_profile(), Vector3.RIGHT * HALF, Color("#925d3a"), true, joins)
		"ridge":
			var top := RISE + HALF_THICKNESS
			var profile := PackedVector3Array([
				Vector3(0, top - 0.027, -RIDGE_HALF), Vector3(0, top - 0.008, -RIDGE_HALF),
				Vector3(0, top + 0.025, 0), Vector3(0, top - 0.008, RIDGE_HALF),
				Vector3(0, top - 0.027, RIDGE_HALF),
			])
			prism(surface, profile, Vector3.RIGHT * HALF, Color("#a87249"), false, joins)
		"gable":
			var profile := PackedVector3Array([
				Vector3(-HALF, 0, 0), Vector3(HALF, 0, 0), Vector3(HALF, RISE, 0),
			])
			prism(surface, profile, Vector3.BACK * WALL_HALF, Color("#d6ad76"))
	surface.generate_normals()
	return surface.commit()


static func prism(surface: SurfaceTool, profile: PackedVector3Array, half_span: Vector3, color: Color, planks := false, joins := 0) -> void:
	var axis := half_span.normalized()
	var left_extent := -half_span
	var right_extent := half_span
	var center := Vector3.ZERO
	for point in profile:
		center += point / profile.size()
	var outline := PackedVector2Array()
	for point in profile:
		outline.append(Vector2(point.z if axis.x != 0.0 else point.x, point.y))
	var indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, indices.size(), 3):
		var a := profile[indices[i]]
		var b := profile[indices[i + 1]]
		var c := profile[indices[i + 2]]
		if not joins & OMIT_RIGHT:
			triangle(surface, a + right_extent, b + right_extent, c + right_extent, axis, color.darkened(0.15))
		if not joins & OMIT_LEFT:
			triangle(surface, a + left_extent, b + left_extent, c + left_extent, -axis, color.darkened(0.15))
	for i in profile.size():
		if i == 0 and joins & OMIT_HIGH:
			continue
		var start := profile[i]
		var end := profile[(i + 1) % profile.size()]
		var outward := (start + end) / 2.0 - center
		var strips := 6 if planks and i == 1 else 1
		for strip in strips:
			var left := left_extent.lerp(right_extent, float(strip) / strips)
			var right := left_extent.lerp(right_extent, float(strip + 1) / strips)
			var tint := color.lightened((strip % 3) * 0.055)
			triangle(surface, start + left, end + left, end + right, outward, tint)
			triangle(surface, start + left, end + right, start + right, outward, tint)


static func triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	surface.set_color(color)
	var cross := (b - a).cross(c - a)
	var axis := cross.abs()
	var points := [a, c, b] if cross.dot(outward) > 0.0 else [a, b, c]
	for point: Vector3 in points:
		if axis.y >= axis.x and axis.y >= axis.z:
			surface.set_uv(Vector2(point.x, point.z))
		elif axis.x >= axis.z:
			surface.set_uv(Vector2(point.z, point.y))
		else:
			surface.set_uv(Vector2(point.x, point.y))
		surface.add_vertex(point)
