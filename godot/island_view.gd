extends Node3D

const Catalog = preload("res://godot/catalog.gd")
const Islands = preload("res://godot/islands.gd")
const GROUND_MATERIAL = preload("res://assets/islands/ground.tres")
const RIM := [
	Vector2(6.8, 0), Vector2(6.3, 2.3), Vector2(4.9, 4), Vector2(2.5, 4.95),
	Vector2(0.15, 5.3), Vector2(-2.4, 5), Vector2(-4.7, 4.3), Vector2(-6.15, 2.6),
	Vector2(-6.8, 0.45), Vector2(-6.5, -1.7), Vector2(-5.2, -3.5), Vector2(-3.1, -4.65),
	Vector2(-0.75, -5.05), Vector2(1.7, -4.7), Vector2(3.7, -4.45), Vector2(5.55, -3),
]
const PET_ROUTE := [
	Vector3(-3.18, 0, 2.12), Vector3(-2.18, 0, 2.75),
	Vector3(-2.68, 0, 3.95), Vector3(-3.62, 0, 3.25),
]

@export_enum("flat", "cabin", "harbor") var terrain: String = "flat"
@onready var pet := get_node_or_null("Pet") as Node3D

var grid: MeshInstance3D
var obstacles: Array[AABB]
var rim: PackedVector2Array
var land_bounds: Rect2
var harbor_water: Rect2
var extension: MeshInstance3D
var base_ground_faces: PackedVector3Array
var pet_waypoint := 1
var pet_pause := 1.6
var pet_gait := 0.0
var elapsed := 0.0


func setup(catalog: Catalog) -> void:
	if terrain == "harbor":
		var shed := catalog.visuals("harborShed")
		shed.position = Vector3(-0.9, 0, -2.9)
		shed.rotation.y = PI
		add_child(shed)
		obstacles.append(catalog.measured(shed))
		var body := StaticBody3D.new()
		body.set_meta("scenery", true)
		catalog.collider_meshes(body, shed)
		add_child(body)
	var scenery := get_node_or_null("Scenery")
	if scenery != null:
		for prop: Node3D in scenery.get_children():
			obstacles.append(catalog.measured(prop))
			if prop.name != "Lilies":
				var body := StaticBody3D.new()
				body.set_meta("scenery", true)
				for model in prop.get_children():
					catalog.collider_meshes(body, model)
				prop.add_child(body)


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
	if terrain == "harbor":
		build_harbor()
		return
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

	var ground := get_node("Terrain/GroundCollision" if terrain == "cabin" else "GroundCollision") as CollisionShape3D
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


func build_harbor() -> void:
	var cell := Catalog.CELL
	harbor_water = Rect2(-1.5 * cell, -0.5 * cell, land_bounds.end.x + 1.5 * cell + 1.0, 2.0 * cell)
	var inlet := PackedVector2Array([
		harbor_water.position, Vector2(harbor_water.end.x, harbor_water.position.y),
		harbor_water.end, Vector2(harbor_water.position.x, harbor_water.end.y),
	])
	var shore := Geometry2D.clip_polygons(rim, inlet)[0]
	if Geometry2D.is_polygon_clockwise(shore):
		shore.reverse()
	var sand := GROUND_MATERIAL.duplicate() as ShaderMaterial
	sand.set_shader_parameter("grass_dark", Color("#77643d"))
	sand.set_shader_parameter("grass_light", Color("#9c8454"))
	var land := polygon_mesh(shore, sand)
	$GroundCollision.shape = land.create_trimesh_shape()
	var outline := PackedVector3Array()
	for point in shore:
		outline.append(Vector3(point.x, 0.0, point.y))
	$RockAndGrass.mesh = add_cliffs(land, outline, sand)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("#3e8d87")
	water.roughness = 0.38
	$Water.mesh = polygon_mesh(Geometry2D.intersect_polygons(rim, inlet)[0], water)


func polygon_mesh(outline: PackedVector2Array, material: Material) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in Geometry2D.triangulate_polygon(outline):
		var point := outline[index]
		surface.add_vertex(Vector3(point.x, 0.0, point.y))
	surface.set_material(material)
	surface.generate_normals()
	return surface.commit()


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


func create_grid(builder: RefCounted) -> void:
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.29, 0.17, 0.48)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var segments: Dictionary = {}
	var first := (land_bounds.position / Catalog.CELL).floor()
	var last := (land_bounds.end / Catalog.CELL).ceil()
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
		lines.surface_add_vertex(Vector3(edge.x * Catalog.CELL / 2, 0.013, edge.y * Catalog.CELL / 2))
		lines.surface_add_vertex(Vector3(edge.z * Catalog.CELL / 2, 0.013, edge.w * Catalog.CELL / 2))
	lines.surface_end()
	if grid == null:
		grid = MeshInstance3D.new()
		grid.hide()
		add_child(grid)
	grid.mesh = lines


func _process(delta: float) -> void:
	if pet == null:
		return
	elapsed += delta
	pet_pause -= delta
	var stride := 0.0
	if pet_pause <= 0.0:
		var target: Vector3 = PET_ROUTE[pet_waypoint]
		var direction := target - pet.position
		direction.y = 0.0
		if direction.length() <= delta * 0.64:
			pet.position = target
			pet_waypoint = (pet_waypoint + 1) % PET_ROUTE.size()
			pet_pause = 1.2
		else:
			pet.position += direction.normalized() * delta * 0.64
			pet.rotation.y = atan2(direction.x, direction.z)
			pet_gait += delta * 11
			stride = sin(pet_gait) * 0.42
	pet.position.y = absf(stride) * 0.08
	for i in range(4):
		pet.get_node("Leg%d" % i).rotation.x = stride if i in [0, 3] else -stride
	pet.get_node("Tail").rotation.y = sin(elapsed * 4.3) * 0.21
