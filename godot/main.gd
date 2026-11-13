extends Node3D

const Catalog = preload("res://godot/catalog.gd")
const Builder = preload("res://godot/builder.gd")
const Islands = preload("res://godot/islands.gd")
const IslandView = preload("res://godot/island_view.gd")
const ISLAND_SCENES := {
	"flat": preload("res://assets/islands/flat.tscn"),
	"cabin": preload("res://assets/islands/cabin.tscn"),
	"harbor": preload("res://assets/islands/harbor.tscn"),
}
const HUD = preload("res://godot/hud.gd")
const Player = preload("res://godot/player.gd")
const SPY_DRONE := "res://local-assets/models/spy-drone/SM_Prop_Drone_01.tscn"
const ORBIT_YAW := 0.595
const ORBIT_PITCH := 0.445
const ORBIT_DISTANCE := 18.9
const CLOUD_CLEARANCE := 3.0

@onready var island_root: Node3D = $Island
@onready var island := island_root.get_node_or_null("CabinIsland") as IslandView
@onready var clouds: Node3D = $Clouds
@onready var structures: Node3D = $Structures
@onready var player: Player = $Player
@onready var overview: Camera3D = $Overview
@onready var build_camera: Camera3D = $BuildCamera
@onready var hud: HUD = $HUD

var catalog := Catalog.new()
var islands: Islands
var builder: Builder
var mode := "player"
var return_mode := "player"
var perspective := false
var orbit_yaw := ORBIT_YAW
var orbit_pitch := ORBIT_PITCH
var orbit_distance := ORBIT_DISTANCE
var build_yaw := 0.42
var build_pitch := -0.52
var drone: Node3D
var rotors: Array[MeshInstance3D]
var cloud_positions: Array[Vector3]
var ghost: Node3D
var preview_wall: StaticBody3D
var ghost_material := StandardMaterial3D.new()
var outline := MeshInstance3D.new()
var outline_material := StandardMaterial3D.new()
var detail_grid := MeshInstance3D.new()
var selected := -1
var draft_item := ""
var draft_turns := 0
var draft_candidates: Array[Dictionary]
var draft_rotation_pending := false
var moving := -1
var opening_host := -1
var target: Dictionary
var valid := false
var place_pending := false
var door_pending := false
var pressed: Dictionary
var dragging := false


func _ready() -> void:
	create_drone()
	for cloud: Node3D in clouds.get_children():
		cloud_positions.append(cloud.position)
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.no_depth_test = false
	outline_material.albedo_color = Color("#b6ffe0")
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(outline)
	add_child(detail_grid)
	islands = Islands.new(catalog)
	hud.setup(catalog)
	hud.build_toggled.connect(toggle_build)
	hud.view_toggled.connect(toggle_view)
	hud.projection_toggled.connect(toggle_projection)
	hud.reset_requested.connect(reset_view)
	hud.island_chosen.connect(switch_island)
	hud.island_created.connect(create_island)
	hud.island_renamed.connect(rename_island)
	hud.settings_opened.connect(release_controls)
	hud.island_config_requested.connect(show_island_config)
	hud.expansion_confirmed.connect(expand_island)
	hud.import_requested.connect(import_save)
	hud.export_requested.connect(export_save)
	hud.item_chosen.connect(choose_item)
	hud.move_requested.connect(move_selected)
	hud.rotate_requested.connect(rotate_item)
	hud.remove_requested.connect(remove_selected)
	hud.remove_opening_requested.connect(remove_selected_opening)
	hud.cancel_requested.connect(cancel)
	hud.place_requested.connect(func(): place_pending = true)
	hud.jump_requested.connect(func(): player.requested_jump = mode == "player")
	hud.door_requested.connect(func(): door_pending = mode == "player")
	hud.touch_key.connect(func(key: Key, down: bool): pressed[key] = down)
	get_window().focus_exited.connect(release_controls)
	show_island()


