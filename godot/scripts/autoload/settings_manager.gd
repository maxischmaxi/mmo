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
## COMPOSITOR_SAFE is recommended for Wayland to avoid compositor sync issues
## It disables hardware VSync and uses FPS limiting instead
enum VSyncMode { DISABLED, ENABLED, ADAPTIVE, MAILBOX, COMPOSITOR_SAFE }

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
		"vsync": -1,  # -1 = use platform default (MAILBOX on Linux, ENABLED elsewhere)
		"fps_limit": 0,  # 0 = unlimited
		"render_scale": 1.0,
		"antialiasing": AAMode.DISABLED,
		"shadow_quality": ShadowQuality.MEDIUM,
		"ssao": false,
		"bloom": true,
	}
}


## Get the platform-appropriate default VSync mode
static func get_platform_default_vsync() -> int:
	if OS.get_name() == "Linux":
		# On Wayland, use COMPOSITOR_SAFE to avoid VSync desync issues
		if is_wayland():
			return VSyncMode.COMPOSITOR_SAFE
		# On X11, MAILBOX works well
		return VSyncMode.MAILBOX
	return VSyncMode.ENABLED

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

# =============================================================================
# VSync Recovery System (for Wayland/compositor issues)
# =============================================================================

## Number of consecutive frames with bad frame time
var _bad_frame_count: int = 0
## Cooldown timer to prevent rapid VSync resets
var _vsync_reset_cooldown: float = 0.0
## Whether a VSync reset is currently in progress
var _vsync_reset_in_progress: bool = false

## Frame time threshold - frames taking longer than this are "bad" (100ms = <10 FPS)
const BAD_FRAME_THRESHOLD: float = 0.1
## Number of consecutive bad frames before triggering VSync reset (aggressive)
const BAD_FRAME_COUNT_TRIGGER: int = 3
## Cooldown time between VSync resets to prevent rapid toggling
const VSYNC_RESET_COOLDOWN_TIME: float = 2.0


func _ready() -> void:
	# Load settings on startup
	load_settings()
	
	# Migrate Wayland users to COMPOSITOR_SAFE if they have other VSync modes
	_migrate_wayland_settings()
	
	# Apply window settings IMMEDIATELY to prevent resolution mismatch
	# This must happen before any frames render to avoid black bars
	# _apply_window_mode() only uses DisplayServer calls, no scene dependencies
	_apply_window_mode()
	
	# Apply remaining settings after scene is ready (needs node references)
	await get_tree().process_frame
	await get_tree().process_frame
	_cache_references()
	_apply_remaining_settings()


func _process(delta: float) -> void:
	"""Monitor frame time and trigger VSync recovery if needed."""
	# Update cooldown timer
	if _vsync_reset_cooldown > 0.0:
		_vsync_reset_cooldown -= delta
	
	# Skip monitoring if reset is in progress or on cooldown
	if _vsync_reset_in_progress or _vsync_reset_cooldown > 0.0:
		return
	
	# Skip if using COMPOSITOR_SAFE mode (no VSync to desync)
	if get_vsync() == VSyncMode.COMPOSITOR_SAFE:
		_bad_frame_count = 0
		return
	
	# Check for bad frame time
	if delta > BAD_FRAME_THRESHOLD:
		_bad_frame_count += 1
		if _bad_frame_count >= BAD_FRAME_COUNT_TRIGGER:
			print("SettingsManager: Detected %d consecutive slow frames (%.1f ms avg), triggering VSync recovery..." % [
				_bad_frame_count, delta * 1000.0
			])
			_trigger_vsync_recovery()
	else:
		# Reset counter on good frame
		_bad_frame_count = 0


func _input(event: InputEvent) -> void:
	"""Handle manual VSync reset keybind."""
	if event.is_action_pressed("vsync_reset"):
		print("SettingsManager: Manual VSync reset triggered (F11)")
		_trigger_vsync_recovery()


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
# Wayland/Compositor Detection and Migration
# =============================================================================

static func is_wayland() -> bool:
	"""Check if running on Wayland display server."""
	if OS.get_name() != "Linux":
		return false
	var session_type = OS.get_environment("XDG_SESSION_TYPE")
	return session_type.to_lower() == "wayland"


