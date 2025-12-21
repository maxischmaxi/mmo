extends Node3D
class_name DayNightController
## Controls the day/night cycle based on real-world time from the server.
## Calculates sun and moon positions using astronomical formulas.

## Signal emitted when time of day changes significantly
signal time_of_day_changed(time_name: String, sun_elevation: float)

## Berlin, Germany coordinates (default, overridden by server)
var latitude: float = 52.5
var longitude: float = 13.4

## Current server Unix timestamp (UTC)
var server_timestamp: int = 0

## Local timestamp offset (for smooth interpolation)
var local_time_offset: float = 0.0

## Time acceleration multiplier (1.0 = real time, 60.0 = 1 min = 1 hour)
var time_multiplier: float = 1.0

## Whether time acceleration is enabled
var time_acceleration_enabled: bool = false

## Interpolation speed for smooth transitions
const INTERPOLATION_SPEED: float = 2.0

## Current sun elevation angle (degrees, -90 to 90)
var current_sun_elevation: float = 45.0

## Current sun azimuth angle (degrees, 0-360, 0=North)
var current_sun_azimuth: float = 180.0

## Target values for interpolation
var target_sun_elevation: float = 45.0
var target_sun_azimuth: float = 180.0

## References to scene nodes (set by _ready or externally)
var sun_light: DirectionalLight3D = null
var moon_light: DirectionalLight3D = null
var world_environment: WorldEnvironment = null
var sky_material: ShaderMaterial = null

## Sky color presets
const SKY_DAY_TOP := Color(0.4, 0.6, 0.9)
const SKY_DAY_HORIZON := Color(0.7, 0.8, 0.95)
const SKY_SUNSET_TOP := Color(0.3, 0.4, 0.7)
const SKY_SUNSET_HORIZON := Color(0.9, 0.5, 0.3)
const SKY_NIGHT_TOP := Color(0.02, 0.02, 0.06)
const SKY_NIGHT_HORIZON := Color(0.05, 0.08, 0.15)

## Light color presets
const SUN_COLOR := Color(1.0, 0.98, 0.94)
const MOON_COLOR := Color(0.7, 0.8, 1.0)

## Current sky colors (for interpolation)
var current_sky_top := SKY_DAY_TOP
var current_sky_horizon := SKY_DAY_HORIZON
var target_sky_top := SKY_DAY_TOP
var target_sky_horizon := SKY_DAY_HORIZON

## Current light energies
var current_sun_energy: float = 1.0
var current_moon_energy: float = 0.0
var current_ambient_energy: float = 0.8
var target_sun_energy: float = 1.0
var target_moon_energy: float = 0.0
var target_ambient_energy: float = 0.8

## Fog color presets
const FOG_DAY_COLOR := Color(0.7, 0.8, 0.95)
const FOG_SUNSET_COLOR := Color(0.9, 0.6, 0.4)
const FOG_NIGHT_COLOR := Color(0.05, 0.08, 0.15)

## Current fog settings (for interpolation)
var current_fog_color := FOG_DAY_COLOR
var target_fog_color := FOG_DAY_COLOR
var current_fog_density: float = 0.0
var target_fog_density: float = 0.0
var current_fog_light_energy: float = 0.3
var target_fog_light_energy: float = 0.3

## Glow/bloom settings (for golden hour enhancement)
var current_glow_intensity: float = 0.15
var target_glow_intensity: float = 0.15

## Time of day name
var current_time_name: String = "Day"

## Cached camera reference (set once in _setup_sky_environment)
var _cached_camera: Camera3D = null

## Created environment (for cleanup)
var _created_environment: Environment = null

## Created sky (for cleanup)
var _created_sky: Sky = null


func _ready() -> void:
	# Find child nodes
	sun_light = get_node_or_null("Sun") as DirectionalLight3D
	moon_light = get_node_or_null("Moon") as DirectionalLight3D
	world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	
	# We'll set up the environment after the tree is ready
	# to ensure all nodes are properly initialized
	call_deferred("_setup_sky_environment")
	
	# Initialize with current system time if no server time yet
	if server_timestamp == 0:
		server_timestamp = int(Time.get_unix_time_from_system())
	
	# Initial calculation
	_update_celestial_positions()
	_apply_visuals_immediately()
	
	# Debug info
	var star_alpha = clamp((-current_sun_elevation - 6) / 12.0, 0.0, 1.0)
	var moon_elev = -current_sun_elevation
	print("DayNightController: Initialized - ", get_time_string(), " (", current_time_name, ")")
	print("  Sun: elevation=", snapped(current_sun_elevation, 0.1), "°, energy=", current_sun_energy)
	print("  Moon: elevation=", snapped(moon_elev, 0.1), "°, energy=", current_moon_energy)
	print("  Stars visible: ", star_alpha > 0)


