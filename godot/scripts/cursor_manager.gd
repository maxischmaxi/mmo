extends Node
class_name CursorManager
## Manages custom cursors for the game.
## Changes cursor based on what the mouse is hovering over.

## Cursor types
enum CursorType {
	DEFAULT,
	ATTACK_ENEMY,
	FRIENDLY,
	CANNOT_TARGET,
	INTERACT,
	LOOT
}

## Current cursor type (-1 means unset, forces first application)
var current_cursor: int = -1

## Loaded cursor textures
var cursors: Dictionary = {}

## Cursor configuration
const CURSOR_SIZE = "36x36px"
const HOTSPOT = Vector2(2, 2)  # Click point offset from top-left

## Reference to camera for raycasting
var camera: Camera3D = null

## Reference to game manager for entity detection
var game_manager: Node = null

## Raycast parameters
const RAY_LENGTH: float = 1000.0


func _ready() -> void:
	# Load cursor textures
	_load_cursors()
	
	# Ensure mouse is visible (not captured/hidden)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Force apply default cursor immediately (current_cursor is -1, so it will apply)
	set_cursor(CursorType.DEFAULT)
	
	# Wait a frame for other nodes to be ready
	await get_tree().process_frame
	_find_references()
	
	# Re-apply cursor after everything is loaded
	_force_apply_cursor()


func _exit_tree() -> void:
	# Reset to system cursor to prevent texture leaks on exit
	Input.set_custom_mouse_cursor(null)
	# Clear texture references
	cursors.clear()


func _load_cursors() -> void:
	var base_path = "res://assets/magic_cursors/" + CURSOR_SIZE + "/"
	
	cursors[CursorType.DEFAULT] = load(base_path + "Cursor Default.png")
	# Full cursor with attack crosshair - indicates an attackable enemy
	cursors[CursorType.ATTACK_ENEMY] = load(base_path + "Cursor Attack Enemy.png")
	cursors[CursorType.FRIENDLY] = load(base_path + "Cursor Default Friends.png")
	cursors[CursorType.CANNOT_TARGET] = load(base_path + "Cursor Cannot Target.png")
	cursors[CursorType.INTERACT] = load(base_path + "Cursor possible.png")
	cursors[CursorType.LOOT] = load(base_path + "Cursor Potion Green.png")


func _find_references() -> void:
	# Find camera
	var local_player = get_tree().get_first_node_in_group("local_player")
	if local_player:
		var camera_controller = local_player.get_node_or_null("CameraController")
		if camera_controller:
			camera = camera_controller.get_node_or_null("SpringArm3D/Camera3D")
	
	# Find game manager
	game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager == null:
		var main = get_tree().current_scene
		if main:
			game_manager = main.get_node_or_null("GameManager")


func _process(_delta: float) -> void:
	# Skip cursor updates when mouse is captured (camera rotation mode)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		return
	_update_cursor_from_hover()


func _update_cursor_from_hover() -> void:
	if not camera or not game_manager:
		return
	
	# Get mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Raycast from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * RAY_LENGTH
	
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		set_cursor(CursorType.DEFAULT)
		return
	
	var hit_node = result.collider
	
	# Check if it's an enemy
	var enemy_data = game_manager.get_enemy_by_node(hit_node)
	if not enemy_data.is_empty():
		set_cursor(CursorType.ATTACK_ENEMY)
		return
	
	# Check if it's a player
	var player_data = game_manager.get_player_by_node(hit_node)
	if not player_data.is_empty():
		set_cursor(CursorType.FRIENDLY)
		return
	
	# TODO: Check for items, NPCs, etc.
	
	# Default cursor for ground/terrain
	set_cursor(CursorType.DEFAULT)


## Set the cursor to a specific type
func set_cursor(type: CursorType) -> void:
	if type == current_cursor:
		return
	
	current_cursor = type
	var texture = cursors.get(type, cursors[CursorType.DEFAULT])
	
	if texture:
		Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, HOTSPOT)


## Force refresh the cursor (call after loading new area, etc.)
func refresh_cursor() -> void:
	_force_apply_cursor()


## Internal: Force apply the current cursor texture
func _force_apply_cursor() -> void:
	var texture = cursors.get(current_cursor, cursors.get(CursorType.DEFAULT))
	if texture:
		Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, HOTSPOT)
