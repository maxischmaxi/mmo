@tool
extends MeshInstance3D
class_name WaterPlane
## Realistic water plane with support for rivers and lakes.
## Set flow_direction to (0,0) for a lake, or a non-zero vector for a river.

# ============================================================================
# WATER TYPE
# ============================================================================

## Flow direction. (0,0) = still lake, non-zero = flowing river.
## The direction indicates which way the water flows.
## Magnitude affects visual flow intensity (normalized internally).
@export var flow_direction: Vector2 = Vector2.ZERO:
	set(value):
		flow_direction = value
		_update_shader_param("flow_direction", value)

## Flow speed multiplier for rivers
@export_range(0.0, 5.0) var flow_speed: float = 1.0:
	set(value):
		flow_speed = value
		_update_shader_param("flow_speed", value)

## Water turbulence (0 = calm, 1 = rough/choppy)
@export_range(0.0, 1.0) var turbulence: float = 0.3:
	set(value):
		turbulence = value
		_update_shader_param("turbulence", value)

## Returns true if this is a river (has flow direction)
var is_river: bool:
	get:
		return flow_direction.length() > 0.001

# ============================================================================
# POSITIONING
# ============================================================================

## Water level height (Y position)
@export var water_level: float = -20.0:
	set(value):
		water_level = value
		position.y = water_level

## Size of the water plane in meters
@export var water_size: float = 2048.0:
	set(value):
		water_size = value
		_update_mesh_size()

## Subdivision level (higher = smoother waves, more expensive)
@export_range(32, 256, 16) var subdivisions: int = 128:
	set(value):
		subdivisions = value
		_update_mesh_size()

## Follow player horizontally (for infinite water effect)
@export var follow_player: bool = true

## Reference to the player node (auto-found if null)
@export var player_node: Node3D

# ============================================================================
# COLORS
# ============================================================================

@export_group("Colors")

## Shallow water color
@export var shallow_color: Color = Color(0.08, 0.55, 0.55):
	set(value):
		shallow_color = value
		_update_shader_param("shallow_color", Vector3(value.r, value.g, value.b))

## Deep water color
@export var deep_color: Color = Color(0.02, 0.12, 0.22):
	set(value):
		deep_color = value
		_update_shader_param("deep_color", Vector3(value.r, value.g, value.b))

## Foam/whitecap color
@export var foam_color: Color = Color(0.95, 0.98, 1.0):
	set(value):
		foam_color = value
		_update_shader_param("foam_color", Vector3(value.r, value.g, value.b))

## Sky reflection color
@export var sky_color: Color = Color(0.55, 0.72, 0.92):
	set(value):
		sky_color = value
		_update_shader_param("sky_reflection_color", Vector3(value.r, value.g, value.b))

# ============================================================================
# WAVES
# ============================================================================

@export_group("Waves")

## Height of waves (vertex displacement)
@export_range(0.0, 3.0) var wave_amplitude: float = 0.4:
	set(value):
		wave_amplitude = value
		_update_shader_param("wave_amplitude", value)

## Wave frequency (smaller = larger waves)
@export_range(0.01, 0.2) var wave_frequency: float = 0.06:
	set(value):
		wave_frequency = value
		_update_shader_param("wave_frequency", value)

## Wave animation speed
@export_range(0.0, 3.0) var wave_speed: float = 1.0:
	set(value):
		wave_speed = value
		_update_shader_param("wave_speed", value)

# ============================================================================
# OPTICAL PROPERTIES
# ============================================================================

@export_group("Optical")

## How far you can see through the water (meters)
@export_range(1.0, 50.0) var clarity: float = 12.0:
	set(value):
		clarity = value
		_update_shader_param("clarity", value)

## Refraction strength (underwater distortion)
@export_range(0.0, 0.2) var refraction_strength: float = 0.04:
	set(value):
		refraction_strength = value
		_update_shader_param("refraction_strength", value)

## Reflection strength
@export_range(0.0, 1.0) var reflection_strength: float = 0.6:
	set(value):
		reflection_strength = value
		_update_shader_param("reflection_strength", value)

## Enable chromatic aberration in refraction
@export var chromatic_aberration: bool = true:
	set(value):
		chromatic_aberration = value
		_update_shader_param("enable_chromatic_aberration", value)

