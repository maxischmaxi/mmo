extends Node
## Game Manager - handles spawning entities and processing world state.
## Also manages the login -> character select -> game flow.

## Scenes to instantiate
const RemotePlayerScene = preload("res://scenes/player/remote_player.tscn")
const WorldHealthBarScene = preload("res://scenes/ui/world_health_bar.tscn")
const DamageNumberScene = preload("res://scenes/effects/damage_number.tscn")
const CharacterSelectScene = preload("res://scenes/ui/character_select_3d.tscn")
const CharacterCreateScene = preload("res://scenes/ui/character_create.tscn")

## Game state enum
enum GameState { LOGIN, CHARACTER_SELECT, CHARACTER_CREATE, IN_GAME }

## Current game state
var current_state: GameState = GameState.LOGIN

## Reference to the local player
var local_player: Node = null

## Reference to login screen
var login_screen: Control = null

## Reference to character select screen
var character_select_screen: Control = null

## Reference to character create screen
var character_create_screen: Control = null

## Reference to game UI container
var game_ui: Control = null

## Reference to UI container (for adding character screens)
var ui_container: CanvasLayer = null

## Reference to loading screen
var loading_screen: Control = null

## Dictionary of remote players by ID
var remote_players: Dictionary = {}

## Dictionary of enemies by ID
var enemies: Dictionary = {}

## Dictionary of world items by entity ID
var world_items: Dictionary = {}

## Damage number pool
var damage_number_pool: Array[DamageNumber] = []
const DAMAGE_NUMBER_POOL_SIZE: int = 20

## Container nodes
@onready var players_container: Node3D = $PlayersContainer
@onready var enemies_container: Node3D = $EnemiesContainer
@onready var items_container: Node3D = $ItemsContainer
@onready var effects_container: Node3D = $EffectsContainer

## Reference to day/night controller
var day_night_controller: Node3D = null


func _ready() -> void:
	# Add to group for easy finding
	add_to_group("game_manager")
	
	# Create effects container if it doesn't exist
	if not effects_container:
		effects_container = Node3D.new()
		effects_container.name = "EffectsContainer"
		add_child(effects_container)
	
	# Initialize damage number pool
	_init_damage_number_pool()
	
	# Find the local player
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		local_player = get_node_or_null("../Player")
	
	# Find UI elements
	ui_container = get_node_or_null("../UI")
	login_screen = get_node_or_null("../UI/LoginScreen")
	game_ui = get_node_or_null("../UI/GameUI")
	loading_screen = get_node_or_null("../UI/LoadingScreen")
	
	if not ui_container:
		push_error("GameManager: Could not find UI container at ../UI")
	else:
		print("GameManager: UI container found at ", ui_container.get_path())
	
	# Connect login screen to player
	if login_screen and local_player:
		login_screen.set_player(local_player)
		login_screen.login_success.connect(_on_login_success)
	
	if local_player:
		# Connect to player signals
		local_player.connect("player_spawned", _on_player_spawned)
		local_player.connect("player_despawned", _on_player_despawned)
		local_player.connect("enemy_spawned", _on_enemy_spawned)
		local_player.connect("chat_received", _on_chat_received)
		local_player.connect("damage_dealt", _on_damage_dealt)
		local_player.connect("disconnected", _on_disconnected)
		local_player.connect("connection_failed", _on_connection_failed)
		
		# Connect to auth signals
		if local_player.has_signal("login_success"):
			local_player.connect("login_success", _on_player_login_success)
		
		# Connect to character selection signals
		if local_player.has_signal("character_selected"):
			local_player.connect("character_selected", _on_character_selected)
		
		# Connect to new signals for targeting support
		if local_player.has_signal("enemy_despawned"):
			local_player.connect("enemy_despawned", _on_enemy_despawned)
		if local_player.has_signal("entity_died"):
			local_player.connect("entity_died", _on_entity_died)
		
		# Connect to world state update signals for entity movement sync
		if local_player.has_signal("enemy_state_updated"):
			local_player.connect("enemy_state_updated", _on_enemy_state_updated)
		if local_player.has_signal("player_state_updated"):
			local_player.connect("player_state_updated", _on_player_state_updated)
		
		# Connect time sync signal for day/night cycle
		if local_player.has_signal("time_sync"):
			local_player.connect("time_sync", _on_time_sync)
		
		# Connect zone change signal to clear entities
		if local_player.has_signal("zone_change"):
			local_player.connect("zone_change", _on_zone_change)
		
		print("GameManager: Connected to local player signals")
	else:
		push_error("GameManager: Could not find local player!")
	
	# Find day/night controller
	day_night_controller = get_node_or_null("../DayNightController")
	if day_night_controller:
		print("GameManager: Found DayNightController")
	
	# Start with login screen visible, game UI hidden
	_change_state(GameState.LOGIN)


