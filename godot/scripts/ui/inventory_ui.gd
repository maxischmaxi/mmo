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

## Item slot sizes (how many horizontal inventory slots the item occupies)
## Daggers = 1, One-handed = 2, Two-handed/Staffs = 3, Others = 1
const ITEM_SLOT_SIZES: Dictionary = {
	# Universal weapons
	4: 2,   # Rusty Sword (one-handed)
	5: 2,   # Iron Sword (one-handed)
	# Ninja weapons
	10: 1,  # Shadow Dagger
	11: 1,  # Viper's Fang
	# Warrior weapons
	12: 3,  # Steel Claymore (two-handed)
	13: 3,  # Berserker's Axe (two-handed)
	# Sura weapons
	14: 2,  # Cursed Scimitar (one-handed)
	15: 2,  # Soulreaver Blade (one-handed)
	# Shaman weapons
	16: 3,  # Oak Staff
	17: 3,  # Spirit Totem
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
	
	# Special Items
	100: {"name": "Teleport Ring", "description": "A magical ring that allows instant travel between villages.", "type": "special", "rarity": "rare"},
	
	# =============================================================================
	# ARMOR ITEMS (IDs 200-235)
	# =============================================================================
	
	# Ninja Armor (IDs 200-205)
	200: {"name": "Ninja Cloth Wrappings", "description": "Simple cloth wrappings worn by ninja initiates.", "type": "armor", "rarity": "common", "defense": 5, "hp_bonus": 20, "class": "ninja"},
	201: {"name": "Shadow Leather Vest", "description": "Dark leather armor that blends with shadows.", "type": "armor", "rarity": "uncommon", "defense": 12, "hp_bonus": 50, "class": "ninja"},
	202: {"name": "Silent Chainmail", "description": "Specially crafted chainmail that makes no sound.", "type": "armor", "rarity": "rare", "defense": 22, "hp_bonus": 90, "class": "ninja"},
	203: {"name": "Assassin's Plate", "description": "Lightweight plate armor favored by master assassins.", "type": "armor", "rarity": "rare", "defense": 35, "hp_bonus": 140, "class": "ninja"},
	204: {"name": "Phantom Armor", "description": "Enchanted armor that seems to phase in and out of existence.", "type": "armor", "rarity": "epic", "defense": 50, "hp_bonus": 200, "class": "ninja"},
	205: {"name": "Eclipse Raiment", "description": "Legendary armor forged during a solar eclipse.", "type": "armor", "rarity": "legendary", "defense": 70, "hp_bonus": 300, "class": "ninja"},
	
	# Warrior Armor (IDs 210-215)
	210: {"name": "Warrior's Padded Tunic", "description": "A thick padded tunic for new warriors.", "type": "armor", "rarity": "common", "defense": 7, "hp_bonus": 30, "class": "warrior"},
	211: {"name": "Battle Leather Armor", "description": "Sturdy leather armor reinforced for combat.", "type": "armor", "rarity": "uncommon", "defense": 15, "hp_bonus": 60, "class": "warrior"},
	212: {"name": "Soldier's Chainmail", "description": "Standard issue chainmail for seasoned soldiers.", "type": "armor", "rarity": "rare", "defense": 28, "hp_bonus": 110, "class": "warrior"},
	213: {"name": "Veteran's Plate", "description": "Heavy plate armor worn by veteran warriors.", "type": "armor", "rarity": "rare", "defense": 45, "hp_bonus": 170, "class": "warrior"},
	214: {"name": "Champion's Aegis", "description": "Magnificent armor forged for tournament champions.", "type": "armor", "rarity": "epic", "defense": 65, "hp_bonus": 250, "class": "warrior"},
	215: {"name": "Warlord's Regalia", "description": "Legendary armor worn by the greatest warlords.", "type": "armor", "rarity": "legendary", "defense": 90, "hp_bonus": 380, "class": "warrior"},
	
	# Sura Armor (IDs 220-225)
	220: {"name": "Sura Initiate Robes", "description": "Dark robes worn by those beginning the path of the Sura.", "type": "armor", "rarity": "common", "defense": 5, "hp_bonus": 25, "class": "sura"},
	221: {"name": "Dark Leather Vestments", "description": "Leather armor imbued with dark energy.", "type": "armor", "rarity": "uncommon", "defense": 12, "hp_bonus": 55, "class": "sura"},
	222: {"name": "Cursed Chainmail", "description": "Chainmail armor corrupted by dark magic.", "type": "armor", "rarity": "rare", "defense": 24, "hp_bonus": 100, "class": "sura"},
	223: {"name": "Demon-Touched Plate", "description": "Plate armor marked by demonic influence.", "type": "armor", "rarity": "rare", "defense": 38, "hp_bonus": 155, "class": "sura"},
	224: {"name": "Abyssal Armor", "description": "Armor forged in the depths of the abyss.", "type": "armor", "rarity": "epic", "defense": 55, "hp_bonus": 220, "class": "sura"},
	225: {"name": "Netherworld Vestments", "description": "Legendary armor from the netherworld.", "type": "armor", "rarity": "legendary", "defense": 75, "hp_bonus": 330, "class": "sura"},
	
	# Shaman Armor (IDs 230-235)
	230: {"name": "Shaman Apprentice Robes", "description": "Simple robes worn by shaman apprentices.", "type": "armor", "rarity": "common", "defense": 4, "hp_bonus": 20, "class": "shaman"},
	231: {"name": "Spirit Leather Tunic", "description": "Leather armor blessed by nature spirits.", "type": "armor", "rarity": "uncommon", "defense": 10, "hp_bonus": 45, "class": "shaman"},
	232: {"name": "Ancestral Chainmail", "description": "Chainmail passed down through generations of shamans.", "type": "armor", "rarity": "rare", "defense": 20, "hp_bonus": 85, "class": "shaman"},
	233: {"name": "Totem-Bearer's Plate", "description": "Sacred plate armor worn by totem bearers.", "type": "armor", "rarity": "rare", "defense": 32, "hp_bonus": 130, "class": "shaman"},
	234: {"name": "Elder's Regalia", "description": "Ceremonial armor of the tribal elders.", "type": "armor", "rarity": "epic", "defense": 48, "hp_bonus": 190, "class": "shaman"},
	235: {"name": "Sacred Spirit Vestments", "description": "Legendary vestments blessed by the great spirits.", "type": "armor", "rarity": "legendary", "defense": 68, "hp_bonus": 290, "class": "shaman"},
}

