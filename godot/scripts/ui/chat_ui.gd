extends Control
class_name ChatUI
## Metin2-style chat UI with passive and active modes.
## Passive: Shows last 4 messages, semi-transparent, messages fade
## Active: Shows more messages, input field visible, full opacity

## Chat modes
enum ChatMode { PASSIVE, ACTIVE }

## Current chat mode
var current_mode: ChatMode = ChatMode.PASSIVE

## Maximum messages to keep in history
const MAX_MESSAGES: int = 100

## Messages visible in each mode
const PASSIVE_VISIBLE_MESSAGES: int = 4
const ACTIVE_VISIBLE_MESSAGES: int = 10

## Message fade time in passive mode (seconds)
const MESSAGE_FADE_TIME: float = 8.0

## Reference to the local player for sending messages
var local_player: Node = null

## Message data structure
class ChatMessage:
	var sender: String
	var content: String
	var color: Color
	var timestamp: float
	var is_system: bool
	
	func _init(s: String, c: String, col: Color, sys: bool = false):
		sender = s
		content = c
		color = col
		is_system = sys
		timestamp = Time.get_ticks_msec() / 1000.0

## Message history
var messages: Array[ChatMessage] = []

## UI References
@onready var messages_container: VBoxContainer = $MessagesContainer
@onready var input_container: HBoxContainer = $InputContainer
@onready var chat_input: LineEdit = $InputContainer/ChatInput
@onready var background_panel: Panel = $BackgroundPanel


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
	
	# Connect UI signals
	if chat_input:
		chat_input.text_submitted.connect(_on_text_submitted)
		chat_input.focus_entered.connect(_on_chat_focus_entered)
		chat_input.focus_exited.connect(_on_chat_focus_exited)
	
	# Start in passive mode
	_set_mode(ChatMode.PASSIVE)
	
	# Add welcome messages
	add_system_message("Welcome to the MMO!")
	add_system_message("Press Enter to chat.")


func _process(delta: float) -> void:
	# In passive mode, update message visibility based on age
	if current_mode == ChatMode.PASSIVE:
		_update_message_fade()


func _input(event: InputEvent) -> void:
	# Only process game inputs when actually in game
	if not _is_in_game():
		return
	
	# Open chat with Enter
	if event.is_action_pressed("open_chat"):
		if current_mode == ChatMode.PASSIVE:
			_set_mode(ChatMode.ACTIVE)
			if chat_input:
				chat_input.grab_focus()
			get_viewport().set_input_as_handled()
	
	# Close chat with Escape when in active mode
	if event.is_action_pressed("ui_cancel") and current_mode == ChatMode.ACTIVE:
		_set_mode(ChatMode.PASSIVE)
		if chat_input:
			chat_input.release_focus()
		get_viewport().set_input_as_handled()


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and "current_state" in game_manager:
		# GameState.IN_GAME = 3
		return game_manager.current_state == 3
	return false


func _set_mode(mode: ChatMode) -> void:
	current_mode = mode
	
	match mode:
		ChatMode.PASSIVE:
			# Hide input, show background faintly or hide it
			if input_container:
				input_container.visible = false
			if background_panel:
				background_panel.visible = false
			# Clear input text
			if chat_input:
				chat_input.text = ""
		
		ChatMode.ACTIVE:
			# Show input and background
			if input_container:
				input_container.visible = true
			if background_panel:
				background_panel.visible = true
	
	# Refresh message display
	_refresh_messages()


func _refresh_messages() -> void:
	# Clear existing message labels
	for child in messages_container.get_children():
		child.queue_free()
	
	# Determine how many messages to show
	var visible_count = PASSIVE_VISIBLE_MESSAGES if current_mode == ChatMode.PASSIVE else ACTIVE_VISIBLE_MESSAGES
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Get the last N messages
	var start_idx = max(0, messages.size() - visible_count)
	for i in range(start_idx, messages.size()):
		var msg = messages[i]
		var label = _create_message_label(msg, current_time)
		messages_container.add_child(label)


func _create_message_label(msg: ChatMessage, current_time: float) -> RichTextLabel:
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Format the message
	var formatted: String
	if msg.is_system:
		formatted = "[color=#cccc55][i]%s[/i][/color]" % msg.content
	else:
		var color_hex = msg.color.to_html(false)
		formatted = "[color=#%s][b]%s:[/b][/color] %s" % [color_hex, msg.sender, msg.content]
	
	label.text = formatted
	
	# In passive mode, apply fade based on age
	if current_mode == ChatMode.PASSIVE:
		var age = current_time - msg.timestamp
		var alpha = 1.0
		if age > MESSAGE_FADE_TIME - 2.0:
			# Fade out over the last 2 seconds
			alpha = clampf((MESSAGE_FADE_TIME - age) / 2.0, 0.0, 1.0)
		label.modulate.a = alpha * 0.85  # Base alpha for passive mode
	else:
		label.modulate.a = 1.0
	
	return label


func _update_message_fade() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var idx = 0
	
	for child in messages_container.get_children():
		if child is RichTextLabel:
			var msg_idx = max(0, messages.size() - PASSIVE_VISIBLE_MESSAGES) + idx
			if msg_idx < messages.size():
				var msg = messages[msg_idx]
				var age = current_time - msg.timestamp
				var alpha = 1.0
				if age > MESSAGE_FADE_TIME - 2.0:
					alpha = clampf((MESSAGE_FADE_TIME - age) / 2.0, 0.0, 1.0)
				child.modulate.a = alpha * 0.85
				
				# Remove if fully faded
				if alpha <= 0:
					child.queue_free()
			idx += 1


func _on_chat_received(sender_name: String, content: String) -> void:
	add_chat_message(sender_name, content)


func _on_text_submitted(_text: String) -> void:
	send_message()
	# Return to passive mode after sending
	_set_mode(ChatMode.PASSIVE)
	if chat_input:
		chat_input.release_focus()


func _on_chat_focus_entered() -> void:
	pass  # Mode is already set by _set_mode


func _on_chat_focus_exited() -> void:
	# If we lost focus, go back to passive mode
	if current_mode == ChatMode.ACTIVE:
		_set_mode(ChatMode.PASSIVE)


func send_message() -> void:
	if not chat_input:
		return
	
	var message = chat_input.text.strip_edges()
	if message.is_empty():
		return
	
	# Check if connected
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
	return current_mode == ChatMode.ACTIVE


## Unfocus the chat input
func unfocus() -> void:
	_set_mode(ChatMode.PASSIVE)
	if chat_input:
		chat_input.release_focus()


func add_chat_message(sender: String, content: String) -> void:
	var color = _get_player_color(sender)
	var msg = ChatMessage.new(sender, content, color, false)
	messages.append(msg)
	_trim_history()
	_refresh_messages()


func add_system_message(message: String) -> void:
	var msg = ChatMessage.new("", message, Color.YELLOW, true)
	messages.append(msg)
	_trim_history()
	_refresh_messages()


func _get_player_color(player_name: String) -> Color:
	# Generate a consistent color for each player based on their name
	var hash_val = player_name.hash()
	var hue = (hash_val % 360) / 360.0
	return Color.from_hsv(hue, 0.6, 0.95)


func _trim_history() -> void:
	while messages.size() > MAX_MESSAGES:
		messages.pop_front()
