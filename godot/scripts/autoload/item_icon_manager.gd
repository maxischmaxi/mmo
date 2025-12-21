extends Node
## Manages item icon generation from 3D weapon models.
## Renders weapon models to textures with transparent backgrounds.
## Icons are cached after first render for performance.

## Reuse weapon data from weapon_visual_manager
const WeaponVisualManager = preload("res://scripts/weapon_visual_manager.gd")

## Path to weapon models
const WEAPON_MESH_PATH := "res://assets/models/low_poly_weapon_pack/Weapons for Itch with image texture.fbx_%s.fbx"

## Icon rendering size
const ICON_SIZE := 64

## Cached icons: item_id -> ImageTexture
var icon_cache: Dictionary = {}

## SubViewport for icon rendering
var icon_viewport: SubViewport = null
var icon_camera: Camera3D = null
var icon_light: DirectionalLight3D = null
var icon_light_fill: DirectionalLight3D = null
var weapon_holder: Node3D = null

## Whether the icon viewport is set up
var is_ready: bool = false

## Queue of pending icon requests (item_id -> Array of callbacks)
var pending_requests: Dictionary = {}


func _ready() -> void:
	_setup_icon_viewport()
	is_ready = true


## Set up the SubViewport and scene for icon rendering
func _setup_icon_viewport() -> void:
	# Create SubViewport for icon rendering
	icon_viewport = SubViewport.new()
	icon_viewport.name = "IconViewport"
	icon_viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	icon_viewport.transparent_bg = true
	icon_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	icon_viewport.msaa_3d = Viewport.MSAA_4X  # Anti-aliasing for smoother icons
	add_child(icon_viewport)
	
	# Create a World3D for isolated rendering
	var world = World3D.new()
	icon_viewport.world_3d = world
	
	# Camera - orthographic for clean isometric-style icons
	# Position camera to view weapon from front-right at slight angle
	icon_camera = Camera3D.new()
	icon_camera.name = "IconCamera"
	icon_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	icon_camera.size = 1.0  # Smaller size = weapon fills more of frame
	icon_camera.position = Vector3(0.8, 0.3, 1.2)  # Front-right view, slightly elevated
	icon_camera.near = 0.01
	icon_camera.far = 10.0
	icon_viewport.add_child(icon_camera)
	# look_at must be called after adding to tree
	icon_camera.look_at(Vector3(0, 0.2, 0))  # Look at point slightly above center
	
	# Key light - main illumination
	icon_light = DirectionalLight3D.new()
	icon_light.name = "KeyLight"
	icon_light.rotation_degrees = Vector3(-45, -45, 0)
	icon_light.light_energy = 1.2
	icon_viewport.add_child(icon_light)
	
	# Fill light - softer, from opposite side
	icon_light_fill = DirectionalLight3D.new()
	icon_light_fill.name = "FillLight"
	icon_light_fill.rotation_degrees = Vector3(-30, 135, 0)
	icon_light_fill.light_energy = 0.5
	icon_viewport.add_child(icon_light_fill)
	
	# Weapon holder node
	weapon_holder = Node3D.new()
	weapon_holder.name = "WeaponHolder"
	icon_viewport.add_child(weapon_holder)


## Check if an item has a 3D model available
func has_model(item_id: int) -> bool:
	return WeaponVisualManager.WEAPON_DATA.has(item_id)


## Get the weapon mesh path for an item
func get_weapon_mesh_path(item_id: int) -> String:
	if not has_model(item_id):
		return ""
	var mesh_name: String = WeaponVisualManager.WEAPON_DATA[item_id]["mesh"]
	return WEAPON_MESH_PATH % mesh_name


## Get item icon texture (synchronous - returns cached or null)
## Use request_item_icon() for async generation
func get_item_icon(item_id: int) -> Texture2D:
	if icon_cache.has(item_id):
		return icon_cache[item_id]
	return null


## Request an item icon (async - will call callback when ready)
## callback signature: func(item_id: int, texture: Texture2D)
func request_item_icon(item_id: int, callback: Callable = Callable()) -> void:
	# Already cached?
	if icon_cache.has(item_id):
		if callback.is_valid():
			callback.call(item_id, icon_cache[item_id])
		return
	
	# No model for this item?
	if not has_model(item_id):
		if callback.is_valid():
			callback.call(item_id, null)
		return
	
	# Already pending?
	if pending_requests.has(item_id):
		if callback.is_valid():
			pending_requests[item_id].append(callback)
		return
	
	# Start new request
	pending_requests[item_id] = []
	if callback.is_valid():
		pending_requests[item_id].append(callback)
	
	# Generate the icon
	_generate_icon_async(item_id)


## Generate icon asynchronously
func _generate_icon_async(item_id: int) -> void:
	var texture = await _render_weapon_icon(item_id)
	
	# Cache the result
	if texture:
		icon_cache[item_id] = texture
	
	# Notify all waiting callbacks
	if pending_requests.has(item_id):
		var callbacks = pending_requests[item_id]
		pending_requests.erase(item_id)
		for cb in callbacks:
			if cb.is_valid():
				cb.call(item_id, texture)