func release_controls() -> void:
	pressed.clear()
	dragging = false


func create_drone() -> void:
	drone = Node3D.new()
	add_child(drone)
	build_camera.fov = 58
	build_camera.near = 0.04
	if ResourceLoader.exists(SPY_DRONE, "PackedScene"):
		var packed := load(SPY_DRONE) as PackedScene
		if packed != null:
			var model := packed.instantiate() as Node3D
			model.scale = Vector3.ONE * 0.8
			drone.add_child(model)
			for rotor in model.get_children():
				if rotor is MeshInstance3D:
					rotors.append(rotor)
			return

	var shell := Color("#f5eed8")
	var dark := Color("#30564c")
	catalog.box(drone, Vector3(0.25, 0.14, 0.34), Vector3.ZERO, shell)
	catalog.box(drone, Vector3(0.20, 0.08, 0.25), Vector3.DOWN * 0.055, dark)
	catalog.box(drone, Vector3(0.12, 0.028, 0.015), Vector3(0, 0.02, 0.17), Color("#89f3c5"))
	for x in [-1, 1]:
		for z in [-1, 1]:
			catalog.box(drone, Vector3(0.31, 0.048, 0.058), Vector3(x * 0.14, 0.012, z * 0.105), shell).rotation.y = -x * z * 0.58
			catalog.box(drone, Vector3(0.09, 0.05, 0.08), Vector3(x * 0.26, 0.038, z * 0.19), dark)
			rotors.append(catalog.box(drone, Vector3(0.22, 0.012, 0.025), Vector3(x * 0.26, 0.072, z * 0.19), dark))


func show_island() -> void:
	clear_selection()
	var data := islands.active()
	catalog = islands.active_catalog()
	hud.set_catalog(catalog)
	create_detail_grid()
	if island == null or island.terrain != data.terrain or island.grid != null:
		if island != null:
			island.free()
		var packed: PackedScene = ISLAND_SCENES[data.terrain]
		island = packed.instantiate() as IslandView
		island_root.add_child(island)
	island.setup(catalog)
	if builder == null:
		builder = Builder.new(catalog, structures)
	else:
		builder.catalog = catalog
	builder.has_pond = data.terrain == "cabin"
	builder.obstacles = island.obstacles
	island.resize_land(Islands.island_size(data))
	position_clouds()
	builder.rim = island.rim
	builder.harbor_water = island.harbor_water
	builder.load_island(data.placements)
	island.create_grid(builder)
	player.yaw = 0.0 if data.terrain == "harbor" else PI
	player.pitch = -0.30
	player.spawn = Vector3(2 * catalog.cell_size, 0.02, -2.8) if data.terrain == "harbor" else Vector3(0, 0.02, 2.8)
	player.respawn()
	aim_overview()
	set_mode("overview" if mode == "overview" else "player")
	hud.set_islands(islands.state)


func show_island_config() -> void:
	release_controls()
	var size := Islands.island_size(islands.active())
	hud.show_island_config(size, Islands.next_size(size))


func expand_island() -> void:
	var size := Islands.island_size(islands.active())
	var next := Islands.next_size(size)
	if next == size:
		return
	if not islands.expand_active(next):
		hud.show_message("存档未写入")
		return
	island.resize_land(next)
	position_clouds()
	builder.rim = island.rim
	builder.harbor_water = island.harbor_water
	island.create_grid(builder)
	aim_overview()


func position_clouds() -> void:
	var area := island.land_bounds.grow(CLOUD_CLEARANCE)
	var center := area.get_center()
	for index in cloud_positions.size():
		var cloud := clouds.get_child(index) as Node3D
		var original := cloud_positions[index]
		var offset := Vector2(original.x, original.z) - center
		var relative := (offset / (area.size * 0.5)).abs()
		var edge_ratio := maxf(relative.x, relative.y)
		if is_zero_approx(edge_ratio):
			offset = Vector2(0, -area.size.y * 0.5)
		elif edge_ratio < 1.0:
			offset /= edge_ratio
		var horizontal := center + offset
		cloud.position = Vector3(horizontal.x, original.y, horizontal.y)


