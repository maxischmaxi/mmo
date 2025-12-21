extends Control
class_name MapWindow
## Circular minimap in top-left corner showing top-down view of the zone.
## Player is always centered, map rotates so camera direction is always "up".
## Renders buildings, terrain, and other world geometry from above.

## Map display colors
const MAP_BG_COLOR := Color(0.1, 0.15, 0.1, 0.95)
const BORDER_COLOR := Color(0.7, 0.55, 0.2, 1.0)  # Gold border
const LOCAL_PLAYER_COLOR := Color(1.0, 0.85, 0.0)  # Bright gold
const REMOTE_PLAYER_COLOR := Color(0.8, 0.65, 0.1)  # Darker gold
const ENEMY_COLOR := Color(0.9, 0.2, 0.2)  # Red
const NPC_COLOR := Color(0.2, 0.8, 0.2)  # Green for NPCs

## Minimap size
const MINIMAP_SIZE: float = 180.0
const MINIMAP_RADIUS: float = MINIMAP_SIZE / 2.0
const BORDER_WIDTH: float = 4.0

## Entity marker sizes
const LOCAL_PLAYER_RADIUS: float = 6.0
const REMOTE_PLAYER_RADIUS: float = 4.0
const ENEMY_RADIUS: float = 4.0
const NPC_RADIUS: float = 4.0
const DIRECTION_ARROW_LENGTH: float = 10.0

## Zoom settings
const DEFAULT_SCALE: float = 2.5  # pixels per world unit
const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 0.5

## Button settings
const BUTTON_SIZE: float = 20.0
const BUTTON_FONT_SIZE: int = 16

## Viewport settings for world rendering
const VIEWPORT_SIZE: int = 256
const CAMERA_HEIGHT: float = 100.0  # Height above player for top-down view
const CIRCLE_SEGMENTS: int = 64  # Smoothness of circular mask

## Current zoom level (multiplier)
var zoom_level: float = 1.0

## References
var local_player: Node = null
var game_manager: Node = null
var camera_controller: Node3D = null

## Viewport rendering
var minimap_viewport: SubViewport = null
var minimap_camera: Camera3D = null
var _viewport_ready: bool = false

## Track if we've logged reference finding to avoid spam
var _logged_references: bool = false

## Track connection retries
var _connection_retries: int = 0
const MAX_CONNECTION_RETRIES: int = 10


func _ready() -> void:
	# Add to group for easy finding
	add_to_group("map_window")
	
	# Set up the control size and position
	custom_minimum_size = Vector2(MINIMAP_SIZE + 40, MINIMAP_SIZE + 20)  # Extra space for buttons
	size = custom_minimum_size
	position = Vector2(10, 10)  # Top-left corner with margin
	
	# Don't register with UIManager - this is always visible, not a dialog
	
	# Start visible (always shown when in game)
	visible = true
	
	# Set up the viewport for world rendering
	_setup_minimap_viewport()
	
	# Find references after a frame
	await get_tree().process_frame
	_find_references()
	
	# Connect viewport to main world after everything is ready
	await get_tree().process_frame
	_connect_viewport_to_world()


func _find_references() -> void:
	"""Find references to local player, game manager, and camera controller."""
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	game_manager = get_tree().get_first_node_in_group("game_manager")
	
	# Find camera controller (child of player)
	if local_player:
		camera_controller = local_player.get_node_or_null("CameraController")
	
	# Debug output (only once)
	if not _logged_references:
		_logged_references = true
		if local_player:
			print("[Minimap] Found local_player: ", local_player.name)
		if game_manager:
			print("[Minimap] Found game_manager: ", game_manager.name)
		if camera_controller:
			print("[Minimap] Found camera_controller")


