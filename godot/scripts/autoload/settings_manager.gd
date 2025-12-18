extends Node
class_name SettingsManagerClass
## Global settings manager for game configuration.
## Handles loading, saving, and applying graphics settings.
## Access via the SettingsManager autoload singleton.

const SETTINGS_PATH := "user://settings.cfg"

## Signal emitted when settings are applied
signal settings_applied

## Window modes
enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }

## VSync modes
enum VSyncMode { DISABLED, ENABLED, ADAPTIVE }

## Anti-aliasing modes
enum AAMode { DISABLED, FXAA, MSAA_2X, MSAA_4X, MSAA_8X, TAA }

## Shadow quality levels
enum ShadowQuality { OFF, LOW, MEDIUM, HIGH }

## Quality presets
enum QualityPreset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }

# =============================================================================
# Default Settings
# =============================================================================

const DEFAULTS := {
	"graphics": {
		"window_mode": WindowMode.WINDOWED,
		"resolution": "1920x1080",
		"vsync": VSyncMode.ENABLED,
		"fps_limit": 0,  # 0 = unlimited
		"render_scale": 1.0,
		"antialiasing": AAMode.DISABLED,
		"shadow_quality": ShadowQuality.MEDIUM,
		"ssao": false,
		"bloom": true,
	}
}

# Quality presets configuration
const PRESETS := {
	"low": {
		"render_scale": 0.75,
		"antialiasing": AAMode.DISABLED,
		"shadow_quality": ShadowQuality.LOW,
		"ssao": false,
		"bloom": false,
	},
	"medium": {
		"render_scale": 0.85,
		"antialiasing": AAMode.FXAA,
		"shadow_quality": ShadowQuality.MEDIUM,
		"ssao": false,
		"bloom": true,
	},
	"high": {
		"render_scale": 1.0,
		"antialiasing": AAMode.MSAA_4X,
		"shadow_quality": ShadowQuality.HIGH,
		"ssao": true,
		"bloom": true,
	},
	"ultra": {
		"render_scale": 1.0,
		"antialiasing": AAMode.TAA,
		"shadow_quality": ShadowQuality.HIGH,
		"ssao": true,
		"bloom": true,
	},
}

# =============================================================================
# Current Settings (in memory)
# =============================================================================

var _config := ConfigFile.new()
var _current_preset: QualityPreset = QualityPreset.CUSTOM

# Cached references for applying settings
var _viewport: Viewport = null
var _environment: Environment = null
var _sun: DirectionalLight3D = null
var _moon: DirectionalLight3D = null


func _ready() -> void:
	# Load settings on startup
	load_settings()
	
	# Apply settings after a short delay to ensure scene is ready
	await get_tree().process_frame
	await get_tree().process_frame
	_cache_references()
	apply_settings()


func _cache_references() -> void:
	"""Cache references to nodes needed for applying settings."""
	_viewport = get_viewport()
	
	# Find WorldEnvironment
	var day_night = get_tree().get_first_node_in_group("day_night_controller")
	if day_night:
		var world_env = day_night.get_node_or_null("WorldEnvironment")
		if world_env and world_env is WorldEnvironment:
			_environment = world_env.environment
	
	# Find sun and moon lights
	if day_night:
		_sun = day_night.get_node_or_null("Sun")
		_moon = day_night.get_node_or_null("Moon")


# =============================================================================
# Settings Persistence
# =============================================================================

func load_settings() -> void:
	"""Load settings from config file."""
	var err = _config.load(SETTINGS_PATH)
	if err != OK:
		print("SettingsManager: No settings file found, using defaults")
		_apply_defaults()
		return
	
	print("SettingsManager: Settings loaded from ", SETTINGS_PATH)


func save_settings() -> void:
	"""Save current settings to config file."""
	var err = _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: Failed to save settings: ", err)
	else:
		print("SettingsManager: Settings saved to ", SETTINGS_PATH)


