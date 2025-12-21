@tool
extends Control
## Server Data Exporter Panel
##
## Exports all data the server needs:
##   1. Heightmaps from Terrain3D objects in village scenes
##   2. Spawn points to server/spawn_points.json
##   3. Obstacles to server/obstacles.json
##   4. Spawn areas to server/spawn_areas.json

# Zone configuration - maps zone_id to scene path and empire name
const ZONE_CONFIG = {
	1: {"scene": "res://scenes/world/shinsoo/village.tscn", "empire": "shinsoo"},
	100: {"scene": "res://scenes/world/chunjo/village.tscn", "empire": "chunjo"},
	200: {"scene": "res://scenes/world/jinno/village.tscn", "empire": "jinno"},
}

# Heightmap export resolution (samples per axis)
const HEIGHTMAP_RESOLUTION: int = 512

# Obstacle filtering
const MAX_OBSTACLE_SIZE = 50.0
const MIN_OBSTACLE_SIZE = 0.3

# UI Elements
var _status_label: RichTextLabel
var _progress_bar: ProgressBar
var _export_all_btn: Button
var _export_heightmaps_btn: Button
var _export_spawns_btn: Button
var _export_obstacles_btn: Button
var _export_spawn_areas_btn: Button
var _zone_checkboxes: Dictionary = {}

# Export state
var _is_exporting := false


func _init() -> void:
	name = "Server Export"
	custom_minimum_size = Vector2(250, 400)


func _ready() -> void:
	_build_ui()


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
	header.text = "Server Data Exporter"
	header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(header)
	
	var desc := Label.new()
	desc.text = "Export data for the game server"
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc)
	
	vbox.add_child(_create_separator())
	
	# Zone selection
	var zones_label := Label.new()
	zones_label.text = "Zones to Export"
	zones_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(zones_label)
	
	for zone_id in ZONE_CONFIG:
		var config = ZONE_CONFIG[zone_id]
		var checkbox := CheckBox.new()
		checkbox.text = "%s (Zone %d)" % [config.empire.capitalize(), zone_id]
		checkbox.button_pressed = true
		vbox.add_child(checkbox)
		_zone_checkboxes[zone_id] = checkbox
	
	vbox.add_child(_create_separator())
	
	# Export options label
	var options_label := Label.new()
	options_label.text = "Export Options"
	options_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(options_label)
	
	# Export All button (main action)
	_export_all_btn = Button.new()
	_export_all_btn.text = "Export All Server Data"
	_export_all_btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	_export_all_btn.pressed.connect(_on_export_all_pressed)
	vbox.add_child(_export_all_btn)
	
	vbox.add_child(_create_separator())
	
	# Individual export buttons
	var individual_label := Label.new()
	individual_label.text = "Export Individual"
	individual_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	individual_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(individual_label)
	
	var btn_container := HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_container)
	
	_export_heightmaps_btn = Button.new()
	_export_heightmaps_btn.text = "Heightmaps"
	_export_heightmaps_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_heightmaps_btn.pressed.connect(_on_export_heightmaps_pressed)
	btn_container.add_child(_export_heightmaps_btn)
	
	_export_spawns_btn = Button.new()
	_export_spawns_btn.text = "Spawns"
	_export_spawns_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_spawns_btn.pressed.connect(_on_export_spawns_pressed)
	btn_container.add_child(_export_spawns_btn)
	
	_export_obstacles_btn = Button.new()
	_export_obstacles_btn.text = "Obstacles"
	_export_obstacles_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_obstacles_btn.pressed.connect(_on_export_obstacles_pressed)
	btn_container.add_child(_export_obstacles_btn)
	
	# Second row of buttons
	var btn_container2 := HBoxContainer.new()
	btn_container2.add_theme_constant_override("separation", 4)
	vbox.add_child(btn_container2)
	
	_export_spawn_areas_btn = Button.new()
	_export_spawn_areas_btn.text = "Spawn Areas"
	_export_spawn_areas_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_spawn_areas_btn.pressed.connect(_on_export_spawn_areas_pressed)
	btn_container2.add_child(_export_spawn_areas_btn)
	
	vbox.add_child(_create_separator())
	
	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.value = 0
	_progress_bar.show_percentage = true
	_progress_bar.custom_minimum_size.y = 20
	_progress_bar.visible = false
	vbox.add_child(_progress_bar)
	
	# Status label
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.custom_minimum_size.y = 150
	_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status_label.scroll_following = true
	_set_status("[color=gray]Ready to export[/color]\n\nOutput: server/")
	vbox.add_child(_status_label)


