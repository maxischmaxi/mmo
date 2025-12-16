extends Control
## Character selection screen UI controller
## Shows up to 4 character slots after login

signal character_selected(character_id: int)
signal create_new_character()
signal back_to_login()

const CLASS_NAMES := ["Ninja", "Warrior", "Sura", "Shaman"]
const GENDER_NAMES := ["Male", "Female"]
const EMPIRE_NAMES := ["Shinsoo", "Chunjo", "Jinno"]
const EMPIRE_COLORS := [Color(0.8, 0.2, 0.2), Color(0.8, 0.8, 0.2), Color(0.2, 0.4, 0.8)]

@onready var status_label: Label = $CenterContainer/Panel/VBox/StatusLabel
@onready var character_grid: GridContainer = $CenterContainer/Panel/VBox/CharacterGrid
@onready var info_panel: PanelContainer = $CenterContainer/Panel/VBox/InfoPanel
@onready var info_name: Label = $CenterContainer/Panel/VBox/InfoPanel/VBox/NameLabel
@onready var info_details: Label = $CenterContainer/Panel/VBox/InfoPanel/VBox/DetailsLabel
@onready var play_button: Button = $CenterContainer/Panel/VBox/ButtonRow/PlayButton
@onready var delete_button: Button = $CenterContainer/Panel/VBox/ButtonRow/DeleteButton
@onready var back_button: Button = $CenterContainer/Panel/VBox/ButtonRow/BackButton
@onready var delete_dialog: ConfirmationDialog = $DeleteDialog
@onready var delete_name_input: LineEdit = $DeleteDialog/VBox/NameInput

## Reference to the player node
var player_node: Node = null

## Current list of characters
var characters: Array = []

## Currently selected character index (-1 = none)
var selected_index: int = -1

## Character slot buttons
var slot_buttons: Array[Button] = []


func _ready() -> void:
	status_label.text = ""
	info_panel.visible = false
	play_button.disabled = true
	delete_button.disabled = true
	
	# Create 4 character slot buttons
	for i in range(4):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(180, 80)
		btn.text = "Empty Slot"
		btn.pressed.connect(_on_slot_pressed.bind(i))
		character_grid.add_child(btn)
		slot_buttons.append(btn)


func set_player(player: Node) -> void:
	"""Set the player node reference and connect signals."""
	player_node = player
	
	# Connect character signals
	if player_node.has_signal("character_list_received"):
		player_node.character_list_received.connect(_on_character_list_received)
	if player_node.has_signal("character_selected"):
		player_node.character_selected.connect(_on_character_selected)
	if player_node.has_signal("character_select_failed"):
		player_node.character_select_failed.connect(_on_character_select_failed)
	if player_node.has_signal("character_deleted"):
		player_node.character_deleted.connect(_on_character_deleted)
	if player_node.has_signal("character_delete_failed"):
		player_node.character_delete_failed.connect(_on_character_delete_failed)


func request_character_list() -> void:
	"""Request character list from server."""
	if player_node:
		_show_status("Loading characters...", Color.WHITE)
		player_node.get_character_list()


func _on_character_list_received(char_list: Array) -> void:
	"""Handle received character list."""
	characters = char_list
	_update_slot_buttons()
	_show_status("", Color.WHITE)
	selected_index = -1
	_update_selection()


func _update_slot_buttons() -> void:
	"""Update slot button appearance based on characters."""
	for i in range(4):
		var btn = slot_buttons[i]
		if i < characters.size():
			var c = characters[i]
			var char_class = CLASS_NAMES[c.get("class", 0)]
			var empire_name = EMPIRE_NAMES[c.get("empire", 0)]
			btn.text = "%s\nLv.%d %s\n%s" % [c.get("name", "?"), c.get("level", 1), char_class, empire_name]
			btn.modulate = EMPIRE_COLORS[c.get("empire", 0)]
		else:
			btn.text = "Create New"
			btn.modulate = Color(0.6, 0.6, 0.6)


