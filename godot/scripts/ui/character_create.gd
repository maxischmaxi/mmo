extends Control
## Character creation screen UI controller
## Allows players to create a new character

signal character_created()
signal back_to_select()

const CLASS_NAMES := ["Ninja", "Warrior", "Sura", "Shaman"]
const CLASS_DESCRIPTIONS := [
	"Agile fighter with high attack.\nHP: 80 | Mana: 40 | ATK: 12 | DEF: 4",
	"Powerful tank with high HP.\nHP: 120 | Mana: 20 | ATK: 10 | DEF: 8",
	"Dark magic user with balance.\nHP: 90 | Mana: 60 | ATK: 11 | DEF: 5",
	"Support caster with high mana.\nHP: 70 | Mana: 80 | ATK: 8 | DEF: 4"
]
const GENDER_NAMES := ["Male", "Female"]
const EMPIRE_NAMES := ["Shinsoo (Red)", "Chunjo (Yellow)", "Jinno (Blue)"]
const EMPIRE_COLORS := [Color(0.8, 0.2, 0.2), Color(0.8, 0.8, 0.2), Color(0.2, 0.4, 0.8)]

@onready var name_input: LineEdit = $CenterContainer/Panel/VBox/NameSection/NameInput
@onready var class_buttons: Array[Button] = []
@onready var class_description: Label = $CenterContainer/Panel/VBox/ClassSection/ClassDescription
@onready var gender_buttons: Array[Button] = []
@onready var empire_buttons: Array[Button] = []
@onready var status_label: Label = $CenterContainer/Panel/VBox/StatusLabel
@onready var create_button: Button = $CenterContainer/Panel/VBox/ButtonRow/CreateButton
@onready var back_button: Button = $CenterContainer/Panel/VBox/ButtonRow/BackButton

## Reference to the player node
var player_node: Node = null

## Selected values
var selected_class: int = -1
var selected_gender: int = -1
var selected_empire: int = -1


func _ready() -> void:
	status_label.text = ""
	
	# Find and setup class buttons
	var class_grid = $CenterContainer/Panel/VBox/ClassSection/ClassGrid
	for i in range(4):
		var btn = class_grid.get_child(i) as Button
		if btn:
			btn.text = CLASS_NAMES[i]
			btn.pressed.connect(_on_class_selected.bind(i))
			class_buttons.append(btn)
	
	# Find and setup gender buttons
	var gender_row = $CenterContainer/Panel/VBox/GenderSection/GenderRow
	for i in range(2):
		var btn = gender_row.get_child(i) as Button
		if btn:
			btn.text = GENDER_NAMES[i]
			btn.pressed.connect(_on_gender_selected.bind(i))
			gender_buttons.append(btn)
	
	# Find and setup empire buttons
	var empire_grid = $CenterContainer/Panel/VBox/EmpireSection/EmpireGrid
	for i in range(3):
		var btn = empire_grid.get_child(i) as Button
		if btn:
			btn.text = EMPIRE_NAMES[i]
			btn.modulate = EMPIRE_COLORS[i]
			btn.pressed.connect(_on_empire_selected.bind(i))
			empire_buttons.append(btn)
	
	# Set defaults
	_on_class_selected(1)  # Warrior
	_on_gender_selected(0)  # Male
	_on_empire_selected(0)  # Red


func set_player(player: Node) -> void:
	"""Set the player node reference and connect signals."""
	player_node = player
	
	if player_node.has_signal("character_created"):
		player_node.character_created.connect(_on_character_created)
	if player_node.has_signal("character_create_failed"):
		player_node.character_create_failed.connect(_on_character_create_failed)


func reset_form() -> void:
	"""Reset the form for a new character."""
	name_input.text = ""
	status_label.text = ""
	_on_class_selected(1)
	_on_gender_selected(0)
	_on_empire_selected(0)
	name_input.grab_focus()


func _on_class_selected(index: int) -> void:
	"""Handle class button selection."""
	selected_class = index
	_update_toggle_buttons(class_buttons, index)
	class_description.text = CLASS_DESCRIPTIONS[index]


func _on_gender_selected(index: int) -> void:
	"""Handle gender button selection."""
	selected_gender = index
	_update_toggle_buttons(gender_buttons, index)


func _on_empire_selected(index: int) -> void:
	"""Handle empire button selection."""
	selected_empire = index
	_update_toggle_buttons(empire_buttons, index)


func _update_toggle_buttons(buttons: Array[Button], selected: int) -> void:
	"""Update button appearance for toggle group."""
	for i in range(buttons.size()):
		var btn = buttons[i]
		if i == selected:
			btn.add_theme_stylebox_override("normal", _create_selected_style())
			btn.button_pressed = true
		else:
			btn.remove_theme_stylebox_override("normal")
			btn.button_pressed = false


func _create_selected_style() -> StyleBoxFlat:
	"""Create a highlight style for selected button."""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.5, 0.7, 0.8)
	style.border_color = Color(0.5, 0.8, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


func _on_create_pressed() -> void:
	"""Handle create button press."""
	var char_name = name_input.text.strip_edges()
	
	# Validate name
	if char_name.is_empty():
		_show_error("Please enter a character name")
		return
	
	if char_name.length() > 32:
		_show_error("Name must be 32 characters or less")
		return
	
	# Check alphanumeric only
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9]+$")
	if not regex.search(char_name):
		_show_error("Name must be alphanumeric only")
		return
	
	# Validate selections
	if selected_class < 0:
		_show_error("Please select a class")
		return
	
	if selected_gender < 0:
		_show_error("Please select a gender")
		return
	
	if selected_empire < 0:
		_show_error("Please select an empire")
		return
	
	# Submit creation request
	_show_status("Creating character...", Color.WHITE)
	create_button.disabled = true
	
	if player_node:
		player_node.create_character(char_name, selected_class, selected_gender, selected_empire)


func _on_back_pressed() -> void:
	"""Handle back button press."""
	back_to_select.emit()


func _on_character_created(character: Dictionary) -> void:
	"""Handle successful character creation."""
	_show_status("Character created!", Color(0.4, 1, 0.4))
	create_button.disabled = false
	character_created.emit()


func _on_character_create_failed(reason: String) -> void:
	"""Handle failed character creation."""
	_show_error(reason)
	create_button.disabled = false


func _show_error(message: String) -> void:
	"""Show an error message."""
	status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	status_label.text = message


func _show_status(message: String, color: Color = Color.WHITE) -> void:
	"""Show a status message."""
	status_label.add_theme_color_override("font_color", color)
	status_label.text = message