func _create_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


func _get_selected_zones() -> Array:
	var selected := []
	for zone_id in _zone_checkboxes:
		if _zone_checkboxes[zone_id].button_pressed:
			selected.append(zone_id)
	return selected


func _set_buttons_enabled(enabled: bool) -> void:
	if _export_all_btn:
		_export_all_btn.disabled = not enabled
	if _export_heightmaps_btn:
		_export_heightmaps_btn.disabled = not enabled
	if _export_spawns_btn:
		_export_spawns_btn.disabled = not enabled
	if _export_obstacles_btn:
		_export_obstacles_btn.disabled = not enabled
	if _export_spawn_areas_btn:
		_export_spawn_areas_btn.disabled = not enabled


func _set_status(text: String) -> void:
	_status_label.text = text


func _append_status(text: String) -> void:
	_status_label.text += text


func _get_server_path() -> String:
	var project_path: String = ProjectSettings.globalize_path("res://")
	return project_path.path_join("../server")


#region Export All
func _on_export_all_pressed() -> void:
	if _is_exporting:
		return
	
	var selected_zones := _get_selected_zones()
	if selected_zones.is_empty():
		_set_status("[color=red]No zones selected![/color]")
		return
	
	_is_exporting = true
	_set_buttons_enabled(false)
	_progress_bar.visible = true
	_progress_bar.value = 0
	
	var server_path := _get_server_path()
	
	_set_status("[color=cyan]Starting export...[/color]\n")
	_append_status("Output: %s\n\n" % server_path)
	
	await get_tree().process_frame
	
	# Step 1: Heightmaps (0-40%)
	_append_status("[color=yellow]Step 1/4: Heightmaps[/color]\n")
	await _export_heightmaps(server_path, selected_zones)
	
	# Step 2: Spawn Points (40-55%)
	_progress_bar.value = 40
	_append_status("\n[color=yellow]Step 2/4: Spawn Points[/color]\n")
	await get_tree().process_frame
	await _export_spawn_points(server_path, selected_zones)
	
	# Step 3: Obstacles (55-70%)
	_progress_bar.value = 55
	_append_status("\n[color=yellow]Step 3/4: Obstacles[/color]\n")
	await get_tree().process_frame
	await _export_obstacles(server_path, selected_zones)
	
	# Step 4: Spawn Areas (70-100%)
	_progress_bar.value = 70
	_append_status("\n[color=yellow]Step 4/4: Spawn Areas[/color]\n")
	await get_tree().process_frame
	await _export_spawn_areas(server_path, selected_zones)
	
	_progress_bar.value = 100
	_append_status("\n[color=lime]=============================")
	_append_status("\n        Export Complete!")
	_append_status("\n=============================[/color]")
	
	_is_exporting = false
	_set_buttons_enabled(true)
	_progress_bar.visible = false
#endregion


#region Individual Exports
func _on_export_heightmaps_pressed() -> void:
	if _is_exporting:
		return
	
	var selected_zones := _get_selected_zones()
	if selected_zones.is_empty():
		_set_status("[color=red]No zones selected![/color]")
		return
	
	_is_exporting = true
	_set_buttons_enabled(false)
	_progress_bar.visible = true
	_progress_bar.value = 0
	
	_set_status("[color=cyan]Exporting heightmaps...[/color]\n\n")
	await get_tree().process_frame
	
	await _export_heightmaps(_get_server_path(), selected_zones)
	
	_progress_bar.value = 100
	_append_status("\n[color=lime]Heightmap export complete![/color]")
	
	_is_exporting = false
	_set_buttons_enabled(true)
	_progress_bar.visible = false


