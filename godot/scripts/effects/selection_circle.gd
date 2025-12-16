extends Node3D
class_name SelectionCircle
## Visual selection indicator that appears under targeted entities.

## Colors for different target types
const COLOR_ENEMY: Color = Color(0.9, 0.2, 0.2, 0.8)
const COLOR_PLAYER: Color = Color(0.2, 0.6, 0.9, 0.8)
const COLOR_NEUTRAL: Color = Color(0.9, 0.9, 0.2, 0.8)

## Rotation speed (radians per second)
@export var rotation_speed: float = 1.0

## Pulse effect settings
@export var pulse_enabled: bool = true
@export var pulse_speed: float = 2.0
@export var pulse_amount: float = 0.1

## Reference to the mesh
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

## Current target type
var current_type: String = "enemy"

## Base scale
var base_scale: Vector3 = Vector3(1, 1, 1)

## Time accumulator for animations
var time: float = 0.0


func _ready() -> void:
	base_scale = scale
	
	# Set initial color
	set_target_type("enemy")


func _process(delta: float) -> void:
	time += delta
	
	# Rotate slowly
	rotation.y += rotation_speed * delta
	
	# Pulse effect
	if pulse_enabled:
		var pulse = 1.0 + sin(time * pulse_speed) * pulse_amount
		scale = base_scale * pulse


## Set the target type and update color
func set_target_type(type: String) -> void:
	current_type = type
	
	if not mesh_instance:
		return
	
	var material = mesh_instance.get_surface_override_material(0)
	if material == null:
		material = mesh_instance.mesh.surface_get_material(0)
		if material:
			material = material.duplicate()
			mesh_instance.set_surface_override_material(0, material)
	
	if material and material is StandardMaterial3D:
		match type:
			"enemy":
				material.albedo_color = COLOR_ENEMY
				material.emission = COLOR_ENEMY * 0.5
			"player":
				material.albedo_color = COLOR_PLAYER
				material.emission = COLOR_PLAYER * 0.5
			_:
				material.albedo_color = COLOR_NEUTRAL
				material.emission = COLOR_NEUTRAL * 0.5
