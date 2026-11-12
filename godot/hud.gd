extends CanvasLayer

signal build_toggled
signal view_toggled
signal projection_toggled
signal reset_requested
signal island_chosen(id: String)
signal island_created
signal island_config_requested
signal expansion_confirmed
signal import_requested(path: String)
signal item_chosen(id: String)
signal move_requested
signal rotate_requested
signal remove_requested
signal cancel_requested
signal touch_key(key: Key, down: bool)
signal place_requested
signal jump_requested
signal door_requested

const Catalog = preload("res://godot/catalog.gd")
const CATEGORIES := {
	"all": "全部", "recent": "最近", "structure": "结构", "furniture": "家具",
	"garden": "园艺", "landscape": "景观",
}
const SUBCATEGORIES := {
	"floors": "地板", "walls": "墙壁", "openings": "门窗", "stairs": "楼梯",
	"fences": "围栏", "frames": "构架", "roofs": "屋顶", "docks": "码头",
	"tables": "桌台", "seats": "座椅", "storage": "容器",
	"flowers": "花坛", "planters": "花盆花箱",
	"lights": "照明", "bridges": "桥梁", "props": "摆件",
}
const CARD_SIZE := Vector2(132, 70)
const GRID_GAP := 6
const RECENT_LIMIT := 12
const BUILD_ACTION_SIZE := Vector2(76, 40)
const BUILD_ACTION_INSET := 22.0
const BUILD_BOTTOM_INSET := 20.0

var catalog: Catalog
var root: Control
var build_button: Button
var door_button: Button
var view_button: Button
var projection_button: Button
var islands: MenuButton
var palette: PanelContainer
var browse: HBoxContainer
var build_actions: VBoxContainer
var exit_button: Button
var place_button: Button
var move_button: Button
var rotate_button: Button
var remove_button: Button
var cancel_button: Button
var items: GridContainer
var item_scroll: ScrollContainer
var subcategory_tabs: HFlowContainer
var expand_button: Button
var crosshair: Label
var hint: Label
var toast: Label
var thumb_textures: Dictionary
var category_buttons: Dictionary
var subcategory_buttons: Dictionary
var item_buttons: Dictionary
var available_items: Array[String]
var recent_items: Array[String]
var category := "all"
var subcategory := "all"
var palette_expanded := false
var palette_loaded := false
var active_item := ""
var touch_pad: VBoxContainer
var touch_mode := ""
var toast_generation := 0
var chooser: FileDialog
var expansion_dialog: ConfirmationDialog
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
	door_button = button(browse, "", func(): door_requested.emit())
	door_button.hide()

	setup_palette()
	setup_build_actions()

	crosshair = centered_label("⊹", 30, Control.PRESET_CENTER, 0.0)
	hint = centered_label("WASD 移动  ·  E/Q 升降  ·  拖动转向  ·  准星对准后点击选中", 14, Control.PRESET_CENTER_TOP, 26.0)
	toast = centered_label("", 15, Control.PRESET_CENTER_TOP, 67.0)
	chooser = FileDialog.new()
	chooser.title = "导入岛屿"
	chooser.access = FileDialog.ACCESS_FILESYSTEM
	chooser.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	chooser.filters = PackedStringArray(["*.json ; 岛屿存档"])
	chooser.use_native_dialog = true
	chooser.file_selected.connect(func(path: String): import_requested.emit(path))
	root.add_child(chooser)
	expansion_dialog = ConfirmationDialog.new()
	expansion_dialog.title = "测试配置"
	expansion_dialog.ok_button_text = "扩建"
	expansion_dialog.confirmed.connect(func(): expansion_confirmed.emit())
	root.add_child(expansion_dialog)

	if DisplayServer.is_touchscreen_available():
		touch_pad = VBoxContainer.new()
		root.add_child(touch_pad)
		touch_pad.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
		touch_pad.offset_left = 14
	set_mode("player")


func setup_palette() -> void:
	palette = PanelContainer.new()
	palette.theme_type_variation = &"BuildPalette"
	root.add_child(palette)
	palette.anchor_left = 0.5
	palette.anchor_right = 0.5
	palette.anchor_top = 1.0
	palette.anchor_bottom = 1.0
	palette.grow_vertical = Control.GROW_DIRECTION_BEGIN
	palette.offset_top = -BUILD_BOTTOM_INSET
	palette.offset_bottom = -BUILD_BOTTOM_INSET
	palette.minimum_size_changed.connect(func(): palette.offset_top = palette.offset_bottom)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	palette.add_child(body)
	var categories := GridContainer.new()
	categories.columns = 2
	categories.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(categories)
	for key: String in CATEGORIES:
		var tab := palette_tab(categories, CATEGORIES[key], change_category.bind(key))
		tab.custom_minimum_size.x = 54
		tab.toggle_mode = true
		category_buttons[key] = tab
	category_buttons["recent"].disabled = true

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", GRID_GAP)
	body.add_child(content)
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(header)
	subcategory_tabs = HFlowContainer.new()
	subcategory_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(subcategory_tabs)
	expand_button = palette_tab(header, "展开", toggle_palette)
	expand_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	item_scroll = ScrollContainer.new()
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	item_scroll.resized.connect(resize_item_grid)
	content.add_child(item_scroll)
	items = GridContainer.new()
	items.add_theme_constant_override("h_separation", GRID_GAP)
	items.add_theme_constant_override("v_separation", GRID_GAP)
	item_scroll.add_child(items)

	root.resized.connect(resize_palette)
	resize_palette()


