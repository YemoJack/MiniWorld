extends StaticBody3D

const Catalog = preload("res://godot/catalog.gd")
const SWING_TIME := 0.28
const SWING_CHECKS := 12

var is_open := false
var hinge: Node3D
var panel: CollisionShape3D
var panel_offset: Vector3
var swing_from := 0.0
var swing_to := 0.0
var swing_time := SWING_TIME


func setup_panel(catalog: Catalog, visual: Node3D) -> void:
	hinge = visual.get_node("DoorHinge")
	var size := catalog.door_panel_size()
	panel_offset = Vector3(size.x / 2.0, size.y / 2.0, 0)
	panel = catalog.box_shape(self, size, hinge.position + panel_offset)


func within_reach(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= 0.65 and absf(local.z) <= 0.90 and local.y >= -0.16 and local.y <= 0.42


func toggle(from: Vector3) -> void:
	if swing_time < SWING_TIME:
		return
	if is_open:
		start_swing(0.0)
	else:
		var away := PI / 2 if to_local(from).z >= 0.0 else -PI / 2
		if not start_swing(away):
			start_swing(-away)


func panel_pose(angle: float) -> Transform3D:
	var rotation_basis := Basis(Vector3.UP, angle)
	return Transform3D(rotation_basis, hinge.position + rotation_basis * panel_offset)


func blocked(pose: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = panel.shape
	query.transform = global_transform * pose
	query.collision_mask = 2 | 4 # Structures and player.
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func start_swing(angle: float) -> bool:
	var current := hinge.rotation.y
	for step in range(1, SWING_CHECKS + 1):
		if blocked(panel_pose(lerpf(current, angle, float(step) / SWING_CHECKS))):
			return false
	swing_from = current
	swing_to = angle
	swing_time = 0.0
	is_open = not is_zero_approx(angle)
	return true


func _physics_process(delta: float) -> void:
	if swing_time >= SWING_TIME:
		return
	swing_time = minf(SWING_TIME, swing_time + delta)
	var t := swing_time / SWING_TIME
	var angle := lerpf(swing_from, swing_to, t * t * (3.0 - 2.0 * t))
	var pose := panel_pose(angle)
	if blocked(pose):
		swing_time = SWING_TIME
		is_open = not is_zero_approx(hinge.rotation.y)
		return
	hinge.rotation.y = angle
	panel.transform = pose