## Reference to local player
var local_player: Node = null

## Inventory data: array of {item_id: int, quantity: int} or null
var inventory_slots: Array = []

## Currently equipped item IDs (-1 = empty)
var equipped_weapon_id: int = -1
var equipped_armor_id: int = -1
var equipped_helmet_id: int = -1
var equipped_shield_id: int = -1
var equipped_boots_id: int = -1
var equipped_necklace_id: int = -1
var equipped_ring_id: int = -1

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
@onready var tooltip_preview_container: Control = $Tooltip/MarginContainer/VBox/PreviewContainer
@onready var tooltip_weapon_preview: Node = $Tooltip/MarginContainer/VBox/PreviewContainer/WeaponPreview

## Equipment panel references (created dynamically)
var equipment_panel: Control = null
var weapon_slot: Control = null
var armor_slot: Control = null
var helmet_slot: Control = null
var shield_slot: Control = null
var boots_slot: Control = null
var necklace_slot: Control = null
var ring_slot: Control = null

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
	return UIManager.is_in_game()


## Check if chat input is currently focused
func _is_chat_focused() -> bool:
	return UIManager.is_chat_focused()


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
	_hide_tooltip()


func _create_equipment_panel() -> void:
	# Get the VBoxContainer that holds everything
	var vbox = $Panel/MarginContainer/VBoxContainer
	if not vbox:
		return
	
	# Create equipment section container
	equipment_panel = VBoxContainer.new()
	equipment_panel.name = "EquipmentPanel"
	equipment_panel.add_theme_constant_override("separation", 4)
	
	# Main equipment layout container (centered)
	var equip_center = CenterContainer.new()
	equip_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Container for the whole equipment layout
	var equip_layout = VBoxContainer.new()
	equip_layout.add_theme_constant_override("separation", 4)
	
	# === ROW 1: Helmet (centered) ===
	var row1 = CenterContainer.new()
	helmet_slot = _create_equipment_slot("helmet")
	row1.add_child(helmet_slot)
	equip_layout.add_child(row1)
	
	# === ROW 2: Necklace - spacer - Ring ===
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 0)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	
	necklace_slot = _create_equipment_slot("necklace")
	row2.add_child(necklace_slot)
	
	# Spacer for character head area
	var head_spacer = Control.new()
	head_spacer.custom_minimum_size = Vector2(50, 0)
	row2.add_child(head_spacer)
	
	ring_slot = _create_equipment_slot("ring")
	row2.add_child(ring_slot)
	equip_layout.add_child(row2)
	
	# === ROW 3: Weapon - Character Body with Armor - Shield ===
	var row3 = HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	
	weapon_slot = _create_equipment_slot("weapon")
	row3.add_child(weapon_slot)
	
	# Character silhouette container with armor slot overlay
	var char_container = _create_character_silhouette()
	row3.add_child(char_container)
	
	shield_slot = _create_equipment_slot("shield")
	row3.add_child(shield_slot)
	equip_layout.add_child(row3)
	
	# === ROW 4: Boots (centered) ===
	var row4 = CenterContainer.new()
	boots_slot = _create_equipment_slot("boots")
	row4.add_child(boots_slot)
	equip_layout.add_child(row4)
	
	equip_center.add_child(equip_layout)
	equipment_panel.add_child(equip_center)
	
	# Separator
	var sep = HSeparator.new()
	sep.modulate = Color(0.55, 0.45, 0.33, 0.5)
	equipment_panel.add_child(sep)
	
	# Insert equipment panel AFTER the Header (index 1)
	vbox.add_child(equipment_panel)
	vbox.move_child(equipment_panel, 1)


