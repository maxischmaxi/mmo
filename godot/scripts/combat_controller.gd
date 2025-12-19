extends Node
class_name CombatController
## Handles combat mechanics including auto-attack, move-to-attack, and attack animations.

## Signal emitted when auto-attack state changes
signal auto_attack_changed(is_active: bool)

## Signal emitted when an attack is performed
signal attack_performed(target_id: int)

## Signal emitted when attack is on cooldown
signal attack_cooldown_updated(progress: float)

## Signal emitted for combat messages
signal combat_message(message: String, message_type: String)

## Reference to the player
var player: Node = null

## Reference to the animation controller
var animation_controller: Node = null

## Reference to the click movement controller
var click_movement_controller: Node = null

## Current attack target (enemy node)
var attack_target_node: Node3D = null

## Current attack target ID
var attack_target_id: int = -1

## Whether auto-attack is active
var auto_attack_active: bool = false

## Current attack cooldown remaining
var attack_cooldown: float = 0.0

## Whether we're moving to attack (out of range, moving closer)
var is_moving_to_attack: bool = false

## Pending attack target ID (attack in progress, waiting for hit point)
var pending_attack_target_id: int = -1

## Attack range
const ATTACK_RANGE: float = 3.0

## Base attack animation duration
const BASE_ATTACK_DURATION: float = 1.53


func _ready() -> void:
	# Find player
	player = _find_player()
	if not player:
		push_warning("CombatController: Could not find player")
		return
	
	# Find animation controller
	await get_tree().process_frame
	_find_animation_controller()
	_find_click_movement_controller()


func _find_player() -> Node:
	var node = get_parent()
	while node:
		if node.has_method("attack_target") and node.has_method("get_attack_speed"):
			return node
		node = node.get_parent()
	return null


func _find_animation_controller() -> void:
	# Look for animation controller in character model
	var char_model = player.get_node_or_null("CharacterModel")
	if char_model:
		animation_controller = char_model.get_node_or_null("AnimationController")
		if animation_controller:
			print("CombatController: Found AnimationController")
			# Connect signals if not already connected
			if animation_controller.has_signal("attack_finished"):
				if not animation_controller.attack_finished.is_connected(_on_attack_animation_finished):
					animation_controller.attack_finished.connect(_on_attack_animation_finished)
			if animation_controller.has_signal("attack_hit"):
				if not animation_controller.attack_hit.is_connected(_on_attack_hit):
					animation_controller.attack_hit.connect(_on_attack_hit)
		else:
			print("CombatController: CharacterModel found but no AnimationController inside")
	else:
		print("CombatController: CharacterModel not found on player")


func _find_click_movement_controller() -> void:
	click_movement_controller = player.get_node_or_null("ClickMovementController")
	if click_movement_controller:
		if not click_movement_controller.destination_reached.is_connected(_on_destination_reached):
			click_movement_controller.destination_reached.connect(_on_destination_reached)


## Ensure animation controller is available, re-finding if necessary
## This handles the case where CharacterModel is removed and re-added to the tree
## (which happens during login -> character select -> game transitions)
func _ensure_animation_controller() -> bool:
	if animation_controller and is_instance_valid(animation_controller):
		return true
	
	print("CombatController: AnimationController not found or invalid, re-finding...")
	_find_animation_controller()
	
	if animation_controller:
		print("CombatController: Successfully re-found AnimationController")
		return true
	else:
		print("CombatController: Failed to find AnimationController")
		return false


func _process(delta: float) -> void:
	# Don't process combat if player is dead
	if player and player.has_method("is_player_dead") and player.is_player_dead():
		return
	
	# Update cooldown
	if attack_cooldown > 0:
		attack_cooldown -= delta
		var attack_speed := _get_attack_speed()
		var total_cooldown := BASE_ATTACK_DURATION / attack_speed
		var progress := 1.0 - (attack_cooldown / total_cooldown)
		emit_signal("attack_cooldown_updated", clamp(progress, 0.0, 1.0))
	
	# Process auto-attack
	if auto_attack_active:
		_process_auto_attack()
	
	# Process move-to-attack
	if is_moving_to_attack:
		_process_move_to_attack()