func switch_island(id: String) -> void:
	if id == islands.state.activeId:
		return
	if not islands.select_island(id):
		hud.show_message("存档未写入")
		return
	hud.settings.hide()
	show_island()


func create_island(title: String) -> void:
	if islands.new_island(title):
		hud.settings.hide()
		show_island()
	else:
		hud.show_message("无法创建岛屿")


func rename_island(id: String, title: String) -> void:
	if islands.rename_island(id, title):
		hud.set_islands(islands.state)
	else:
		hud.show_message("无法重命名岛屿")


func save() -> void:
	if not islands.write():
		hud.show_message("存档未写入")


func import_save(path: String) -> void:
	if islands.merge_import(path):
		hud.settings.hide()
		show_island()
	else:
		hud.show_message("无法导入这个岛屿存档")


func export_save(id: String, path: String) -> void:
	hud.show_message("已导出存档" if islands.export_island(id, path) else "无法导出存档")


func reset_view() -> void:
	player.yaw = 0.0 if island.terrain == "harbor" else PI
	player.pitch = -0.30
	player.respawn()
	orbit_yaw = ORBIT_YAW
	orbit_pitch = ORBIT_PITCH
	orbit_distance = ORBIT_DISTANCE
	aim_overview()


func set_mode(next: String) -> void:
	mode = next
	player.active = mode == "player"
	player.visible = player.active
	drone.visible = mode == "build"
	island.grid.visible = mode == "build"
	pressed.clear()
	dragging = false
	place_pending = false
	door_pending = false
	match mode:
		"player": player.camera.make_current()
		"overview": overview.make_current()
		"build": build_camera.make_current()
	hud.set_mode(mode, perspective)


func toggle_view() -> void:
	if mode == "player":
		set_mode("overview")
	elif mode == "overview":
		set_mode("player")


func toggle_projection() -> void:
	perspective = not perspective
	aim_overview()
	hud.set_mode(mode, perspective)


func toggle_build() -> void:
	if mode != "build":
		return_mode = mode
		build_yaw = 0.42
		build_pitch = -0.52
		drone.position = Vector3(0.4, 1.1, 1.65)
		if island.terrain == "harbor":
			build_yaw = PI
			build_pitch = -0.58
			drone.position = Vector3(2 * catalog.cell_size, 1.1, -3 * catalog.cell_size)
		aim_drone()
		set_mode("build")
	else:
		clear_selection()
		set_mode(return_mode)
		if return_mode == "player" and player.test_move(player.global_transform, Vector3.ZERO, null, 0.001, true):
			player.respawn()


func aim_overview() -> void:
	var distance := orbit_distance * maxf(1.0, island.land_bounds.size.length() / Vector2(Islands.BASE_SIZE).length())
	overview.projection = Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	overview.size = distance * 0.67
	overview.fov = 43
	var center := Vector3(0, -0.64, 0)
	overview.position = center + Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch)) * distance
	overview.look_at(center)


func aim_drone() -> void:
	build_camera.rotation = Vector3(build_pitch, build_yaw, 0)
	build_camera.position = drone.position + build_camera.basis.z * 2.45 + build_camera.basis.y * 0.26
	drone.rotation.y = build_yaw + PI


func held(key: Key) -> int:
	return int(Input.is_physical_key_pressed(key) or pressed.get(key, false))


