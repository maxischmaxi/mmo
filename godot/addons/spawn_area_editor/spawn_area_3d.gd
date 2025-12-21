@tool
class_name SpawnArea3D
extends Node3D
## A spawn area that defines where enemies can spawn.
##
## The area is defined by a polygon (list of XZ vertices) drawn on the ground.
## Enemies will spawn randomly within this polygon based on the configured
## enemy types, weights, and population limits.

## Unique identifier for this spawn area (used in export)
@export var area_id: String = "":
	set(value):
		area_id = value
		update_gizmos()

## The polygon vertices defining the spawn area (XZ coordinates, Y is ignored)
## Edit these in the 3D viewport using the gizmo handles
@export var polygon: PackedVector2Array = PackedVector2Array():
	set(value):
		polygon = value
		update_gizmos()
		_update_debug_mesh()

## List of enemy configurations that can spawn in this area
@export var enemy_configs: Array[SpawnAreaEnemyConfig] = []

## Maximum number of enemies alive at once in this area
@export_range(1, 50) var max_population: int = 5

## Time in seconds before a dead enemy respawns
@export_range(1.0, 600.0, 1.0) var respawn_time: float = 60.0

## Minimum distance between spawned enemies
@export_range(1.0, 20.0, 0.5) var min_spawn_distance: float = 2.0

## Color for the spawn area visualization
@export var area_color: Color = Color(0.2, 0.8, 0.2, 0.3):
	set(value):
		area_color = value
		_update_debug_mesh()

## Show the area visualization in-game (for debugging)
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		_update_debug_mesh()

# Debug mesh for visualization
var _debug_mesh_instance: MeshInstance3D = null


func _ready() -> void:
	if Engine.is_editor_hint() or show_in_game:
		_update_debug_mesh()


func _enter_tree() -> void:
	# Generate a default area_id if empty
	if area_id.is_empty():
		area_id = "spawn_area_%d" % get_instance_id()


func _exit_tree() -> void:
	if _debug_mesh_instance:
		_debug_mesh_instance.queue_free()
		_debug_mesh_instance = null


## Create a default rectangular polygon
func create_default_polygon(size: float = 10.0) -> void:
	var half := size / 2.0
	polygon = PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])


## Add a vertex at the given position (in local XZ space)
func add_vertex(pos: Vector2, index: int = -1) -> void:
	var new_polygon := Array(polygon)
	if index < 0 or index >= new_polygon.size():
		new_polygon.append(pos)
	else:
		new_polygon.insert(index, pos)
	polygon = PackedVector2Array(new_polygon)


## Remove a vertex by index
func remove_vertex(index: int) -> void:
	if index >= 0 and index < polygon.size() and polygon.size() > 3:
		var new_polygon := Array(polygon)
		new_polygon.remove_at(index)
		polygon = PackedVector2Array(new_polygon)


## Move a vertex to a new position
func set_vertex(index: int, pos: Vector2) -> void:
	if index >= 0 and index < polygon.size():
		polygon[index] = pos
		update_gizmos()
		_update_debug_mesh()


## Get the center point of the polygon
func get_center() -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	
	var center := Vector2.ZERO
	for vertex in polygon:
		center += vertex
	return center / polygon.size()


## Check if a point is inside the polygon (XZ coordinates)
func contains_point(point: Vector2) -> bool:
	if polygon.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, polygon)


## Get a random point inside the polygon
func get_random_point() -> Vector2:
	if polygon.size() < 3:
		return Vector2.ZERO
	
	# Use rejection sampling with bounding box
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	
	for vertex in polygon:
		min_pt.x = min(min_pt.x, vertex.x)
		min_pt.y = min(min_pt.y, vertex.y)
		max_pt.x = max(max_pt.x, vertex.x)
		max_pt.y = max(max_pt.y, vertex.y)
	
	# Try up to 100 times to find a valid point
	for _i in range(100):
		var test_point := Vector2(
			randf_range(min_pt.x, max_pt.x),
			randf_range(min_pt.y, max_pt.y)
		)
		if contains_point(test_point):
			return test_point
	
	# Fallback to center
	return get_center()


## Calculate the area of the polygon
func get_area() -> float:
	if polygon.size() < 3:
		return 0.0
	
	var area := 0.0
	var j := polygon.size() - 1
	
	for i in range(polygon.size()):
		area += (polygon[j].x + polygon[i].x) * (polygon[j].y - polygon[i].y)
		j = i
	
	return abs(area) / 2.0


## Export the spawn area data as a dictionary (for JSON export)
func to_dict() -> Dictionary:
	var configs := []
	for config in enemy_configs:
		if config:
			configs.append({
				"enemy_type": config.get_enemy_type_string(),
				"weight": config.spawn_weight,
				"min_level": config.min_level,
				"max_level": config.max_level,
			})
	
	# Convert polygon vertices to global coordinates
	# Use position if not in tree (global_position requires being in tree)
	var global_vertices := []
	var global_pos: Vector3
	if is_inside_tree():
		global_pos = global_position
	else:
		global_pos = position
	
	for vertex in polygon:
		global_vertices.append([
			global_pos.x + vertex.x,
			global_pos.z + vertex.y,  # Note: Vector2.y -> world Z
		])
	
	return {
		"id": area_id,
		"polygon": global_vertices,
		"enemy_configs": configs,
		"max_population": max_population,
		"respawn_time_secs": respawn_time,
		"min_spawn_distance": min_spawn_distance,
	}


## Update the debug mesh visualization
func _update_debug_mesh() -> void:
	# Only show in editor or if explicitly enabled
	if not Engine.is_editor_hint() and not show_in_game:
		if _debug_mesh_instance:
			_debug_mesh_instance.visible = false
		return
	
	if polygon.size() < 3:
		if _debug_mesh_instance:
			_debug_mesh_instance.visible = false
		return
	
	# Create mesh instance if needed
	if not _debug_mesh_instance:
		_debug_mesh_instance = MeshInstance3D.new()
		_debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_mesh_instance)
	
	_debug_mesh_instance.visible = true
	
	# Create the mesh
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Triangulate the polygon
	var indices := Geometry2D.triangulate_polygon(polygon)
	
	for i in range(0, indices.size(), 3):
		var v0 := polygon[indices[i]]
		var v1 := polygon[indices[i + 1]]
		var v2 := polygon[indices[i + 2]]
		
		mesh.surface_set_color(area_color)
		mesh.surface_add_vertex(Vector3(v0.x, 0.1, v0.y))  # Slightly above ground
		mesh.surface_add_vertex(Vector3(v1.x, 0.1, v1.y))
		mesh.surface_add_vertex(Vector3(v2.x, 0.1, v2.y))
	
	mesh.surface_end()
	
	_debug_mesh_instance.mesh = mesh
	
	# Create material
	var material := StandardMaterial3D.new()
	material.albedo_color = area_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debug_mesh_instance.material_override = material
