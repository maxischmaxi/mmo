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

## Single character model instance (only the currently selected character)
var current_character_model: Node3D = null

## Slot container nodes (for positioning)
var slot_nodes: Array[Node3D] = []

## Dot indicator labels
var dot_labels: Array[Label] = []

## Character rotation state
var is_rotating_character: bool = false
var rotation_start_pos: Vector2 = Vector2.ZERO
var character_rotation: float = 0.0
const ROTATION_SENSITIVITY: float = 0.003

## Guard flag to prevent concurrent model creation
var _is_creating_model: bool = false

## Timestamp of last character list received (for debouncing)
var _last_character_list_time: float = 0.0
const CHARACTER_LIST_DEBOUNCE_MS: float = 100.0

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
	"""Remove the character model from the scene."""
	_clear_current_model()


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
	# Ignore duplicate character list responses if we're already processing one
	if _is_creating_model:
		print("[CharSelect3D] Ignoring duplicate character list (model creation in progress)")
		return
	
	# Debounce rapid duplicate character list responses
	var current_time = Time.get_ticks_msec()
	if current_time - _last_character_list_time < CHARACTER_LIST_DEBOUNCE_MS:
		print("[CharSelect3D] Ignoring duplicate character list (debounced)")
		return
	_last_character_list_time = current_time
	
	characters = char_list
	print("[CharSelect3D] Received %d characters" % characters.size())
	
	# Reset to first slot
	current_index = 0
	character_rotation = 0.0
	
	# Clear any existing model and create one for the first slot
	_clear_current_model()
	
	# No need to await since we now use synchronous removal
	_create_model_for_current_slot()
	
	# Position slider without recreating the model
	character_slider.position.x = 0
	
	_update_ui()


func _clear_current_model() -> void:
	"""Remove the current character model if it exists.
	Uses synchronous removal to prevent race conditions with model creation."""
	if current_character_model != null and is_instance_valid(current_character_model):
		# Synchronously remove from tree first, then queue for deletion
		if current_character_model.get_parent():
			current_character_model.get_parent().remove_child(current_character_model)
		current_character_model.queue_free()
	current_character_model = null
	
	# Also clear any children from all slot nodes (safety cleanup)
	# This catches any orphaned models that might exist
	for slot_node in slot_nodes:
		# Get children as array first to avoid modifying while iterating
		var children = slot_node.get_children()
		for child in children:
			if is_instance_valid(child):
				# Synchronously remove from tree first
				slot_node.remove_child(child)
				child.queue_free()


func _create_model_for_current_slot() -> void:
	"""Create a character model for the currently selected slot (if it has a character).
	Uses a guard flag to prevent concurrent model creation race conditions."""
	# Prevent concurrent model creation
	if _is_creating_model:
		print("[CharSelect3D] Model creation already in progress, skipping")
		return
	
	# Only create a model if the current slot has a character
	if current_index >= characters.size():
		print("[CharSelect3D] Slot %d is empty, no model to show" % current_index)
		return
	
	_is_creating_model = true
	
	# Double-check the slot is empty before creating (safety)
	var slot_node = slot_nodes[current_index]
	if slot_node.get_child_count() > 0:
		print("[CharSelect3D] WARNING: Slot %d already has children, clearing first" % current_index)
		for child in slot_node.get_children():
			slot_node.remove_child(child)
			child.queue_free()
	
	print("[CharSelect3D] Creating model for slot %d" % current_index)
	
	# Create character model
	var model = CharacterModelScene.instantiate()
	slot_node.add_child(model)
	
	# Assign to current_character_model IMMEDIATELY so it can be properly cleaned up
	current_character_model = model
	
	# Apply any stored rotation
	model.rotation.y = character_rotation
	
	# Set the model to render layer 2 (character select layer) for isolation
	_set_node_layer_recursive(model, 2)
	
	# Configure animation controller for idle animation only
	var anim_ctrl = model.get_node_or_null("AnimationController")
	if anim_ctrl:
		anim_ctrl.auto_detect = false
		# Start idle animation after a short delay (use call_deferred to avoid await issues)
		_setup_idle_animation.call_deferred(anim_ctrl, model)
	
	_is_creating_model = false
	print("[CharSelect3D] Model created and assigned")


func _setup_idle_animation(anim_ctrl: Node, model: Node3D) -> void:
	"""Setup idle animation for the character model (deferred to avoid await issues)."""
	# Check if the model is still valid and is our current model
	if not is_instance_valid(model) or model != current_character_model:
		return
	
	if anim_ctrl and anim_ctrl.has_method("play_animation"):
		anim_ctrl.play_animation("Idle")


func _set_node_layer_recursive(node: Node, layer: int) -> void:
	"""Recursively set the visual layer for all VisualInstance3D nodes."""
	if node is VisualInstance3D:
		# Clear all layers and set only the specified one
		node.layers = 1 << (layer - 1)
	
	for child in node.get_children():
		_set_node_layer_recursive(child, layer)


