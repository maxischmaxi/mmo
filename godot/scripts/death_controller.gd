extends Node
## Controls player death and respawn flow.
## Listens for death signal, shows dialog, and handles respawn.

## Reference to the player node (set on _ready)
var player: CharacterBody3D

## Reference to the animation controller
var animation_controller: Node

## The death dialog instance
var death_dialog: CanvasLayer

## Preloaded death dialog scene
const DeathDialogScene = preload("res://scenes/ui/death_dialog.tscn")


func _ready() -> void:
	# Find player in parent hierarchy
	player = _find_player()
	if not player:
		push_error("DeathController: Could not find Player node")
		return
	
	# Find animation controller
	animation_controller = _find_animation_controller()
	
	# Connect to player signals
	if player.has_signal("player_died"):
		player.player_died.connect(_on_player_died)
	else:
		push_warning("DeathController: Player node does not have player_died signal")
	
	if player.has_signal("player_respawned"):
		player.player_respawned.connect(_on_player_respawned)
	else:
		push_warning("DeathController: Player node does not have player_respawned signal")


## Find the Player node (CharacterBody3D with player script) in parent hierarchy
func _find_player() -> CharacterBody3D:
	var node = get_parent()
	while node:
		if node is CharacterBody3D and node.has_method("request_respawn"):
			return node
		node = node.get_parent()
	return null


## Find the AnimationController in siblings or children
func _find_animation_controller() -> Node:
	# Check siblings
	if get_parent():
		for sibling in get_parent().get_children():
			if sibling.name == "AnimationController" or sibling.get_script() and sibling.get_script().resource_path.ends_with("animation_controller.gd"):
				return sibling
	
	# Check within the character model
	var model = get_parent().get_node_or_null("CharacterModel")
	if model:
		for child in model.get_children():
			if child.name == "AnimationController":
				return child
	
	return null


## Called when the local player dies
func _on_player_died() -> void:
	print("DeathController: Player died!")
	
	# Play death animation
	if animation_controller and animation_controller.has_method("play_death_animation"):
		animation_controller.play_death_animation()
	
	# Create and show death dialog
	if not death_dialog:
		death_dialog = DeathDialogScene.instantiate()
		get_tree().root.add_child(death_dialog)
		
		# Connect dialog signals
		death_dialog.respawn_at_spawn.connect(_on_respawn_at_spawn)
		death_dialog.revive_here.connect(_on_revive_here)
	
	death_dialog.show_dialog()


## Called when player chooses to respawn at empire spawn
func _on_respawn_at_spawn() -> void:
	print("DeathController: Requesting respawn at empire spawn")
	if player and player.has_method("request_respawn"):
		player.request_respawn(0)  # 0 = empire spawn


## Called when player chooses to revive at death location
func _on_revive_here() -> void:
	print("DeathController: Requesting revive at death location")
	if player and player.has_method("request_respawn"):
		player.request_respawn(1)  # 1 = death location


## Called when the server confirms respawn
func _on_player_respawned(position: Vector3, health: int, max_health: int) -> void:
	print("DeathController: Player respawned at %s with %d/%d HP" % [position, health, max_health])
	
	# Reset animation state
	if animation_controller and animation_controller.has_method("reset_from_death"):
		animation_controller.reset_from_death()
	
	# Hide death dialog if still visible
	if death_dialog:
		death_dialog.hide_dialog()
	
	# Restore mouse mode for gameplay
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _exit_tree() -> void:
	# Clean up death dialog
	if death_dialog and is_instance_valid(death_dialog):
		death_dialog.queue_free()
