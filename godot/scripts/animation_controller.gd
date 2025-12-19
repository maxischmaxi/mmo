extends Node3D
## Controls character animations based on movement state.
## Attach this to a Node3D that contains the animated character model.
## Supports runtime loading of Mixamo animations from separate FBX files.

## Signal emitted when attack animation finishes
signal attack_finished

## Signal emitted when attack animation reaches the hit point (damage should be applied)
signal attack_hit

## Signal emitted when death animation finishes
signal death_animation_finished

## Signal emitted when rallying animation finishes
signal rallying_finished

## Path to the AnimationPlayer node within the character model
@export var animation_player_path: NodePath = ""

## Reference to the AnimationPlayer
@onready var animation_player: AnimationPlayer = get_node_or_null(animation_player_path)

## Currently playing animation
var current_animation: String = ""

## Whether this controller should auto-detect animation from parent velocity
## Set to false for remote players that receive animation state from server
@export var auto_detect: bool = true

## Animation library name for loaded animations
const MIXAMO_LIBRARY := "mixamo"

## Whether currently playing attack animation (blocks movement animations)
var is_attacking: bool = false

## Whether the character is dead (blocks all other animations)
var is_dead: bool = false

## Whether currently playing rallying animation
var is_rallying: bool = false

## Timer for attack hit point
var attack_hit_timer: SceneTreeTimer = null

## Whether animations have been loaded
var animations_loaded: bool = false

## Base attack animation duration (will be updated from actual animation)
var attack_animation_duration: float = 1.0

## Attack hit point (percentage through animation when damage should be dealt)
## 0.5 = 50% through animation, when sword typically connects
const ATTACK_HIT_POINT: float = 0.5

# Speed thresholds
const RUN_SPEED := 0.5  # Any movement above this plays run animation
const SPRINT_SPEED := 6.0  # Sprint animation threshold (speed * sprint_multiplier = 5.0 * 1.5 = 7.5)

# Jump/Landing transition settings
const JUMP_BLEND_IN: float = 0.1  # Quick transition into jump (should be snappy)
const LANDING_BLEND_OUT: float = 0.3  # Longer blend for smooth landing transition

## Whether we were in the air last frame (for detecting landing)
var was_in_air: bool = false

## Whether we're currently in the landing transition
var is_landing: bool = false

## Landing transition timer
var landing_blend_timer: float = 0.0

# Animation name constants - these match the Mixamo FBX file names
const ANIM_IDLE := "Neutral Idle"
const ANIM_JOG := "Jog Forward"
const ANIM_JOG_BWD := "Jog Backward"
const ANIM_SPRINT := "Sprint"
const ANIM_JUMP := "Jump"
const ANIM_ATTACK := "Stable Sword Outward Slash"
const ANIM_HIT := "Stomach Hit"
const ANIM_DEATH := "Standing React Death Right"
const ANIM_RALLYING := "Rallying"
const ANIM_SPELL := "Magic Spell Casting"
const ANIM_SHEATHE := "Sheathing Sword"

# Animation FBX file paths
const ANIMATION_FILES := {
	ANIM_IDLE: "res://assets/animations/Neutral Idle.fbx",
	ANIM_JOG: "res://assets/animations/Jog Forward.fbx",
	ANIM_JOG_BWD: "res://assets/animations/Jog Backward.fbx",
	ANIM_SPRINT: "res://assets/animations/Sprint.fbx",
	ANIM_JUMP: "res://assets/animations/Jump.fbx",
	ANIM_ATTACK: "res://assets/animations/Stable Sword Outward Slash.fbx",
	ANIM_HIT: "res://assets/animations/Stomach Hit.fbx",
	ANIM_DEATH: "res://assets/animations/Standing React Death Right.fbx",
	ANIM_RALLYING: "res://assets/animations/Rallying.fbx",
	ANIM_SPELL: "res://assets/animations/Magic Spell Casting.fbx",
	ANIM_SHEATHE: "res://assets/animations/Sheathing Sword.fbx",
}


