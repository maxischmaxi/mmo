extends Control
class_name InventoryUI
## Inventory UI with equipment panel and grid of item slots.

## Number of inventory slots
const SLOT_COUNT: int = 20
const SLOTS_PER_ROW: int = 5

## Rarity colors
const RARITY_COLORS: Dictionary = {
	"common": Color(0.7, 0.7, 0.7),
	"uncommon": Color(0.3, 0.8, 0.3),
	"rare": Color(0.3, 0.5, 1.0),
	"epic": Color(0.6, 0.3, 0.9),
	"legendary": Color(1.0, 0.6, 0.0),
}

## Item definitions (mirrored from server database)
const ITEM_DEFS: Dictionary = {
	# Consumables and Materials (IDs 1-3)
	1: {"name": "Health Potion", "description": "Restores 50 health.", "type": "consumable", "rarity": "common"},
	2: {"name": "Mana Potion", "description": "Restores 30 mana.", "type": "consumable", "rarity": "common"},
	3: {"name": "Goblin Ear", "description": "A trophy from a slain goblin.", "type": "material", "rarity": "common"},
	
	# Universal Weapons (IDs 4-5)
	4: {"name": "Rusty Sword", "description": "A worn blade. Better than nothing.", "type": "weapon", "rarity": "common", "damage": 8, "speed": 1.0, "class": "any"},
	5: {"name": "Iron Sword", "description": "A sturdy iron blade.", "type": "weapon", "rarity": "uncommon", "damage": 12, "speed": 1.0, "class": "any"},
	
	# Ninja Weapons (IDs 10-11)
	10: {"name": "Shadow Dagger", "description": "A swift blade favored by ninjas.", "type": "weapon", "rarity": "common", "damage": 10, "speed": 1.3, "class": "ninja"},
	11: {"name": "Viper's Fang", "description": "A deadly dagger that strikes like a serpent.", "type": "weapon", "rarity": "rare", "damage": 18, "speed": 1.4, "class": "ninja"},
	
	# Warrior Weapons (IDs 12-13)
	12: {"name": "Steel Claymore", "description": "A heavy two-handed sword for warriors.", "type": "weapon", "rarity": "common", "damage": 16, "speed": 0.85, "class": "warrior"},
	13: {"name": "Berserker's Axe", "description": "A massive axe that cleaves through armor.", "type": "weapon", "rarity": "rare", "damage": 26, "speed": 0.8, "class": "warrior"},
	
	# Sura Weapons (IDs 14-15)
	14: {"name": "Cursed Scimitar", "description": "A blade infused with dark magic.", "type": "weapon", "rarity": "common", "damage": 12, "speed": 1.15, "class": "sura"},
	15: {"name": "Soulreaver Blade", "description": "A sword that hungers for souls.", "type": "weapon", "rarity": "rare", "damage": 22, "speed": 1.2, "class": "sura"},
	
	# Shaman Weapons (IDs 16-17)
	16: {"name": "Oak Staff", "description": "A simple staff for channeling nature magic.", "type": "weapon", "rarity": "common", "damage": 8, "speed": 1.0, "class": "shaman"},
	17: {"name": "Spirit Totem", "description": "A totem imbued with ancestral spirits.", "type": "weapon", "rarity": "rare", "damage": 14, "speed": 1.1, "class": "shaman"},
}

## Reference to local player
var local_player: Node = null

## Inventory data: array of {item_id: int, quantity: int} or null
var inventory_slots: Array = []

## Currently equipped weapon item ID (-1 = unarmed)
var equipped_weapon_id: int = -1

## Dragging state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

## UI References
@onready var panel: Panel = $Panel
@onready var grid: GridContainer = $Panel/MarginContainer/VBoxContainer/GridContainer
@onready var header: HBoxContainer = $Panel/MarginContainer/VBoxContainer/Header
@onready var tooltip: Control = $Tooltip
@onready var tooltip_name: Label = $Tooltip/VBox/ItemName
@onready var tooltip_type: Label = $Tooltip/VBox/ItemType
@onready var tooltip_desc: Label = $Tooltip/VBox/Description
@onready var tooltip_hint: Label = $Tooltip/VBox/UseHint
@onready var tooltip_stats: Label = $Tooltip/VBox/Stats

