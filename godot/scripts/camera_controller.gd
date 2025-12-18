extends Node3D
class_name CameraController
## WoW/Metin2 hybrid camera controller.
## - Right-click + drag: Orbit camera around player (also selects target if clicking on entity)
## - Left-click on enemy: Attack enemy (move to if out of range, auto-attack)
## - Left-click on ground: Move to that location (click-to-move)
## - Left-click elsewhere: Clear target, stop auto-attack
## - Mouse wheel: Zoom in/out
##
## NOTE: We do NOT capture/hide the mouse. Custom cursors are handled by CursorManager.

## Signal emitted when ground is clicked (for click-to-move)
signal ground_clicked(world_position: Vector3)

## Signal emitted when enemy is clicked (for attack)
signal enemy_clicked(enemy_id: int, enemy_node: Node3D)

## Signal emitted when player/NPC is clicked (for selection)
signal entity_clicked(entity_id: int, entity_type: String, entity_node: Node3D)

## Signal emitted when clicking on nothing
signal clicked_nothing

## The player node to follow
@export var target: Node3D

## Camera distance settings
@export var min_distance: float = 2.0
@export var max_distance: float = 15.0
@export var default_distance: float = 7.0

## Camera angle limits (degrees)
@export var min_pitch: float = -80.0
@export var max_pitch: float = 60.0

## Sensitivity settings
@export var rotation_speed: float = 0.15
@export var zoom_speed: float = 1.0
@export var smooth_speed: float = 10.0

## Click vs drag detection thresholds
@export var click_threshold_distance: float = 20.0  # pixels - increased for better fast-click detection
@export var click_threshold_time: float = 0.35  # seconds - increased for better fast-click detection

## Current camera state
var current_yaw: float = 0.0
var current_pitch: float = -20.0
var current_distance: float = 7.0
var target_distance: float = 7.0

## Mouse state
var is_rotating: bool = false  # Right mouse held and dragging

## Click detection state - LEFT MOUSE
var left_click_start_pos: Vector2 = Vector2.ZERO
var left_click_start_time: float = 0.0
var left_click_is_drag: bool = false
var left_mouse_down: bool = false

## Click detection state - RIGHT MOUSE
var right_click_start_pos: Vector2 = Vector2.ZERO
var right_click_start_time: float = 0.0
var right_click_is_drag: bool = false
var right_mouse_down: bool = false

## Rotation indicator (shown at click position when rotating)
var rotation_start_pos: Vector2 = Vector2.ZERO
var rotation_indicator: TextureRect = null
var rotation_indicator_layer: CanvasLayer = null
var ROTATION_INDICATOR_TEXTURE: Texture2D = null

## Click indicator (Metin2-style ground click effect)
const ClickIndicatorScene = preload("res://scenes/effects/click_indicator.tscn")
var current_click_indicator: Node3D = null

## References
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

## Reference to combat controller
var combat_controller: Node = null

## Reference to click movement controller
var click_movement_controller: Node = null

## Reference to game manager (for entity lookups)
var game_manager: Node = null

## Raycast length
const RAY_LENGTH: float = 1000.0


func _ready() -> void:
	current_distance = default_distance
	target_distance = default_distance
	
	if spring_arm:
		spring_arm.spring_length = current_distance
	
	# Apply initial rotation
	_update_camera_transform()
	
	# Resolve target if it's not set (should be parent Player node)
	if target == null:
		target = get_parent()
	
	# Create rotation indicator
	_create_rotation_indicator()
	
	# Find controllers and managers after a frame
	await get_tree().process_frame
	_find_references()


func _find_references() -> void:
	# Ensure target is resolved
	if target == null:
		target = get_parent()
	
	# Find combat controller
	if target:
		combat_controller = target.get_node_or_null("CombatController")
		click_movement_controller = target.get_node_or_null("ClickMovementController")
	
	# Find game manager
	game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager == null:
		var main = get_tree().current_scene
		if main:
			game_manager = main.get_node_or_null("GameManager")


func _create_rotation_indicator() -> void:
	"""Create a visual indicator shown at the rotation pivot point."""
	# Try to load the rotation indicator texture
	ROTATION_INDICATOR_TEXTURE = load("res://assets/magic_cursors/36x36px/Cursor Target Move A.png") as Texture2D
	if ROTATION_INDICATOR_TEXTURE == null:
		push_warning("CameraController: Could not load rotation indicator texture")
		return
	
	# Create CanvasLayer to ensure it renders on top of everything
	rotation_indicator_layer = CanvasLayer.new()
	rotation_indicator_layer.layer = 100  # High layer to be on top
	add_child(rotation_indicator_layer)
	
	# Create the indicator texture
	rotation_indicator = TextureRect.new()
	rotation_indicator.texture = ROTATION_INDICATOR_TEXTURE
	rotation_indicator.visible = false
	rotation_indicator_layer.add_child(rotation_indicator)


