@tool
extends EditorScript
## Server Data Exporter
##
## This tool exports all data the server needs:
##   1. Exports heightmaps from Terrain3D objects in village scenes
##   2. Exports spawn points to server/spawn_points.json
##   3. Exports obstacles to server/obstacles.json
##
## Right-click this file in the FileSystem dock and select "Run" to execute.


# Zone configuration - maps zone_id to scene path and empire name
const ZONE_CONFIG = {
	1: {"scene": "res://scenes/world/shinsoo/village.tscn", "empire": "shinsoo"},
	100: {"scene": "res://scenes/world/chunjo/village.tscn", "empire": "chunjo"},
	200: {"scene": "res://scenes/world/jinno/village.tscn", "empire": "jinno"},
}

# Heightmap export resolution (samples per axis)
# Higher = more accurate but larger files
const HEIGHTMAP_RESOLUTION: int = 512

# Obstacle filtering
const MAX_OBSTACLE_SIZE = 50.0
const MIN_OBSTACLE_SIZE = 0.3


func _run() -> void:
	print("")
	print("##############################################")
	print("#       MMO Server Data Exporter            #")
	print("##############################################")
	print("")
	
	var project_path: String = ProjectSettings.globalize_path("res://")
	var server_path: String = project_path.path_join("../server")
	
	# Step 1: Export heightmaps from Terrain3D in scenes
	_export_heightmaps(server_path)
	
	# Step 2: Export spawn points
	_export_spawn_points(server_path)
	
	# Step 3: Export obstacles
	_export_obstacles(server_path)
	
	# Summary
	print("")
	print("##############################################")
	print("#       Export Complete!                    #")
	print("##############################################")
	print("")
	print("Server data exported to: ", server_path)
	print("  - heightmaps/*.json, *.bin")
	print("  - spawn_points.json")
	print("  - obstacles.json")
	print("")


#region Heightmap Export
func _export_heightmaps(server_path: String) -> void:
	print("")
	print("==============================================")
	print("       Step 1: Exporting Heightmaps")
	print("==============================================")
	print("")
	
	var heightmaps_path: String = server_path.path_join("heightmaps")
	
	# Ensure target directory exists
	if not DirAccess.dir_exists_absolute(heightmaps_path):
		var err := DirAccess.make_dir_recursive_absolute(heightmaps_path)
		if err != OK:
			push_error("Failed to create directory: ", heightmaps_path)
			return
		print("Created directory: ", heightmaps_path)
	
	for zone_id in ZONE_CONFIG:
		var config = ZONE_CONFIG[zone_id]
		var scene_path: String = config.scene
		var empire_name: String = config.empire
		
		print("----------------------------------------")
		print("Processing ", empire_name, " (zone ", zone_id, ")")
		print("----------------------------------------")
		
		# Load scene
		var scene = load(scene_path)
		if scene == null:
			push_error("Failed to load scene: ", scene_path)
			continue
		
		# Instantiate scene to access Terrain3D
		var root = scene.instantiate()
		if root == null:
			push_error("Failed to instantiate scene: ", scene_path)
			continue
		
		# Find Terrain3D node
		var terrain: Terrain3D = _find_terrain3d(root)
		if terrain == null:
			push_warning("No Terrain3D found in ", scene_path)
			root.queue_free()
			continue
		
		print("  Found Terrain3D node: ", terrain.name)
		print("  Data directory: ", terrain.data_directory)
		
		# Check if terrain has data
		if terrain.data == null:
			print("  WARNING: Terrain3D.data is null, trying to load data...")
			# The data might need to be loaded from the data_directory
			# Let's try to access it directly
		
		# For Terrain3D, the data is loaded from data_directory
		# We need to check if the data_directory has actual terrain data
		var data_dir: String = terrain.data_directory
		if data_dir.is_empty():
			push_error("  Terrain3D has no data_directory set")
			root.queue_free()
			continue
		
		# Check if data directory exists and has .res files
		var dir := DirAccess.open(data_dir)
		if dir == null:
			push_error("  Cannot open data_directory: ", data_dir)
			# Try globalizing the path
			var global_data_dir := ProjectSettings.globalize_path(data_dir)
			print("  Trying global path: ", global_data_dir)
			dir = DirAccess.open(global_data_dir)
			if dir == null:
				push_error("  Cannot open global data_directory either")
				root.queue_free()
				continue
		
		# List .res files to confirm terrain data exists
		var res_files: Array[String] = []
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".res"):
				res_files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		
		print("  Found ", res_files.size(), " terrain region files in ", data_dir)
		
		if res_files.is_empty():
			push_error("  No terrain data files found in ", data_dir)
			root.queue_free()
			continue
		
		# Export heightmap by reading the Terrain3D data directly
		# Since we can't easily access terrain.data without adding to tree,
		# we'll load the terrain data manually
		var success := _export_terrain_heightmap_from_directory(data_dir, empire_name, heightmaps_path)
		
		# Cleanup
		root.queue_free()
		
		if success:
			print("  [OK] Heightmap exported for ", empire_name)
		else:
			print("  [FAIL] Failed to export heightmap for ", empire_name)
		print("")
	
	print("Heightmap export complete!")
	print("")


