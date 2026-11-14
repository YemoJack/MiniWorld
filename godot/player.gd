extends CharacterBody3D

const Avatar = preload("res://godot/avatar.gd")
const LOCOMOTION_LIBRARY = preload("res://assets/animations/locomotion.res")
const SEATING_LIBRARY := "res://local-assets/models/spy-player/seating.res"
const SIT_DOWN := &"seating/sit_down"
const STAND_UP := &"seating/stand_up"
const SEATED_CONTACT := Vector3(0, 0.161, -0.191)
const FALLBACK_CONTACT := Vector3(0, 0.343, 0)
const WALK_SPEED := 1.7
const RUN_SPEED := 3.1
const STRAFE_SPEED := 0.9
const BACKPEDAL_SPEED := 1.1
const GROUND_ACCELERATION := 14.0
const GROUND_BRAKING := 19.0
const AIR_ACCELERATION := 4.5
const JUMP_SPEED := 2.65
const GRAVITY := 8.2
const JUMP_BUFFER := 0.12
const COYOTE_TIME := 0.09
const CAMERA_DEFAULT_DISTANCE := 1.42
const CAMERA_DEFAULT_PITCH := deg_to_rad(-13.0)
const CAMERA_DOWN_LIMIT := deg_to_rad(-70.0)
const CAMERA_UP_LIMIT := deg_to_rad(55.0)
const CAMERA_HEIGHT := 0.65
const CAMERA_SHOULDER := 0.34
const CAMERA_MARGIN := 0.035

enum Seating { NONE, SITTING_DOWN, SEATED, STANDING_UP }

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var visual: Avatar = $Avatar
@onready var capsule: CollisionShape3D = $CollisionShape3D

var animation: AnimationPlayer
var movement_clips: Dictionary
var yaw := 0.0
var pitch := CAMERA_DEFAULT_PITCH
var active := true
var jump_buffer := 0.0
var ground_grace := 0.0
var camera_zoom := CAMERA_DEFAULT_DISTANCE
var camera_distance := CAMERA_DEFAULT_DISTANCE
var camera_sweep := PhysicsShapeQueryParameters3D.new()
var fallback_limbs: Array[Node3D]
var skeleton: Skeleton3D
var joints: Array[int]
var joint_axes: Array[Vector3]
var sideways_axes: Array[Vector3]
var rest_rotations: Array[Quaternion]
var phase := 0.0
var spawn := Vector3(0, 0.02, 2.8)
var smooth_y := 0.0
var seating := Seating.NONE
var seat: StaticBody3D
var seat_position := Vector3.ZERO
var seat_time := 0.0
var seat_yaw := 0.0
var stand_camera_yaw := 0.0
var seating_library: AnimationLibrary


func _ready() -> void:
	var sweep_shape := SphereShape3D.new()
	sweep_shape.radius = 0.085
	camera_sweep.shape = sweep_shape
	camera_sweep.collision_mask = collision_mask
	camera_sweep.exclude = [get_rid()]
	var asset := visual.model
	if asset != null:
		var animations := asset.find_children("*", "AnimationPlayer", true, false)
		if not animations.is_empty():
			animation = animations[0] as AnimationPlayer
			for clip in animation.get_animation_list():
				var kind := String(clip).get_file().to_lower()
				if kind in ["idle", "walk", "jump"]:
					movement_clips[kind] = clip
		setup_fallback_rig(asset)
		if animation != null and skeleton != null:
			animation.add_animation_library(&"locomotion", LOCOMOTION_LIBRARY)
			for clip in LOCOMOTION_LIBRARY.get_animation_list():
				movement_clips[String(clip)] = StringName("locomotion/" + String(clip))
			if ResourceLoader.exists(SEATING_LIBRARY, "AnimationLibrary"):
				seating_library = load(SEATING_LIBRARY) as AnimationLibrary
				animation.add_animation_library(&"seating", seating_library)
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
		sideways_axes.append(rest * Vector3.BACK)
		rest_rotations.append(neutral)


func respawn() -> void:
	clear_seating()
	global_position = spawn
	velocity = Vector3.ZERO
	jump_buffer = 0.0
	ground_grace = 0.0
	smooth_y = spawn.y
	visual.rotation.y = yaw + PI
	visual.show()
	camera_distance = Vector2(CAMERA_SHOULDER, camera_zoom).length()
	update_camera_pivot()
	camera.position = Vector3(CAMERA_SHOULDER, 0, camera_zoom)
	reset_physics_interpolation()
	camera_rig.reset_physics_interpolation()