func _start_camera_rotation() -> void:
	"""Start camera rotation mode - capture mouse and show indicator."""
	if is_rotating:
		return
	
	rotation_start_pos = get_viewport().get_mouse_position()
	is_rotating = true
	
	# Capture the mouse - hides cursor and prevents UI from intercepting
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Show indicator at the position where rotation started
	if rotation_indicator:
		var tex_size = rotation_indicator.texture.get_size()
		rotation_indicator.position = rotation_start_pos - tex_size / 2
		rotation_indicator.visible = true


func _stop_camera_rotation() -> void:
	"""Stop camera rotation mode - release mouse and hide indicator."""
	if not is_rotating:
		return
	
	is_rotating = false
	
	# Hide the indicator
	if rotation_indicator:
		rotation_indicator.visible = false
	
	# Release mouse capture and restore visibility
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Warp mouse back to where rotation started
	get_viewport().warp_mouse(rotation_start_pos)


func _unhandled_input(event: InputEvent) -> void:
	# Handle chat focus - click outside chat to unfocus
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if _is_chat_focused():
				_unfocus_chat()
				reset_mouse_state()
				return
	
	# Don't process camera input if chat is focused
	if _is_chat_focused():
		return
	
	# Handle mouse button events
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	
	# Handle mouse motion
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# LEFT MOUSE BUTTON
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			left_mouse_down = true
			left_click_start_pos = event.position
			left_click_start_time = Time.get_ticks_msec() / 1000.0
			left_click_is_drag = false
		else:
			left_mouse_down = false
			
			# Check if this was a click (not a drag)
			# For click-to-move: accept ANY quick click regardless of mouse movement
			# The player wants to move to where they RELEASE the mouse, not where they pressed
			# Only reject if the click duration is too long (held down too long)
			var click_duration = Time.get_ticks_msec() / 1000.0 - left_click_start_time
			
			if click_duration < click_threshold_time:
				_handle_left_click(event.position)
	
	# RIGHT MOUSE BUTTON
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			right_mouse_down = true
			right_click_start_pos = event.position
			right_click_start_time = Time.get_ticks_msec() / 1000.0
			right_click_is_drag = false
		else:
			right_mouse_down = false
			
			# Stop rotation if we were rotating
			_stop_camera_rotation()
			
			# Check if this was a click (not a drag) - select target
			if not right_click_is_drag:
				var click_duration = Time.get_ticks_msec() / 1000.0 - right_click_start_time
				if click_duration < click_threshold_time:
					_handle_right_click(event.position)
	
	# Mouse wheel - zoom
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		target_distance = max(min_distance, target_distance - zoom_speed)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		target_distance = min(max_distance, target_distance + zoom_speed)


func _handle_mouse_motion(motion: InputEventMouseMotion) -> void:
	# Check if left-click has become a drag
	if left_mouse_down and not left_click_is_drag:
		var drag_distance = motion.position.distance_to(left_click_start_pos)
		if drag_distance > click_threshold_distance:
			left_click_is_drag = true
	
	# Check if right-click has become a drag - start rotation mode
	if right_mouse_down and not right_click_is_drag:
		var drag_distance = motion.position.distance_to(right_click_start_pos)
		if drag_distance > click_threshold_distance:
			right_click_is_drag = true
			_start_camera_rotation()
	
	# Rotate camera when in rotation mode
	if is_rotating:
		current_yaw += motion.relative.x * rotation_speed
		current_pitch -= motion.relative.y * rotation_speed
		current_pitch = clamp(current_pitch, min_pitch, max_pitch)


func _process(delta: float) -> void:
	# Note: Camera follows player automatically via parent-child relationship.
	# The CameraController is a child of Player with a local Y offset of 1.5.
	# We only need to handle rotation and zoom here.
	
	# Smooth zoom
	current_distance = lerp(current_distance, target_distance, smooth_speed * delta)
	if spring_arm:
		spring_arm.spring_length = current_distance
	
	# Update camera transform
	_update_camera_transform()


func _update_camera_transform() -> void:
	global_rotation_degrees = Vector3(current_pitch, -current_yaw, 0)


## Handle left-click: Attack enemy, move to ground, or clear target
func _handle_left_click(screen_pos: Vector2) -> void:
	var hit := _raycast_at_position(screen_pos)
	
	if hit.is_empty():
		# Clicked on nothing
		_on_clicked_nothing()
		return
	
	# Check what was clicked
	var entity_info := _get_entity_from_hit(hit)
	
	if entity_info.type == "enemy":
		# Left-click on enemy: ATTACK
		_on_enemy_clicked(entity_info.id, entity_info.node)
	elif entity_info.type == "player":
		# Left-click on player: Just select (no attack)
		_on_entity_selected(entity_info.id, "player", entity_info.node)
	elif hit.has("position"):
		# Left-click on ground/surface: Move to location
		_on_ground_clicked(hit.position)
	else:
		_on_clicked_nothing()


