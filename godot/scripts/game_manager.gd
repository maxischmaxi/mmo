extends Node
## Game Manager - handles spawning entities and processing world state.
## Also manages the login -> character select -> game flow.

## Scenes to instantiate
const RemotePlayerScene = preload("res://scenes/player/remote_player.tscn")
const WorldHealthBarScene = preload("res://scenes/ui/world_health_bar.tscn")
const DamageNumberScene = preload("res://scenes/effects/damage_number.tscn")
const CharacterSelectScene = preload("res://scenes/ui/character_select_3d.tscn")
const CharacterCreateScene = preload("res://scenes/ui/character_create.tscn")

## Enemy model scenes - loaded dynamically based on type
## Key: enemy_type (int), Value: PackedScene path
const ENEMY_SCENES := {
	# 0: "res://scenes/enemies/goblin.tscn",  # TODO: Add goblin model
	# 1: "res://scenes/enemies/skeleton.tscn",  # TODO: Add skeleton model
	2: "res://scenes/enemies/mutant.tscn",  # Mutant - elite dangerous enemy
	3: "res://scenes/enemies/wolf.tscn",    # Wolf - pack predator
}

## NPC model scenes - loaded dynamically based on type
## Key: npc_type (int), Value: PackedScene path
const NPC_SCENES := {
	0: "res://scenes/npcs/old_man.tscn",  # Old Man NPC
}

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

## Dictionary of NPCs by ID
var npcs: Dictionary = {}

## Dictionary of world items by entity ID
var world_items: Dictionary = {}

## Damage number pool
var damage_number_pool: Array[DamageNumber] = []
const DAMAGE_NUMBER_POOL_SIZE: int = 20

## Container nodes
@onready var players_container: Node3D = $PlayersContainer
@onready var enemies_container: Node3D = $EnemiesContainer
@onready var npcs_container: Node3D = $NpcsContainer
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
		
		# Connect to NPC signals
		if local_player.has_signal("npc_state_updated"):
			local_player.connect("npc_state_updated", _on_npc_state_updated)
		
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
	# Early exit if no entities to interpolate - avoids unnecessary loop overhead
	if enemies.is_empty() and remote_players.is_empty() and npcs.is_empty():
		return
	
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
	
	# Interpolate NPC positions for smooth movement (for future roaming support)
	for id in npcs:
		var npc_data = npcs[id]
		var node = npc_data["node"] as Node3D
		
		if npc_data.has("target_position"):
			var target_pos: Vector3 = npc_data["target_position"]
			node.global_position = node.global_position.lerp(target_pos, INTERPOLATION_SPEED * delta)
		
		if npc_data.has("target_rotation"):
			var target_rot: float = npc_data["target_rotation"]
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
			# Hide game world during login, but keep sky visible for atmosphere
			_set_game_world_visible(false, true)
		
		GameState.CHARACTER_SELECT:
			_ensure_character_select_screen()
			if character_select_screen:
				character_select_screen.visible = true
				character_select_screen.request_character_list()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			# Hide game world during character select, but keep sky visible
			_set_game_world_visible(false, true)
		
		GameState.CHARACTER_CREATE:
			_ensure_character_create_screen()
			if character_create_screen:
				character_create_screen.visible = true
				character_create_screen.reset_form()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			# Hide game world during character create, but keep sky visible
			_set_game_world_visible(false, true)
		
		GameState.IN_GAME:
			if game_ui:
				game_ui.visible = true
			# Show game world when entering game
			_set_game_world_visible(true)
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


## Stored player position when hidden (to restore later)
var _stored_player_position: Vector3 = Vector3.ZERO

## Stored reference to CharacterModel when removed from tree
var _stored_character_model: Node3D = null

