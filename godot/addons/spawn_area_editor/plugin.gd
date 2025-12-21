@tool
extends EditorPlugin
## Spawn Area Editor Plugin
##
## Provides visual editing tools for SpawnArea3D nodes.
## Allows drawing polygon-based spawn regions on terrain.
##
## Controls:
## - Click and drag vertex handles to move them
## - Double-click on edge to add a new vertex
## - Select vertex and press Delete to remove it
## - Ctrl+Click on ground to add vertex at end

const SpawnArea3DScript := preload("res://addons/spawn_area_editor/spawn_area_3d.gd")
const SpawnAreaGizmo := preload("res://addons/spawn_area_editor/spawn_area_gizmo.gd")

var _gizmo_plugin: SpawnAreaGizmo = null
var _selected_spawn_area: SpawnArea3D = null
var _selected_vertex_index: int = -1


func _enter_tree() -> void:
	# Register the custom node type
	add_custom_type(
		"SpawnArea3D",
		"Node3D",
		SpawnArea3DScript,
		_get_spawn_area_icon()
	)
	
	# Register the gizmo plugin
	_gizmo_plugin = SpawnAreaGizmo.new()
	_gizmo_plugin.set_undo_redo(get_undo_redo())
	add_node_3d_gizmo_plugin(_gizmo_plugin)
	
	# Connect to selection changed
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	# Disconnect from selection
	if get_editor_interface().get_selection().selection_changed.is_connected(_on_selection_changed):
		get_editor_interface().get_selection().selection_changed.disconnect(_on_selection_changed)
	
	# Unregister the gizmo plugin
	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null
	
	# Unregister the custom node type
	remove_custom_type("SpawnArea3D")


func _get_spawn_area_icon() -> Texture2D:
	# Try to load custom icon, fall back to built-in
	if FileAccess.file_exists("res://addons/spawn_area_editor/spawn_area_icon.svg"):
		return load("res://addons/spawn_area_editor/spawn_area_icon.svg")
	# Use a built-in icon as fallback
	return get_editor_interface().get_base_control().get_theme_icon("Area3D", "EditorIcons")


func _on_selection_changed() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	
	_selected_spawn_area = null
	_selected_vertex_index = -1
	
	for node in selected:
		if node is SpawnArea3D:
			_selected_spawn_area = node
			break


func _handles(object: Object) -> bool:
	return object is SpawnArea3D


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not _selected_spawn_area:
		return AFTER_GUI_INPUT_PASS
	
	# Handle keyboard input
	if event is InputEventKey:
		return _handle_key_input(event)
	
	# Handle mouse input
	if event is InputEventMouseButton:
		return _handle_mouse_input(viewport_camera, event)
	
	return AFTER_GUI_INPUT_PASS


func _handle_key_input(event: InputEventKey) -> int:
	if not event.pressed:
		return AFTER_GUI_INPUT_PASS
	
	match event.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			# Delete selected vertex
			if _selected_vertex_index >= 0 and _selected_spawn_area.polygon.size() > 3:
				var undo_redo := get_undo_redo()
				undo_redo.create_action("Delete Spawn Area Vertex")
				undo_redo.add_do_method(_selected_spawn_area, "remove_vertex", _selected_vertex_index)
				undo_redo.add_undo_method(_selected_spawn_area, "add_vertex", 
					_selected_spawn_area.polygon[_selected_vertex_index], _selected_vertex_index)
				undo_redo.commit_action()
				_selected_vertex_index = -1
				return AFTER_GUI_INPUT_STOP
		
		KEY_ESCAPE:
			_selected_vertex_index = -1
			return AFTER_GUI_INPUT_STOP
	
	return AFTER_GUI_INPUT_PASS


