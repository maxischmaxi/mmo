extends Control
class_name ChatUI
## Metin2-style chat UI with passive and active modes.
## Passive: Shows last few messages, semi-transparent, messages fade
## Active: Shows all messages with scrollbar, input field visible, full opacity

## Chat modes
enum ChatMode { PASSIVE, ACTIVE }

## Current chat mode
var current_mode: ChatMode = ChatMode.PASSIVE

## Maximum messages to keep in history
const MAX_MESSAGES: int = 200

## Messages visible in passive mode
const PASSIVE_VISIBLE_MESSAGES: int = 5

## Message fade time in passive mode (seconds)
const MESSAGE_FADE_TIME: float = 8.0

## Font size for messages
const MESSAGE_FONT_SIZE: int = 12

## Scroll amount per arrow key press
const SCROLL_STEP: int = 40

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
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var messages_container: VBoxContainer = $ScrollContainer/MessagesContainer
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
		# Connect to command response signal
		if local_player.has_signal("command_response"):
			local_player.connect("command_response", _on_command_response)
		# Close chat when teleporting to another zone
		if local_player.has_signal("zone_change"):
			local_player.connect("zone_change", _on_zone_change)
		# Connect to experience and level up signals for notifications
		if local_player.has_signal("experience_gained"):
			local_player.connect("experience_gained", _on_experience_gained)
		if local_player.has_signal("level_up"):
			local_player.connect("level_up", _on_level_up)
		if local_player.has_signal("gold_updated"):
			local_player.connect("gold_updated", _on_gold_updated)
	
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
	
	# When chat is active, handle special keys
	if current_mode == ChatMode.ACTIVE:
		if event is InputEventKey and event.pressed:
			# Allow Escape to close chat
			if event.is_action_pressed("ui_cancel"):
				_set_mode(ChatMode.PASSIVE)
				if chat_input:
					chat_input.release_focus()
				get_viewport().set_input_as_handled()
				return
			
			# Arrow up/down for scrolling (only when not typing in middle of text)
			if event.keycode == KEY_UP:
				_scroll_up()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_DOWN:
				_scroll_down()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_PAGEUP:
				_scroll_page_up()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_PAGEDOWN:
				_scroll_page_down()
				get_viewport().set_input_as_handled()
				return
		# Don't consume other events - let them reach the LineEdit for typing
		return
	
	# Open chat with Enter (only when in passive mode)
	if event.is_action_pressed("open_chat"):
		_set_mode(ChatMode.ACTIVE)
		if chat_input:
			chat_input.grab_focus()
		get_viewport().set_input_as_handled()


## Scroll up by a fixed amount
func _scroll_up() -> void:
	if scroll_container:
		var current = scroll_container.scroll_vertical
		scroll_container.scroll_vertical = max(0, current - SCROLL_STEP)


## Scroll down by a fixed amount
func _scroll_down() -> void:
	if scroll_container:
		var current = scroll_container.scroll_vertical
		var max_scroll = _get_max_scroll()
		scroll_container.scroll_vertical = min(max_scroll, current + SCROLL_STEP)


## Scroll up by a page
func _scroll_page_up() -> void:
	if scroll_container:
		var page_size = scroll_container.size.y - 50
		var current = scroll_container.scroll_vertical
		scroll_container.scroll_vertical = max(0, current - page_size)


## Scroll down by a page
func _scroll_page_down() -> void:
	if scroll_container:
		var page_size = scroll_container.size.y - 50
		var current = scroll_container.scroll_vertical
		var max_scroll = _get_max_scroll()
		scroll_container.scroll_vertical = min(max_scroll, current + page_size)


## Get maximum scroll value
func _get_max_scroll() -> int:
	if not scroll_container or not messages_container:
		return 0
	var content_height = messages_container.size.y
	var view_height = scroll_container.size.y
	return max(0, int(content_height - view_height))


## Scroll to the bottom (latest messages)
func _scroll_to_bottom() -> void:
	if scroll_container and messages_container:
		# Use call_deferred to ensure the scroll happens after layout is complete
		_do_scroll_to_bottom.call_deferred()


## Actually perform the scroll to bottom (called deferred)
func _do_scroll_to_bottom() -> void:
	if scroll_container and messages_container:
		# Force the container to update its minimum size
		messages_container.reset_size()
		# Wait one more frame for sizes to propagate
		await get_tree().process_frame
		scroll_container.scroll_vertical = _get_max_scroll()


## Check if we're in the actual game (not login/character select screens)
func _is_in_game() -> bool:
	return UIManager.is_in_game()


func _set_mode(mode: ChatMode) -> void:
	current_mode = mode
	
	match mode:
		ChatMode.PASSIVE:
			# Hide input, show background faintly or hide it
			if input_container:
				input_container.visible = false
			if background_panel:
				background_panel.visible = false
			if scroll_container:
				# Disable scrollbar in passive mode
				scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
			# Clear input text
			if chat_input:
				chat_input.text = ""
		
		ChatMode.ACTIVE:
			# Show input and background
			if input_container:
				input_container.visible = true
			if background_panel:
				background_panel.visible = true
			if scroll_container:
				# Enable scrollbar in active mode
				scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	
	# Refresh message display
	_refresh_messages()
	
	# Scroll to bottom when opening chat
	if mode == ChatMode.ACTIVE:
		_scroll_to_bottom()