func _setup_minimap_viewport() -> void:
	"""Create the SubViewport and Camera3D for rendering the world from above."""
	# Create SubViewport
	minimap_viewport = SubViewport.new()
	minimap_viewport.name = "MinimapViewport"
	minimap_viewport.size = Vector2i(VIEWPORT_SIZE, VIEWPORT_SIZE)
	minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	minimap_viewport.transparent_bg = false
	minimap_viewport.msaa_3d = Viewport.MSAA_2X
	minimap_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	minimap_viewport.positional_shadow_atlas_size = 0  # Disable point/spot light shadows
	# Disable all shadow atlas quadrants to fully disable positional shadows
	minimap_viewport.positional_shadow_atlas_16_bits = false
	minimap_viewport.set_positional_shadow_atlas_quadrant_subdiv(0, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED)
	minimap_viewport.set_positional_shadow_atlas_quadrant_subdiv(1, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED)
	minimap_viewport.set_positional_shadow_atlas_quadrant_subdiv(2, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED)
	minimap_viewport.set_positional_shadow_atlas_quadrant_subdiv(3, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED)
	
	# Use unshaded debug draw to completely remove lighting/shadows from minimap
	# This gives a clean, flat look appropriate for a top-down map view
	minimap_viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	
	add_child(minimap_viewport)
	
	# Create orthographic camera
	minimap_camera = Camera3D.new()
	minimap_camera.name = "MinimapCamera"
	minimap_camera.projection = 1  # PROJECTION_ORTHOGONAL
	minimap_camera.size = _calculate_camera_size()
	minimap_camera.near = 0.1
	minimap_camera.far = 200.0
	minimap_camera.current = true  # Make it the active camera in this viewport
	# Start looking straight down
	minimap_camera.rotation_degrees = Vector3(-90, 0, 0)
	# Exclude layer 2 (enemies) from minimap rendering - we draw dots instead
	# Layer 1 = terrain/buildings (bit 0), Layer 2 = enemies (bit 1)
	# Cull mask: all layers except layer 2 = 0xFFFFFFFF & ~(1 << 1) = 0xFFFFFFFD
	minimap_camera.cull_mask = 0xFFFFFFFD
	minimap_viewport.add_child(minimap_camera)


func _connect_viewport_to_world() -> void:
	"""Connect the SubViewport to share the main scene's 3D world."""
	if not minimap_viewport:
		return
	
	# Get the main viewport's world_3d
	var main_viewport = get_viewport()
	if main_viewport and main_viewport.world_3d:
		minimap_viewport.world_3d = main_viewport.world_3d
		_viewport_ready = true
		print("[Minimap] Connected to main world_3d")
	else:
		# Try again next frame if world_3d isn't ready yet
		_connection_retries += 1
		if _connection_retries < MAX_CONNECTION_RETRIES:
			push_warning("[Minimap] world_3d not ready, retrying (%d/%d)..." % [_connection_retries, MAX_CONNECTION_RETRIES])
			await get_tree().process_frame
			_connect_viewport_to_world()
		else:
			push_error("[Minimap] Failed to connect to world_3d after %d attempts" % MAX_CONNECTION_RETRIES)





func _calculate_camera_size() -> float:
	"""Calculate the orthographic camera size based on zoom level.
	Returns half the visible world height in world units."""
	# Visible world diameter = minimap pixels / (pixels per world unit)
	var visible_diameter = MINIMAP_SIZE / (DEFAULT_SCALE * zoom_level)
	# Orthographic size is half the height
	return visible_diameter / 2.0


func _update_minimap_camera() -> void:
	"""Update the minimap camera position and rotation to follow the player."""
	if not minimap_camera or not local_player or not is_instance_valid(local_player):
		return
	
	# Get player position
	var player_pos := Vector3.ZERO
	if local_player is Node3D:
		player_pos = (local_player as Node3D).global_position
	
	# Position camera above player
	minimap_camera.global_position = Vector3(player_pos.x, player_pos.y + CAMERA_HEIGHT, player_pos.z)
	
	# Update camera size based on current zoom
	minimap_camera.size = _calculate_camera_size()
	
	# Rotate camera to match player camera orientation
	# The map should rotate so that camera direction is always "up"
	var yaw: float = 0.0
	if camera_controller and is_instance_valid(camera_controller) and "current_yaw" in camera_controller:
		yaw = camera_controller.current_yaw
	elif camera_controller and is_instance_valid(camera_controller):
		yaw = rad_to_deg(-camera_controller.global_rotation.y)
	elif local_player is Node3D:
		yaw = rad_to_deg(-(local_player as Node3D).rotation.y)
	
	# Looking down (-90 X) with Y rotation for orientation
	# Negative yaw because we want the map to rotate opposite to camera movement
	minimap_camera.rotation_degrees = Vector3(-90, -yaw, 0)


func _process(_delta: float) -> void:
	# Update camera position and redraw when visible
	if visible:
		_update_minimap_camera()
		queue_redraw()


func _draw() -> void:
	# Try to find references if not set
	if not local_player or not is_instance_valid(local_player):
		_find_references()
	
	var center = Vector2(MINIMAP_RADIUS + 10, MINIMAP_RADIUS + 10)  # Offset for margin
	
	# Draw world from viewport as circular background
	if _viewport_ready and minimap_viewport:
		var texture = minimap_viewport.get_texture()
		if texture:
			_draw_circular_texture(center, MINIMAP_RADIUS, texture)
		else:
			draw_circle(center, MINIMAP_RADIUS, MAP_BG_COLOR)
	else:
		# Fallback to solid background while loading
		draw_circle(center, MINIMAP_RADIUS, MAP_BG_COLOR)
	
	# Draw map content (entities) on top
	_draw_map_content(center)
	
	# Draw gold border
	draw_arc(center, MINIMAP_RADIUS, 0, TAU, 64, BORDER_COLOR, BORDER_WIDTH, true)
	
	# Draw zoom buttons on the border
	_draw_zoom_buttons(center)