func _apply_defaults() -> void:
	"""Apply default settings to config."""
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			_config.set_value(section, key, DEFAULTS[section][key])


func reset_to_defaults() -> void:
	"""Reset all settings to default values (does not apply or save)."""
	_apply_defaults()
	_current_preset = QualityPreset.MEDIUM


# =============================================================================
# Settings Getters/Setters
# =============================================================================

func get_setting(section: String, key: String, default = null):
	"""Get a setting value."""
	if _config.has_section_key(section, key):
		return _config.get_value(section, key)
	elif DEFAULTS.has(section) and DEFAULTS[section].has(key):
		return DEFAULTS[section][key]
	return default


func set_setting(section: String, key: String, value) -> void:
	"""Set a setting value (does not apply or save)."""
	_config.set_value(section, key, value)
	_current_preset = QualityPreset.CUSTOM


# Graphics-specific getters for convenience
func get_window_mode() -> int:
	return get_setting("graphics", "window_mode", WindowMode.WINDOWED)

func get_resolution() -> String:
	return get_setting("graphics", "resolution", "1920x1080")

func get_vsync() -> int:
	return get_setting("graphics", "vsync", VSyncMode.ENABLED)

func get_fps_limit() -> int:
	return get_setting("graphics", "fps_limit", 0)

func get_render_scale() -> float:
	return get_setting("graphics", "render_scale", 1.0)

func get_antialiasing() -> int:
	return get_setting("graphics", "antialiasing", AAMode.DISABLED)

func get_shadow_quality() -> int:
	return get_setting("graphics", "shadow_quality", ShadowQuality.MEDIUM)

func get_ssao() -> bool:
	return get_setting("graphics", "ssao", false)

func get_bloom() -> bool:
	return get_setting("graphics", "bloom", true)

func get_current_preset() -> int:
	return _current_preset


# =============================================================================
# Quality Presets
# =============================================================================

func apply_preset(preset_name: String) -> void:
	"""Apply a quality preset (does not save)."""
	if not PRESETS.has(preset_name):
		push_error("SettingsManager: Unknown preset: ", preset_name)
		return
	
	var preset = PRESETS[preset_name]
	for key in preset:
		set_setting("graphics", key, preset[key])
	
	match preset_name:
		"low":
			_current_preset = QualityPreset.LOW
		"medium":
			_current_preset = QualityPreset.MEDIUM
		"high":
			_current_preset = QualityPreset.HIGH
		"ultra":
			_current_preset = QualityPreset.ULTRA


func detect_preset() -> int:
	"""Detect which preset (if any) matches current settings."""
	for preset_name in PRESETS:
		var preset = PRESETS[preset_name]
		var matches = true
		for key in preset:
			if get_setting("graphics", key) != preset[key]:
				matches = false
				break
		if matches:
			match preset_name:
				"low": return QualityPreset.LOW
				"medium": return QualityPreset.MEDIUM
				"high": return QualityPreset.HIGH
				"ultra": return QualityPreset.ULTRA
	return QualityPreset.CUSTOM


# =============================================================================
# Resolution Detection
# =============================================================================

func get_available_resolutions() -> Array[String]:
	"""Get list of available resolutions for current display."""
	var resolutions: Array[String] = []
	var screen_size = DisplayServer.screen_get_size()
	
	# Common resolutions, ordered from smallest to largest
	var common = [
		"1280x720",
		"1366x768",
		"1600x900",
		"1920x1080",
		"2560x1440",
		"3840x2160",
	]
	
	for res in common:
		var parts = res.split("x")
		var w = int(parts[0])
		var h = int(parts[1])
		if w <= screen_size.x and h <= screen_size.y:
			resolutions.append(res)
	
	# Always include current screen resolution if not in list
	var native = "%dx%d" % [screen_size.x, screen_size.y]
	if native not in resolutions:
		resolutions.append(native)
		resolutions.sort()
	
	return resolutions