func reset_camera() -> void:
	yaw = 0.0
	pitch = CAMERA_DEFAULT_PITCH
	camera_zoom = CAMERA_DEFAULT_DISTANCE


func turn(relative: Vector2) -> void:
	if seating != Seating.STANDING_UP:
		yaw = wrapf(yaw - relative.x, -PI, PI)
	pitch = clampf(pitch - relative.y, CAMERA_DOWN_LIMIT, CAMERA_UP_LIMIT)


func zoom(steps: float) -> void:
	camera_zoom = clampf(camera_zoom * pow(1.13, steps), 1.10, 3.20)


func request_jump() -> void:
	if seating == Seating.NONE:
		jump_buffer = JUMP_BUFFER


func stop_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	jump_buffer = 0.0
	ground_grace = 0.0


func drive(input: Vector2, delta: float, run_requested := false) -> void:
	if not active:
		return
	if seating != Seating.NONE:
		update_seating(delta)
		update_camera(delta)
		return
	var grounded := is_on_floor()
	ground_grace = COYOTE_TIME if grounded else maxf(0.0, ground_grace - delta)
	var axis := input.limit_length()
	var running := run_requested and axis.y > absf(axis.x) * 0.75
	var speed := RUN_SPEED if running else walking_speed(axis)
	var direction := Vector3(axis.x, 0, -axis.y).rotated(Vector3.UP, yaw)
	var acceleration := AIR_ACCELERATION
	if grounded:
		acceleration = GROUND_BRAKING if axis.is_zero_approx() else GROUND_ACCELERATION
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(direction.x, direction.z) * speed, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity.y -= GRAVITY * delta
	if jump_buffer > 0.0 and ground_grace > 0.0:
		velocity.y = JUMP_SPEED
		ground_grace = 0.0
		jump_buffer = 0.0
	else:
		jump_buffer = maxf(0.0, jump_buffer - delta)
	move_and_slide()
	if global_position.y < -3.4:
		respawn()
		update_camera(delta)
		return
	visual.rotation.y = lerp_angle(visual.rotation.y, yaw + PI, 1.0 - exp(-16.0 * delta))
	var motion := get_real_velocity()
	var local_motion := Vector3(motion.x, 0, motion.z).rotated(Vector3.UP, -yaw)
	animate(Vector2(local_motion.x, -local_motion.z), axis, running, delta)
	update_camera(delta)


func walking_speed(axis: Vector2) -> float:
	var longitudinal := BACKPEDAL_SPEED if axis.y < 0.0 else WALK_SPEED
	var direction := axis.normalized()
	return lerpf(STRAFE_SPEED, longitudinal, absf(direction.y))


func update_camera_pivot() -> void:
	var view_center := Vector3(global_position.x, smooth_y + CAMERA_HEIGHT, global_position.z)
	if seating != Seating.NONE:
		var seated_center := seat_position + Vector3.UP * 0.40
		view_center = view_center.lerp(seated_center, seating_progress())
	camera_rig.global_position = view_center
	camera_rig.rotation = Vector3(pitch, yaw, 0)


func update_camera(delta: float) -> void:
	smooth_y = clampf(lerpf(smooth_y, global_position.y, 1.0 - exp(-18.0 * delta)), global_position.y - 0.13, global_position.y + 0.13)
	update_camera_pivot()
	camera_sweep.transform.origin = camera_rig.global_position
	var offset := Vector3(CAMERA_SHOULDER, 0, camera_zoom)
	var length := offset.length()
	camera_sweep.motion = camera_rig.global_basis * offset
	var space := get_world_3d().direct_space_state
	var safe_fraction := 0.0 if not space.intersect_shape(camera_sweep, 1).is_empty() else space.cast_motion(camera_sweep)[0]
	var limit := length if safe_fraction >= 1.0 else maxf(0.0, length * safe_fraction - CAMERA_MARGIN)
	camera_distance = minf(limit, lerpf(camera_distance, limit, 1.0 - exp(-9.0 * delta)))
	camera.position = offset * (camera_distance / length)
	visual.visible = camera_distance > 0.30


func can_use_seats() -> bool:
	return seating_library != null or not fallback_limbs.is_empty()


func sit_at(place: Dictionary) -> void:
	if seating != Seating.NONE or not can_use_seats() or place.is_empty():
		return
	seat = place.seat
	seat_position = place.sit
	seat_yaw = place.yaw
	global_position = place.stand
	visual.position = Vector3.ZERO
	visual.rotation.y = seat_yaw
	for limb in fallback_limbs:
		limb.rotation.z = 0.0
	smooth_y = global_position.y
	velocity = Vector3.ZERO
	jump_buffer = 0.0
	ground_grace = 0.0
	reset_physics_interpolation()
	seating = Seating.SITTING_DOWN
	start_seat_clip(SIT_DOWN)
	update_camera(0.0)
	camera_rig.reset_physics_interpolation()


