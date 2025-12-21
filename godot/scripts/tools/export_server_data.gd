@tool
extends EditorScript
## Server Data Exporter
##
## This comprehensive tool exports all data the server needs:
##   1. Generates terrain for all empires
##   2. Copies heightmaps to server/heightmaps/
##   3. Exports spawn points to server/spawn_points.json
##   4. Exports obstacles to server/obstacles.json
##
## Right-click this file in the FileSystem dock and select "Run" to execute.
##
## NOTE: You may see "Resource file not found: res://" errors during terrain generation.
## These are benign warnings from the Terrain3D addon and can be safely ignored.


# Zone configuration
const ZONE_SCENES = {
	1: "res://scenes/world/shinsoo/village.tscn",
	100: "res://scenes/world/chunjo/village.tscn",
	200: "res://scenes/world/jinno/village.tscn",
}

const EMPIRES: Array[String] = ["shinsoo", "chunjo", "jinno"]
const TERRAIN_SOURCE_DIR: String = "res://assets/terrain"

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
	
	# Step 1: Generate terrains
	_generate_terrains()
	
	# Step 2: Copy heightmaps to server
	_copy_heightmaps_to_server(server_path)
	
	# Step 3: Export spawn points
	_export_spawn_points(server_path)
	
	# Step 4: Export obstacles
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


#region Terrain Generation
func _generate_terrains() -> void:
	print("")
	print("==============================================")
	print("       Step 1: Generating Terrains")
	print("==============================================")
	print("")
	
	for empire_idx in range(3):
		var empire_name: String = ""
		match empire_idx:
			0: empire_name = "Shinsoo"
			1: empire_name = "Chunjo"
			2: empire_name = "Jinno"
		
		print("----------------------------------------")
		print("Generating ", empire_name, " terrain...")
		print("----------------------------------------")
		
		var generator: TerrainGenerator = TerrainGenerator.new()
		generator.empire = empire_idx
		generator.output_directory = "res://assets/terrain"
		
		# Add to edited scene root so it can work
		var scene_root := get_scene()
		if scene_root:
			scene_root.add_child(generator)
		else:
			get_editor_interface().get_base_control().add_child(generator)
		
		generator.generate_and_save()
		generator.queue_free()
		print("")
	
	print("Terrain generation complete!")
	print("")
#endregion


#region Heightmap Copy
func _copy_heightmaps_to_server(server_path: String) -> void:
	print("")
	print("==============================================")
	print("       Step 2: Copying Heightmaps")
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
	
	var success_count: int = 0
	var expected_count: int = EMPIRES.size() * 2
	
	for empire in EMPIRES:
		# Copy JSON file
		var json_source := TERRAIN_SOURCE_DIR + "/" + empire + "_heightmap.json"
		var json_target := heightmaps_path.path_join(empire + "_heightmap.json")
		if _copy_file(json_source, json_target):
			success_count += 1
		
		# Copy BIN file
		var bin_source := TERRAIN_SOURCE_DIR + "/" + empire + "_heightmap.bin"
		var bin_target := heightmaps_path.path_join(empire + "_heightmap.bin")
		if _copy_file(bin_source, bin_target):
			success_count += 1
	
	print("")
	if success_count == expected_count:
		print("All heightmaps copied successfully!")
	else:
		print("Copied ", success_count, "/", expected_count, " heightmap files")
	print("")
#endregion


#region Spawn Points Export
func _export_spawn_points(server_path: String) -> void:
	print("")
	print("==============================================")
	print("       Step 3: Exporting Spawn Points")
	print("==============================================")
	print("")
	
	var all_zones = {}
	
	for zone_id in ZONE_SCENES:
		var scene_path = ZONE_SCENES[zone_id]
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
	print("       Step 4: Exporting Obstacles")
	print("==============================================")
	print("")
	
	var all_zones = {}
	
	for zone_id in ZONE_SCENES:
		var scene_path = ZONE_SCENES[zone_id]
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


#region Utility Functions
func _copy_file(source_path: String, target_path: String) -> bool:
	if not FileAccess.file_exists(source_path):
		push_error("Source file not found: ", source_path)
		print("  [SKIP] ", source_path.get_file(), " (not found)")
		return false
	
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		push_error("Failed to open source: ", source_path)
		print("  [FAIL] ", source_path.get_file(), " (read error)")
		return false
	
	var content := source_file.get_buffer(source_file.get_length())
	source_file.close()
	
	var target_file := FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		push_error("Failed to open target: ", target_path)
		print("  [FAIL] ", target_path.get_file(), " (write error)")
		return false
	
	target_file.store_buffer(content)
	target_file.close()
	
	print("  [OK] ", source_path.get_file(), " -> ", target_path.get_file())
	return true
#endregion