func _create_equipment_slot(slot_type: String) -> Control:
	"""Create an equipment slot with proper signal connections."""
	var slot = ItemSlotScene.instantiate()
	slot.slot_index = -1  # Special index for equipment slots
	slot.set_meta("slot_type", slot_type)
	
	# Connect signals based on slot type
	slot.connect("slot_clicked", _on_equipment_slot_clicked.bind(slot_type))
	slot.connect("slot_right_clicked", _on_equipment_slot_right_clicked.bind(slot_type))
	slot.connect("slot_hovered", _on_equipment_slot_hovered.bind(slot_type))
	slot.connect("slot_unhovered", _on_equipment_slot_unhovered.bind(slot_type))
	
	return slot


func _create_character_silhouette() -> Control:
	"""Create a character silhouette with armor slot overlay."""
	# Container that holds both silhouette and armor slot
	var container = Control.new()
	container.custom_minimum_size = Vector2(70, 90)
	
	# Silhouette background panel
	var silhouette_bg = Panel.new()
	silhouette_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var silhouette_style = StyleBoxFlat.new()
	silhouette_style.bg_color = Color(0.08, 0.09, 0.12, 0.6)
	silhouette_style.border_color = Color(0.29, 0.25, 0.21, 0.5)
	silhouette_style.set_border_width_all(1)
	silhouette_style.set_corner_radius_all(4)
	silhouette_bg.add_theme_stylebox_override("panel", silhouette_style)
	container.add_child(silhouette_bg)
	
	# Head (circle) - positioned at top center
	var head = ColorRect.new()
	head.color = Color(0.2, 0.22, 0.28, 0.8)
	head.size = Vector2(20, 20)
	head.position = Vector2(25, 5)
	container.add_child(head)
	
	# Body (rectangle) - positioned below head
	var body = ColorRect.new()
	body.color = Color(0.2, 0.22, 0.28, 0.8)
	body.size = Vector2(30, 40)
	body.position = Vector2(20, 28)
	container.add_child(body)
	
	# Left arm
	var left_arm = ColorRect.new()
	left_arm.color = Color(0.2, 0.22, 0.28, 0.8)
	left_arm.size = Vector2(8, 30)
	left_arm.position = Vector2(10, 30)
	container.add_child(left_arm)
	
	# Right arm
	var right_arm = ColorRect.new()
	right_arm.color = Color(0.2, 0.22, 0.28, 0.8)
	right_arm.size = Vector2(8, 30)
	right_arm.position = Vector2(52, 30)
	container.add_child(right_arm)
	
	# Legs
	var left_leg = ColorRect.new()
	left_leg.color = Color(0.2, 0.22, 0.28, 0.8)
	left_leg.size = Vector2(12, 18)
	left_leg.position = Vector2(22, 70)
	container.add_child(left_leg)
	
	var right_leg = ColorRect.new()
	right_leg.color = Color(0.2, 0.22, 0.28, 0.8)
	right_leg.size = Vector2(12, 18)
	right_leg.position = Vector2(36, 70)
	container.add_child(right_leg)
	
	# Armor slot - overlay on body
	armor_slot = _create_equipment_slot("armor")
	armor_slot.position = Vector2(10, 20)
	container.add_child(armor_slot)
	
	return container


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
			var continuation_of = slot_data.get("continuation_of", -1)
			
			# Check if this is a continuation slot
			if continuation_of >= 0:
				# This is a continuation slot - hidden, primary slot expands over it
				slot_node.set_continuation_slot(continuation_of)
			else:
				# This is a primary slot - render with vertical expansion
				var item_def = ITEM_DEFS.get(item_id, null)
				var slot_size = _get_item_slot_size(item_id)
				
				if item_def:
					var rarity = item_def.get("rarity", "common")
					var color = RARITY_COLORS.get(rarity, RARITY_COLORS["common"])
					slot_node.set_item(item_id, quantity, color, item_def["name"], slot_size)
				else:
					slot_node.set_item(item_id, quantity, Color(0.5, 0.5, 0.5), "Unknown", slot_size)
		else:
			slot_node.clear_item()
	
	# Update equipment display
	_refresh_equipment_display()


