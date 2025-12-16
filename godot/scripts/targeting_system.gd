extends Node
class_name TargetingSystem
## WoW-style targeting system for selecting enemies and players.

## Signal emitted when target changes
signal target_changed(target_id: int, target_type: String, target_data: Dictionary)

## Signal emitted when we need to show a UI message
signal show_message(message: String, message_type: String)

## Signal emitted when auto-attack state changes
signal auto_attack_changed(is_active: bool)

## Signal emitted when swing timer updates (for UI)
signal swing_timer_updated(progress: float, is_attacking: bool)

## Current target information
var current_target_id: int = -1
var current_target_type: String = "none"  # "enemy", "player", "none"
var current_target_node: Node3D = null

## Reference to game manager for entity lookups
var game_manager: Node = null

## Reference to local player
var local_player: Node = null

## Reference to the camera
var camera: Camera3D = null

## Selection circle instance
var selection_circle: Node3D = null
const SelectionCircleScene = preload("res://scenes/effects/selection_circle.tscn")

## Attack range for feedback
const ATTACK_RANGE: float = 5.0

## Raycast parameters
const RAY_LENGTH: float = 1000.0

## Auto-attack state
var auto_attack_active: bool = false
var attack_cooldown: float = 0.0
const ATTACK_SPEED: float = 2.0  # Seconds between attacks (swing timer)
const AUTO_TARGET_RANGE: float = 30.0  # Range to auto-target nearest enemy


func _ready() -> void:
	# Add to group for easy finding
	add_to_group("targeting_system")
	
	# Wait a frame for other nodes to be ready
	await get_tree().process_frame
	
	# Find game manager
	game_manager = get_node_or_null("/root/Main/GameManager")
	if game_manager == null:
		game_manager = get_tree().get_first_node_in_group("game_manager")
	
	# Find local player
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	# Find camera
	if local_player:
		var camera_controller = local_player.get_node_or_null("CameraController")
		if camera_controller:
			camera = camera_controller.get_node_or_null("SpringArm3D/Camera3D")
	
	# Connect to entity death signals
	if local_player:
		if local_player.has_signal("entity_died"):
			local_player.connect("entity_died", _on_entity_died)
		if local_player.has_signal("enemy_despawned"):
			local_player.connect("enemy_despawned", _on_enemy_despawned)
	
	# Create selection circle
	_create_selection_circle()


func _create_selection_circle() -> void:
	if SelectionCircleScene:
		selection_circle = SelectionCircleScene.instantiate()
		selection_circle.visible = false
		add_child(selection_circle)


func _process(delta: float) -> void:
	# Update selection circle position
	if selection_circle and current_target_node and is_instance_valid(current_target_node):
		selection_circle.global_position = current_target_node.global_position
		selection_circle.global_position.y = 0.05  # Slightly above ground
	elif selection_circle:
		selection_circle.visible = false
	
	# Process auto-attack
	_process_auto_attack(delta)


func _input(event: InputEvent) -> void:
	# Don't process targeting input if chat is focused
	if _is_chat_focused():
		return
	
	# Tab to cycle targets
	if event.is_action_pressed("target_cycle"):
		cycle_next_target()
	
	# Escape to clear target and stop auto-attack
	if event.is_action_pressed("clear_target"):
		stop_auto_attack()
		clear_target()
	
	# Toggle auto-attack on current target (or start attacking nearest)
	if event.is_action_pressed("attack_target"):
		toggle_auto_attack()


## Check if chat input is currently focused
func _is_chat_focused() -> bool:
	var chat_ui = get_tree().get_first_node_in_group("chat_ui")
	if chat_ui and chat_ui.has_method("is_input_focused"):
		return chat_ui.call("is_input_focused")
	return false


## Select target at screen position (called by camera controller on click)
func select_target_at_position(screen_pos: Vector2) -> void:
	if not camera:
		return
	
	# Create ray from camera
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * RAY_LENGTH
	
	# Perform raycast
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		# Clicked on nothing - clear target
		clear_target()
		return
	
	var hit_node = result.collider
	
	# Check if we hit an enemy or player
	var entity_data = _get_entity_from_node(hit_node)
	
	if entity_data.is_empty():
		# Hit something that's not a targetable entity - clear target
		clear_target()
		return
	
	# Set the new target
	set_target(entity_data.id, entity_data.type, hit_node)