func _ready() -> void:
	# Try to find AnimationPlayer if path doesn't work
	if not animation_player:
		animation_player = _find_animation_player(get_parent())
	
	if animation_player:
		# Load all Mixamo animations
		_load_mixamo_animations()
		
		# Connect to animation finished signal
		if not animation_player.animation_finished.is_connected(_on_animation_finished):
			animation_player.animation_finished.connect(_on_animation_finished)
		
		# Start with idle animation
		play_animation(ANIM_IDLE)
	else:
		push_warning("AnimationController: Could not find AnimationPlayer")


func _process(_delta: float) -> void:
	if not auto_detect:
		return
	
	# Don't update movement animation while dead
	if is_dead:
		return
	
	# Don't update movement animation while attacking
	if is_attacking:
		return
	
	# Don't update movement animation while rallying
	if is_rallying:
		return
	
	# Find the CharacterBody3D parent (Player or RemotePlayer)
	var body := _find_character_body()
	if body:
		update_animation_from_velocity(body)


## Load all Mixamo animations from FBX files into the AnimationPlayer
func _load_mixamo_animations() -> void:
	if animations_loaded:
		return
	
	if not animation_player:
		push_error("AnimationController: Cannot load animations - no AnimationPlayer")
		return
	
	# Create a new AnimationLibrary for Mixamo animations
	var library := AnimationLibrary.new()
	
	var loaded_count := 0
	for anim_name in ANIMATION_FILES:
		var fbx_path: String = ANIMATION_FILES[anim_name]
		var animation := _load_animation_from_fbx(fbx_path, anim_name)
		if animation:
			var err := library.add_animation(anim_name, animation)
			if err == OK:
				loaded_count += 1
			else:
				push_warning("AnimationController: Failed to add animation '%s' to library" % anim_name)
	
	# Add the library to the AnimationPlayer
	if animation_player.has_animation_library(MIXAMO_LIBRARY):
		animation_player.remove_animation_library(MIXAMO_LIBRARY)
	
	var err := animation_player.add_animation_library(MIXAMO_LIBRARY, library)
	if err == OK:
		animations_loaded = true
		print("AnimationController: Loaded %d/%d Mixamo animations" % [loaded_count, ANIMATION_FILES.size()])
		
		# Update attack animation duration from actual animation
		var attack_anim_name := MIXAMO_LIBRARY + "/" + ANIM_ATTACK
		if animation_player.has_animation(attack_anim_name):
			var attack_anim := animation_player.get_animation(attack_anim_name)
			if attack_anim:
				attack_animation_duration = attack_anim.length
				print("AnimationController: Attack animation duration: %.2fs" % attack_animation_duration)
	else:
		push_error("AnimationController: Failed to add Mixamo library to AnimationPlayer")


## Animations that should loop continuously
const LOOPING_ANIMATIONS := [
	ANIM_IDLE,
	ANIM_JOG,
	ANIM_JOG_BWD,
	ANIM_SPRINT,
	# Note: Jump is NOT looping - it plays once and holds the last frame
	# This ensures a consistent pose for landing transitions
]

## Animations that should have root motion removed
## This prevents the animation from moving the character, letting physics handle movement
const ANIMATIONS_WITHOUT_ROOT_MOTION := [
	ANIM_JUMP,  # Physics handles the jump height, animation only handles the pose
]


