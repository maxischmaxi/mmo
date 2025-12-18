extends Control
class_name EscapeMenu
## Escape/Pause menu with Resume, Settings, Sign Out, and Quit options.
## Sign Out and Quit have a 3-second countdown that can be cancelled by movement or damage.

signal menu_closed

## Countdown configuration
const COUNTDOWN_SECONDS := 3

## Action types for countdown
enum CountdownAction { NONE, SIGN_OUT, QUIT }

## Current countdown state
var _countdown_active: bool = false
var _countdown_remaining: int = 0
var _countdown_action: CountdownAction = CountdownAction.NONE
var _original_button_text: String = ""

## Reference to local player (for sign out and damage detection)
var local_player: Node = null

## Reference to chat UI (for system messages)
var chat_ui: Control = null

## Reference to game manager (for sign out)
var game_manager: Node = null

## UI References
@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var title_label: Label = $CenterContainer/Panel/VBox/Title
@onready var resume_button: Button = $CenterContainer/Panel/VBox/ResumeButton
@onready var settings_button: Button = $CenterContainer/Panel/VBox/SettingsButton
@onready var sign_out_button: Button = $CenterContainer/Panel/VBox/SignOutButton
@onready var quit_button: Button = $CenterContainer/Panel/VBox/QuitButton
@onready var countdown_timer: Timer = $CountdownTimer

## Settings dialog reference
var settings_dialog: Control = null