# ============================================================================
# FOAM
# ============================================================================

@export_group("Foam")

## Overall foam amount
@export_range(0.0, 1.0) var foam_amount: float = 0.35:
	set(value):
		foam_amount = value
		_update_shader_param("foam_amount", value)

## Width of shore foam (meters from edge)
@export_range(0.5, 10.0) var shore_foam_width: float = 2.5:
	set(value):
		shore_foam_width = value
		_update_shader_param("shore_foam_width", value)

## River foam intensity (streaky foam in flowing water)
@export_range(0.0, 1.0) var river_foam_intensity: float = 0.5:
	set(value):
		river_foam_intensity = value
		_update_shader_param("river_foam_intensity", value)

# ============================================================================
# CAUSTICS
# ============================================================================

@export_group("Caustics")

## Enable underwater caustic patterns
@export var enable_caustics: bool = true:
	set(value):
		enable_caustics = value
		_update_shader_param("enable_caustics", value)

## Caustic intensity
@export_range(0.0, 1.0) var caustic_strength: float = 0.35:
	set(value):
		caustic_strength = value
		_update_shader_param("caustic_strength", value)

# ============================================================================
# PRESETS
# ============================================================================

enum WaterPreset {
	CALM_LAKE,
	WINDY_LAKE,
	STORMY_LAKE,
	GENTLE_RIVER,
	FAST_RIVER,
	RAPIDS,
	TROPICAL_LAGOON,
	DEEP_OCEAN,
	SWAMP,
	ARCTIC
}

## Apply a water preset
@export var preset: WaterPreset = WaterPreset.CALM_LAKE:
	set(value):
		preset = value
		apply_preset(value)


func _ready() -> void:
	position.y = water_level
	_update_mesh_size()
	
	# Apply initial preset
	apply_preset(preset)
	
	if follow_player and player_node == null:
		call_deferred("_find_player")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	if follow_player and player_node:
		position.x = player_node.position.x
		position.z = player_node.position.z


func _find_player() -> void:
	var possible_paths := [
		"/root/Main/Player",
		"/root/Main/World/Player",
		"../Player",
		"../../Player"
	]
	
	for path in possible_paths:
		var node := get_node_or_null(path)
		if node:
			player_node = node
			return
	
	var root := get_tree().root
	player_node = _find_node_by_name(root, "Player")


func _find_node_by_name(node: Node, target_name: String) -> Node3D:
	if node.name == target_name and node is Node3D:
		return node as Node3D
	for child in node.get_children():
		var result := _find_node_by_name(child, target_name)
		if result:
			return result
	return null


func _update_mesh_size() -> void:
	if mesh == null:
		mesh = PlaneMesh.new()
	
	if mesh is PlaneMesh:
		var plane_mesh := mesh as PlaneMesh
		plane_mesh.size = Vector2(water_size, water_size)
		plane_mesh.subdivide_width = subdivisions
		plane_mesh.subdivide_depth = subdivisions


func _update_shader_param(param_name: String, value: Variant) -> void:
	if material_override and material_override is ShaderMaterial:
		var shader_mat := material_override as ShaderMaterial
		shader_mat.set_shader_parameter(param_name, value)