func _refresh_messages() -> void:
	# Clear existing message labels
	for child in messages_container.get_children():
		child.queue_free()
	
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if current_mode == ChatMode.PASSIVE:
		# In passive mode, only show last N messages
		var start_idx = max(0, messages.size() - PASSIVE_VISIBLE_MESSAGES)
		for i in range(start_idx, messages.size()):
			var msg = messages[i]
			var label = _create_message_label(msg, current_time)
			messages_container.add_child(label)
	else:
		# In active mode, show ALL messages
		for msg in messages:
			var label = _create_message_label(msg, current_time)
			messages_container.add_child(label)


func _create_message_label(msg: ChatMessage, current_time: float) -> RichTextLabel:
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Set smaller font size
	label.add_theme_font_size_override("normal_font_size", MESSAGE_FONT_SIZE)
	label.add_theme_font_size_override("bold_font_size", MESSAGE_FONT_SIZE)
	label.add_theme_font_size_override("italics_font_size", MESSAGE_FONT_SIZE)
	label.add_theme_font_size_override("bold_italics_font_size", MESSAGE_FONT_SIZE)
	
	# Format the message
	var formatted: String
	if msg.is_system:
		# Use the message's color directly for system/command messages
		var color_hex = msg.color.to_html(false)
		formatted = "[color=#%s][i]%s[/i][/color]" % [color_hex, msg.content]
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


func _on_zone_change(_zone_id: int, _zone_name: String, _scene_path: String, _spawn_x: float, _spawn_y: float, _spawn_z: float) -> void:
	"""Close chat when teleporting to another zone."""
	unfocus()


func _on_command_response(success: bool, message: String) -> void:
	"""Handle command responses from the server."""
	# Split multi-line messages and add each line
	var lines = message.split("\n")
	for line in lines:
		if not line.strip_edges().is_empty():
			if success:
				add_command_success_message(line)
			else:
				add_command_error_message(line)


func _on_experience_gained(amount: int, _current_xp: int, _xp_to_next: int) -> void:
	"""Show XP gain notification in chat."""
	add_xp_message("+" + str(amount) + " XP")


func _on_level_up(new_level: int, _max_health: int, _max_mana: int, _attack: int, _defense: int) -> void:
	"""Show level up notification in chat."""
	add_level_up_message("Level Up! You are now level " + str(new_level) + "!")


var _last_gold: int = -1  # Track last gold to show difference

func _on_gold_updated(gold: int) -> void:
	"""Show gold gain notification in chat."""
	if _last_gold >= 0 and gold != _last_gold:
		var diff = gold - _last_gold
		if diff > 0:
			add_gold_message("+" + str(diff) + " Gold")
		elif diff < 0:
			add_gold_message(str(diff) + " Gold")
	_last_gold = gold


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
	
	# Handle client-side /clear command
	if message.to_lower() == "/clear":
		messages.clear()
		_refresh_messages()
		chat_input.text = ""
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
	# Auto-scroll to bottom when new message arrives (if in active mode)
	if current_mode == ChatMode.ACTIVE:
		_scroll_to_bottom()


func add_system_message(message: String) -> void:
	var msg = ChatMessage.new("", message, Color.YELLOW, true)
	messages.append(msg)
	_trim_history()
	_refresh_messages()
	if current_mode == ChatMode.ACTIVE:
		_scroll_to_bottom()


func add_command_success_message(message: String) -> void:
	"""Add a command success message (cyan/info color)."""
	var msg = ChatMessage.new("", message, Color(0.4, 0.9, 0.9), true)
	messages.append(msg)
	_trim_history()
	_refresh_messages()
	if current_mode == ChatMode.ACTIVE:
		_scroll_to_bottom()


func add_command_error_message(message: String) -> void:
	"""Add a command error message (red color)."""
	var msg = ChatMessage.new("", message, Color(1.0, 0.4, 0.4), true)
	messages.append(msg)
	_trim_history()
	_refresh_messages()
	if current_mode == ChatMode.ACTIVE:
		_scroll_to_bottom()


func _get_player_color(player_name: String) -> Color:
	# Generate a consistent color for each player based on their name
	var hash_val = player_name.hash()
	var hue = (hash_val % 360) / 360.0
	return Color.from_hsv(hue, 0.6, 0.95)


func _trim_history() -> void:
	while messages.size() > MAX_MESSAGES:
		messages.pop_front()


func add_xp_message(message: String) -> void:
	"""Add an XP gain message (green color)."""
	var msg = ChatMessage.new("", message, Color(0.4, 1.0, 0.4), true)
	messages.append(msg)
	_trim_history()
	_refresh_messages()
	if current_mode == ChatMode.ACTIVE:
		_scroll_to_bottom()


func add_gold_message(message: String) -> void:
	"""Add a gold gain/loss message (gold color)."""
	var msg = ChatMessage.new("", message, Color(1.0, 0.85, 0.2), true)
	messages.append(msg)
	_trim_history()
	_refresh_messages()
	if current_mode == ChatMode.ACTIVE:
		_scroll_to_bottom()


func add_level_up_message(message: String) -> void:
	"""Add a level up message (bright yellow/gold color)."""
	var msg = ChatMessage.new("", message, Color(1.0, 0.95, 0.3), true)
	messages.append(msg)
	_trim_history()
	_refresh_messages()
	if current_mode == ChatMode.ACTIVE:
		_scroll_to_bottom()
