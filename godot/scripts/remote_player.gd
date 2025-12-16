extends CharacterBody3D
## Remote player - represents another player in the world.
## Uses interpolation for smooth movement.

## Player ID from the server
var player_id: int = 0

## Player username
var player_username: String = "Unknown"

## Target position for interpolation
var target_position: Vector3 = Vector3.ZERO

## Target rotation for interpolation
var target_rotation: float = 0.0

## Interpolation speed
const INTERPOLATION_SPEED: float = 15.0

@onready var name_label: Label3D = $NameLabel


func _ready() -> void:
	target_position = global_position
	update_name_label()


func _physics_process(delta: float) -> void:
	# Interpolate position
	global_position = global_position.lerp(target_position, INTERPOLATION_SPEED * delta)
	
	# Interpolate rotation
	var current_rot = rotation.y
	rotation.y = lerp_angle(current_rot, target_rotation, INTERPOLATION_SPEED * delta)


## Set player info
func set_player_info(id: int, username: String) -> void:
	player_id = id
	player_username = username
	update_name_label()


## Update the position from server data
func update_from_server(pos: Vector3, rot: float) -> void:
	target_position = pos
	target_rotation = rot


func update_name_label() -> void:
	if name_label:
		name_label.text = player_username