func _on_export_spawns_pressed() -> void:
	if _is_exporting:
		return
	
	var selected_zones := _get_selected_zones()
	if selected_zones.is_empty():
		_set_status("[color=red]No zones selected![/color]")
		return
	
	_is_exporting = true
	_set_buttons_enabled(false)
	
	_set_status("[color=cyan]Exporting spawn points...[/color]\n\n")
	await get_tree().process_frame
	
	await _export_spawn_points(_get_server_path(), selected_zones)
	
	_append_status("\n[color=lime]Spawn points export complete![/color]")
	
	_is_exporting = false
	_set_buttons_enabled(true)


func _on_export_obstacles_pressed() -> void:
	if _is_exporting:
		return
	
	var selected_zones := _get_selected_zones()
	if selected_zones.is_empty():
		_set_status("[color=red]No zones selected![/color]")
		return
	
	_is_exporting = true
	_set_buttons_enabled(false)
	
	_set_status("[color=cyan]Exporting obstacles...[/color]\n\n")
	await get_tree().process_frame
	
	await _export_obstacles(_get_server_path(), selected_zones)
	
	_append_status("\n[color=lime]Obstacles export complete![/color]")
	
	_is_exporting = false
	_set_buttons_enabled(true)


func _on_export_spawn_areas_pressed() -> void:
	if _is_exporting:
		return
	
	var selected_zones := _get_selected_zones()
	if selected_zones.is_empty():
		_set_status("[color=red]No zones selected![/color]")
		return
	
	_is_exporting = true
	_set_buttons_enabled(false)
	
	_set_status("[color=cyan]Exporting spawn areas...[/color]\n\n")
	await get_tree().process_frame
	
	await _export_spawn_areas(_get_server_path(), selected_zones)
	
	_append_status("\n[color=lime]Spawn areas export complete![/color]")
	
	_is_exporting = false
	_set_buttons_enabled(true)
#endregion


#region Heightmap Export
func _export_heightmaps(server_path: String, zones: Array) -> void:
	var heightmaps_path: String = server_path.path_join("heightmaps")
	
	# Ensure target directory exists
	if not DirAccess.dir_exists_absolute(heightmaps_path):
		var err := DirAccess.make_dir_recursive_absolute(heightmaps_path)
		if err != OK:
			_append_status("[color=red]Failed to create directory[/color]\n")
			return
	
	var zone_count := zones.size()
	var zone_idx := 0
	
	for zone_id in zones:
		var config = ZONE_CONFIG[zone_id]
		var scene_path: String = config.scene
		var empire_name: String = config.empire
		
		_append_status("  %s... " % empire_name.capitalize())
		await get_tree().process_frame
		
		# Load scene
		var scene = load(scene_path)
		if scene == null:
			_append_status("[color=red]scene not found[/color]\n")
			continue
		
		# Instantiate scene to access Terrain3D
		var root = scene.instantiate()
		if root == null:
			_append_status("[color=red]failed to instantiate[/color]\n")
			continue
		
		# Find Terrain3D node
		var terrain: Terrain3D = _find_terrain3d(root)
		if terrain == null:
			_append_status("[color=yellow]no terrain[/color]\n")
			root.queue_free()
			continue
		
		# Get data directory
		var data_dir: String = terrain.data_directory
		if data_dir.is_empty():
			_append_status("[color=red]no data dir[/color]\n")
			root.queue_free()
			continue
		
		root.queue_free()
		
		# Export heightmap
		var success := await _export_terrain_heightmap_from_directory(data_dir, empire_name, heightmaps_path)
		
		if success:
			_append_status("[color=lime]OK[/color]\n")
		else:
			_append_status("[color=red]FAILED[/color]\n")
		
		zone_idx += 1
		_progress_bar.value = (float(zone_idx) / zone_count) * 50.0


