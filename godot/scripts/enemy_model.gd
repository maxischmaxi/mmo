extends Node3D
## Enemy model wrapper that handles animation initialization and state updates.
## Attach this to the root of an enemy model scene.

## Reference to the animation controller
var animation_controller: Node3D = null

## Enemy type for this model (set by GameManager when spawning)
var enemy_type: int = -1

## Whether initialization is pending (waiting for _ready)
var _init_pending: bool = false

## Animation mappings per enemy type
## Maps enemy type ID to folder name and animation file mappings
## For single_fbx mode, mappings map standard names to source animation names in the FBX
## For separate FBX mode (no single_fbx), mappings map standard names to FBX file names
const ENEMY_CONFIGS := {
	# Type 0: Goblin (placeholder - will need its own character later)
	0: {
		"folder": "goblin",
		"mappings": {
			"Idle": "Idle",
			"Walk": "Walk",
			"Run": "Run",
			"Attack": "Attack",
			"Hit": "Hit",
			"Death": "Death",
		}
	},
	# Type 1: Skeleton (placeholder - will need its own character later)
	1: {
		"folder": "skeleton",
		"mappings": {
			"Idle": "Idle",
			"Walk": "Walk",
			"Run": "Run",
			"Attack": "Attack",
			"Hit": "Hit",
			"Death": "Death",
		}
	},
	# Type 2: Mutant - elite dangerous enemy
	2: {
		"folder": "mutant",
		"mappings": {
			"Idle": "Mutant Idle",
			"Walk": "Mutant Walking",
			"Run": "Mutant Run",
			"Attack": "Mutant Swiping",
			"Hit": "Mutant Idle",  # No hit animation, use idle
			"Death": "Mutant Dying",
		}
	},
	# Type 3: Wolf - pack predator with all animations in one Blender file
	# Uses substitute animations: Creep for Attack, Sit for Death
	3: {
		"folder": "wolf",
		"single_fbx": "Wolf_With_Baked_Action_Animations_For_Export_One_Mesh.blend",  # Use Blender file directly
		"mappings": {
			"Idle": "idle",       # Maps to "idle" animation 
			"Walk": "walk",       # Maps to "walk" animation
			"Run": "run",         # Maps to "run" animation
			"Attack": "creep",    # Substitute: creep (stalking) for attack
			"Hit": "idle",        # Fallback to idle for hit reaction
			"Death": "sit",       # Substitute: sit (lies down) for death
		},
		"pingpong": ["Idle"],     # Idle animation ping-pongs for smooth tail movement
	},
}


func _ready() -> void:
	# Find animation controller
	animation_controller = get_node_or_null("AnimationController")
	
	# If initialization was requested before we were ready, do it now
	if _init_pending and enemy_type >= 0:
		_do_initialize()


## Initialize the enemy model with its type
## This loads the appropriate animations based on enemy type
func initialize_enemy(type: int) -> void:
	enemy_type = type
	
	# If not in tree yet, defer initialization to _ready
	if not is_inside_tree():
		_init_pending = true
		return
	
	_do_initialize()


## Actually perform the initialization (called from _ready or initialize_enemy)
func _do_initialize() -> void:
	_init_pending = false
	
	if not animation_controller:
		animation_controller = get_node_or_null("AnimationController")
	
	if not animation_controller:
		push_error("EnemyModel: No animation controller found")
		return
	
	if not ENEMY_CONFIGS.has(enemy_type):
		push_warning("EnemyModel: Unknown enemy type %d, using default" % enemy_type)
		return
	
	var config: Dictionary = ENEMY_CONFIGS[enemy_type]
	var single_fbx: String = config.get("single_fbx", "")
	var pingpong: Array = config.get("pingpong", [])
	animation_controller.initialize(config["folder"], config["mappings"], single_fbx, pingpong)
	print("EnemyModel: Initialized enemy type %d (%s)" % [enemy_type, config["folder"]])


## Update animation state from server
## state: 0=Idle, 1=Walking, 2=Running, 3=Jumping, 4=Attacking, 5=TakingDamage, 6=Dying, 7=Dead
func set_animation_state(state: int) -> void:
	if animation_controller and animation_controller.has_method("set_animation_state"):
		animation_controller.set_animation_state(state)


## Play death animation
func play_death_animation() -> void:
	if animation_controller and animation_controller.has_method("play_death_animation"):
		animation_controller.play_death_animation()


## Play hit reaction animation
func play_hit_animation() -> void:
	if animation_controller and animation_controller.has_method("play_hit_animation"):
		animation_controller.play_hit_animation()


## Get current animation state
func is_dead() -> bool:
	if animation_controller:
		return animation_controller.is_dead
	return false
