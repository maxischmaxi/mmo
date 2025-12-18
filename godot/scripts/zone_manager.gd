extends Node
## Zone Manager - handles loading and unloading of zone scenes.
## Each empire has completely separate maps - players only see/interact
## with other players and enemies in their current zone.

## Signal emitted when zone loading starts
signal zone_loading_started(zone_id: int, zone_name: String)

## Signal emitted when zone loading finishes
signal zone_loading_finished(zone_id: int)

## Current zone ID (0 = not loaded)
var current_zone_id: int = 0

## Current zone name
var current_zone_name: String = ""

## Current zone scene instance
var current_zone_instance: Node3D = null

## Reference to the local player
var local_player: Node = null

## Reference to loading screen
var loading_screen: Control = null

## Zone container for instanced scenes
@onready var zone_container: Node3D = $ZoneContainer


func _ready() -> void:
	# Add to group for easy finding
	add_to_group("zone_manager")
	
	# Find local player
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		local_player = get_node_or_null("../Player")
	
	# Connect to player's zone_change signal
	if local_player:
		if local_player.has_signal("zone_change"):
			local_player.connect("zone_change", _on_zone_change)
			print("ZoneManager: Connected to player zone_change signal")
	else:
		push_error("ZoneManager: Could not find local player!")
	
	# Find loading screen in UI
	loading_screen = get_node_or_null("../UI/LoadingScreen")
	if loading_screen:
		print("ZoneManager: Found LoadingScreen")


func _on_zone_change(zone_id: int, zone_name: String, scene_path: String, spawn_x: float, spawn_y: float, spawn_z: float) -> void:
	"""Handle zone change request from server."""
	print("ZoneManager: Zone change to zone ", zone_id, " (", zone_name, ") at ", scene_path)
	print("ZoneManager: Spawn position: (", spawn_x, ", ", spawn_y, ", ", spawn_z, ")")
	
	# Don't reload if already in this zone
	if current_zone_id == zone_id and current_zone_instance != null:
		print("ZoneManager: Already in zone ", zone_id, ", skipping reload")
		return
	
	# Start loading process
	_load_zone(zone_id, zone_name, scene_path, Vector3(spawn_x, spawn_y, spawn_z))


func _load_zone(zone_id: int, zone_name: String, scene_path: String, spawn_position: Vector3) -> void:
	"""Load a new zone scene."""
	zone_loading_started.emit(zone_id, zone_name)
	
	# Show loading screen with fade
	if loading_screen and loading_screen.has_method("fade_in"):
		loading_screen.fade_in()
		await loading_screen.fade_finished
	
	# Unload current zone
	if current_zone_instance:
		current_zone_instance.queue_free()
		current_zone_instance = null
		await get_tree().process_frame  # Wait for cleanup
	
	# Load new zone scene
	if ResourceLoader.exists(scene_path):
		var zone_scene = load(scene_path)
		if zone_scene:
			current_zone_instance = zone_scene.instantiate()
			zone_container.add_child(current_zone_instance)
			print("ZoneManager: Loaded zone scene ", scene_path)
		else:
			push_error("ZoneManager: Failed to instantiate zone scene: ", scene_path)
	else:
		push_error("ZoneManager: Zone scene not found: ", scene_path)
		# Create a fallback empty zone
		current_zone_instance = _create_fallback_zone(zone_name)
		zone_container.add_child(current_zone_instance)
	
	# Update tracking
	current_zone_id = zone_id
	current_zone_name = zone_name
	
	# Move player to spawn position
	if local_player:
		local_player.global_position = spawn_position
		print("ZoneManager: Moved player to spawn position: ", spawn_position)
	
	# Hide loading screen with fade
	if loading_screen and loading_screen.has_method("fade_out"):
		loading_screen.fade_out()
	
	zone_loading_finished.emit(zone_id)
	print("ZoneManager: Zone loading finished for zone ", zone_id)


func _create_fallback_zone(zone_name: String) -> Node3D:
	"""Create a simple fallback zone if the scene file doesn't exist."""
	var zone = Node3D.new()
	zone.name = "FallbackZone"
	
	# Create a simple ground plane
	var ground = MeshInstance3D.new()
	ground.name = "Ground"
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(100, 100)
	ground.mesh = plane_mesh
	
	# Create material based on zone name for visual distinction
	var material = StandardMaterial3D.new()
	if "Shinsoo" in zone_name:
		material.albedo_color = Color(0.6, 0.4, 0.3)  # Reddish-brown
	elif "Chunjo" in zone_name:
		material.albedo_color = Color(0.7, 0.6, 0.4)  # Golden-brown
	elif "Jinno" in zone_name:
		material.albedo_color = Color(0.4, 0.5, 0.6)  # Blue-gray
	else:
		material.albedo_color = Color(0.5, 0.5, 0.5)  # Neutral gray
	ground.material_override = material
	
	zone.add_child(ground)
	
	# Create a static body for collision
	var static_body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(100, 0.1, 100)
	collision.shape = shape
	collision.position.y = -0.05
	static_body.add_child(collision)
	zone.add_child(static_body)
	
	# Add a label showing the zone name
	var label = Label3D.new()
	label.text = zone_name
	label.position = Vector3(0, 3, 0)
	label.font_size = 128
	label.modulate = Color.WHITE
	zone.add_child(label)
	
	print("ZoneManager: Created fallback zone for: ", zone_name)
	return zone


## Get the current zone ID
func get_current_zone_id() -> int:
	return current_zone_id


## Get the current zone name
func get_current_zone_name() -> String:
	return current_zone_name


## Check if currently loading a zone
func is_loading() -> bool:
	if loading_screen and loading_screen.has_method("is_visible"):
		return loading_screen.visible
	return false
