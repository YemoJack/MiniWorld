extends Node3D

const Builder = preload("res://godot/builder.gd")
const Islands = preload("res://godot/islands.gd")
const GROUND_MATERIAL = preload("res://assets/islands/ground.tres")
const RIM := [
	Vector2(6.8, 0), Vector2(6.3, 2.3), Vector2(4.9, 4), Vector2(2.5, 4.95),
	Vector2(0.15, 5.3), Vector2(-2.4, 5), Vector2(-4.7, 4.3), Vector2(-6.15, 2.6),
	Vector2(-6.8, 0.45), Vector2(-6.5, -1.7), Vector2(-5.2, -3.5), Vector2(-3.1, -4.65),
	Vector2(-0.75, -5.05), Vector2(1.7, -4.7), Vector2(3.7, -4.45), Vector2(5.55, -3),
]

var grid: MeshInstance3D
var rim: PackedVector2Array
var land_bounds: Rect2
var extension: MeshInstance3D
var base_ground_faces: PackedVector3Array


func resize_land(size: Vector2i) -> void:
	var original := PackedVector2Array(RIM)
	rim = original
	land_bounds = Rect2(original[0], Vector2.ZERO)
	for point in original:
		land_bounds = land_bounds.expand(point)
	if size != Islands.BASE_SIZE:
		var margin := (Vector2(size) - land_bounds.size) / 2.0
		if size.x == Islands.BASE_SIZE.x:
			margin.x = 0.0
		if size.y == Islands.BASE_SIZE.y:
			margin.y = 0.0
		var corners := PackedVector2Array()
		for point in original:
			for offset in [margin, Vector2(margin.x, -margin.y), Vector2(-margin.x, margin.y), -margin]:
				corners.append(point + offset)
		rim = Geometry2D.convex_hull(corners)
		rim.remove_at(rim.size() - 1) # The hull repeats its first point.
		land_bounds = land_bounds.grow_individual(margin.x, margin.y, margin.x, margin.y)
	if size == Islands.BASE_SIZE:
		return

	# Split the annulus at the corners of both outlines so its edges follow the original terrain.
	var angles := PackedFloat32Array()
	for point in original + rim:
		angles.append(point.angle())
	angles.sort()
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	var last_angle := -INF
	for angle in angles:
		if is_equal_approx(last_angle, angle):
			continue
		var direction := Vector2.from_angle(angle)
		inner.append(rim_point(original, direction))
		outer.append(rim_point(rim, direction))
		last_angle = angle

	var ground := $GroundCollision as CollisionShape3D
	if extension == null:
		base_ground_faces = (ground.shape as ConcavePolygonShape3D).get_faces()
		extension = MeshInstance3D.new()
		extension.name = "LandExtension"
		add_child(extension)

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for i in outer.size():
		var next := (i + 1) % outer.size()
		land_triangle(surface, inner[i], outer[i], outer[next], Color.WHITE)
		land_triangle(surface, inner[i], outer[next], inner[next], Color.WHITE)
	surface.set_material(GROUND_MATERIAL)
	surface.generate_normals()
	var mesh := surface.commit()

	var collision := ConcavePolygonShape3D.new()
	collision.set_faces(base_ground_faces + mesh.get_faces())
	ground.shape = collision
	extension.mesh = add_cliffs(mesh, outer, GROUND_MATERIAL)


func add_cliffs(mesh: ArrayMesh, outer: PackedVector3Array, material: Material) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var upper := outer
	for profile in [Vector2(1.015, -0.35), Vector2(0.74, -1.65), Vector2(0.40, -3.0)]:
		var lower := PackedVector3Array()
		for point in outer:
			lower.append(Vector3(point.x * profile.x, profile.y, point.z * profile.x))
		for i in outer.size():
			var next := (i + 1) % outer.size()
			var rock := Color("#51462b").lerp(Color("#695636"), float(i % 3) / 2)
			land_triangle(surface, upper[i], lower[i], lower[next], rock)
			land_triangle(surface, upper[i], lower[next], upper[next], rock)
		upper = lower
	for i in upper.size():
		land_triangle(surface, upper[i], Vector3(0.0, -4.2, 0.0), upper[(i + 1) % upper.size()], Color("#403721"))
	surface.set_material(material)
	surface.generate_normals()
	return surface.commit(mesh)


func rim_point(outline: PackedVector2Array, direction: Vector2) -> Vector3:
	var distance := INF
	for i in outline.size():
		var start := outline[i]
		var edge := outline[(i + 1) % outline.size()] - start
		var divisor := direction.cross(edge)
		if is_zero_approx(divisor):
			continue
		var along_edge := start.cross(direction) / divisor
		var along_ray := start.cross(edge) / divisor
		if along_edge >= -0.00001 and along_edge <= 1.00001 and along_ray > 0.0:
			distance = minf(distance, along_ray)
	return Vector3(direction.x, 0.0, direction.y) * distance


func land_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).is_zero_approx():
		return
	for point in [a, b, c]:
		surface.set_color(color)
		surface.add_vertex(point)


func create_grid(builder: Builder) -> void:
	var cell_size := builder.catalog.cell_size
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.29, 0.17, 0.48)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var segments: Dictionary = {}
	var first := (land_bounds.position / cell_size).floor()
	var last := (land_bounds.end / cell_size).ceil()
	for x in range(int(first.x), int(last.x) + 1):
		for z in range(int(first.y), int(last.y) + 1):
			if not builder.within_island(Vector2i(x, z)):
				continue
			var a := Vector2i(x * 2 - 1, z * 2 - 1)
			var b := a + Vector2i(2, 0)
			var c := a + Vector2i(0, 2)
			var d := a + Vector2i(2, 2)
			for edge in [Vector4i(a.x, a.y, b.x, b.y), Vector4i(a.x, a.y, c.x, c.y), Vector4i(c.x, c.y, d.x, d.y), Vector4i(b.x, b.y, d.x, d.y)]:
				segments[edge] = true
	for edge: Vector4i in segments:
		lines.surface_add_vertex(Vector3(edge.x * cell_size / 2, 0.013, edge.y * cell_size / 2))
		lines.surface_add_vertex(Vector3(edge.z * cell_size / 2, 0.013, edge.w * cell_size / 2))
	lines.surface_end()
	if grid == null:
		grid = MeshInstance3D.new()
		grid.hide()
		add_child(grid)
	grid.mesh = lines
