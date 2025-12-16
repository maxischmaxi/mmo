extends Node
class_name ClickMovementController
## Handles click-to-move navigation for the player.
## Works alongside WASD movement - WASD input cancels click-to-move.

## Signal emitted when player reaches the click destination
signal destination_reached

## Signal emitted when click-to-move is cancelled (by WASD input)
signal movement_cancelled

## Reference to the player (CharacterBody3D)
var player: CharacterBody3D = null

## Current destination to move to (null if not moving to a point)
var target_position: Vector3 = Vector3.ZERO

## Whether we're currently moving to a clicked position
var is_moving_to_target: bool = false

## Distance threshold to consider destination reached
const ARRIVAL_THRESHOLD: float = 0.5

## Movement speed (should match player speed)
var move_speed: float = 5.0


func _ready() -> void:
	# Find player in parent hierarchy
	var node = get_parent()
	while node:
		if node is CharacterBody3D:
			player = node
			break
		node = node.get_parent()
	
	if not player:
		push_warning("ClickMovementController: Could not find player CharacterBody3D")


func _physics_process(delta: float) -> void:
	if not is_moving_to_target or not player:
		return
	
	# Check if WASD is being pressed - cancel click-to-move
	if _is_wasd_pressed():
		cancel_movement()
		return
	
	# Calculate direction to target (only XZ plane)
	var current_pos := player.global_position
	var direction := target_position - current_pos
	direction.y = 0  # Only move on XZ plane
	
	var distance := direction.length()
	
	# Check if we've arrived
	if distance < ARRIVAL_THRESHOLD:
		_arrive_at_destination()
		return
	
	# Normalize direction
	direction = direction.normalized()
	
	# Apply movement
	var velocity := player.velocity
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	# Keep Y velocity (gravity)
	player.velocity = velocity
	
	# Rotate player to face movement direction
	var target_yaw := atan2(direction.x, direction.z)
	var current_rot := player.rotation
	player.rotation.y = lerp_angle(current_rot.y, target_yaw, 10.0 * delta)


## Check if any WASD key is pressed
func _is_wasd_pressed() -> bool:
	return Input.is_action_pressed("move_forward") or \
		   Input.is_action_pressed("move_back") or \
		   Input.is_action_pressed("move_left") or \
		   Input.is_action_pressed("move_right") or \
		   Input.is_action_pressed("strafe_left") or \
		   Input.is_action_pressed("strafe_right")


## Start moving to a position
func move_to(position: Vector3) -> void:
	target_position = position
	target_position.y = player.global_position.y  # Keep same Y level
	is_moving_to_target = true


## Cancel current click-to-move
func cancel_movement() -> void:
	if is_moving_to_target:
		is_moving_to_target = false
		emit_signal("movement_cancelled")


## Called when player arrives at destination
func _arrive_at_destination() -> void:
	is_moving_to_target = false
	
	# Stop horizontal movement
	if player:
		var velocity := player.velocity
		velocity.x = 0
		velocity.z = 0
		player.velocity = velocity
	
	emit_signal("destination_reached")


## Check if currently moving to a clicked position
func is_click_moving() -> bool:
	return is_moving_to_target


## Get current target position
func get_target_position() -> Vector3:
	return target_position


## Update move speed (call when player speed changes)
func set_move_speed(speed: float) -> void:
	move_speed = speed
