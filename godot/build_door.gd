extends StaticBody3D

const Catalog = preload("res://godot/catalog.gd")

var is_open := false
var hinge: Node3D
var panel: CollisionShape3D


func setup_panel(catalog: Catalog, visual: Node3D) -> void:
	hinge = visual.get_node("DoorHinge")
	panel = catalog.box_shape(self, Catalog.DOOR_PANEL_SIZE, hinge.position + panel_offset())


func panel_offset() -> Vector3:
	return Vector3(Catalog.DOOR_PANEL_SIZE.x / 2, Catalog.DOOR_PANEL_SIZE.y / 2, 0)


func toggle(from: Vector3) -> void:
	if is_open:
		try_angle(0.0)
	else:
		var away := PI / 2 if to_local(from).z >= 0.0 else -PI / 2
		if not try_angle(away):
			try_angle(-away)


func try_angle(angle: float) -> bool:
	var rotation_basis := Basis(Vector3.UP, angle)
	var next := Transform3D(rotation_basis, hinge.position + rotation_basis * panel_offset())
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = panel.shape
	query.transform = global_transform * next
	query.collision_mask = 2 | 4 # Structures and player.
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	is_open = not is_zero_approx(angle)
	hinge.rotation.y = angle
	hinge.reset_physics_interpolation()
	panel.transform = next
	return true
