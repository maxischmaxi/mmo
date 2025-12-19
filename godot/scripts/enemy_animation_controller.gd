extends Node3D
## Controls enemy character animations based on state.
## Similar to AnimationController but designed for enemies with per-type animations.
## Loads animations from assets/animations/enemies/{enemy_type}/ folders.

## Signal emitted when attack animation reaches the hit point
signal attack_hit

## Signal emitted when death animation finishes
signal death_animation_finished

## Path to the AnimationPlayer node within the character model
@export var animation_player_path: NodePath = ""

## Reference to the AnimationPlayer
@onready var animation_player: AnimationPlayer = get_node_or_null(animation_player_path)

## Currently playing animation
var current_animation: String = ""

## Animation library name for loaded animations
const ENEMY_LIBRARY := "enemy"

## Whether currently playing attack animation
var is_attacking: bool = false

## Whether the character is dead
var is_dead: bool = false

## Whether animations have been loaded
var animations_loaded: bool = false

## Attack animation duration (updated from actual animation)
var attack_animation_duration: float = 1.0

## Attack hit point (percentage through animation when damage should be dealt)
const ATTACK_HIT_POINT: float = 0.5

## Timer for attack hit point
var attack_hit_timer: SceneTreeTimer = null

## The enemy type folder name (e.g., "mutant", "skeleton", "goblin")
var enemy_type_folder: String = ""

## Animation name mappings - can be customized per enemy type
## Maps our standard animation names to the actual file names (or source animation names for multi-anim FBX)
var animation_mappings: Dictionary = {}

## Single FBX file name if all animations are in one file (e.g., wolf)
## Empty string means use separate FBX files per animation (e.g., mutant)
var single_fbx_file: String = ""

## Cached FBX instance for multi-animation files (to avoid reloading)
var _cached_fbx_instance: Node = null
var _cached_fbx_anim_player: AnimationPlayer = null

# Standard animation names (what code uses)
const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"
const ANIM_RUN := "Run"
const ANIM_ATTACK := "Attack"
const ANIM_HIT := "Hit"
const ANIM_DEATH := "Death"

## Animations that should loop continuously
const LOOPING_ANIMATIONS := [
	ANIM_IDLE,
	ANIM_WALK,
	ANIM_RUN,
]

## Animations that should ping-pong (play forward then backward) for smoother loops
## This is configured per enemy type via pingpong_anims in the config
var pingpong_animations: Array = []


func _ready() -> void:
	# Try to find AnimationPlayer if path doesn't work
	if not animation_player:
		animation_player = _find_animation_player(get_parent())
	
	if animation_player:
		# Connect to animation finished signal
		if not animation_player.animation_finished.is_connected(_on_animation_finished):
			animation_player.animation_finished.connect(_on_animation_finished)
	else:
		push_warning("EnemyAnimationController: Could not find AnimationPlayer")


## Initialize the controller with the enemy type folder name
## This should be called after the enemy model is set up
## folder_name: The folder name under assets/animations/enemies/ (e.g., "mutant")
## mappings: Dictionary mapping standard names to actual file names or source animation names
##           For separate FBX per animation: {"Idle": "Mutant Idle", "Attack": "Mutant Swiping"}
##           For multi-anim FBX: {"Idle": "idle", "Walk": "walk", "Attack": "creep"}
## single_fbx: Optional - if set, all animations are loaded from this single FBX file
##             e.g., "Wolf_with_Animations" for wolf which has all anims in one file
## pingpong_anims: Optional - array of animation names that should ping-pong instead of linear loop
func initialize(folder_name: String, mappings: Dictionary, single_fbx: String = "", pingpong_anims: Array = []) -> void:
	enemy_type_folder = folder_name
	animation_mappings = mappings
	single_fbx_file = single_fbx
	pingpong_animations = pingpong_anims
	
	if animation_player:
		_load_enemy_animations()
		play_animation(ANIM_IDLE)


