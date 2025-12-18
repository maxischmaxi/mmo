extends Node
class_name UIManagerClass
## Global UI manager for dialog stack management and escape key handling.
## Access via the UIManager autoload singleton.

## Signal emitted when escape menu should be shown
signal escape_menu_requested

## Signal emitted when a dialog is opened
signal dialog_opened(dialog: Control)

## Signal emitted when a dialog is closed
signal dialog_closed(dialog: Control)

## Stack of currently open dialogs (topmost is last)
var _dialog_stack: Array[Control] = []

## All registered dialogs
var _registered_dialogs: Array[Control] = []

## Reference to escape menu (set by EscapeMenu on ready)
var escape_menu: Control = null

## Whether we're currently in game (to enable escape key handling)
var _in_game: bool = false


func _ready() -> void:
	# Process input before other nodes
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	# Only handle escape when in game
	if not _is_in_game():
		return
	
	if event.is_action_pressed("ui_cancel"):
		_handle_escape()
		get_viewport().set_input_as_handled()


func _handle_escape() -> void:
	"""Handle escape key press."""
	if is_any_dialog_open():
		# Close topmost dialog
		close_topmost()
	else:
		# Show escape menu
		if escape_menu and escape_menu.has_method("show_menu"):
			escape_menu.show_menu()
		else:
			escape_menu_requested.emit()


func _is_in_game() -> bool:
	"""Check if we're in the actual game state."""
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and "current_state" in game_manager:
		# GameState.IN_GAME = 3
		return game_manager.current_state == 3
	return false


# =============================================================================
# Dialog Registration
# =============================================================================

func register_dialog(dialog: Control) -> void:
	"""Register a dialog with the UI manager."""
	if dialog not in _registered_dialogs:
		_registered_dialogs.append(dialog)
		
		# Connect visibility changed signal if available
		if dialog.has_signal("visibility_changed"):
			if not dialog.visibility_changed.is_connected(_on_dialog_visibility_changed.bind(dialog)):
				dialog.visibility_changed.connect(_on_dialog_visibility_changed.bind(dialog))


func unregister_dialog(dialog: Control) -> void:
	"""Unregister a dialog from the UI manager."""
	_registered_dialogs.erase(dialog)
	_dialog_stack.erase(dialog)
	
	# Disconnect signal
	if dialog.has_signal("visibility_changed"):
		if dialog.visibility_changed.is_connected(_on_dialog_visibility_changed.bind(dialog)):
			dialog.visibility_changed.disconnect(_on_dialog_visibility_changed.bind(dialog))


func _on_dialog_visibility_changed(dialog: Control) -> void:
	"""Handle dialog visibility changes."""
	if dialog.visible:
		if dialog not in _dialog_stack:
			_dialog_stack.append(dialog)
			dialog_opened.emit(dialog)
	else:
		if dialog in _dialog_stack:
			_dialog_stack.erase(dialog)
			dialog_closed.emit(dialog)


# =============================================================================
# Dialog Stack Management
# =============================================================================

func open_dialog(dialog: Control) -> void:
	"""Open a dialog and add it to the stack."""
	if dialog not in _registered_dialogs:
		register_dialog(dialog)
	
	dialog.visible = true
	
	if dialog not in _dialog_stack:
		_dialog_stack.append(dialog)
		dialog_opened.emit(dialog)


func close_dialog(dialog: Control) -> void:
	"""Close a specific dialog."""
	if dialog.has_method("close_dialog"):
		dialog.close_dialog()
	elif dialog.has_method("close_inventory"):
		dialog.close_inventory()
	elif dialog.has_method("hide_menu"):
		dialog.hide_menu()
	else:
		dialog.visible = false
	
	if dialog in _dialog_stack:
		_dialog_stack.erase(dialog)
		dialog_closed.emit(dialog)


func close_topmost() -> bool:
	"""Close the topmost dialog. Returns true if something was closed."""
	if _dialog_stack.is_empty():
		return false
	
	var topmost = _dialog_stack.back()
	close_dialog(topmost)
	return true


func close_all_dialogs() -> void:
	"""Close all open dialogs."""
	# Work backwards through the stack
	while not _dialog_stack.is_empty():
		close_topmost()


func is_any_dialog_open() -> bool:
	"""Check if any dialog is currently open."""
	# Also check escape menu
	if escape_menu and escape_menu.visible:
		return true
	return not _dialog_stack.is_empty()


func get_topmost_dialog() -> Control:
	"""Get the topmost open dialog, or null if none."""
	if _dialog_stack.is_empty():
		return null
	return _dialog_stack.back()


func is_dialog_open(dialog: Control) -> bool:
	"""Check if a specific dialog is open."""
	return dialog in _dialog_stack


func get_open_dialog_count() -> int:
	"""Get the number of open dialogs."""
	return _dialog_stack.size()


# =============================================================================
# Escape Menu Management
# =============================================================================

func set_escape_menu(menu: Control) -> void:
	"""Set the escape menu reference."""
	escape_menu = menu
	register_dialog(menu)


func show_escape_menu() -> void:
	"""Show the escape menu."""
	if escape_menu:
		if escape_menu.has_method("show_menu"):
			escape_menu.show_menu()
		else:
			escape_menu.visible = true


func hide_escape_menu() -> void:
	"""Hide the escape menu."""
	if escape_menu:
		if escape_menu.has_method("hide_menu"):
			escape_menu.hide_menu()
		else:
			escape_menu.visible = false


func is_escape_menu_open() -> bool:
	"""Check if the escape menu is currently open."""
	return escape_menu and escape_menu.visible
