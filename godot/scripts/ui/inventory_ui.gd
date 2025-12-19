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

## Teleport Ring item ID
const TELEPORT_RING_ID: int = 100

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
	
	# Special Items
	100: {"name": "Teleport Ring", "description": "A magical ring that allows instant travel between villages.", "type": "special", "rarity": "rare"},
}

## Reference to local player
var local_player: Node = null

## Inventory data: array of {item_id: int, quantity: int} or null
var inventory_slots: Array = []

## Currently equipped weapon item ID (-1 = unarmed)
var equipped_weapon_id: int = -1

## Current gold
var current_gold: int = 0

## Window dragging state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

## Item drag & drop state
var is_dragging_item: bool = false
var drag_from_slot: int = -1
var drag_item_id: int = 0
var drag_item_quantity: int = 0
var drag_item_color: Color = Color.WHITE
var drag_preview: Control = null

## UI References
@onready var panel: Panel = $Panel
@onready var grid: GridContainer = $Panel/MarginContainer/VBoxContainer/GridContainer
@onready var header: HBoxContainer = $Panel/MarginContainer/VBoxContainer/Header
@onready var tooltip: Control = $Tooltip
@onready var tooltip_name: Label = $Tooltip/MarginContainer/VBox/ItemName
@onready var tooltip_type: Label = $Tooltip/MarginContainer/VBox/ItemType
@onready var tooltip_desc: Label = $Tooltip/MarginContainer/VBox/Description
@onready var tooltip_hint: Label = $Tooltip/MarginContainer/VBox/UseHint
@onready var tooltip_stats: Label = $Tooltip/MarginContainer/VBox/Stats

## Equipment panel references (created dynamically if not in scene)
var equipment_panel: Control = null
var weapon_slot: Control = null
var weapon_name_label: Label = null
var weapon_stats_label: Label = null

## Gold display references
var gold_panel: Control = null
var gold_label: Label = null

## Item slot scene
var ItemSlotScene = preload("res://scenes/ui/item_slot.tscn")

## Slot references
var slot_nodes: Array[Control] = []


func _ready() -> void:
	# Add to group so bottom bar can find us
	add_to_group("inventory_ui")
	
	# Register with UIManager for escape key handling
	UIManager.register_dialog(self)
	
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
	
	# Create gold display
	_create_gold_panel()
	
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
		# Connect to gold signals
		if local_player.has_signal("gold_updated"):
			local_player.connect("gold_updated", _on_gold_updated)
		if local_player.has_signal("stats_updated"):
			local_player.connect("stats_updated", _on_stats_updated)
		# Connect to character_selected to get initial gold value when entering game
		if local_player.has_signal("character_selected"):
			local_player.connect("character_selected", _on_character_selected)
		# Close inventory when teleporting to another zone
		if local_player.has_signal("zone_change"):
			local_player.connect("zone_change", _on_zone_change)
		# Load initial gold value (in case character is already selected)
		if local_player.has_method("get_gold"):
			current_gold = local_player.get_gold()
			_refresh_gold_display()


func _input(event: InputEvent) -> void:
	# Only process game inputs when actually in game
	if not _is_in_game():
		return
	
	# Don't toggle inventory if chat is focused
	if _is_chat_focused():
		return
	
	if event.is_action_pressed("toggle_inventory"):
		toggle_visibility()
		get_viewport().set_input_as_handled()
	# Note: Escape key is now handled by UIManager
	
	# Handle drag end when mouse released anywhere
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if is_dragging_item:
				_finish_item_drag()


func _process(_delta: float) -> void:
	# Update drag preview position to follow mouse
	if is_dragging_item and drag_preview and is_instance_valid(drag_preview):
		drag_preview.global_position = get_global_mouse_position() - Vector2(22, 22)


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and "current_state" in game_manager:
		# GameState.IN_GAME = 3
		return game_manager.current_state == 3
	# Fallback - assume we're in game if no game manager found
	return true


## Check if chat input is currently focused
func _is_chat_focused() -> bool:
	var chat_ui = get_tree().get_first_node_in_group("chat_ui")
	if chat_ui and chat_ui.has_method("is_input_focused"):
		return chat_ui.call("is_input_focused")
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
		slot.connect("drag_started", _on_item_drag_started)
		slot.connect("drag_ended", _on_item_drag_ended)
		grid.add_child(slot)
		slot_nodes.append(slot)