func _setup_sky_environment() -> void:
	"""Set up the custom sky shader environment on the main camera."""
	# Safety check - don't set up if we're being destroyed
	if not is_inside_tree():
		return
	
	# Get the main camera
	var main_viewport = get_viewport()
	if not main_viewport:
		push_warning("DayNightController: No viewport found!")
		return
	
	var main_camera = main_viewport.get_camera_3d()
	if not main_camera or not is_instance_valid(main_camera):
		push_warning("DayNightController: No main camera found for sky environment!")
		return
	
	# Cache the camera reference
	_cached_camera = main_camera
	
	# Load the sky shader
	var sky_shader = load("res://shaders/sky.gdshader") as Shader
	if not sky_shader:
		push_error("DayNightController: Could not load sky shader!")
		return
	
	# Create ShaderMaterial for the sky
	sky_material = ShaderMaterial.new()
	sky_material.shader = sky_shader
	
	# Set star brightness (subtle, realistic)
	sky_material.set_shader_parameter("star_brightness", 1.0)
	
	# Set atmospheric scattering parameters for realistic sky
	sky_material.set_shader_parameter("rayleigh_strength", 0.5)
	sky_material.set_shader_parameter("mie_strength", 0.3)
	sky_material.set_shader_parameter("atmosphere_density", 1.0)
	sky_material.set_shader_parameter("horizon_fade_power", 1.2)
	
	# Set initial sky colors based on current time
	_update_sky_shader_colors()
	
	# Create Sky resource with our shader material
	_created_sky = Sky.new()
	_created_sky.sky_material = sky_material
	_created_sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_created_sky.radiance_size = Sky.RADIANCE_SIZE_256
	
	# Create Environment with our sky
	_created_environment = Environment.new()
	_created_environment.background_mode = Environment.BG_SKY
	_created_environment.sky = _created_sky
	_created_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_created_environment.ambient_light_energy = current_ambient_energy
	
	# Set safe defaults for fog (disabled initially until settings are applied)
	_created_environment.fog_enabled = false
	_created_environment.volumetric_fog_enabled = false
	
	# Apply environment directly to the camera (WorldEnvironment wasn't working)
	main_camera.environment = _created_environment
	
	# Apply atmosphere settings from SettingsManager (deferred to ensure it's ready)
	call_deferred("_apply_atmosphere_settings")
	
	print("DayNightController: Sky environment applied with atmosphere effects")


func _update_sky_shader_colors() -> void:
	"""Update the sky shader parameters based on current colors."""
	if not sky_material:
		return
	
	sky_material.set_shader_parameter("sky_top_color", Vector3(current_sky_top.r, current_sky_top.g, current_sky_top.b))
	sky_material.set_shader_parameter("sky_horizon_color", Vector3(current_sky_horizon.r, current_sky_horizon.g, current_sky_horizon.b))
	
	# Ground colors derived from sky
	var ground_bottom = current_sky_top * 0.3
	var ground_horizon = current_sky_horizon * 0.5
	sky_material.set_shader_parameter("ground_bottom_color", Vector3(ground_bottom.r, ground_bottom.g, ground_bottom.b))
	sky_material.set_shader_parameter("ground_horizon_color", Vector3(ground_horizon.r, ground_horizon.g, ground_horizon.b))
	
	# Star visibility - stars visible when sun is below -6 degrees (civil twilight)
	var star_alpha = clamp((-current_sun_elevation - 6) / 12.0, 0.0, 1.0)
	sky_material.set_shader_parameter("star_visibility", star_alpha)


## Called by SettingsManager when atmosphere settings change
func update_atmosphere_settings() -> void:
	"""Update atmosphere settings from SettingsManager."""
	_apply_atmosphere_settings()


