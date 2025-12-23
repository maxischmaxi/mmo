@tool
class_name GrassSystem
extends Node3D
## Fortnite-style grass system using MultiMeshInstance3D
## Generates stylized grass blades and scatters them across the terrain

# ============================================================================
# GRASS BLADE SETTINGS
# ============================================================================

@export_group("Grass Blade")
## Width of each grass blade at the base
@export_range(0.01, 0.5) var blade_width: float = 0.08:
	set(value):
		blade_width = value
		if Engine.is_editor_hint():
			_regenerate_mesh()

## Height of each grass blade
@export_range(0.1, 2.0) var blade_height: float = 0.4:
	set(value):
		blade_height = value
		if Engine.is_editor_hint():
			_regenerate_mesh()

## Random height variation (0.2 = +/- 20%)
@export_range(0.0, 0.5) var height_variation: float = 0.25

## Number of segments per blade (more = smoother bending)
@export_range(1, 6) var blade_segments: int = 3:
	set(value):
		blade_segments = value
		if Engine.is_editor_hint():
			_regenerate_mesh()

## Curve factor for blade shape (how much it bends backward)
@export_range(0.0, 1.0) var blade_curve: float = 0.15:
	set(value):
		blade_curve = value
		if Engine.is_editor_hint():
			_regenerate_mesh()

# ============================================================================
# SPAWNING SETTINGS
# ============================================================================

@export_group("Spawning")
## Number of grass instances to spawn
@export_range(100, 100000) var instance_count: int = 10000:
	set(value):
		instance_count = value
		if Engine.is_editor_hint():
			_regenerate_instances()

## Radius around this node to spawn grass
@export_range(1.0, 500.0) var spawn_radius: float = 50.0:
	set(value):
		spawn_radius = value
		if Engine.is_editor_hint():
			_regenerate_instances()

## Minimum distance between grass blades (for natural spacing)
@export_range(0.0, 1.0) var min_spacing: float = 0.1

## Use terrain height (requires Terrain3D in scene)
@export var use_terrain_height: bool = true

## Terrain3D node path (if using terrain height)
@export var terrain_path: NodePath

## Minimum terrain height for grass to spawn
@export var min_height: float = -10.0

## Maximum terrain height for grass to spawn
@export var max_height: float = 50.0

## Slope threshold - grass won't spawn on steeper slopes (0 = flat, 1 = vertical)
@export_range(0.0, 1.0) var max_slope: float = 0.6

# ============================================================================
# MATERIAL SETTINGS
# ============================================================================

@export_group("Material")
## Custom shader material (if not set, creates default)
@export var grass_material: ShaderMaterial

## Base color for grass
@export var base_color: Color = Color(0.18, 0.45, 0.12):
	set(value):
		base_color = value
		_update_material_colors()

## Tip color for grass
@export var tip_color: Color = Color(0.45, 0.78, 0.25):
	set(value):
		tip_color = value
		_update_material_colors()

## Highlight color for grass tips
@export var highlight_color: Color = Color(0.65, 0.92, 0.45):
	set(value):
		highlight_color = value
		_update_material_colors()

# ============================================================================
# WIND SETTINGS
# ============================================================================

@export_group("Wind")
## Wind strength
@export_range(0.0, 0.3) var wind_strength: float = 0.08:
	set(value):
		wind_strength = value
		_update_wind_settings()

## Wind speed
@export_range(0.0, 5.0) var wind_speed: float = 1.2:
	set(value):
		wind_speed = value
		_update_wind_settings()

## Wind direction
@export var wind_direction: Vector2 = Vector2(1.0, 0.3):
	set(value):
		wind_direction = value
		_update_wind_settings()

# ============================================================================
# DEBUG / TOOLS
# ============================================================================

@export_group("Tools")
## Regenerate grass (click to refresh)
@export var regenerate: bool = false:
	set(value):
		if value:
			regenerate_grass()
			regenerate = false

# ============================================================================
# INTERNAL VARIABLES
# ============================================================================