func _find_terrain3d(node: Node) -> Terrain3D:
	if node is Terrain3D:
		return node
	
	for child in node.get_children():
		var result = _find_terrain3d(child)
		if result != null:
			return result
	
	return null


func _parse_terrain_coords(coords_part: String) -> PackedStringArray:
	var result := PackedStringArray()
	var parts := coords_part.split("_")
	
	if parts.size() >= 2:
		result.append(parts[0])
		result.append(parts[1])
	
	return result


func _export_terrain_heightmap_from_directory(data_dir: String, empire_name: String, output_dir: String) -> bool:
	# Create a temporary Terrain3D to load and query the data
	var terrain := Terrain3D.new()
	terrain.data_directory = data_dir
	
	# Add to scene tree temporarily so it can initialize
	var parent: Node = EditorInterface.get_base_control()
	parent.add_child(terrain)
	
	await get_tree().process_frame
	
	# Check if data loaded
	if terrain.data == null:
		terrain.queue_free()
		return false
	
	# Get terrain bounds by parsing the .res filenames
	var region_size: int = terrain.region_size
	
	var dir := DirAccess.open(data_dir)
	if dir == null:
		terrain.queue_free()
		return false
	
	var min_rx: int = 999999
	var max_rx: int = -999999
	var min_rz: int = 999999
	var max_rz: int = -999999
	var region_count: int = 0
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".res") and file_name.begins_with("terrain3d_"):
			var coords_part: String = file_name.replace("terrain3d_", "").replace(".res", "")
			var coords: PackedStringArray = _parse_terrain_coords(coords_part)
			if coords.size() == 2:
				var rx: int = int(coords[0])
				var rz: int = int(coords[1])
				min_rx = min(min_rx, rx)
				max_rx = max(max_rx, rx)
				min_rz = min(min_rz, rz)
				max_rz = max(max_rz, rz)
				region_count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	
	if region_count == 0:
		terrain.queue_free()
		return false
	
	# Convert region coordinates to world coordinates
	var min_x: float = float(min_rx) * region_size
	var max_x: float = float(max_rx + 1) * region_size
	var min_z: float = float(min_rz) * region_size
	var max_z: float = float(max_rz + 1) * region_size
	
	var terrain_size_x: float = max_x - min_x
	var terrain_size_z: float = max_z - min_z
	var terrain_size: float = maxf(terrain_size_x, terrain_size_z)
	
	# Use appropriate resolution based on terrain size
	var resolution: int = HEIGHTMAP_RESOLUTION
	if terrain_size > 1024:
		resolution = 1024
	
	# Metadata
	var metadata: Dictionary = {
		"version": 1,
		"width": resolution,
		"height": resolution,
		"world_min_x": min_x,
		"world_max_x": max_x,
		"world_min_z": min_z,
		"world_max_z": max_z,
		"terrain_size": terrain_size,
	}
	
	# Save metadata JSON
	var json_path: String = output_dir.path_join(empire_name + "_heightmap.json")
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	if json_file == null:
		terrain.queue_free()
		return false
	
	json_file.store_string(JSON.stringify(metadata, "  "))
	json_file.close()
	
	# Sample and export height data
	var bin_path: String = output_dir.path_join(empire_name + "_heightmap.bin")
	var bin_file := FileAccess.open(bin_path, FileAccess.WRITE)
	if bin_file == null:
		terrain.queue_free()
		return false
	
	var step_x: float = terrain_size_x / float(resolution)
	var step_z: float = terrain_size_z / float(resolution)
	
	for z_idx in range(resolution):
		var world_z: float = min_z + (float(z_idx) + 0.5) * step_z
		
		for x_idx in range(resolution):
			var world_x: float = min_x + (float(x_idx) + 0.5) * step_x
			
			var height: float = terrain.data.get_height(Vector3(world_x, 0, world_z))
			
			# Handle NaN (outside terrain bounds)
			if is_nan(height):
				height = 0.0
			
			bin_file.store_float(height)
	
	bin_file.close()
	
	# Cleanup terrain node
	terrain.queue_free()
	
	return true