## Start attacking a target (called when left-clicking an enemy)
func attack_enemy(target_id: int, target_node: Node3D) -> void:
	print("CombatController: attack_enemy called - target_id=%d" % target_id)
	attack_target_id = target_id
	attack_target_node = target_node
	
	# Ensure we have a valid animation controller
	_ensure_animation_controller()
	
	# Check if in range
	if _is_in_attack_range():
		print("CombatController: Target in range, starting auto-attack")
		# In range - start auto-attack immediately
		start_auto_attack()
	else:
		print("CombatController: Target out of range, moving to attack")
		# Out of range - move to target
		is_moving_to_attack = true
		_move_toward_target()
		# Also enable auto-attack for when we arrive
		auto_attack_active = true
		emit_signal("auto_attack_changed", true)


## Start auto-attacking current target
func start_auto_attack() -> void:
	if attack_target_id == -1 or attack_target_node == null:
		emit_signal("combat_message", "No target", "error")
		return
	
	auto_attack_active = true
	emit_signal("auto_attack_changed", true)
	
	# Try to attack immediately if cooldown is ready
	if attack_cooldown <= 0:
		_perform_attack()


## Stop auto-attack
func stop_auto_attack() -> void:
	auto_attack_active = false
	is_moving_to_attack = false
	attack_target_id = -1
	attack_target_node = null
	pending_attack_target_id = -1  # Clear pending attack
	
	# Cancel click movement if we were moving to attack
	if click_movement_controller:
		click_movement_controller.cancel_movement()
	
	# Cancel attack animation if playing
	if animation_controller and animation_controller.has_method("cancel_attack"):
		animation_controller.cancel_attack()
	
	emit_signal("auto_attack_changed", false)
	emit_signal("attack_cooldown_updated", 0.0)


## Cancel current attack (but don't stop auto-attack entirely)
func cancel_current_attack() -> void:
	if animation_controller and animation_controller.has_method("cancel_attack"):
		animation_controller.cancel_attack()


## Check if auto-attack is active
func is_auto_attacking() -> bool:
	return auto_attack_active


## Set attack target without starting attack
func set_target(target_id: int, target_node: Node3D) -> void:
	attack_target_id = target_id
	attack_target_node = target_node


## Clear current target
func clear_target() -> void:
	stop_auto_attack()


## Process auto-attack logic
func _process_auto_attack() -> void:
	# Validate target still exists
	if attack_target_id == -1 or attack_target_node == null or not is_instance_valid(attack_target_node):
		stop_auto_attack()
		emit_signal("combat_message", "Target lost", "info")
		return
	
	# Check if in range
	if not _is_in_attack_range():
		# Target moved out of range - follow them
		is_moving_to_attack = true
		_move_toward_target()
		return
	
	# In range and cooldown ready - attack
	if attack_cooldown <= 0:
		_perform_attack()


## Process move-to-attack logic
func _process_move_to_attack() -> void:
	if attack_target_node == null or not is_instance_valid(attack_target_node):
		is_moving_to_attack = false
		return
	
	# Check if we're now in range
	if _is_in_attack_range():
		is_moving_to_attack = false
		# Cancel click movement if active
		if click_movement_controller:
			click_movement_controller.cancel_movement()
		# Attack immediately
		if attack_cooldown <= 0:
			_perform_attack()
	else:
		# Keep moving toward target
		_move_toward_target()


## Move player toward attack target
func _move_toward_target() -> void:
	if attack_target_node == null or not is_instance_valid(attack_target_node):
		return
	
	if click_movement_controller:
		# Calculate position just outside attack range
		var target_pos: Vector3 = attack_target_node.global_position
		var player_pos: Vector3 = player.global_position
		var direction: Vector3 = (target_pos - player_pos).normalized()
		
		# Move to a position within attack range
		var destination: Vector3 = target_pos - direction * (ATTACK_RANGE - 0.5)
		click_movement_controller.move_to(destination)