func _find_terrain3d(node: Node) -> Terrain3D:
	if node is Terrain3D:
		return node
	
	for child in node.get_children():
		var result = _find_terrain3d(child)
		if result != null:
			return result
	
	return null


## Parse terrain region coordinates from filename part like "00_01", "-01_00", "01-01"
## Returns PackedStringArray with [x_coord, z_coord] as strings
func _parse_terrain_coords(coords_part: String) -> PackedStringArray:
	# Terrain3D region filenames follow these patterns:
	#   "00_01"   -> x=0,  z=1
	#   "-01_00"  -> x=-1, z=0
	#   "01_-01"  -> x=1,  z=-1
	#   "-01_-01" -> x=-1, z=-1
	
	var result := PackedStringArray()
	
	# Try splitting by underscore first (handles most cases)
	var parts := coords_part.split("_")
	
	if parts.size() == 2:
		# Simple case: "00_01" or "-01_00"
		result.append(parts[0])
		result.append(parts[1])
	elif parts.size() == 3 and parts[0] == "":
		# Case: "_01_00" which split from "-01_00" incorrectly? 
		# Actually split("-") on "-01_00" gives ["", "01_00"]
		# Let's handle the underscore split properly
		# "-01_00".split("_") gives ["-01", "00"] - this should work
		# "-01_-01".split("_") gives ["-01", "-01"] - this should work too
		pass
	
	# If we didn't get 2 parts, the simple split worked or we need more parsing
	if result.size() != 2 and parts.size() >= 2:
		result.append(parts[0])
		result.append(parts[1])
	
	# Validate we have exactly 2 coordinates
	if result.size() != 2:
		push_warning("Could not parse terrain coordinates from: ", coords_part)
		return PackedStringArray()
	
	return result


func _export_terrain_heightmap_from_directory(data_dir: String, empire_name: String, output_dir: String) -> bool:
	# Create a temporary Terrain3D to load and query the data
	var terrain := Terrain3D.new()
	terrain.data_directory = data_dir
	
	# Add to scene tree temporarily so it can initialize
	var parent: Node = get_editor_interface().get_base_control()
	parent.add_child(terrain)
	
	# Force the terrain to load its data
	# Terrain3D loads data when added to tree if data_directory is set
	
	# Check if data loaded
	if terrain.data == null:
		push_error("  Failed to load terrain data from ", data_dir)
		terrain.queue_free()
		return false
	
	# Get terrain bounds by parsing the .res filenames
	# Filenames follow pattern: terrain3d_XX_YY.res where XX and YY are region coordinates
	# Negative coordinates use format: terrain3d_-XX_YY.res or terrain3d_XX-YY.res
	var region_size: int = terrain.region_size  # Usually 256
	print("  Region size: ", region_size)
	
	# Parse region coordinates from filenames
	var dir := DirAccess.open(data_dir)
	if dir == null:
		push_error("  Cannot open data directory: ", data_dir)
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
			# Parse coordinates from filename like "terrain3d_00_01.res" or "terrain3d_-01_00.res"
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
	
	print("  Parsed ", region_count, " region coordinates")
	
	if region_count == 0:
		push_error("  No valid region files found")
		terrain.queue_free()
		return false
	
	print("  Region bounds: X[", min_rx, " to ", max_rx, "] Z[", min_rz, " to ", max_rz, "]")
	
	# Convert region coordinates to world coordinates
	# Region (0,0) covers world coordinates (0,0) to (region_size, region_size)
	# Region (-1,-1) covers world coordinates (-region_size, -region_size) to (0, 0)
	var min_x: float = float(min_rx) * region_size
	var max_x: float = float(max_rx + 1) * region_size
	var min_z: float = float(min_rz) * region_size
	var max_z: float = float(max_rz + 1) * region_size
	
	var terrain_size_x: float = max_x - min_x
	var terrain_size_z: float = max_z - min_z
	var terrain_size: float = maxf(terrain_size_x, terrain_size_z)
	
	print("  Terrain bounds: X[", min_x, " to ", max_x, "] Z[", min_z, " to ", max_z, "]")
	print("  Terrain size: ", terrain_size_x, " x ", terrain_size_z)
	
	# Use appropriate resolution based on terrain size
	var resolution: int = HEIGHTMAP_RESOLUTION
	if terrain_size > 1024:
		resolution = 1024
	
	print("  Exporting ", resolution, "x", resolution, " heightmap...")
	
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
		push_error("  Failed to open JSON file: ", json_path)
		terrain.queue_free()
		return false
	
	json_file.store_string(JSON.stringify(metadata, "  "))
	json_file.close()
	print("  Saved metadata to: ", json_path)
	
	# Sample and export height data
	var bin_path: String = output_dir.path_join(empire_name + "_heightmap.bin")
	var bin_file := FileAccess.open(bin_path, FileAccess.WRITE)
	if bin_file == null:
		push_error("  Failed to open binary file: ", bin_path)
		terrain.queue_free()
		return false
	
	var step_x: float = terrain_size_x / float(resolution)
	var step_z: float = terrain_size_z / float(resolution)
	
	var total_points: int = resolution * resolution
	var points_done: int = 0
	var last_progress: int = -1
	var nan_count: int = 0
	
	for z_idx in range(resolution):
		var world_z: float = min_z + (float(z_idx) + 0.5) * step_z
		
		for x_idx in range(resolution):
			var world_x: float = min_x + (float(x_idx) + 0.5) * step_x
			
			var height: float = terrain.data.get_height(Vector3(world_x, 0, world_z))
			
			# Handle NaN (outside terrain bounds)
			if is_nan(height):
				height = 0.0
				nan_count += 1
			
			bin_file.store_float(height)
			points_done += 1
		
		# Progress reporting every 20%
		var progress: int = (points_done * 100) / total_points
		if progress >= last_progress + 20:
			last_progress = progress
			print("  Progress: ", progress, "%")
	
	bin_file.close()
	
	var file_size: int = resolution * resolution * 4
	print("  Saved binary to: ", bin_path, " (", file_size / 1024, " KB)")
	if nan_count > 0:
		print("  Warning: ", nan_count, " points had NaN heights (set to 0)")
	
	# Sample a few heights for verification (before freeing terrain)
	print("  Sample heights:")
	var center_x: float = (min_x + max_x) / 2.0
	var center_z: float = (min_z + max_z) / 2.0
	var h_center: float = terrain.data.get_height(Vector3(center_x, 0, center_z))
	var h_origin: float = terrain.data.get_height(Vector3(0, 0, 0))
	var h_min: float = terrain.data.get_height(Vector3(min_x + 1, 0, min_z + 1))
	print("    Center (", center_x, ", ", center_z, "): ", h_center)
	print("    Origin (0, 0): ", h_origin)
	print("    Near min (", min_x + 1, ", ", min_z + 1, "): ", h_min)
	
	# Cleanup terrain node
	terrain.queue_free()
	
	return true
