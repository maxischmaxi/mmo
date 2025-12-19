extends Control
class_name CharacterPanel
## Character Panel UI - shows detailed information about the player's character.
## Toggle with 'C' key.

## Class name mappings
const CLASS_NAMES: Dictionary = {
	0: "Ninja",
	1: "Warrior",
	2: "Sura",
	3: "Shaman",
}

## Empire name and color mappings
const EMPIRE_DATA: Dictionary = {
	0: {"name": "Shinsoo", "color": Color(0.9, 0.3, 0.3)},   # Red
	1: {"name": "Chunjo", "color": Color(0.9, 0.8, 0.3)},    # Yellow
	2: {"name": "Jinno", "color": Color(0.3, 0.5, 0.9)},     # Blue
}

## Reference to local player
var local_player: Node = null

## Window dragging state
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

## Cached stat values (for display)
var cached_stats: Dictionary = {
	"name": "",
	"class": -1,
	"empire": -1,
	"level": 1,
	"health": 100,
	"max_health": 100,
	"mana": 50,
	"max_mana": 50,
	"experience": 0,
	"experience_to_next_level": 100,
	"attack": 10,
	"defense": 5,
	"attack_speed": 1.0,
	"gold": 0,
}

## UI References
@onready var panel: Panel = $Panel
@onready var header: HBoxContainer = $Panel/MarginContainer/VBoxContainer/Header
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/Header/CloseButton

# Character info
@onready var character_name_label: Label = $Panel/MarginContainer/VBoxContainer/CharacterSection/CharacterVBox/CharacterName
@onready var class_label: Label = $Panel/MarginContainer/VBoxContainer/CharacterSection/CharacterVBox/InfoGrid/ClassValue
@onready var empire_label: Label = $Panel/MarginContainer/VBoxContainer/CharacterSection/CharacterVBox/InfoGrid/EmpireValue

# Stats
@onready var level_value: Label = $Panel/MarginContainer/VBoxContainer/StatsSection/StatsVBox/StatsGrid/LevelValue
@onready var health_value: Label = $Panel/MarginContainer/VBoxContainer/StatsSection/StatsVBox/StatsGrid/HealthValue
@onready var mana_value: Label = $Panel/MarginContainer/VBoxContainer/StatsSection/StatsVBox/StatsGrid/ManaValue
@onready var attack_value: Label = $Panel/MarginContainer/VBoxContainer/StatsSection/StatsVBox/StatsGrid/AttackValue
@onready var defense_value: Label = $Panel/MarginContainer/VBoxContainer/StatsSection/StatsVBox/StatsGrid/DefenseValue
@onready var attack_speed_value: Label = $Panel/MarginContainer/VBoxContainer/StatsSection/StatsVBox/StatsGrid/AttackSpeedValue
@onready var gold_value: Label = $Panel/MarginContainer/VBoxContainer/StatsSection/StatsVBox/StatsGrid/GoldValue

# Experience
@onready var exp_bar: ProgressBar = $Panel/MarginContainer/VBoxContainer/ExpSection/ExpVBox/ExpBar
@onready var exp_label: Label = $Panel/MarginContainer/VBoxContainer/ExpSection/ExpVBox/ExpBar/ExpLabel


func _ready() -> void:
	# Add to group so other scripts can find us
	add_to_group("character_panel")
	
	# Register with UIManager for escape key handling
	UIManager.register_dialog(self)
	
	# Connect header for dragging
	if header:
		header.gui_input.connect(_on_header_gui_input)
		header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	
	# Connect close button
	if close_button:
		close_button.pressed.connect(close_panel)
	
	# Connect to viewport resize
	get_tree().root.size_changed.connect(_on_viewport_resized)
	
	# Start hidden
	visible = false
	
	# Find local player and connect signals after a frame
	await get_tree().process_frame
	_find_player_and_connect()
	
	# Center panel on first show
	_center_on_screen()


func _input(event: InputEvent) -> void:
	# Only process game inputs when actually in game
	if not _is_in_game():
		return
	
	# Don't toggle if chat is focused
	if _is_chat_focused():
		return
	
	# Don't toggle if any text input has focus
	if _is_text_input_focused():
		return
	
	if event.is_action_pressed("toggle_character_panel"):
		toggle_visibility()
		get_viewport().set_input_as_handled()


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and "current_state" in game_manager:
		# GameState.IN_GAME = 3
		return game_manager.current_state == 3
	return false


