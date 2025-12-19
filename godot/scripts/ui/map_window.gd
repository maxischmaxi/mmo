extends Control
class_name MapWindow
## Circular minimap in top-left corner showing top-down view of the zone.
## Player is always centered, map rotates so camera direction is always "up".

## Map display colors
const MAP_BG_COLOR := Color(0.1, 0.15, 0.1, 0.95)
const BORDER_COLOR := Color(0.7, 0.55, 0.2, 1.0)  # Gold border
const LOCAL_PLAYER_COLOR := Color(1.0, 0.85, 0.0)  # Bright gold
const REMOTE_PLAYER_COLOR := Color(0.8, 0.65, 0.1)  # Darker gold
const ENEMY_COLOR := Color(0.9, 0.2, 0.2)  # Red

## Minimap size
const MINIMAP_SIZE: float = 180.0
const MINIMAP_RADIUS: float = MINIMAP_SIZE / 2.0
const BORDER_WIDTH: float = 4.0

## Entity marker sizes
const LOCAL_PLAYER_RADIUS: float = 6.0
const REMOTE_PLAYER_RADIUS: float = 4.0
const ENEMY_RADIUS: float = 4.0
const DIRECTION_ARROW_LENGTH: float = 10.0

## Zoom settings
const DEFAULT_SCALE: float = 2.5  # pixels per world unit
const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 0.5

## Button settings
const BUTTON_SIZE: float = 20.0
const BUTTON_FONT_SIZE: int = 16

## Current zoom level (multiplier)
var zoom_level: float = 1.0

## References
var local_player: Node = null
var game_manager: Node = null
var camera_controller: Node3D = null

## Track if we've logged reference finding to avoid spam
var _logged_references: bool = false


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
	
	# Find references after a frame
	await get_tree().process_frame
	_find_references()


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


func _process(_delta: float) -> void:
	# Always redraw when visible
	if visible:
		queue_redraw()


func _draw() -> void:
	# Try to find references if not set
	if not local_player or not is_instance_valid(local_player):
		_find_references()
	
	var center = Vector2(MINIMAP_RADIUS + 10, MINIMAP_RADIUS + 10)  # Offset for margin
	
	# Draw circular background with clipping
	draw_circle(center, MINIMAP_RADIUS, MAP_BG_COLOR)
	
	# Draw map content (clipped to circle)
	_draw_map_content(center)
	
	# Draw gold border
	draw_arc(center, MINIMAP_RADIUS, 0, TAU, 64, BORDER_COLOR, BORDER_WIDTH, true)
	
	# Draw zoom buttons on the border
	_draw_zoom_buttons(center)


func _draw_map_content(center: Vector2) -> void:
	"""Draw enemies, players, and local player on the map."""
	if not local_player or not is_instance_valid(local_player):
		return
	
	var scale = DEFAULT_SCALE * zoom_level
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
	
	# Draw enemies
	if game_manager:
		var enemies = game_manager.get_all_enemies()
		for id in enemies:
			var enemy_data = enemies[id]
			if enemy_data.has("node") and is_instance_valid(enemy_data["node"]):
				var enemy_node = enemy_data["node"] as Node3D
				var world_pos = enemy_node.global_position
				var screen_pos = _world_to_screen(world_pos, player_pos, center, scale, camera_rotation_y)
				
				# Only draw if within circle
				if center.distance_to(screen_pos) <= MINIMAP_RADIUS - ENEMY_RADIUS:
					draw_circle(screen_pos, ENEMY_RADIUS, ENEMY_COLOR)
		
		# Draw remote players
		var players = game_manager.get_all_players()
		for id in players:
			var player_data = players[id]
			if player_data.has("node") and is_instance_valid(player_data["node"]):
				var player_node = player_data["node"] as Node3D
				var world_pos = player_node.global_position
				var screen_pos = _world_to_screen(world_pos, player_pos, center, scale, camera_rotation_y)
				
				if center.distance_to(screen_pos) <= MINIMAP_RADIUS - REMOTE_PLAYER_RADIUS:
					draw_circle(screen_pos, REMOTE_PLAYER_RADIUS, REMOTE_PLAYER_COLOR)
	
	# Draw local player (always at center)
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
