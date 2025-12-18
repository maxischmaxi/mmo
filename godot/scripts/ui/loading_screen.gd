extends ColorRect
## Loading Screen - simple fade to black overlay for zone transitions.

## Signal emitted when fade animation finishes
signal fade_finished

## Fade duration in seconds
@export var fade_duration: float = 0.5

## Tween for animation
var tween: Tween = null


func _ready() -> void:
	# Start fully transparent and hidden
	modulate.a = 0.0
	visible = false
	
	# Make sure we're on top of everything
	z_index = 100
	
	# Set to full screen black
	color = Color.BLACK
	set_anchors_preset(Control.PRESET_FULL_RECT)


func fade_in() -> void:
	"""Fade to black (show loading screen)."""
	visible = true
	
	# Cancel any existing tween
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	tween.tween_callback(_emit_fade_finished)


func fade_out() -> void:
	"""Fade from black (hide loading screen)."""
	# Cancel any existing tween
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(_on_fade_out_complete)


func _emit_fade_finished() -> void:
	fade_finished.emit()


func _on_fade_out_complete() -> void:
	visible = false
	fade_finished.emit()


## Check if currently fading
func is_fading() -> bool:
	return tween != null and tween.is_valid() and tween.is_running()