func _physics_process(delta: float) -> void:
	if hud.settings.visible or hud.expansion_dialog.visible:
		return
	var move := Vector2(held(KEY_D) - held(KEY_A), held(KEY_W) - held(KEY_S)).limit_length()
	var turn := Vector2(held(KEY_RIGHT) - held(KEY_LEFT), held(KEY_DOWN) - held(KEY_UP)) * delta * 1.42
	if mode == "player":
		player.turn(turn)
		update_nearby_door()
		player.drive(move, delta)
	elif mode == "build":
		build_yaw -= turn.x
		build_pitch = clampf(build_pitch - turn.y, -1.42, 1.22)
		var flight := Vector3(move.x, held(KEY_E) - held(KEY_Q), -move.y).limit_length()
		drone.position += flight.rotated(Vector3.UP, build_yaw) * 2.35 * delta
		var limits := island.land_bounds.grow_individual(2.2, 2.7, 2.2, 2.7)
		drone.position = drone.position.clamp(
			Vector3(limits.position.x, 0.28, limits.position.y), Vector3(limits.end.x, 9.3, limits.end.y)
		)
		aim_drone()
		for i in range(rotors.size()):
			rotors[i].rotation.y += delta * (22 if i % 2 == 0 else -22)
		update_build()


func update_nearby_door() -> void:
	var door := builder.nearby_door(player.global_position)
	var action := ""
	if door != null:
		if door_pending:
			door.toggle(player.global_position)
		action = "关门" if door.is_open else "开门"
	door_pending = false
	hud.set_door_action(action)


func _unhandled_input(event: InputEvent) -> void:
	if hud.settings.visible:
		if event.is_action_pressed("ui_cancel"):
			hud.settings.hide()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				if mode == "player":
					player.requested_jump = true
			KEY_F:
				door_pending = mode == "player"
			KEY_R:
				rotate_item()
			KEY_DELETE, KEY_BACKSPACE:
				remove_selected()
			KEY_ESCAPE:
				if mode == "build" and draft_item.is_empty():
					toggle_build()
				else:
					cancel()
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dragging = event.pressed
		elif mode == "overview" and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			orbit_distance = clampf(orbit_distance * (0.90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 5.0, 27.0)
			aim_overview()
	elif event is InputEventMouseMotion and dragging:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) == 0:
			dragging = false
			return
		var amount: Vector2 = event.relative * 0.005
		if mode == "player":
			player.turn(amount)
		elif mode == "build":
			build_yaw -= amount.x
			build_pitch = clampf(build_pitch - amount.y, -1.42, 1.22)
		else:
			orbit_yaw -= amount.x
			orbit_pitch = clampf(orbit_pitch + amount.y, -0.72, 1.42)
			aim_overview()


func clear_selection() -> void:
	if moving >= 0 and builder != null and builder.bodies[moving] != null:
		builder.bodies[moving].show()
	selected = -1
	moving = -1
	opening_host = -1
	draft_item = ""
	draft_candidates.clear()
	draft_rotation_pending = false
	target = {}
	valid = false
	place_pending = false
	update_ghost()
	update_outline(-1)
	hud.set_build_state("", false, false)


func cancel() -> void:
	if mode == "build" and not draft_item.is_empty():
		clear_selection()


func choose_item(id: String) -> void:
	clear_selection()
	draft_item = id
	draft_turns = 0


func move_selected() -> void:
	if selected < 0 or not draft_item.is_empty():
		return
	var p: Dictionary = builder.placements[selected]
	draft_item = p.item
	draft_turns = p.turns
	moving = selected
	builder.bodies[moving].hide()


func rotate_item() -> void:
	if mode != "build":
		return
	if not draft_item.is_empty():
		if draft_item not in Catalog.WOOD_OPENINGS:
			draft_rotation_pending = true
	elif selected >= 0:
		var p: Dictionary = builder.placements[selected].duplicate()
		if builder.layer(p) in ["edge", "gable"]:
			var facing: Vector2i = Builder.DIRECTIONS[p.turns]
			p.x += facing.x
			p.z += facing.y
			p.turns = (p.turns + 2) % 4
		else:
			p.turns = (p.turns + 1) % 4
		if builder.put(p, selected) >= 0:
			save()
		else:
			hud.show_message("无法旋转")