func _on_slot_pressed(index: int) -> void:
	"""Handle slot button press."""
	if index < characters.size():
		# Select existing character
		selected_index = index
		_update_selection()
	else:
		# Create new character
		create_new_character.emit()


func _update_selection() -> void:
	"""Update UI based on current selection."""
	# Update button styles
	for i in range(4):
		var btn = slot_buttons[i]
		if i == selected_index:
			btn.add_theme_stylebox_override("normal", _create_selected_style())
		else:
			btn.remove_theme_stylebox_override("normal")
	
	# Update info panel and buttons
	if selected_index >= 0 and selected_index < characters.size():
		var c = characters[selected_index]
		info_panel.visible = true
		info_name.text = c.get("name", "Unknown")
		var char_class = CLASS_NAMES[c.get("class", 0)]
		var gender_name = GENDER_NAMES[c.get("gender", 0)]
		var empire_name = EMPIRE_NAMES[c.get("empire", 0)]
		info_details.text = "Level %d %s %s\nEmpire: %s" % [c.get("level", 1), gender_name, char_class, empire_name]
		play_button.disabled = false
		delete_button.disabled = false
	else:
		info_panel.visible = false
		play_button.disabled = true
		delete_button.disabled = true


func _create_selected_style() -> StyleBoxFlat:
	"""Create a highlight style for selected button."""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.5, 0.7, 0.8)
	style.border_color = Color(0.5, 0.8, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


func _on_play_pressed() -> void:
	"""Handle play button press."""
	if selected_index >= 0 and selected_index < characters.size():
		var c = characters[selected_index]
		var char_id = c.get("id", 0)
		_show_status("Entering game...", Color.WHITE)
		play_button.disabled = true
		delete_button.disabled = true
		if player_node:
			player_node.select_character(char_id)


func _on_delete_pressed() -> void:
	"""Handle delete button press - show confirmation dialog."""
	if selected_index >= 0 and selected_index < characters.size():
		var c = characters[selected_index]
		delete_dialog.title = "Delete Character"
		delete_dialog.dialog_text = "Type the character name to confirm deletion:\n\n%s" % c.get("name", "")
		delete_name_input.text = ""
		delete_name_input.placeholder_text = c.get("name", "")
		delete_dialog.popup_centered()
		delete_name_input.grab_focus()


func _on_delete_dialog_confirmed() -> void:
	"""Handle delete dialog confirmation."""
	if selected_index >= 0 and selected_index < characters.size():
		var c = characters[selected_index]
		var char_id = c.get("id", 0)
		var char_name = c.get("name", "")
		var entered_name = delete_name_input.text.strip_edges()
		
		if entered_name != char_name:
			_show_error("Name does not match. Deletion cancelled.")
			return
		
		_show_status("Deleting character...", Color.WHITE)
		if player_node:
			player_node.delete_character(char_id, entered_name)


func _on_back_pressed() -> void:
	"""Handle back button press."""
	if player_node:
		player_node.disconnect_from_server()
	back_to_login.emit()


func _on_character_selected(character_id: int) -> void:
	"""Handle successful character selection."""
	character_selected.emit(character_id)


func _on_character_select_failed(reason: String) -> void:
	"""Handle failed character selection."""
	_show_error(reason)
	play_button.disabled = false
	delete_button.disabled = false


func _on_character_deleted(character_id: int) -> void:
	"""Handle successful character deletion."""
	_show_status("Character deleted!", Color(0.4, 1, 0.4))
	# Refresh character list
	request_character_list()


func _on_character_delete_failed(reason: String) -> void:
	"""Handle failed character deletion."""
	_show_error(reason)


func _show_error(message: String) -> void:
	"""Show an error message."""
	status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	status_label.text = message


func _show_status(message: String, color: Color = Color.WHITE) -> void:
	"""Show a status message."""
	status_label.add_theme_color_override("font_color", color)
	status_label.text = message