## Interpolation speed for smooth entity movement
const INTERPOLATION_SPEED: float = 10.0


func _process(delta: float) -> void:
	# Interpolate enemy positions for smooth movement
	for id in enemies:
		var enemy_data = enemies[id]
		var node = enemy_data["node"] as Node3D
		
		if enemy_data.has("target_position"):
			var target_pos: Vector3 = enemy_data["target_position"]
			node.global_position = node.global_position.lerp(target_pos, INTERPOLATION_SPEED * delta)
		
		if enemy_data.has("target_rotation"):
			var target_rot: float = enemy_data["target_rotation"]
			node.rotation.y = lerp_angle(node.rotation.y, target_rot, INTERPOLATION_SPEED * delta)
	
	# Interpolate remote player positions for smooth movement
	for id in remote_players:
		var player_data = remote_players[id]
		var node = player_data["node"] as Node3D
		
		if player_data.has("target_position"):
			var target_pos: Vector3 = player_data["target_position"]
			node.global_position = node.global_position.lerp(target_pos, INTERPOLATION_SPEED * delta)
		
		if player_data.has("target_rotation"):
			var target_rot: float = player_data["target_rotation"]
			node.rotation.y = lerp_angle(node.rotation.y, target_rot, INTERPOLATION_SPEED * delta)


func _init_damage_number_pool() -> void:
	for i in range(DAMAGE_NUMBER_POOL_SIZE):
		var damage_number = DamageNumberScene.instantiate() as DamageNumber
		damage_number.visible = false
		effects_container.add_child(damage_number)
		damage_number_pool.append(damage_number)


func _get_damage_number() -> DamageNumber:
	# Find an inactive damage number in the pool
	for dn in damage_number_pool:
		if not dn.is_animating():
			return dn
	
	# All in use, create a new one (and add to pool for future use)
	var damage_number = DamageNumberScene.instantiate() as DamageNumber
	effects_container.add_child(damage_number)
	damage_number_pool.append(damage_number)
	return damage_number


func _change_state(new_state: GameState) -> void:
	"""Change game state and update UI visibility."""
	current_state = new_state
	
	# Hide all screens
	if login_screen:
		login_screen.visible = false
	if character_select_screen:
		character_select_screen.visible = false
	if character_create_screen:
		character_create_screen.visible = false
	if game_ui:
		game_ui.visible = false
	
	# Show appropriate screen
	match new_state:
		GameState.LOGIN:
			if login_screen:
				login_screen.visible = true
				# Clear form fields (except remembered username) when returning to login
				if login_screen.has_method("clear_form"):
					login_screen.clear_form()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
		GameState.CHARACTER_SELECT:
			_ensure_character_select_screen()
			if character_select_screen:
				character_select_screen.visible = true
				character_select_screen.request_character_list()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
		GameState.CHARACTER_CREATE:
			_ensure_character_create_screen()
			if character_create_screen:
				character_create_screen.visible = true
				character_create_screen.reset_form()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
		GameState.IN_GAME:
			if game_ui:
				game_ui.visible = true
			# Reset any pending click-to-move or mouse state from UI interactions
			_reset_player_input_state()


func _reset_player_input_state() -> void:
	"""Reset player input state to prevent residual UI clicks from triggering movement."""
	if not local_player:
		return
	
	# Reset camera controller mouse state
	var camera_controller = local_player.get_node_or_null("CameraController")
	if camera_controller and camera_controller.has_method("reset_mouse_state"):
		camera_controller.reset_mouse_state()
	
	# Cancel any pending click-to-move
	var click_movement = local_player.get_node_or_null("ClickMovementController")
	if click_movement and click_movement.has_method("cancel_movement"):
		click_movement.cancel_movement()


func _ensure_character_select_screen() -> void:
	"""Create character select screen if it doesn't exist."""
	if character_select_screen:
		return
	
	character_select_screen = CharacterSelectScene.instantiate()
	if ui_container:
		ui_container.add_child(character_select_screen)
		print("GameManager: CharacterSelect3D added to UI container")
	else:
		push_error("GameManager: UI container not found! Adding CharacterSelect3D to GameManager instead.")
		add_child(character_select_screen)
	
	# Connect signals
	character_select_screen.set_player(local_player)
	character_select_screen.character_selected.connect(_on_character_screen_selected)
	character_select_screen.create_new_character.connect(_on_create_new_character)
	character_select_screen.back_to_login.connect(_on_back_to_login)


