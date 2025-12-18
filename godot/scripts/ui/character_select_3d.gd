extends Control
class_name CharacterSelect3D
## Metin2-style character selection screen with 3D character preview.
## Navigate with arrow keys, select with Enter.

signal character_selected(character_id: int)
signal create_new_character()
signal back_to_login()

const CharacterModelScene = preload("res://scenes/player/character_model.tscn")

const CLASS_NAMES := ["Ninja", "Warrior", "Sura", "Shaman"]
const GENDER_NAMES := ["Male", "Female"]
const EMPIRE_NAMES := ["Shinsoo", "Chunjo", "Jinno"]

## Empire colors - gold-tinted versions for the fantasy theme
const EMPIRE_COLORS := [
	Color(0.95, 0.45, 0.35),  # Shinsoo - warm red
	Color(0.95, 0.85, 0.35),  # Chunjo - gold yellow
	Color(0.45, 0.65, 0.95)   # Jinno - cool blue
]

## UI Colors matching login screen
const COLOR_GOLD := Color(0.83, 0.66, 0.29)
const COLOR_MUTED := Color(0.6, 0.53, 0.4)
const COLOR_TEXT := Color(0.91, 0.89, 0.86)

## Spacing between character slots in 3D space
## Must be large enough that characters in adjacent slots aren't visible
const SLOT_SPACING: float = 8.0

## Slide animation duration
const SLIDE_DURATION: float = 0.3

## Maximum character slots
const MAX_SLOTS: int = 4

## Reference to the player node
var player_node: Node = null

## Current list of characters from server
var characters: Array = []

## Currently selected slot index (0-3)
var current_index: int = 0

## Whether we're currently animating a transition
var is_transitioning: bool = false

## Character model instances (one per slot, null if empty)
var character_models: Array = [null, null, null, null]

## Slot container nodes
var slot_nodes: Array[Node3D] = []

## Dot indicator labels
var dot_labels: Array[Label] = []

# UI References - 3D Viewport
@onready var subviewport: SubViewport = $SubViewportContainer/SubViewport
@onready var character_slider: Node3D = $SubViewportContainer/SubViewport/CharacterSlider
@onready var camera: Camera3D = $SubViewportContainer/SubViewport/Camera3D

# UI References - Overlay elements
@onready var top_info: PanelContainer = $Overlay/TopInfo
@onready var char_name_label: Label = $Overlay/TopInfo/InfoMargin/InfoVBox/CharacterName
@onready var char_details_label: Label = $Overlay/TopInfo/InfoMargin/InfoVBox/CharacterDetails
@onready var create_prompt: VBoxContainer = $Overlay/CreatePrompt
@onready var left_arrow: Label = $Overlay/LeftArrow
@onready var right_arrow: Label = $Overlay/RightArrow
@onready var instructions_label: Label = $Overlay/Instructions

@onready var slot_indicators: HBoxContainer = $Overlay/SlotIndicators
@onready var delete_button: Button = $Overlay/BottomButtons/DeleteButton
@onready var back_button: Button = $Overlay/BottomButtons/BackButton
@onready var enter_button: Button = $Overlay/EnterButton

@onready var delete_dialog: ConfirmationDialog = $DeleteDialog
@onready var delete_name_input: LineEdit = $DeleteDialog/VBox/NameInput

# Particles
@onready var particle_effect: GPUParticles2D = $ParticleEffect


