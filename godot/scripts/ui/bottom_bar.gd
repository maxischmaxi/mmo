extends Control
class_name BottomBar
## Bottom bar UI containing player stats, action bar, and utility buttons.

## Number of action slots
const ACTION_SLOT_COUNT: int = 8

## Reference to local player
var local_player: Node = null

## Reference to targeting system
var targeting_system: Node = null

## Current stat values (for smooth animation)
var current_health: float = 100.0
var current_mana: float = 50.0
var current_exp: float = 0.0
var target_health: float = 100.0
var target_mana: float = 50.0
var target_exp: float = 0.0

## Max values
var max_health: float = 100.0
var max_mana: float = 50.0
var max_exp: float = 1000.0

## Animation speed for bars
const BAR_LERP_SPEED: float = 8.0

## Action slot scene
var ActionSlotScene = preload("res://scenes/ui/action_slot.tscn")

## Action bar ability IDs (8 slots)
var action_bar_abilities: Array[int] = [-1, -1, -1, -1, -1, -1, -1, -1]

## Ability definitions (loaded once)
## Map of ability_id -> { name, description, mana_cost, cooldown, range, target_type }
var ability_defs: Dictionary = {
	# Universal abilities
	1: { "id": 1, "name": "Power Strike", "description": "A powerful melee attack dealing 150% weapon damage.", "mana_cost": 10, "cooldown": 6.0, "range": 3.0, "target_type": "enemy" },
	2: { "id": 2, "name": "Recuperate", "description": "Regenerate 20% of max HP over 10 seconds.", "mana_cost": 20, "cooldown": 30.0, "range": 0.0, "target_type": "self" },
	# Ninja abilities
	11: { "id": 11, "name": "Shadow Strike", "description": "Strike from the shadows for 200% weapon damage.", "mana_cost": 15, "cooldown": 8.0, "range": 3.0, "target_type": "enemy" },
	12: { "id": 12, "name": "Poison Blade", "description": "Coat your blade with poison. Deals damage and poisons the target.", "mana_cost": 20, "cooldown": 12.0, "range": 3.0, "target_type": "enemy" },
	# Warrior abilities
	21: { "id": 21, "name": "Crushing Blow", "description": "A devastating blow dealing 180% damage and reducing enemy defense.", "mana_cost": 20, "cooldown": 10.0, "range": 3.0, "target_type": "enemy" },
	22: { "id": 22, "name": "Battle Cry", "description": "Let out a battle cry, increasing attack by 20% for 15 seconds.", "mana_cost": 25, "cooldown": 45.0, "range": 0.0, "target_type": "self" },
	# Sura abilities
	31: { "id": 31, "name": "Dark Slash", "description": "Channel dark energy into your blade for 170% damage.", "mana_cost": 15, "cooldown": 7.0, "range": 3.0, "target_type": "enemy" },
	32: { "id": 32, "name": "Life Drain", "description": "Drain the life force of your enemy, healing yourself.", "mana_cost": 30, "cooldown": 15.0, "range": 5.0, "target_type": "enemy" },
	# Shaman abilities
	41: { "id": 41, "name": "Lightning Bolt", "description": "Call down lightning to strike your enemy from range.", "mana_cost": 20, "cooldown": 5.0, "range": 15.0, "target_type": "enemy" },
	42: { "id": 42, "name": "Healing Wave", "description": "Channel healing energy to restore 25% of max HP.", "mana_cost": 35, "cooldown": 12.0, "range": 0.0, "target_type": "self" },
}

## UI References
@onready var health_bar: ProgressBar = $Panel/HBoxContainer/LeftSection/StatsContainer/HealthBar
@onready var mana_bar: ProgressBar = $Panel/HBoxContainer/LeftSection/StatsContainer/ManaBar
@onready var exp_bar: ProgressBar = $Panel/HBoxContainer/LeftSection/StatsContainer/ExpBar
@onready var level_label: Label = $Panel/HBoxContainer/LeftSection/LevelContainer/LevelLabel
@onready var action_bar_container: HBoxContainer = $Panel/HBoxContainer/CenterSection/ActionBarContainer
@onready var inventory_button: Button = $Panel/HBoxContainer/RightSection/InventoryButton

## Action slot references
var action_slots: Array = []


func _ready() -> void:
	# Create action slots
	_create_action_slots()
	
	# Connect inventory button
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_button_pressed)
	
	# Find local player and connect signals
	await get_tree().process_frame
	_find_player_and_connect()
	
	# Initialize bars
	_initialize_bars()