func _set_game_world_visible(vis: bool, keep_sky: bool = false) -> void:
	"""Show or hide the game world (player, camera, entities).
	
	This ensures COMPLETE separation between character select/create screens
	and the actual game world. The character select screen has its own
	SubViewport with its own camera for character preview.
	
	When hiding, the player's CharacterModel is actually REMOVED from the scene
	tree (not just made invisible) to guarantee it cannot be rendered by any camera.
	
	Args:
		vis: Whether to show the game world
		keep_sky: If true, keeps the DayNightController visible (for sky/sun/moon backdrop)
	"""
	# Hide/show the local player (and its camera)
	if local_player:
		var char_model = local_player.get_node_or_null("CharacterModel")
		
		if vis:
			# Restore player visibility
			local_player.visible = true
			local_player.process_mode = Node.PROCESS_MODE_INHERIT
			# Position will be set by zone loading, no need to restore here
			
			# Re-add CharacterModel to player if it was removed
			if _stored_character_model and not _stored_character_model.get_parent():
				local_player.add_child(_stored_character_model)
				# Move it to be the first child (after CollisionShape3D) for proper ordering
				local_player.move_child(_stored_character_model, 1)
				print("[GameManager] CharacterModel re-added to player")
			_stored_character_model = null
			
			# Ensure CharacterModel is visible
			char_model = local_player.get_node_or_null("CharacterModel")
			if char_model:
				char_model.visible = true
				var rig = char_model.get_node_or_null("Rig")
				if rig:
					rig.visible = true
		else:
			# Store position and move player far away
			_stored_player_position = local_player.global_position
			local_player.visible = false
			local_player.global_position = Vector3(0, -1000, 0)
			# NOTE: We do NOT disable processing here because the player needs to
			# continue polling the network for login/character list responses.
			
			# COMPLETELY REMOVE the CharacterModel from the scene tree
			# This guarantees it cannot be rendered by ANY camera
			if char_model and char_model.get_parent():
				_stored_character_model = char_model
				local_player.remove_child(char_model)
				print("[GameManager] CharacterModel removed from player tree")
		
		# Also disable/enable the player's camera
		var camera = local_player.get_node_or_null("CameraController/SpringArm3D/Camera3D")
		if camera and camera is Camera3D:
			camera.current = vis
		
		print("[GameManager] Player visibility set to %s, position: %s" % [vis, local_player.global_position])
	
	# Hide/show the day/night controller (includes sun, moon, world environment)
	# Keep it visible if keep_sky is true (for character select backdrop)
	if day_night_controller:
		day_night_controller.visible = vis or keep_sky
	
	# Hide/show entity containers (remote players, enemies, items, effects)
	if players_container:
		players_container.visible = vis
	if enemies_container:
		enemies_container.visible = vis
	if items_container:
		items_container.visible = vis
	if effects_container:
		effects_container.visible = vis


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
	
	var enemy = _create_enemy(enemy_type)
	
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
		2: return "Mutant"
		3: return "Wolf"
		_: return "Enemy"


## Create an enemy with the appropriate model (or placeholder if model not available)
func _create_enemy(enemy_type: int) -> Node3D:
	# Check if we have a model scene for this enemy type
	if ENEMY_SCENES.has(enemy_type):
		var scene_path: String = ENEMY_SCENES[enemy_type]
		if ResourceLoader.exists(scene_path):
			var scene = load(scene_path) as PackedScene
			if scene:
				var enemy_model = scene.instantiate()
				
				# Wrap in CharacterBody3D for physics/collision
				var enemy = CharacterBody3D.new()
				enemy.add_child(enemy_model)
				
				# Initialize the enemy model with its type
				if enemy_model.has_method("initialize_enemy"):
					enemy_model.initialize_enemy(enemy_type)
				
				# Add collision shape
				var collision = CollisionShape3D.new()
				var shape = CapsuleShape3D.new()
				shape.radius = 0.5
				shape.height = 2.0
				collision.shape = shape
				collision.position.y = 1.0
				enemy.add_child(collision)
				
				# Store reference to model for animation updates
				enemy.set_meta("enemy_model", enemy_model)
				
				# Set enemy to layer 2 (bit 1) so minimap can exclude it
				_set_visual_layer_recursive(enemy, 2)
				
				return enemy
	
	# Fallback to placeholder
	return _create_enemy_placeholder(enemy_type)


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
		2:  # Mutant
			material.albedo_color = Color(0.6, 0.3, 0.5)
		3:  # Wolf
			material.albedo_color = Color(0.5, 0.4, 0.3)  # Brown/gray
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
	
	# Set enemy to layer 2 (bit 1) so minimap can exclude it
	_set_visual_layer_recursive(enemy, 2)
	
	return enemy