## Load all enemy animations from the enemy type folder
func _load_enemy_animations() -> void:
	if animations_loaded:
		return
	
	if not animation_player:
		push_error("EnemyAnimationController: Cannot load animations - no AnimationPlayer")
		return
	
	if enemy_type_folder.is_empty():
		push_error("EnemyAnimationController: Cannot load animations - no enemy type folder set")
		return
	
	# Create a new AnimationLibrary for enemy animations
	var library := AnimationLibrary.new()
	
	var base_path := "res://assets/animations/enemies/%s/" % enemy_type_folder
	var loaded_count := 0
	
	# Check if we're using a single multi-animation file or separate files
	if not single_fbx_file.is_empty():
		# Multi-animation mode: load all animations from one file
		# Support both FBX and Blend files
		var file_path: String
		if single_fbx_file.ends_with(".blend"):
			file_path = base_path + single_fbx_file
		else:
			file_path = base_path + single_fbx_file + ".fbx"
		loaded_count = _load_animations_from_multi_fbx(file_path, library)
	else:
		# Separate FBX mode: load each animation from its own file
		for standard_name in animation_mappings:
			var file_name: String = animation_mappings[standard_name]
			var fbx_path := base_path + file_name + ".fbx"
			
			var animation := _load_animation_from_fbx(fbx_path, standard_name)
			if animation:
				var err := library.add_animation(standard_name, animation)
				if err == OK:
					loaded_count += 1
				else:
					push_warning("EnemyAnimationController: Failed to add animation '%s' to library" % standard_name)
	
	# Clean up cached FBX instance if any
	_cleanup_cached_fbx()
	
	# Add the library to the AnimationPlayer
	if animation_player.has_animation_library(ENEMY_LIBRARY):
		animation_player.remove_animation_library(ENEMY_LIBRARY)
	
	var err := animation_player.add_animation_library(ENEMY_LIBRARY, library)
	if err == OK:
		animations_loaded = true
		print("EnemyAnimationController [%s]: Loaded %d/%d animations" % [enemy_type_folder, loaded_count, animation_mappings.size()])
		
		# Update attack animation duration from actual animation
		var attack_anim_name := ENEMY_LIBRARY + "/" + ANIM_ATTACK
		if animation_player.has_animation(attack_anim_name):
			var attack_anim := animation_player.get_animation(attack_anim_name)
			if attack_anim:
				attack_animation_duration = attack_anim.length
				print("EnemyAnimationController [%s]: Attack animation duration: %.2fs" % [enemy_type_folder, attack_animation_duration])
	else:
		push_error("EnemyAnimationController: Failed to add enemy library to AnimationPlayer")


