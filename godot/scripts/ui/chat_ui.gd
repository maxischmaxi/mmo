extends Control
## Chat UI - handles displaying and sending chat messages.

## Maximum messages to keep in history
const MAX_MESSAGES: int = 100

## Reference to the local player for sending messages
var local_player: Node = null

## Track if chat input is focused (for blocking player input)
var is_chat_focused: bool = false

@onready var chat_history: RichTextLabel = $VBoxContainer/ChatHistory
@onready var chat_input: LineEdit = $VBoxContainer/InputContainer/ChatInput
@onready var send_button: Button = $VBoxContainer/InputContainer/SendButton


func _ready() -> void:
	# Add to group so other scripts can find us
	add_to_group("chat_ui")
	
	# Find the local player
	await get_tree().process_frame
	local_player = get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	if local_player:
		local_player.connect("chat_received", _on_chat_received)
		# Connect to login success signal (replaces old "connected" signal)
		if local_player.has_signal("login_success"):
			local_player.connect("login_success", _on_login_success)
	
	# Connect UI signals
	send_button.pressed.connect(_on_send_pressed)
	chat_input.text_submitted.connect(_on_text_submitted)
	chat_input.focus_entered.connect(_on_chat_focus_entered)
	chat_input.focus_exited.connect(_on_chat_focus_exited)
	
	add_system_message("Welcome to the MMO!")
	add_system_message("Press Enter to chat.")


func _input(event: InputEvent) -> void:
	# Open chat with Enter
	if event.is_action_pressed("open_chat"):
		if not is_chat_focused:
			chat_input.grab_focus()
	
	# Close chat with Escape when focused
	if event.is_action_pressed("clear_target") and is_chat_focused:
		chat_input.release_focus()
		get_viewport().set_input_as_handled()  # Don't let other systems process this Escape


func _on_login_success(player_id: int) -> void:
	add_system_message("Logged in! Your ID: " + str(player_id))


func _on_chat_received(sender_name: String, content: String) -> void:
	add_chat_message(sender_name, content)


func _on_send_pressed() -> void:
	send_message()


func _on_text_submitted(_text: String) -> void:
	send_message()
	# Release focus after sending
	chat_input.release_focus()


func _on_chat_focus_entered() -> void:
	is_chat_focused = true


func _on_chat_focus_exited() -> void:
	is_chat_focused = false
	# Notify camera controller to sync state
	_notify_camera_focus_changed()


func send_message() -> void:
	var message = chat_input.text.strip_edges()
	if message.is_empty():
		return
	
	# Check if connected - use call() to handle the method safely
	var is_connected = false
	if local_player and local_player.has_method("is_connected_to_server"):
		is_connected = local_player.call("is_connected_to_server")
	
	if is_connected:
		local_player.send_chat(message)
	else:
		add_system_message("Not connected to server!")
	
	chat_input.text = ""


## Check if the chat input is currently focused
func is_input_focused() -> bool:
	return is_chat_focused


## Unfocus the chat input
func unfocus() -> void:
	if chat_input:
		chat_input.release_focus()


## Notify camera controller that focus changed
func _notify_camera_focus_changed() -> void:
	var local_player = get_tree().get_first_node_in_group("local_player")
	if local_player:
		var camera_controller = local_player.get_node_or_null("CameraController")
		if camera_controller and camera_controller.has_method("on_ui_focus_released"):
			camera_controller.call("on_ui_focus_released")


func add_chat_message(sender: String, content: String) -> void:
	var color = _get_player_color(sender)
	var formatted = "[color=%s][b]%s:[/b][/color] %s\n" % [color, sender, content]
	chat_history.append_text(formatted)
	_trim_history()


func add_system_message(message: String) -> void:
	var formatted = "[color=yellow][i]%s[/i][/color]\n" % message
	chat_history.append_text(formatted)
	_trim_history()


func _get_player_color(player_name: String) -> String:
	# Generate a consistent color for each player based on their name
	var hash_val = player_name.hash()
	var hue = (hash_val % 360) / 360.0
	var color = Color.from_hsv(hue, 0.7, 0.9)
	return color.to_html(false)


func _trim_history() -> void:
	# Simple trim - just clear if too long
	# In a real game you'd want to be smarter about this
	var text = chat_history.text
	var lines = text.split("\n")
	if lines.size() > MAX_MESSAGES:
		chat_history.clear()
		for i in range(lines.size() - MAX_MESSAGES, lines.size()):
			if i >= 0 and i < lines.size():
				chat_history.append_text(lines[i] + "\n")
