extends Control
class_name SettingsDialog
## Settings dialog with tabs for Graphics, Audio, Controls, and Gameplay.
## Changes are staged until Apply is clicked.

signal dialog_closed

## Staged settings (not yet applied)
var _staged_settings: Dictionary = {}

## Track if settings have been modified
var _settings_modified: bool = false

## UI References - Main
@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var close_button: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var tab_container: TabContainer = $CenterContainer/Panel/VBox/TabContainer

## UI References - Bottom buttons
@onready var reset_button: Button = $CenterContainer/Panel/VBox/BottomButtons/ResetButton
@onready var cancel_button: Button = $CenterContainer/Panel/VBox/BottomButtons/CancelButton
@onready var apply_button: Button = $CenterContainer/Panel/VBox/BottomButtons/ApplyButton

## UI References - Graphics Tab
@onready var preset_low_btn: Button = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/PresetContainer/LowButton
@onready var preset_medium_btn: Button = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/PresetContainer/MediumButton
@onready var preset_high_btn: Button = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/PresetContainer/HighButton
@onready var preset_ultra_btn: Button = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/PresetContainer/UltraButton

@onready var window_mode_option: OptionButton = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/DisplaySection/WindowModeRow/WindowModeOption
@onready var resolution_option: OptionButton = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/DisplaySection/ResolutionRow/ResolutionOption
@onready var vsync_option: OptionButton = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/DisplaySection/VSyncRow/VSyncOption
@onready var fps_limit_option: OptionButton = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/DisplaySection/FPSLimitRow/FPSLimitOption

@onready var render_scale_slider: HSlider = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/QualitySection/RenderScaleRow/RenderScaleSlider
@onready var render_scale_label: Label = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/QualitySection/RenderScaleRow/RenderScaleValue
@onready var aa_option: OptionButton = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/QualitySection/AARow/AAOption
@onready var shadow_option: OptionButton = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/QualitySection/ShadowRow/ShadowOption

@onready var ssao_check: CheckBox = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/EffectsSection/SSAORow/SSAOCheck
@onready var bloom_check: CheckBox = $CenterContainer/Panel/VBox/TabContainer/Graphics/VBox/EffectsSection/BloomRow/BloomCheck


func _ready() -> void:
	# Start hidden
	visible = false
	
	# Register with UIManager
	UIManager.register_dialog(self)
	
	# Connect main buttons
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if reset_button:
		reset_button.pressed.connect(_on_reset_pressed)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)
	if apply_button:
		apply_button.pressed.connect(_on_apply_pressed)
	
	# Setup controls after a frame
	await get_tree().process_frame
	_setup_graphics_controls()
	_load_current_settings()


func _setup_graphics_controls() -> void:
	"""Setup all graphics control options and connect signals."""
	# Preset buttons
	if preset_low_btn:
		preset_low_btn.pressed.connect(_on_preset_low)
	if preset_medium_btn:
		preset_medium_btn.pressed.connect(_on_preset_medium)
	if preset_high_btn:
		preset_high_btn.pressed.connect(_on_preset_high)
	if preset_ultra_btn:
		preset_ultra_btn.pressed.connect(_on_preset_ultra)
	
	# Window Mode
	if window_mode_option:
		window_mode_option.clear()
		window_mode_option.add_item("Windowed", 0)
		window_mode_option.add_item("Fullscreen", 1)
		window_mode_option.add_item("Borderless Fullscreen", 2)
		window_mode_option.item_selected.connect(_on_window_mode_changed)
	
	# Resolution
	if resolution_option:
		_populate_resolutions()
		resolution_option.item_selected.connect(_on_resolution_changed)
	
	# VSync
	if vsync_option:
		vsync_option.clear()
		vsync_option.add_item("Disabled", 0)
		vsync_option.add_item("Enabled", 1)
		vsync_option.add_item("Adaptive", 2)
		vsync_option.add_item("Mailbox", 3)
		# Add Compositor Safe option with recommendation for Wayland users
		var compositor_label = "Compositor Safe"
		if SettingsManager.is_wayland():
			compositor_label = "Compositor Safe (Recommended)"
		vsync_option.add_item(compositor_label, 4)
		vsync_option.item_selected.connect(_on_vsync_changed)
	
	# FPS Limit
	if fps_limit_option:
		fps_limit_option.clear()
		fps_limit_option.add_item("Unlimited", 0)
		fps_limit_option.add_item("30 FPS", 30)
		fps_limit_option.add_item("60 FPS", 60)
		fps_limit_option.add_item("120 FPS", 120)
		fps_limit_option.add_item("144 FPS", 144)
		fps_limit_option.add_item("240 FPS", 240)
		fps_limit_option.item_selected.connect(_on_fps_limit_changed)
	
	# Render Scale
	if render_scale_slider:
		render_scale_slider.min_value = 0.5
		render_scale_slider.max_value = 1.0
		render_scale_slider.step = 0.05
		render_scale_slider.value_changed.connect(_on_render_scale_changed)
	
	# Anti-Aliasing
	if aa_option:
		aa_option.clear()
		aa_option.add_item("Disabled", 0)
		aa_option.add_item("FXAA", 1)
		aa_option.add_item("MSAA 2x", 2)
		aa_option.add_item("MSAA 4x", 3)
		aa_option.add_item("MSAA 8x", 4)
		aa_option.add_item("TAA", 5)
		aa_option.item_selected.connect(_on_aa_changed)
	
	# Shadow Quality
	if shadow_option:
		shadow_option.clear()
		shadow_option.add_item("Off", 0)
		shadow_option.add_item("Low", 1)
		shadow_option.add_item("Medium", 2)
		shadow_option.add_item("High", 3)
		shadow_option.item_selected.connect(_on_shadow_changed)
	
	# SSAO
	if ssao_check:
		ssao_check.toggled.connect(_on_ssao_toggled)
	
	# Bloom
	if bloom_check:
		bloom_check.toggled.connect(_on_bloom_toggled)