## Apply a preset water style
func apply_preset(water_preset: WaterPreset) -> void:
	match water_preset:
		WaterPreset.CALM_LAKE:
			flow_direction = Vector2.ZERO
			turbulence = 0.1
			wave_amplitude = 0.2
			wave_speed = 0.7
			clarity = 15.0
			shallow_color = Color(0.08, 0.55, 0.55)
			deep_color = Color(0.02, 0.12, 0.22)
			foam_amount = 0.2
			reflection_strength = 0.7
		
		WaterPreset.WINDY_LAKE:
			flow_direction = Vector2.ZERO
			turbulence = 0.4
			wave_amplitude = 0.5
			wave_speed = 1.2
			clarity = 10.0
			shallow_color = Color(0.06, 0.45, 0.48)
			deep_color = Color(0.02, 0.1, 0.18)
			foam_amount = 0.4
			reflection_strength = 0.5
		
		WaterPreset.STORMY_LAKE:
			flow_direction = Vector2.ZERO
			turbulence = 0.9
			wave_amplitude = 1.2
			wave_speed = 1.8
			clarity = 5.0
			shallow_color = Color(0.08, 0.35, 0.38)
			deep_color = Color(0.02, 0.08, 0.12)
			foam_amount = 0.7
			reflection_strength = 0.3
		
		WaterPreset.GENTLE_RIVER:
			flow_direction = Vector2(1.0, 0.0)
			flow_speed = 0.8
			turbulence = 0.2
			wave_amplitude = 0.25
			wave_speed = 1.0
			clarity = 12.0
			shallow_color = Color(0.1, 0.5, 0.5)
			deep_color = Color(0.03, 0.15, 0.2)
			foam_amount = 0.3
			river_foam_intensity = 0.3
			reflection_strength = 0.5
		
		WaterPreset.FAST_RIVER:
			flow_direction = Vector2(1.0, 0.0)
			flow_speed = 2.0
			turbulence = 0.5
			wave_amplitude = 0.4
			wave_speed = 1.5
			clarity = 8.0
			shallow_color = Color(0.08, 0.45, 0.48)
			deep_color = Color(0.02, 0.12, 0.18)
			foam_amount = 0.5
			river_foam_intensity = 0.6
			reflection_strength = 0.4
		
		WaterPreset.RAPIDS:
			flow_direction = Vector2(1.0, 0.0)
			flow_speed = 3.5
			turbulence = 0.85
			wave_amplitude = 0.8
			wave_speed = 2.0
			clarity = 4.0
			shallow_color = Color(0.1, 0.4, 0.42)
			deep_color = Color(0.02, 0.1, 0.15)
			foam_amount = 0.85
			river_foam_intensity = 0.9
			reflection_strength = 0.2
		
		WaterPreset.TROPICAL_LAGOON:
			flow_direction = Vector2.ZERO
			turbulence = 0.05
			wave_amplitude = 0.15
			wave_speed = 0.5
			clarity = 25.0
			shallow_color = Color(0.15, 0.7, 0.65)
			deep_color = Color(0.0, 0.25, 0.4)
			foam_amount = 0.15
			reflection_strength = 0.75
			sky_color = Color(0.6, 0.85, 0.95)
		
		WaterPreset.DEEP_OCEAN:
			flow_direction = Vector2.ZERO
			turbulence = 0.3
			wave_amplitude = 0.8
			wave_frequency = 0.03
			wave_speed = 0.6
			clarity = 8.0
			shallow_color = Color(0.02, 0.3, 0.4)
			deep_color = Color(0.0, 0.05, 0.12)
			foam_amount = 0.25
			reflection_strength = 0.6
		
		WaterPreset.SWAMP:
			flow_direction = Vector2(0.2, 0.1)
			flow_speed = 0.3
			turbulence = 0.15
			wave_amplitude = 0.1
			wave_speed = 0.4
			clarity = 2.0
			shallow_color = Color(0.15, 0.25, 0.12)
			deep_color = Color(0.05, 0.1, 0.05)
			foam_amount = 0.1
			river_foam_intensity = 0.2
			reflection_strength = 0.3
			enable_caustics = false
		
		WaterPreset.ARCTIC:
			flow_direction = Vector2.ZERO
			turbulence = 0.2
			wave_amplitude = 0.3
			wave_speed = 0.8
			clarity = 20.0
			shallow_color = Color(0.4, 0.65, 0.72)
			deep_color = Color(0.05, 0.2, 0.35)
			foam_amount = 0.3
			foam_color = Color(0.98, 0.99, 1.0)
			reflection_strength = 0.8
			sky_color = Color(0.7, 0.8, 0.9)


## Set river flow direction and speed
func set_river_flow(direction: Vector2, speed: float = 1.0) -> void:
	flow_direction = direction.normalized() if direction.length() > 0.001 else Vector2.ZERO
	flow_speed = speed


## Make this a still lake (no flow)
func set_as_lake() -> void:
	flow_direction = Vector2.ZERO


## Set all colors at once
func set_water_colors(shallow: Color, deep: Color, foam: Color = Color.WHITE) -> void:
	shallow_color = shallow
	deep_color = deep
	foam_color = foam
