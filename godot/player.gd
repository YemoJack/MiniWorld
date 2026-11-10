extends CharacterBody3D

const Avatar = preload("res://godot/avatar.gd")

@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var visual: Avatar = $Avatar

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


func _ready() -> void:
	var asset := visual.model
	if asset != null:
		var animations := asset.find_children("*", "AnimationPlayer", true, false)
		if not animations.is_empty():
			animation = animations[0] as AnimationPlayer
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
	for name in ["Shoulder_L", "Shoulder_R", "UpperLeg_L", "UpperLeg_R"]:
		var bone := skeleton.find_bone(name)
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
	camera_rig.global_position = Vector3(global_position.x, smooth_y + 0.59, global_position.z)
	camera_rig.rotation = Vector3(pitch, yaw - PI, 0)


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
			var rotation := skeleton.get_bone_pose_rotation(joints[i])
			skeleton.set_bone_pose_rotation(joints[i], rotation.slerp(goal, 1.0 - exp(-14.0 * delta)))
		elif fallback_limbs.size() == 4:
			fallback_limbs[i].rotation.x = lerpf(fallback_limbs[i].rotation.x, angle, 1.0 - exp(-14.0 * delta))
