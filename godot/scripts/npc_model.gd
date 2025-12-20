extends Node3D
## NPC model wrapper that handles animation initialization and state updates.
## NPCs are simpler than enemies - they mostly just idle and maybe walk around.

## NPC type for this model (set by GameManager when spawning)
var npc_type: int = -1

## Reference to the AnimationPlayer (found in child FBX)
var animation_player: AnimationPlayer = null

## Currently playing animation
var current_animation: String = ""

## Whether initialization is complete
var initialized: bool = false

## Animation library name for NPC animations
const NPC_LIBRARY := "npc"

## NPC type configurations
## Maps npc_type ID to configuration for that NPC
const NPC_CONFIGS := {
	# Type 0: Old Man
	0: {
		"name": "Old Man",
		"idle_animation": "mixamo.com",  # Mixamo animations use this name
	},
}


func _ready() -> void:
	# Find AnimationPlayer in child nodes (inside the Rig/FBX)
	animation_player = _find_animation_player(self)
	
	if animation_player:
		# Load and set up animations with proper looping
		_setup_animations()
		initialized = true
	else:
		push_warning("NpcModel: No AnimationPlayer found in children")


## Initialize the NPC with its type
func initialize_npc(type: int) -> void:
	npc_type = type
	
	# Try to find AnimationPlayer if not found yet
	if not animation_player:
		animation_player = _find_animation_player(self)
	
	if animation_player and not initialized:
		_setup_animations()
		initialized = true


## Set up animations - copy from FBX and enable looping
func _setup_animations() -> void:
	if not animation_player:
		return
	
	var anim_list := animation_player.get_animation_list()
	if anim_list.is_empty():
		push_warning("NpcModel: No animations available in AnimationPlayer")
		return
	
	print("NpcModel: Found animations in FBX: ", anim_list)
	
	# Get config for this NPC type
	var idle_anim_name := "mixamo.com"  # Default Mixamo animation name
	if NPC_CONFIGS.has(npc_type):
		idle_anim_name = NPC_CONFIGS[npc_type].get("idle_animation", "mixamo.com")
	
	# Find the idle animation in the FBX
	var source_anim_name: String = ""
	for anim_name in anim_list:
		if anim_name == idle_anim_name or anim_name.contains(idle_anim_name):
			source_anim_name = anim_name
			break
	
	# Fallback to first animation if not found
	if source_anim_name.is_empty() and not anim_list.is_empty():
		source_anim_name = anim_list[0]
	
	if source_anim_name.is_empty():
		push_warning("NpcModel: Could not find source animation")
		return
	
	# Get the source animation
	var source_animation := animation_player.get_animation(source_anim_name)
	if not source_animation:
		push_warning("NpcModel: Failed to get animation: %s" % source_anim_name)
		return
	
	# Duplicate and set up looping
	var idle_animation := source_animation.duplicate() as Animation
	idle_animation.loop_mode = Animation.LOOP_LINEAR
	
	# Create animation library with our looping animation
	var library := AnimationLibrary.new()
	var err := library.add_animation("Idle", idle_animation)
	if err != OK:
		push_error("NpcModel: Failed to add Idle animation to library")
		return
	
	# Remove existing library if present
	if animation_player.has_animation_library(NPC_LIBRARY):
		animation_player.remove_animation_library(NPC_LIBRARY)
	
	# Add our library
	err = animation_player.add_animation_library(NPC_LIBRARY, library)
	if err != OK:
		push_error("NpcModel: Failed to add animation library")
		return
	
	print("NpcModel [%s]: Set up Idle animation with looping enabled" % _get_npc_name())
	
	# Play the idle animation
	_play_idle()


## Play the idle animation
func _play_idle() -> void:
	if not animation_player:
		return
	
	var anim_name := NPC_LIBRARY + "/Idle"
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		current_animation = anim_name
		print("NpcModel [%s]: Playing %s" % [_get_npc_name(), anim_name])
	else:
		push_warning("NpcModel: Idle animation not found")


## Play the idle animation (public method)
func play_idle() -> void:
	if not animation_player:
		return
	
	if not current_animation.is_empty():
		if not animation_player.is_playing():
			animation_player.play(current_animation)
	else:
		_play_idle()


## Update animation state from server
## For NPCs, we mostly just play idle. Future: walking for roaming NPCs
## state: 0=Idle, 1=Walking, 2=Running, etc.
func set_animation_state(state: int) -> void:
	match state:
		0:  # Idle
			play_idle()
		1, 2:  # Walking/Running - future: add walk animation
			play_idle()  # Fallback to idle for now
		_:
			play_idle()


## Recursively search for AnimationPlayer in children
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null


## Get NPC name
func get_npc_name() -> String:
	return _get_npc_name()


func _get_npc_name() -> String:
	if NPC_CONFIGS.has(npc_type):
		return NPC_CONFIGS[npc_type]["name"]
	return "NPC"
