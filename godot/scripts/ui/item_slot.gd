extends Control
class_name ItemSlot
## Single inventory slot that can hold an item.
## Supports drag & drop for rearranging items.

## Slot index in the inventory
var slot_index: int = 0

## Current item data
var item_id: int = 0
var item_quantity: int = 0
var is_empty: bool = true

## Drag state
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float = 5.0  # Pixels to move before drag starts

## Signals
signal slot_clicked(index: int)
signal slot_right_clicked(index: int)
signal slot_hovered(index: int)
signal slot_unhovered(index: int)
signal drag_started(index: int)
signal drag_ended(index: int)

## UI References
@onready var background: Panel = $Background
@onready var icon: ColorRect = $Icon
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
				if not is_empty:
					# Start potential drag
					drag_start_pos = mouse_event.position
				else:
					emit_signal("slot_clicked", slot_index)
			else:
				# Mouse released
				if is_dragging:
					is_dragging = false
					emit_signal("drag_ended", slot_index)
				elif not is_empty:
					# Was a click, not a drag
					emit_signal("slot_clicked", slot_index)
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			emit_signal("slot_right_clicked", slot_index)
	
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not is_empty and not is_dragging:
			var distance = event.position.distance_to(drag_start_pos)
			if distance > DRAG_THRESHOLD:
				is_dragging = true
				emit_signal("drag_started", slot_index)


func _on_mouse_entered() -> void:
	if highlight:
		highlight.visible = true
	if not is_empty:
		emit_signal("slot_hovered", slot_index)


func _on_mouse_exited() -> void:
	if highlight:
		highlight.visible = false
	emit_signal("slot_unhovered", slot_index)


## Set item in this slot
func set_item(id: int, quantity: int, color: Color, _name: String = "") -> void:
	item_id = id
	item_quantity = quantity
	is_empty = false
	
	if icon:
		icon.visible = true
		icon.color = color
	
	if quantity_label:
		if quantity > 1:
			quantity_label.text = str(quantity)
			quantity_label.visible = true
		else:
			quantity_label.visible = false


## Clear this slot
func clear_item() -> void:
	item_id = 0
	item_quantity = 0
	is_empty = true
	
	if icon:
		icon.visible = false
	
	if quantity_label:
		quantity_label.visible = false


## Get the item color for drag preview
func get_item_color() -> Color:
	if icon:
		return icon.color
	return Color(0.5, 0.5, 0.5)