func remove_selected() -> void:
	if mode == "build" and selected >= 0 and draft_item.is_empty():
		if not builder.remove(selected):
			hud.show_message("请先移走上方的物件")
			return
		clear_selection()
		save()


func remove_selected_opening() -> void:
	if mode == "build" and draft_item.is_empty() and builder.set_wall_opening(selected, ""):
		save()


func update_build() -> void:
	var origin := build_camera.global_position
	var ray_end := origin - build_camera.global_basis.z * 24
	var installing := draft_item in Catalog.WOOD_OPENINGS
	var mask := 19 | Builder.OPENING_PICK_LAYER if installing else 19
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, mask)
	if moving >= 0:
		query.exclude = [builder.bodies[moving].get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as CollisionObject3D
	if collider != null and collider.collision_layer == Builder.OPENING_PICK_LAYER:
		collider = collider.get_parent() as CollisionObject3D
	var aimed := -1 if collider == null else int(collider.get_meta("placement", -1))
	selected = aimed if draft_item.is_empty() else -1
	if installing:
		update_opening_draft(aimed)
	elif not draft_item.is_empty():
		update_draft(hit, origin, ray_end)
	if place_pending:
		place_pending = false
		if not draft_item.is_empty() and valid:
			var destination := -1
			if installing:
				if builder.set_wall_opening(opening_host, draft_item):
					destination = opening_host
			else:
				destination = builder.put(target, moving)
			if destination >= 0:
				if moving >= 0:
					clear_selection()
				else:
					opening_host = -1
					valid = false
					target = {}
					draft_candidates.clear()
					update_ghost()
				save()
	update_outline(opening_host if installing else selected)
	var has_opening: bool = selected >= 0 and builder.placements[selected].has("opening")
	hud.set_build_state(draft_item, selected >= 0, valid, has_opening)


func update_opening_draft(aimed: int) -> void:
	var host := aimed if builder.can_set_wall_opening(aimed, draft_item) else -1
	if host == opening_host:
		return
	opening_host = host
	valid = host >= 0
	target = {}
	if valid:
		target = builder.placements[host].duplicate()
		target.opening = draft_item
	update_ghost()


func update_draft(hit: Dictionary, origin: Vector3, ray_end := Vector3.INF) -> void:
	var kind: String = catalog.items[draft_item].layer
	if kind == "edge":
		update_edge_draft(hit, origin, hit.get("position", ray_end))
		return
	if kind in ["roof", "gable"]:
		var shared_edges := builder.roof_edge_targets(draft_item, hit, moving)
		if not shared_edges.is_empty():
			if shared_edges != draft_candidates or draft_rotation_pending:
				draft_candidates = shared_edges
				var current := shared_edges.find(target)
				if draft_rotation_pending and current >= 0:
					shared_edges = shared_edges.slice(current + 1) + shared_edges.slice(0, current + 1)
				draft_rotation_pending = false
				choose_draft(shared_edges)
			return
	var candidates: Array[Dictionary] = []
	for turns in 4:
		candidates.append(builder.target(draft_item, turns, hit, origin))
	if candidates == draft_candidates and not draft_rotation_pending:
		return
	draft_candidates = candidates
	var start := (draft_turns + 1) % 4 if draft_rotation_pending else draft_turns
	draft_rotation_pending = false
	var ordered: Array[Dictionary] = []
	for step in 4:
		ordered.append(candidates[(start + step) % 4])
	choose_draft(ordered)


func update_edge_draft(hit: Dictionary, origin: Vector3, ray_end: Vector3) -> void:
	var candidates := builder.opening_edge_targets(draft_item, origin, ray_end, moving)
	var has_opening := not candidates.is_empty()
	var nearby := builder.nearby_edge_targets(draft_item, hit, origin)
	candidates.append_array(nearby)
	if nearby.is_empty():
		var snap := builder.connection_snap(draft_item, hit)
		var start: int = snap.get("turns", draft_turns)
		for step in 4:
			var candidate := builder.target(draft_item, (start + step) % 4, hit, origin, snap)
			if not candidate.is_empty() and candidate not in candidates:
				candidates.append(candidate)
	if moving >= 0 and builder.placements[moving].has("opening"):
		for candidate in candidates:
			candidate.opening = builder.placements[moving].opening
	if candidates == draft_candidates and not draft_rotation_pending:
		return
	draft_candidates = candidates
	var current := candidates.find(target)
	if draft_rotation_pending and current >= 0:
		var rotated: Array[Dictionary] = []
		for step in range(1, 5):
			var turns := (draft_turns + step) % 4
			for candidate in candidates:
				if candidate.turns == turns and candidate != target:
					rotated.append(candidate)
		rotated.append(target)
		candidates = rotated
	elif not has_opening and not nearby.is_empty() and current > 0 and valid \
		and builder.edge_target_score(target, hit.position, origin) <= builder.edge_target_score(nearby[0], hit.position, origin) + 0.035:
		candidates = candidates.duplicate()
		candidates.remove_at(current)
		candidates.push_front(target)
	draft_rotation_pending = false
	choose_draft(candidates)


func choose_draft(candidates: Array[Dictionary]) -> void:
	var next := {}
	var can_place := false
	for candidate in candidates:
		if candidate.is_empty():
			continue
		if next.is_empty():
			next = candidate
		if builder.can_place(candidate, moving):
			next = candidate
			draft_turns = candidate.turns
			can_place = true
			break
	if next != target or can_place != valid:
		target = next
		valid = can_place
		update_ghost()


func create_detail_grid() -> void:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, outline_material)
	for i in range(6):
		var axis := catalog.cell_size * (i / 5.0 - 0.5)
		lines.surface_add_vertex(Vector3(axis, 0, -catalog.cell_size / 2))
		lines.surface_add_vertex(Vector3(axis, 0, catalog.cell_size / 2))
		lines.surface_add_vertex(Vector3(-catalog.cell_size / 2, 0, axis))
		lines.surface_add_vertex(Vector3(catalog.cell_size / 2, 0, axis))
	lines.surface_end()
	detail_grid.mesh = lines
	detail_grid.hide()


