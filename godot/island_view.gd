extends Node3D

const Catalog = preload("res://godot/catalog.gd")
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

@export_enum("flat", "cabin") var terrain: String = "flat"
@onready var pet := get_node_or_null("Pet") as Node3D

var grid: MeshInstance3D
var obstacles: Array[AABB]
var pet_waypoint := 1
var pet_pause := 1.6
var pet_gait := 0.0
var elapsed := 0.0


func setup(catalog: Catalog) -> void:
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


func create_grid(builder: RefCounted) -> void:
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.29, 0.17, 0.48)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var segments: Dictionary = {}
	for x in range(-8, 9):
		for z in range(-7, 8):
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
	grid = MeshInstance3D.new()
	grid.mesh = lines
	grid.hide()
	add_child(grid)


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
