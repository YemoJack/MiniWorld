extends CharacterBody3D

const Avatar = preload("res://godot/avatar.gd")
const SEATING_LIBRARY := "res://local-assets/models/spy-player/seating.res"
const SIT_DOWN := &"seating/sit_down"
const STAND_UP := &"seating/stand_up"
const SEATED_CONTACT := Vector3(0, 0.161, -0.191)
const FALLBACK_CONTACT := Vector3(0, 0.343, 0)

enum Seating { NONE, SITTING_DOWN, SEATED, STANDING_UP }

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var visual: Avatar = $Avatar
@onready var capsule: CollisionShape3D = $CollisionShape3D

var animation: AnimationPlayer
var yaw := PI
var pitch := -0.30
var active := true
var requested_jump := false
var fallback_limbs: Array[Node3D]
var skeleton: Skeleton3D
var joints: Array[int]
var joint_axes: Array[Vector3]
var rest_rotations: Array[Quaternion]
var phase := 0.0
var spawn := Vector3(0, 0.02, 2.8)
var smooth_y := 0.0
var seating := Seating.NONE
var seat: StaticBody3D
var seat_position := Vector3.ZERO
var seat_time := 0.0
var seat_approach_offset := Vector3.ZERO
var seat_approach_yaw := 0.0
var seat_yaw := 0.0
var seating_library: AnimationLibrary


func _ready() -> void:
	var asset := visual.model
	if asset != null:
		var animations := asset.find_children("*", "AnimationPlayer", true, false)
		if not animations.is_empty():
			animation = animations[0] as AnimationPlayer
			if ResourceLoader.exists(SEATING_LIBRARY, "AnimationLibrary"):
				seating_library = load(SEATING_LIBRARY) as AnimationLibrary
				animation.add_animation_library(&"seating", seating_library)
		setup_fallback_rig(asset)
	else:
		for limb in ["ArmLeft", "ArmRight", "LegLeft", "LegRight"]:
			fallback_limbs.append(visual.get_node("Fallback/" + limb))
	respawn()


func setup_fallback_rig(asset: Node3D) -> void:
	var skeletons := asset.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	skeleton = skeletons[0] as Skeleton3D
	for bone_name in ["Shoulder_L", "Shoulder_R", "UpperLeg_L", "UpperLeg_R"]:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			joints.clear()
			return
		var rest := skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()
		var neutral := skeleton.get_bone_pose_rotation(bone)
		if joints.size() < 2:
			neutral = Avatar.neutral_shoulder(skeleton, bone, joints.is_empty())
		joints.append(bone)
		joint_axes.append(rest * Vector3.RIGHT)
		rest_rotations.append(neutral)


func respawn() -> void:
	clear_seating()
	global_position = spawn
	velocity = Vector3.ZERO
	requested_jump = false
	smooth_y = spawn.y
	visual.rotation.y = PI
	update_camera()
	reset_physics_interpolation()
	camera_rig.reset_physics_interpolation()


func turn(relative: Vector2) -> void:
	yaw -= relative.x
	pitch = clampf(pitch - relative.y, -1.12, 0.18)


func drive(input: Vector2, delta: float) -> void:
	if not active:
		return
	if seating != Seating.NONE:
		requested_jump = false
		update_seating(delta)
		return
	var direction := Vector3(input.x, 0, -input.y).rotated(Vector3.UP, yaw - PI)
	velocity.x = direction.x * 1.7
	velocity.z = direction.z * 1.7
	velocity.y -= 8.2 * delta
	if requested_jump and is_on_floor():
		velocity.y = 2.65
	requested_jump = false
	move_and_slide()
	if global_position.y < -3.4:
		respawn()
	if direction.length_squared() > 0.001:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-16.0 * delta))
	animate(direction.length(), delta)
	smooth_y = lerpf(smooth_y, global_position.y, 1.0 - exp(-18.0 * delta))
	update_camera()


func update_camera() -> void:
	var view_center := global_position + Vector3.UP * 0.59
	if seating != Seating.NONE:
		var seated_center := seat_position + Vector3.UP * 0.40
		var progress := seating_progress()
		view_center = view_center.lerp(seated_center, progress)
		view_center.y += smooth_y - global_position.y
	else:
		view_center.y = smooth_y + 0.59
	camera_rig.global_position = view_center
	camera_rig.rotation = Vector3(pitch, yaw - PI, 0)


func can_use_seats() -> bool:
	return seating_library != null or not fallback_limbs.is_empty()