var _multimesh_instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _grass_mesh: ArrayMesh
var _terrain: Node3D
var _rng: RandomNumberGenerator

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash(global_position)
	
	# Find terrain if path is set
	if terrain_path and use_terrain_height:
		_terrain = get_node_or_null(terrain_path)
	
	# Create or get MultiMeshInstance3D child
	_setup_multimesh_instance()
	
	# Generate grass mesh
	_regenerate_mesh()
	
	# Create default material if not set
	if not grass_material:
		_create_default_material()
	
	# Spawn grass instances
	_regenerate_instances()

func _setup_multimesh_instance() -> void:
	# Look for existing MultiMeshInstance3D child
	for child in get_children():
		if child is MultiMeshInstance3D:
			_multimesh_instance = child
			break
	
	# Create if not found
	if not _multimesh_instance:
		_multimesh_instance = MultiMeshInstance3D.new()
		_multimesh_instance.name = "GrassMultiMesh"
		add_child(_multimesh_instance)
		if Engine.is_editor_hint():
			_multimesh_instance.owner = get_tree().edited_scene_root
	
	# Create MultiMesh if needed
	if not _multimesh_instance.multimesh:
		_multimesh = MultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh_instance.multimesh = _multimesh

# ============================================================================
# MESH GENERATION
# ============================================================================

func _regenerate_mesh() -> void:
	if not is_inside_tree():
		return
	
	_grass_mesh = _create_grass_blade_mesh()
	
	if _multimesh_instance and _multimesh_instance.multimesh:
		_multimesh_instance.multimesh.mesh = _grass_mesh

func _create_grass_blade_mesh() -> ArrayMesh:
	## Creates a cross-pattern grass blade (two quads crossing at 90 degrees)
	## This looks good from all viewing angles
	
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Create two crossing quads
	for rotation_idx in range(2):
		var angle = rotation_idx * PI / 2.0  # 0 and 90 degrees
		_add_grass_blade_quad(st, angle)
	
	st.generate_normals()
	st.generate_tangents()
	
	return st.commit()

func _add_grass_blade_quad(st: SurfaceTool, y_rotation: float) -> void:
	## Adds a single grass blade quad with the given Y rotation
	
	var half_width = blade_width / 2.0
	var segments = blade_segments
	
	# Rotation transform
	var rot = Transform3D()
	rot = rot.rotated(Vector3.UP, y_rotation)
	
	# Generate vertices for each segment
	var vertices: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	
	for i in range(segments + 1):
		var t = float(i) / float(segments)  # 0 to 1
		var height = t * blade_height
		
		# Taper width toward tip
		var width_at_height = half_width * (1.0 - t * 0.8)
		
		# Curve the blade backward slightly
		var curve_offset = blade_curve * t * t * blade_height
		
		# Left and right vertices at this height
		var left = rot * Vector3(-width_at_height, height, curve_offset)
		var right = rot * Vector3(width_at_height, height, curve_offset)
		
		vertices.append(left)
		vertices.append(right)
		uvs.append(Vector2(0.0, t))
		uvs.append(Vector2(1.0, t))
	
	# Create triangles between segments
	for i in range(segments):
		var base = i * 2
		
		# First triangle (bottom-left, bottom-right, top-left)
		_add_vertex(st, vertices[base], uvs[base])
		_add_vertex(st, vertices[base + 1], uvs[base + 1])
		_add_vertex(st, vertices[base + 2], uvs[base + 2])
		
		# Second triangle (bottom-right, top-right, top-left)
		_add_vertex(st, vertices[base + 1], uvs[base + 1])
		_add_vertex(st, vertices[base + 3], uvs[base + 3])
		_add_vertex(st, vertices[base + 2], uvs[base + 2])

func _add_vertex(st: SurfaceTool, pos: Vector3, uv: Vector2) -> void:
	st.set_uv(uv)
	st.add_vertex(pos)

# ============================================================================
# MATERIAL CREATION
# ============================================================================

