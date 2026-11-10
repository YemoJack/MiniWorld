extends CanvasLayer

signal build_toggled
signal view_toggled
signal projection_toggled
signal reset_requested
signal island_chosen(id: String)
signal island_created
signal import_requested(path: String)
signal item_chosen(id: String)
signal move_requested
signal rotate_requested
signal remove_requested
signal cancel_requested
signal touch_key(key: Key, down: bool)
signal confirm_requested
signal jump_requested

const Catalog = preload("res://godot/catalog.gd")
const CATEGORIES := {"all": "全部", "structure": "结构", "furniture": "家具", "garden": "园艺", "landscape": "景观"}

var catalog: Catalog
var root: Control
var build_button: Button
var view_button: Button
var projection_button: Button
var islands: MenuButton
var palette: PanelContainer
var browse: HBoxContainer
var status: Label
var move_button: Button
var rotate_button: Button
var remove_button: Button
var cancel_button: Button
var items: HBoxContainer
var crosshair: Label
var hint: Label
var toast: Label
var thumb_textures: Dictionary
var category_buttons: Dictionary
var item_buttons: Dictionary
var category := "all"
var active_item := ""
var touch_pad: VBoxContainer
var touch_mode := ""
var toast_generation := 0
var chooser: FileDialog
var build_state: Array


func setup(assets: Catalog) -> void:
	catalog = assets
	root = Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = build_theme()

	var brand := Label.new()
	brand.text = "MiniWorld"
	brand.add_theme_font_size_override("font_size", 26)
	root.add_child(brand)
	brand.position = Vector2(24, 19)
	var top := HBoxContainer.new()
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_right = -22
	top.offset_top = 18
	projection_button = button(top, "透视", func(): projection_toggled.emit())
	view_button = button(top, "岛屿", func(): view_toggled.emit())
	islands = MenuButton.new()
	islands.focus_mode = Control.FOCUS_NONE
	top.add_child(islands)
	islands.get_popup().id_pressed.connect(on_island_menu)

	browse = HBoxContainer.new()
	root.add_child(browse)
	browse.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	browse.grow_horizontal = Control.GROW_DIRECTION_BOTH
	browse.grow_vertical = Control.GROW_DIRECTION_BEGIN
	browse.offset_bottom = -22
	build_button = button(browse, "建造", func(): build_toggled.emit())
	button(browse, "复位", func(): reset_requested.emit())

	palette = PanelContainer.new()
	root.add_child(palette)
	palette.anchor_left = 0.5
	palette.anchor_right = 0.5
	palette.anchor_top = 1.0
	palette.anchor_bottom = 1.0
	palette.grow_vertical = Control.GROW_DIRECTION_BEGIN
	palette.offset_bottom = -20
	root.resized.connect(resize_palette)
	resize_palette()
	var rows := VBoxContainer.new()
	palette.add_child(rows)
	var selection := HBoxContainer.new()
	rows.add_child(selection)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection.add_child(status)
	move_button = button(selection, "移动", func(): move_requested.emit())
	rotate_button = button(selection, "旋转", func(): rotate_requested.emit())
	remove_button = button(selection, "删除", func(): remove_requested.emit())
	cancel_button = button(selection, "取消", func(): cancel_requested.emit())
	var filters := HBoxContainer.new()
	rows.add_child(filters)
	for key: String in CATEGORIES:
		var filter := button(filters, CATEGORIES[key], change_category.bind(key))
		filter.toggle_mode = true
		category_buttons[key] = filter
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(spacer)
	button(filters, "完成", func(): build_toggled.emit())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rows.add_child(scroll)
	items = HBoxContainer.new()
	scroll.add_child(items)

	crosshair = centered_label("⊹", 30, Control.PRESET_CENTER, 0.0)
	hint = centered_label("WASD 移动  ·  E/Q 升降  ·  拖动转向  ·  点击或回车确认", 14, Control.PRESET_CENTER_TOP, 26.0)
	toast = centered_label("", 15, Control.PRESET_CENTER_TOP, 67.0)
	chooser = FileDialog.new()
	chooser.title = "导入岛屿"
	chooser.access = FileDialog.ACCESS_FILESYSTEM
	chooser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	chooser.filters = PackedStringArray(["*.json ; 岛屿存档"])
	chooser.use_native_dialog = true
	chooser.file_selected.connect(func(path: String): import_requested.emit(path))
	root.add_child(chooser)

	if DisplayServer.is_touchscreen_available():
		touch_pad = VBoxContainer.new()
		root.add_child(touch_pad)
		touch_pad.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
		touch_pad.offset_left = 14
	set_mode("player")


func resize_palette() -> void:
	var half := clampf(root.size.x / 2 - 12, 0, 420)
	palette.offset_left = -half
	palette.offset_right = half