func setup_build_actions() -> void:
	build_actions = VBoxContainer.new()
	build_actions.add_theme_constant_override("separation", GRID_GAP)
	root.add_child(build_actions)
	build_actions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	build_actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	build_actions.grow_vertical = Control.GROW_DIRECTION_BOTH
	build_actions.offset_right = -BUILD_ACTION_INSET
	build_actions.offset_left = -BUILD_ACTION_INSET

	place_button = build_action(build_actions, "放置", func(): place_requested.emit())
	place_button.add_theme_stylebox_override("normal", palette_style("#785421ed", "#f0c57e", 8, 3))
	place_button.add_theme_stylebox_override("hover", palette_style("#94692a", "#f8d49e", 8, 3))
	rotate_button = build_action(build_actions, "旋转", func(): rotate_requested.emit())
	move_button = build_action(build_actions, "移动", func(): move_requested.emit())
	remove_button = build_action(build_actions, "删除", func(): remove_requested.emit())
	cancel_button = build_action(build_actions, "取消", func(): cancel_requested.emit())

	exit_button = build_action(root, "退出", func(): build_toggled.emit())
	exit_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	exit_button.offset_right = -BUILD_ACTION_INSET
	exit_button.offset_left = -BUILD_ACTION_INSET - BUILD_ACTION_SIZE.x
	exit_button.offset_bottom = -BUILD_BOTTOM_INSET
	exit_button.offset_top = -BUILD_BOTTOM_INSET - BUILD_ACTION_SIZE.y


func build_action(parent: Control, title: String, action: Callable) -> Button:
	var control := palette_tab(parent, title, action)
	control.custom_minimum_size = BUILD_ACTION_SIZE
	control.add_theme_font_size_override("font_size", 16)
	return control


func resize_palette() -> void:
	var half := clampf(root.size.x / 2 - 12, 0, 520)
	var right_limit := root.size.x / 2 - BUILD_ACTION_INSET - BUILD_ACTION_SIZE.x - 12
	palette.offset_left = -half
	palette.offset_right = minf(half, right_limit)
	var row_count := clampi(floori(root.size.y * 0.40 / (CARD_SIZE.y + GRID_GAP)), 1, 3) if palette_expanded else 1
	item_scroll.custom_minimum_size.y = row_count * (CARD_SIZE.y + GRID_GAP) - GRID_GAP


func resize_item_grid() -> void:
	var width := item_scroll.size.x - item_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	items.columns = maxi(1, floori((width + GRID_GAP) / (CARD_SIZE.x + GRID_GAP)))


func toggle_palette() -> void:
	palette_expanded = not palette_expanded
	expand_button.text = "收起" if palette_expanded else "展开"
	resize_palette()


func palette_tab(parent: Control, title: String, action: Callable) -> Button:
	var tab := button(parent, title, action)
	tab.theme_type_variation = &"PaletteTab"
	return tab


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
	theme.set_type_variation(&"BuildPalette", &"PanelContainer")
	theme.set_stylebox("panel", &"BuildPalette", palette_style("#111719ac", "#c4d1ce48", 10, 8))
	for variant: StringName in [&"PaletteTab", &"PaletteCard"]:
		theme.set_type_variation(variant, &"Button")
		theme.set_font_size("font_size", variant, 14)
		var fill := "#4b5458ad" if variant == &"PaletteCard" else "#19222599"
		theme.set_stylebox("normal", variant, palette_style(fill, "#c5d1ce66", 8, 3))
		theme.set_stylebox("hover", variant, palette_style("#52636ada", "#d4ded8ac", 8, 3))
		theme.set_stylebox("pressed", variant, palette_style("#785421e8", "#f0c57e", 8, 3))
		theme.set_stylebox("disabled", variant, palette_style("#222a2b6b", "#d0d9d22c", 8, 3))
		theme.set_stylebox("hover_pressed", variant, theme.get_stylebox("pressed", variant))
		for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
			theme.set_color(state, variant, Color("#f0ede4"))
		theme.set_color("font_pressed_color", variant, Color("#fff0d1"))
		theme.set_color("font_hover_pressed_color", variant, Color("#fff0d1"))
		theme.set_color("font_disabled_color", variant, Color("#a8adaa"))
	return theme


