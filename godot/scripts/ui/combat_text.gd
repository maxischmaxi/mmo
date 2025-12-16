extends Control
class_name CombatText
## Displays combat feedback messages like "Out of range", "No target", etc.

## How long messages stay on screen
@export var message_duration: float = 2.0

## Fade out time
@export var fade_duration: float = 0.5

## Message colors
const COLOR_ERROR: Color = Color(1.0, 0.3, 0.3, 1.0)
const COLOR_INFO: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_WARNING: Color = Color(1.0, 0.8, 0.2, 1.0)
const COLOR_SUCCESS: Color = Color(0.3, 1.0, 0.3, 1.0)

## UI References
@onready var message_label: Label = $Panel/MessageLabel
@onready var panel: Panel = $Panel

## Animation state
var time_remaining: float = 0.0
var is_showing: bool = false

## Reference to targeting system
var targeting_system: Node = null


func _ready() -> void:
	# Hide by default
	visible = false
	modulate.a = 0.0
	
	# Wait a frame for other nodes
	await get_tree().process_frame
	
	# Find and connect to targeting system
	targeting_system = get_tree().get_first_node_in_group("targeting_system")
	if targeting_system == null:
		var main = get_tree().current_scene
		if main:
			targeting_system = main.get_node_or_null("GameManager/TargetingSystem")
	
	if targeting_system and targeting_system.has_signal("show_message"):
		targeting_system.connect("show_message", _on_show_message)


func _process(delta: float) -> void:
	if not is_showing:
		return
	
	time_remaining -= delta
	
	if time_remaining <= 0:
		# Start fade out
		is_showing = false
		_fade_out()
	elif time_remaining <= fade_duration:
		# Fading out
		modulate.a = time_remaining / fade_duration


func _on_show_message(message: String, message_type: String) -> void:
	show_message(message, message_type)


## Show a message with the specified type
func show_message(message: String, message_type: String = "info") -> void:
	if message_label:
		message_label.text = message
		
		# Set color based on type
		match message_type:
			"error":
				message_label.add_theme_color_override("font_color", COLOR_ERROR)
			"warning":
				message_label.add_theme_color_override("font_color", COLOR_WARNING)
			"success":
				message_label.add_theme_color_override("font_color", COLOR_SUCCESS)
			_:
				message_label.add_theme_color_override("font_color", COLOR_INFO)
	
	# Show and reset timer
	visible = true
	modulate.a = 1.0
	time_remaining = message_duration
	is_showing = true


func _fade_out() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(func(): visible = false)
