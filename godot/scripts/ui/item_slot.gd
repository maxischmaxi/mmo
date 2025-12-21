extends Control
class_name ItemSlot
## Single inventory slot that can hold an item.
## Supports drag & drop for rearranging items.
## Displays 3D weapon icons when available, falls back to color for other items.
## Multi-slot items occupy multiple VERTICAL slots (like Metin2).
## Primary slot expands downward to cover continuation slots.

## Slot index in the inventory
var slot_index: int = 0

## Current item data
var item_id: int = 0
var item_quantity: int = 0
var is_empty: bool = true
var has_icon_texture: bool = false

## Multi-slot state
var current_slot_size: int = 1  # How many vertical slots this item occupies
var is_continuation: bool = false  # True if this slot is covered by item above
var continuation_of_slot: int = -1  # Index of the primary slot

## Drag state
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float = 5.0  # Pixels to move before drag starts

## Slot dimensions
const SLOT_SIZE: float = 50.0
const SLOT_SPACING: float = 3.0  # Gap between slots in grid (matches GridContainer v_separation)

## Signals
signal slot_clicked(index: int)
signal slot_right_clicked(index: int)
signal slot_hovered(index: int)
signal slot_unhovered(index: int)
signal drag_started(index: int)
signal drag_ended(index: int)

## UI References
@onready var background: Panel = $Background
@onready var icon_placeholder: ColorRect = $IconPlaceholder
@onready var icon_texture: TextureRect = $IconTexture
@onready var quantity_label: Label = $QuantityLabel
@onready var highlight: ColorRect = $Highlight


func _ready() -> void:
	# Set up mouse events
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	
	# Initialize display
	clear_item()
	
	if highlight:
		highlight.visible = false


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# For continuation slots, redirect to the primary slot
				var effective_slot = continuation_of_slot if is_continuation else slot_index
				if not is_empty:
					# Start potential drag
					drag_start_pos = mouse_event.position
				else:
					emit_signal("slot_clicked", effective_slot)
			else:
				# Mouse released
				var effective_slot = continuation_of_slot if is_continuation else slot_index
				if is_dragging:
					is_dragging = false
					emit_signal("drag_ended", effective_slot)
				elif not is_empty:
					# Was a click, not a drag
					emit_signal("slot_clicked", effective_slot)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			# For continuation slots, redirect to the primary slot
			var effective_slot = continuation_of_slot if is_continuation else slot_index
			emit_signal("slot_right_clicked", effective_slot)
	
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_empty and not is_dragging:
			var distance = event.position.distance_to(drag_start_pos)
			if distance > DRAG_THRESHOLD:
				is_dragging = true
				# For continuation slots, redirect to the primary slot
				var effective_slot = continuation_of_slot if is_continuation else slot_index
				emit_signal("drag_started", effective_slot)


func _on_mouse_entered() -> void:
	if highlight:
		highlight.visible = true
	if not is_empty:
		# For continuation slots, redirect to the primary slot
		var effective_slot = continuation_of_slot if is_continuation else slot_index
		emit_signal("slot_hovered", effective_slot)


func _on_mouse_exited() -> void:
	if highlight:
		highlight.visible = false
	# For continuation slots, redirect to the primary slot
	var effective_slot = continuation_of_slot if is_continuation else slot_index
	emit_signal("slot_unhovered", effective_slot)


## Set item in this slot (primary slot for the item)
## slot_size: how many vertical slots this item occupies (1, 2, or 3)
func set_item(id: int, quantity: int, color: Color, _name: String = "", slot_size: int = 1) -> void:
	item_id = id
	item_quantity = quantity
	is_empty = false
	has_icon_texture = false
	is_continuation = false
	continuation_of_slot = -1
	current_slot_size = slot_size
	
	# Expand slot vertically if multi-slot item
	_update_slot_height(slot_size)
	
	# Try to get icon texture from ItemIconManager
	if ItemIconManager.has_model(id):
		# Check if already cached
		var cached_icon = ItemIconManager.get_item_icon(id)
		if cached_icon:
			_show_texture_icon(cached_icon)
		else:
			# Request async generation, show placeholder meanwhile
			_show_placeholder_icon(color)
			ItemIconManager.request_item_icon(id, _on_icon_ready)
	else:
		# No 3D model for this item, use colored placeholder
		_show_placeholder_icon(color)
	
	# Update quantity label
	if quantity_label:
		if quantity > 1:
			quantity_label.text = str(quantity)
			quantity_label.visible = true
		else:
			quantity_label.visible = false
	
	# Ensure we're on top of continuation slots (higher z-index)
	z_index = 1


