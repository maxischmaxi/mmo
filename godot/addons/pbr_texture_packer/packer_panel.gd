@tool
extends Control
## PBR Texture Packer - Packs separate PBR textures into Terrain3D-compatible format.
##
## Terrain3D requires packed textures:
## - Albedo+Height: RGB = Albedo, A = Height
## - Normal+Roughness: RGB = Normal, A = Roughness

# Detection patterns for auto-detecting texture types
const ALBEDO_PATTERNS := ["_diff", "_albedo", "_color", "_col", "_basecolor", "_base_color", "_bc"]
const NORMAL_PATTERNS := ["_nor", "_normal", "_nrm", "_norm"]
const ROUGHNESS_PATTERNS := ["_rough", "_roughness", "_rgh"]
const HEIGHT_PATTERNS := ["_height", "_disp", "_displacement", "_bump", "_ht", "_parallax"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "tga", "bmp"]

# Size options for output
const SIZE_OPTIONS := {
	"Original": 0,
	"512x512": 512,
	"1024x1024": 1024,
	"2048x2048": 2048,
	"4096x4096": 4096
}

# UI elements
var _albedo_path: LineEdit
var _height_path: LineEdit
var _normal_path: LineEdit
var _roughness_path: LineEdit
var _output_folder: LineEdit
var _output_name: LineEdit
var _output_size: OptionButton
var _status_label: RichTextLabel
var _generate_btn: Button
var _progress_bar: ProgressBar

# File dialogs
var _file_dialog: EditorFileDialog
var _folder_dialog: EditorFileDialog
var _output_folder_dialog: EditorFileDialog
var _current_target: LineEdit


func _init() -> void:
	name = "PBR Packer"
	custom_minimum_size = Vector2(250, 400)


func _ready() -> void:
	_build_ui()
	_create_dialogs()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# Header
	var header := Label.new()
	header.text = "PBR Texture Packer"
	header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(header)
	
	var desc := Label.new()
	desc.text = "Pack textures for Terrain3D"
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc)
	
	vbox.add_child(_create_separator())
	
	# Auto-detect button
	var auto_btn := Button.new()
	auto_btn.text = "Auto-Detect from Folder..."
	auto_btn.pressed.connect(_on_auto_detect_pressed)
	vbox.add_child(auto_btn)
	
	vbox.add_child(_create_separator())
	
	# Albedo + Height section
	var albedo_label := Label.new()
	albedo_label.text = "Albedo + Height"
	albedo_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(albedo_label)
	
	_albedo_path = _add_file_row(vbox, "Albedo:", "required")
	_height_path = _add_file_row(vbox, "Height:", "optional")
	
	vbox.add_child(_create_separator())
	
	# Normal + Roughness section
	var normal_label := Label.new()
	normal_label.text = "Normal + Roughness"
	normal_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(normal_label)
	
	_normal_path = _add_file_row(vbox, "Normal:", "required")
	_roughness_path = _add_file_row(vbox, "Roughness:", "optional")
	
	vbox.add_child(_create_separator())
	
	# Output settings
	var output_label := Label.new()
	output_label.text = "Output"
	output_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(output_label)
	
	_output_folder = _add_file_row(vbox, "Folder:", "select folder", true)
	
	# Output name
	var name_hbox := HBoxContainer.new()
	name_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(name_hbox)
	
	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.custom_minimum_size.x = 65
	name_hbox.add_child(name_label)
	
	_output_name = LineEdit.new()
	_output_name.placeholder_text = "base name"
	_output_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(_output_name)
	
	# Output size
	var size_hbox := HBoxContainer.new()
	size_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(size_hbox)
	
	var size_label := Label.new()
	size_label.text = "Size:"
	size_label.custom_minimum_size.x = 65
	size_hbox.add_child(size_label)
	
	_output_size = OptionButton.new()
	for key in SIZE_OPTIONS.keys():
		_output_size.add_item(key)
	_output_size.selected = 0
	_output_size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_hbox.add_child(_output_size)
	
	vbox.add_child(_create_separator())
	
	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.value = 0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size.y = 6
	_progress_bar.visible = false
	vbox.add_child(_progress_bar)
	
	# Generate button
	_generate_btn = Button.new()
	_generate_btn.text = "Generate Packed Textures"
	_generate_btn.pressed.connect(_on_generate_pressed)
	vbox.add_child(_generate_btn)
	
	# Status label
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.custom_minimum_size.y = 80
	_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status_label.scroll_following = true
	_set_status("[color=gray]Ready[/color]")
	vbox.add_child(_status_label)


func _create_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