## Check if chat input is currently focused
func _is_chat_focused() -> bool:
	var chat_ui = get_tree().get_first_node_in_group("chat_ui")
	if chat_ui and chat_ui.has_method("is_input_focused"):
		return chat_ui.call("is_input_focused")
	return false


## Check if any text input (LineEdit) has focus
func _is_text_input_focused() -> bool:
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit


func _find_player_and_connect() -> void:
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	if local_player:
		# Connect to relevant signals
		if local_player.has_signal("character_selected"):
			local_player.connect("character_selected", _on_character_selected)
		
		if local_player.has_signal("stats_updated"):
			local_player.connect("stats_updated", _on_stats_updated)
		
		if local_player.has_signal("level_up"):
			local_player.connect("level_up", _on_level_up)
		
		if local_player.has_signal("experience_gained"):
			local_player.connect("experience_gained", _on_experience_gained)
		
		if local_player.has_signal("health_changed"):
			local_player.connect("health_changed", _on_health_changed)
		
		if local_player.has_signal("gold_updated"):
			local_player.connect("gold_updated", _on_gold_updated)


# =============================================================================
# Signal Handlers
# =============================================================================

func _on_character_selected(_character_id: int) -> void:
	# Refresh all stats from player
	_refresh_all_stats()


func _on_stats_updated(level: int, max_health: int, max_mana: int, attack: int, defense: int, gold: int, health: int, mana: int) -> void:
	cached_stats["level"] = level
	cached_stats["max_health"] = max_health
	cached_stats["max_mana"] = max_mana
	cached_stats["attack"] = attack
	cached_stats["defense"] = defense
	cached_stats["gold"] = gold
	cached_stats["health"] = health
	cached_stats["mana"] = mana
	
	# Update experience from player
	if local_player:
		if local_player.has_method("get_experience"):
			cached_stats["experience"] = local_player.get_experience()
		if local_player.has_method("get_experience_to_next_level"):
			cached_stats["experience_to_next_level"] = local_player.get_experience_to_next_level()
		if local_player.has_method("get_attack_speed"):
			cached_stats["attack_speed"] = local_player.get_attack_speed()
	
	if visible:
		_update_display()


func _on_level_up(new_level: int, max_health: int, max_mana: int, attack: int, defense: int) -> void:
	cached_stats["level"] = new_level
	cached_stats["max_health"] = max_health
	cached_stats["max_mana"] = max_mana
	cached_stats["attack"] = attack
	cached_stats["defense"] = defense
	# Level up heals to full
	cached_stats["health"] = max_health
	cached_stats["mana"] = max_mana
	
	# Update experience from player
	if local_player:
		if local_player.has_method("get_experience"):
			cached_stats["experience"] = local_player.get_experience()
		if local_player.has_method("get_experience_to_next_level"):
			cached_stats["experience_to_next_level"] = local_player.get_experience_to_next_level()
	
	if visible:
		_update_display()


func _on_experience_gained(_amount: int, current_xp: int, xp_to_next: int) -> void:
	cached_stats["experience"] = current_xp
	cached_stats["experience_to_next_level"] = xp_to_next
	
	if visible:
		_update_exp_display()


func _on_health_changed(current: int, maximum: int) -> void:
	cached_stats["health"] = current
	cached_stats["max_health"] = maximum
	
	if visible:
		_update_health_display()


func _on_gold_updated(gold: int) -> void:
	cached_stats["gold"] = gold
	
	if visible:
		_update_gold_display()


# =============================================================================
# Display Updates
# =============================================================================

func _refresh_all_stats() -> void:
	"""Fetch all stats from player and update cache."""
	if not local_player:
		return
	
	# Character info
	if local_player.has_method("get_character_name"):
		cached_stats["name"] = local_player.get_character_name()
	if local_player.has_method("get_character_class"):
		cached_stats["class"] = local_player.get_character_class()
	if local_player.has_method("get_character_empire"):
		cached_stats["empire"] = local_player.get_character_empire()
	
	# Stats
	if local_player.has_method("get_level"):
		cached_stats["level"] = local_player.get_level()
	if local_player.has_method("get_health"):
		cached_stats["health"] = local_player.get_health()
	if local_player.has_method("get_max_health"):
		cached_stats["max_health"] = local_player.get_max_health()
	if local_player.has_method("get_mana"):
		cached_stats["mana"] = local_player.get_mana()
	if local_player.has_method("get_max_mana"):
		cached_stats["max_mana"] = local_player.get_max_mana()
	if local_player.has_method("get_experience"):
		cached_stats["experience"] = local_player.get_experience()
	if local_player.has_method("get_experience_to_next_level"):
		cached_stats["experience_to_next_level"] = local_player.get_experience_to_next_level()
	if local_player.has_method("get_attack_power"):
		cached_stats["attack"] = local_player.get_attack_power()
	if local_player.has_method("get_defense"):
		cached_stats["defense"] = local_player.get_defense()
	if local_player.has_method("get_attack_speed"):
		cached_stats["attack_speed"] = local_player.get_attack_speed()
	if local_player.has_method("get_gold"):
		cached_stats["gold"] = local_player.get_gold()
	
	_update_display()


