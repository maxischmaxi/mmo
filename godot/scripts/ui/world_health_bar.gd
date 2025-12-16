extends Node3D
class_name WorldHealthBar
## Billboard health bar that floats above entities in the world.

## The entity name to display
@export var entity_name: String = "Entity":
	set(value):
		entity_name = value
		if name_label:
			name_label.text = value

## Maximum health
@export var max_health: int = 100:
	set(value):
		max_health = value
		_update_bar()

## Current health
@export var current_health: int = 100:
	set(value):
		current_health = value
		_update_bar()

## Bar colors
@export var full_health_color: Color = Color(0.2, 0.8, 0.2)
@export var low_health_color: Color = Color(0.8, 0.2, 0.2)
@export var background_color: Color = Color(0.15, 0.15, 0.15, 0.9)

## Bar dimensions
@export var bar_width: float = 1.0
@export var bar_height: float = 0.1

## References
@onready var name_label: Label3D = $NameLabel
@onready var bar_background: MeshInstance3D = $BarBackground
@onready var bar_fill: MeshInstance3D = $BarFill

## Materials
var fill_material: StandardMaterial3D


func _ready() -> void:
	# Create materials
	_setup_materials()
	_update_bar()
	
	if name_label:
		name_label.text = entity_name


func _process(_delta: float) -> void:
	# Billboard: always face the camera
	var camera = get_viewport().get_camera_3d()
	if camera:
		# Look at camera but stay upright
		var cam_pos = camera.global_position
		var my_pos = global_position
		var direction = (cam_pos - my_pos).normalized()
		direction.y = 0  # Keep upright
		if direction.length() > 0.01:
			look_at(global_position - direction, Vector3.UP)


func _setup_materials() -> void:
	# Background material
	if bar_background:
		var bg_mat = StandardMaterial3D.new()
		bg_mat.albedo_color = background_color
		bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bg_mat.disable_receive_shadows = true
		bar_background.material_override = bg_mat
	
	# Fill material
	if bar_fill:
		fill_material = StandardMaterial3D.new()
		fill_material.albedo_color = full_health_color
		fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fill_material.disable_receive_shadows = true
		bar_fill.material_override = fill_material


func _update_bar() -> void:
	if not bar_fill:
		return
	
	# Calculate health percentage
	var health_pct = float(current_health) / float(max(max_health, 1))
	health_pct = clamp(health_pct, 0.0, 1.0)
	
	# Update fill bar scale and position
	bar_fill.scale.x = health_pct
	bar_fill.position.x = (health_pct - 1.0) * bar_width * 0.5
	
	# Update color based on health percentage
	if fill_material:
		fill_material.albedo_color = low_health_color.lerp(full_health_color, health_pct)


## Set health values
func set_health(current: int, maximum: int) -> void:
	max_health = maximum
	current_health = current


## Set the display name
func set_entity_name(new_name: String) -> void:
	entity_name = new_name