## Render a weapon icon from its 3D model
func _render_weapon_icon(item_id: int) -> ImageTexture:
	if not has_model(item_id):
		return null
	
	var weapon_data = WeaponVisualManager.WEAPON_DATA[item_id]
	var mesh_name: String = weapon_data["mesh"]
	var path = WEAPON_MESH_PATH % mesh_name
	
	if not ResourceLoader.exists(path):
		push_warning("ItemIconManager: Weapon mesh not found: %s" % path)
		return null
	
	# Clear previous weapon
	for child in weapon_holder.get_children():
		child.queue_free()
	
	# Wait a frame for cleanup
	await get_tree().process_frame
	
	# Load and add weapon
	var scene = load(path) as PackedScene
	if not scene:
		push_warning("ItemIconManager: Failed to load weapon scene: %s" % path)
		return null
	
	var weapon_instance = scene.instantiate()
	weapon_holder.add_child(weapon_instance)
	
	# Position/rotate weapon for good icon view
	# Adjust based on weapon type for best appearance
	var visual_type: int = weapon_data["type"]
	_position_weapon_for_icon(weapon_instance, visual_type)
	
	# Wait for the instance to be ready
	await get_tree().process_frame
	
	# Render one frame
	icon_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# Wait for render to complete
	await RenderingServer.frame_post_draw
	
	# Capture texture
	var img = icon_viewport.get_texture().get_image()
	var tex = ImageTexture.create_from_image(img)
	
	# Clean up
	weapon_instance.queue_free()
	icon_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	
	return tex


## Position weapon optimally for icon rendering based on visual type
## Weapons should appear vertical (blade pointing up) in icons
## Weapons are modeled with blade along +Y axis (up), handle at origin
func _position_weapon_for_icon(weapon: Node3D, visual_type: int) -> void:
	# Reset transform
	weapon.position = Vector3.ZERO
	weapon.scale = Vector3.ONE
	
	# Weapons are modeled with blade pointing up (+Y)
	# We rotate slightly around Y to show the flat of the blade (not edge-on)
	# Slight X tilt to add depth perception
	
	# Different weapon types need different positioning
	match visual_type:
		WeaponVisualManager.WeaponVisualType.DAGGER:
			# Daggers are small, scale up significantly
			weapon.scale = Vector3(2.0, 2.0, 2.0)
			weapon.rotation_degrees = Vector3(10, -30, 5)  # Slight tilt to show blade
			weapon.position = Vector3(0, -0.1, 0)
		
		WeaponVisualManager.WeaponVisualType.TWO_HANDED_SWORD:
			# Two-handed swords are big, scale down more
			weapon.scale = Vector3(0.5, 0.5, 0.5)
			weapon.rotation_degrees = Vector3(10, -30, 5)
			weapon.position = Vector3(0, 0, 0)
		
		WeaponVisualManager.WeaponVisualType.TWO_HANDED_AXE:
			# Big axes - show the axe head prominently
			weapon.scale = Vector3(0.55, 0.55, 0.55)
			weapon.rotation_degrees = Vector3(10, -30, 5)
			weapon.position = Vector3(0, 0, 0)
		
		WeaponVisualManager.WeaponVisualType.STAFF:
			# Staffs are long, need more scale down
			weapon.scale = Vector3(0.35, 0.35, 0.35)
			weapon.rotation_degrees = Vector3(10, -30, 5)
			weapon.position = Vector3(0, 0, 0)
		
		WeaponVisualManager.WeaponVisualType.ONE_HANDED_SWORD:
			# One-handed swords
			weapon.scale = Vector3(1.0, 1.0, 1.0)
			weapon.rotation_degrees = Vector3(10, -30, 5)
			weapon.position = Vector3(0, -0.05, 0)
		
		WeaponVisualManager.WeaponVisualType.ONE_HANDED_AXE:
			# One-handed axes
			weapon.scale = Vector3(1.0, 1.0, 1.0)
			weapon.rotation_degrees = Vector3(10, -30, 5)
			weapon.position = Vector3(0, -0.05, 0)
		
		WeaponVisualManager.WeaponVisualType.HAMMER:
			# Hammers
			weapon.scale = Vector3(0.9, 0.9, 0.9)
			weapon.rotation_degrees = Vector3(10, -30, 5)
			weapon.position = Vector3(0, -0.05, 0)
		
		WeaponVisualManager.WeaponVisualType.BOW:
			# Bows - show string side
			weapon.scale = Vector3(0.6, 0.6, 0.6)
			weapon.rotation_degrees = Vector3(0, 0, 0)
			weapon.position = Vector3(0, 0, 0)
		
		WeaponVisualManager.WeaponVisualType.SPEAR:
			# Spears are very long
			weapon.scale = Vector3(0.35, 0.35, 0.35)
			weapon.rotation_degrees = Vector3(10, -30, 5)
			weapon.position = Vector3(0, 0.1, 0)
		
		_:
			# Default for any other weapons
			weapon.scale = Vector3(1.0, 1.0, 1.0)
			weapon.rotation_degrees = Vector3(10, -30, 5)
			weapon.position = Vector3(0, -0.05, 0)


## Preload icons for all known weapons (call during loading screen)
func preload_all_icons() -> void:
	for item_id in WeaponVisualManager.WEAPON_DATA.keys():
		if not icon_cache.has(item_id):
			await _render_weapon_icon(item_id)
			if icon_cache.has(item_id):
				print("ItemIconManager: Preloaded icon for item %d" % item_id)


## Clear the icon cache (for memory management)
func clear_cache() -> void:
	icon_cache.clear()
