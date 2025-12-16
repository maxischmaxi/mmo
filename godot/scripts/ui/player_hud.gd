extends Control
class_name PlayerHUD
## Player HUD showing health, mana, and player info.

## Reference to local player
var local_player: Node = null

## Current values (for smooth animation)
var current_health: float = 100.0
var current_mana: float = 50.0
var target_health: float = 100.0
var target_mana: float = 50.0

## Animation speed for bars
const BAR_LERP_SPEED: float = 5.0

## UI References
@onready var health_bar: ProgressBar = $Panel/VBoxContainer/HealthBar
@onready var mana_bar: ProgressBar = $Panel/VBoxContainer/ManaBar
@onready var player_name_label: Label = $Panel/VBoxContainer/PlayerInfo/PlayerName
@onready var level_label: Label = $Panel/VBoxContainer/PlayerInfo/Level
@onready var swing_timer_container: HBoxContainer = $Panel/VBoxContainer/SwingTimerContainer
@onready var swing_timer_bar: ProgressBar = $Panel/VBoxContainer/SwingTimerContainer/SwingTimer


func _ready() -> void:
	# Find local player
	await get_tree().process_frame
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	if local_player:
		# Connect to login success signal (replaces old "connected" signal)
		if local_player.has_signal("login_success"):
			local_player.connect("login_success", _on_login_success)
		# Connect to health changed signal
		if local_player.has_signal("health_changed"):
			local_player.connect("health_changed", _on_health_changed)
		# Set initial values
		update_player_name("Player")
	
	# Find combat controller for auto-attack signals
	if local_player:
		var combat_controller = local_player.get_node_or_null("CombatController")
		if combat_controller:
			if combat_controller.has_signal("auto_attack_changed"):
				combat_controller.connect("auto_attack_changed", _on_auto_attack_changed)
			if combat_controller.has_signal("attack_cooldown_updated"):
				combat_controller.connect("attack_cooldown_updated", _on_swing_timer_updated)
	
	# Set initial bar values
	if health_bar:
		health_bar.max_value = 100
		health_bar.value = 100
	if mana_bar:
		mana_bar.max_value = 50
		mana_bar.value = 50
	
	# Hide swing timer initially
	if swing_timer_container:
		swing_timer_container.visible = false


func _process(delta: float) -> void:
	# Smoothly animate health bar
	if health_bar:
		current_health = lerp(current_health, target_health, BAR_LERP_SPEED * delta)
		health_bar.value = current_health
	
	# Smoothly animate mana bar
	if mana_bar:
		current_mana = lerp(current_mana, target_mana, BAR_LERP_SPEED * delta)
		mana_bar.value = current_mana


func _on_login_success(_player_id: int) -> void:
	# Update HUD with player data from login
	if local_player:
		# Get stats from player if available
		if local_player.has_method("get_health"):
			var health = local_player.get_health()
			var max_health = local_player.get_max_health()
			set_health_immediate(health, max_health)
		if local_player.has_method("get_mana"):
			var mana = local_player.get_mana()
			var max_mana = local_player.get_max_mana()
			set_mana_immediate(mana, max_mana)
		if local_player.has_method("get_level"):
			update_level(local_player.get_level())


func _on_health_changed(current_health_value: int, max_health_value: int) -> void:
	update_health(current_health_value, max_health_value)
	_update_health_label(current_health_value, max_health_value)


func _update_health_label(current: int, maximum: int) -> void:
	var health_label = health_bar.get_node_or_null("HealthLabel") as Label
	if health_label:
		health_label.text = "%d / %d" % [current, maximum]


## Update health display
func update_health(current: int, maximum: int) -> void:
	target_health = float(current)
	if health_bar:
		health_bar.max_value = maximum


## Update mana display
func update_mana(current: int, maximum: int) -> void:
	target_mana = float(current)
	if mana_bar:
		mana_bar.max_value = maximum


## Update player name
func update_player_name(player_name: String) -> void:
	if player_name_label:
		player_name_label.text = player_name


## Update level
func update_level(level: int) -> void:
	if level_label:
		level_label.text = "Lv. " + str(level)


## Set health immediately (no animation)
func set_health_immediate(current: int, maximum: int) -> void:
	current_health = float(current)
	target_health = float(current)
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current


## Set mana immediately (no animation)
func set_mana_immediate(current: int, maximum: int) -> void:
	current_mana = float(current)
	target_mana = float(current)
	if mana_bar:
		mana_bar.max_value = maximum
		mana_bar.value = current


# =============================================================================
# Auto-Attack / Swing Timer
# =============================================================================

## Called when auto-attack state changes
func _on_auto_attack_changed(is_active: bool) -> void:
	if swing_timer_container:
		swing_timer_container.visible = is_active
	if swing_timer_bar and not is_active:
		swing_timer_bar.value = 0.0


## Called when swing timer updates (attack cooldown progress)
func _on_swing_timer_updated(progress: float) -> void:
	if swing_timer_bar:
		swing_timer_bar.value = progress * 100.0  # Convert 0-1 to 0-100 for progress bar