func _add_file_row(parent: Control, label_text: String, hint: String, is_folder := false) -> LineEdit:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	parent.add_child(hbox)
	
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 65
	hbox.add_child(label)
	
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = hint
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(line_edit)
	
	var browse_btn := Button.new()
	browse_btn.text = "..."
	browse_btn.custom_minimum_size.x = 30
	if is_folder:
		browse_btn.pressed.connect(_on_browse_output_folder_pressed)
	else:
		browse_btn.pressed.connect(_on_browse_file_pressed.bind(line_edit))
	hbox.add_child(browse_btn)
	
	return line_edit


func _create_dialogs() -> void:
	# File dialog for texture selection
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "Select Texture"
	_file_dialog.filters = PackedStringArray([
		"*.png, *.jpg, *.jpeg, *.webp, *.tga ; Image Files"
	])
	_file_dialog.file_selected.connect(_on_file_selected)
	EditorInterface.get_base_control().add_child(_file_dialog)
	
	# Folder dialog for auto-detect
	_folder_dialog = EditorFileDialog.new()
	_folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_folder_dialog.title = "Select Folder with PBR Textures"
	_folder_dialog.dir_selected.connect(_on_folder_selected)
	EditorInterface.get_base_control().add_child(_folder_dialog)
	
	# Output folder dialog
	_output_folder_dialog = EditorFileDialog.new()
	_output_folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_output_folder_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_output_folder_dialog.title = "Select Output Folder"
	_output_folder_dialog.dir_selected.connect(_on_output_folder_selected)
	EditorInterface.get_base_control().add_child(_output_folder_dialog)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _file_dialog and is_instance_valid(_file_dialog):
			_file_dialog.queue_free()
		if _folder_dialog and is_instance_valid(_folder_dialog):
			_folder_dialog.queue_free()
		if _output_folder_dialog and is_instance_valid(_output_folder_dialog):
			_output_folder_dialog.queue_free()


func _on_browse_file_pressed(target: LineEdit) -> void:
	_current_target = target
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	if _current_target:
		_current_target.text = path


func _on_browse_output_folder_pressed() -> void:
	_output_folder_dialog.popup_centered_ratio(0.6)


func _on_output_folder_selected(path: String) -> void:
	_output_folder.text = path


func _on_auto_detect_pressed() -> void:
	_folder_dialog.popup_centered_ratio(0.6)


func _on_folder_selected(folder: String) -> void:
	_auto_detect_textures(folder)


