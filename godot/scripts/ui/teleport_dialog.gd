extends Control
class_name TeleportDialog
## Teleport Dialog - Shows available destinations when using Teleport Ring.

## Signal emitted when dialog is closed
signal dialog_closed

## Reference to local player
var local_player: Node = null

## Available zones (zone_id -> {name, empire})
## Empire values: 0 = Shinsoo (Red), 1 = Chunjo (Yellow), 2 = Jinno (Blue)
const ZONES: Dictionary = {
	1: {"name": "Shinsoo Village", "empire": 0, "color": Color(0.9, 0.4, 0.3)},
	100: {"name": "Chunjo Village", "empire": 1, "color": Color(0.9, 0.8, 0.3)},
	200: {"name": "Jinno Village", "empire": 2, "color": Color(0.3, 0.6, 0.9)},
}

## UI References
@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var title_label: Label = $CenterContainer/Panel/VBox/Title
@onready var zone_container: VBoxContainer = $CenterContainer/Panel/VBox/ZoneContainer
@onready var cancel_button: Button = $CenterContainer/Panel/VBox/CancelButton


func _ready() -> void:
	# Add to group for easy access
	add_to_group("teleport_dialog")
	
	# Start hidden
	visible = false
	
	# Connect cancel button
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)
	
	# Create zone buttons
	_create_zone_buttons()


func _input(event: InputEvent) -> void:
	# Close dialog with Escape
	if visible and event.is_action_pressed("ui_cancel"):
		close_dialog()
		get_viewport().set_input_as_handled()


func _create_zone_buttons() -> void:
	"""Create buttons for each available zone."""
	if not zone_container:
		return
	
	# Clear existing buttons
	for child in zone_container.get_children():
		child.queue_free()
	
	# Create a button for each zone
	for zone_id in ZONES:
		var zone_info = ZONES[zone_id]
		
		var button = Button.new()
		button.text = zone_info["name"]
		button.custom_minimum_size = Vector2(200, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Style the button with empire color
		var style = StyleBoxFlat.new()
		style.bg_color = zone_info["color"].darkened(0.5)
		style.border_width_bottom = 2
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_color = zone_info["color"]
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		button.add_theme_stylebox_override("normal", style)
		
		# Hover style
		var hover_style = style.duplicate()
		hover_style.bg_color = zone_info["color"].darkened(0.3)
		button.add_theme_stylebox_override("hover", hover_style)
		
		# Pressed style
		var pressed_style = style.duplicate()
		pressed_style.bg_color = zone_info["color"].darkened(0.1)
		button.add_theme_stylebox_override("pressed", pressed_style)
		
		# Connect the button
		button.pressed.connect(_on_zone_selected.bind(zone_id))
		
		zone_container.add_child(button)


func show_dialog() -> void:
	"""Show the teleport dialog."""
	# Find local player if not already set
	if not local_player:
		local_player = get_tree().get_first_node_in_group("local_player")
		if not local_player:
			var main = get_tree().current_scene
			if main:
				local_player = main.get_node_or_null("Player")
	
	visible = true
	# Panel is centered via anchors in the tscn file


func close_dialog() -> void:
	"""Hide the teleport dialog."""
	visible = false
	dialog_closed.emit()


func _on_zone_selected(zone_id: int) -> void:
	"""Handle zone button pressed."""
	print("TeleportDialog: Selected zone ", zone_id)
	
	if local_player and local_player.has_method("send_teleport_request"):
		local_player.send_teleport_request(zone_id)
		print("TeleportDialog: Sent teleport request to zone ", zone_id)
	else:
		push_error("TeleportDialog: Could not find local player or send_teleport_request method")
	
	close_dialog()


func _on_cancel_pressed() -> void:
	"""Handle cancel button pressed."""
	close_dialog()