func _apply_atmosphere_settings() -> void:
	"""Apply atmosphere settings (fog, tone mapping, etc.) from SettingsManager."""
	if not _created_environment:
		print("DayNightController: Cannot apply atmosphere - environment not created")
		return
	
	# Get settings - use SettingsManager if available
	var fog_distance_setting: int = 2  # Default: MEDIUM
	var volumetric_enabled: bool = false
	var tone_mapping_enabled: bool = true
	var ssao_enabled: bool = false
	var bloom_enabled: bool = true
	
	# Check if SettingsManager singleton exists and is ready
	var settings = get_node_or_null("/root/SettingsManager")
	if settings and settings.has_method("get_fog_distance"):
		fog_distance_setting = settings.get_fog_distance()
		volumetric_enabled = settings.get_volumetric_fog()
		tone_mapping_enabled = settings.get_tone_mapping()
		ssao_enabled = settings.get_ssao()
		bloom_enabled = settings.get_bloom()
		print("DayNightController: Loaded settings - fog_distance=", fog_distance_setting, ", volumetric=", volumetric_enabled)
	else:
		# SettingsManager not ready yet, use safe defaults
		print("DayNightController: SettingsManager not ready, using defaults")
		fog_distance_setting = 2  # MEDIUM
		volumetric_enabled = false
		tone_mapping_enabled = true
		ssao_enabled = false
		bloom_enabled = true
	
	# Apply fog settings based on fog distance
	_apply_fog_settings(fog_distance_setting, volumetric_enabled)
	
	# Apply tone mapping
	_apply_tone_mapping(tone_mapping_enabled)
	
	# Apply SSAO
	_apply_ssao_settings(ssao_enabled)
	
	# Apply bloom/glow
	_apply_glow_settings(bloom_enabled)


func _apply_fog_settings(fog_distance: int, volumetric: bool) -> void:
	"""Apply fog settings based on distance preset."""
	if not _created_environment:
		return
	
	# Fog distance presets - using exponential fog density
	# Higher density = fog kicks in closer, lower density = fog only at far distance
	# Godot exponential fog: 0.001 = light, 0.01 = medium, 0.1 = heavy
	var fog_densities := {
		0: 0.0,      # OFF
		1: 0.03,     # NEAR (50m) - thick fog, close visibility
		2: 0.015,    # MEDIUM (100m) - noticeable fog
		3: 0.008,    # FAR (200m) - moderate distant fog
		4: 0.004,    # VERY_FAR (400m) - subtle atmospheric haze
	}
	
	var density = fog_densities.get(fog_distance, 0.0)
	
	if density <= 0.0:
		# Fog disabled
		_created_environment.fog_enabled = false
		_created_environment.volumetric_fog_enabled = false
		target_fog_density = 0.0
		print("DayNightController: Fog disabled")
		return
	
	# Enable fog with exponential mode
	_created_environment.fog_enabled = true
	_created_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_created_environment.fog_density = density
	target_fog_density = density
	current_fog_density = density  # Also set current immediately
	
	# Set the fog color (will be updated dynamically based on time of day)
	_created_environment.fog_light_color = current_fog_color
	_created_environment.fog_light_energy = 1.0
	
	# Fog affects sky - creates horizon blend
	_created_environment.fog_sky_affect = 0.3
	
	# Aerial perspective - distant objects fade to fog/sky color
	_created_environment.fog_aerial_perspective = 0.3
	
	# Sun scatter - DISABLED, causes bright glow even when sun is below horizon
	_created_environment.fog_sun_scatter = 0.0
	
	print("DayNightController: Fog enabled - density=", density, ", color=", current_fog_color, ", mode=EXPONENTIAL")
	print("DayNightController: fog_enabled=", _created_environment.fog_enabled, ", fog_density=", _created_environment.fog_density)
	
	# Volumetric fog settings
	if volumetric:
		_created_environment.volumetric_fog_enabled = true
		# Volumetric density relative to base fog
		_created_environment.volumetric_fog_density = density * 0.5
		_created_environment.volumetric_fog_albedo = Color(0.95, 0.95, 1.0)
		_created_environment.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		_created_environment.volumetric_fog_emission_energy = 0.0
		_created_environment.volumetric_fog_anisotropy = 0.7  # Forward scattering for god rays
		_created_environment.volumetric_fog_length = 200.0
		_created_environment.volumetric_fog_detail_spread = 2.0
		_created_environment.volumetric_fog_gi_inject = 0.1
		_created_environment.volumetric_fog_ambient_inject = 0.0
		_created_environment.volumetric_fog_sky_affect = 1.0
		print("DayNightController: Volumetric fog enabled")
	else:
		_created_environment.volumetric_fog_enabled = false