func _ensure_character_create_screen() -> void:
	"""Create character create screen if it doesn't exist."""
	if character_create_screen:
		return
	
	character_create_screen = CharacterCreateScene.instantiate()
	if ui_container:
		ui_container.add_child(character_create_screen)
	else:
		add_child(character_create_screen)
	
	# Connect signals
	character_create_screen.set_player(local_player)
	character_create_screen.character_created.connect(_on_character_created)
	character_create_screen.back_to_select.connect(_on_back_to_character_select)


func _on_login_success(_player_id: int) -> void:
	"""Handle successful login from login screen - go to character select."""
	print("GameManager: Login successful, showing character select")
	_change_state(GameState.CHARACTER_SELECT)


func _on_player_login_success(_player_id: int) -> void:
	"""Handle login success signal from player - go to character select."""
	print("GameManager: Player logged in, showing character select")
	_change_state(GameState.CHARACTER_SELECT)


func _on_character_screen_selected(_character_id: int) -> void:
	"""Handle character selected from character select screen."""
	# Wait for character_selected signal from player to enter game
	pass


func _on_character_selected(_character_id: int) -> void:
	"""Handle character selected signal from player - enter game."""
	print("GameManager: Character selected, entering game")
	
	# Show loading screen FIRST before hiding character select
	# This prevents the "flying character" visual glitch where the player
	# appears floating in empty space before the zone loads
	if loading_screen and loading_screen.has_method("fade_in"):
		loading_screen.fade_in()
		await loading_screen.fade_finished
	
	# Now transition to game state (hides character select, shows game UI)
	_change_state(GameState.IN_GAME)


func _on_create_new_character() -> void:
	"""Handle create new character button."""
	_change_state(GameState.CHARACTER_CREATE)


func _on_character_created() -> void:
	"""Handle character created - go back to character select."""
	_change_state(GameState.CHARACTER_SELECT)


func _on_back_to_login() -> void:
	"""Handle back to login from character select."""
	_change_state(GameState.LOGIN)


func _on_back_to_character_select() -> void:
	"""Handle back to character select from character create."""
	_change_state(GameState.CHARACTER_SELECT)


func _on_disconnected() -> void:
	print("GameManager: Disconnected from server")
	# Clean up all remote entities
	for id in remote_players.keys():
		_remove_remote_player(id)
	for id in enemies.keys():
		_remove_enemy(id)
	
	# Show login screen again
	_change_state(GameState.LOGIN)


func _on_connection_failed(reason: String) -> void:
	push_error("GameManager: Connection failed - ", reason)


func _on_player_spawned(id: int, name: String, class_id: int, gender_id: int, empire_id: int, position: Vector3) -> void:
	# Don't spawn ourselves
	if local_player and id == local_player.get_player_id():
		return
	
	# Don't duplicate
	if remote_players.has(id):
		return
	
	print("GameManager: Spawning remote player ", name, " (ID: ", id, ", Class: ", class_id, ") at ", position)
	
	var remote_player = RemotePlayerScene.instantiate()
	remote_player.set_player_info(id, name)
	
	# Add health bar above player
	var health_bar = WorldHealthBarScene.instantiate() as WorldHealthBar
	health_bar.position = Vector3(0, 2.5, 0)
	health_bar.set_entity_name(name)
	health_bar.set_health(100, 100)
	remote_player.add_child(health_bar)
	
	# Add to scene tree FIRST, then set global_position
	if players_container:
		players_container.add_child(remote_player)
	else:
		add_child(remote_player)
	
	# Now we can set global_position since it's in the tree
	remote_player.global_position = position
	
	remote_players[id] = {
		"id": id,
		"node": remote_player,
		"name": name,
		"class": class_id,
		"gender": gender_id,
		"empire": empire_id,
		"health_bar": health_bar,
		"health": 100,
		"max_health": 100,
		"level": 1,
		"target_position": position,
		"target_rotation": 0.0
	}


func _on_player_despawned(id: int) -> void:
	print("GameManager: Despawning player ID ", id)
	_remove_remote_player(id)


func _remove_remote_player(id: int) -> void:
	if remote_players.has(id):
		var data = remote_players[id]
		data["node"].queue_free()
		remote_players.erase(id)