func _process(delta: float) -> void:
	# Smoothly animate health bar
	if health_bar:
		current_health = lerpf(current_health, target_health, BAR_LERP_SPEED * delta)
		health_bar.value = current_health
	
	# Smoothly animate mana bar
	if mana_bar:
		current_mana = lerpf(current_mana, target_mana, BAR_LERP_SPEED * delta)
		mana_bar.value = current_mana
	
	# Smoothly animate exp bar
	if exp_bar:
		current_exp = lerpf(current_exp, target_exp, BAR_LERP_SPEED * delta)
		exp_bar.value = current_exp
	
	# Update action slot cooldowns
	for slot in action_slots:
		if slot and slot.has_method("update_cooldown"):
			slot.update_cooldown(delta)


func _find_player_and_connect() -> void:
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	# Find targeting system
	targeting_system = get_tree().get_first_node_in_group("targeting_system")
	
	if local_player:
		# Connect to health changed signal
		if local_player.has_signal("health_changed"):
			local_player.connect("health_changed", _on_health_changed)
		
		# Connect to character selected signal (to update initial values)
		if local_player.has_signal("character_selected"):
			local_player.connect("character_selected", _on_character_selected)
		
		# Connect to experience gained signal
		if local_player.has_signal("experience_gained"):
			local_player.connect("experience_gained", _on_experience_gained)
		
		# Connect to level up signal
		if local_player.has_signal("level_up"):
			local_player.connect("level_up", _on_level_up)
		
		# Connect to stats updated signal (for /xp command etc)
		if local_player.has_signal("stats_updated"):
			local_player.connect("stats_updated", _on_stats_updated)
		
		# Connect to ability signals
		if local_player.has_signal("action_bar_received"):
			local_player.connect("action_bar_received", _on_action_bar_received)
		
		if local_player.has_signal("ability_cooldown"):
			local_player.connect("ability_cooldown", _on_ability_cooldown)
		
		if local_player.has_signal("ability_failed"):
			local_player.connect("ability_failed", _on_ability_failed)
		
		if local_player.has_signal("ability_used"):
			local_player.connect("ability_used", _on_ability_used)


func _initialize_bars() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	
	if mana_bar:
		mana_bar.max_value = max_mana
		mana_bar.value = current_mana
	
	if exp_bar:
		exp_bar.max_value = max_exp
		exp_bar.value = current_exp


func _create_action_slots() -> void:
	if not action_bar_container:
		return
	
	# Clear existing slots
	for child in action_bar_container.get_children():
		child.queue_free()
	action_slots.clear()
	
	# Create 8 action slots
	for i in range(ACTION_SLOT_COUNT):
		var slot = ActionSlotScene.instantiate()
		slot.slot_number = i + 1
		slot.slot_clicked.connect(_on_action_slot_clicked)
		slot.slot_right_clicked.connect(_on_action_slot_right_clicked)
		action_bar_container.add_child(slot)
		action_slots.append(slot)


func _on_inventory_button_pressed() -> void:
	# Find and toggle the inventory UI
	var inventory_ui = get_tree().get_first_node_in_group("inventory_ui")
	if inventory_ui == null:
		# Try to find it in the UI hierarchy
		var game_ui = get_parent()
		if game_ui:
			inventory_ui = game_ui.get_node_or_null("InventoryUI")
	
	if inventory_ui and inventory_ui.has_method("toggle_visibility"):
		inventory_ui.toggle_visibility()


func _on_action_slot_clicked(slot_number: int) -> void:
	# Activate ability in this slot (0-indexed internally)
	_use_ability_in_slot(slot_number - 1)


func _on_action_slot_right_clicked(_slot_number: int) -> void:
	# For future: open ability assignment menu
	pass


## Use ability in a specific slot (0-indexed)
func _use_ability_in_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= action_bar_abilities.size():
		return
	
	var ability_id = action_bar_abilities[slot_index]
	if ability_id <= 0:
		return  # No ability in this slot
	
	if not local_player:
		return
	
	# Get target for ability (if needed)
	var target_id: int = -1
	if ability_defs.has(ability_id):
		var ability = ability_defs[ability_id]
		if ability.target_type == "enemy":
			if targeting_system and targeting_system.has_target():
				target_id = targeting_system.get_current_target_id()
	
	# Use the ability
	if local_player.has_method("use_ability"):
		local_player.use_ability(ability_id, target_id)


func _on_health_changed(current: int, maximum: int) -> void:
	max_health = float(maximum)
	target_health = float(current)
	if health_bar:
		health_bar.max_value = max_health
	_update_health_label()