func _apply_tone_mapping(enabled: bool) -> void:
	"""Apply tone mapping settings."""
	if not _created_environment:
		return
	
	if enabled:
		# Use Filmic tone mapping for cinematic look
		_created_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		_created_environment.tonemap_exposure = 1.0
		_created_environment.tonemap_white = 1.0
	else:
		# Linear (no tone mapping)
		_created_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR


func _apply_ssao_settings(enabled: bool) -> void:
	"""Apply SSAO settings."""
	if not _created_environment:
		return
	
	_created_environment.ssao_enabled = enabled
	if enabled:
		_created_environment.ssao_radius = 0.8
		_created_environment.ssao_intensity = 1.0
		_created_environment.ssao_power = 1.5
		_created_environment.ssao_detail = 0.5
		_created_environment.ssao_horizon = 0.06
		_created_environment.ssao_sharpness = 0.98
		_created_environment.ssao_light_affect = 0.2


func _apply_glow_settings(enabled: bool) -> void:
	"""Apply glow/bloom settings."""
	if not _created_environment:
		return
	
	_created_environment.glow_enabled = enabled
	if enabled:
		_created_environment.glow_intensity = current_glow_intensity
		_created_environment.glow_strength = 0.8
		_created_environment.glow_bloom = 0.05
		_created_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		_created_environment.glow_hdr_threshold = 0.8
		_created_environment.glow_hdr_scale = 2.0
		_created_environment.glow_hdr_luminance_cap = 12.0
		# Subtle glow levels
		_created_environment.glow_levels_1 = true
		_created_environment.glow_levels_2 = true
		_created_environment.glow_levels_3 = true
		_created_environment.glow_levels_4 = false
		_created_environment.glow_levels_5 = false
		_created_environment.glow_levels_6 = false
		_created_environment.glow_levels_7 = false


func _process(delta: float) -> void:
	# Safety check - don't process if we're being destroyed
	if not is_inside_tree():
		return
	
	# Update local time offset (accounts for time acceleration)
	if time_acceleration_enabled:
		local_time_offset += delta * (time_multiplier - 1.0)
	
	# Recalculate positions every frame for smooth movement
	_update_celestial_positions()
	
	# Interpolate visual changes
	_interpolate_visuals(delta)
	
	# Apply to scene
	_apply_visuals()


func _exit_tree() -> void:
	"""Clean up references to prevent memory leaks on exit."""
	# Remove environment from camera to break circular references
	# This is safe as it just removes the reference, not freeing GPU resources
	if _cached_camera and is_instance_valid(_cached_camera):
		_cached_camera.environment = null
	
	# Clear our local references - let Godot's reference counting handle cleanup
	# DO NOT manually null shader/sky_material/sky properties as that triggers
	# GPU resource freeing from the wrong thread
	_cached_camera = null
	sky_material = null
	_created_sky = null
	_created_environment = null


## Called when server sends time sync
func on_time_sync(unix_timestamp: int, server_latitude: float, server_longitude: float) -> void:
	server_timestamp = unix_timestamp
	latitude = server_latitude
	longitude = server_longitude
	local_time_offset = 0.0
	
	# Immediately update calculations
	_update_celestial_positions()


## Enable/disable time acceleration
func set_time_acceleration(enabled: bool) -> void:
	time_acceleration_enabled = enabled
	if not enabled:
		local_time_offset = 0.0


## Get current game time as Unix timestamp
func get_current_timestamp() -> int:
	return server_timestamp + int(local_time_offset) + int(Time.get_unix_time_from_system()) - server_timestamp


## Get current game time as a formatted string (HH:MM)
func get_time_string() -> String:
	var current_time = _get_effective_timestamp()
	var datetime = Time.get_datetime_dict_from_unix_time(current_time)
	return "%02d:%02d" % [datetime.hour, datetime.minute]


## Get the effective timestamp accounting for acceleration
func _get_effective_timestamp() -> int:
	var base_time = server_timestamp
	var elapsed_since_sync = Time.get_unix_time_from_system() - server_timestamp
	
	if time_acceleration_enabled:
		# Apply time multiplier to elapsed time
		return int(base_time + elapsed_since_sync * time_multiplier + local_time_offset)
	else:
		return int(base_time + elapsed_since_sync)