## Equipment panel references (created dynamically if not in scene)
var equipment_panel: Control = null
var weapon_slot: Control = null
var weapon_name_label: Label = null
var weapon_stats_label: Label = null

## Item slot scene
var ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")

## Slot references
var slot_nodes: Array[Control] = []


func _ready() -> void:
	# Add to group so bottom bar can find us
	add_to_group("inventory_ui")
	
	# Initialize inventory data
	for i in range(SLOT_COUNT):
		inventory_slots.append(null)
	
	# Connect header for dragging
	if header:
		header.gui_input.connect(_on_header_gui_input)
		header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	
	# Connect to viewport resize
	get_tree().root.size_changed.connect(_on_viewport_resized)
	
	# Create equipment panel
	_create_equipment_panel()
	
	# Create slot UI elements
	_create_slots()
	
	# Hide tooltip initially
	if tooltip:
		tooltip.visible = false
	
	# Start hidden
	visible = false
	
	# Resize window to fit content after a frame (so layout is calculated)
	await get_tree().process_frame
	_resize_to_fit_content()
	
	# Center inventory on first show
	_center_on_screen()
	
	# Find local player and connect signals
	await get_tree().process_frame
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	if local_player:
		local_player.connect("inventory_updated", _on_inventory_updated)
		local_player.connect("equipment_changed", _on_equipment_changed)


func _input(event: InputEvent) -> void:
	# Only process game inputs when actually in game
	if not _is_in_game():
		return
	
	if event.is_action_pressed("toggle_inventory"):
		toggle_visibility()
		get_viewport().set_input_as_handled()
	# Close with Escape when visible
	elif event.is_action_pressed("ui_cancel") and visible:
		close_inventory()
		get_viewport().set_input_as_handled()


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("get") and "current_state" in game_manager:
		# GameState.IN_GAME = 3
		return game_manager.current_state == 3
	return false


# =============================================================================
# Dragging and Window Management
# =============================================================================

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Start dragging
				is_dragging = true
				drag_offset = global_position - get_global_mouse_position()
			else:
				# Stop dragging
				is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		# Move the window
		global_position = get_global_mouse_position() + drag_offset
		_clamp_to_viewport()


func _clamp_to_viewport() -> void:
	"""Ensure the inventory window stays within the viewport bounds."""
	var viewport_size = get_viewport_rect().size
	var window_size = size
	
	# Clamp position to keep window fully visible
	var new_pos = global_position
	new_pos.x = clampf(new_pos.x, 0, viewport_size.x - window_size.x)
	new_pos.y = clampf(new_pos.y, 0, viewport_size.y - window_size.y)
	global_position = new_pos


func _on_viewport_resized() -> void:
	"""Handle viewport resize - keep inventory in bounds."""
	# Wait a frame for the resize to fully apply
	await get_tree().process_frame
	_clamp_to_viewport()


func _center_on_screen() -> void:
	"""Center the inventory window on the screen."""
	var viewport_size = get_viewport_rect().size
	var window_size = size
	global_position = (viewport_size - window_size) / 2


func _resize_to_fit_content() -> void:
	"""Resize the inventory window to exactly fit its content."""
	var vbox = $Panel/MarginContainer/VBoxContainer
	var margin_container = $Panel/MarginContainer
	
	if not vbox or not margin_container:
		return
	
	# Calculate content size from VBoxContainer
	var content_size = vbox.get_combined_minimum_size()
	
	# Add margins
	var margin_left = margin_container.get_theme_constant("margin_left")
	var margin_right = margin_container.get_theme_constant("margin_right")
	var margin_top = margin_container.get_theme_constant("margin_top")
	var margin_bottom = margin_container.get_theme_constant("margin_bottom")
	
	var total_size = Vector2(
		content_size.x + margin_left + margin_right,
		content_size.y + margin_top + margin_bottom
	)
	
	# Set our size to match
	size = total_size
	custom_minimum_size = total_size


func close_inventory() -> void:
	visible = false
	if tooltip:
		tooltip.visible = false


func _create_equipment_panel() -> void:
	# Get the VBoxContainer that holds everything
	var vbox = $Panel/MarginContainer/VBoxContainer
	if not vbox:
		return
	
	# Create equipment section container
	equipment_panel = VBoxContainer.new()
	equipment_panel.name = "EquipmentPanel"
	equipment_panel.add_theme_constant_override("separation", 5)
	
	# Equipment header
	var equip_header = Label.new()
	equip_header.text = "EQUIPMENT"
	equip_header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6, 1))
	equip_header.add_theme_font_size_override("font_size", 14)
	equipment_panel.add_child(equip_header)
	
	# Weapon slot container (horizontal)
	var weapon_container = HBoxContainer.new()
	weapon_container.add_theme_constant_override("separation", 10)
	
	# Weapon slot (visual)
	weapon_slot = ItemSlotScene.instantiate()
	weapon_slot.slot_index = -1  # Special index for equipment
	weapon_slot.connect("slot_clicked", _on_weapon_slot_clicked)
	weapon_slot.connect("slot_right_clicked", _on_weapon_slot_right_clicked)
	weapon_slot.connect("slot_hovered", _on_weapon_slot_hovered)
	weapon_slot.connect("slot_unhovered", _on_weapon_slot_unhovered)
	weapon_container.add_child(weapon_slot)
	
	# Weapon info
	var weapon_info = VBoxContainer.new()
	weapon_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	weapon_name_label = Label.new()
	weapon_name_label.text = "[Unarmed]"
	weapon_name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	weapon_info.add_child(weapon_name_label)
	
	weapon_stats_label = Label.new()
	weapon_stats_label.text = ""
	weapon_stats_label.add_theme_font_size_override("font_size", 12)
	weapon_stats_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	weapon_info.add_child(weapon_stats_label)
	
	weapon_container.add_child(weapon_info)
	equipment_panel.add_child(weapon_container)
	
	# Separator
	var sep = HSeparator.new()
	equipment_panel.add_child(sep)
	
	# Insert equipment panel AFTER the Header (index 1)
	vbox.add_child(equipment_panel)
	vbox.move_child(equipment_panel, 1)


func _create_slots() -> void:
	if not grid:
		return
	
	# Set grid columns
	grid.columns = SLOTS_PER_ROW
	
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
	# Update inventory slots
	for i in range(min(slot_nodes.size(), inventory_slots.size())):
		var slot_data = inventory_slots[i]
		var slot_node = slot_nodes[i]
		
		if slot_data != null and slot_data.has("item_id"):
			var item_id = slot_data["item_id"]
			var quantity = slot_data.get("quantity", 1)
			var item_def = ITEM_DEFS.get(item_id, null)
			
			if item_def:
				var rarity = item_def.get("rarity", "common")
				var color = RARITY_COLORS.get(rarity, RARITY_COLORS["common"])
				slot_node.set_item(item_id, quantity, color, item_def["name"])
			else:
				slot_node.set_item(item_id, quantity, Color(0.5, 0.5, 0.5), "Unknown")
		else:
			slot_node.clear_item()
	
	# Update equipment display
	_refresh_equipment_display()


func _refresh_equipment_display() -> void:
	if not weapon_slot:
		return
	
	if equipped_weapon_id > 0:
		var item_def = ITEM_DEFS.get(equipped_weapon_id, null)
		if item_def:
			var rarity = item_def.get("rarity", "common")
			var color = RARITY_COLORS.get(rarity, RARITY_COLORS["common"])
			weapon_slot.set_item(equipped_weapon_id, 1, color, item_def["name"])
			
			if weapon_name_label:
				weapon_name_label.text = item_def["name"]
				weapon_name_label.add_theme_color_override("font_color", color)
			
			if weapon_stats_label:
				var damage = item_def.get("damage", 0)
				var speed = item_def.get("speed", 1.0)
				weapon_stats_label.text = "Dmg: %d  Spd: %.2fx" % [damage, speed]
		else:
			weapon_slot.set_item(equipped_weapon_id, 1, Color(0.5, 0.5, 0.5), "Unknown")
			if weapon_name_label:
				weapon_name_label.text = "Unknown Weapon"
			if weapon_stats_label:
				weapon_stats_label.text = ""
	else:
		weapon_slot.clear_item()
		if weapon_name_label:
			weapon_name_label.text = "[Unarmed]"
			weapon_name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		if weapon_stats_label:
			weapon_stats_label.text = "Dmg: Reduced"


