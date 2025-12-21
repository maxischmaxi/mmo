extends SubViewportContainer
class_name WeaponPreview
## Displays a rotating 3D preview of a weapon.
## Used in inventory tooltips for weapons with 3D models.

## Rotation speed in degrees per second
@export var rotation_speed: float = 30.0

## Preview size
@export var preview_size: Vector2i = Vector2i(120, 120)

## Reuse weapon data from weapon_visual_manager
const WeaponVisualManager = preload("res://scripts/weapon_visual_manager.gd")
const WEAPON_MESH_PATH := "res://assets/models/low_poly_weapon_pack/Weapons for Itch with image texture.fbx_%s.fbx"

## References
var viewport: SubViewport = null
var camera: Camera3D = null
var key_light: DirectionalLight3D = null
var fill_light: DirectionalLight3D = null
var weapon_holder: Node3D = null
var current_weapon: Node3D = null

## Current item being displayed (-1 = none)
var current_item_id: int = -1

## Whether preview is active
var is_active: bool = false


func _ready() -> void:
	# Set container size
	custom_minimum_size = Vector2(preview_size)
	size = Vector2(preview_size)
	stretch = true
	
	# Create the SubViewport
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.size = preview_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	
	# Create isolated World3D
	var world = World3D.new()
	viewport.world_3d = world
	
	# Camera - perspective for better 3D feel in preview
	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.current = true
	camera.fov = 30
	camera.position = Vector3(0, 0.3, 2.0)
	camera.near = 0.01
	camera.far = 10.0
	viewport.add_child(camera)
	# look_at must be called after adding to tree
	camera.look_at(Vector3(0, 0.1, 0))
	
	# Key light
	key_light = DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-45, -30, 0)
	key_light.light_energy = 1.3
	viewport.add_child(key_light)
	
	# Fill light
	fill_light = DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.rotation_degrees = Vector3(-20, 150, 0)
	fill_light.light_energy = 0.4
	viewport.add_child(fill_light)
	
	# Weapon holder (this is what rotates)
	weapon_holder = Node3D.new()
	weapon_holder.name = "WeaponHolder"
	viewport.add_child(weapon_holder)
	
	# Start hidden
	visible = false


func _process(delta: float) -> void:
	if not is_active or not visible:
		return
	
	# Rotate the weapon
	if weapon_holder and current_weapon:
		weapon_holder.rotate_y(deg_to_rad(rotation_speed * delta))


## Set the weapon to display by item ID
func set_weapon(item_id: int) -> void:
	# Already showing this weapon?
	if item_id == current_item_id and current_weapon != null:
		_activate()
		return
	
	# Clear any existing weapon
	clear()
	
	# Check if this item has a model
	if not WeaponVisualManager.WEAPON_DATA.has(item_id):
		return
	
	var weapon_data = WeaponVisualManager.WEAPON_DATA[item_id]
	var mesh_name: String = weapon_data["mesh"]
	var path = WEAPON_MESH_PATH % mesh_name
	
	if not ResourceLoader.exists(path):
		push_warning("WeaponPreview: Weapon mesh not found: %s" % path)
		return
	
	# Load and instantiate weapon
	var scene = load(path) as PackedScene
	if not scene:
		push_warning("WeaponPreview: Failed to load weapon scene: %s" % path)
		return
	
	current_weapon = scene.instantiate()
	weapon_holder.add_child(current_weapon)
	current_item_id = item_id
	
	# Position weapon for preview
	var visual_type: int = weapon_data["type"]
	_position_weapon(visual_type)
	
	# Reset holder rotation
	weapon_holder.rotation = Vector3.ZERO
	
	# Activate
	_activate()


## Clear the current weapon
func clear() -> void:
	_deactivate()
	
	if current_weapon:
		current_weapon.queue_free()
		current_weapon = null
	current_item_id = -1


## Check if a weapon is currently displayed
func has_weapon() -> bool:
	return current_weapon != null


## Activate the preview (start rendering and show)
func _activate() -> void:
	is_active = true
	visible = true
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## Deactivate the preview (stop rendering and hide)
func _deactivate() -> void:
	is_active = false
	visible = false
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Position weapon based on visual type
func _position_weapon(visual_type: int) -> void:
	if not current_weapon:
		return
	
	# Reset transform
	current_weapon.position = Vector3.ZERO
	current_weapon.rotation = Vector3.ZERO
	current_weapon.scale = Vector3.ONE
	
	# Adjust based on weapon type
	match visual_type:
		WeaponVisualManager.WeaponVisualType.DAGGER:
			current_weapon.scale = Vector3(1.5, 1.5, 1.5)
			current_weapon.rotation_degrees = Vector3(-30, 0, -30)
		
		WeaponVisualManager.WeaponVisualType.TWO_HANDED_SWORD:
			current_weapon.scale = Vector3(0.6, 0.6, 0.6)
			current_weapon.rotation_degrees = Vector3(-30, 0, -15)
		
		WeaponVisualManager.WeaponVisualType.TWO_HANDED_AXE:
			current_weapon.scale = Vector3(0.6, 0.6, 0.6)
			current_weapon.rotation_degrees = Vector3(-30, 0, -15)
		
		WeaponVisualManager.WeaponVisualType.STAFF:
			current_weapon.scale = Vector3(0.45, 0.45, 0.45)
			current_weapon.rotation_degrees = Vector3(-30, 0, -15)
			current_weapon.position.y = -0.2
		
		_:
			# Default for one-handed weapons
			current_weapon.rotation_degrees = Vector3(-30, 0, -30)