func _populate_resolutions() -> void:
	"""Populate resolution dropdown with available resolutions."""
	if not resolution_option:
		return
	
	resolution_option.clear()
	var resolutions = SettingsManager.get_available_resolutions()
	for res in resolutions:
		resolution_option.add_item(res)


func _load_current_settings() -> void:
	"""Load current settings from SettingsManager into UI controls."""
	# Window Mode
	if window_mode_option:
		window_mode_option.select(SettingsManager.get_window_mode())
	
	# Resolution
	if resolution_option:
		var current_res = SettingsManager.get_resolution()
		for i in range(resolution_option.item_count):
			if resolution_option.get_item_text(i) == current_res:
				resolution_option.select(i)
				break
	
	# VSync
	if vsync_option:
		vsync_option.select(SettingsManager.get_vsync())
	
	# FPS Limit
	if fps_limit_option:
		var fps = SettingsManager.get_fps_limit()
		for i in range(fps_limit_option.item_count):
			if fps_limit_option.get_item_id(i) == fps:
				fps_limit_option.select(i)
				break
	
	# Render Scale
	if render_scale_slider:
		render_scale_slider.value = SettingsManager.get_render_scale()
		_update_render_scale_label(render_scale_slider.value)
	
	# Anti-Aliasing
	if aa_option:
		aa_option.select(SettingsManager.get_antialiasing())
	
	# Shadow Quality
	if shadow_option:
		shadow_option.select(SettingsManager.get_shadow_quality())
	
	# SSAO
	if ssao_check:
		ssao_check.button_pressed = SettingsManager.get_ssao()
	
	# Bloom
	if bloom_check:
		bloom_check.button_pressed = SettingsManager.get_bloom()
	
	# Clear staged settings and modified flag
	_staged_settings.clear()
	_settings_modified = false
	_update_apply_button()
	_update_preset_highlight()
	_update_resolution_visibility()


func _update_render_scale_label(value: float) -> void:
	"""Update the render scale percentage label."""
	if render_scale_label:
		render_scale_label.text = "%d%%" % int(value * 100)


func _update_apply_button() -> void:
	"""Update apply button state based on whether settings changed."""
	if apply_button:
		apply_button.disabled = not _settings_modified


func _update_preset_highlight() -> void:
	"""Update preset button highlighting based on current settings."""
	var preset = SettingsManager.detect_preset()
	
	var buttons = [preset_low_btn, preset_medium_btn, preset_high_btn, preset_ultra_btn]
	var presets = [
		SettingsManager.QualityPreset.LOW,
		SettingsManager.QualityPreset.MEDIUM,
		SettingsManager.QualityPreset.HIGH,
		SettingsManager.QualityPreset.ULTRA
	]
	
	for i in range(buttons.size()):
		if buttons[i]:
			if presets[i] == preset:
				buttons[i].add_theme_color_override("font_color", Color(1, 0.9, 0.5))
			else:
				buttons[i].remove_theme_color_override("font_color")


func _update_resolution_visibility() -> void:
	"""Show/hide resolution option based on window mode."""
	if not resolution_option:
		return
	
	var mode = window_mode_option.selected if window_mode_option else 0
	# Resolution only matters in windowed mode (not fullscreen or borderless)
	resolution_option.get_parent().visible = (mode == 0)