func _update_display() -> void:
	"""Update all display elements from cached stats."""
	_update_character_info()
	_update_stats_display()
	_update_exp_display()


func _update_character_info() -> void:
	# Name
	if character_name_label:
		character_name_label.text = cached_stats["name"]
	
	# Class
	if class_label:
		var class_id = cached_stats["class"]
		class_label.text = CLASS_NAMES.get(class_id, "Unknown")
	
	# Empire
	if empire_label:
		var empire_id = cached_stats["empire"]
		var empire_data = EMPIRE_DATA.get(empire_id, {"name": "Unknown", "color": Color.WHITE})
		empire_label.text = empire_data["name"]
		empire_label.add_theme_color_override("font_color", empire_data["color"])


func _update_stats_display() -> void:
	if level_value:
		level_value.text = str(cached_stats["level"])
	
	_update_health_display()
	_update_mana_display()
	
	if attack_value:
		attack_value.text = str(cached_stats["attack"])
	
	if defense_value:
		defense_value.text = str(cached_stats["defense"])
	
	if attack_speed_value:
		attack_speed_value.text = "%.2fx" % cached_stats["attack_speed"]
	
	_update_gold_display()


func _update_health_display() -> void:
	if health_value:
		health_value.text = "%d / %d" % [cached_stats["health"], cached_stats["max_health"]]


func _update_mana_display() -> void:
	if mana_value:
		mana_value.text = "%d / %d" % [cached_stats["mana"], cached_stats["max_mana"]]


func _update_gold_display() -> void:
	if gold_value:
		gold_value.text = _format_gold(cached_stats["gold"])


func _update_exp_display() -> void:
	var current = cached_stats["experience"]
	var to_next = cached_stats["experience_to_next_level"]
	var level = cached_stats["level"]
	
	# Calculate XP within current level (not total XP)
	# Formula matches server: xp_for_level = 100 * (level-1)^2
	var xp_for_current_level = 100 * (level - 1) * (level - 1) if level > 1 else 0
	var xp_within_level = current - xp_for_current_level
	
	# Calculate needed for this level
	var xp_needed_for_level = to_next
	
	if exp_bar:
		exp_bar.max_value = xp_needed_for_level if xp_needed_for_level > 0 else 1
		exp_bar.value = xp_within_level
	
	if exp_label:
		var percent = (float(xp_within_level) / float(xp_needed_for_level)) * 100.0 if xp_needed_for_level > 0 else 0.0
		exp_label.text = "%d / %d (%.1f%%)" % [xp_within_level, xp_needed_for_level, percent]


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


# =============================================================================
# Window Management
# =============================================================================

func toggle_visibility() -> void:
	visible = not visible
	if visible:
		_refresh_all_stats()
		# Release mouse when opening panel
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close_panel() -> void:
	visible = false


func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				is_dragging = true
				drag_offset = global_position - get_global_mouse_position()
			else:
				is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		global_position = get_global_mouse_position() + drag_offset
		_clamp_to_viewport()


func _clamp_to_viewport() -> void:
	"""Ensure the panel stays within the viewport bounds."""
	var viewport_size = get_viewport_rect().size
	var window_size = size
	
	var new_pos = global_position
	new_pos.x = clampf(new_pos.x, 0, viewport_size.x - window_size.x)
	new_pos.y = clampf(new_pos.y, 0, viewport_size.y - window_size.y)
	global_position = new_pos


func _on_viewport_resized() -> void:
	await get_tree().process_frame
	_clamp_to_viewport()


func _center_on_screen() -> void:
	"""Center the panel on the screen."""
	var viewport_size = get_viewport_rect().size
	var window_size = size
	global_position = (viewport_size - window_size) / 2
