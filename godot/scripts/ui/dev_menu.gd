extends Control
class_name DevMenu
## Developer menu for debugging and testing.
## Toggle with F12. Only available in debug builds.

## Reference to local player
var local_player: Node = null

## UI References
@onready var panel: Panel = $Panel
@onready var item_id_input: SpinBox = $Panel/VBox/ItemIDContainer/ItemIDInput
@onready var quantity_input: SpinBox = $Panel/VBox/QuantityContainer/QuantityInput
@onready var add_button: Button = $Panel/VBox/AddButton
@onready var status_label: Label = $Panel/VBox/StatusLabel


func _ready() -> void:
	# Only allow in debug builds
	if not OS.is_debug_build():
		queue_free()
		return
	
	# Start hidden
	visible = false
	
	# Setup UI
	if item_id_input:
		item_id_input.min_value = 1
		item_id_input.max_value = 9999
		item_id_input.value = 1
	
	if quantity_input:
		quantity_input.min_value = 1
		quantity_input.max_value = 99
		quantity_input.value = 1
	
	if add_button:
		add_button.pressed.connect(_on_add_button_pressed)
	
	# Find local player
	await get_tree().process_frame
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")


func _input(event: InputEvent) -> void:
	# Only process game inputs when actually in game
	if not _is_in_game():
		return
	
	if event.is_action_pressed("dev_menu"):
		toggle_visibility()


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and "current_state" in game_manager:
		# GameState.IN_GAME = 3
		return game_manager.current_state == 3
	return false


func toggle_visibility() -> void:
	visible = not visible
	if visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if status_label:
			status_label.text = ""


func _on_add_button_pressed() -> void:
	if not local_player:
		if status_label:
			status_label.text = "Error: No player found"
			status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		return
	
	if not local_player.has_method("dev_add_item"):
		if status_label:
			status_label.text = "Error: dev_add_item not available"
			status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		return
	
	var item_id = int(item_id_input.value)
	var quantity = int(quantity_input.value)
	
	local_player.dev_add_item(item_id, quantity)
	
	if status_label:
		status_label.text = "Added %dx item #%d" % [quantity, item_id]
		status_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