## Load an animation from an FBX file
func _load_animation_from_fbx(fbx_path: String, anim_name: String) -> Animation:
	if not ResourceLoader.exists(fbx_path):
		push_warning("AnimationController: FBX file not found: %s" % fbx_path)
		return null
	
	# Load the FBX as a PackedScene
	var scene := load(fbx_path) as PackedScene
	if not scene:
		push_warning("AnimationController: Failed to load FBX: %s" % fbx_path)
		return null
	
	# Instantiate temporarily to extract animation
	var instance := scene.instantiate()
	if not instance:
		push_warning("AnimationController: Failed to instantiate FBX: %s" % fbx_path)
		return null
	
	# Find the AnimationPlayer in the FBX scene
	var fbx_anim_player := _find_animation_player(instance)
	if not fbx_anim_player:
		push_warning("AnimationController: No AnimationPlayer in FBX: %s" % fbx_path)
		instance.queue_free()
		return null
	
	# Get the animation (Mixamo exports typically name it "mixamo.com" or based on the animation)
	var anim_list := fbx_anim_player.get_animation_list()
	if anim_list.is_empty():
		push_warning("AnimationController: No animations in FBX: %s" % fbx_path)
		instance.queue_free()
		return null
	
	# Get the first animation (there should only be one per Mixamo FBX)
	var source_anim_name: String = anim_list[0]
	var source_animation := fbx_anim_player.get_animation(source_anim_name)
	if not source_animation:
		push_warning("AnimationController: Failed to get animation from FBX: %s" % fbx_path)
		instance.queue_free()
		return null
	
	# Duplicate the animation so we can modify it
	var animation := source_animation.duplicate() as Animation
	
	# Remove root motion for specific animations (like jump)
	# This prevents the animation from moving the character vertically,
	# allowing physics to control the actual jump height
	if anim_name in ANIMATIONS_WITHOUT_ROOT_MOTION:
		_remove_root_motion(animation)
	
	# Set loop mode based on animation type
	if anim_name in LOOPING_ANIMATIONS:
		animation.loop_mode = Animation.LOOP_LINEAR
	else:
		animation.loop_mode = Animation.LOOP_NONE
	
	# Clean up the temporary instance
	instance.queue_free()
	
	return animation


## Remove vertical root motion from an animation
## This prevents the animation from moving the character up/down,
## allowing physics to control vertical movement (e.g., for jumps)
func _remove_root_motion(animation: Animation) -> void:
	for track_idx in range(animation.get_track_count()):
		var track_path := animation.track_get_path(track_idx)
		var track_type := animation.track_get_type(track_idx)
		
		# Look for position tracks on the Hips bone (Mixamo root bone)
		if track_type == Animation.TYPE_POSITION_3D:
			var path_str := str(track_path)
			if "Hips" in path_str:
				var key_count := animation.track_get_key_count(track_idx)
				if key_count == 0:
					continue
				
				# Get the base Y position from first keyframe
				var first_pos: Vector3 = animation.track_get_key_value(track_idx, 0)
				var base_y := first_pos.y
				
				# Flatten all Y values to the base position
				# This removes vertical movement while keeping horizontal adjustments
				for key_idx in range(key_count):
					var pos: Vector3 = animation.track_get_key_value(track_idx, key_idx)
					pos.y = base_y
					animation.track_set_key_value(track_idx, key_idx, pos)
				
				return  # Found and processed the root bone


## Find the CharacterBody3D in the parent hierarchy
func _find_character_body() -> CharacterBody3D:
	var node = get_parent()
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


## Recursively search for AnimationPlayer in children
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null


## Get full animation name with library prefix
func _get_full_anim_name(base_name: String) -> String:
	return MIXAMO_LIBRARY + "/" + base_name


## Update animation based on CharacterBody3D velocity and state
func update_animation_from_velocity(body: CharacterBody3D) -> void:
	# Don't override attack animation
	if is_attacking:
		return
	
	var velocity := body.velocity
	var on_floor := body.is_on_floor()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var vertical_velocity := velocity.y
	
	# Detect landing (transitioning from air to ground)
	var just_landed := was_in_air and on_floor
	was_in_air = not on_floor
	
	var new_anim: String
	var blend_time: float = 0.1  # Default blend time
	
	if not on_floor:
		# In the air - use jump animation
		new_anim = ANIM_JUMP
		
		# Blend time depends on whether jumping up or already in air
		if current_animation != _get_full_anim_name(ANIM_JUMP):
			# Just started jumping - use quick blend
			blend_time = JUMP_BLEND_IN
		else:
			# Already in jump animation - no blend needed
			blend_time = 0.0
			
	elif just_landed:
		# Just landed - use longer blend for smooth transition
		is_landing = true
		landing_blend_timer = LANDING_BLEND_OUT
		blend_time = LANDING_BLEND_OUT
		
		# Choose landing animation based on movement
		if horizontal_speed > SPRINT_SPEED:
			new_anim = ANIM_SPRINT
		elif horizontal_speed > RUN_SPEED:
			new_anim = ANIM_JOG
		else:
			new_anim = ANIM_IDLE
	else:
		# Normal ground movement
		if horizontal_speed > SPRINT_SPEED:
			new_anim = ANIM_SPRINT
		elif horizontal_speed > RUN_SPEED:
			new_anim = ANIM_JOG
		else:
			new_anim = ANIM_IDLE
		
		# If we're still in landing transition, maintain the longer blend
		if is_landing:
			blend_time = LANDING_BLEND_OUT
	
	play_animation(new_anim, blend_time)
	
	# Update landing state
	if is_landing:
		landing_blend_timer -= get_process_delta_time()
		if landing_blend_timer <= 0:
			is_landing = false