#endregion


#region Spawn Points Export
func _export_spawn_points(server_path: String) -> void:
	print("")
	print("==============================================")
	print("       Step 2: Exporting Spawn Points")
	print("==============================================")
	print("")
	
	var all_zones = {}
	
	for zone_id in ZONE_CONFIG:
		var config = ZONE_CONFIG[zone_id]
		var scene_path: String = config.scene
		print("Processing zone %d: %s" % [zone_id, scene_path])
		
		var scene = load(scene_path)
		if scene == null:
			push_error("Failed to load scene: %s" % scene_path)
			continue
		
		var root = scene.instantiate()
		var spawn_points = _extract_spawn_points(root, Transform3D.IDENTITY)
		root.queue_free()
		
		if spawn_points.is_empty():
			push_warning("No spawn points found in zone %d" % zone_id)
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
		print("  Found %d spawn point(s)" % spawn_points.size())
		for sp in spawn_points:
			var default_str = " (default)" if sp.get("is_default", false) else ""
			print("    - %s: (%.2f, %.2f, %.2f)%s" % [sp.name, sp.x, sp.y, sp.z, default_str])
	
	# Save to JSON
	var json_string = JSON.stringify(all_zones, "  ")
	
	# Save to godot project
	var godot_path = "res://exported_spawn_points.json"
	var file = FileAccess.open(godot_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Exported to: %s" % godot_path)
	
	# Save to server
	var server_file_path = server_path.path_join("spawn_points.json")
	var server_file = FileAccess.open(server_file_path, FileAccess.WRITE)
	if server_file:
		server_file.store_string(json_string)
		server_file.close()
		print("Exported to: %s" % server_file_path)
	else:
		push_warning("Could not write to: %s" % server_file_path)
	
	print("")


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
func _export_obstacles(server_path: String) -> void:
	print("")
	print("==============================================")
	print("       Step 3: Exporting Obstacles")
	print("==============================================")
	print("")
	
	var all_zones = {}
	
	for zone_id in ZONE_CONFIG:
		var config = ZONE_CONFIG[zone_id]
		var scene_path: String = config.scene
		print("Processing zone %d: %s" % [zone_id, scene_path])
		
		var scene = load(scene_path)
		if scene == null:
			push_error("Failed to load scene: %s" % scene_path)
			continue
		
		var root = scene.instantiate()
		var raw_obstacles = _extract_obstacles(root, Transform3D.IDENTITY)
		root.queue_free()
		
		var obstacles = _filter_and_dedupe_obstacles(raw_obstacles)
		all_zones[str(zone_id)] = obstacles
		print("  Found %d obstacles (after filtering)" % obstacles.size())
	
	# Save to JSON
	var json_string = JSON.stringify(all_zones, "  ")
	
	# Save to godot project
	var godot_path = "res://exported_obstacles.json"
	var file = FileAccess.open(godot_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Exported to: %s" % godot_path)
	
	# Save to server
	var server_file_path = server_path.path_join("obstacles.json")
	var server_file = FileAccess.open(server_file_path, FileAccess.WRITE)
	if server_file:
		server_file.store_string(json_string)
		server_file.close()
		print("Exported to: %s" % server_file_path)
	else:
		push_warning("Could not write to: %s" % server_file_path)
	
	print("")


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