## Set this slot as a continuation of another slot's multi-slot item
## This slot will be hidden as the primary slot expands over it
func set_continuation_slot(primary_slot: int) -> void:
	item_id = 0
	item_quantity = 0
	is_empty = false  # Not empty, but belongs to another slot's item
	is_continuation = true
	continuation_of_slot = primary_slot
	current_slot_size = 1
	has_icon_texture = false
	
	# Reset to standard height
	_update_slot_height(1)
	
	# Hide everything - the primary slot will visually cover this
	if icon_placeholder:
		icon_placeholder.visible = false
	if icon_texture:
		icon_texture.visible = false
		icon_texture.texture = null
	if quantity_label:
		quantity_label.visible = false
	if background:
		background.visible = false
	if highlight:
		highlight.visible = false
	
	# Lower z-index so primary slot renders on top
	z_index = 0


## Update the slot height for multi-slot items (vertical expansion)
func _update_slot_height(slot_size: int) -> void:
	var target_height: float
	if slot_size <= 1:
		target_height = SLOT_SIZE
	else:
		# Height = (slot_size * slot_height) + ((slot_size - 1) * spacing between rows)
		target_height = (slot_size * SLOT_SIZE) + ((slot_size - 1) * SLOT_SPACING)
	
	# Update our size
	custom_minimum_size = Vector2(SLOT_SIZE, target_height)
	size = Vector2(SLOT_SIZE, target_height)
	
	# Make sure background is visible and covers full area
	if background:
		background.visible = true
		# Background uses anchors, so it will auto-resize


## Callback when async icon is ready
func _on_icon_ready(received_item_id: int, texture: Texture2D) -> void:
	# Make sure this is still the item we're showing
	if received_item_id != item_id or is_empty:
		return
	
	if texture:
		_show_texture_icon(texture)


## Show the texture icon (from 3D model)
func _show_texture_icon(texture: Texture2D) -> void:
	has_icon_texture = true
	
	if icon_texture:
		icon_texture.texture = texture
		icon_texture.visible = true
	
	if icon_placeholder:
		icon_placeholder.visible = false


## Show the placeholder icon (colored rectangle)
func _show_placeholder_icon(color: Color) -> void:
	has_icon_texture = false
	
	if icon_placeholder:
		icon_placeholder.visible = true
		icon_placeholder.color = color
	
	if icon_texture:
		icon_texture.visible = false


## Clear this slot
func clear_item() -> void:
	item_id = 0
	item_quantity = 0
	is_empty = true
	has_icon_texture = false
	is_continuation = false
	continuation_of_slot = -1
	current_slot_size = 1
	
	# Reset to standard height
	_update_slot_height(1)
	
	# Show background again
	if background:
		background.visible = true
	
	if icon_placeholder:
		icon_placeholder.visible = false
	
	if icon_texture:
		icon_texture.visible = false
		icon_texture.texture = null
	
	if quantity_label:
		quantity_label.visible = false
	
	# Reset z-index
	z_index = 0


## Get the item color for drag preview (fallback color)
func get_item_color() -> Color:
	if icon_placeholder:
		return icon_placeholder.color
	return Color(0.5, 0.5, 0.5)


## Get the item icon texture (if available)
func get_item_texture() -> Texture2D:
	if has_icon_texture and icon_texture:
		return icon_texture.texture
	return null


## Check if this slot has a 3D icon texture
func has_texture_icon() -> bool:
	return has_icon_texture
