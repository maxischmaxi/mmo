extends Control
class_name DebugOverlay
## Minecraft F3-style debug overlay.
## Toggle with F3 key. Shows FPS, coordinates, network stats, etc.

## Reference to local player
var local_player: Node = null

## Reference to game manager (for entity counts)
var game_manager: Node = null

## Reference to day/night controller (for time display)
var day_night_controller: Node3D = null

## Reference to zone manager (for zone name)
var zone_manager: Node = null

## Update interval in seconds (0.25s is a good balance)
const UPDATE_INTERVAL: float = 0.25

## Time since last update
var time_since_update: float = 0.0

## UI References - Right column
@onready var right_column: VBoxContainer = $RightColumn
@onready var fps_label: Label = $RightColumn/FPSLabel
@onready var xyz_label: Label = $RightColumn/XYZLabel
@onready var facing_label: Label = $RightColumn/FacingLabel
@onready var speed_label: Label = $RightColumn/SpeedLabel
@onready var zone_label: Label = $RightColumn/ZoneLabel
@onready var time_label: Label = $RightColumn/TimeLabel
@onready var connected_label: Label = $RightColumn/ConnectedLabel
@onready var ping_label: Label = $RightColumn/PingLabel
@onready var packets_label: Label = $RightColumn/PacketsLabel
@onready var players_label: Label = $RightColumn/PlayersLabel
@onready var enemies_label: Label = $RightColumn/EnemiesLabel
@onready var npcs_label: Label = $RightColumn/NPCsLabel
@onready var draw_calls_label: Label = $RightColumn/DrawCallsLabel
@onready var memory_label: Label = $RightColumn/MemoryLabel


func _ready() -> void:
	# Start hidden
	visible = false
	
	print("[DebugOverlay] Ready - F3 to toggle")
	
	# Wait a frame for other nodes to be ready
	await get_tree().process_frame
	
	# Find references
	_find_references()


func _find_references() -> void:
	# Find local player
	local_player = get_tree().get_first_node_in_group("local_player")
	if not local_player:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	# Find game manager
	game_manager = get_tree().get_first_node_in_group("game_manager")
	
	# Find day/night controller
	if game_manager and game_manager.has_method("get_day_night_controller"):
		day_night_controller = game_manager.get_day_night_controller()
	
	# Find zone manager
	zone_manager = get_tree().get_first_node_in_group("zone_manager")


func _process(delta: float) -> void:
	# Only update when visible
	if not visible:
		return
	
	# Rate limit updates
	time_since_update += delta
	if time_since_update < UPDATE_INTERVAL:
		return
	time_since_update = 0.0
	
	# Update all stats
	_update_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay"):
		print("[DebugOverlay] F3 pressed, in_game=", _is_in_game())
		toggle_visibility()
		# Mark as handled so it doesn't propagate
		get_viewport().set_input_as_handled()


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	if not game_manager:
		game_manager = get_tree().get_first_node_in_group("game_manager")
	
	if game_manager and "current_state" in game_manager:
		# GameState.IN_GAME = 3
		return game_manager.current_state == 3
	return false


func toggle_visibility() -> void:
	visible = not visible
	print("[DebugOverlay] Toggled to visible=", visible)
	if visible:
		# Refresh references in case they changed
		_find_references()
		# Update immediately when shown
		time_since_update = UPDATE_INTERVAL
		_update_stats()


