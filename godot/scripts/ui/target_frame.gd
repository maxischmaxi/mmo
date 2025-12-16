extends Control
class_name TargetFrame
## Target Frame UI - shows information about the currently selected target.

## Reference to the targeting system
var targeting_system: Node = null

## Current values (for smooth animation)
var current_health: float = 100.0
var target_health: float = 100.0
var max_health: float = 100.0

## Animation speed for bars
const BAR_LERP_SPEED: float = 8.0

## UI References
@onready var panel: Panel = $Panel
@onready var hostile_indicator: ColorRect = $Panel/VBoxContainer/TargetInfo/HostileIndicator
@onready var target_name_label: Label = $Panel/VBoxContainer/TargetInfo/TargetName
@onready var level_label: Label = $Panel/VBoxContainer/TargetInfo/Level
@onready var health_bar: ProgressBar = $Panel/VBoxContainer/HealthBar
@onready var health_label: Label = $Panel/VBoxContainer/HealthBar/HealthLabel


func _ready() -> void:
	# Hide by default
	visible = false
	
	# Wait a frame for other nodes to initialize
	await get_tree().process_frame
	
	# Find targeting system
	targeting_system = get_tree().get_first_node_in_group("targeting_system")
	if targeting_system == null:
		var main = get_tree().current_scene
		if main:
			targeting_system = main.get_node_or_null("GameManager/TargetingSystem")
	
	if targeting_system:
		targeting_system.connect("target_changed", _on_target_changed)


func _process(delta: float) -> void:
	if not visible:
		return
	
	# Smoothly animate health bar
	if health_bar:
		current_health = lerp(current_health, target_health, BAR_LERP_SPEED * delta)
		health_bar.value = current_health
		
		# Update health label
		if health_label:
			health_label.text = "%d / %d" % [int(current_health), int(max_health)]
	
	# Update health from game manager if we have a target
	if targeting_system and targeting_system.has_target():
		var data = targeting_system.get_target_data()
		if not data.is_empty() and data.has("health"):
			target_health = float(data.health)
			if data.has("max_health"):
				max_health = float(data.max_health)
				if health_bar:
					health_bar.max_value = max_health


func _on_target_changed(target_id: int, target_type: String, target_data: Dictionary) -> void:
	if target_id == -1 or target_type == "none":
		# No target - hide frame
		visible = false
		return
	
	# Show frame
	visible = true
	
	# Update hostile indicator
	if hostile_indicator:
		if target_type == "enemy":
			hostile_indicator.color = Color(0.8, 0.2, 0.2, 1.0)  # Red for enemies
			hostile_indicator.visible = true
		elif target_type == "player":
			hostile_indicator.color = Color(0.2, 0.6, 0.9, 1.0)  # Blue for players
			hostile_indicator.visible = true
		else:
			hostile_indicator.visible = false
	
	# Update name
	if target_name_label:
		if target_data.has("name"):
			target_name_label.text = target_data.name
		else:
			target_name_label.text = "Unknown"
		
		# Color name based on type
		if target_type == "enemy":
			target_name_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		else:
			target_name_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	
	# Update level
	if level_label:
		if target_data.has("level"):
			level_label.text = "Lv. %d" % target_data.level
		else:
			level_label.text = ""
	
	# Update health
	if target_data.has("health") and target_data.has("max_health"):
		max_health = float(target_data.max_health)
		target_health = float(target_data.health)
		current_health = target_health  # Snap to value on target change
		
		if health_bar:
			health_bar.max_value = max_health
			health_bar.value = current_health
		
		if health_label:
			health_label.text = "%d / %d" % [int(current_health), int(max_health)]