func update_ghost() -> void:
	if is_instance_valid(preview_wall):
		preview_wall.show()
	preview_wall = null
	if ghost != null:
		ghost.free()
		ghost = null
	detail_grid.hide()
	if target.is_empty():
		return
	ghost = catalog.visuals(target.get("opening", target.item), builder.rise(target, moving), builder.visual_joins(target, moving))
	if opening_host >= 0:
		preview_wall = builder.bodies[opening_host]
		preview_wall.hide()
	else:
		ghost_material.albedo_color = Color(0.49, 0.88, 0.67, 0.55) if valid else Color(1.0, 0.34, 0.25, 0.53)
		for mesh in ghost.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = ghost_material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	ghost.transform = builder.placement_transform(target, moving)
	if builder.fine(target):
		var horizontal := Vector2(builder.cell(target)) * catalog.cell_size
		detail_grid.position = Vector3(horizontal.x, ghost.position.y + 0.006, horizontal.y)
		detail_grid.show()


func update_outline(index: int) -> void:
	if index < 0 or index >= builder.placements.size():
		outline.hide()
		outline.remove_meta("bounds")
		return
	var bounds := builder.placement_bounds(builder.placements[index]).grow(0.009)
	if outline.get_meta("bounds", AABB()) == bounds:
		return
	outline.set_meta("bounds", bounds)
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, outline_material)
	for corner in range(8):
		for bit in [1, 2, 4]:
			if corner & bit == 0:
				lines.surface_add_vertex(bounds.get_endpoint(corner))
				lines.surface_add_vertex(bounds.get_endpoint(corner | bit))
	lines.surface_end()
	outline.mesh = lines
	outline.show()