func _ready() -> void:
	# Create slot container nodes in the slider
	_setup_slot_nodes()
	
	# Create slot container nodes in the slider
	_setup_dot_indicators()
	
	# Setup particle effect
	_setup_particles()
	
	# Initial UI state
	_update_ui()
	
	# Connect button signals
	back_button.pressed.connect(_on_back_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	enter_button.pressed.connect(_confirm_selection)
	delete_dialog.confirmed.connect(_on_delete_dialog_confirmed)
	
	# Connect visibility change to control SubViewport rendering
	visibility_changed.connect(_on_visibility_changed)


func _setup_particles() -> void:
	"""Configure the particle system for floating ember effect."""
	var material = ParticleProcessMaterial.new()
	
	# Emission from bottom of screen, spreading across width
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(get_viewport().get_visible_rect().size.x / 2, 50, 0)
	
	# Direction: upward with slight spread
	material.direction = Vector3(0, -1, 0)
	material.spread = 20.0
	
	# Velocity
	material.initial_velocity_min = 15.0
	material.initial_velocity_max = 35.0
	
	# Gravity (slight upward float)
	material.gravity = Vector3(0, -3, 0)
	
	# Scale variation
	material.scale_min = 1.5
	material.scale_max = 4.0
	
	# Color with fade out
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.83, 0.58, 0.29, 0.8))  # Gold/amber
	gradient.set_color(1, Color(0.83, 0.58, 0.29, 0.0))  # Fade to transparent
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	particle_effect.process_material = material
	particle_effect.position = Vector2(get_viewport().get_visible_rect().size.x / 2, get_viewport().get_visible_rect().size.y + 50)


func _on_visibility_changed() -> void:
	"""Stop/start SubViewport rendering based on visibility."""
	if not is_node_ready():
		return
	
	var container = get_node_or_null("SubViewportContainer")
	var viewport = get_node_or_null("SubViewportContainer/SubViewport")
	var floor_mesh = get_node_or_null("SubViewportContainer/SubViewport/Floor")
	
	if visible:
		# Show and enable rendering when visible
		if container:
			container.visible = true
		if viewport:
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if floor_mesh:
			floor_mesh.visible = true
	else:
		# Hide and disable rendering when hidden
		if container:
			container.visible = false
		if viewport:
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if floor_mesh:
			floor_mesh.visible = false
		
		# Clean up character models to prevent any rendering issues
		_cleanup_character_models()


func _cleanup_character_models() -> void:
	"""Remove all character models from the scene."""
	for i in range(MAX_SLOTS):
		if character_models[i] != null:
			character_models[i].queue_free()
			character_models[i] = null
		if i < slot_nodes.size():
			for child in slot_nodes[i].get_children():
				child.queue_free()


func _setup_slot_nodes() -> void:
	"""Create 4 slot Node3D containers for character models."""
	for i in range(MAX_SLOTS):
		var slot = Node3D.new()
		slot.name = "Slot%d" % i
		slot.position = Vector3(i * SLOT_SPACING, 0, 0)
		character_slider.add_child(slot)
		slot_nodes.append(slot)


func _setup_dot_indicators() -> void:
	"""Create dot indicator labels for each slot."""
	for i in range(MAX_SLOTS):
		var dot = Label.new()
		dot.text = "○"
		dot.add_theme_font_size_override("font_size", 20)
		dot.add_theme_color_override("font_color", COLOR_MUTED)
		slot_indicators.add_child(dot)
		dot_labels.append(dot)


func set_player(player: Node) -> void:
	"""Set the player node reference and connect signals."""
	player_node = player
	
	if player_node.has_signal("character_list_received"):
		if not player_node.character_list_received.is_connected(_on_character_list_received):
			player_node.character_list_received.connect(_on_character_list_received)
	if player_node.has_signal("character_selected"):
		if not player_node.character_selected.is_connected(_on_character_selected_success):
			player_node.character_selected.connect(_on_character_selected_success)
	if player_node.has_signal("character_select_failed"):
		if not player_node.character_select_failed.is_connected(_on_character_select_failed):
			player_node.character_select_failed.connect(_on_character_select_failed)
	if player_node.has_signal("character_deleted"):
		if not player_node.character_deleted.is_connected(_on_character_deleted):
			player_node.character_deleted.connect(_on_character_deleted)
	if player_node.has_signal("character_delete_failed"):
		if not player_node.character_delete_failed.is_connected(_on_character_delete_failed):
			player_node.character_delete_failed.connect(_on_character_delete_failed)


