extends Node
class_name TargetingSystem
## WoW-style targeting system for selecting enemies and players.
## Works with CombatController for actual combat logic.

## Signal emitted when target changes
signal target_changed(target_id: int, target_type: String, target_data: Dictionary)

## Signal emitted when we need to show a UI message
signal show_message(message: String, message_type: String)

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

## Reference to combat controller
var combat_controller: Node = null

## Selection circle instance
var selection_circle: Node3D = null
const SelectionCircleScene = preload("res://scenes/effects/selection_circle.tscn")

## Tab targeting range
const TAB_TARGET_RANGE: float = 30.0


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
			# Connect to camera signals
			if camera_controller.has_signal("enemy_clicked"):
				camera_controller.enemy_clicked.connect(_on_enemy_clicked)
			if camera_controller.has_signal("entity_clicked"):
				camera_controller.entity_clicked.connect(_on_entity_clicked)
			if camera_controller.has_signal("clicked_nothing"):
				camera_controller.clicked_nothing.connect(_on_clicked_nothing)
	
	# Find combat controller
	if local_player:
		combat_controller = local_player.get_node_or_null("CombatController")
	
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


func _process(_delta: float) -> void:
	# Early exit if selection circle isn't visible - no work to do
	if not selection_circle or not selection_circle.visible:
		return
	
	# Update selection circle position to follow target
	if current_target_node and is_instance_valid(current_target_node):
		selection_circle.global_position = current_target_node.global_position
		selection_circle.global_position.y = 0.05  # Slightly above ground
	else:
		# Target no longer valid, hide selection circle
		selection_circle.visible = false


func _input(event: InputEvent) -> void:
	# Only process game inputs when actually in game
	if not _is_in_game():
		return
	
	# Don't process targeting input if chat is focused
	if _is_chat_focused():
		return
	
	# Tab to cycle targets
	if event.is_action_pressed("target_cycle"):
		cycle_next_target()
	
	# Escape to clear target
	if event.is_action_pressed("clear_target"):
		clear_target()


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	return UIManager.is_in_game()


## Check if chat input is currently focused
func _is_chat_focused() -> bool:
	return UIManager.is_chat_focused()


## Called when enemy is clicked (from camera controller)
func _on_enemy_clicked(enemy_id: int, enemy_node: Node3D) -> void:
	set_target(enemy_id, "enemy", enemy_node)


## Called when entity is clicked for selection (from camera controller)
func _on_entity_clicked(entity_id: int, entity_type: String, entity_node: Node3D) -> void:
	set_target(entity_id, entity_type, entity_node)


## Called when clicking on nothing (from camera controller)
func _on_clicked_nothing() -> void:
	clear_target()


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
	
	# Also stop auto-attack in combat controller
	if combat_controller:
		combat_controller.stop_auto_attack()
	
	emit_signal("target_changed", -1, "none", {})


## Cycle to next target (Tab targeting)
func cycle_next_target() -> void:
	if not game_manager or not local_player:
		return
	
	var player_pos = local_player.global_position
	var enemies = _get_nearby_enemies(player_pos, TAB_TARGET_RANGE)
	
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


## Get current target ID
func get_current_target_id() -> int:
	return current_target_id


## Get current target node
func get_current_target_node() -> Node3D:
	return current_target_node


## Get nearby enemies for Tab targeting
func _get_nearby_enemies(position: Vector3, radius: float) -> Array:
	if not game_manager:
		return []
	
	return game_manager.get_nearby_enemies(position, radius)


## Handle entity death - clear target if our target died
func _on_entity_died(entity_id: int, _killer_id: int) -> void:
	if entity_id == current_target_id:
		clear_target()
		emit_signal("show_message", "Target died", "info")


## Handle enemy despawn - clear target if our target despawned
func _on_enemy_despawned(id: int) -> void:
	if id == current_target_id:
		clear_target()