func _on_inventory_updated() -> void:
	# Get inventory data from player
	if local_player and local_player.has_method("get_inventory_slot"):
		for i in range(SLOT_COUNT):
			var slot_data = local_player.get_inventory_slot(i)
			if slot_data.has("item_id"):
				inventory_slots[i] = {"item_id": slot_data["item_id"], "quantity": slot_data.get("quantity", 1)}
			else:
				inventory_slots[i] = null
	refresh_display()


func _on_equipment_changed(weapon_id: int) -> void:
	equipped_weapon_id = weapon_id
	_refresh_equipment_display()


func _on_slot_clicked(slot_index: int) -> void:
	print("Slot clicked: ", slot_index)
	# TODO: Implement slot selection / drag-drop


func _on_slot_right_clicked(slot_index: int) -> void:
	print("Slot right-clicked: ", slot_index)
	var slot_data = inventory_slots[slot_index]
	
	if slot_data != null and slot_data.has("item_id"):
		var item_id = slot_data["item_id"]
		var item_def = ITEM_DEFS.get(item_id, null)
		
		if not item_def:
			return
		
		# Use consumables on right-click
		if item_def["type"] == "consumable":
			if local_player and local_player.has_method("use_item"):
				local_player.use_item(slot_index)
				print("Using item in slot ", slot_index)
		# Equip weapons on right-click
		elif item_def["type"] == "weapon":
			if local_player and local_player.has_method("equip_item"):
				local_player.equip_item(slot_index)
				print("Equipping weapon from slot ", slot_index)


func _on_slot_hovered(slot_index: int) -> void:
	var slot_data = inventory_slots[slot_index]
	
	if slot_data != null and slot_data.has("item_id"):
		var item_id = slot_data["item_id"]
		var item_def = ITEM_DEFS.get(item_id, null)
		
		if item_def and tooltip:
			_show_tooltip_for_item(item_def, false)


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


# =============================================================================
# Equipment Slot Handlers
# =============================================================================

func _on_weapon_slot_clicked(_slot_index: int) -> void:
	# Left-click on weapon slot does nothing for now
	pass


func _on_weapon_slot_right_clicked(_slot_index: int) -> void:
	# Right-click on equipped weapon to unequip
	if equipped_weapon_id > 0:
		if local_player and local_player.has_method("unequip_item"):
			local_player.unequip_item("weapon")
			print("Unequipping weapon")


func _on_weapon_slot_hovered(_slot_index: int) -> void:
	if equipped_weapon_id > 0:
		var item_def = ITEM_DEFS.get(equipped_weapon_id, null)
		if item_def and tooltip:
			_show_tooltip_for_item(item_def, true)


func _on_weapon_slot_unhovered(_slot_index: int) -> void:
	if tooltip:
		tooltip.visible = false


func _show_tooltip_for_item(item_def: Dictionary, is_equipped: bool = false) -> void:
	tooltip_name.text = item_def["name"]
	
	var type_text = item_def["type"].capitalize()
	if item_def["type"] == "weapon":
		var class_restriction = item_def.get("class", "any")
		if class_restriction != "any":
			type_text += " (%s)" % class_restriction.capitalize()
	tooltip_type.text = type_text
	
	tooltip_desc.text = item_def["description"]
	
	# Set rarity color on name
	var rarity = item_def.get("rarity", "common")
	var color = RARITY_COLORS.get(rarity, RARITY_COLORS["common"])
	tooltip_name.add_theme_color_override("font_color", color)
	
	# Show weapon stats if applicable
	if tooltip_stats and item_def["type"] == "weapon":
		var damage = item_def.get("damage", 0)
		var speed = item_def.get("speed", 1.0)
		tooltip_stats.text = "Damage: %d | Speed: %.2fx" % [damage, speed]
		tooltip_stats.visible = true
	elif tooltip_stats:
		tooltip_stats.visible = false
	
	# Show hint
	if item_def["type"] == "consumable":
		tooltip_hint.text = "[Right-click to use]"
		tooltip_hint.visible = true
	elif item_def["type"] == "weapon":
		if is_equipped:
			tooltip_hint.text = "[Right-click to unequip]"
		else:
			tooltip_hint.text = "[Right-click to equip]"
		tooltip_hint.visible = true
	else:
		tooltip_hint.visible = false
	
	# Position tooltip near mouse
	tooltip.global_position = get_global_mouse_position() + Vector2(15, 15)
	tooltip.visible = true