func sit_at(place: Dictionary) -> void:
	if seating != Seating.NONE or not can_use_seats() or place.is_empty():
		return
	seat = place.seat
	seat_position = place.sit
	seat_yaw = place.yaw
	seat_approach_offset = global_position - place.stand
	seat_approach_yaw = visual.rotation.y
	global_position = place.stand
	smooth_y = global_position.y
	velocity = Vector3.ZERO
	requested_jump = false
	reset_physics_interpolation()
	seating = Seating.SITTING_DOWN
	start_seat_clip(SIT_DOWN)


func stand_up() -> void:
	if seating == Seating.SEATED:
		seating = Seating.STANDING_UP
		start_seat_clip(STAND_UP)


func start_seat_clip(clip: StringName) -> void:
	seat_time = 0.0
	if seating_library != null:
		animation.play(clip)
		animation.advance(0)
		animation.pause()


func seat_duration() -> float:
	if seating_library == null:
		return 0.48
	var clip := STAND_UP if seating == Seating.STANDING_UP else SIT_DOWN
	return animation.get_animation(clip).length


func seating_progress() -> float:
	if seating == Seating.SEATED:
		return 1.0
	var progress := smoothstep(0.0, 1.0, seat_time / seat_duration())
	return 1.0 - progress if seating == Seating.STANDING_UP else progress


func update_seating(delta: float) -> void:
	if not is_instance_valid(seat):
		clear_seating()
		update_camera()
		return
	var duration := seat_duration()
	if seating != Seating.SEATED:
		seat_time = minf(seat_time + delta, duration)
		if seating_library != null:
			animation.seek(seat_time, true)
	var progress := seating_progress()
	var approach := 1.0 - smoothstep(0.0, 0.24, seat_time) if seating == Seating.SITTING_DOWN else 0.0
	visual.rotation.y = lerp_angle(seat_yaw, seat_approach_yaw, approach)
	var contact := SEATED_CONTACT if seating_library != null else FALLBACK_CONTACT
	var seated_origin := seat_position - Basis(Vector3.UP, seat_yaw) * contact
	visual.global_position = global_position.lerp(seated_origin, progress) + seat_approach_offset * approach
	if seating_library == null:
		for leg in fallback_limbs.slice(2):
			leg.rotation.x = -PI / 2.0 * progress
			leg.get_node("Shin").rotation.x = PI / 2.0 * progress
		for arm in fallback_limbs.slice(0, 2):
			arm.rotation.x = -0.38 * progress
	if seat_time >= duration:
		if seating == Seating.SITTING_DOWN:
			seating = Seating.SEATED
		elif seating == Seating.STANDING_UP:
			clear_seating()
	update_camera()


func clear_seating() -> void:
	if seating == Seating.NONE:
		return
	seating = Seating.NONE
	seat = null
	visual.position = Vector3.ZERO
	if seating_library != null:
		animation.stop()
		skeleton.reset_bone_poses()
		for clip in animation.get_animation_list():
			if String(clip).get_file().to_lower() == "idle":
				animation.play(clip)
				animation.advance(0.0)
				break
	else:
		for limb in fallback_limbs:
			limb.rotation.x = 0.0
			if limb.has_node("Shin"):
				limb.get_node("Shin").rotation.x = 0.0
	visual.reset_physics_interpolation()


func animate(speed: float, delta: float) -> void:
	if animation != null:
		var target := "jump" if not is_on_floor() else ("walk" if speed > 0.01 else "idle")
		for clip in animation.get_animation_list():
			if String(clip).get_file().to_lower() == target:
				var source := animation.get_animation(clip)
				source.loop_mode = Animation.LOOP_NONE if target == "jump" else Animation.LOOP_LINEAR
				if animation.assigned_animation != clip:
					animation.play(clip, 0.12)
				return
	phase += speed * delta * 10
	for i in range(4):
		var angle := sin(phase + (PI if i in [1, 2] else 0.0)) * speed * 0.42 if is_on_floor() else -0.35
		if joints.size() == 4:
			var goal := rest_rotations[i] * Quaternion(joint_axes[i], angle)
			var current_pose := skeleton.get_bone_pose_rotation(joints[i])
			skeleton.set_bone_pose_rotation(joints[i], current_pose.slerp(goal, 1.0 - exp(-14.0 * delta)))
		elif fallback_limbs.size() == 4:
			fallback_limbs[i].rotation.x = lerpf(fallback_limbs[i].rotation.x, angle, 1.0 - exp(-14.0 * delta))