## Calculate sun and moon positions based on current time
func _update_celestial_positions() -> void:
	var timestamp = _get_effective_timestamp()
	var sun_pos = _calculate_sun_position(timestamp)
	
	target_sun_elevation = sun_pos.elevation
	target_sun_azimuth = sun_pos.azimuth
	
	# Update time of day and calculate target visuals
	_calculate_target_visuals(sun_pos.elevation)


## Calculate sun position using simplified solar position algorithm
func _calculate_sun_position(timestamp: int) -> Dictionary:
	var datetime = Time.get_datetime_dict_from_unix_time(timestamp)
	
	# Day of year (1-365)
	var day_of_year = _get_day_of_year(datetime)
	
	# Solar declination (angle between sun and equator)
	# Simplified formula: varies from -23.45 to +23.45 degrees over the year
	var declination = -23.45 * cos(deg_to_rad(360.0 / 365.0 * (day_of_year + 10)))
	
	# Calculate solar time
	# First, get UTC hour as decimal
	var utc_hour = datetime.hour + datetime.minute / 60.0 + datetime.second / 3600.0
	
	# Equation of time correction (simplified)
	var b = deg_to_rad(360.0 / 365.0 * (day_of_year - 81))
	var eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)  # in minutes
	
	# Local solar time
	var solar_time = utc_hour + longitude / 15.0 + eot / 60.0
	
	# Hour angle (0 at solar noon, negative in morning, positive in afternoon)
	var hour_angle = 15.0 * (solar_time - 12.0)
	
	# Convert to radians for calculations
	var lat_rad = deg_to_rad(latitude)
	var dec_rad = deg_to_rad(declination)
	var ha_rad = deg_to_rad(hour_angle)
	
	# Calculate elevation angle
	var sin_elevation = sin(lat_rad) * sin(dec_rad) + cos(lat_rad) * cos(dec_rad) * cos(ha_rad)
	var elevation = rad_to_deg(asin(clamp(sin_elevation, -1.0, 1.0)))
	
	# Calculate azimuth angle
	var cos_azimuth = (sin(dec_rad) - sin(lat_rad) * sin_elevation) / (cos(lat_rad) * cos(deg_to_rad(elevation)))
	cos_azimuth = clamp(cos_azimuth, -1.0, 1.0)
	var azimuth = rad_to_deg(acos(cos_azimuth))
	
	# Adjust azimuth based on hour angle (morning vs afternoon)
	if hour_angle > 0:
		azimuth = 360.0 - azimuth
	
	return { "elevation": elevation, "azimuth": azimuth }


## Get day of year from datetime dictionary
func _get_day_of_year(datetime: Dictionary) -> int:
	var days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	
	# Check for leap year
	var year = datetime.year
	if (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0):
		days_in_month[1] = 29
	
	var day_of_year = datetime.day
	for i in range(datetime.month - 1):
		day_of_year += days_in_month[i]
	
	return day_of_year