func palette_style(fill: String, border: String, inset_x: float, inset_y: float) -> StyleBoxFlat:
	var background := style(Color(fill), inset_x, inset_y)
	background.set_corner_radius_all(2)
	background.set_border_width_all(1)
	background.border_color = Color(border)
	return background


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
	popup.add_item("测试配置…", 1000002)


func on_island_menu(id: int) -> void:
	if id == 1000000:
		island_created.emit()
	elif id == 1000001:
		chooser.popup_centered_ratio(0.7)
	elif id == 1000002:
		island_config_requested.emit()
	else:
		var popup := islands.get_popup()
		island_chosen.emit(popup.get_item_metadata(popup.get_item_index(id)))


func show_island_config(current: Vector2i, next: Vector2i) -> void:
	var at_limit := current == next
	expansion_dialog.dialog_text = "%d × %d 米" % [current.x, current.y]
	expansion_dialog.dialog_text += "（已达上限）" if at_limit else " → %d × %d 米" % [next.x, next.y]
	expansion_dialog.get_ok_button().disabled = at_limit
	expansion_dialog.cancel_button_text = "关闭" if at_limit else "取消"
	expansion_dialog.popup_centered(Vector2i(320, 120))


func set_mode(mode: String, perspective := false) -> void:
	var editing := mode == "build"
	browse.visible = not editing
	set_door_action("")
	palette.visible = editing
	build_actions.visible = editing
	exit_button.visible = editing
	crosshair.visible = editing
	hint.visible = editing and not DisplayServer.is_touchscreen_available()
	view_button.text = "岛屿" if mode == "player" else "角色"
	view_button.visible = not editing
	projection_button.text = "正交" if perspective else "透视"
	projection_button.visible = mode == "overview"
	if editing and not palette_loaded:
		palette_loaded = true
		for id: String in catalog.items:
			if catalog.available(id):
				available_items.append(id)
		change_category(category)
	update_touch(mode)


func set_door_action(action: String) -> void:
	door_button.visible = not action.is_empty()
	if door_button.visible:
		var title := action if touch_pad != null else "F  " + action
		if door_button.text != title:
			door_button.text = title


func change_category(key: String) -> void:
	category = key
	for id: String in category_buttons:
		category_buttons[id].set_pressed_no_signal(id == key)
	for child in subcategory_tabs.get_children():
		child.free()
	subcategory_buttons.clear()
	if key != "all" and key != "recent":
		var types := {}
		for id: String in available_items:
			var info: Dictionary = catalog.items[id]
			if info.category == key:
				types[info.get("subcategory", "")] = true
		if types.size() > 1:
			add_subcategory_tab("all", "全部")
			for type: String in SUBCATEGORIES:
				if types.has(type):
					add_subcategory_tab(type, SUBCATEGORIES[type])
	change_subcategory("all")


func add_subcategory_tab(key: String, title: String) -> void:
	var tab := palette_tab(subcategory_tabs, title, change_subcategory.bind(key))
	tab.toggle_mode = true
	subcategory_buttons[key] = tab


func change_subcategory(key: String) -> void:
	subcategory = key
	for id: String in subcategory_buttons:
		subcategory_buttons[id].set_pressed_no_signal(id == key)
	for child in items.get_children():
		child.free()
	item_buttons.clear()
	item_scroll.scroll_vertical = 0
	var choices := recent_items if category == "recent" else available_items
	for id: String in choices:
		var info: Dictionary = catalog.items[id]
		if category != "all" and category != "recent" and category != info.category:
			continue
		if subcategory != "all" and info.get("subcategory", "") != subcategory:
			continue
		var card := button(items, info.label, choose_from_palette.bind(id))
		card.theme_type_variation = &"PaletteCard"
		card.custom_minimum_size = CARD_SIZE
		card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.tooltip_text = info.label
		card.toggle_mode = true
		card.expand_icon = true
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_theme_constant_override("icon_max_width", 76)
		card.icon = thumbnail(id)
		card.set_pressed_no_signal(id == active_item)
		item_buttons[id] = card


func choose_from_palette(id: String) -> void:
	recent_items.erase(id)
	recent_items.push_front(id)
	if recent_items.size() > RECENT_LIMIT:
		recent_items.pop_back()
	category_buttons["recent"].disabled = false
	if category == "recent":
		items.move_child(item_buttons[id], 0)
		item_scroll.scroll_vertical = 0
	item_chosen.emit(id)


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


func set_build_state(item: String, selected: bool, valid: bool) -> void:
	var next := [item, selected, valid]
	if next == build_state:
		return
	build_state = next
	active_item = item
	var placing := not item.is_empty()
	place_button.disabled = not (placing and valid)
	move_button.disabled = not selected or placing
	remove_button.disabled = move_button.disabled
	rotate_button.disabled = not (selected or placing)
	cancel_button.disabled = rotate_button.disabled
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
