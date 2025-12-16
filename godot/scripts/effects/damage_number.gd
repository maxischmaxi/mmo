extends Node3D
class_name DamageNumber
## Floating damage number that rises and fades out.

## Duration of the animation
@export var duration: float = 1.0

## Rise distance
@export var rise_distance: float = 1.5

## Random horizontal spread
@export var horizontal_spread: float = 0.5

## Colors
@export var normal_color: Color = Color(1, 1, 1)
@export var critical_color: Color = Color(1, 0.9, 0.2)
@export var heal_color: Color = Color(0.2, 1, 0.4)

## Reference to label
@onready var label: Label3D = $Label3D

## Animation state
var elapsed: float = 0.0
var start_position: Vector3
var target_offset: Vector3
var is_active: bool = false


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	if not is_active:
		return
	
	elapsed += delta
	var progress = elapsed / duration
	
	if progress >= 1.0:
		# Animation complete
		is_active = false
		visible = false
		return
	
	# Ease out curve for smooth deceleration
	var ease_progress = 1.0 - pow(1.0 - progress, 3.0)
	
	# Update position
	position = start_position + target_offset * ease_progress
	
	# Fade out in the last 40%
	if label and progress > 0.6:
		var fade_progress = (progress - 0.6) / 0.4
		label.modulate.a = 1.0 - fade_progress
	
	# Billboard: face camera
	var camera = get_viewport().get_camera_3d()
	if camera:
		var cam_pos = camera.global_position
		var direction = (cam_pos - global_position).normalized()
		direction.y = 0
		if direction.length() > 0.01:
			look_at(global_position - direction, Vector3.UP)


## Show damage number at position
func show_damage(world_position: Vector3, amount: int, is_critical: bool = false) -> void:
	start_position = world_position
	position = world_position
	
	# Random horizontal offset
	var random_x = randf_range(-horizontal_spread, horizontal_spread)
	var random_z = randf_range(-horizontal_spread, horizontal_spread)
	target_offset = Vector3(random_x, rise_distance, random_z)
	
	# Set text and color
	if label:
		label.text = str(amount)
		if is_critical:
			label.modulate = critical_color
			label.font_size = 48  # Larger for crits
			label.text = str(amount) + "!"
		else:
			label.modulate = normal_color
			label.font_size = 32
		label.modulate.a = 1.0
	
	# Reset and start animation
	elapsed = 0.0
	is_active = true
	visible = true


## Show heal number
func show_heal(world_position: Vector3, amount: int) -> void:
	start_position = world_position
	position = world_position
	
	var random_x = randf_range(-horizontal_spread, horizontal_spread)
	var random_z = randf_range(-horizontal_spread, horizontal_spread)
	target_offset = Vector3(random_x, rise_distance, random_z)
	
	if label:
		label.text = "+" + str(amount)
		label.modulate = heal_color
		label.font_size = 32
		label.modulate.a = 1.0
	
	elapsed = 0.0
	is_active = true
	visible = true


## Check if this damage number is currently animating
func is_animating() -> bool:
	return is_active