## Set target directly
func set_target(id: int, type: String, node: Node3D) -> void:
	# Don't target ourselves
	if type == "player" and local_player and id == local_player.get_player_id():
		clear_target()
		return
	
	current_target_id = id
	current_target_type = type
	current_target_node = node
	
	# Get full target data
	var target_data = get_target_data()
	
	# Update selection circle
	if selection_circle:
		selection_circle.visible = true
		selection_circle.global_position = node.global_position
		selection_circle.global_position.y = 0.05
		
		# Set color based on type
		if selection_circle.has_method("set_target_type"):
			selection_circle.set_target_type(type)
	
	emit_signal("target_changed", current_target_id, current_target_type, target_data)


## Clear current target
func clear_target() -> void:
	current_target_id = -1
	current_target_type = "none"
	current_target_node = null
	
	if selection_circle:
		selection_circle.visible = false
	
	emit_signal("target_changed", -1, "none", {})


## Cycle to next target (Tab targeting)
func cycle_next_target() -> void:
	if not game_manager or not local_player:
		return
	
	var player_pos = local_player.global_position
	var enemies = _get_nearby_enemies(player_pos, 30.0)
	
	if enemies.is_empty():
		clear_target()
		return
	
	# Sort by distance
	enemies.sort_custom(func(a, b): 
		var dist_a = player_pos.distance_to(a.node.global_position)
		var dist_b = player_pos.distance_to(b.node.global_position)
		return dist_a < dist_b
	)
	
	# Find current target in list and select next
	var current_index = -1
	for i in range(enemies.size()):
		if enemies[i].id == current_target_id:
			current_index = i
			break
	
	var next_index = (current_index + 1) % enemies.size()
	var next_enemy = enemies[next_index]
	
	set_target(next_enemy.id, "enemy", next_enemy.node)


## Attack the current target
func attack_current_target() -> void:
	if current_target_id == -1:
		emit_signal("show_message", "No target", "error")
		return
	
	if current_target_type != "enemy":
		emit_signal("show_message", "Cannot attack that target", "error")
		return
	
	if not local_player:
		return
	
	# Check range
	if current_target_node and is_instance_valid(current_target_node):
		var distance = local_player.global_position.distance_to(current_target_node.global_position)
		if distance > ATTACK_RANGE:
			emit_signal("show_message", "Out of range", "error")
			return
	
	# Send attack
	local_player.attack_target(current_target_id)


## Get current target data as dictionary
func get_target_data() -> Dictionary:
	if current_target_id == -1:
		return {}
	
	if current_target_type == "enemy" and game_manager:
		return game_manager.get_enemy_data(current_target_id)
	elif current_target_type == "player" and game_manager:
		return game_manager.get_player_data(current_target_id)
	
	return {}


## Check if we have a target
func has_target() -> bool:
	return current_target_id != -1


## Get entity info from a node (used for raycast hits)
func _get_entity_from_node(node: Node) -> Dictionary:
	if not game_manager:
		return {}
	
	# Check if it's an enemy
	var enemy_data = game_manager.get_enemy_by_node(node)
	if not enemy_data.is_empty():
		return {"id": enemy_data.id, "type": "enemy"}
	
	# Check if it's a remote player
	var player_data = game_manager.get_player_by_node(node)
	if not player_data.is_empty():
		return {"id": player_data.id, "type": "player"}
	
	return {}


## Get nearby enemies for Tab targeting
func _get_nearby_enemies(position: Vector3, radius: float) -> Array:
	if not game_manager:
		return []
	
	return game_manager.get_nearby_enemies(position, radius)


## Handle entity death - clear target if our target died
func _on_entity_died(entity_id: int, _killer_id: int) -> void:
	if entity_id == current_target_id:
		clear_target()
		# Try to auto-target next enemy if auto-attack was active
		if auto_attack_active:
			if not _auto_target_nearest_enemy():
				stop_auto_attack()
				emit_signal("show_message", "No more enemies", "info")