func _position_slider_for_index(index: int, animate: bool = true) -> void:
	"""Position the slider so the given index is centered at x=0 and show the character."""
	var target_x = -index * SLOT_SPACING
	
	# If model creation is in progress, wait for it to complete
	if _is_creating_model:
		print("[CharSelect3D] Waiting for model creation to complete before navigating")
		return
	
	# Clear old model and create new one for the current slot
	# No need to await since we now use synchronous removal
	_clear_current_model()
	_create_model_for_current_slot()
	
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
	
	# Handle mouse input for character rotation
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Start rotation if we have a character in the current slot
				if current_index < characters.size():
					is_rotating_character = true
					rotation_start_pos = mouse_event.position
					get_viewport().set_input_as_handled()
			else:
				# Stop rotation
				is_rotating_character = false
	
	elif event is InputEventMouseMotion and is_rotating_character:
		var motion_event := event as InputEventMouseMotion
		var delta_x := motion_event.relative.x
		character_rotation += delta_x * ROTATION_SENSITIVITY
		_apply_character_rotation()
		get_viewport().set_input_as_handled()
	
	# Keyboard navigation
	elif event.is_action_pressed("ui_left"):
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
		character_rotation = 0.0  # Reset rotation for new character
		current_index -= 1
		_position_slider_for_index(current_index)
		_update_ui()
		_animate_arrow(left_arrow)


func _select_next() -> void:
	"""Navigate to next slot."""
	if current_index < MAX_SLOTS - 1:
		character_rotation = 0.0  # Reset rotation for new character
		current_index += 1
		_position_slider_for_index(current_index)
		_update_ui()
		_animate_arrow(right_arrow)


func _animate_arrow(arrow: Label) -> void:
	"""Brief scale animation on arrow press."""
	var tween = create_tween()
	tween.tween_property(arrow, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(arrow, "scale", Vector2(1.0, 1.0), 0.1)


func _apply_character_rotation() -> void:
	"""Apply the current rotation to the current character model."""
	if current_character_model != null:
		current_character_model.rotation.y = character_rotation


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


func _debug_count_character_models() -> void:
	"""DEBUG: Count all nodes named 'CharacterModel' or 'Rig' in the entire scene tree."""
	var root = get_tree().root
	
	print("[DEBUG] ========================================")
	print("[DEBUG] Searching for all CharacterModel and Rig nodes...")
	
	var char_models = _find_nodes_by_name(root, "CharacterModel")
	var rigs = _find_nodes_by_name(root, "Rig")
	
	print("[DEBUG] Found %d CharacterModel nodes:" % char_models.size())
	for node in char_models:
		var vis_str = "N/A"
		var global_vis_str = "N/A"
		if node is Node3D:
			vis_str = str(node.visible)
			# Check if any parent is hidden
			var parent = node.get_parent()
			var effectively_visible = node.visible
			while parent:
				if parent is Node3D and not parent.visible:
					effectively_visible = false
					break
				if parent is CanvasItem and not parent.visible:
					effectively_visible = false
					break
				parent = parent.get_parent()
			global_vis_str = str(effectively_visible)
		print("[DEBUG]   - %s" % node.get_path())
		print("[DEBUG]     visible=%s, effectively_visible=%s, parent=%s" % [vis_str, global_vis_str, node.get_parent().name if node.get_parent() else "none"])
	
	print("[DEBUG] Found %d Rig nodes:" % rigs.size())
	for node in rigs:
		var vis_str = "N/A"
		if node is Node3D:
			vis_str = str(node.visible)
		print("[DEBUG]   - %s (visible: %s)" % [node.get_path(), vis_str])
	
	# Also check the Player node specifically
	var player = get_tree().get_first_node_in_group("local_player")
	if player:
		print("[DEBUG] Player node: %s" % player.get_path())
		print("[DEBUG]   visible: %s" % player.visible)
		print("[DEBUG]   position: %s" % player.global_position)
		var player_camera = player.get_node_or_null("CameraController/SpringArm3D/Camera3D")
		if player_camera:
			print("[DEBUG]   Camera current: %s" % player_camera.current)
	else:
		print("[DEBUG] Player node NOT FOUND in local_player group!")
	
	print("[DEBUG] ========================================")


func _find_nodes_by_name(node: Node, search_name: String) -> Array:
	var result = []
	if node.name == search_name:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_nodes_by_name(child, search_name))
	return result


func _count_nodes_recursive(node: Node, search_name: String, count: int, results: Array) -> void:
	if node.name == search_name:
		count += 1
		results.append(node)
	for child in node.get_children():
		_count_nodes_recursive(child, search_name, count, results)
