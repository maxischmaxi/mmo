extends Control
## Character creation screen UI controller
## Allows players to create a new character

signal character_created()
signal back_to_select()

## UI Colors matching the fantasy theme
const COLOR_GOLD := Color(0.83, 0.66, 0.29)
const COLOR_MUTED := Color(0.6, 0.53, 0.4)
const COLOR_TEXT := Color(0.91, 0.89, 0.86)
const COLOR_ERROR := Color(0.91, 0.33, 0.33)
const COLOR_SUCCESS := Color(0.33, 0.91, 0.48)

const CLASS_NAMES := ["Ninja", "Warrior", "Sura", "Shaman"]
const CLASS_DESCRIPTIONS := [
	"Agile fighter with high attack.\nHP: 80 | Mana: 40 | ATK: 12 | DEF: 4",
	"Powerful tank with high HP.\nHP: 120 | Mana: 20 | ATK: 10 | DEF: 8",
	"Dark magic user with balance.\nHP: 90 | Mana: 60 | ATK: 11 | DEF: 5",
	"Support caster with high mana.\nHP: 70 | Mana: 80 | ATK: 8 | DEF: 4"
]
const GENDER_NAMES := ["Male", "Female"]
const EMPIRE_NAMES := ["Shinsoo", "Chunjo", "Jinno"]

## Empire colors for the fantasy theme
const EMPIRE_COLORS := [
	Color(0.95, 0.45, 0.35),  # Shinsoo - warm red
	Color(0.95, 0.85, 0.35),  # Chunjo - gold yellow
	Color(0.45, 0.65, 0.95)   # Jinno - cool blue
]

# Node references
@onready var name_input: LineEdit = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/NameSection/NameContainer/NameInput
@onready var name_container: PanelContainer = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/NameSection/NameContainer
@onready var class_buttons: Array[Button] = []
@onready var class_description: Label = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/ClassSection/ClassDescription
@onready var gender_buttons: Array[Button] = []
@onready var empire_buttons: Array[Button] = []
@onready var status_label: Label = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/StatusLabel
@onready var create_button: Button = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/ButtonRow/CreateButton
@onready var back_button: Button = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/ButtonRow/BackButton
@onready var particle_effect: GPUParticles2D = $ParticleEffect

## Reference to the player node
var player_node: Node = null

## Selected values
var selected_class: int = -1
var selected_gender: int = -1
var selected_empire: int = -1

## StyleBox for normal input state
var normal_input_style: StyleBoxFlat
## StyleBox for focused input state
var focused_input_style: StyleBoxFlat
## StyleBox for selected toggle buttons
var selected_toggle_style: StyleBoxFlat


func _ready() -> void:
	status_label.text = ""
	
	# Setup input styles
	_setup_input_styles()
	
	# Connect focus signals for name input
	name_input.focus_entered.connect(_on_name_focus_entered)
	name_input.focus_exited.connect(_on_name_focus_exited)
	
	# Setup particle effect
	_setup_particles()
	
	# Find and setup class buttons
	var class_grid = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/ClassSection/ClassGrid
	for i in range(4):
		var btn = class_grid.get_child(i) as Button
		if btn:
			btn.text = CLASS_NAMES[i]
			btn.pressed.connect(_on_class_selected.bind(i))
			class_buttons.append(btn)
	
	# Find and setup gender buttons
	var gender_row = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/GenderSection/GenderRow
	for i in range(2):
		var btn = gender_row.get_child(i) as Button
		if btn:
			btn.text = GENDER_NAMES[i]
			btn.pressed.connect(_on_gender_selected.bind(i))
			gender_buttons.append(btn)
	
	# Find and setup empire buttons
	var empire_grid = $ContentContainer/MainVBox/Panel/PanelMargin/VBox/EmpireSection/EmpireGrid
	for i in range(3):
		var btn = empire_grid.get_child(i) as Button
		if btn:
			btn.text = EMPIRE_NAMES[i]
			btn.pressed.connect(_on_empire_selected.bind(i))
			empire_buttons.append(btn)
	
	# Set defaults
	_on_class_selected(1)  # Warrior
	_on_gender_selected(0)  # Male
	_on_empire_selected(0)  # Shinsoo