func _on_character_selected(_character_id: int) -> void:
	# Update all stats from player
	if local_player:
		if local_player.has_method("get_health"):
			var health = local_player.get_health()
			var health_max = local_player.get_max_health()
			set_health_immediate(health, health_max)
		
		if local_player.has_method("get_mana"):
			var mana = local_player.get_mana()
			var mana_max = local_player.get_max_mana()
			set_mana_immediate(mana, mana_max)
		
		if local_player.has_method("get_level"):
			update_level(local_player.get_level())
		
		if local_player.has_method("get_experience") and local_player.has_method("get_experience_to_next_level"):
			var exp = local_player.get_experience()
			var exp_to_next = local_player.get_experience_to_next_level()
			# Calculate XP within current level
			var level = local_player.get_level()
			var current_level_xp = _get_xp_within_level(exp, level)
			set_exp_immediate(current_level_xp, exp_to_next)


## Calculate XP within current level (not total XP)
## Formula matches server: xp_for_level = 100 * (level-1)^2
func _get_xp_within_level(total_xp: int, level: int) -> int:
	if level <= 1:
		return total_xp
	# XP required to reach current level
	var xp_for_current = 100 * (level - 1) * (level - 1)
	return total_xp - xp_for_current


func _on_experience_gained(amount: int, current_xp: int, xp_to_next: int) -> void:
	# Calculate XP within current level
	if local_player and local_player.has_method("get_level"):
		var level = local_player.get_level()
		var current_level_xp = _get_xp_within_level(current_xp, level)
		update_exp(current_level_xp, xp_to_next)


func _on_level_up(new_level: int, new_max_health: int, new_max_mana: int, _attack: int, _defense: int) -> void:
	# Update level display
	update_level(new_level)
	
	# Update health and mana bars (level up heals to full)
	set_health_immediate(new_max_health, new_max_health)
	set_mana_immediate(new_max_mana, new_max_mana)
	
	# Reset XP bar for new level
	if local_player and local_player.has_method("get_experience_to_next_level"):
		var xp_to_next = local_player.get_experience_to_next_level()
		set_exp_immediate(0, xp_to_next)


func _on_stats_updated(level: int, _max_health: int, _max_mana: int, _attack: int, _defense: int, _gold: int, health: int, mana: int) -> void:
	# Update level display
	update_level(level)
	
	# Update health and mana
	if local_player:
		set_health_immediate(health, local_player.get_max_health() if local_player.has_method("get_max_health") else health)
		set_mana_immediate(mana, local_player.get_max_mana() if local_player.has_method("get_max_mana") else mana)
		
		# Update XP bar
		if local_player.has_method("get_experience") and local_player.has_method("get_experience_to_next_level"):
			var exp = local_player.get_experience()
			var xp_to_next = local_player.get_experience_to_next_level()
			var current_level_xp = _get_xp_within_level(exp, level)
			set_exp_immediate(current_level_xp, xp_to_next)


func _update_health_label() -> void:
	var health_label = health_bar.get_node_or_null("ValueLabel") as Label
	if health_label:
		health_label.text = "%d/%d" % [int(target_health), int(max_health)]


func _update_mana_label() -> void:
	var mana_label = mana_bar.get_node_or_null("ValueLabel") as Label
	if mana_label:
		mana_label.text = "%d/%d" % [int(target_mana), int(max_mana)]


func _update_exp_label() -> void:
	var exp_label = exp_bar.get_node_or_null("ValueLabel") as Label
	if exp_label:
		var percent = (target_exp / max_exp) * 100.0 if max_exp > 0 else 0.0
		exp_label.text = "%.1f%%" % percent


## Set health immediately (no animation)
func set_health_immediate(current: int, maximum: int) -> void:
	max_health = float(maximum)
	current_health = float(current)
	target_health = float(current)
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	_update_health_label()


## Set mana immediately (no animation)
func set_mana_immediate(current: int, maximum: int) -> void:
	max_mana = float(maximum)
	current_mana = float(current)
	target_mana = float(current)
	if mana_bar:
		mana_bar.max_value = max_mana
		mana_bar.value = current_mana
	_update_mana_label()


## Set exp immediately (no animation)
func set_exp_immediate(current: int, maximum: int) -> void:
	max_exp = float(maximum)
	current_exp = float(current)
	target_exp = float(current)
	if exp_bar:
		exp_bar.max_value = max_exp
		exp_bar.value = current_exp
	_update_exp_label()


## Update level display
func update_level(level: int) -> void:
	if level_label:
		level_label.text = str(level)


## Update health (animated)
func update_health(current: int, maximum: int) -> void:
	max_health = float(maximum)
	target_health = float(current)
	if health_bar:
		health_bar.max_value = max_health
	_update_health_label()