func request_character_list() -> void:
	"""Request character list from server."""
	if player_node:
		player_node.get_character_list()


func _on_character_list_received(char_list: Array) -> void:
	"""Handle received character list from server."""
	characters = char_list
	print("[CharSelect3D] Received %d characters" % characters.size())
	_setup_character_models()
	
	# Reset to first slot (or first character if exists)
	current_index = 0
	_position_slider_for_index(current_index, false)
	_update_ui()


func _setup_character_models() -> void:
	"""Instantiate character models for each slot based on character data."""
	print("[CharSelect3D] Setting up models for %d characters" % characters.size())
	
	# Clear existing models from all slots
	for i in range(MAX_SLOTS):
		if character_models[i] != null:
			character_models[i].queue_free()
			character_models[i] = null
		# Also clear any children from slot nodes
		if i < slot_nodes.size():
			for child in slot_nodes[i].get_children():
				child.queue_free()
	
	# Wait a frame for queue_free to complete
	await get_tree().process_frame
	
	# Create models ONLY for slots that have characters
	for i in range(characters.size()):
		print("[CharSelect3D] Creating model for slot %d" % i)
		var slot_node = slot_nodes[i]
		
		# Create character model
		var model = CharacterModelScene.instantiate()
		slot_node.add_child(model)
		
		# Configure animation controller for idle animation only
		var anim_ctrl = model.get_node_or_null("AnimationController")
		if anim_ctrl:
			anim_ctrl.auto_detect = false
			# Wait a frame for the animation player to be ready
			await get_tree().process_frame
			anim_ctrl.play_animation("Idle")
		
		character_models[i] = model
	
	print("[CharSelect3D] Setup complete. Models created: %d" % characters.size())


func _position_slider_for_index(index: int, animate: bool = true) -> void:
	"""Position the slider so the given index is centered at x=0."""
	var target_x = -index * SLOT_SPACING
	
	if animate and not is_transitioning:
		is_transitioning = true
		var tween = create_tween()
		tween.tween_property(character_slider, "position:x", target_x, SLIDE_DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_callback(_on_transition_finished)
	else:
		character_slider.position.x = target_x


func _on_transition_finished() -> void:
	"""Called when slide transition completes."""
	is_transitioning = false


func _input(event: InputEvent) -> void:
	# Don't process input if not visible
	if not visible:
		return
	
	# Don't process during transitions
	if is_transitioning:
		return
	
	# Don't process if delete dialog is open
	if delete_dialog.visible:
		return
	
	if event.is_action_pressed("ui_left"):
		_select_previous()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_select_next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _select_previous() -> void:
	"""Navigate to previous slot."""
	if current_index > 0:
		current_index -= 1
		_position_slider_for_index(current_index)
		_update_ui()
		_animate_arrow(left_arrow)


func _select_next() -> void:
	"""Navigate to next slot."""
	if current_index < MAX_SLOTS - 1:
		current_index += 1
		_position_slider_for_index(current_index)
		_update_ui()
		_animate_arrow(right_arrow)


func _animate_arrow(arrow: Label) -> void:
	"""Brief scale animation on arrow press."""
	var tween = create_tween()
	tween.tween_property(arrow, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(arrow, "scale", Vector2(1.0, 1.0), 0.1)


func _confirm_selection() -> void:
	"""Confirm current selection - play character or create new."""
	if current_index < characters.size():
		# Select existing character
		var char_data = characters[current_index]
		var char_id = char_data.get("id", 0)
		if player_node:
			enter_button.text = "ENTERING..."
			enter_button.disabled = true
			player_node.select_character(char_id)
	else:
		# Empty slot - go to character creation
		create_new_character.emit()


func _update_ui() -> void:
	"""Update all UI elements based on current state."""
	var has_character = current_index < characters.size()
	
	# Update character info
	if has_character:
		var c = characters[current_index]
		char_name_label.text = c.get("name", "Unknown")
		
		var level = c.get("level", 1)
		var char_class = CLASS_NAMES[c.get("class", 0)]
		var empire_name = EMPIRE_NAMES[c.get("empire", 0)]
		var empire_idx = c.get("empire", 0)
		
		char_details_label.text = "Lv.%d %s - %s" % [level, char_class, empire_name]
		
		# Color the name by empire
		char_name_label.add_theme_color_override("font_color", EMPIRE_COLORS[empire_idx])
		
		top_info.visible = true
		create_prompt.visible = false
		delete_button.disabled = false
		enter_button.text = "ENTER WORLD"
		enter_button.disabled = false
	else:
		# Empty slot
		top_info.visible = false
		create_prompt.visible = true
		delete_button.disabled = true
		enter_button.text = "CREATE"
		enter_button.disabled = false
	
	# Update dot indicators
	for i in range(MAX_SLOTS):
		if i == current_index:
			dot_labels[i].text = "●"
			dot_labels[i].add_theme_color_override("font_color", COLOR_GOLD)
		elif i < characters.size():
			dot_labels[i].text = "●"
			dot_labels[i].add_theme_color_override("font_color", COLOR_MUTED)
		else:
			dot_labels[i].text = "○"
			dot_labels[i].add_theme_color_override("font_color", Color(COLOR_MUTED.r, COLOR_MUTED.g, COLOR_MUTED.b, 0.4))
	
	# Update arrow visibility with animation
	_update_arrow_visibility()


func _update_arrow_visibility() -> void:
	"""Update arrow opacity based on navigation availability."""
	var left_alpha = 1.0 if current_index > 0 else 0.25
	var right_alpha = 1.0 if current_index < MAX_SLOTS - 1 else 0.25
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(left_arrow, "modulate:a", left_alpha, 0.15)
	tween.tween_property(right_arrow, "modulate:a", right_alpha, 0.15)


func _on_back_pressed() -> void:
	"""Handle back button / Escape key."""
	if player_node:
		player_node.disconnect_from_server()
	back_to_login.emit()


func _on_delete_pressed() -> void:
	"""Handle delete button - show confirmation dialog."""
	if current_index >= characters.size():
		return
	
	var c = characters[current_index]
	delete_dialog.dialog_text = ""
	delete_name_input.text = ""
	delete_name_input.placeholder_text = c.get("name", "")
	delete_dialog.popup_centered()
	delete_name_input.grab_focus()


func _on_delete_dialog_confirmed() -> void:
	"""Handle delete dialog confirmation."""
	if current_index >= characters.size():
		return
	
	var c = characters[current_index]
	var char_id = c.get("id", 0)
	var char_name = c.get("name", "")
	var entered_name = delete_name_input.text.strip_edges()
	
	if entered_name != char_name:
		# Name doesn't match - could show error
		return
	
	if player_node:
		player_node.delete_character(char_id, entered_name)


func _on_character_selected_success(character_id: int) -> void:
	"""Handle successful character selection."""
	character_selected.emit(character_id)


func _on_character_select_failed(reason: String) -> void:
	"""Handle failed character selection."""
	push_warning("Character select failed: %s" % reason)
	enter_button.text = "ENTER WORLD"
	enter_button.disabled = false


func _on_character_deleted(character_id: int) -> void:
	"""Handle successful character deletion."""
	# Refresh character list
	request_character_list()


func _on_character_delete_failed(reason: String) -> void:
	"""Handle failed character deletion."""
	push_warning("Character delete failed: %s" % reason)


func reset_form() -> void:
	"""Reset the form when shown."""
	current_index = 0
	enter_button.text = "ENTER WORLD"
	enter_button.disabled = false
	_update_ui()