func _on_enemy_spawned(id: int, enemy_type: int, position: Vector3, health: int, max_health: int, level: int = 1) -> void:
	if enemies.has(id):
		return
	
	var enemy_name = _get_enemy_name(enemy_type)
	print("GameManager: Spawning ", enemy_name, " Lv.", level, " (ID: ", id, ") at ", position)
	
	var enemy = _create_enemy_placeholder(enemy_type)
	
	# Add health bar above enemy
	var health_bar = WorldHealthBarScene.instantiate() as WorldHealthBar
	health_bar.position = Vector3(0, 1.8, 0)
	health_bar.set_entity_name(enemy_name + " Lv." + str(level))
	health_bar.set_health(health, max_health)
	enemy.add_child(health_bar)
	
	# Add to scene tree FIRST, then set global_position
	if enemies_container:
		enemies_container.add_child(enemy)
	else:
		add_child(enemy)
	
	# Now we can set global_position since it's in the tree
	enemy.global_position = position
	
	enemies[id] = {
		"id": id,
		"node": enemy,
		"type": enemy_type,
		"name": enemy_name,
		"level": level,
		"health": health,
		"max_health": max_health,
		"health_bar": health_bar,
		"target_position": position,
		"target_rotation": 0.0
	}


func _on_enemy_despawned(id: int) -> void:
	print("GameManager: Despawning enemy ID ", id)
	_remove_enemy(id)


func _on_entity_died(entity_id: int, _killer_id: int) -> void:
	# Entity death is handled - could show death animation here
	print("GameManager: Entity ", entity_id, " died")


func _get_enemy_name(enemy_type: int) -> String:
	match enemy_type:
		0: return "Goblin"
		1: return "Skeleton"
		2: return "Wolf"
		_: return "Enemy"


func _create_enemy_placeholder(enemy_type: int) -> Node3D:
	var enemy = CharacterBody3D.new()
	
	# Create mesh
	var mesh_instance = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.2
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.6
	
	# Color based on type
	var material = StandardMaterial3D.new()
	match enemy_type:
		0:  # Goblin
			material.albedo_color = Color(0.2, 0.8, 0.2)
		1:  # Skeleton
			material.albedo_color = Color(0.9, 0.9, 0.8)
		2:  # Wolf
			material.albedo_color = Color(0.5, 0.4, 0.3)
		_:
			material.albedo_color = Color(1, 0, 1)
	mesh_instance.material_override = material
	
	enemy.add_child(mesh_instance)
	
	# Add collision
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.2
	collision.shape = shape
	collision.position.y = 0.6
	enemy.add_child(collision)
	
	return enemy


func _remove_enemy(id: int) -> void:
	if enemies.has(id):
		var enemy_data = enemies[id]
		enemy_data["node"].queue_free()
		enemies.erase(id)


func _on_chat_received(sender_name: String, content: String) -> void:
	print("[Chat] ", sender_name, ": ", content)
	# Chat UI handles this via its own signal connection


func _on_damage_dealt(attacker_id: int, target_id: int, damage: int, is_critical: bool) -> void:
	var crit_str = " (CRIT!)" if is_critical else ""
	print("Damage: ", attacker_id, " -> ", target_id, " for ", damage, crit_str)
	
	# Get target position for damage number
	var target_pos: Vector3 = Vector3.ZERO
	var target_found: bool = false
	
	# Check if target is an enemy
	if enemies.has(target_id):
		var enemy_data = enemies[target_id]
		enemy_data["health"] = max(0, enemy_data["health"] - damage)
		
		# Update health bar
		if enemy_data.has("health_bar"):
			enemy_data["health_bar"].set_health(enemy_data["health"], enemy_data["max_health"])
		
		target_pos = enemy_data["node"].global_position + Vector3(0, 1.0, 0)
		target_found = true
	
	# Check if target is a remote player
	if remote_players.has(target_id):
		var player_data = remote_players[target_id]
		player_data["health"] = max(0, player_data["health"] - damage)
		
		# Update health bar
		if player_data.has("health_bar"):
			player_data["health_bar"].set_health(player_data["health"], player_data["max_health"])
		
		target_pos = player_data["node"].global_position + Vector3(0, 1.5, 0)
		target_found = true
	
	# Check if target is local player
	if local_player and target_id == local_player.get_player_id():
		target_pos = local_player.global_position + Vector3(0, 1.5, 0)
		target_found = true
		# TODO: Update player HUD health
	
	# Spawn damage number
	if target_found:
		var damage_number = _get_damage_number()
		damage_number.show_damage(target_pos, damage, is_critical)


## Update remote player position from world state (with interpolation)
func update_remote_player(id: int, position: Vector3, rotation: float, health: int = -1, animation_state: int = -1, weapon_id: int = -1) -> void:
	if remote_players.has(id):
		var data = remote_players[id]
		
		# Store target position/rotation for interpolation
		data["target_position"] = position
		data["target_rotation"] = rotation
		
		# Update health if provided
		if health >= 0:
			data["health"] = health
			if data.has("health_bar"):
				data["health_bar"].set_health(health, data["max_health"])
		
		# Update animation state and weapon on the remote player node
		var remote_player_node = data["node"]
		if remote_player_node and remote_player_node.has_method("update_from_server"):
			remote_player_node.update_from_server(position, rotation, animation_state, weapon_id)