## Calculate target visual values based on sun elevation
func _calculate_target_visuals(sun_elevation: float) -> void:
	var new_time_name: String
	
	if sun_elevation < -12:
		# Night
		new_time_name = "Night"
		target_sky_top = SKY_NIGHT_TOP
		target_sky_horizon = SKY_NIGHT_HORIZON
		target_sun_energy = 0.0
		target_moon_energy = 0.25
		target_ambient_energy = 0.15
		# Night fog - dark blue, slightly denser for mystery
		target_fog_color = FOG_NIGHT_COLOR
		target_fog_light_energy = 0.1
		target_glow_intensity = 0.1
	elif sun_elevation < -6:
		# Nautical twilight
		var t = (sun_elevation + 12) / 6.0  # 0 to 1
		new_time_name = "Twilight"
		target_sky_top = SKY_NIGHT_TOP.lerp(SKY_SUNSET_TOP, t)
		target_sky_horizon = SKY_NIGHT_HORIZON.lerp(SKY_SUNSET_HORIZON, t)
		target_sun_energy = 0.0
		target_moon_energy = 0.25 * (1.0 - t)
		target_ambient_energy = lerp(0.15, 0.3, t)
		# Transition fog color
		target_fog_color = FOG_NIGHT_COLOR.lerp(FOG_SUNSET_COLOR, t)
		target_fog_light_energy = lerp(0.1, 0.3, t)
		target_glow_intensity = lerp(0.1, 0.2, t)
	elif sun_elevation < 0:
		# Civil twilight (golden hour)
		var t = (sun_elevation + 6) / 6.0  # 0 to 1
		new_time_name = "Golden Hour"
		target_sky_top = SKY_SUNSET_TOP.lerp(SKY_DAY_TOP, t * 0.5)
		target_sky_horizon = SKY_SUNSET_HORIZON
		target_sun_energy = t * 0.5
		target_moon_energy = 0.0
		target_ambient_energy = lerp(0.3, 0.5, t)
		# Golden hour - warm fog, enhanced glow
		target_fog_color = FOG_SUNSET_COLOR
		target_fog_light_energy = 0.5
		target_glow_intensity = 0.25  # Stronger glow during golden hour
	elif sun_elevation < 15:
		# Morning/Evening
		var t = sun_elevation / 15.0  # 0 to 1
		new_time_name = "Morning" if _is_morning() else "Evening"
		target_sky_top = SKY_SUNSET_TOP.lerp(SKY_DAY_TOP, t)
		target_sky_horizon = SKY_SUNSET_HORIZON.lerp(SKY_DAY_HORIZON, t)
		target_sun_energy = lerp(0.5, 1.0, t)
		target_moon_energy = 0.0
		target_ambient_energy = lerp(0.5, 0.8, t)
		# Transition from sunset to day fog
		target_fog_color = FOG_SUNSET_COLOR.lerp(FOG_DAY_COLOR, t)
		target_fog_light_energy = lerp(0.5, 0.3, t)
		target_glow_intensity = lerp(0.25, 0.15, t)
	else:
		# Full day
		new_time_name = "Day"
		target_sky_top = SKY_DAY_TOP
		target_sky_horizon = SKY_DAY_HORIZON
		target_sun_energy = 1.0 + (sun_elevation - 15) / 75.0 * 0.2  # Slight increase at noon
		target_moon_energy = 0.0
		target_ambient_energy = 0.8
		# Day fog - light blue-gray
		target_fog_color = FOG_DAY_COLOR
		target_fog_light_energy = 0.3
		target_glow_intensity = 0.15
	
	# Emit signal if time of day changed
	if new_time_name != current_time_name:
		current_time_name = new_time_name
		emit_signal("time_of_day_changed", current_time_name, sun_elevation)


## Check if it's morning (before solar noon)
func _is_morning() -> bool:
	var timestamp = _get_effective_timestamp()
	var datetime = Time.get_datetime_dict_from_unix_time(timestamp)
	var solar_time = datetime.hour + datetime.minute / 60.0 + longitude / 15.0
	return solar_time < 12.0


## Interpolate visual values smoothly
func _interpolate_visuals(delta: float) -> void:
	var lerp_factor = 1.0 - exp(-INTERPOLATION_SPEED * delta)
	
	# Interpolate sun position
	current_sun_elevation = lerp(current_sun_elevation, target_sun_elevation, lerp_factor)
	
	# Handle azimuth wrap-around (0-360)
	var azimuth_diff = target_sun_azimuth - current_sun_azimuth
	if azimuth_diff > 180:
		azimuth_diff -= 360
	elif azimuth_diff < -180:
		azimuth_diff += 360
	current_sun_azimuth = fmod(current_sun_azimuth + azimuth_diff * lerp_factor + 360, 360.0)
	
	# Interpolate sky colors
	current_sky_top = current_sky_top.lerp(target_sky_top, lerp_factor)
	current_sky_horizon = current_sky_horizon.lerp(target_sky_horizon, lerp_factor)
	
	# Interpolate light energies
	current_sun_energy = lerp(current_sun_energy, target_sun_energy, lerp_factor)
	current_moon_energy = lerp(current_moon_energy, target_moon_energy, lerp_factor)
	current_ambient_energy = lerp(current_ambient_energy, target_ambient_energy, lerp_factor)
	
	# Interpolate fog colors and settings
	current_fog_color = current_fog_color.lerp(target_fog_color, lerp_factor)
	current_fog_light_energy = lerp(current_fog_light_energy, target_fog_light_energy, lerp_factor)
	
	# Interpolate glow intensity
	current_glow_intensity = lerp(current_glow_intensity, target_glow_intensity, lerp_factor)


