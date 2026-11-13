extends ColorRect

signal island_chosen(id: String)
signal island_created(title: String)
signal island_renamed(id: String, title: String)
signal expansion_requested
signal import_requested(path: String)
signal export_requested(id: String, path: String)

var save_list: ItemList
var open_button: Button
var rename_button: Button
var export_button: Button
var expand_button: Button
var name_dialog: ConfirmationDialog
var name_field: LineEdit
var chooser: FileDialog
var active_id := ""
var rename_id := ""
var export_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.08, 0.14, 0.13, 0.53)
	hide()

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 520
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var heading := Label.new()
	heading.text = "设置"
	heading.add_theme_font_size_override("font_size", 23)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	action(header, "关闭", hide)

	var toolbar := HBoxContainer.new()
	box.add_child(toolbar)
	var section := Label.new()
	section.text = "存档管理"
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(section)
	action(toolbar, "新建岛屿", edit_name.bind(false))
	action(toolbar, "导入…", choose_file.bind(false))

	save_list = ItemList.new()
	save_list.custom_minimum_size.y = 230
	save_list.add_theme_constant_override("v_separation", 12)
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color("#eeeadd")
	list_style.set_corner_radius_all(8)
	list_style.content_margin_left = 10
	list_style.content_margin_right = 10
	list_style.content_margin_top = 8
	list_style.content_margin_bottom = 8
	save_list.add_theme_stylebox_override("panel", list_style)
	save_list.add_theme_color_override("font_color", Color("#233e34"))
	save_list.add_theme_color_override("font_selected_color", Color("#faf6e8"))
	var selected_style := list_style.duplicate() as StyleBoxFlat
	selected_style.bg_color = Color("#345749")
	save_list.add_theme_stylebox_override("selected", selected_style)
	save_list.add_theme_stylebox_override("selected_focus", selected_style)
	save_list.item_selected.connect(func(_index: int): update_actions())
	save_list.item_activated.connect(func(_index: int): open_selected())
	box.add_child(save_list)

	var actions := HBoxContainer.new()
	box.add_child(actions)
	open_button = action(actions, "进入", open_selected)
	rename_button = action(actions, "重命名", edit_name.bind(true))
	export_button = action(actions, "导出…", choose_file.bind(true))
	expand_button = action(actions, "扩建岛屿", func(): expansion_requested.emit())

	name_dialog = ConfirmationDialog.new()
	name_dialog.ok_button_text = "保存"
	name_dialog.cancel_button_text = "取消"
	name_dialog.confirmed.connect(submit_name)
	add_child(name_dialog)
	name_field = LineEdit.new()
	name_field.placeholder_text = "岛屿名称"
	name_field.max_length = 40
	name_field.text_changed.connect(func(value: String):
		name_dialog.get_ok_button().disabled = value.strip_edges().is_empty()
	)
	name_dialog.add_child(name_field)
	name_dialog.register_text_enter(name_field)

	chooser = FileDialog.new()
	chooser.access = FileDialog.ACCESS_FILESYSTEM
	chooser.filters = PackedStringArray(["*.json ; 岛屿存档"])
	chooser.use_native_dialog = true
	chooser.file_selected.connect(file_selected)
	add_child(chooser)


func action(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func refresh(state: Dictionary) -> void:
	var previous := selected_id() if visible else ""
	active_id = state.activeId
	save_list.clear()
	var focus := 0
	for island: Dictionary in state.islands:
		var current: bool = island.id == active_id
		var index := save_list.add_item(("●  " if current else "     ") + island.name)
		save_list.set_item_metadata(index, island.id)
		save_list.set_item_tooltip(index, island.name)
		if island.id == previous or (previous.is_empty() and current):
			focus = index
	if save_list.item_count > 0:
		save_list.select(focus)
		save_list.ensure_current_is_visible()
	update_actions()


func selected_id() -> String:
	var selected := save_list.get_selected_items()
	return "" if selected.is_empty() else save_list.get_item_metadata(selected[0])


func update_actions() -> void:
	var id := selected_id()
	open_button.disabled = id.is_empty() or id == active_id
	rename_button.disabled = id.is_empty()
	export_button.disabled = id.is_empty()
	expand_button.disabled = id.is_empty() or id != active_id


func open_selected() -> void:
	var id := selected_id()
	if not id.is_empty() and id != active_id:
		island_chosen.emit(id)


func edit_name(rename: bool) -> void:
	var selected := save_list.get_selected_items()
	if rename and selected.is_empty():
		return
	rename_id = selected_id() if rename else ""
	name_dialog.title = "重命名岛屿" if rename else "新建平坦岛"
	name_dialog.ok_button_text = "保存" if rename else "创建"
	name_field.text = save_list.get_item_tooltip(selected[0]) if rename else ""
	name_dialog.get_ok_button().disabled = name_field.text.strip_edges().is_empty()
	name_dialog.popup_centered(Vector2i(320, 100))
	name_field.grab_focus()
	name_field.select_all()


func submit_name() -> void:
	var title := name_field.text.strip_edges()
	if title.is_empty():
		return
	if rename_id.is_empty():
		island_created.emit(title)
	else:
		island_renamed.emit(rename_id, title)


func choose_file(exporting: bool) -> void:
	export_id = selected_id() if exporting else ""
	if exporting and export_id.is_empty():
		return
	chooser.title = "导出岛屿" if exporting else "导入存档"
	chooser.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	chooser.current_file = "MiniWorld.json" if exporting else ""
	chooser.popup_centered_ratio(0.7)


func file_selected(path: String) -> void:
	if export_id.is_empty():
		import_requested.emit(path)
	else:
		export_requested.emit(export_id, path)
