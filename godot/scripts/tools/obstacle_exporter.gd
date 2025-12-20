@tool
extends EditorScript
## Obstacle Exporter Tool
##
## This tool exports all collision shapes from zone scenes to a JSON file
## that the server can load for enemy pathfinding.
##
## Usage: Open this script in the Godot editor and run it via Script > Run (Ctrl+Shift+X)

const OUTPUT_PATH = "res://exported_obstacles.json"

# Zone scenes to export
const ZONE_SCENES = {
	1: "res://scenes/world/shinsoo/village.tscn",
	100: "res://scenes/world/chunjo/village.tscn",
	200: "res://scenes/world/jinno/village.tscn",
}

# Maximum size for an obstacle (to filter out ground planes)
const MAX_OBSTACLE_SIZE = 50.0

# Minimum size for an obstacle (to filter out tiny decorations)
const MIN_OBSTACLE_SIZE = 0.3

func _run() -> void:
	print("=== Obstacle Exporter ===")
	
	var all_zones = {}
	
	for zone_id in ZONE_SCENES:
		var scene_path = ZONE_SCENES[zone_id]
		print("Processing zone %d: %s" % [zone_id, scene_path])
		
		var scene = load(scene_path)
		if scene == null:
			push_error("Failed to load scene: %s" % scene_path)
			continue
		
		var root = scene.instantiate()
		var raw_obstacles = extract_obstacles(root, Transform3D.IDENTITY)
		root.queue_free()
		
		# Filter and deduplicate obstacles
		var obstacles = filter_and_dedupe(raw_obstacles)
		
		all_zones[str(zone_id)] = obstacles
		print("  Found %d obstacles (after filtering)" % obstacles.size())
	
	# Save to JSON
	var json_string = JSON.stringify(all_zones, "  ")
	var file = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Exported to: %s" % OUTPUT_PATH)
	else:
		push_error("Failed to write file: %s" % OUTPUT_PATH)
	
	# Also save to server directory
	var abs_path = ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir() + "/server/obstacles.json"
	var server_file = FileAccess.open(abs_path, FileAccess.WRITE)
	if server_file:
		server_file.store_string(json_string)
		server_file.close()
		print("Exported to server: %s" % abs_path)
	else:
		push_warning("Could not write to server path: %s" % abs_path)
	
	print("=== Export Complete ===")


func filter_and_dedupe(obstacles: Array) -> Array:
	var result = []
	var seen = {}  # Key: "type_x_z" -> true
	
	for obs in obstacles:
		# Skip empty obstacles
		if obs.is_empty():
			continue
		
		# Skip obstacles that are too large (ground planes)
		if obs.type == "box":
			if obs.half_width > MAX_OBSTACLE_SIZE or obs.half_depth > MAX_OBSTACLE_SIZE:
				continue
			# Skip obstacles that are too small
			if obs.half_width < MIN_OBSTACLE_SIZE and obs.half_depth < MIN_OBSTACLE_SIZE:
				continue
		elif obs.type == "circle":
			if obs.radius > MAX_OBSTACLE_SIZE:
				continue
			if obs.radius < MIN_OBSTACLE_SIZE:
				continue
		
		# Create a key for deduplication (round to 1 decimal place)
		var key = "%s_%.1f_%.1f" % [obs.type, obs.center_x, obs.center_z]
		
		if not seen.has(key):
			seen[key] = true
			result.append(obs)
	
	return result


func extract_obstacles(node: Node, parent_transform: Transform3D, depth: int = 0) -> Array:
	var obstacles = []
	var indent = "  ".repeat(depth)
	
	# Calculate this node's global transform
	var global_transform = parent_transform
	if node is Node3D:
		global_transform = parent_transform * node.transform
	
	# Debug: show what we're traversing (only for first few levels)
	if depth <= 3:
		var node_type = node.get_class()
		var child_count = node.get_child_count()
		if node is StaticBody3D or "fence" in node.name.to_lower() or "Fence" in node.name:
			print("%s[%s] %s (%d children)" % [indent, node_type, node.name, child_count])
	
	# Check if this is a StaticBody3D (collision object)
	# Skip if it's named "GroundCollision" or similar
	if node is StaticBody3D:
		var node_name = node.name.to_lower()
		if not ("ground" in node_name or "floor" in node_name):
			# Look for CollisionShape3D children
			for child in node.get_children():
				if child is CollisionShape3D:
					if child.shape != null:
						var shape_transform = global_transform * child.transform
						var obstacle = extract_shape(child.shape, shape_transform)
						if obstacle != null:
							print("%s  -> Found: %s at (%.1f, %.1f) size: %.1fx%.1f" % [
								indent, child.shape.get_class(), 
								obstacle.center_x, obstacle.center_z,
								obstacle.get("half_width", obstacle.get("radius", 0)) * 2,
								obstacle.get("half_depth", obstacle.get("radius", 0)) * 2])
							obstacles.append(obstacle)
						else:
							print("%s  -> Shape %s returned null" % [indent, child.shape.get_class()])
					else:
						print("%s  -> CollisionShape3D has null shape!" % indent)
	
	# Also check for CSG shapes with collision enabled
	if node is CSGShape3D and node.use_collision:
		var obstacle = extract_csg_shape(node, global_transform)
		if obstacle != null:
			obstacles.append(obstacle)
	
	# Recursively process children
	for child in node.get_children():
		obstacles.append_array(extract_obstacles(child, global_transform, depth + 1))
	
	return obstacles


func extract_shape(shape: Shape3D, transform: Transform3D) -> Variant:
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
		# Treat capsule as a circle with the larger dimension
		return {
			"type": "circle",
			"center_x": pos.x,
			"center_z": pos.z,
			"radius": shape.radius * max(abs(scale.x), abs(scale.z)),
		}
	
	elif shape is ConcavePolygonShape3D:
		# Trimesh shape - compute bounding box from vertices
		var faces = shape.get_faces()
		if faces.size() == 0:
			return null
		
		var min_x = INF
		var max_x = -INF
		var min_z = INF
		var max_z = -INF
		
		for vertex in faces:
			# Apply scale to vertex
			var scaled_vertex = vertex * scale
			min_x = min(min_x, scaled_vertex.x)
			max_x = max(max_x, scaled_vertex.x)
			min_z = min(min_z, scaled_vertex.z)
			max_z = max(max_z, scaled_vertex.z)
		
		var half_width = (max_x - min_x) * 0.5
		var half_depth = (max_z - min_z) * 0.5
		var center_x = pos.x + (min_x + max_x) * 0.5
		var center_z = pos.z + (min_z + max_z) * 0.5
		
		return {
			"type": "box",
			"center_x": center_x,
			"center_z": center_z,
			"half_width": abs(half_width),
			"half_depth": abs(half_depth),
		}
	
	elif shape is ConvexPolygonShape3D:
		# Convex hull shape - compute bounding box from points
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
		
		var half_width = (max_x - min_x) * 0.5
		var half_depth = (max_z - min_z) * 0.5
		var center_x = pos.x + (min_x + max_x) * 0.5
		var center_z = pos.z + (min_z + max_z) * 0.5
		
		return {
			"type": "box",
			"center_x": center_x,
			"center_z": center_z,
			"half_width": abs(half_width),
			"half_depth": abs(half_depth),
		}
	
	# Unsupported shape - log it
	print("    [WARN] Unsupported shape type: %s" % shape.get_class())
	return null


func extract_csg_shape(csg: CSGShape3D, transform: Transform3D) -> Variant:
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