## Apply current visual values to scene nodes
func _apply_visuals() -> void:
	# Determine which light is dominant (for shadow casting)
	# Only ONE light should cast shadows at a time to prevent double shadows
	var sun_is_dominant = current_sun_energy >= current_moon_energy
	
	# Update sun light direction and energy
	if sun_light:
		sun_light.rotation = _direction_to_rotation(current_sun_elevation, current_sun_azimuth)
		sun_light.light_energy = current_sun_energy
		# Only visible when it has meaningful energy AND above horizon
		var sun_visible = current_sun_energy > 0.01 and current_sun_elevation > -5
		sun_light.visible = sun_visible
		# Only cast shadows when sun is the dominant light source
		sun_light.shadow_enabled = sun_is_dominant and current_sun_energy > 0.05
		# ALWAYS use LIGHT_ONLY - we handle sky rendering via shader uniforms
		# This prevents Godot from adding the light to the sky via LIGHT0/LIGHT1
		sun_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	
	# Update moon light - position opposite to sun in the sky
	# Moon is visible when sun is below horizon (simplified lunar model)
	if moon_light:
		# Moon elevation: when sun is at -45 degrees, moon should be at +45 degrees
		# This creates a realistic day/night where moon rises as sun sets
		var moon_elevation = -current_sun_elevation  # Direct opposite
		# Clamp moon elevation to reasonable values
		moon_elevation = clamp(moon_elevation, -90.0, 90.0)
		# Moon azimuth is opposite to sun (180 degrees apart)
		var moon_azimuth = fmod(current_sun_azimuth + 180.0, 360.0)
		
		moon_light.rotation = _direction_to_rotation(moon_elevation, moon_azimuth)
		moon_light.light_energy = current_moon_energy
		# Only visible when it has meaningful energy AND above horizon
		var moon_visible = current_moon_energy > 0.01 and moon_elevation > 0
		moon_light.visible = moon_visible
		# Only cast shadows when moon is the dominant light source
		moon_light.shadow_enabled = not sun_is_dominant and current_moon_energy > 0.05
		# ALWAYS use LIGHT_ONLY - we handle sky rendering via shader uniforms
		moon_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	
	# Update sky shader material
	if sky_material:
		# Set sky colors as vec3 (shader expects vec3, not Color)
		sky_material.set_shader_parameter("sky_top_color", Vector3(current_sky_top.r, current_sky_top.g, current_sky_top.b))
		sky_material.set_shader_parameter("sky_horizon_color", Vector3(current_sky_horizon.r, current_sky_horizon.g, current_sky_horizon.b))
		
		# Ground colors derived from sky
		var ground_bottom = current_sky_top * 0.3
		var ground_horizon = current_sky_horizon * 0.5
		sky_material.set_shader_parameter("ground_bottom_color", Vector3(ground_bottom.r, ground_bottom.g, ground_bottom.b))
		sky_material.set_shader_parameter("ground_horizon_color", Vector3(ground_horizon.r, ground_horizon.g, ground_horizon.b))
		
		# Update star visibility - stars visible when sun is below -6 degrees
		var star_alpha = clamp((-current_sun_elevation - 6) / 12.0, 0.0, 1.0)
		sky_material.set_shader_parameter("star_visibility", star_alpha)
		
		# Set sun direction and energy for sky shader (bypasses Godot's LIGHT0/LIGHT1)
		# This gives us direct control over when the sun/moon disks are rendered
		var sun_dir = _elevation_azimuth_to_direction(current_sun_elevation, current_sun_azimuth)
		sky_material.set_shader_parameter("sun_direction", sun_dir)
		sky_material.set_shader_parameter("sun_energy", current_sun_energy)
		sky_material.set_shader_parameter("sun_color", Vector3(SUN_COLOR.r, SUN_COLOR.g, SUN_COLOR.b))
		
		# Set moon direction and energy
		var moon_elevation = -current_sun_elevation  # Moon opposite to sun
		var moon_azimuth = fmod(current_sun_azimuth + 180.0, 360.0)
		var moon_dir = _elevation_azimuth_to_direction(moon_elevation, moon_azimuth)
		sky_material.set_shader_parameter("moon_direction", moon_dir)
		sky_material.set_shader_parameter("moon_energy", current_moon_energy)
		sky_material.set_shader_parameter("moon_color", Vector3(MOON_COLOR.r, MOON_COLOR.g, MOON_COLOR.b))
	
	# Update ambient light on camera environment
	# Use cached camera reference for better performance and safety
	if not _cached_camera or not is_instance_valid(_cached_camera):
		# Try to re-acquire camera if lost
		var main_viewport = get_viewport()
		if main_viewport:
			_cached_camera = main_viewport.get_camera_3d()
	
	if _cached_camera and is_instance_valid(_cached_camera) and _cached_camera.environment:
		var env = _cached_camera.environment
		
		# Update ambient light
		env.ambient_light_energy = current_ambient_energy
		# Tint ambient light based on time - bluer at night, warmer during day
		var night_factor = clamp(-current_sun_elevation / 12.0, 0.0, 1.0)
		var day_ambient = Color(0.6, 0.65, 0.7)
		var night_ambient = Color(0.3, 0.35, 0.5)
		env.ambient_light_color = day_ambient.lerp(night_ambient, night_factor)
		
		# Update fog color dynamically based on time of day
		if env.fog_enabled:
			env.fog_light_color = current_fog_color
			env.fog_light_energy = current_fog_light_energy
			# Sun scatter only when sun is above horizon - prevents bright glow at night
			if current_sun_elevation > 0:
				env.fog_sun_scatter = 0.1 * (current_sun_elevation / 45.0)  # Gradual increase
			else:
				env.fog_sun_scatter = 0.0
			# Note: fog_density is set by _apply_fog_settings and shouldn't be
			# overwritten here, as it's controlled by the settings menu
		
		# Update volumetric fog color if enabled - use a lighter color for visibility
		if env.volumetric_fog_enabled:
			# Volumetric fog should be lighter/more neutral for god rays
			var vol_fog_color = current_fog_color.lerp(Color.WHITE, 0.7)
			env.volumetric_fog_albedo = vol_fog_color
		
		# Update glow intensity for golden hour enhancement
		if env.glow_enabled:
			env.glow_intensity = current_glow_intensity


