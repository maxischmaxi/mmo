extends CharacterBody3D
## Remote player - represents another player in the world.
## Uses interpolation for smooth movement and velocity-based animation.

## Player ID from the server
var player_id: int = 0

## Player username
var player_username: String = "Unknown"

## Target position for interpolation
var target_position: Vector3 = Vector3.ZERO

## Target rotation for interpolation
var target_rotation: float = 0.0

## Previous position for velocity calculation
var previous_position: Vector3 = Vector3.ZERO

## Calculated velocity for animations
var calculated_velocity: Vector3 = Vector3.ZERO

## Animation state received from server
var server_animation_state: int = 0

## Currently equipped weapon ID (for visual sync)
var current_weapon_id: int = -1

## Interpolation speed
const INTERPOLATION_SPEED: float = 15.0

## Reference to the name label
@onready var name_label: Label3D = $NameLabel

## Reference to the animation controller
@onready var animation_controller: Node3D = $CharacterModel/AnimationController

## Reference to the weapon visual manager
@onready var weapon_visual_manager: Node3D = $CharacterModel/WeaponVisualManager


func _ready() -> void:
	target_position = global_position
	previous_position = global_position
	update_name_label()
	
	# Disable auto-detect on animation controller - we'll drive it from interpolated velocity
	if animation_controller and animation_controller.has_method("set"):
		animation_controller.auto_detect = false


func _physics_process(delta: float) -> void:
	# Store previous position for velocity calculation
	previous_position = global_position
	
	# Interpolate position
	global_position = global_position.lerp(target_position, INTERPOLATION_SPEED * delta)
	
	# Interpolate rotation
	var current_rot = rotation.y
	rotation.y = lerp_angle(current_rot, target_rotation, INTERPOLATION_SPEED * delta)
	
	# Calculate velocity from position change (for animation)
	if delta > 0:
		calculated_velocity = (global_position - previous_position) / delta
	
	# Update animation based on calculated velocity
	update_animation()


## Update animation based on interpolated movement and server state
func update_animation() -> void:
	if not animation_controller:
		return
	
	# If server says attacking (state 4), prioritize that
	if server_animation_state == 4:
		if animation_controller.has_method("set_animation_state"):
			animation_controller.set_animation_state(4)
		return
	
	# Otherwise use velocity-based animation
	var horizontal_speed := Vector2(calculated_velocity.x, calculated_velocity.z).length()
	
	# Determine animation state
	var anim_state: int
	if horizontal_speed > 6.0:
		anim_state = 2  # Running/Sprint
	elif horizontal_speed > 0.5:
		anim_state = 1  # Walking/Jog
	else:
		anim_state = 0  # Idle
	
	# Call the animation controller's set_animation_state method
	if animation_controller.has_method("set_animation_state"):
		animation_controller.set_animation_state(anim_state)


## Set player info
func set_player_info(id: int, username: String) -> void:
	player_id = id
	player_username = username
	update_name_label()


## Update the position from server data
func update_from_server(pos: Vector3, rot: float, animation_state: int = -1, weapon_id: int = -1) -> void:
	target_position = pos
	target_rotation = rot
	
	# Update animation state if provided
	if animation_state >= 0:
		server_animation_state = animation_state
	
	# Update weapon visual if changed
	if weapon_id != current_weapon_id:
		current_weapon_id = weapon_id
		_update_weapon_visual(weapon_id)


func update_name_label() -> void:
	if name_label:
		name_label.text = player_username


## Update the weapon visual based on equipped weapon ID
func _update_weapon_visual(weapon_id: int) -> void:
	if not weapon_visual_manager:
		return
	
	if weapon_id < 0:
		weapon_visual_manager.unequip_weapon()
	else:
		weapon_visual_manager.equip_weapon(weapon_id)