func parse_resolution(res_string: String) -> Vector2i:
	"""Parse a resolution string like '1920x1080' into Vector2i."""
	var parts = res_string.split("x")
	if parts.size() != 2:
		return Vector2i(1920, 1080)
	return Vector2i(int(parts[0]), int(parts[1]))


# =============================================================================
# Apply Settings to Engine
# =============================================================================

func apply_settings() -> void:
	"""Apply all current settings to the engine."""
	_cache_references()
	
	_apply_window_mode()
	_apply_vsync()
	_apply_fps_limit()
	_apply_render_scale()
	_apply_antialiasing()
	_apply_shadow_quality()
	_apply_ssao()
	_apply_bloom()
	
	settings_applied.emit()
	print("SettingsManager: Settings applied")


func _apply_window_mode() -> void:
	"""Apply window mode and resolution settings."""
	var mode = get_window_mode()
	var resolution = parse_resolution(get_resolution())
	
	match mode:
		WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(resolution)
			# Center window on screen
			var screen_size = DisplayServer.screen_get_size()
			var window_pos = (screen_size - resolution) / 2
			DisplayServer.window_set_position(window_pos)
		
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			# Set to full screen size
			var screen_size = DisplayServer.screen_get_size()
			DisplayServer.window_set_size(screen_size)
			DisplayServer.window_set_position(Vector2i.ZERO)


func _apply_vsync() -> void:
	"""Apply VSync setting."""
	var vsync = get_vsync()
	match vsync:
		VSyncMode.DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VSyncMode.ENABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		VSyncMode.ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)


func _apply_fps_limit() -> void:
	"""Apply FPS limit setting."""
	Engine.max_fps = get_fps_limit()


func _apply_render_scale() -> void:
	"""Apply render scale setting."""
	if _viewport:
		_viewport.scaling_3d_scale = get_render_scale()


func _apply_antialiasing() -> void:
	"""Apply anti-aliasing setting."""
	if not _viewport:
		return
	
	var aa = get_antialiasing()
	
	# Reset all AA settings first
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	
	match aa:
		AAMode.DISABLED:
			pass  # Already reset above
		AAMode.FXAA:
			_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		AAMode.MSAA_2X:
			_viewport.msaa_3d = Viewport.MSAA_2X
		AAMode.MSAA_4X:
			_viewport.msaa_3d = Viewport.MSAA_4X
		AAMode.MSAA_8X:
			_viewport.msaa_3d = Viewport.MSAA_8X
		AAMode.TAA:
			_viewport.use_taa = true


func _apply_shadow_quality() -> void:
	"""Apply shadow quality setting."""
	var quality = get_shadow_quality()
	
	# Apply to sun and moon if available
	var lights = [_sun, _moon]
	for light in lights:
		if not light:
			continue
		
		match quality:
			ShadowQuality.OFF:
				light.shadow_enabled = false
			ShadowQuality.LOW:
				light.shadow_enabled = true
				light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				light.directional_shadow_max_distance = 100.0
			ShadowQuality.MEDIUM:
				light.shadow_enabled = true
				light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
				light.directional_shadow_max_distance = 150.0
			ShadowQuality.HIGH:
				light.shadow_enabled = true
				light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				light.directional_shadow_max_distance = 200.0


func _apply_ssao() -> void:
	"""Apply SSAO setting."""
	if _environment:
		_environment.ssao_enabled = get_ssao()
		if get_ssao():
			_environment.ssao_radius = 1.0
			_environment.ssao_intensity = 2.0


func _apply_bloom() -> void:
	"""Apply bloom/glow setting."""
	if _environment:
		_environment.glow_enabled = get_bloom()
		if get_bloom():
			_environment.glow_intensity = 0.8
			_environment.glow_strength = 1.0
			_environment.glow_bloom = 0.1
			_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