## Play an animation by name with crossfade
func play_animation(base_anim_name: String, crossfade: float = 0.1) -> void:
	var full_name := _get_full_anim_name(base_anim_name)
	
	if full_name == current_animation:
		return
	
	if not animation_player:
		return
	
	if animation_player.has_animation(full_name):
		animation_player.play(full_name, crossfade)
		current_animation = full_name
	else:
		# Try without library prefix as fallback (for built-in animations)
		if animation_player.has_animation(base_anim_name):
			animation_player.play(base_anim_name, crossfade)
			current_animation = base_anim_name
		else:
			push_warning("AnimationController: Animation '%s' not found (tried '%s')" % [base_anim_name, full_name])


## Crossfade duration for transitioning into attack animation (seconds)
## This provides a smooth blend from idle/run into the attack
const ATTACK_BLEND_IN: float = 0.15

## Crossfade duration for transitioning out of attack animation (seconds)
## This provides a smooth blend from attack back to idle/run
const ATTACK_BLEND_OUT: float = 0.2

## Play attack animation with speed scaling based on attack_speed
## attack_speed: multiplier (1.0 = normal, 2.0 = twice as fast)
## Returns the actual duration of the attack animation
func play_attack_animation(attack_speed: float = 1.0) -> float:
	if is_attacking:
		return 0.0
	
	if not animation_player:
		return 0.0
	
	is_attacking = true
	
	# Calculate animation speed scale
	var speed_scale := attack_speed
	animation_player.speed_scale = speed_scale
	
	# Play attack animation with smooth blend-in transition
	var full_name := _get_full_anim_name(ANIM_ATTACK)
	if animation_player.has_animation(full_name):
		animation_player.play(full_name, ATTACK_BLEND_IN)
		current_animation = full_name
	elif animation_player.has_animation(ANIM_ATTACK):
		animation_player.play(ANIM_ATTACK, ATTACK_BLEND_IN)
		current_animation = ANIM_ATTACK
	else:
		push_warning("AnimationController: Attack animation not found")
		is_attacking = false
		animation_player.speed_scale = 1.0
		return 0.0
	
	# Calculate actual animation duration
	var actual_duration := attack_animation_duration / attack_speed
	
	# Create timer for hit point (when damage should be dealt)
	var hit_delay := actual_duration * ATTACK_HIT_POINT
	attack_hit_timer = get_tree().create_timer(hit_delay)
	attack_hit_timer.timeout.connect(_on_attack_hit_timer)
	
	# Return actual animation duration
	return actual_duration


## Called when attack hit timer fires (at the hit point in animation)
func _on_attack_hit_timer() -> void:
	if is_attacking:
		attack_hit.emit()
	attack_hit_timer = null


## Cancel the current attack animation (if allowed)
func cancel_attack() -> void:
	if not is_attacking:
		return
	
	is_attacking = false
	animation_player.speed_scale = 1.0
	
	# Cancel hit timer to prevent damage from cancelled attack
	if attack_hit_timer and attack_hit_timer.time_left > 0:
		# Disconnect the timer signal to prevent it from firing
		if attack_hit_timer.timeout.is_connected(_on_attack_hit_timer):
			attack_hit_timer.timeout.disconnect(_on_attack_hit_timer)
	attack_hit_timer = null
	
	# Return to idle with smooth blend-out transition
	play_animation(ANIM_IDLE, ATTACK_BLEND_OUT)
	
	emit_signal("attack_finished")