func _ready() -> void:
	# Start hidden
	visible = false
	
	# Register with UIManager
	UIManager.set_escape_menu(self)
	
	# Connect button signals
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	if sign_out_button:
		sign_out_button.pressed.connect(_on_sign_out_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	
	# Connect countdown timer
	if countdown_timer:
		countdown_timer.timeout.connect(_on_countdown_tick)
	
	# Find references after scene is ready
	await get_tree().process_frame
	_find_references()


func _find_references() -> void:
	"""Find references to other nodes."""
	# Find local player
	local_player = get_tree().get_first_node_in_group("local_player")
	if not local_player:
		var main = get_tree().current_scene
		if main:
			local_player = main.get_node_or_null("Player")
	
	# Connect to damage signal for countdown cancellation
	if local_player and local_player.has_signal("damage_dealt"):
		if not local_player.damage_dealt.is_connected(_on_damage_dealt):
			local_player.damage_dealt.connect(_on_damage_dealt)
	
	# Find chat UI
	chat_ui = get_tree().get_first_node_in_group("chat_ui")
	if not chat_ui:
		var game_ui = get_parent()
		if game_ui:
			chat_ui = game_ui.get_node_or_null("ChatUI")
	
	# Find game manager
	game_manager = get_tree().get_first_node_in_group("game_manager")
	
	# Find settings dialog
	var game_ui = get_parent()
	if game_ui:
		settings_dialog = game_ui.get_node_or_null("SettingsDialog")


func _input(event: InputEvent) -> void:
	# Only process when visible and countdown is active
	if not visible or not _countdown_active:
		return
	
	# Check for movement input to cancel countdown
	if _is_movement_input(event):
		_cancel_countdown("Movement detected")


func _is_movement_input(event: InputEvent) -> bool:
	"""Check if the event is a movement input."""
	if event is InputEventKey:
		# Check for any movement-related action
		var movement_actions = [
			"move_forward", "move_back", "move_left", "move_right",
			"strafe_left", "strafe_right", "jump"
		]
		for action in movement_actions:
			if event.is_action_pressed(action):
				return true
	return false


# =============================================================================
# Menu Visibility
# =============================================================================

func show_menu() -> void:
	"""Show the escape menu."""
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Reset button states
	_reset_buttons()
	
	# Re-find references in case they changed
	_find_references()


func hide_menu() -> void:
	"""Hide the escape menu."""
	# Cancel any active countdown
	if _countdown_active:
		_cancel_countdown_silent()
	
	visible = false
	menu_closed.emit()


func _reset_buttons() -> void:
	"""Reset all buttons to their default state."""
	if resume_button:
		resume_button.disabled = false
	if settings_button:
		settings_button.disabled = false
	if sign_out_button:
		sign_out_button.disabled = false
		sign_out_button.text = "Sign Out"
	if quit_button:
		quit_button.disabled = false
		quit_button.text = "Quit Game"


# =============================================================================
# Button Handlers
# =============================================================================

func _on_resume_pressed() -> void:
	"""Resume game - close menu."""
	hide_menu()


func _on_settings_pressed() -> void:
	"""Open settings dialog."""
	if settings_dialog:
		if settings_dialog.has_method("show_dialog"):
			settings_dialog.show_dialog()
		else:
			settings_dialog.visible = true
	else:
		_add_system_message("Settings dialog not found")


func _on_sign_out_pressed() -> void:
	"""Handle sign out button - start countdown or cancel."""
	if _countdown_active and _countdown_action == CountdownAction.SIGN_OUT:
		# Cancel countdown
		_cancel_countdown("Cancelled")
	else:
		# Start countdown
		_start_countdown(CountdownAction.SIGN_OUT, sign_out_button, "Sign Out")


func _on_quit_pressed() -> void:
	"""Handle quit button - start countdown or cancel."""
	if _countdown_active and _countdown_action == CountdownAction.QUIT:
		# Cancel countdown
		_cancel_countdown("Cancelled")
	else:
		# Start countdown
		_start_countdown(CountdownAction.QUIT, quit_button, "Quit Game")


# =============================================================================
# Countdown System
# =============================================================================

func _start_countdown(action: CountdownAction, button: Button, action_name: String) -> void:
	"""Start the countdown for sign out or quit."""
	_countdown_active = true
	_countdown_action = action
	_countdown_remaining = COUNTDOWN_SECONDS
	_original_button_text = button.text
	
	# Disable other buttons
	if resume_button:
		resume_button.disabled = true
	if settings_button:
		settings_button.disabled = true
	
	# Disable the OTHER action button (not the one clicked)
	if action == CountdownAction.SIGN_OUT and quit_button:
		quit_button.disabled = true
	elif action == CountdownAction.QUIT and sign_out_button:
		sign_out_button.disabled = true
	
	# Update button text to show cancel option
	button.text = "Cancel (%d)" % _countdown_remaining
	
	# Send chat message
	var message = "%s in %d..." % [action_name, _countdown_remaining]
	_add_system_message(message)
	
	# Start timer
	countdown_timer.start()


func _on_countdown_tick() -> void:
	"""Handle countdown timer tick."""
	_countdown_remaining -= 1
	
	# Get the active button
	var active_button: Button = null
	var action_name: String = ""
	
	match _countdown_action:
		CountdownAction.SIGN_OUT:
			active_button = sign_out_button
			action_name = "Signing out"
		CountdownAction.QUIT:
			active_button = quit_button
			action_name = "Quitting"
	
	if _countdown_remaining > 0:
		# Update button text
		if active_button:
			active_button.text = "Cancel (%d)" % _countdown_remaining
		
		# Send chat message
		var message = "%s in %d..." % [action_name, _countdown_remaining]
		_add_system_message(message)
	else:
		# Countdown complete - execute action
		countdown_timer.stop()
		_execute_countdown_action()


func _cancel_countdown(reason: String) -> void:
	"""Cancel the countdown and notify user."""
	var action_name = ""
	match _countdown_action:
		CountdownAction.SIGN_OUT:
			action_name = "Sign out"
		CountdownAction.QUIT:
			action_name = "Quit"
	
	_cancel_countdown_silent()
	
	# Send cancellation message
	_add_system_message("%s cancelled - %s" % [action_name, reason])


func _cancel_countdown_silent() -> void:
	"""Cancel the countdown without notification."""
	countdown_timer.stop()
	_countdown_active = false
	_countdown_action = CountdownAction.NONE
	_countdown_remaining = 0
	
	# Reset buttons
	_reset_buttons()


func _execute_countdown_action() -> void:
	"""Execute the countdown action (sign out or quit)."""
	var action = _countdown_action
	
	# Reset state first
	_cancel_countdown_silent()
	
	match action:
		CountdownAction.SIGN_OUT:
			_do_sign_out()
		CountdownAction.QUIT:
			_do_quit()


func _do_sign_out() -> void:
	"""Execute sign out - return to character select."""
	_add_system_message("Signed out")
	hide_menu()
	
	# Close all other dialogs
	UIManager.close_all_dialogs()
	
	# Disconnect from server and go to character select
	if local_player and local_player.has_method("disconnect_from_server"):
		local_player.disconnect_from_server()
	elif game_manager and game_manager.has_method("_change_state"):
		# Fallback: directly change state
		game_manager._change_state(1)  # CHARACTER_SELECT = 1


func _do_quit() -> void:
	"""Execute quit - close the game."""
	_add_system_message("Goodbye!")
	
	# Small delay to show message
	await get_tree().create_timer(0.2).timeout
	
	get_tree().quit()


# =============================================================================
# Damage Detection (for countdown cancellation)
# =============================================================================

func _on_damage_dealt(attacker_id: int, target_id: int, _damage: int, _is_critical: bool) -> void:
	"""Handle damage dealt event - cancel countdown if local player is hit."""
	if not _countdown_active:
		return
	
	# Check if local player was the target
	if local_player and local_player.has_method("get_player_id"):
		var player_id = local_player.get_player_id()
		if target_id == player_id:
			_cancel_countdown("Under attack!")


# =============================================================================
# Chat Integration
# =============================================================================

func _add_system_message(message: String) -> void:
	"""Add a system message to chat."""
	if chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message(message)
	else:
		print("EscapeMenu: ", message)
