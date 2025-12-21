@tool
class_name SpawnAreaGizmoPlugin
extends EditorNode3DGizmoPlugin
## Gizmo plugin for SpawnArea3D visual editing.
##
## Provides:
## - Polygon outline visualization
## - Draggable vertex handles
## - Click on edge to add new vertex
## - Right-click vertex to delete

const HANDLE_SIZE := 0.15
const EDGE_COLOR := Color(0.2, 0.9, 0.3, 1.0)
const VERTEX_COLOR := Color(1.0, 1.0, 0.0, 1.0)
const SELECTED_VERTEX_COLOR := Color(1.0, 0.5, 0.0, 1.0)
const FILL_COLOR := Color(0.2, 0.8, 0.2, 0.2)

var _undo_redo: EditorUndoRedoManager = null


func _init() -> void:
	create_material("edge", EDGE_COLOR, false, true)
	create_material("fill", FILL_COLOR, false, true)
	create_handle_material("vertex")


func _get_gizmo_name() -> String:
	return "SpawnArea3D"


func _has_gizmo(node: Node3D) -> bool:
	return node is SpawnArea3D


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	return "Vertex %d" % handle_id


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var spawn_area := gizmo.get_node_3d() as SpawnArea3D
	if spawn_area and handle_id < spawn_area.polygon.size():
		return spawn_area.polygon[handle_id]
	return Vector2.ZERO


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var spawn_area := gizmo.get_node_3d() as SpawnArea3D
	if not spawn_area or handle_id >= spawn_area.polygon.size():
		return
	
	# Project screen position to XZ plane at spawn area's Y position
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	
	# Intersect with Y=0 plane in local space
	var plane := Plane(Vector3.UP, 0.0)
	var global_transform := spawn_area.global_transform
	var local_plane := Plane(
		global_transform.basis.inverse() * plane.normal,
		plane.d - global_transform.origin.dot(plane.normal)
	)
	
	# Transform ray to local space
	var local_origin := global_transform.affine_inverse() * ray_origin
	var local_dir := global_transform.basis.inverse() * ray_dir
	
	var intersection := local_plane.intersects_ray(local_origin, local_dir)
	if intersection:
		# Update the vertex position (XZ only)
		var new_pos := Vector2(intersection.x, intersection.z)
		spawn_area.set_vertex(handle_id, new_pos)


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var spawn_area := gizmo.get_node_3d() as SpawnArea3D
	if not spawn_area:
		return
	
	if cancel:
		spawn_area.set_vertex(handle_id, restore)
		return
	
	# Create undo/redo entry
	if _undo_redo:
		_undo_redo.create_action("Move Spawn Area Vertex")
		_undo_redo.add_do_method(spawn_area, "set_vertex", handle_id, spawn_area.polygon[handle_id])
		_undo_redo.add_undo_method(spawn_area, "set_vertex", handle_id, restore)
		_undo_redo.commit_action()


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	
	var spawn_area := gizmo.get_node_3d() as SpawnArea3D
	if not spawn_area:
		return
	
	var polygon := spawn_area.polygon
	if polygon.size() < 3:
		# Show a placeholder when no polygon exists
		_draw_placeholder(gizmo, spawn_area)
		return
	
	# Draw filled polygon
	_draw_filled_polygon(gizmo, polygon)
	
	# Draw polygon edges
	_draw_polygon_edges(gizmo, polygon)
	
	# Draw vertex handles
	_draw_vertex_handles(gizmo, polygon)
	
	# Draw info label (area, population)
	_draw_info(gizmo, spawn_area)


func _draw_placeholder(gizmo: EditorNode3DGizmo, spawn_area: SpawnArea3D) -> void:
	# Draw a small cross to indicate where the spawn area is
	var lines := PackedVector3Array([
		Vector3(-1, 0, 0), Vector3(1, 0, 0),
		Vector3(0, 0, -1), Vector3(0, 0, 1),
	])
	gizmo.add_lines(lines, get_material("edge", gizmo))


func _draw_filled_polygon(gizmo: EditorNode3DGizmo, polygon: PackedVector2Array) -> void:
	# Triangulate and create mesh for filled area
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		return
	
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var mesh_indices := PackedInt32Array()
	
	for i in range(0, indices.size(), 3):
		var v0 := polygon[indices[i]]
		var v1 := polygon[indices[i + 1]]
		var v2 := polygon[indices[i + 2]]
		
		var base_idx := vertices.size()
		vertices.append(Vector3(v0.x, 0.05, v0.y))
		vertices.append(Vector3(v1.x, 0.05, v1.y))
		vertices.append(Vector3(v2.x, 0.05, v2.y))
		
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		
		mesh_indices.append(base_idx)
		mesh_indices.append(base_idx + 1)
		mesh_indices.append(base_idx + 2)
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = mesh_indices
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	gizmo.add_mesh(mesh, get_material("fill", gizmo))


func _draw_polygon_edges(gizmo: EditorNode3DGizmo, polygon: PackedVector2Array) -> void:
	var lines := PackedVector3Array()
	
	for i in range(polygon.size()):
		var current := polygon[i]
		var next := polygon[(i + 1) % polygon.size()]
		
		lines.append(Vector3(current.x, 0.1, current.y))
		lines.append(Vector3(next.x, 0.1, next.y))
	
	gizmo.add_lines(lines, get_material("edge", gizmo))


func _draw_vertex_handles(gizmo: EditorNode3DGizmo, polygon: PackedVector2Array) -> void:
	var handles := PackedVector3Array()
	var ids := PackedInt32Array()
	
	for i in range(polygon.size()):
		var vertex := polygon[i]
		handles.append(Vector3(vertex.x, 0.1, vertex.y))
		ids.append(i)
	
	gizmo.add_handles(handles, get_material("vertex", gizmo), ids)


func _draw_info(gizmo: EditorNode3DGizmo, spawn_area: SpawnArea3D) -> void:
	# Info is drawn in the SpawnArea3D node's _update_debug_mesh for now
	# Could add billboard text here in the future
	pass


func _subgizmos_intersect_ray(gizmo: EditorNode3DGizmo, camera: Camera3D, screen_pos: Vector2) -> int:
	# Check if clicking near an edge to add a new vertex
	var spawn_area := gizmo.get_node_3d() as SpawnArea3D
	if not spawn_area or spawn_area.polygon.size() < 2:
		return -1
	
	# For now, return -1 (no subgizmo selection)
	# Edge clicking for vertex insertion is handled in _forward_3d_gui_input
	return -1


## Set the undo/redo manager
func set_undo_redo(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