## Get the number of inventory slots an item occupies (vertically)
func _get_item_slot_size(item_id: int) -> int:
	return ITEM_SLOT_SIZES.get(item_id, 1)


func _refresh_equipment_display() -> void:
	# Update weapon slot
	_update_equipment_slot(weapon_slot, equipped_weapon_id)
	
	# Update armor slot
	_update_equipment_slot(armor_slot, equipped_armor_id)
	
	# Update other equipment slots (currently no items for these)
	_update_equipment_slot(helmet_slot, equipped_helmet_id)
	_update_equipment_slot(shield_slot, equipped_shield_id)
	_update_equipment_slot(boots_slot, equipped_boots_id)
	_update_equipment_slot(necklace_slot, equipped_necklace_id)
	_update_equipment_slot(ring_slot, equipped_ring_id)


func _update_equipment_slot(slot: Control, item_id: int) -> void:
	"""Update a single equipment slot's display."""
	if not slot:
		return
	
	if item_id > 0:
		var item_def = ITEM_DEFS.get(item_id, null)
		if item_def:
			var rarity = item_def.get("rarity", "common")
			var color = RARITY_COLORS.get(rarity, RARITY_COLORS["common"])
			slot.set_item(item_id, 1, color, item_def["name"])
		else:
			slot.set_item(item_id, 1, Color(0.5, 0.5, 0.5), "Unknown")
	else:
		slot.clear_item()


func _on_inventory_updated() -> void:
	# Get inventory data from player
	if local_player and local_player.has_method("get_inventory_slot"):
		for i in range(SLOT_COUNT):
			var slot_data = local_player.get_inventory_slot(i)
			if slot_data.has("item_id"):
				var continuation_of = slot_data.get("continuation_of", -1)
				inventory_slots[i] = {
					"item_id": slot_data["item_id"],
					"quantity": slot_data.get("quantity", 1),
					"continuation_of": continuation_of  # -1 = primary slot, >= 0 = continuation
				}
			else:
				inventory_slots[i] = null
	refresh_display()


func _on_equipment_changed(weapon_id: int, armor_id: int) -> void:
	equipped_weapon_id = weapon_id
	equipped_armor_id = armor_id
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
	
	# If this is a continuation slot, get data from primary slot instead
	var primary_slot = slot_index
	var continuation_of = slot_data.get("continuation_of", -1)
	if continuation_of >= 0:
		primary_slot = continuation_of
		slot_data = inventory_slots[primary_slot]
		if slot_data == null or not slot_data.has("item_id"):
			return
	
	is_dragging_item = true
	drag_from_slot = primary_slot  # Always drag from the primary slot
	drag_item_id = slot_data["item_id"]
	drag_item_quantity = slot_data.get("quantity", 1)
	
	# Get the item color from the primary slot
	if primary_slot < slot_nodes.size():
		drag_item_color = slot_nodes[primary_slot].get_item_color()
	else:
		drag_item_color = Color(0.5, 0.5, 0.5)
	
	# Create ghost preview
	_create_drag_preview()
	
	# Hide tooltip during drag
	_hide_tooltip()
	
	print("Started dragging item from slot ", primary_slot)


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
	
	# Check if item has a 3D icon texture
	var icon_texture: Texture2D = null
	if drag_from_slot >= 0 and drag_from_slot < slot_nodes.size():
		var slot = slot_nodes[drag_from_slot]
		if slot.has_texture_icon():
			icon_texture = slot.get_item_texture()
	
	if icon_texture:
		# Use the 3D weapon icon
		var icon_rect = TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.size = Vector2(36, 36)
		icon_rect.position = Vector2(4, 4)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_panel.add_child(icon_rect)
	else:
		# Fallback to colored rectangle
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
		# Equip armor on right-click
		elif item_def["type"] == "armor":
			if local_player and local_player.has_method("equip_item"):
				local_player.equip_item(slot_index)
				print("Equipping armor from slot ", slot_index)