#endregion


#region Spawn Points Export
func _export_spawn_points(server_path: String, zones: Array) -> void:
	var all_zones = {}
	
	for zone_id in zones:
		var config = ZONE_CONFIG[zone_id]
		var scene_path: String = config.scene
		
		_append_status("  Zone %d... " % zone_id)
		
		var scene = load(scene_path)
		if scene == null:
			_append_status("[color=red]not found[/color]\n")
			continue
		
		var root = scene.instantiate()
		var spawn_points = _extract_spawn_points(root, Transform3D.IDENTITY)
		root.queue_free()
		
		if spawn_points.is_empty():
			spawn_points.append({
				"name": "default",
				"x": 0.0,
				"y": 1.0,
				"z": 0.0,
				"is_default": true,
			})
		else:
			# Mark first spawn point as default if none are marked
			var has_default = false
			for sp in spawn_points:
				if sp.get("is_default", false):
					has_default = true
					break
			if not has_default:
				spawn_points[0]["is_default"] = true
		
		all_zones[str(zone_id)] = spawn_points
		_append_status("[color=lime]%d spawn(s)[/color]\n" % spawn_points.size())
	
	# Save to JSON
	var json_string = JSON.stringify(all_zones, "  ")
	
	# Save to godot project
	var godot_path = "res://exported_spawn_points.json"
	var file = FileAccess.open(godot_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	
	# Save to server
	var server_file_path = server_path.path_join("spawn_points.json")
	var server_file = FileAccess.open(server_file_path, FileAccess.WRITE)
	if server_file:
		server_file.store_string(json_string)
		server_file.close()
		_append_status("  Saved to server/spawn_points.json\n")


func _extract_spawn_points(node: Node, parent_transform: Transform3D) -> Array:
	var spawn_points = []
	
	var global_transform = parent_transform
	if node is Node3D:
		global_transform = parent_transform * node.transform
	
	if node is Marker3D:
		var node_name = node.name as String
		if "SpawnPoint" in node_name or "spawn_point" in node_name.to_lower():
			var pos = global_transform.origin
			var is_default = (node_name == "SpawnPoint")
			var spawn_name = node_name.replace("SpawnPoint", "").strip_edges()
			if spawn_name.is_empty():
				spawn_name = "default"
			
			spawn_points.append({
				"name": spawn_name,
				"x": pos.x,
				"y": pos.y,
				"z": pos.z,
				"is_default": is_default,
			})
	
	for child in node.get_children():
		spawn_points.append_array(_extract_spawn_points(child, global_transform))
	
	return spawn_points
#endregion


#region Obstacles Export
func _export_obstacles(server_path: String, zones: Array) -> void:
	var all_zones = {}
	
	for zone_id in zones:
		var config = ZONE_CONFIG[zone_id]
		var scene_path: String = config.scene
		
		_append_status("  Zone %d... " % zone_id)
		
		var scene = load(scene_path)
		if scene == null:
			_append_status("[color=red]not found[/color]\n")
			continue
		
		var root = scene.instantiate()
		var raw_obstacles = _extract_obstacles(root, Transform3D.IDENTITY)
		root.queue_free()
		
		var obstacles = _filter_and_dedupe_obstacles(raw_obstacles)
		all_zones[str(zone_id)] = obstacles
		_append_status("[color=lime]%d obstacle(s)[/color]\n" % obstacles.size())
	
	# Save to JSON
	var json_string = JSON.stringify(all_zones, "  ")
	
	# Save to godot project
	var godot_path = "res://exported_obstacles.json"
	var file = FileAccess.open(godot_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	
	# Save to server
	var server_file_path = server_path.path_join("obstacles.json")
	var server_file = FileAccess.open(server_file_path, FileAccess.WRITE)
	if server_file:
		server_file.store_string(json_string)
		server_file.close()
		_append_status("  Saved to server/obstacles.json\n")


func _filter_and_dedupe_obstacles(obstacles: Array) -> Array:
	var result = []
	var seen = {}
	
	for obs in obstacles:
		if obs.is_empty():
			continue
		
		if obs.type == "box":
			if obs.half_width > MAX_OBSTACLE_SIZE or obs.half_depth > MAX_OBSTACLE_SIZE:
				continue
			if obs.half_width < MIN_OBSTACLE_SIZE and obs.half_depth < MIN_OBSTACLE_SIZE:
				continue
		elif obs.type == "circle":
			if obs.radius > MAX_OBSTACLE_SIZE or obs.radius < MIN_OBSTACLE_SIZE:
				continue
		
		var key = "%s_%.1f_%.1f" % [obs.type, obs.center_x, obs.center_z]
		if not seen.has(key):
			seen[key] = true
			result.append(obs)
	
	return result


func _extract_obstacles(node: Node, parent_transform: Transform3D, depth: int = 0) -> Array:
	var obstacles = []
	
	var global_transform = parent_transform
	if node is Node3D:
		global_transform = parent_transform * node.transform
	
	if node is StaticBody3D:
		var node_name = node.name.to_lower()
		if not ("ground" in node_name or "floor" in node_name):
			for child in node.get_children():
				if child is CollisionShape3D and child.shape != null:
					var shape_transform = global_transform * child.transform
					var obstacle = _extract_shape(child.shape, shape_transform)
					if obstacle != null:
						obstacles.append(obstacle)
	
	if node is CSGShape3D and node.use_collision:
		var obstacle = _extract_csg_shape(node, global_transform)
		if obstacle != null:
			obstacles.append(obstacle)
	
	for child in node.get_children():
		obstacles.append_array(_extract_obstacles(child, global_transform, depth + 1))
	
	return obstacles


func _extract_shape(shape: Shape3D, transform: Transform3D) -> Variant:
	var pos = transform.origin
	var scale = transform.basis.get_scale()
	
	if shape is BoxShape3D:
		var half_extents = shape.size * 0.5 * scale
		return {
			"type": "box",
			"center_x": pos.x,
			"center_z": pos.z,
			"half_width": abs(half_extents.x),
			"half_depth": abs(half_extents.z),
		}
	elif shape is CylinderShape3D:
		return {
			"type": "circle",
			"center_x": pos.x,
			"center_z": pos.z,
			"radius": shape.radius * max(abs(scale.x), abs(scale.z)),
		}
	elif shape is SphereShape3D:
		return {
			"type": "circle",
			"center_x": pos.x,
			"center_z": pos.z,
			"radius": shape.radius * max(abs(scale.x), abs(scale.z)),
		}
	elif shape is CapsuleShape3D:
		return {
			"type": "circle",
			"center_x": pos.x,
			"center_z": pos.z,
			"radius": shape.radius * max(abs(scale.x), abs(scale.z)),
		}
	elif shape is ConcavePolygonShape3D:
		var faces = shape.get_faces()
		if faces.size() == 0:
			return null
		var min_x = INF
		var max_x = -INF
		var min_z = INF
		var max_z = -INF
		for vertex in faces:
			var scaled_vertex = vertex * scale
			min_x = min(min_x, scaled_vertex.x)
			max_x = max(max_x, scaled_vertex.x)
			min_z = min(min_z, scaled_vertex.z)
			max_z = max(max_z, scaled_vertex.z)
		return {
			"type": "box",
			"center_x": pos.x + (min_x + max_x) * 0.5,
			"center_z": pos.z + (min_z + max_z) * 0.5,
			"half_width": abs((max_x - min_x) * 0.5),
			"half_depth": abs((max_z - min_z) * 0.5),
		}
	elif shape is ConvexPolygonShape3D:
		var points = shape.points
		if points.size() == 0:
			return null
		var min_x = INF
		var max_x = -INF
		var min_z = INF
		var max_z = -INF
		for point in points:
			var scaled_point = point * scale
			min_x = min(min_x, scaled_point.x)
			max_x = max(max_x, scaled_point.x)
			min_z = min(min_z, scaled_point.z)
			max_z = max(max_z, scaled_point.z)
		return {
			"type": "box",
			"center_x": pos.x + (min_x + max_x) * 0.5,
			"center_z": pos.z + (min_z + max_z) * 0.5,
			"half_width": abs((max_x - min_x) * 0.5),
			"half_depth": abs((max_z - min_z) * 0.5),
		}
	
	return null


func _extract_csg_shape(csg: CSGShape3D, transform: Transform3D) -> Variant:
	var pos = transform.origin
	var scale = transform.basis.get_scale()
	
	if csg is CSGBox3D:
		var half_extents = csg.size * 0.5 * scale
		return {
			"type": "box",
			"center_x": pos.x,
			"center_z": pos.z,
			"half_width": abs(half_extents.x),
			"half_depth": abs(half_extents.z),
		}
	elif csg is CSGCylinder3D:
		return {
			"type": "circle",
			"center_x": pos.x,
			"center_z": pos.z,
			"radius": csg.radius * max(abs(scale.x), abs(scale.z)),
		}
	elif csg is CSGSphere3D:
		return {
			"type": "circle",
			"center_x": pos.x,
			"center_z": pos.z,
			"radius": csg.radius * max(abs(scale.x), abs(scale.z)),
		}
	
	return null
#endregion


#region Spawn Areas Export
func _export_spawn_areas(server_path: String, zones: Array) -> void:
	var all_zones = {}
	
	for zone_id in zones:
		var config = ZONE_CONFIG[zone_id]
		var scene_path: String = config.scene
		
		_append_status("  Zone %d... " % zone_id)
		
		var scene = load(scene_path)
		if scene == null:
			_append_status("[color=red]not found[/color]\n")
			continue
		
		var root = scene.instantiate()
		var spawn_areas = _extract_spawn_areas(root)
		root.queue_free()
		
		all_zones[str(zone_id)] = spawn_areas
		_append_status("[color=lime]%d area(s)[/color]\n" % spawn_areas.size())
	
	# Save to JSON
	var json_string = JSON.stringify(all_zones, "  ")
	
	# Save to godot project
	var godot_path = "res://exported_spawn_areas.json"
	var file = FileAccess.open(godot_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	
	# Save to server
	var server_file_path = server_path.path_join("spawn_areas.json")
	var server_file = FileAccess.open(server_file_path, FileAccess.WRITE)
	if server_file:
		server_file.store_string(json_string)
		server_file.close()
		_append_status("  Saved to server/spawn_areas.json\n")


func _extract_spawn_areas(node: Node) -> Array:
	var spawn_areas = []
	
	# Check if this node is a SpawnArea3D
	if node.get_script() != null:
		var script_path = node.get_script().resource_path if node.get_script() else ""
		if "spawn_area_3d" in script_path.to_lower() or node.get_class() == "SpawnArea3D":
			# This is a SpawnArea3D node
			if node.has_method("to_dict"):
				var area_data = node.to_dict()
				if not area_data.polygon.is_empty():
					spawn_areas.append(area_data)
	
	# Also check by class name for custom types
	if node is Node3D and node.has_method("to_dict"):
		# Check if it has SpawnArea3D properties
		if "polygon" in node and "enemy_configs" in node:
			var area_data = node.to_dict()
			if not area_data.polygon.is_empty():
				# Avoid duplicates
				var dominated = false
				for existing in spawn_areas:
					if existing.id == area_data.id:
						dominated = true
						break
				if not dominated:
					spawn_areas.append(area_data)
	
	# Recursively search children
	for child in node.get_children():
		spawn_areas.append_array(_extract_spawn_areas(child))
	
	return spawn_areas
#endregion
