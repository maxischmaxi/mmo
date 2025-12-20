@tool
extends Node3D
class_name TerrainLoader
## Loads pre-generated Terrain3D data for a zone.
## Attach to the root of a zone scene to automatically load terrain.
## Uses a custom shader override for proper shadow support.

## Path to the terrain data directory (e.g., "res://assets/terrain/shinsoo")
@export_dir var terrain_data_path: String = "":
	set(value):
		terrain_data_path = value
		if Engine.is_editor_hint():
			_reload_terrain()

## Path to the terrain assets file
@export_file("*.tres") var terrain_assets_path: String = "":
	set(value):
		terrain_assets_path = value
		if Engine.is_editor_hint():
			_reload_terrain()

## Enable terrain collision (required for player movement)
@export var enable_collision: bool = true

## Reload terrain in editor
@export var reload_terrain: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_reload_terrain()

## The loaded Terrain3D node
var terrain: Terrain3D = null


func _ready() -> void:
	if terrain_data_path.is_empty():
		push_warning("TerrainLoader: No terrain_data_path set")
		return
	
	_load_terrain()


func _reload_terrain() -> void:
	# Remove existing terrain
	if terrain and is_instance_valid(terrain):
		terrain.queue_free()
		terrain = null
	
	# Load if path is set and we're in the tree
	if not terrain_data_path.is_empty() and is_inside_tree():
		# Wait a frame for cleanup
		await get_tree().process_frame
		if is_inside_tree():
			_load_terrain()


func _load_terrain() -> void:
	if terrain_data_path.is_empty():
		return
	
	# Create Terrain3D node
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	
	# Set data directory FIRST (required before terrain initializes)
	terrain.data_directory = terrain_data_path
	
	# Shadow settings
	terrain.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_ON
	terrain.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	
	# Create material with custom shader for proper shadow receiving
	# The default Terrain3D shader doesn't set POSITION which breaks shadows
	terrain.material = Terrain3DMaterial.new()
	var shadow_shader = load("res://shaders/terrain_shadow_fix.gdshader") as Shader
	if shadow_shader:
		terrain.material.shader_override = shadow_shader
		terrain.material.enable_shader_override(true)
	
	# Load assets
	if not terrain_assets_path.is_empty() and ResourceLoader.exists(terrain_assets_path):
		terrain.assets = load(terrain_assets_path)
	else:
		terrain.assets = Terrain3DAssets.new()
	
	# Add to scene
	add_child(terrain)
	move_child(terrain, 0)
	
	# Runtime setup
	if not Engine.is_editor_hint():
		await get_tree().process_frame
		await get_tree().process_frame
		
		if terrain and is_instance_valid(terrain):
			# Set camera for Terrain3D LOD system
			var camera = get_viewport().get_camera_3d()
			if camera:
				terrain.set_camera(camera)
			
			# Configure material
			if terrain.material:
				terrain.material.world_background = Terrain3DMaterial.NONE
				terrain.material.update()
	
	print("TerrainLoader: Terrain loaded from ", terrain_data_path)


## Get the height at a world position
func get_height_at(world_pos: Vector3) -> float:
	if terrain and terrain.data:
		return terrain.data.get_height(world_pos)
	return 0.0


## Check if a position is within the terrain bounds
func is_position_valid(world_pos: Vector3) -> bool:
	if terrain and terrain.data:
		var height: float = terrain.data.get_height(world_pos)
		return not is_nan(height)
	return false