## Perform a single attack
func _perform_attack() -> void:
	print("CombatController: _perform_attack called")
	
	if attack_target_id == -1 or not player:
		print("CombatController: No target or player, aborting attack")
		return
	
	# Verify target is valid
	if attack_target_node == null or not is_instance_valid(attack_target_node):
		print("CombatController: Target node invalid, stopping auto-attack")
		stop_auto_attack()
		return
	
	# Verify range
	if not _is_in_attack_range():
		print("CombatController: Target out of range, moving to attack")
		# Start moving to target
		is_moving_to_attack = true
		_move_toward_target()
		return
	
	# Face the target
	_face_target()
	
	# Get attack speed
	var attack_speed := _get_attack_speed()
	print("CombatController: Attack speed = %.2f" % attack_speed)
	
	# Store pending attack target (damage will be dealt when animation hits)
	pending_attack_target_id = attack_target_id
	
	# Ensure animation controller is available (re-find if necessary)
	if not _ensure_animation_controller():
		push_warning("CombatController: Cannot attack - no animation controller")
		return
	
	# Play attack animation (this will trigger attack_hit signal at hit point)
	if animation_controller.has_method("play_attack_animation"):
		print("CombatController: Playing attack animation")
		animation_controller.play_attack_animation(attack_speed)
	else:
		push_warning("CombatController: AnimationController missing play_attack_animation method")
	
	# Set animation state on player (for network sync)
	if player.has_method("set_animation_state"):
		player.set_animation_state(4)  # 4 = Attacking
	
	# Start cooldown
	attack_cooldown = BASE_ATTACK_DURATION / attack_speed
	
	emit_signal("attack_performed", attack_target_id)


## Face the attack target
func _face_target() -> void:
	if attack_target_node == null or not is_instance_valid(attack_target_node):
		return
	
	var player_pos: Vector3 = player.global_position
	var target_pos: Vector3 = attack_target_node.global_position
	var direction: Vector3 = target_pos - player_pos
	direction.y = 0
	
	if direction.length_squared() > 0.01:
		var target_yaw: float = atan2(direction.x, direction.z)
		player.rotation.y = target_yaw


## Check if player is within attack range of target
func _is_in_attack_range() -> bool:
	if attack_target_node == null or not is_instance_valid(attack_target_node):
		return false
	
	var distance: float = player.global_position.distance_to(attack_target_node.global_position)
	return distance <= ATTACK_RANGE


## Get attack speed from player
func _get_attack_speed() -> float:
	if player and player.has_method("get_attack_speed"):
		return player.get_attack_speed()
	return 1.0


## Called when attack animation reaches hit point (damage should be dealt now)
func _on_attack_hit() -> void:
	print("CombatController: _on_attack_hit signal received")
	
	# Verify we have a pending attack
	if pending_attack_target_id == -1:
		print("CombatController: No pending attack target")
		return
	
	# Verify target is still valid
	if attack_target_node == null or not is_instance_valid(attack_target_node):
		print("CombatController: Target node no longer valid")
		pending_attack_target_id = -1
		return
	
	# Verify still in range (target might have moved)
	if not _is_in_attack_range():
		print("CombatController: Target moved out of range")
		pending_attack_target_id = -1
		return
	
	# Send attack to server NOW (at the hit point of the animation)
	if player.has_method("attack_target"):
		print("CombatController: Sending attack to server for target %d" % pending_attack_target_id)
		player.attack_target(pending_attack_target_id)
	
	pending_attack_target_id = -1


## Called when attack animation finishes
func _on_attack_animation_finished() -> void:
	# Clear any pending attack that didn't fire
	pending_attack_target_id = -1
	
	# Reset animation state to idle (will be overridden by movement if moving)
	if player.has_method("set_animation_state"):
		player.set_animation_state(0)  # 0 = Idle


## Called when click movement reaches destination
func _on_destination_reached() -> void:
	# If we were moving to attack, check if we can attack now
	if is_moving_to_attack and _is_in_attack_range():
		is_moving_to_attack = false
		if attack_cooldown <= 0:
			_perform_attack()