func _update_stats() -> void:
	# FPS
	var fps = Engine.get_frames_per_second()
	fps_label.text = "FPS: %d" % fps
	
	# Player position
	if local_player:
		var pos = local_player.global_position
		xyz_label.text = "XYZ: %.2f / %.2f / %.2f" % [pos.x, pos.y, pos.z]
		
		# Facing direction (convert radians to degrees, normalize to 0-360)
		var rotation_deg = rad_to_deg(local_player.rotation.y)
		# Normalize to 0-360 range
		rotation_deg = fmod(rotation_deg + 360.0, 360.0)
		var cardinal = _get_cardinal_direction(rotation_deg)
		facing_label.text = "Facing: %.1f (%s)" % [rotation_deg, cardinal]
		
		# Speed (velocity magnitude)
		var velocity = local_player.get_velocity() if local_player.has_method("get_velocity") else Vector3.ZERO
		var speed = velocity.length()
		speed_label.text = "Speed: %.2f m/s" % speed
	else:
		xyz_label.text = "XYZ: N/A"
		facing_label.text = "Facing: N/A"
		speed_label.text = "Speed: N/A"
	
	# Zone name
	var zone_name = "Unknown"
	if zone_manager and zone_manager.has_method("get_current_zone_name"):
		zone_name = zone_manager.get_current_zone_name()
	elif local_player and local_player.has_method("get_current_zone_id"):
		zone_name = "Zone %d" % local_player.get_current_zone_id()
	zone_label.text = "Zone: %s" % zone_name
	
	# In-game time
	var time_str = "N/A"
	var time_name = ""
	if day_night_controller:
		if day_night_controller.has_method("get_time_string"):
			time_str = day_night_controller.get_time_string()
		if "current_time_name" in day_night_controller:
			time_name = " [%s]" % day_night_controller.current_time_name
	time_label.text = "Time: %s%s" % [time_str, time_name]
	
	# Connection status
	var connected = false
	if local_player and local_player.has_method("is_connected_to_server"):
		connected = local_player.is_connected_to_server()
	connected_label.text = "Connected: %s" % ("Yes" if connected else "No")
	
	# Network stats (from Rust)
	if local_player and local_player.has_method("get_ping_ms"):
		var ping = local_player.get_ping_ms()
		if ping >= 0:
			ping_label.text = "Ping: %d ms" % ping
		else:
			ping_label.text = "Ping: N/A"
	else:
		ping_label.text = "Ping: N/A"
	
	if local_player and local_player.has_method("get_packets_sent"):
		var sent = local_player.get_packets_sent()
		var recv = local_player.get_packets_received()
		packets_label.text = "Packets: %d sent / %d recv" % [sent, recv]
	else:
		packets_label.text = "Packets: N/A"
	
	# Entity counts from game manager
	var player_count = 0
	var enemy_count = 0
	var npc_count = 0
	
	if game_manager:
		if "remote_players" in game_manager:
			player_count = game_manager.remote_players.size()
		if "enemies" in game_manager:
			enemy_count = game_manager.enemies.size()
		if "npcs" in game_manager:
			npc_count = game_manager.npcs.size()
	
	players_label.text = "Players: %d" % player_count
	enemies_label.text = "Enemies: %d" % enemy_count
	npcs_label.text = "NPCs: %d" % npc_count
	
	# Draw calls
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	draw_calls_label.text = "Draw Calls: %d" % int(draw_calls)
	
	# Memory usage (in MB)
	var memory_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	var memory_mb = memory_bytes / (1024.0 * 1024.0)
	memory_label.text = "Memory: %.1f MB" % memory_mb


## Convert rotation degrees to cardinal direction
func _get_cardinal_direction(degrees: float) -> String:
	# In Godot, 0 degrees is facing -Z (forward), rotation is counterclockwise
	# Adjust so 0 = North, 90 = East, 180 = South, 270 = West
	# Actually in most games: 0 = North (forward/-Z), so let's map accordingly
	
	# Normalize to 0-360
	degrees = fmod(degrees + 360.0, 360.0)
	
	if degrees >= 337.5 or degrees < 22.5:
		return "N"
	elif degrees >= 22.5 and degrees < 67.5:
		return "NW"
	elif degrees >= 67.5 and degrees < 112.5:
		return "W"
	elif degrees >= 112.5 and degrees < 157.5:
		return "SW"
	elif degrees >= 157.5 and degrees < 202.5:
		return "S"
	elif degrees >= 202.5 and degrees < 247.5:
		return "SE"
	elif degrees >= 247.5 and degrees < 292.5:
		return "E"
	else:  # 292.5 to 337.5
		return "NE"