func _handle_mouse_input(camera: Camera3D, event: InputEventMouseButton) -> int:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return AFTER_GUI_INPUT_PASS
	
	if not event.pressed:
		return AFTER_GUI_INPUT_PASS
	
	# Ctrl+Click to add vertex
	if event.ctrl_pressed:
		var pos = _get_ground_position(camera, event.position)
		if pos != null:
			# Convert to local space
			var world_pos: Vector3 = pos as Vector3
			var local_pos: Vector3 = _selected_spawn_area.global_transform.affine_inverse() * world_pos
			var vertex_pos := Vector2(local_pos.x, local_pos.z)
			
			var undo_redo := get_undo_redo()
			
			if _selected_spawn_area.polygon.size() < 3:
				# Create initial polygon
				undo_redo.create_action("Create Spawn Area Polygon")
				var new_polygon := PackedVector2Array([
					vertex_pos + Vector2(-5, -5),
					vertex_pos + Vector2(5, -5),
					vertex_pos + Vector2(5, 5),
					vertex_pos + Vector2(-5, 5),
				])
				undo_redo.add_do_property(_selected_spawn_area, "polygon", new_polygon)
				undo_redo.add_undo_property(_selected_spawn_area, "polygon", _selected_spawn_area.polygon)
				undo_redo.commit_action()
			else:
				# Add vertex at the end
				undo_redo.create_action("Add Spawn Area Vertex")
				undo_redo.add_do_method(_selected_spawn_area, "add_vertex", vertex_pos)
				undo_redo.add_undo_method(_selected_spawn_area, "remove_vertex", _selected_spawn_area.polygon.size())
				undo_redo.commit_action()
			
			return AFTER_GUI_INPUT_STOP
	
	# Double-click to add vertex on edge
	if event.double_click:
		var edge_info := _find_closest_edge(camera, event.position)
		if edge_info.edge_index >= 0:
			var pos = _get_ground_position(camera, event.position)
			if pos != null:
				var world_pos: Vector3 = pos as Vector3
				var local_pos: Vector3 = _selected_spawn_area.global_transform.affine_inverse() * world_pos
				var vertex_pos := Vector2(local_pos.x, local_pos.z)
				
				var undo_redo := get_undo_redo()
				undo_redo.create_action("Insert Spawn Area Vertex")
				undo_redo.add_do_method(_selected_spawn_area, "add_vertex", vertex_pos, edge_info.edge_index + 1)
				undo_redo.add_undo_method(_selected_spawn_area, "remove_vertex", edge_info.edge_index + 1)
				undo_redo.commit_action()
				
				return AFTER_GUI_INPUT_STOP
	
	return AFTER_GUI_INPUT_PASS


func _get_ground_position(camera: Camera3D, screen_pos: Vector2) -> Variant:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	
	# Intersect with Y=0 plane (or spawn area's Y)
	var y_level := 0.0
	if _selected_spawn_area:
		y_level = _selected_spawn_area.global_position.y
	
	var plane := Plane(Vector3.UP, y_level)
	var intersection := plane.intersects_ray(ray_origin, ray_dir)
	
	return intersection


func _find_closest_edge(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var result := {"edge_index": -1, "distance": INF}
	
	if not _selected_spawn_area or _selected_spawn_area.polygon.size() < 2:
		return result
	
	var polygon := _selected_spawn_area.polygon
	var global_transform := _selected_spawn_area.global_transform
	
	for i in range(polygon.size()):
		var v0 := polygon[i]
		var v1 := polygon[(i + 1) % polygon.size()]
		
		# Convert to world space
		var world_v0 := global_transform * Vector3(v0.x, 0, v0.y)
		var world_v1 := global_transform * Vector3(v1.x, 0, v1.y)
		
		# Project to screen
		var screen_v0 := camera.unproject_position(world_v0)
		var screen_v1 := camera.unproject_position(world_v1)
		
		# Distance from screen_pos to edge
		var closest := Geometry2D.get_closest_point_to_segment(screen_pos, screen_v0, screen_v1)
		var dist := screen_pos.distance_to(closest)
		
		if dist < result.distance and dist < 20.0:  # 20 pixel threshold
			result.edge_index = i
			result.distance = dist
	
	return result


func _make_visible(visible: bool) -> void:
	if not visible:
		_selected_spawn_area = null
		_selected_vertex_index = -1