## Load animations from a multi-animation FBX file (e.g., wolf with all anims in one file)
## Returns the number of animations successfully loaded
func _load_animations_from_multi_fbx(fbx_path: String, library: AnimationLibrary) -> int:
	if not ResourceLoader.exists(fbx_path):
		push_error("EnemyAnimationController: Multi-animation FBX file not found: %s" % fbx_path)
		return 0
	
	# Load the FBX as a PackedScene
	var scene := load(fbx_path) as PackedScene
	if not scene:
		push_error("EnemyAnimationController: Failed to load multi-animation FBX: %s" % fbx_path)
		return 0
	
	# Instantiate to extract animations
	var instance := scene.instantiate()
	if not instance:
		push_error("EnemyAnimationController: Failed to instantiate multi-animation FBX: %s" % fbx_path)
		return 0
	
	# Find the AnimationPlayer in the FBX scene
	var fbx_anim_player := _find_animation_player(instance)
	if not fbx_anim_player:
		push_error("EnemyAnimationController: No AnimationPlayer in multi-animation FBX: %s" % fbx_path)
		instance.queue_free()
		return 0
	
	# Get all available animations
	var anim_list := fbx_anim_player.get_animation_list()
	if anim_list.is_empty():
		push_error("EnemyAnimationController: No animations in multi-animation FBX: %s" % fbx_path)
		instance.queue_free()
		return 0
	
	print("EnemyAnimationController [%s]: Found %d animations in FBX: %s" % [enemy_type_folder, anim_list.size(), anim_list])
	
	var loaded_count := 0
	
	# Map each standard animation name to its source animation in the FBX
	for standard_name in animation_mappings:
		var source_anim_name: String = animation_mappings[standard_name]
		
		# Find matching animation in the FBX (case-insensitive search)
		var found_anim_name := ""
		for anim_name in anim_list:
			if anim_name.to_lower() == source_anim_name.to_lower():
				found_anim_name = anim_name
				break
			# Also check if it contains the name (some FBX files prefix/suffix animation names)
			if anim_name.to_lower().contains(source_anim_name.to_lower()):
				found_anim_name = anim_name
				break
		
		if found_anim_name.is_empty():
			push_warning("EnemyAnimationController [%s]: Animation '%s' not found in FBX (looking for '%s')" % [enemy_type_folder, standard_name, source_anim_name])
			continue
		
		var source_animation := fbx_anim_player.get_animation(found_anim_name)
		if not source_animation:
			push_warning("EnemyAnimationController [%s]: Failed to get animation '%s' from FBX" % [enemy_type_folder, found_anim_name])
			continue
		
		# Duplicate the animation so we can modify it
		var animation := source_animation.duplicate() as Animation
		
		# Set loop mode based on animation type
		if standard_name in pingpong_animations:
			animation.loop_mode = Animation.LOOP_PINGPONG
		elif standard_name in LOOPING_ANIMATIONS:
			animation.loop_mode = Animation.LOOP_LINEAR
		else:
			animation.loop_mode = Animation.LOOP_NONE
		
		var err := library.add_animation(standard_name, animation)
		if err == OK:
			loaded_count += 1
			print("EnemyAnimationController [%s]: Loaded '%s' from '%s'" % [enemy_type_folder, standard_name, found_anim_name])
		else:
			push_warning("EnemyAnimationController [%s]: Failed to add animation '%s' to library" % [enemy_type_folder, standard_name])
	
	# Clean up
	instance.queue_free()
	
	return loaded_count


## Clean up cached FBX instance
func _cleanup_cached_fbx() -> void:
	if _cached_fbx_instance:
		_cached_fbx_instance.queue_free()
		_cached_fbx_instance = null
		_cached_fbx_anim_player = null


## Load an animation from an FBX file
func _load_animation_from_fbx(fbx_path: String, anim_name: String) -> Animation:
	if not ResourceLoader.exists(fbx_path):
		push_warning("EnemyAnimationController: FBX file not found: %s" % fbx_path)
		return null
	
	# Load the FBX as a PackedScene
	var scene := load(fbx_path) as PackedScene
	if not scene:
		push_warning("EnemyAnimationController: Failed to load FBX: %s" % fbx_path)
		return null
	
	# Instantiate temporarily to extract animation
	var instance := scene.instantiate()
	if not instance:
		push_warning("EnemyAnimationController: Failed to instantiate FBX: %s" % fbx_path)
		return null
	
	# Find the AnimationPlayer in the FBX scene
	var fbx_anim_player := _find_animation_player(instance)
	if not fbx_anim_player:
		push_warning("EnemyAnimationController: No AnimationPlayer in FBX: %s" % fbx_path)
		instance.queue_free()
		return null
	
	# Get the animation (Mixamo exports typically name it based on the animation)
	var anim_list := fbx_anim_player.get_animation_list()
	if anim_list.is_empty():
		push_warning("EnemyAnimationController: No animations in FBX: %s" % fbx_path)
		instance.queue_free()
		return null
	
	# Get the first animation (there should only be one per Mixamo FBX)
	var source_anim_name: String = anim_list[0]
	var source_animation := fbx_anim_player.get_animation(source_anim_name)
	if not source_animation:
		push_warning("EnemyAnimationController: Failed to get animation from FBX: %s" % fbx_path)
		instance.queue_free()
		return null
	
	# Duplicate the animation so we can modify it
	var animation := source_animation.duplicate() as Animation
	
	# Set loop mode based on animation type
	if anim_name in LOOPING_ANIMATIONS:
		animation.loop_mode = Animation.LOOP_LINEAR
	else:
		animation.loop_mode = Animation.LOOP_NONE
	
	# Clean up the temporary instance
	instance.queue_free()
	
	return animation


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
	return ENEMY_LIBRARY + "/" + base_name


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
		push_warning("EnemyAnimationController: Animation '%s' not found" % full_name)