func _migrate_wayland_settings() -> void:
	"""Migrate Wayland users to COMPOSITOR_SAFE mode if using problematic VSync modes."""
	if not is_wayland():
		return
	
	var current_vsync = get_setting("graphics", "vsync", -1)
	
	# If using default (-1) or any hardware VSync mode, migrate to COMPOSITOR_SAFE
	if current_vsync == -1 or (current_vsync >= VSyncMode.DISABLED and current_vsync <= VSyncMode.MAILBOX):
		# Only migrate if not already on COMPOSITOR_SAFE
		if current_vsync != VSyncMode.COMPOSITOR_SAFE:
			print("SettingsManager: Wayland detected - migrating VSync to COMPOSITOR_SAFE mode")
			print("SettingsManager: This prevents frame timing issues when moving windows")
			set_setting("graphics", "vsync", VSyncMode.COMPOSITOR_SAFE)
			save_settings()


static func get_monitor_refresh_rate() -> int:
	"""Get the current monitor's refresh rate, with fallback to 60Hz."""
	var refresh_rate = DisplayServer.screen_get_refresh_rate()
	if refresh_rate <= 0:
		return 60  # Fallback
	return int(refresh_rate)


# =============================================================================
# VSync Recovery System
# =============================================================================

func _trigger_vsync_recovery() -> void:
	"""Trigger an async VSync recovery by toggling VSync off and back on."""
	if _vsync_reset_in_progress:
		return
	
	_vsync_reset_in_progress = true
	_vsync_reset_cooldown = VSYNC_RESET_COOLDOWN_TIME
	_bad_frame_count = 0
	
	# Run the async recovery
	_perform_vsync_recovery()


func _perform_vsync_recovery() -> void:
	"""Perform the actual VSync reset (async)."""
	var original_vsync = get_vsync()
	
	# Step 1: Disable VSync
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("SettingsManager: VSync disabled for recovery...")
	
	# Step 2: Wait a few frames for GPU to stabilize
	if is_inside_tree():
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
	
	# Step 3: Re-apply original VSync setting
	await _apply_vsync()
	
	print("SettingsManager: VSync recovery complete, restored to mode %d" % original_vsync)
	_vsync_reset_in_progress = false


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
	var vsync = get_setting("graphics", "vsync", -1)
	if vsync == -1:
		return get_platform_default_vsync()
	return vsync

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
	
	await _apply_remaining_settings()


func _apply_remaining_settings() -> void:
	"""Apply settings that depend on scene nodes being ready."""
	# VSync is async to allow frame delays for GPU/compositor sync
	await _apply_vsync()
	
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
	"""Apply VSync setting with proper sync handling.
	
	Includes frame delay and window refresh to prevent GPU/compositor
	sync issues, especially on Linux with Vulkan and desktop compositors.
	"""
	var vsync = get_vsync()
	
	# Apply the VSync mode
	match vsync:
		VSyncMode.DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			# Restore default FPS limit when not using COMPOSITOR_SAFE
			Engine.max_fps = get_fps_limit()
		VSyncMode.ENABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			Engine.max_fps = get_fps_limit()
		VSyncMode.ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
			Engine.max_fps = get_fps_limit()
		VSyncMode.MAILBOX:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
			Engine.max_fps = get_fps_limit()
		VSyncMode.COMPOSITOR_SAFE:
			# Disable hardware VSync and use FPS limiting instead
			# This avoids VSync desync issues on Wayland/compositors
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			var target_fps = get_monitor_refresh_rate()
			Engine.max_fps = target_fps
			print("SettingsManager: COMPOSITOR_SAFE mode - VSync disabled, FPS capped to %d" % target_fps)
	
	# Wait a couple frames to let GPU/compositor sync properly
	# This helps prevent the 1 FPS issue when switching VSync modes at runtime
	if is_inside_tree():
		await get_tree().process_frame
		await get_tree().process_frame
		
		# Force window refresh to help with sync state
		var current_mode = DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(current_mode)


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