## Update mana (animated)
func update_mana(current: int, maximum: int) -> void:
	max_mana = float(maximum)
	target_mana = float(current)
	if mana_bar:
		mana_bar.max_value = max_mana
	_update_mana_label()


## Update exp (animated)
func update_exp(current: int, maximum: int) -> void:
	max_exp = float(maximum)
	target_exp = float(current)
	if exp_bar:
		exp_bar.max_value = max_exp
	_update_exp_label()


# ==========================================================================
# Ability System
# ==========================================================================

## Handle action bar received from server
func _on_action_bar_received(slots: Array) -> void:
	# Update local action bar abilities
	for i in range(min(slots.size(), ACTION_SLOT_COUNT)):
		action_bar_abilities[i] = slots[i] if slots[i] is int else int(slots[i])
	
	# Update action slot displays
	_update_action_slots()


## Handle ability cooldown started/updated
func _on_ability_cooldown(ability_id: int, remaining: float, total: float) -> void:
	# Find the slot with this ability and start cooldown
	for i in range(action_bar_abilities.size()):
		if action_bar_abilities[i] == ability_id:
			if i < action_slots.size() and action_slots[i]:
				# Start cooldown from remaining (server tells us how much is left)
				action_slots[i].cooldown_total = total
				action_slots[i].cooldown_remaining = remaining
				action_slots[i].is_on_cooldown = remaining > 0
				action_slots[i]._update_display()


## Handle ability failed message
func _on_ability_failed(ability_id: int, reason: String) -> void:
	# Show error message in chat
	var chat_ui = get_tree().get_first_node_in_group("chat_ui")
	var ability_name = "Ability"
	if ability_defs.has(ability_id):
		ability_name = ability_defs[ability_id].name
	
	if chat_ui and chat_ui.has_method("add_command_error_message"):
		chat_ui.add_command_error_message("%s failed: %s" % [ability_name, reason])
	elif chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message("%s failed: %s" % [ability_name, reason])


## Handle ability used (for visual feedback)
func _on_ability_used(caster_id: int, ability_id: int, _target_id: int) -> void:
	# Only flash for our own abilities
	if local_player and local_player.has_method("get_entity_id"):
		var our_id = local_player.get_entity_id()
		if caster_id != our_id:
			return
	
	# Find the slot with this ability and trigger flash
	for i in range(action_bar_abilities.size()):
		if action_bar_abilities[i] == ability_id:
			if i < action_slots.size() and action_slots[i]:
				action_slots[i].trigger_use_flash()


## Update action slot UI to reflect current abilities
func _update_action_slots() -> void:
	for i in range(action_slots.size()):
		var slot = action_slots[i]
		if not slot:
			continue
		
		var ability_id = action_bar_abilities[i] if i < action_bar_abilities.size() else -1
		
		if ability_id > 0 and ability_defs.has(ability_id):
			var ability = ability_defs[ability_id]
			slot.set_full_ability_data(ability)
		else:
			slot.clear_ability()


func _input(event: InputEvent) -> void:
	# Only process ability keybinds when in game
	if not _is_in_game():
		return
	
	# Don't process if chat is focused or any LineEdit has focus
	if _is_chat_focused() or _is_text_input_focused():
		return
	
	# Check for number key presses (1-8 for action slots)
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event = event as InputEventKey
		match key_event.keycode:
			KEY_1:
				_use_ability_in_slot(0)
				get_viewport().set_input_as_handled()
			KEY_2:
				_use_ability_in_slot(1)
				get_viewport().set_input_as_handled()
			KEY_3:
				_use_ability_in_slot(2)
				get_viewport().set_input_as_handled()
			KEY_4:
				_use_ability_in_slot(3)
				get_viewport().set_input_as_handled()
			KEY_5:
				_use_ability_in_slot(4)
				get_viewport().set_input_as_handled()
			KEY_6:
				_use_ability_in_slot(5)
				get_viewport().set_input_as_handled()
			KEY_7:
				_use_ability_in_slot(6)
				get_viewport().set_input_as_handled()
			KEY_8:
				_use_ability_in_slot(7)
				get_viewport().set_input_as_handled()


## Check if chat input is currently focused
func _is_chat_focused() -> bool:
	var chat_ui = get_tree().get_first_node_in_group("chat_ui")
	if chat_ui and chat_ui.has_method("is_input_focused"):
		return chat_ui.call("is_input_focused")
	return false


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm and "current_state" in gm:
		# GameState.IN_GAME = 3
		return gm.current_state == 3
	return false


## Check if any text input (LineEdit) has focus
func _is_text_input_focused() -> bool:
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit
