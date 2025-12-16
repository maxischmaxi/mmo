extends Control
class_name InventoryUI
## Inventory UI with grid of item slots.

## Number of inventory slots
const SLOT_COUNT: int = 20
const SLOTS_PER_ROW: int = 5

## Item definitions (mirrored from shared/items.rs)
const ITEM_DEFS: Dictionary = {
	1: {"name": "Health Potion", "description": "Restores 50 health.", "type": "consumable", "color": Color(0.8, 0.2, 0.2)},
	2: {"name": "Mana Potion", "description": "Restores 30 mana.", "type": "consumable", "color": Color(0.2, 0.4, 0.9)},
	3: {"name": "Goblin Ear", "description": "A trophy from a slain goblin.", "type": "material", "color": Color(0.5, 0.4, 0.3)},
	4: {"name": "Rusty Sword", "description": "A worn blade. Better than nothing.", "type": "weapon", "color": Color(0.6, 0.6, 0.6)},
	5: {"name": "Iron Sword", "description": "A sturdy iron blade.", "type": "weapon", "color": Color(0.7, 0.7, 0.8)},
}

## Reference to local player
var local_player: Node = null

## Inventory data: array of {item_id: int, quantity: int} or null
var inventory_slots: Array = []

## UI References
@onready var grid: GridContainer = $Panel/MarginContainer/VBoxContainer/GridContainer
@onready var tooltip: Control = $Tooltip
@onready var tooltip_name: Label = $Tooltip/VBox/ItemName
@onready var tooltip_type: Label = $Tooltip/VBox/ItemType
@onready var tooltip_desc: Label = $Tooltip/VBox/Description
@onready var tooltip_hint: Label = $Tooltip/VBox/UseHint

## Item slot scene
var ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")

## Slot references
var slot_nodes: Array[Control] = []


func _ready() -> void:
	# Initialize inventory data
	for i in range(SLOT_COUNT):
		inventory_slots.append(null)
	
	# Create slot UI elements
	_create_slots()
	
	# Hide tooltip initially
	if tooltip:
		tooltip.visible = false
	
	# Start hidden
	visible = false
	
	# Find local player and connect signals
	await get_tree().process_frame
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	if local_player:
		local_player.connect("inventory_updated", _on_inventory_updated)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle_visibility()


func _create_slots() -> void:
	if not grid:
		return
	
	# Clear existing slots
	for child in grid.get_children():
		child.queue_free()
	slot_nodes.clear()
	
	# Create new slots
	for i in range(SLOT_COUNT):
		var slot = ItemSlotScene.instantiate()
		slot.slot_index = i
		slot.connect("slot_clicked", _on_slot_clicked)
		slot.connect("slot_right_clicked", _on_slot_right_clicked)
		slot.connect("slot_hovered", _on_slot_hovered)
		slot.connect("slot_unhovered", _on_slot_unhovered)
		grid.add_child(slot)
		slot_nodes.append(slot)


func toggle_visibility() -> void:
	visible = not visible
	if visible:
		refresh_display()
		# Release mouse when opening inventory
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func refresh_display() -> void:
	for i in range(min(slot_nodes.size(), inventory_slots.size())):
		var slot_data = inventory_slots[i]
		var slot_node = slot_nodes[i]
		
		if slot_data != null and slot_data.has("item_id"):
			var item_id = slot_data["item_id"]
			var quantity = slot_data.get("quantity", 1)
			var item_def = ITEM_DEFS.get(item_id, null)
			
			if item_def:
				slot_node.set_item(item_id, quantity, item_def["color"], item_def["name"])
			else:
				slot_node.set_item(item_id, quantity, Color(0.5, 0.5, 0.5), "Unknown")
		else:
			slot_node.clear_item()


func _on_inventory_updated() -> void:
	# TODO: Get actual inventory data from player/server
	# For now, just refresh display
	refresh_display()


func _on_slot_clicked(slot_index: int) -> void:
	print("Slot clicked: ", slot_index)
	# TODO: Implement slot selection / drag-drop


func _on_slot_right_clicked(slot_index: int) -> void:
	print("Slot right-clicked: ", slot_index)
	var slot_data = inventory_slots[slot_index]
	
	if slot_data != null and slot_data.has("item_id"):
		var item_id = slot_data["item_id"]
		var item_def = ITEM_DEFS.get(item_id, null)
		
		# Use consumables on right-click
		if item_def and item_def["type"] == "consumable":
			if local_player and local_player.has_method("use_item"):
				local_player.use_item(slot_index)
				print("Using item in slot ", slot_index)


func _on_slot_hovered(slot_index: int) -> void:
	var slot_data = inventory_slots[slot_index]
	
	if slot_data != null and slot_data.has("item_id"):
		var item_id = slot_data["item_id"]
		var item_def = ITEM_DEFS.get(item_id, null)
		
		if item_def and tooltip:
			tooltip_name.text = item_def["name"]
			tooltip_type.text = item_def["type"].capitalize()
			tooltip_desc.text = item_def["description"]
			
			if item_def["type"] == "consumable":
				tooltip_hint.text = "[Right-click to use]"
				tooltip_hint.visible = true
			else:
				tooltip_hint.visible = false
			
			# Position tooltip near mouse
			tooltip.global_position = get_global_mouse_position() + Vector2(15, 15)
			tooltip.visible = true


func _on_slot_unhovered(slot_index: int) -> void:
	if tooltip:
		tooltip.visible = false


## Set inventory data (called from network/server updates)
func set_inventory(slots: Array) -> void:
	inventory_slots = slots
	# Pad to SLOT_COUNT if needed
	while inventory_slots.size() < SLOT_COUNT:
		inventory_slots.append(null)
	refresh_display()


## Set a specific slot
func set_slot(index: int, item_id: int, quantity: int) -> void:
	if index >= 0 and index < SLOT_COUNT:
		inventory_slots[index] = {"item_id": item_id, "quantity": quantity}
		refresh_display()


## Clear a specific slot
func clear_slot(index: int) -> void:
	if index >= 0 and index < SLOT_COUNT:
		inventory_slots[index] = null
		refresh_display()