func _setup_input_styles() -> void:
	"""Create stylebox resources for input focus effects."""
	# Normal style
	normal_input_style = StyleBoxFlat.new()
	normal_input_style.bg_color = Color(0.03, 0.04, 0.06, 0.9)
	normal_input_style.set_border_width_all(1)
	normal_input_style.border_color = Color(0.29, 0.25, 0.21)
	normal_input_style.set_corner_radius_all(4)
	normal_input_style.content_margin_left = 10
	normal_input_style.content_margin_right = 10
	normal_input_style.content_margin_top = 8
	normal_input_style.content_margin_bottom = 8
	
	# Focused style (gold border)
	focused_input_style = StyleBoxFlat.new()
	focused_input_style.bg_color = Color(0.03, 0.04, 0.06, 0.9)
	focused_input_style.set_border_width_all(2)
	focused_input_style.border_color = COLOR_GOLD
	focused_input_style.set_corner_radius_all(4)
	focused_input_style.content_margin_left = 10
	focused_input_style.content_margin_right = 10
	focused_input_style.content_margin_top = 8
	focused_input_style.content_margin_bottom = 8
	
	# Selected toggle button style
	selected_toggle_style = StyleBoxFlat.new()
	selected_toggle_style.bg_color = Color(0.48, 0.39, 0.26, 1)
	selected_toggle_style.set_border_width_all(2)
	selected_toggle_style.border_color = COLOR_GOLD
	selected_toggle_style.set_corner_radius_all(4)
	selected_toggle_style.content_margin_left = 10
	selected_toggle_style.content_margin_right = 10
	selected_toggle_style.content_margin_top = 8
	selected_toggle_style.content_margin_bottom = 8


func _setup_particles() -> void:
	"""Configure the particle system for floating ember effect."""
	var material = ParticleProcessMaterial.new()
	
	# Emission from bottom of screen
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(get_viewport().get_visible_rect().size.x / 2, 50, 0)
	
	# Direction: upward with slight spread
	material.direction = Vector3(0, -1, 0)
	material.spread = 15.0
	
	# Velocity
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 40.0
	
	# Gravity (slight upward float)
	material.gravity = Vector3(0, -5, 0)
	
	# Scale variation
	material.scale_min = 2.0
	material.scale_max = 6.0
	
	# Color with fade out
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.83, 0.58, 0.29, 1.0))
	gradient.set_color(1, Color(0.83, 0.58, 0.29, 0.0))
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	particle_effect.process_material = material
	particle_effect.position = Vector2(get_viewport().get_visible_rect().size.x / 2, get_viewport().get_visible_rect().size.y + 50)


func _on_name_focus_entered() -> void:
	"""Apply focused style when name input gains focus."""
	name_container.add_theme_stylebox_override("panel", focused_input_style)


func _on_name_focus_exited() -> void:
	"""Apply normal style when name input loses focus."""
	name_container.add_theme_stylebox_override("panel", normal_input_style)


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
	create_button.text = "CREATE CHARACTER"
	create_button.disabled = false
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
			btn.add_theme_stylebox_override("normal", selected_toggle_style)
			btn.button_pressed = true
		else:
			btn.remove_theme_stylebox_override("normal")
			btn.button_pressed = false


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
	create_button.text = "CREATING..."
	create_button.disabled = true
	
	if player_node:
		player_node.create_character(char_name, selected_class, selected_gender, selected_empire)


func _on_back_pressed() -> void:
	"""Handle back button press."""
	back_to_select.emit()


func _on_character_created(character: Dictionary) -> void:
	"""Handle successful character creation."""
	_show_status("Character created!", COLOR_SUCCESS)
	create_button.text = "CREATE CHARACTER"
	create_button.disabled = false
	character_created.emit()


func _on_character_create_failed(reason: String) -> void:
	"""Handle failed character creation."""
	_show_error(reason)
	create_button.text = "CREATE CHARACTER"
	create_button.disabled = false


func _show_error(message: String) -> void:
	"""Show an error message."""
	status_label.add_theme_color_override("font_color", COLOR_ERROR)
	status_label.text = message


func _show_status(message: String, color: Color = Color.WHITE) -> void:
	"""Show a status message."""
	status_label.add_theme_color_override("font_color", color)
	status_label.text = message
