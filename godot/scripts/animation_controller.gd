extends Node3D
## Controls character animations based on movement state.
## Attach this to a Node3D that contains the animated character model.

## Signal emitted when attack animation finishes
signal attack_finished

## Signal emitted when attack animation reaches the hit point (damage should be applied)
signal attack_hit

## Signal emitted when death animation finishes
signal death_animation_finished

## Path to the AnimationPlayer node within the character model
@export var animation_player_path: NodePath = "../Rig/AnimationPlayer"

## Reference to the AnimationPlayer
@onready var animation_player: AnimationPlayer = get_node_or_null(animation_player_path)

## Currently playing animation
var current_animation: String = ""

## Whether this controller should auto-detect animation from parent velocity
## Set to false for remote players that receive animation state from server
@export var auto_detect: bool = true

## Animation library prefix (set automatically on ready)
var animation_prefix: String = ""

## Whether currently playing attack animation (blocks movement animations)
var is_attacking: bool = false

## Whether the character is dead (blocks all other animations)
var is_dead: bool = false

## Timer for attack hit point
var attack_hit_timer: SceneTreeTimer = null

## Base attack animation duration (Sword_Attack is 1.53 seconds)
const BASE_ATTACK_DURATION: float = 1.53

## Attack hit point (percentage through animation when damage should be dealt)
## 0.5 = 50% through animation, when sword typically connects
const ATTACK_HIT_POINT: float = 0.5

# Speed thresholds
const RUN_SPEED := 0.5  # Any movement above this plays run animation
const SPRINT_SPEED := 6.0  # Sprint animation threshold (speed * sprint_multiplier = 5.0 * 1.5 = 7.5)

# Animation name mapping (actual names from imported GLB)
const ANIM_IDLE := "Idle"
const ANIM_JOG := "Jog_Fwd"
const ANIM_SPRINT := "Sprint"
const ANIM_JUMP_START := "Jump_Start"
const ANIM_JUMP_LOOP := "Jump"  # In-air loop
const ANIM_JUMP_LAND := "Jump_Land"
const ANIM_ATTACK := "Sword_Attack"
const ANIM_HIT := "Hit_Chest"
const ANIM_DEATH := "Death01"


func _ready() -> void:
	# Try to find AnimationPlayer if path doesn't work
	if not animation_player:
		animation_player = _find_animation_player(get_parent())
	
	if animation_player:
		# Detect animation library prefix
		_detect_animation_prefix()
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
	
	# Find the CharacterBody3D parent (Player or RemotePlayer)
	var body := _find_character_body()
	if body:
		update_animation_from_velocity(body)


## Detect the animation library prefix from available animations
func _detect_animation_prefix() -> void:
	if not animation_player:
		return
	
	var anim_list := animation_player.get_animation_list()
	if anim_list.is_empty():
		return
	
	# Print available animations for debugging (only once)
	print("AnimationController: Found %d animations" % anim_list.size())
	
	# Look for Idle animation to determine prefix
	for anim_name in anim_list:
		# Check if it ends with just "Idle" (our target animation)
		if anim_name.ends_with("Idle") and not anim_name.ends_with("_Idle"):
			# Extract prefix (everything before "Idle")
			var idx := anim_name.rfind("Idle")
			if idx > 0:
				animation_prefix = anim_name.substr(0, idx)
				print("AnimationController: Detected animation prefix: '%s'" % animation_prefix)
			return
		elif anim_name == "Idle":
			# No prefix
			animation_prefix = ""
			return


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


## Get full animation name with prefix
func _get_full_anim_name(base_name: String) -> String:
	return animation_prefix + base_name


## Update animation based on CharacterBody3D velocity and state
func update_animation_from_velocity(body: CharacterBody3D) -> void:
	# Don't override attack animation
	if is_attacking:
		return
	
	var velocity := body.velocity
	var on_floor := body.is_on_floor()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	
	var new_anim: String
	
	if not on_floor:
		# In the air
		if velocity.y > 0.5:
			new_anim = ANIM_JUMP_START
		else:
			new_anim = ANIM_JUMP_LOOP
	elif horizontal_speed > SPRINT_SPEED:
		# Sprinting (shift held)
		new_anim = ANIM_SPRINT
	elif horizontal_speed > RUN_SPEED:
		# Normal movement (running is default)
		new_anim = ANIM_JOG
	else:
		# Standing still
		new_anim = ANIM_IDLE
	
	play_animation(new_anim)


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
		# Try without prefix as fallback
		if animation_player.has_animation(base_anim_name):
			animation_player.play(base_anim_name, crossfade)
			current_animation = base_anim_name
		else:
			push_warning("AnimationController: Animation '%s' not found (tried '%s')" % [base_anim_name, full_name])


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
	
	# Play attack animation
	var full_name := _get_full_anim_name(ANIM_ATTACK)
	if animation_player.has_animation(full_name):
		animation_player.play(full_name, 0.05)  # Quick blend into attack
		current_animation = full_name
	elif animation_player.has_animation(ANIM_ATTACK):
		animation_player.play(ANIM_ATTACK, 0.05)
		current_animation = ANIM_ATTACK
	else:
		push_warning("AnimationController: Attack animation not found")
		is_attacking = false
		animation_player.speed_scale = 1.0
		return 0.0
	
	# Calculate actual animation duration
	var actual_duration := BASE_ATTACK_DURATION / attack_speed
	
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
	
	# Return to idle immediately
	play_animation(ANIM_IDLE, 0.1)
	
	emit_signal("attack_finished")


## Play death animation (blocks all other animations until reset)
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
	elif animation_player.has_animation(ANIM_DEATH):
		animation_player.play(ANIM_DEATH, 0.1)
		current_animation = ANIM_DEATH
	else:
		push_warning("AnimationController: Death animation not found")


## Reset from death state (called when respawning)
func reset_from_death() -> void:
	is_dead = false
	is_attacking = false
	animation_player.speed_scale = 1.0
	play_animation(ANIM_IDLE, 0.1)


## Called when any animation finishes
func _on_animation_finished(anim_name: String) -> void:
	# Check if it was the attack animation
	if anim_name.ends_with(ANIM_ATTACK) or anim_name == ANIM_ATTACK:
		is_attacking = false
		animation_player.speed_scale = 1.0
		emit_signal("attack_finished")
	
	# Check if it was the death animation
	if anim_name.ends_with(ANIM_DEATH) or anim_name == ANIM_DEATH:
		death_animation_finished.emit()


## Check if currently attacking
func is_attack_playing() -> bool:
	return is_attacking


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
			play_animation(ANIM_JUMP_LOOP)
		4:  # Attacking
			play_attack_animation(attack_speed)
		5:  # TakingDamage
			play_animation(ANIM_HIT)
		_:
			play_animation(ANIM_IDLE)


## Get the current animation name
func get_current_animation() -> String:
	return current_animation