## Play attack animation
## Returns the actual duration of the attack animation
func play_attack_animation(attack_speed: float = 1.0) -> float:
	if is_attacking:
		return 0.0
	
	if not animation_player:
		return 0.0
	
	is_attacking = true
	
	# Calculate animation speed scale
	animation_player.speed_scale = attack_speed
	
	# Play attack animation
	var full_name := _get_full_anim_name(ANIM_ATTACK)
	if animation_player.has_animation(full_name):
		animation_player.play(full_name, 0.15)
		current_animation = full_name
	else:
		push_warning("EnemyAnimationController: Attack animation not found")
		is_attacking = false
		animation_player.speed_scale = 1.0
		return 0.0
	
	# Calculate actual animation duration
	var actual_duration := attack_animation_duration / attack_speed
	
	# Create timer for hit point
	var hit_delay := actual_duration * ATTACK_HIT_POINT
	attack_hit_timer = get_tree().create_timer(hit_delay)
	attack_hit_timer.timeout.connect(_on_attack_hit_timer)
	
	return actual_duration


## Called when attack hit timer fires
func _on_attack_hit_timer() -> void:
	if is_attacking:
		attack_hit.emit()
	attack_hit_timer = null


## Play death animation
func play_death_animation() -> void:
	if is_dead:
		return
	
	is_dead = true
	is_attacking = false
	animation_player.speed_scale = 1.0
	
	var full_name := _get_full_anim_name(ANIM_DEATH)
	if animation_player.has_animation(full_name):
		animation_player.play(full_name, 0.1)
		current_animation = full_name
	else:
		push_warning("EnemyAnimationController: Death animation not found")


## Play hit reaction animation
func play_hit_animation() -> void:
	if is_dead or is_attacking:
		return
	
	var full_name := _get_full_anim_name(ANIM_HIT)
	if animation_player.has_animation(full_name):
		animation_player.play(full_name, 0.1)
		current_animation = full_name


## Reset from death state (for respawning)
func reset_from_death() -> void:
	is_dead = false
	is_attacking = false
	animation_player.speed_scale = 1.0
	play_animation(ANIM_IDLE, 0.1)


## Called when any animation finishes
func _on_animation_finished(anim_name: String) -> void:
	# Check if it was the attack animation
	if anim_name.ends_with(ANIM_ATTACK):
		is_attacking = false
		animation_player.speed_scale = 1.0
		play_animation(ANIM_IDLE, 0.2)
	
	# Check if it was the death animation
	if anim_name.ends_with(ANIM_DEATH):
		death_animation_finished.emit()
	
	# Check if it was the hit animation
	if anim_name.ends_with(ANIM_HIT):
		play_animation(ANIM_IDLE, 0.1)


## Set animation state from server (for synced enemies)
## state: 0=Idle, 1=Walking, 2=Running, 3=Jumping, 4=Attacking, 5=TakingDamage, 6=Dying, 7=Dead
func set_animation_state(state: int) -> void:
	# Handle death states
	if state == 6 or state == 7:  # Dying/Dead
		play_death_animation()
		return
	
	if is_dead:
		return
	
	match state:
		0:  # Idle
			if not is_attacking:
				play_animation(ANIM_IDLE)
		1:  # Walking
			if not is_attacking:
				play_animation(ANIM_WALK)
		2:  # Running
			if not is_attacking:
				play_animation(ANIM_RUN)
		4:  # Attacking
			play_attack_animation()
		5:  # TakingDamage
			play_hit_animation()
		_:
			if not is_attacking:
				play_animation(ANIM_IDLE)


## Check if currently attacking
func is_attack_playing() -> bool:
	return is_attacking


## Get the current animation name
func get_current_animation() -> String:
	return current_animation