## Apply visuals immediately without interpolation
func _apply_visuals_immediately() -> void:
	current_sun_elevation = target_sun_elevation
	current_sun_azimuth = target_sun_azimuth
	current_sky_top = target_sky_top
	current_sky_horizon = target_sky_horizon
	current_sun_energy = target_sun_energy
	current_moon_energy = target_moon_energy
	current_ambient_energy = target_ambient_energy
	current_fog_color = target_fog_color
	current_fog_density = target_fog_density
	current_fog_light_energy = target_fog_light_energy
	current_glow_intensity = target_glow_intensity
	_apply_visuals()


## Convert elevation and azimuth angles to a direction vector (for shader)
## Returns the direction the light is coming FROM (towards the viewer)
func _elevation_azimuth_to_direction(elevation: float, azimuth: float) -> Vector3:
	var elev_rad = deg_to_rad(elevation)
	var azim_rad = deg_to_rad(azimuth)
	
	# Direction vector pointing towards the celestial body
	# Azimuth: 0 = North (+Z), 90 = East (+X), 180 = South (-Z), 270 = West (-X)
	# Elevation: positive = above horizon, negative = below
	return Vector3(
		sin(azim_rad) * cos(elev_rad),
		sin(elev_rad),
		cos(azim_rad) * cos(elev_rad)
	).normalized()


## Convert elevation and azimuth angles to rotation for DirectionalLight3D
func _direction_to_rotation(elevation: float, azimuth: float) -> Vector3:
	# Godot's DirectionalLight3D shines along -Z axis by default
	# We need to rotate it to point in the correct direction
	
	# Convert to radians
	var elev_rad = deg_to_rad(elevation)
	var azim_rad = deg_to_rad(azimuth)
	
	# Calculate direction vector (from light source to ground)
	# Azimuth: 0 = North (+Z), 90 = East (+X), 180 = South (-Z), 270 = West (-X)
	var dir = Vector3(
		sin(azim_rad) * cos(elev_rad),
		-sin(elev_rad),
		cos(azim_rad) * cos(elev_rad)
	)
	
	# Create rotation that makes -Z point in this direction
	if dir.length() < 0.001:
		return Vector3.ZERO
	
	var target = -dir.normalized()
	var rotation = Vector3.ZERO
	
	# Calculate pitch (rotation around X) - elevation
	rotation.x = -elev_rad
	
	# Calculate yaw (rotation around Y) - azimuth
	rotation.y = azim_rad
	
	return rotation
