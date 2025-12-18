extends Node3D
class_name ClickIndicator
## Metin2-style click indicator that appears when clicking on the ground.
## Shows a golden arrow dropping down with an expanding ring effect.

## Golden yellow color scheme (Metin2 style)
const COLOR_GOLD := Color(1.0, 0.85, 0.3, 1.0)
const COLOR_GOLD_EMISSION := Color(1.0, 0.7, 0.2)

## Animation settings
const DROP_HEIGHT: float = 1.5       ## Arrow starts this high above ground
const DROP_DURATION: float = 0.15    ## Time for arrow to drop
const EXPAND_DURATION: float = 0.4   ## Time for ring to expand
const FADE_DURATION: float = 0.3     ## Time to fade out
const FADE_DELAY: float = 0.15       ## Start fading after this delay
const ROTATION_SPEED: float = 8.0    ## Arrow rotation speed (radians/sec)
const TOTAL_DURATION: float = 0.55   ## Total animation duration before deletion

## References to child meshes
@onready var arrow: MeshInstance3D = $Arrow
@onready var ring: MeshInstance3D = $Ring

## Materials (duplicated for independent animation)
var arrow_material: StandardMaterial3D
var ring_material: StandardMaterial3D

## Animation state
var is_animating: bool = false
var elapsed_time: float = 0.0


func _ready() -> void:
	# Duplicate materials so we can animate alpha independently per instance
	if arrow:
		var mat = arrow.get_surface_override_material(0)
		if mat:
			arrow_material = mat.duplicate()
			arrow.set_surface_override_material(0, arrow_material)
	
	if ring:
		var mat = ring.get_surface_override_material(0)
		if mat:
			ring_material = mat.duplicate()
			ring.set_surface_override_material(0, ring_material)
	
	# Start the animation
	_play_animation()


func _process(delta: float) -> void:
	if not is_animating:
		return
	
	elapsed_time += delta
	
	# Rotate the arrow while animating
	if arrow:
		arrow.rotation.y += ROTATION_SPEED * delta


func _play_animation() -> void:
	is_animating = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# === Arrow Animation ===
	# Start above and drop down
	if arrow:
		arrow.position.y = DROP_HEIGHT
		tween.tween_property(arrow, "position:y", 0.05, DROP_DURATION) \
			.set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_QUAD)
	
	# === Ring Animation ===
	# Start small and expand
	if ring:
		ring.scale = Vector3(0.3, 1.0, 0.3)
		tween.tween_property(ring, "scale", Vector3(1.5, 1.0, 1.5), EXPAND_DURATION) \
			.set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_QUAD)
	
	# === Fade Out (both meshes) ===
	if arrow_material:
		tween.tween_property(arrow_material, "albedo_color:a", 0.0, FADE_DURATION) \
			.set_delay(FADE_DELAY)
		tween.tween_property(arrow_material, "emission_energy_multiplier", 0.0, FADE_DURATION) \
			.set_delay(FADE_DELAY)
	
	if ring_material:
		tween.tween_property(ring_material, "albedo_color:a", 0.0, FADE_DURATION) \
			.set_delay(FADE_DELAY)
		tween.tween_property(ring_material, "emission_energy_multiplier", 0.0, FADE_DURATION) \
			.set_delay(FADE_DELAY)
	
	# === Self-destruct after animation completes ===
	tween.chain().tween_callback(_on_animation_finished)


func _on_animation_finished() -> void:
	is_animating = false
	queue_free()
