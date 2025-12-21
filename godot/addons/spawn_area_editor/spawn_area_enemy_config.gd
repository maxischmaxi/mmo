@tool
class_name SpawnAreaEnemyConfig
extends Resource
## Configuration for a single enemy type within a spawn area.
##
## Defines which enemy type can spawn, its probability weight,
## and the level range for spawned enemies.

## Enemy type to spawn
## 0 = Goblin, 1 = Wolf, 2 = Skeleton, 3 = Mutant
@export_enum("Goblin:0", "Wolf:1", "Skeleton:2", "Mutant:3") var enemy_type: int = 0

## Relative spawn weight. Higher values = more likely to spawn this type.
## Example: weight=3 means 3x more likely than weight=1
@export_range(0.1, 10.0, 0.1) var spawn_weight: float = 1.0

## Minimum level for spawned enemies of this type
@export_range(1, 100) var min_level: int = 1

## Maximum level for spawned enemies of this type
@export_range(1, 100) var max_level: int = 5


func _init() -> void:
	resource_name = "EnemyConfig"


## Get the enemy type as a string for export
func get_enemy_type_string() -> String:
	match enemy_type:
		0: return "Goblin"
		1: return "Wolf"
		2: return "Skeleton"
		3: return "Mutant"
		_: return "Goblin"


## Validate that min_level <= max_level
func _validate_property(property: Dictionary) -> void:
	if property.name == "max_level" and max_level < min_level:
		max_level = min_level