func stand_up() -> void:
	if seating == Seating.SEATED:
		stand_camera_yaw = yaw
		seating = Seating.STANDING_UP
		start_seat_clip(STAND_UP)


func start_seat_clip(clip: StringName) -> void:
	seat_time = 0.0
	if seating_library != null:
		animation.speed_scale = 1.0
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
		return
	var duration := seat_duration()
	if seating != Seating.SEATED:
		seat_time = minf(seat_time + delta, duration)
		if seating_library != null:
			animation.seek(seat_time, true)
	var progress := seating_progress()
	visual.rotation.y = seat_yaw
	if seating == Seating.STANDING_UP:
		var turn_duration := minf(duration, 0.55)
		yaw = lerp_angle(stand_camera_yaw, seat_yaw - PI, smoothstep(0.0, turn_duration, seat_time))
	var contact := SEATED_CONTACT if seating_library != null else FALLBACK_CONTACT
	var seated_origin := seat_position - Basis(Vector3.UP, seat_yaw) * contact
	visual.global_position = global_position.lerp(seated_origin, progress)
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


func clear_seating() -> void:
	if seating == Seating.NONE:
		return
	seating = Seating.NONE
	seat = null
	visual.position = Vector3.ZERO
	if seating_library != null:
		animation.stop()
		skeleton.reset_bone_poses()
		if movement_clips.has("idle"):
			animation.play(movement_clips.idle)
			animation.advance(0.0)
	else:
		for limb in fallback_limbs:
			limb.rotation.x = 0.0
			if limb.has_node("Shin"):
				limb.get_node("Shin").rotation.x = 0.0
	visual.reset_physics_interpolation()


func animate(motion: Vector2, input: Vector2, running: bool, delta: float) -> void:
	var speed := motion.length()
	var target := "idle"
	if not is_on_floor():
		target = "jump"
	elif speed > 0.12:
		if running:
			target = "run"
		else:
			# Keep a held diagonal on one clip as physics velocity fluctuates.
			var heading := input if not input.is_zero_approx() else motion
			if absf(heading.x) > absf(heading.y):
				target = "walk_right" if heading.x > 0.0 else "walk_left"
			else:
				target = "walk_back" if heading.y < 0.0 else "walk"
	if animation != null:
		var clip: StringName = movement_clips.get(target, movement_clips.get("walk", &"") if speed > 0.12 and is_on_floor() else &"")
		if not clip.is_empty():
			if animation.assigned_animation != clip:
				var source := animation.get_animation(clip)
				source.loop_mode = Animation.LOOP_NONE if target == "jump" else Animation.LOOP_LINEAR
				animation.play(clip, 0.12)
			var playback := 1.0
			match target:
				"walk_left", "walk_right":
					playback = clampf(speed / STRAFE_SPEED, 0.5, 1.2) * 1.55
				"walk_back":
					playback = clampf(speed / BACKPEDAL_SPEED, 0.5, 1.2) * 1.45
				"walk":
					playback = clampf(speed / WALK_SPEED, 0.5, 1.2)
				"run":
					playback = clampf(speed / RUN_SPEED, 0.7, 1.2) * 1.15
			animation.speed_scale = playback
			return
	var stride := clampf(speed / walking_speed(motion), 0.0, 1.0)
	var stride_direction := motion.normalized()
	var grounded := is_on_floor()
	var weight := 1.0 - exp(-14.0 * delta)
	phase += stride * delta * (14.0 if running else 10.0)
	for i in range(4):
		var angle := sin(phase + (PI if i in [1, 2] else 0.0)) * stride * (0.72 if running else 0.42)
		var forward := angle * stride_direction.y if grounded else -0.35
		var sideways := -angle * stride_direction.x * (0.42 if i < 2 else 0.80) if grounded else 0.0
		if joints.size() == 4:
			var goal := rest_rotations[i] * Quaternion(joint_axes[i], forward) * Quaternion(sideways_axes[i], sideways)
			var current_pose := skeleton.get_bone_pose_rotation(joints[i])
			skeleton.set_bone_pose_rotation(joints[i], current_pose.slerp(goal, weight))
		elif fallback_limbs.size() == 4:
			fallback_limbs[i].rotation.x = lerpf(fallback_limbs[i].rotation.x, forward, weight)
			fallback_limbs[i].rotation.z = lerpf(fallback_limbs[i].rotation.z, sideways, weight)