func _mark_modified() -> void:
	"""Mark settings as modified."""
	_settings_modified = true
	_update_apply_button()


# =============================================================================
# Dialog Visibility
# =============================================================================

func show_dialog() -> void:
	"""Show the settings dialog."""
	_load_current_settings()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close_dialog() -> void:
	"""Close the settings dialog."""
	visible = false
	dialog_closed.emit()


# =============================================================================
# Main Button Handlers
# =============================================================================

func _on_close_pressed() -> void:
	"""Close button pressed - same as cancel."""
	_on_cancel_pressed()


func _on_reset_pressed() -> void:
	"""Reset to defaults button pressed."""
	SettingsManager.reset_to_defaults()
	_load_current_settings()
	_mark_modified()


func _on_cancel_pressed() -> void:
	"""Cancel button pressed - discard changes."""
	# Reload current settings to discard staged changes
	_load_current_settings()
	close_dialog()


func _on_apply_pressed() -> void:
	"""Apply button pressed - save and apply settings."""
	# Apply staged settings to SettingsManager
	for key in _staged_settings:
		var parts = key.split("/")
		if parts.size() == 2:
			SettingsManager.set_setting(parts[0], parts[1], _staged_settings[key])
	
	# Save and apply
	SettingsManager.save_settings()
	SettingsManager.apply_settings()
	
	# Clear modified state
	_staged_settings.clear()
	_settings_modified = false
	_update_apply_button()


# =============================================================================
# Preset Handlers
# =============================================================================

func _on_preset_low() -> void:
	_apply_preset("low")

func _on_preset_medium() -> void:
	_apply_preset("medium")

func _on_preset_high() -> void:
	_apply_preset("high")

func _on_preset_ultra() -> void:
	_apply_preset("ultra")


func _apply_preset(preset_name: String) -> void:
	"""Apply a quality preset to the UI controls."""
	SettingsManager.apply_preset(preset_name)
	
	# Reload UI to reflect preset
	if render_scale_slider:
		render_scale_slider.value = SettingsManager.get_render_scale()
		_update_render_scale_label(render_scale_slider.value)
	if aa_option:
		aa_option.select(SettingsManager.get_antialiasing())
	if shadow_option:
		shadow_option.select(SettingsManager.get_shadow_quality())
	if ssao_check:
		ssao_check.button_pressed = SettingsManager.get_ssao()
	if bloom_check:
		bloom_check.button_pressed = SettingsManager.get_bloom()
	
	_mark_modified()
	_update_preset_highlight()


# =============================================================================
# Graphics Control Handlers
# =============================================================================

func _on_window_mode_changed(index: int) -> void:
	_staged_settings["graphics/window_mode"] = index
	SettingsManager.set_setting("graphics", "window_mode", index)
	_mark_modified()
	_update_resolution_visibility()


func _on_resolution_changed(index: int) -> void:
	var res = resolution_option.get_item_text(index)
	_staged_settings["graphics/resolution"] = res
	SettingsManager.set_setting("graphics", "resolution", res)
	_mark_modified()


func _on_vsync_changed(index: int) -> void:
	_staged_settings["graphics/vsync"] = index
	SettingsManager.set_setting("graphics", "vsync", index)
	_mark_modified()


func _on_fps_limit_changed(index: int) -> void:
	var fps = fps_limit_option.get_item_id(index)
	_staged_settings["graphics/fps_limit"] = fps
	SettingsManager.set_setting("graphics", "fps_limit", fps)
	_mark_modified()


func _on_render_scale_changed(value: float) -> void:
	_update_render_scale_label(value)
	_staged_settings["graphics/render_scale"] = value
	SettingsManager.set_setting("graphics", "render_scale", value)
	_mark_modified()
	_update_preset_highlight()


func _on_aa_changed(index: int) -> void:
	_staged_settings["graphics/antialiasing"] = index
	SettingsManager.set_setting("graphics", "antialiasing", index)
	_mark_modified()
	_update_preset_highlight()


func _on_shadow_changed(index: int) -> void:
	_staged_settings["graphics/shadow_quality"] = index
	SettingsManager.set_setting("graphics", "shadow_quality", index)
	_mark_modified()
	_update_preset_highlight()


func _on_ssao_toggled(pressed: bool) -> void:
	_staged_settings["graphics/ssao"] = pressed
	SettingsManager.set_setting("graphics", "ssao", pressed)
	_mark_modified()
	_update_preset_highlight()


func _on_bloom_toggled(pressed: bool) -> void:
	_staged_settings["graphics/bloom"] = pressed
	SettingsManager.set_setting("graphics", "bloom", pressed)
	_mark_modified()
	_update_preset_highlight()