## Play death animation (blocks all other animations until reset)
func play_death_animation() -> void:
	if is_dead:
		return
	
	is_dead = true
	is_attacking = false
	is_rallying = false
	animation_player.speed_scale = 1.0
	
	var full_name := _get_full_anim_name(ANIM_DEATH)
	if animation_player.has_animation(full_name):
		animation_player.play(full_name, 0.1)
		current_animation = full_name
	elif animation_player.has_animation(ANIM_DEATH):
		animation_player.play(ANIM_DEATH, 0.1)
		current_animation = ANIM_DEATH
	else:
		push_warning("AnimationController: Death animation not found")


## Reset from death state (called when respawning)
func reset_from_death() -> void:
	is_dead = false
	is_attacking = false
	is_rallying = false
	animation_player.speed_scale = 1.0
	play_animation(ANIM_IDLE, 0.1)


## Play rallying animation (for character select screen)
func play_rallying_animation() -> void:
	if is_rallying:
		return
	
	is_rallying = true
	is_attacking = false
	animation_player.speed_scale = 1.0
	
	var full_name := _get_full_anim_name(ANIM_RALLYING)
	if animation_player.has_animation(full_name):
		animation_player.play(full_name, 0.1)
		current_animation = full_name
	elif animation_player.has_animation(ANIM_RALLYING):
		animation_player.play(ANIM_RALLYING, 0.1)
		current_animation = ANIM_RALLYING
	else:
		push_warning("AnimationController: Rallying animation not found")
		is_rallying = false
		# Fall back to idle
		play_animation(ANIM_IDLE)


## Called when any animation finishes
func _on_animation_finished(anim_name: String) -> void:
	# Check if it was the attack animation
	if anim_name.ends_with(ANIM_ATTACK) or anim_name == ANIM_ATTACK:
		is_attacking = false
		animation_player.speed_scale = 1.0
		
		# Smoothly transition back to idle (or movement will override in _process)
		play_animation(ANIM_IDLE, ATTACK_BLEND_OUT)
		
		emit_signal("attack_finished")
	
	# Check if it was the death animation
	if anim_name.ends_with(ANIM_DEATH) or anim_name == ANIM_DEATH:
		death_animation_finished.emit()
	
	# Check if it was the rallying animation
	if anim_name.ends_with(ANIM_RALLYING) or anim_name == ANIM_RALLYING:
		is_rallying = false
		rallying_finished.emit()
		# Transition to idle after rallying
		play_animation(ANIM_IDLE)


## Check if currently attacking
func is_attack_playing() -> bool:
	return is_attacking


## Check if currently playing rallying animation
func is_rallying_playing() -> bool:
	return is_rallying


## Set animation state directly (for remote players synced from server)
## state: 0=Idle, 1=Walking, 2=Running, 3=Jumping, 4=Attacking, 5=TakingDamage, 6=Dying, 7=Dead
func set_animation_state(state: int, attack_speed: float = 1.0) -> void:
	# Handle death states
	if state == 6 or state == 7:  # Dying/Dead
		play_death_animation()
		return
	
	# If we're dead, only death/respawn can change state
	if is_dead:
		return
	
	match state:
		0:  # Idle
			if is_attacking:
				cancel_attack()
			play_animation(ANIM_IDLE)
		1:  # Walking
			if is_attacking:
				cancel_attack()
			play_animation(ANIM_JOG)
		2:  # Running
			if is_attacking:
				cancel_attack()
			play_animation(ANIM_SPRINT)
		3:  # Jumping
			if is_attacking:
				cancel_attack()
			play_animation(ANIM_JUMP)
		4:  # Attacking
			play_attack_animation(attack_speed)
		5:  # TakingDamage
			play_animation(ANIM_HIT)
		_:
			play_animation(ANIM_IDLE)


## Get the current animation name
func get_current_animation() -> String:
	return current_animation
