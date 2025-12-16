extends Node3D
class_name CameraController
## WoW-style third-person camera controller.
## - Right-click + drag: Orbit camera around player
## - Left-click + drag: Turn character to face camera direction
## - Left-click (no drag): Select target
## - Both buttons: Move forward in camera direction
## - Mouse wheel: Zoom in/out
##
## NOTE: We do NOT capture/hide the mouse. Custom cursors are handled by CursorManager.
## Camera rotation uses mouse movement delta (InputEventMouseMotion.relative).

## Signal emitted when player clicks (for targeting)
signal clicked(screen_position: Vector2)

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
@export var click_threshold_distance: float = 5.0  # pixels
@export var click_threshold_time: float = 0.25  # seconds

## Current camera state
var current_yaw: float = 0.0
var current_pitch: float = -20.0
var current_distance: float = 7.0
var target_distance: float = 7.0

## Mouse state
var is_rotating: bool = false  # Right mouse held
var is_turning: bool = false   # Left mouse held (and dragging)

## Click detection state
var left_click_start_pos: Vector2 = Vector2.ZERO
var left_click_start_time: float = 0.0
var left_click_is_drag: bool = false
var left_mouse_down: bool = false  # Track if left mouse is currently down

## References
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

## Reference to targeting system
var targeting_system: Node = null


func _ready() -> void:
	current_distance = default_distance
	target_distance = default_distance
	
	if spring_arm:
		spring_arm.spring_length = current_distance
	
	# Apply initial rotation
	_update_camera_transform()
	
	# Find targeting system after a frame
	await get_tree().process_frame
	targeting_system = get_tree().get_first_node_in_group("targeting_system")
	if targeting_system == null:
		var main = get_tree().current_scene
		if main:
			targeting_system = main.get_node_or_null("GameManager/TargetingSystem")


func _input(event: InputEvent) -> void:
	# Handle chat focus - click outside chat to unfocus
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Check if chat is focused and we clicked outside it
			if _is_chat_focused():
				_unfocus_chat()
				# Reset all mouse state since we're coming out of chat
				_reset_mouse_state()
				return
	
	# Don't process camera input if chat is focused
	if _is_chat_focused():
		return
	
	# Handle mouse button state
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		# Right mouse button - camera rotation
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			is_rotating = mouse_event.pressed
		
		# Left mouse button - character turning OR target selection
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Left button pressed - start tracking for click vs drag
				left_mouse_down = true
				left_click_start_pos = mouse_event.position
				left_click_start_time = Time.get_ticks_msec() / 1000.0
				left_click_is_drag = false
				is_turning = false  # Not turning yet until we detect drag
			else:
				# Left button released
				left_mouse_down = false
				is_turning = false
				
				# Check if this was a click (not a drag)
				if not left_click_is_drag:
					var click_duration = Time.get_ticks_msec() / 1000.0 - left_click_start_time
					if click_duration < click_threshold_time:
						# This was a click - trigger target selection at current mouse position
						_handle_click(get_viewport().get_mouse_position())
		
		# Mouse wheel - zoom
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = max(min_distance, target_distance - zoom_speed)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = min(max_distance, target_distance + zoom_speed)
	
	# Handle mouse motion
	if event is InputEventMouseMotion:
		var motion = event as InputEventMouseMotion
		
		# Check if left-click has become a drag
		if left_mouse_down and not left_click_is_drag:
			var current_pos = get_viewport().get_mouse_position()
			var drag_distance = current_pos.distance_to(left_click_start_pos)
			if drag_distance > click_threshold_distance:
				left_click_is_drag = true
				is_turning = true
		
		# Rotate camera when right-click is held OR left-click is dragging
		if is_rotating or is_turning:
			# Rotate camera yaw (horizontal) - move mouse right = camera rotates right
			current_yaw += motion.relative.x * rotation_speed
			
			# Rotate camera pitch (vertical) - move mouse up = camera looks up
			current_pitch -= motion.relative.y * rotation_speed
			current_pitch = clamp(current_pitch, min_pitch, max_pitch)
			
			# Note: Character rotation is now handled automatically when moving
			# The player rotates to face their movement direction


func _process(delta: float) -> void:
	# Follow target
	if target:
		global_position = target.global_position
	
	# Smooth zoom
	current_distance = lerp(current_distance, target_distance, smooth_speed * delta)
	if spring_arm:
		spring_arm.spring_length = current_distance
	
	# Update camera transform FIRST
	_update_camera_transform()
	
	# Don't process movement controls if chat is focused
	if _is_chat_focused():
		return
	
	# Auto-move forward when both buttons held
	if is_rotating and left_mouse_down and target:
		# Signal the player to move forward
		_move_player_forward()


func _update_camera_transform() -> void:
	# Apply rotation in global space so camera is independent of player rotation
	global_rotation_degrees = Vector3(current_pitch, -current_yaw, 0)


func _move_player_forward() -> void:
	# Get the camera's forward direction (projected onto XZ plane)
	if target and target.has_method("set_movement_direction"):
		var forward = -global_transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		target.set_movement_direction(forward)
		# Also rotate character to face camera direction (WoW-style)
		target.rotation.y = atan2(forward.x, forward.z)


func _handle_click(screen_pos: Vector2) -> void:
	# Emit signal for external handlers
	emit_signal("clicked", screen_pos)
	
	# Also directly call targeting system if available
	if targeting_system and targeting_system.has_method("select_target_at_position"):
		targeting_system.select_target_at_position(screen_pos)


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


## Check if character is being turned
func is_character_turning() -> bool:
	return is_turning


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


## Reset all mouse tracking state
func _reset_mouse_state() -> void:
	is_rotating = false
	is_turning = false
	left_mouse_down = false
	left_click_is_drag = false
	_sync_camera_to_player()


## Sync camera yaw with player rotation (optional, for when player rotates externally)
func _sync_camera_to_player() -> void:
	# With camera-relative movement, we don't need to sync camera to player
	# The player follows the camera direction, not the other way around
	pass


## Called when UI (like chat) releases focus
func on_ui_focus_released() -> void:
	_reset_mouse_state()