## Handle right-click: Select/highlight target
func _handle_right_click(screen_pos: Vector2) -> void:
	var hit := _raycast_at_position(screen_pos)
	
	if hit.is_empty():
		return  # Right-click on nothing does nothing
	
	# Check what was clicked
	var entity_info := _get_entity_from_hit(hit)
	
	if entity_info.type == "enemy" or entity_info.type == "player":
		# Right-click on entity: SELECT (highlight)
		_on_entity_selected(entity_info.id, entity_info.type, entity_info.node)


## Called when enemy is left-clicked (attack)
func _on_enemy_clicked(enemy_id: int, enemy_node: Node3D) -> void:
	# Stop any current click-to-move
	if click_movement_controller:
		click_movement_controller.cancel_movement()
	
	# Start attacking this enemy
	if combat_controller:
		combat_controller.attack_enemy(enemy_id, enemy_node)
	
	emit_signal("enemy_clicked", enemy_id, enemy_node)


## Called when ground is left-clicked (move to)
func _on_ground_clicked(world_pos: Vector3) -> void:
	# Spawn click indicator at the click location
	_spawn_click_indicator(world_pos)
	
	# Stop auto-attack
	if combat_controller:
		combat_controller.stop_auto_attack()
	
	# Start moving to clicked position
	if click_movement_controller:
		click_movement_controller.move_to(world_pos)
	
	emit_signal("ground_clicked", world_pos)


## Spawn a Metin2-style click indicator at the given position
func _spawn_click_indicator(world_pos: Vector3) -> void:
	# Remove existing indicator if any (only one at a time)
	if current_click_indicator and is_instance_valid(current_click_indicator):
		current_click_indicator.queue_free()
		current_click_indicator = null
	
	# Create new indicator
	current_click_indicator = ClickIndicatorScene.instantiate()
	
	# Add to tree FIRST, then set position (global_position requires being in tree)
	var effects_container := _get_effects_container()
	if effects_container:
		effects_container.add_child(current_click_indicator)
	else:
		get_tree().current_scene.add_child(current_click_indicator)
	
	# Now set position after it's in the tree
	current_click_indicator.global_position = world_pos


## Get the effects container from game manager
func _get_effects_container() -> Node:
	if game_manager:
		return game_manager.get_node_or_null("EffectsContainer")
	return null


## Called when entity is selected (right-click)
func _on_entity_selected(entity_id: int, entity_type: String, entity_node: Node3D) -> void:
	# Set target in combat controller (without attacking)
	if combat_controller:
		combat_controller.set_target(entity_id, entity_node)
	
	emit_signal("entity_clicked", entity_id, entity_type, entity_node)


## Called when clicking on nothing
func _on_clicked_nothing() -> void:
	# Stop auto-attack and clear target
	if combat_controller:
		combat_controller.stop_auto_attack()
	
	emit_signal("clicked_nothing")


## Perform raycast at screen position
func _raycast_at_position(screen_pos: Vector2) -> Dictionary:
	if not camera:
		return {}
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	return space_state.intersect_ray(query)


## Get entity info from raycast hit
func _get_entity_from_hit(hit: Dictionary) -> Dictionary:
	if hit.is_empty() or not game_manager:
		return {"type": "none", "id": -1, "node": null}
	
	var collider = hit.collider
	
	# Check if it's an enemy
	var enemy_data = game_manager.get_enemy_by_node(collider)
	if not enemy_data.is_empty():
		return {"type": "enemy", "id": enemy_data.id, "node": enemy_data.node}
	
	# Check if it's a remote player
	var player_data = game_manager.get_player_by_node(collider)
	if not player_data.is_empty():
		return {"type": "player", "id": player_data.id, "node": player_data.node}
	
	# Not an entity - must be ground/terrain
	return {"type": "ground", "id": -1, "node": collider}


## Get the camera's forward direction on the XZ plane
func get_camera_forward() -> Vector3:
	var forward = -global_transform.basis.z
	forward.y = 0
	return forward.normalized()


## Get the camera's right direction on the XZ plane
func get_camera_right() -> Vector3:
	var right = global_transform.basis.x
	right.y = 0
	return right.normalized()


## Check if camera is currently being rotated
func is_camera_rotating() -> bool:
	return is_rotating


## Check if chat input is currently focused
func _is_chat_focused() -> bool:
	var chat_ui = get_tree().get_first_node_in_group("chat_ui")
	if chat_ui and chat_ui.has_method("is_input_focused"):
		return chat_ui.call("is_input_focused")
	return false


## Unfocus the chat input
func _unfocus_chat() -> void:
	var chat_ui = get_tree().get_first_node_in_group("chat_ui")
	if chat_ui and chat_ui.has_method("unfocus"):
		chat_ui.call("unfocus")


## Reset all mouse tracking state (public for external reset on state changes)
func reset_mouse_state() -> void:
	_stop_camera_rotation()
	left_mouse_down = false
	left_click_is_drag = false
	right_mouse_down = false
	right_click_is_drag = false


func _exit_tree() -> void:
	# Clean up texture references to prevent RID leaks on exit
	if rotation_indicator:
		rotation_indicator.texture = null
	ROTATION_INDICATOR_TEXTURE = null
