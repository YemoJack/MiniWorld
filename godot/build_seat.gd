extends StaticBody3D

const STANDING_CLEARANCE := 0.17
const MAX_REACH := 0.75

var seat_bounds: AABB
var seat_count: int
var seat_height: float
var front_side := 0.0


func nearest_place(player: CharacterBody3D, capsule: CollisionShape3D) -> Dictionary:
	var origin := player.global_position
	var local := to_local(origin)
	if absf(local.y) > 0.32 or absf(local.x) > seat_bounds.size.x / 2.0 + MAX_REACH \
		or absf(local.z) > seat_bounds.size.z / 2.0 + MAX_REACH:
		return {}
	var space := get_world_3d().direct_space_state
	var side := 1.0 if local.z >= seat_bounds.get_center().z else -1.0
	if front_side != 0.0:
		side = front_side
	var best := {}
	var best_distance := MAX_REACH * MAX_REACH
	for i in seat_count:
		var x := seat_bounds.position.x + seat_bounds.size.x * (i + 0.5) / seat_count
		var sit := to_global(Vector3(x, seat_height, seat_bounds.get_center().z))
		var z := seat_bounds.get_center().z + side * (seat_bounds.size.z / 2.0 + STANDING_CLEARANCE)
		var stand := to_global(Vector3(x, 0, z))
		var floor_ray := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.28, stand - Vector3.UP * 0.35, player.collision_mask, [player.get_rid(), get_rid()])
		var floor_hit := space.intersect_ray(floor_ray)
		if floor_hit.is_empty() or floor_hit.normal.y < 0.75:
			continue
		stand.y = floor_hit.position.y + 0.003
		if absf(stand.y - origin.y) > 0.14 or sit.y - stand.y < 0.12 or sit.y - stand.y > 0.65:
			continue
		var distance := origin.distance_squared_to(stand)
		if distance >= best_distance:
			continue
		var standing := player.global_transform
		standing.origin = stand
		if player.test_move(standing, Vector3.ZERO, null, player.safe_margin, true) \
			or player.test_move(player.global_transform, stand - origin):
			continue
		var clearance := PhysicsShapeQueryParameters3D.new()
		var seated_shape := CapsuleShape3D.new()
		seated_shape.radius = (capsule.shape as CapsuleShape3D).radius
		seated_shape.height = 0.49
		clearance.shape = seated_shape
		clearance.transform.origin = sit + Vector3.UP * (seated_shape.height / 2.0 + 0.015)
		clearance.collision_mask = player.collision_mask
		clearance.exclude = [player.get_rid(), get_rid()]
		if not space.intersect_shape(clearance, 1).is_empty():
			continue
		var forward := global_basis.z * side
		best = {"seat": self, "sit": sit, "stand": stand, "yaw": atan2(forward.x, forward.z), "distance": distance}
		best_distance = distance
	return best