func _draw_circular_texture(center: Vector2, radius: float, texture: Texture2D) -> void:
	"""Draw a texture masked to a circle using triangle fan."""
	if texture == null:
		draw_circle(center, radius, MAP_BG_COLOR)
		return
	
	# Draw the texture as a series of triangles forming a circle
	for i in range(CIRCLE_SEGMENTS):
		var angle1 = float(i) / CIRCLE_SEGMENTS * TAU - PI / 2  # Start from top
		var angle2 = float(i + 1) / CIRCLE_SEGMENTS * TAU - PI / 2
		
		# Triangle points: center, edge1, edge2
		var p0 = center
		var p1 = center + Vector2(cos(angle1), sin(angle1)) * radius
		var p2 = center + Vector2(cos(angle2), sin(angle2)) * radius
		
		# UV coordinates (map circle to square texture)
		var uv0 = Vector2(0.5, 0.5)
		var uv1 = Vector2(0.5 + cos(angle1) * 0.5, 0.5 + sin(angle1) * 0.5)
		var uv2 = Vector2(0.5 + cos(angle2) * 0.5, 0.5 + sin(angle2) * 0.5)
		
		var points = PackedVector2Array([p0, p1, p2])
		var uvs = PackedVector2Array([uv0, uv1, uv2])
		var colors = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
		
		draw_polygon(points, colors, uvs, texture)


func _draw_map_content(center: Vector2) -> void:
	"""Draw enemies, NPCs, players, and local player on the map."""
	if not local_player or not is_instance_valid(local_player):
		return
	
	# Calculate the correct scale to match the viewport camera
	# The camera's orthographic size is half the visible world height
	# The viewport texture is scaled to fit MINIMAP_SIZE diameter
	var camera_size = _calculate_camera_size()  # Half the visible world diameter
	var visible_world_diameter = camera_size * 2.0
	# Scale: how many minimap pixels per world unit
	var map_scale = MINIMAP_SIZE / visible_world_diameter
	
	var player_pos: Vector3 = Vector3.ZERO
	if local_player is Node3D:
		player_pos = (local_player as Node3D).global_position
	
	# Get camera rotation for map orientation
	var camera_rotation_y: float = 0.0
	if camera_controller and is_instance_valid(camera_controller) and "current_yaw" in camera_controller:
		camera_rotation_y = deg_to_rad(camera_controller.current_yaw)
	elif camera_controller and is_instance_valid(camera_controller):
		camera_rotation_y = -camera_controller.global_rotation.y
	elif local_player is Node3D:
		camera_rotation_y = -(local_player as Node3D).rotation.y
	
	if game_manager:
		# Draw enemies (red)
		var all_enemies = game_manager.get_all_enemies()
		for id in all_enemies:
			var enemy_data = all_enemies[id]
			if enemy_data.has("node") and is_instance_valid(enemy_data["node"]):
				var enemy_node = enemy_data["node"] as Node3D
				var world_pos = enemy_node.global_position
				var screen_pos = _world_to_screen(world_pos, player_pos, center, map_scale, camera_rotation_y)
				
				# Only draw if within circle
				if center.distance_to(screen_pos) <= MINIMAP_RADIUS - ENEMY_RADIUS:
					draw_circle(screen_pos, ENEMY_RADIUS, ENEMY_COLOR)
		
		# Draw NPCs (green)
		var all_npcs = game_manager.get_all_npcs()
		for id in all_npcs:
			var npc_data = all_npcs[id]
			if npc_data.has("node") and is_instance_valid(npc_data["node"]):
				var npc_node = npc_data["node"] as Node3D
				var world_pos = npc_node.global_position
				var screen_pos = _world_to_screen(world_pos, player_pos, center, map_scale, camera_rotation_y)
				
				if center.distance_to(screen_pos) <= MINIMAP_RADIUS - NPC_RADIUS:
					draw_circle(screen_pos, NPC_RADIUS, NPC_COLOR)
		
		# Draw remote players (gold)
		var all_players = game_manager.get_all_players()
		for id in all_players:
			var player_data = all_players[id]
			if player_data.has("node") and is_instance_valid(player_data["node"]):
				var player_node = player_data["node"] as Node3D
				var world_pos = player_node.global_position
				var screen_pos = _world_to_screen(world_pos, player_pos, center, map_scale, camera_rotation_y)
				
				if center.distance_to(screen_pos) <= MINIMAP_RADIUS - REMOTE_PLAYER_RADIUS:
					draw_circle(screen_pos, REMOTE_PLAYER_RADIUS, REMOTE_PLAYER_COLOR)
	
	# Draw local player (always at center, bright gold)
	draw_circle(center, LOCAL_PLAYER_RADIUS, LOCAL_PLAYER_COLOR)
	
	# Draw direction arrow for local player (always points up)
	_draw_direction_arrow(center)