func _create_gold_panel() -> void:
	# Get the VBoxContainer that holds everything
	var vbox = $Panel/MarginContainer/VBoxContainer
	if not vbox:
		return
	
	# Create gold panel (horizontal container)
	gold_panel = HBoxContainer.new()
	gold_panel.name = "GoldPanel"
	gold_panel.add_theme_constant_override("separation", 8)
	gold_panel.alignment = BoxContainer.ALIGNMENT_END  # Right-align
	
	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# Gold icon placeholder (a small yellow square for now)
	var gold_icon = ColorRect.new()
	gold_icon.custom_minimum_size = Vector2(16, 16)
	gold_icon.color = Color(1.0, 0.85, 0.0, 1.0)  # Gold color
	gold_panel.add_child(gold_icon)
	
	# Gold label
	gold_label = Label.new()
	gold_label.text = "0"
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 1.0))  # Gold color
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_panel.add_child(gold_label)
	
	# Add gold panel at the end
	vbox.add_child(gold_panel)


func _refresh_gold_display() -> void:
	if gold_label:
		# Format gold with commas for readability
		gold_label.text = _format_gold(current_gold)


func _format_gold(amount: int) -> String:
	"""Format gold amount with commas for readability."""
	var str_amount = str(amount)
	var result = ""
	var count = 0
	for i in range(str_amount.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_amount[i] + result
		count += 1
	return result


func _on_gold_updated(gold: int) -> void:
	current_gold = gold
	_refresh_gold_display()


func _on_stats_updated(_level: int, _max_health: int, _max_mana: int, _attack: int, _defense: int, gold: int, _health: int, _mana: int) -> void:
	# Extract gold from stats update
	current_gold = gold
	_refresh_gold_display()


func _on_character_selected(_character_id: int) -> void:
	# Refresh gold when character is selected (entering game)
	if local_player and local_player.has_method("get_gold"):
		current_gold = local_player.get_gold()
		_refresh_gold_display()


func toggle_visibility() -> void:
	visible = not visible
	if visible:
		# Refresh gold from player when opening (in case it wasn't updated via signals)
		if local_player and local_player.has_method("get_gold"):
			current_gold = local_player.get_gold()
		refresh_display()
		_refresh_gold_display()
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


func _on_zone_change(_zone_id: int, _zone_name: String, _scene_path: String, _spawn_x: float, _spawn_y: float, _spawn_z: float) -> void:
	"""Close inventory when teleporting to another zone."""
	_cancel_item_drag()
	close_inventory()


# =============================================================================
# Item Drag & Drop
# =============================================================================

func _on_item_drag_started(slot_index: int) -> void:
	"""Called when user starts dragging an item from a slot."""
	var slot_data = inventory_slots[slot_index]
	if slot_data == null or not slot_data.has("item_id"):
		return
	
	is_dragging_item = true
	drag_from_slot = slot_index
	drag_item_id = slot_data["item_id"]
	drag_item_quantity = slot_data.get("quantity", 1)
	
	# Get the item color from the slot
	if slot_index < slot_nodes.size():
		drag_item_color = slot_nodes[slot_index].get_item_color()
	else:
		drag_item_color = Color(0.5, 0.5, 0.5)
	
	# Create ghost preview
	_create_drag_preview()
	
	# Hide tooltip during drag
	if tooltip:
		tooltip.visible = false
	
	print("Started dragging item from slot ", slot_index)


func _on_item_drag_ended(slot_index: int) -> void:
	"""Called when user releases mouse after dragging (from item_slot signal)."""
	# The actual logic is handled in _finish_item_drag() which is called from _input
	pass


func _finish_item_drag() -> void:
	"""Complete the drag operation - swap, drop, or cancel."""
	if not is_dragging_item:
		return
	
	# Find what slot (if any) is under the mouse
	var drop_target_slot = _get_slot_under_mouse()
	
	if drop_target_slot >= 0:
		if drop_target_slot != drag_from_slot:
			# Swap the slots
			if local_player and local_player.has_method("swap_inventory_slots"):
				local_player.swap_inventory_slots(drag_from_slot, drop_target_slot)
				print("Swapping slots ", drag_from_slot, " <-> ", drop_target_slot)
	else:
		# Dropped outside inventory - check if we should drop the item
		if not _is_mouse_over_inventory():
			if local_player and local_player.has_method("drop_item"):
				local_player.drop_item(drag_from_slot)
				print("Dropping item from slot ", drag_from_slot)
	
	_cancel_item_drag()


func _cancel_item_drag() -> void:
	"""Cancel the current drag operation and clean up."""
	is_dragging_item = false
	drag_from_slot = -1
	drag_item_id = 0
	drag_item_quantity = 0
	_destroy_drag_preview()


func _create_drag_preview() -> void:
	"""Create a ghost preview of the dragged item."""
	# Create a simple panel with border for the preview
	var preview_panel = Panel.new()
	preview_panel.custom_minimum_size = Vector2(44, 44)
	preview_panel.size = Vector2(44, 44)
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Style the panel with a border
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_color = Color(0.8, 0.8, 0.2, 1.0)  # Yellow border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	preview_panel.add_theme_stylebox_override("panel", style)
	
	# Add the item icon inside
	var icon_rect = ColorRect.new()
	icon_rect.set_anchors_preset(Control.PRESET_CENTER)
	icon_rect.size = Vector2(36, 36)
	icon_rect.position = Vector2(4, 4)
	icon_rect.color = drag_item_color
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(icon_rect)
	
	# Add quantity label if more than 1
	if drag_item_quantity > 1:
		var qty_label = Label.new()
		qty_label.text = str(drag_item_quantity)
		qty_label.position = Vector2(24, 26)
		qty_label.add_theme_font_size_override("font_size", 12)
		qty_label.add_theme_color_override("font_color", Color.WHITE)
		qty_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		qty_label.add_theme_constant_override("shadow_offset_x", 1)
		qty_label.add_theme_constant_override("shadow_offset_y", 1)
		qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_panel.add_child(qty_label)
	
	# Add directly to the CanvasLayer UI is on, with high z_index
	var ui_layer = get_parent().get_parent()  # Should be the UI CanvasLayer
	if ui_layer:
		ui_layer.add_child(preview_panel)
	else:
		get_tree().root.add_child(preview_panel)
	
	preview_panel.z_index = 100
	drag_preview = preview_panel
	
	# Position at mouse
	drag_preview.global_position = get_global_mouse_position() - Vector2(22, 22)


func _destroy_drag_preview() -> void:
	"""Remove and free the drag preview."""
	if drag_preview and is_instance_valid(drag_preview):
		drag_preview.queue_free()
		drag_preview = null


func _get_slot_under_mouse() -> int:
	"""Get the slot index under the current mouse position, or -1 if none."""
	var mouse_pos = get_global_mouse_position()
	for i in range(slot_nodes.size()):
		var slot = slot_nodes[i]
		var rect = Rect2(slot.global_position, slot.size)
		if rect.has_point(mouse_pos):
			return i
	return -1


func _is_mouse_over_inventory() -> bool:
	"""Check if the mouse is currently over the inventory panel."""
	if not panel:
		return false
	var mouse_pos = get_global_mouse_position()
	var rect = Rect2(panel.global_position, panel.size)
	return rect.has_point(mouse_pos)


func _on_slot_clicked(slot_index: int) -> void:
	print("Slot clicked: ", slot_index)


func _on_slot_right_clicked(slot_index: int) -> void:
	print("Slot right-clicked: ", slot_index)
	var slot_data = inventory_slots[slot_index]
	
	if slot_data != null and slot_data.has("item_id"):
		var item_id = slot_data["item_id"]
		var item_def = ITEM_DEFS.get(item_id, null)
		
		if not item_def:
			return
		
		# Special handling for Teleport Ring
		if item_id == TELEPORT_RING_ID:
			close_inventory()  # Close inventory first
			_open_teleport_dialog()
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
	elif item_def["type"] == "special":
		tooltip_hint.text = "[Right-click to use]"
		tooltip_hint.visible = true
	else:
		tooltip_hint.visible = false
	
	# Show tooltip and position it smartly
	tooltip.visible = true
	_position_tooltip_smart()


## Position tooltip smartly within viewport bounds
func _position_tooltip_smart() -> void:
	if not tooltip:
		return
	
	# Reset tooltip size so it can recalculate from content
	tooltip.reset_size()
	
	# Get mouse position and tooltip size
	var mouse_pos = get_global_mouse_position()
	var tooltip_size = tooltip.size
	var viewport_size = get_viewport_rect().size
	var margin = 15  # Distance from cursor
	
	# Start with bottom-right positioning (preferred)
	var pos = mouse_pos + Vector2(margin, margin)
	
	# Flip horizontally if it would overflow the right edge
	if pos.x + tooltip_size.x > viewport_size.x:
		pos.x = mouse_pos.x - tooltip_size.x - margin
	
	# Flip vertically if it would overflow the bottom edge
	if pos.y + tooltip_size.y > viewport_size.y:
		pos.y = mouse_pos.y - tooltip_size.y - margin
	
	# Final safety clamp to ensure it's always fully visible
	pos.x = clampf(pos.x, 0, viewport_size.x - tooltip_size.x)
	pos.y = clampf(pos.y, 0, viewport_size.y - tooltip_size.y)
	
	tooltip.global_position = pos


## Open the teleport dialog (for Teleport Ring)
func _open_teleport_dialog() -> void:
	print("Opening teleport dialog")
	
	# Find teleport dialog in the scene
	var teleport_dialog = get_tree().get_first_node_in_group("teleport_dialog")
	if teleport_dialog and teleport_dialog.has_method("show_dialog"):
		teleport_dialog.show_dialog()
	else:
		push_error("InventoryUI: Could not find teleport dialog!")