func centered_label(value: String, size: int, preset: int, y: float) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#fff9e8"))
	label.add_theme_color_override("font_outline_color", Color("#30443b"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.position.y += y
	return label


func button(parent: Control, title: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = title
	result.focus_mode = Control.FOCUS_NONE
	parent.add_child(result)
	if action.is_valid():
		result.pressed.connect(action)
	return result


func style(fill: Color, inset_x: float, inset_y: float) -> StyleBoxFlat:
	var background := StyleBoxFlat.new()
	background.bg_color = fill
	background.set_corner_radius_all(12)
	background.content_margin_left = inset_x
	background.content_margin_right = inset_x
	background.content_margin_top = inset_y
	background.content_margin_bottom = inset_y
	return background


func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", Color("#233e34"))
	for type in ["Button", "MenuButton"]:
		theme.set_stylebox("normal", type, style(Color("#faf6e8"), 13, 8))
		theme.set_stylebox("hover", type, style(Color("#e5ecdc"), 13, 8))
		theme.set_stylebox("pressed", type, style(Color("#345749"), 13, 8))
		for key in ["font_color", "font_hover_color", "font_focus_color"]:
			theme.set_color(key, type, Color("#233e34"))
		theme.set_color("font_pressed_color", type, Color("#fff8e5"))
	theme.set_stylebox("panel", "PanelContainer", style(Color("#faf6e8"), 10, 8))
	return theme


func set_islands(state: Dictionary) -> void:
	var popup := islands.get_popup()
	popup.clear()
	for i in range(state.islands.size()):
		var island: Dictionary = state.islands[i]
		popup.add_radio_check_item(island.name, i)
		popup.set_item_metadata(i, island.id)
		if island.id == state.activeId:
			islands.text = island.name + "  ⌄"
			popup.set_item_checked(i, true)
	popup.add_separator()
	popup.add_item("新建平坦岛", 1000000)
	popup.add_item("导入存档…", 1000001)


func on_island_menu(id: int) -> void:
	if id == 1000000:
		island_created.emit()
	elif id == 1000001:
		chooser.popup_centered_ratio(0.7)
	else:
		var popup := islands.get_popup()
		island_chosen.emit(popup.get_item_metadata(popup.get_item_index(id)))


func set_mode(mode: String, perspective := false) -> void:
	var editing := mode == "build"
	browse.visible = not editing
	palette.visible = editing
	crosshair.visible = editing
	hint.visible = editing and not DisplayServer.is_touchscreen_available()
	view_button.text = "岛屿" if mode == "player" else "角色"
	view_button.visible = not editing
	projection_button.text = "正交" if perspective else "透视"
	projection_button.visible = mode == "overview"
	if editing and item_buttons.is_empty():
		change_category(category)
	update_touch(mode)


func change_category(key: String) -> void:
	category = key
	for id: String in category_buttons:
		category_buttons[id].set_pressed_no_signal(id == key)
	for child in items.get_children():
		child.free()
	item_buttons.clear()
	for id: String in catalog.items:
		if not catalog.available(id):
			continue
		var info: Dictionary = catalog.items[id]
		if key != "all" and key != info.category:
			continue
		var card := button(items, info.label, func(): item_chosen.emit(id))
		card.custom_minimum_size.x = 100
		card.toggle_mode = true
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_theme_constant_override("icon_max_width", 79)
		card.icon = thumbnail(id)
		card.set_pressed_no_signal(id == active_item)
		item_buttons[id] = card


func thumbnail(id: String) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	if thumb_textures.has(id):
		return thumb_textures[id]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 66)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var model := catalog.visuals(id)
	viewport.add_child(model)
	var bounds := catalog.measured(model)
	var extent := maxf(bounds.size.length(), 0.10)
	var target := bounds.get_center()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent * 1.12
	camera.near = 0.001
	viewport.add_child(camera)
	camera.position = target + Vector3(0.7, 0.55, 0.9) * extent * 2.1
	camera.look_at(target)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -34, 0)
	light.light_energy = 1.35
	viewport.add_child(light)
	var ambient := DirectionalLight3D.new()
	ambient.rotation_degrees = Vector3(-10, 150, 0)
	ambient.light_energy = 0.48
	viewport.add_child(ambient)
	thumb_textures[id] = viewport.get_texture()
	return thumb_textures[id]


func set_build_state(item: String, selected: bool, placing: bool, moving: bool, valid: bool) -> void:
	var next := [item, selected, placing, moving, valid]
	if next == build_state:
		return
	build_state = next
	active_item = item
	status.text = ""
	if not item.is_empty():
		status.text = catalog.items[item].label
		if placing and not valid:
			status.text += " · 位置不可用"
	move_button.visible = selected and not placing
	remove_button.visible = selected and not placing
	rotate_button.visible = selected or placing
	cancel_button.visible = placing
	cancel_button.text = "取消移动" if moving else "取消"
	for id: String in item_buttons:
		item_buttons[id].set_pressed_no_signal(id == item and placing)
	crosshair.modulate = Color("#b8ffd8") if valid or not placing else Color("#ffb6a3")


func update_touch(mode: String) -> void:
	if touch_pad == null or touch_mode == mode:
		return
	touch_mode = mode
	for node in touch_pad.get_children():
		node.free()
	touch_pad.visible = mode != "overview"
	if not touch_pad.visible:
		return
	for entry in [["↑", KEY_W], ["←", KEY_A], ["↓", KEY_S], ["→", KEY_D]]:
		add_touch(entry[0], entry[1])
	if mode == "build":
		add_touch("升", KEY_E)
		add_touch("降", KEY_Q)
		button(touch_pad, "确认", func(): confirm_requested.emit())
	else:
		button(touch_pad, "跳", func(): jump_requested.emit())


func add_touch(title: String, key: Key) -> void:
	var control := button(touch_pad, title, Callable())
	control.button_down.connect(func(): touch_key.emit(key, true))
	control.button_up.connect(func(): touch_key.emit(key, false))


func show_message(value: String) -> void:
	toast_generation += 1
	var version := toast_generation
	toast.text = value
	toast.position.x = (root.size.x - toast.size.x) / 2
	await get_tree().create_timer(2.5).timeout
	if toast_generation == version:
		toast.text = ""