func _create_default_material() -> void:
	grass_material = ShaderMaterial.new()
	
	# Load the grass shader
	var shader = load("res://shaders/fortnite_grass.gdshader")
	if shader:
		grass_material.shader = shader
		_update_material_colors()
		_update_wind_settings()
	else:
		push_warning("GrassSystem: Could not load fortnite_grass.gdshader")
	
	if _multimesh_instance:
		_multimesh_instance.material_override = grass_material

func _update_material_colors() -> void:
	if grass_material:
		grass_material.set_shader_parameter("base_color", Vector3(base_color.r, base_color.g, base_color.b))
		grass_material.set_shader_parameter("tip_color", Vector3(tip_color.r, tip_color.g, tip_color.b))
		grass_material.set_shader_parameter("highlight_color", Vector3(highlight_color.r, highlight_color.g, highlight_color.b))

func _update_wind_settings() -> void:
	if grass_material:
		grass_material.set_shader_parameter("wind_strength", wind_strength)
		grass_material.set_shader_parameter("wind_speed", wind_speed)
		grass_material.set_shader_parameter("wind_direction", wind_direction)

# ============================================================================
# INSTANCE SPAWNING
# ============================================================================

func _regenerate_instances() -> void:
	if not is_inside_tree():
		return
	
	if not _multimesh_instance or not _multimesh_instance.multimesh:
		return
	
	_multimesh = _multimesh_instance.multimesh
	_multimesh.instance_count = instance_count
	
	# Get terrain reference if needed
	if use_terrain_height and terrain_path:
		_terrain = get_node_or_null(terrain_path)
	
	var origin = global_position
	var valid_instances = 0
	
	for i in range(instance_count):
		# Generate random position within spawn radius (uniform disk distribution)
		var angle = _rng.randf() * TAU
		var radius = sqrt(_rng.randf()) * spawn_radius  # sqrt for uniform distribution
		
		var local_pos = Vector3(
			cos(angle) * radius,
			0.0,
			sin(angle) * radius
		)
		
		var world_pos = origin + local_pos
		var height = 0.0
		var normal = Vector3.UP
		
		# Get terrain height if available
		if _terrain and _terrain.has_method("get_height"):
			height = _terrain.get_height(world_pos)
			
			# Check height bounds
			if height < min_height or height > max_height:
				# Place outside view (effectively hidden)
				_multimesh.set_instance_transform(i, Transform3D().translated(Vector3(0, -1000, 0)))
				continue
			
			# Get terrain normal for slope check
			if _terrain.has_method("get_normal"):
				normal = _terrain.get_normal(world_pos)
				var slope = 1.0 - normal.y
				if slope > max_slope:
					_multimesh.set_instance_transform(i, Transform3D().translated(Vector3(0, -1000, 0)))
					continue
		
		# Random rotation around Y axis
		var y_rot = _rng.randf() * TAU
		
		# Random scale variation
		var scale_factor = 1.0 + (_rng.randf() - 0.5) * height_variation * 2.0
		
		# Build transform
		var transform = Transform3D()
		
		# Apply rotation
		transform = transform.rotated(Vector3.UP, y_rot)
		
		# Apply scale
		transform = transform.scaled(Vector3(scale_factor, scale_factor, scale_factor))
		
		# Apply position
		local_pos.y = height
		transform.origin = local_pos
		
		_multimesh.set_instance_transform(i, transform)
		valid_instances += 1
	
	if Engine.is_editor_hint():
		print("GrassSystem: Spawned %d grass instances" % valid_instances)

# ============================================================================
# PUBLIC API
# ============================================================================

## Regenerate all grass (mesh and instances)
func regenerate_grass() -> void:
	_regenerate_mesh()
	_regenerate_instances()
	
	if grass_material:
		_multimesh_instance.material_override = grass_material
		_update_material_colors()
		_update_wind_settings()

## Update grass positions (call after terrain changes)
func update_positions() -> void:
	_regenerate_instances()

## Set the terrain node for height sampling
func set_terrain(terrain_node: Node3D) -> void:
	_terrain = terrain_node

## Get the MultiMeshInstance3D for custom modifications
func get_multimesh_instance() -> MultiMeshInstance3D:
	return _multimesh_instance
