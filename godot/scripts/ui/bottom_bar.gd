extends Control
class_name BottomBar
## Bottom bar UI containing player stats, action bar, and utility buttons.

## Number of action slots
const ACTION_SLOT_COUNT: int = 8

## Reference to local player
var local_player: Node = null

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


func _find_player_and_connect() -> void:
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	if local_player:
		# Connect to health changed signal
		if local_player.has_signal("health_changed"):
			local_player.connect("health_changed", _on_health_changed)
		
		# Connect to character selected signal (to update initial values)
		if local_player.has_signal("character_selected"):
			local_player.connect("character_selected", _on_character_selected)


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
	# For future: activate the ability in this slot
	# For now: do nothing (as per user request)
	pass


func _on_action_slot_right_clicked(slot_number: int) -> void:
	# For future: open ability assignment menu
	pass


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
		
		if local_player.has_method("get_experience"):
			# For now, use a placeholder max exp formula
			var exp = local_player.get_experience()
			var level = local_player.get_level()
			var exp_max = level * 1000  # Simple formula
			set_exp_immediate(exp, exp_max)


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