func _world_to_screen(world_pos: Vector3, player_pos: Vector3, map_center: Vector2, scale: float, camera_rotation: float) -> Vector2:
	"""Convert world position to screen position, centered on player."""
	var dx = world_pos.x - player_pos.x
	var dz = world_pos.z - player_pos.z
	
	var world_2d = Vector2(dx, dz)
	var rotated = world_2d.rotated(-camera_rotation)
	
	return map_center + rotated * scale


func _draw_direction_arrow(center: Vector2) -> void:
	"""Draw an arrow indicating player facing direction (always points up)."""
	var arrow_dir = Vector2(0, -1)
	var arrow_end = center + arrow_dir * DIRECTION_ARROW_LENGTH
	
	draw_line(center, arrow_end, LOCAL_PLAYER_COLOR, 2.0)
	
	var head_size = 4.0
	var head_angle = PI / 6
	var left_head = arrow_end - arrow_dir.rotated(-head_angle) * head_size
	var right_head = arrow_end - arrow_dir.rotated(head_angle) * head_size
	
	draw_line(arrow_end, left_head, LOCAL_PLAYER_COLOR, 2.0)
	draw_line(arrow_end, right_head, LOCAL_PLAYER_COLOR, 2.0)


func _draw_zoom_buttons(center: Vector2) -> void:
	"""Draw + and - zoom buttons sitting on top of the border."""
	# Position buttons at bottom of the circle, sitting on the border
	# Use angle to position them at roughly 7 o'clock and 5 o'clock positions
	var left_angle = PI * 0.75  # 135 degrees - bottom-left
	var right_angle = PI * 0.25  # 45 degrees - bottom-right
	
	# Position on the border itself
	var minus_pos = center + Vector2(cos(left_angle), sin(left_angle)) * MINIMAP_RADIUS
	var plus_pos = center + Vector2(cos(right_angle), sin(right_angle)) * MINIMAP_RADIUS
	
	_draw_zoom_button(minus_pos, "-", zoom_level <= MIN_ZOOM)
	_draw_zoom_button(plus_pos, "+", zoom_level >= MAX_ZOOM)


func _draw_zoom_button(pos: Vector2, symbol: String, disabled: bool) -> void:
	"""Draw a single zoom button with + or - symbol."""
	var bg_color = Color(0.15, 0.12, 0.08, 1.0) if not disabled else Color(0.1, 0.08, 0.05, 0.8)
	var symbol_color = BORDER_COLOR if not disabled else Color(0.4, 0.3, 0.15, 0.6)
	var border_thickness = 3.0
	
	# Draw button background (solid circle)
	draw_circle(pos, BUTTON_SIZE / 2, bg_color)
	
	# Draw gold border
	draw_arc(pos, BUTTON_SIZE / 2, 0, TAU, 32, BORDER_COLOR, border_thickness, true)
	
	# Draw + or - symbol manually using lines for better visibility
	var line_length = BUTTON_SIZE * 0.4
	var line_width = 2.5
	
	# Horizontal line (for both + and -)
	draw_line(
		pos + Vector2(-line_length / 2, 0),
		pos + Vector2(line_length / 2, 0),
		symbol_color,
		line_width
	)
	
	# Vertical line (only for +)
	if symbol == "+":
		draw_line(
			pos + Vector2(0, -line_length / 2),
			pos + Vector2(0, line_length / 2),
			symbol_color,
			line_width
		)


func _gui_input(event: InputEvent) -> void:
	"""Handle input for zoom buttons."""
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var center = Vector2(MINIMAP_RADIUS + 10, MINIMAP_RADIUS + 10)
			var mouse_pos = mouse_event.position
			
			# Calculate button positions (same as in _draw_zoom_buttons)
			var left_angle = PI * 0.75
			var right_angle = PI * 0.25
			var minus_pos = center + Vector2(cos(left_angle), sin(left_angle)) * MINIMAP_RADIUS
			var plus_pos = center + Vector2(cos(right_angle), sin(right_angle)) * MINIMAP_RADIUS
			
			# Check minus button
			if mouse_pos.distance_to(minus_pos) <= BUTTON_SIZE / 2:
				_zoom_out()
				accept_event()
				return
			
			# Check plus button
			if mouse_pos.distance_to(plus_pos) <= BUTTON_SIZE / 2:
				_zoom_in()
				accept_event()
				return


func _zoom_in() -> void:
	zoom_level = minf(zoom_level + ZOOM_STEP, MAX_ZOOM)


func _zoom_out() -> void:
	zoom_level = maxf(zoom_level - ZOOM_STEP, MIN_ZOOM)