## Handle enemy despawn - clear target if our target despawned
func _on_enemy_despawned(id: int) -> void:
	if id == current_target_id:
		clear_target()
		# Try to auto-target next enemy if auto-attack was active
		if auto_attack_active:
			_auto_target_nearest_enemy()


# =============================================================================
# Auto-Attack System
# =============================================================================

## Toggle auto-attack on/off
func toggle_auto_attack() -> void:
	if auto_attack_active:
		stop_auto_attack()
	else:
		start_auto_attack()


## Start auto-attacking
func start_auto_attack() -> void:
	# If no target, try to get nearest enemy
	if current_target_id == -1 or current_target_type != "enemy":
		if not _auto_target_nearest_enemy():
			emit_signal("show_message", "No enemy target", "error")
			return
	
	# Verify we have a valid enemy target
	if current_target_type != "enemy":
		emit_signal("show_message", "Cannot attack that target", "error")
		return
	
	auto_attack_active = true
	
	# Immediately try to attack if cooldown is ready
	if attack_cooldown <= 0.0:
		_perform_auto_attack()
	
	emit_signal("auto_attack_changed", true)
	emit_signal("show_message", "Auto-attack ON", "info")


## Stop auto-attacking
func stop_auto_attack() -> void:
	if not auto_attack_active:
		return
	
	auto_attack_active = false
	attack_cooldown = 0.0
	emit_signal("auto_attack_changed", false)
	emit_signal("swing_timer_updated", 0.0, false)


## Process auto-attack each frame
func _process_auto_attack(delta: float) -> void:
	if not auto_attack_active:
		return
	
	# Update swing timer UI
	var progress = 1.0 - (attack_cooldown / ATTACK_SPEED)
	emit_signal("swing_timer_updated", clamp(progress, 0.0, 1.0), true)
	
	# Count down cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
		return
	
	# Cooldown ready - try to attack
	_perform_auto_attack()


## Perform a single auto-attack
func _perform_auto_attack() -> void:
	# Validate target still exists
	if current_target_id == -1 or current_target_type != "enemy":
		# Try to find new target
		if not _auto_target_nearest_enemy():
			stop_auto_attack()
			emit_signal("show_message", "No target", "error")
			return
	
	# Validate target node
	if not current_target_node or not is_instance_valid(current_target_node):
		# Try to get node from game manager
		if game_manager:
			var enemy_data = game_manager.get_enemy_data(current_target_id)
			if not enemy_data.is_empty() and enemy_data.has("node"):
				current_target_node = enemy_data["node"]
			else:
				# Enemy gone, try to find new target
				if not _auto_target_nearest_enemy():
					stop_auto_attack()
					return
	
	# Check range
	if not local_player:
		stop_auto_attack()
		return
	
	var distance = local_player.global_position.distance_to(current_target_node.global_position)
	if distance > ATTACK_RANGE:
		# Out of range - don't attack but keep auto-attack active
		# Reset cooldown to check again soon
		attack_cooldown = 0.25  # Check range every 0.25s
		emit_signal("swing_timer_updated", 0.0, true)  # Reset swing timer visual
		return
	
	# In range - attack!
	local_player.attack_target(current_target_id)
	
	# Start cooldown
	attack_cooldown = ATTACK_SPEED


## Auto-target the nearest enemy
func _auto_target_nearest_enemy() -> bool:
	if not game_manager or not local_player:
		return false
	
	var player_pos = local_player.global_position
	var enemies = _get_nearby_enemies(player_pos, AUTO_TARGET_RANGE)
	
	if enemies.is_empty():
		return false
	
	# Sort by distance and pick closest
	enemies.sort_custom(func(a, b): 
		var dist_a = player_pos.distance_to(a.node.global_position)
		var dist_b = player_pos.distance_to(b.node.global_position)
		return dist_a < dist_b
	)
	
	var nearest = enemies[0]
	set_target(nearest.id, "enemy", nearest.node)
	return true


## Check if auto-attack is currently active
func is_auto_attacking() -> bool:
	return auto_attack_active


## Get current attack cooldown progress (0.0 to 1.0)
func get_swing_progress() -> float:
	if not auto_attack_active or attack_cooldown <= 0.0:
		return 1.0
	return 1.0 - (attack_cooldown / ATTACK_SPEED)