func _auto_detect_textures(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		_set_status("[color=red]Error: Could not open folder[/color]")
		return
	
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			if ext in IMAGE_EXTENSIONS:
				files.append(folder.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	
	if files.is_empty():
		_set_status("[color=yellow]No images found[/color]")
		return
	
	# Clear existing paths
	_albedo_path.text = ""
	_height_path.text = ""
	_normal_path.text = ""
	_roughness_path.text = ""
	
	var detected := 0
	
	for file_path in files:
		var file_lower := file_path.to_lower()
		
		if _albedo_path.text.is_empty():
			for pattern in ALBEDO_PATTERNS:
				if pattern in file_lower:
					_albedo_path.text = file_path
					detected += 1
					break
		
		if _normal_path.text.is_empty():
			for pattern in NORMAL_PATTERNS:
				if pattern in file_lower:
					_normal_path.text = file_path
					detected += 1
					break
		
		if _roughness_path.text.is_empty():
			for pattern in ROUGHNESS_PATTERNS:
				if pattern in file_lower:
					_roughness_path.text = file_path
					detected += 1
					break
		
		if _height_path.text.is_empty():
			for pattern in HEIGHT_PATTERNS:
				if pattern in file_lower:
					_height_path.text = file_path
					detected += 1
					break
	
	# Auto-fill output folder and name
	if _output_folder.text.is_empty():
		_output_folder.text = folder
	
	if _output_name.text.is_empty() and not _albedo_path.text.is_empty():
		var base := _albedo_path.text.get_file().get_basename()
		for pattern in ALBEDO_PATTERNS:
			if pattern in base.to_lower():
				var idx := base.to_lower().find(pattern)
				base = base.substr(0, idx)
				break
		base = base.trim_suffix("_2k").trim_suffix("_4k").trim_suffix("_1k")
		_output_name.text = base
	
	var status := "Found %d textures\n" % detected
	status += "[color=green]A[/color]" if not _albedo_path.text.is_empty() else "[color=red]A[/color]"
	status += " [color=green]N[/color]" if not _normal_path.text.is_empty() else " [color=red]N[/color]"
	status += " [color=green]R[/color]" if not _roughness_path.text.is_empty() else " [color=gray]R[/color]"
	status += " [color=green]H[/color]" if not _height_path.text.is_empty() else " [color=gray]H[/color]"
	_set_status(status)


func _on_generate_pressed() -> void:
	if _albedo_path.text.is_empty():
		_set_status("[color=red]Albedo required[/color]")
		return
	
	if _normal_path.text.is_empty():
		_set_status("[color=red]Normal required[/color]")
		return
	
	if _output_folder.text.is_empty():
		_set_status("[color=red]Output folder required[/color]")
		return
	
	if _output_name.text.is_empty():
		_set_status("[color=red]Output name required[/color]")
		return
	
	_generate_btn.disabled = true
	_progress_bar.visible = true
	_progress_bar.value = 0
	
	await _generate_packed_textures()
	
	_generate_btn.disabled = false
	_progress_bar.visible = false


func _generate_packed_textures() -> void:
	_set_status("Loading textures...")
	_progress_bar.value = 10
	await get_tree().process_frame
	
	var albedo := _load_image(_albedo_path.text)
	if albedo == null:
		_set_status("[color=red]Failed to load albedo[/color]")
		return
	
	var target_size := Vector2i(albedo.get_width(), albedo.get_height())
	var size_key := _output_size.get_item_text(_output_size.selected)
	if SIZE_OPTIONS[size_key] > 0:
		var s: int = SIZE_OPTIONS[size_key]
		target_size = Vector2i(s, s)
	
	_progress_bar.value = 20
	await get_tree().process_frame
	
	var height: Image
	if _height_path.text.is_empty():
		height = Image.create(target_size.x, target_size.y, false, Image.FORMAT_L8)
		height.fill(Color.WHITE)
	else:
		height = _load_image(_height_path.text)
		if height == null:
			_set_status("[color=red]Failed to load height[/color]")
			return
	
	_progress_bar.value = 30
	await get_tree().process_frame
	
	var normal := _load_image(_normal_path.text)
	if normal == null:
		_set_status("[color=red]Failed to load normal[/color]")
		return
	
	_progress_bar.value = 40
	await get_tree().process_frame
	
	var roughness: Image
	if _roughness_path.text.is_empty():
		roughness = Image.create(target_size.x, target_size.y, false, Image.FORMAT_L8)
		roughness.fill(Color.WHITE)
	else:
		roughness = _load_image(_roughness_path.text)
		if roughness == null:
			_set_status("[color=red]Failed to load roughness[/color]")
			return
	
	_set_status("Packing textures...")
	_progress_bar.value = 50
	await get_tree().process_frame
	
	var albedo_height := _pack_channels(albedo, height, target_size)
	if albedo_height == null:
		_set_status("[color=red]Failed to pack albedo+height[/color]")
		return
	
	_progress_bar.value = 70
	await get_tree().process_frame
	
	var normal_roughness := _pack_channels(normal, roughness, target_size)
	if normal_roughness == null:
		_set_status("[color=red]Failed to pack normal+roughness[/color]")
		return
	
	_set_status("Saving...")
	_progress_bar.value = 85
	await get_tree().process_frame
	
	var base_name := _output_name.text
	var output_dir := _output_folder.text
	
	var albedo_height_path := output_dir.path_join(base_name + "_alb_ht.png")
	var normal_roughness_path := output_dir.path_join(base_name + "_nrm_rgh.png")
	
	var err := albedo_height.save_png(albedo_height_path)
	if err != OK:
		_set_status("[color=red]Failed to save albedo+height[/color]")
		return
	
	err = normal_roughness.save_png(normal_roughness_path)
	if err != OK:
		_set_status("[color=red]Failed to save normal+roughness[/color]")
		return
	
	_progress_bar.value = 100
	
	var status := "[color=lime]Done![/color] %dx%d\n\n" % [target_size.x, target_size.y]
	status += "[color=green]%s[/color]\n" % (base_name + "_alb_ht.png")
	status += "[color=green]%s[/color]" % (base_name + "_nrm_rgh.png")
	_set_status(status)
	
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


func _pack_channels(rgb_image: Image, alpha_image: Image, target_size: Vector2i) -> Image:
	var rgb := Image.new()
	rgb.copy_from(rgb_image)
	
	var alpha := Image.new()
	alpha.copy_from(alpha_image)
	
	if rgb.get_size() != target_size:
		rgb.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	
	if alpha.get_size() != target_size:
		alpha.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	
	rgb.convert(Image.FORMAT_RGBA8)
	alpha.convert(Image.FORMAT_L8)
	
	var rgb_data := rgb.get_data()
	var alpha_data := alpha.get_data()
	
	var output_data := PackedByteArray()
	output_data.resize(target_size.x * target_size.y * 4)
	
	var pixel_count := target_size.x * target_size.y
	for i in pixel_count:
		var rgb_idx := i * 4
		output_data[rgb_idx] = rgb_data[rgb_idx]
		output_data[rgb_idx + 1] = rgb_data[rgb_idx + 1]
		output_data[rgb_idx + 2] = rgb_data[rgb_idx + 2]
		output_data[rgb_idx + 3] = alpha_data[i]
	
	return Image.create_from_data(target_size.x, target_size.y, false, Image.FORMAT_RGBA8, output_data)


func _set_status(text: String) -> void:
	_status_label.text = text