func _on_slot_hovered(slot_index: int) -> void:
	var slot_data = inventory_slots[slot_index]
	
	if slot_data != null and slot_data.has("item_id"):
		var item_id = slot_data["item_id"]
		var item_def = ITEM_DEFS.get(item_id, null)
		
		if item_def and tooltip:
			_show_tooltip_for_item(item_id, item_def, false)


func _on_slot_unhovered(slot_index: int) -> void:
	_hide_tooltip()


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

func _on_equipment_slot_clicked(_slot_index: int, slot_type: String) -> void:
	# Left-click on equipment slot does nothing for now
	pass


func _on_equipment_slot_right_clicked(_slot_index: int, slot_type: String) -> void:
	# Right-click on equipped item to unequip
	var item_id = _get_equipped_item_id(slot_type)
	if item_id > 0:
		if local_player and local_player.has_method("unequip_item"):
			local_player.unequip_item(slot_type)
			print("Unequipping ", slot_type)


func _on_equipment_slot_hovered(_slot_index: int, slot_type: String) -> void:
	var item_id = _get_equipped_item_id(slot_type)
	if item_id > 0:
		var item_def = ITEM_DEFS.get(item_id, null)
		if item_def and tooltip:
			_show_tooltip_for_item(item_id, item_def, true)


func _on_equipment_slot_unhovered(_slot_index: int, slot_type: String) -> void:
	_hide_tooltip()


func _get_equipped_item_id(slot_type: String) -> int:
	"""Get the equipped item ID for a given slot type."""
	match slot_type:
		"weapon": return equipped_weapon_id
		"armor": return equipped_armor_id
		"helmet": return equipped_helmet_id
		"shield": return equipped_shield_id
		"boots": return equipped_boots_id
		"necklace": return equipped_necklace_id
		"ring": return equipped_ring_id
		_: return -1


func _show_tooltip_for_item(item_id: int, item_def: Dictionary, is_equipped: bool = false) -> void:
	tooltip_name.text = item_def["name"]
	
	var type_text = item_def["type"].capitalize()
	if item_def["type"] == "weapon" or item_def["type"] == "armor":
		var class_restriction = item_def.get("class", "any")
		if class_restriction != "any":
			type_text += " (%s)" % class_restriction.capitalize()
	tooltip_type.text = type_text
	
	tooltip_desc.text = item_def["description"]
	
	# Set rarity color on name
	var rarity = item_def.get("rarity", "common")
	var color = RARITY_COLORS.get(rarity, RARITY_COLORS["common"])
	tooltip_name.add_theme_color_override("font_color", color)
	
	# Show 3D weapon preview if item has a model
	if tooltip_preview_container and tooltip_weapon_preview:
		if ItemIconManager.has_model(item_id):
			tooltip_weapon_preview.set_weapon(item_id)
			tooltip_preview_container.visible = true
		else:
			tooltip_weapon_preview.clear()
			tooltip_preview_container.visible = false
	
	# Show weapon stats if applicable
	if tooltip_stats and item_def["type"] == "weapon":
		var damage = item_def.get("damage", 0)
		var speed = item_def.get("speed", 1.0)
		tooltip_stats.text = "Damage: %d | Speed: %.2fx" % [damage, speed]
		tooltip_stats.visible = true
	# Show armor stats if applicable
	elif tooltip_stats and item_def["type"] == "armor":
		var defense = item_def.get("defense", 0)
		var hp_bonus = item_def.get("hp_bonus", 0)
		tooltip_stats.text = "Defense: %d | HP: +%d" % [defense, hp_bonus]
		tooltip_stats.visible = true
	elif tooltip_stats:
		tooltip_stats.visible = false
	
	# Show hint
	if item_def["type"] == "consumable":
		tooltip_hint.text = "[Right-click to use]"
		tooltip_hint.visible = true
	elif item_def["type"] == "weapon" or item_def["type"] == "armor":
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


## Hide tooltip and clear weapon preview
func _hide_tooltip() -> void:
	if tooltip:
		tooltip.visible = false
	if tooltip_weapon_preview:
		tooltip_weapon_preview.clear()
	if tooltip_preview_container:
		tooltip_preview_container.visible = false


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