func _remove_enemy(id: int) -> void:
	if enemies.has(id):
		var enemy_data = enemies[id]
		enemy_data["node"].queue_free()
		enemies.erase(id)


## Set visual layer for a node and all its children recursively.
## Used to put enemies on layer 2 so minimap can exclude them.
func _set_visual_layer_recursive(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		# Set only this layer (clear layer 1, set layer 2)
		node.layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_visual_layer_recursive(child, layer)


# =============================================================================
# NPC Handling
# =============================================================================

## Handle NPC state update from WorldState
## NPCs are spawned on first update (no separate spawn signal like enemies)
func _on_npc_state_updated(id: int, position: Vector3, rotation: float, animation_state: int = 0) -> void:
	if npcs.has(id):
		# Update existing NPC
		update_npc(id, position, rotation, animation_state)
	else:
		# First time seeing this NPC - spawn it
		# Extract npc_type from the ID range (NPCs start at 30000)
		# For now, all NPCs are type 0 (Old Man) until we have more types
		_spawn_npc(id, 0, position, rotation)


## Spawn an NPC
func _spawn_npc(id: int, npc_type: int, position: Vector3, rotation: float) -> void:
	if npcs.has(id):
		return
	
	var npc_name := _get_npc_name(npc_type)
	print("GameManager: Spawning NPC ", npc_name, " (ID: ", id, ") at ", position)
	
	var npc := _create_npc(npc_type)
	if not npc:
		push_warning("GameManager: Failed to create NPC of type %d" % npc_type)
		return
	
	# Add to scene tree first, then set position
	if npcs_container:
		npcs_container.add_child(npc)
	else:
		add_child(npc)
	
	npc.global_position = position
	npc.rotation.y = rotation
	
	npcs[id] = {
		"id": id,
		"node": npc,
		"type": npc_type,
		"name": npc_name,
		"target_position": position,
		"target_rotation": rotation,
	}


## Create an NPC with the appropriate model
func _create_npc(npc_type: int) -> Node3D:
	# Check if we have a scene for this NPC type
	if NPC_SCENES.has(npc_type):
		var scene_path: String = NPC_SCENES[npc_type]
		if ResourceLoader.exists(scene_path):
			var scene = load(scene_path) as PackedScene
			if scene:
				var npc_model = scene.instantiate()
				
				# Wrap in a simple Node3D (NPCs don't need physics)
				var npc = Node3D.new()
				npc.add_child(npc_model)
				
				# Initialize the NPC model with its type
				if npc_model.has_method("initialize_npc"):
					npc_model.initialize_npc(npc_type)
				
				# Store reference to model for animation updates
				npc.set_meta("npc_model", npc_model)
				
				# Set NPC to layer 2 (bit 1) so minimap can exclude it
				_set_visual_layer_recursive(npc, 2)
				
				return npc
	
	# Fallback to placeholder
	return _create_npc_placeholder(npc_type)


## Create a placeholder NPC (capsule)
func _create_npc_placeholder(npc_type: int) -> Node3D:
	var npc = Node3D.new()
	
	# Create mesh
	var mesh_instance = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.5
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.75
	
	# Give NPCs a distinct color (blue-ish)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.5, 0.8)  # Blue-ish for NPC
	mesh_instance.material_override = material
	
	npc.add_child(mesh_instance)
	
	# Set NPC to layer 2 (bit 1) so minimap can exclude it
	_set_visual_layer_recursive(npc, 2)
	
	return npc


## Update NPC position from world state
func update_npc(id: int, position: Vector3, rotation: float, animation_state: int = 0) -> void:
	if npcs.has(id):
		var npc_data = npcs[id]
		
		# Store target position/rotation for interpolation
		npc_data["target_position"] = position
		npc_data["target_rotation"] = rotation
		
		# Update animation state on the NPC model (if it has one)
		var npc_node = npc_data["node"]
		if npc_node and npc_node.has_meta("npc_model"):
			var npc_model = npc_node.get_meta("npc_model")
			if npc_model and npc_model.has_method("set_animation_state"):
				npc_model.set_animation_state(animation_state)


## Remove an NPC
func _remove_npc(id: int) -> void:
	if npcs.has(id):
		var npc_data = npcs[id]
		npc_data["node"].queue_free()
		npcs.erase(id)


## Get NPC name by type
func _get_npc_name(npc_type: int) -> String:
	match npc_type:
		0: return "Old Man"
		_: return "NPC"


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
func update_enemy(id: int, position: Vector3, rotation: float, health: int, animation_state: int = 0) -> void:
	if enemies.has(id):
		var enemy_data = enemies[id]
		
		# Store target position/rotation for interpolation
		enemy_data["target_position"] = position
		enemy_data["target_rotation"] = rotation
		enemy_data["health"] = health
		
		# Update health bar
		if enemy_data.has("health_bar"):
			enemy_data["health_bar"].set_health(health, enemy_data["max_health"])
		
		# Update animation state on the enemy model (if it has one)
		var enemy_node = enemy_data["node"]
		if enemy_node and enemy_node.has_meta("enemy_model"):
			var enemy_model = enemy_node.get_meta("enemy_model")
			if enemy_model and enemy_model.has_method("set_animation_state"):
				enemy_model.set_animation_state(animation_state)


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


## Get all NPCs
func get_all_npcs() -> Dictionary:
	return npcs.duplicate()


# =============================================================================
# World State Update Handlers
# =============================================================================

## Handle enemy state update from WorldState
func _on_enemy_state_updated(id: int, position: Vector3, rotation: float, health: int, animation_state: int = 0) -> void:
	update_enemy(id, position, rotation, health, animation_state)


## Handle remote player state update from WorldState
func _on_player_state_updated(id: int, position: Vector3, rotation: float, health: int, animation_state: int = 0, weapon_id: int = -1, _armor_id: int = -1) -> void:
	# TODO: Pass armor_id to update_remote_player when armor visuals are implemented
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
	
	# Clear all NPCs - they were in the old zone
	for id in npcs.keys():
		_remove_npc(id)
	npcs.clear()
	
	# Clear world items
	for id in world_items.keys():
		if world_items[id].has("node"):
			world_items[id]["node"].queue_free()
	world_items.clear()
	
	# Clear targeting if any
	var targeting_system = get_tree().get_first_node_in_group("targeting_system")
	if targeting_system and targeting_system.has_method("clear_target"):
		targeting_system.clear_target()
	
	print("GameManager: Cleared ", remote_players.size(), " players, ", enemies.size(), " enemies, ", npcs.size(), " NPCs")


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


func _exit_tree() -> void:
	"""Clean up resources to prevent memory leaks on exit."""
	# If we have a stored character model that was removed from tree, re-add it 
	# so it gets properly freed with its parent
	if _stored_character_model and is_instance_valid(_stored_character_model):
		if local_player and is_instance_valid(local_player) and not _stored_character_model.get_parent():
			local_player.add_child(_stored_character_model)
		_stored_character_model = null
	
	# Clear references to prevent keeping nodes alive
	local_player = null
	login_screen = null
	character_select_screen = null
	character_create_screen = null
	game_ui = null
	ui_container = null
	loading_screen = null
	day_night_controller = null

