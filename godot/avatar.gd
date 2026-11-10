@tool
extends Node3D

const Catalog = preload("res://godot/catalog.gd")

var model: Node3D


func _ready() -> void:
	var catalog := Catalog.new()
	model = catalog.imported("player")
	$Fallback.visible = model == null
	if model == null:
		return
	var mount: Node3D = $Model
	mount.transform = Transform3D.IDENTITY
	mount.add_child(model)
	var bounds := AABB()
	var model_space := mount.global_transform.affine_inverse()
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var local := model_space * part.global_transform * rest_bounds(part)
		bounds = bounds.merge(local) if bounds.has_surface() else local
	if bounds.size.y > 0.01:
		mount.scale = Vector3.ONE * (0.84 / bounds.size.y)
		mount.position.y = -bounds.position.y * mount.scale.y
	if Engine.is_editor_hint():
		pose_preview()


func pose_preview() -> void:
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	if rigs.is_empty():
		return
	var rig := rigs[0] as Skeleton3D
	for i in range(2):
		var bone := rig.find_bone("Shoulder_L" if i == 0 else "Shoulder_R")
		if bone >= 0:
			rig.set_bone_pose_rotation(bone, neutral_shoulder(rig, bone, i == 0))


static func neutral_shoulder(rig: Skeleton3D, bone: int, left: bool) -> Quaternion:
	var rest := rig.get_bone_global_rest(bone).basis.orthonormalized().inverse()
	return rig.get_bone_pose_rotation(bone) * Quaternion(rest * Vector3.FORWARD, 1.4 if left else -1.4)


func rest_bounds(part: MeshInstance3D) -> AABB:
	var rig := part.get_node_or_null(part.skeleton) as Skeleton3D if not part.skeleton.is_empty() else null
	if part.skin == null or rig == null:
		return part.get_aabb()

	# The source mesh may be in centimeters while its posed skeleton is in meters.
	var bind_transforms: Array[Transform3D] = []
	for i in range(part.skin.get_bind_count()):
		var bone := part.skin.get_bind_bone(i)
		if bone < 0:
			bone = rig.find_bone(part.skin.get_bind_name(i))
		var rest := rig.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
		bind_transforms.append(rest * part.skin.get_bind_pose(i))
	var bounds := AABB()
	var found := false
	for surface in range(part.mesh.get_surface_count()):
		var arrays := part.mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := 8 if part.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		for i in range(vertices.size()):
			var point := Vector3.ZERO
			for j in range(i * stride, (i + 1) * stride):
				if weights[j] > 0.0:
					point += (bind_transforms[bones[j]] * vertices[i]) * weights[j]
			bounds = bounds.expand(point) if found else AABB(point, Vector3.ZERO)
			found = true
	return bounds if found else part.get_aabb()