## Update enemy position from world state (with interpolation)
func update_enemy(id: int, position: Vector3, rotation: float, health: int) -> void:
	if enemies.has(id):
		var enemy_data = enemies[id]
		
		# Store target position/rotation for interpolation
		enemy_data["target_position"] = position
		enemy_data["target_rotation"] = rotation
		enemy_data["health"] = health
		
		# Update health bar
		if enemy_data.has("health_bar"):
			enemy_data["health_bar"].set_health(health, enemy_data["max_health"])


# =============================================================================
# Targeting System Support Methods
# =============================================================================

## Get enemy data by ID (for targeting system)
func get_enemy_data(id: int) -> Dictionary:
	if enemies.has(id):
		return enemies[id].duplicate()
	return {}


## Get player data by ID (for targeting system)
func get_player_data(id: int) -> Dictionary:
	if remote_players.has(id):
		return remote_players[id].duplicate()
	return {}


## Get enemy by node reference (for raycast hit detection)
func get_enemy_by_node(node: Node) -> Dictionary:
	for id in enemies:
		var data = enemies[id]
		if data["node"] == node or data["node"].is_ancestor_of(node):
			return data.duplicate()
	return {}


## Get player by node reference (for raycast hit detection)
func get_player_by_node(node: Node) -> Dictionary:
	for id in remote_players:
		var data = remote_players[id]
		if data["node"] == node or data["node"].is_ancestor_of(node):
			return data.duplicate()
	return {}


## Get nearby enemies within radius (for Tab targeting)
func get_nearby_enemies(position: Vector3, radius: float) -> Array:
	var nearby = []
	for id in enemies:
		var data = enemies[id]
		var enemy_pos = data["node"].global_position
		var distance = position.distance_to(enemy_pos)
		if distance <= radius:
			nearby.append({
				"id": id,
				"node": data["node"],
				"distance": distance,
				"data": data.duplicate()
			})
	return nearby


## Get all enemies
func get_all_enemies() -> Dictionary:
	return enemies.duplicate()


## Get all remote players
func get_all_players() -> Dictionary:
	return remote_players.duplicate()


# =============================================================================
# World State Update Handlers
# =============================================================================

## Handle enemy state update from WorldState
func _on_enemy_state_updated(id: int, position: Vector3, rotation: float, health: int) -> void:
	update_enemy(id, position, rotation, health)


## Handle remote player state update from WorldState
func _on_player_state_updated(id: int, position: Vector3, rotation: float, health: int, animation_state: int = 0, weapon_id: int = -1) -> void:
	update_remote_player(id, position, rotation, health, animation_state, weapon_id)


# =============================================================================
# Zone Change Support
# =============================================================================

## Handle zone change - clear all remote entities since they're in a different zone now
func _on_zone_change(_zone_id: int, _zone_name: String, _scene_path: String, _spawn_x: float, _spawn_y: float, _spawn_z: float) -> void:
	print("GameManager: Zone change detected, clearing remote entities")
	
	# Clear all remote players - they were in the old zone
	for id in remote_players.keys():
		_remove_remote_player(id)
	remote_players.clear()
	
	# Clear all enemies - they were in the old zone
	for id in enemies.keys():
		_remove_enemy(id)
	enemies.clear()
	
	# Clear world items
	for id in world_items.keys():
		if world_items[id].has("node"):
			world_items[id]["node"].queue_free()
	world_items.clear()
	
	# Clear targeting if any
	var targeting_system = get_tree().get_first_node_in_group("targeting_system")
	if targeting_system and targeting_system.has_method("clear_target"):
		targeting_system.clear_target()
	
	print("GameManager: Cleared ", remote_players.size(), " players, ", enemies.size(), " enemies")


# =============================================================================
# Day/Night Cycle Support
# =============================================================================

## Handle time sync from server
func _on_time_sync(unix_timestamp: int, latitude: float, longitude: float) -> void:
	print("GameManager: Received time sync - timestamp: ", unix_timestamp, ", lat: ", latitude, ", lon: ", longitude)
	if day_night_controller:
		day_night_controller.on_time_sync(unix_timestamp, latitude, longitude)


## Get the day/night controller reference (for dev menu)
func get_day_night_controller() -> Node3D:
	return day_night_controller



