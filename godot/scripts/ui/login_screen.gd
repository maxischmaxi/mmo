extends Control
## Login/Register screen UI controller
## Handles authentication before showing the game

signal login_success(player_id: int)
signal login_started()

@onready var tab_container: TabContainer = $CenterContainer/Panel/VBox/TabContainer
@onready var status_label: Label = $CenterContainer/Panel/VBox/StatusLabel
@onready var server_input: LineEdit = $CenterContainer/Panel/VBox/ServerInfo/ServerInput

# Login tab
@onready var login_username: LineEdit = $CenterContainer/Panel/VBox/TabContainer/Login/UsernameInput
@onready var login_password: LineEdit = $CenterContainer/Panel/VBox/TabContainer/Login/PasswordInput
@onready var login_button: Button = $CenterContainer/Panel/VBox/TabContainer/Login/LoginButton

# Register tab
@onready var register_username: LineEdit = $CenterContainer/Panel/VBox/TabContainer/Register/UsernameInput
@onready var register_password: LineEdit = $CenterContainer/Panel/VBox/TabContainer/Register/PasswordInput
@onready var register_confirm: LineEdit = $CenterContainer/Panel/VBox/TabContainer/Register/ConfirmInput
@onready var register_button: Button = $CenterContainer/Panel/VBox/TabContainer/Register/RegisterButton

## Reference to the player node (set by main scene)
var player_node: Node = null

func _ready() -> void:
	# Clear any status
	status_label.text = ""
	
	# Focus username field on start
	login_username.grab_focus()


func set_player(player: Node) -> void:
	"""Set the player node reference and connect signals."""
	player_node = player
	
	# Connect auth signals
	if player_node.has_signal("login_success"):
		player_node.login_success.connect(_on_player_login_success)
	if player_node.has_signal("login_failed"):
		player_node.login_failed.connect(_on_player_login_failed)
	if player_node.has_signal("register_success"):
		player_node.register_success.connect(_on_player_register_success)
	if player_node.has_signal("register_failed"):
		player_node.register_failed.connect(_on_player_register_failed)
	if player_node.has_signal("connection_failed"):
		player_node.connection_failed.connect(_on_player_connection_failed)


func get_server_address() -> String:
	"""Get the server address from the input field."""
	return server_input.text.strip_edges()


func _on_login_pressed() -> void:
	"""Handle login button press."""
	var username = login_username.text.strip_edges()
	var password = login_password.text
	
	if username.is_empty():
		_show_error("Please enter a username")
		return
	
	if password.is_empty():
		_show_error("Please enter a password")
		return
	
	_set_loading(true)
	_show_status("Logging in...", Color(1, 1, 1))
	
	# Update player's server address
	if player_node:
		player_node.server_address = get_server_address()
		player_node.login(username, password)
	
	login_started.emit()


func _on_login_username_submitted(_text: String) -> void:
	"""Handle Enter key in username field - move to password."""
	login_password.grab_focus()


func _on_login_password_submitted(_text: String) -> void:
	"""Handle Enter key in password field - submit login."""
	_on_login_pressed()


func _on_register_pressed() -> void:
	"""Handle register button press."""
	var username = register_username.text.strip_edges()
	var password = register_password.text
	var confirm = register_confirm.text
	
	if username.length() < 3 or username.length() > 32:
		_show_error("Username must be 3-32 characters")
		return
	
	if password.length() < 4:
		_show_error("Password must be at least 4 characters")
		return
	
	if password != confirm:
		_show_error("Passwords do not match")
		return
	
	_set_loading(true)
	_show_status("Creating account...", Color(1, 1, 1))
	
	# Update player's server address
	if player_node:
		player_node.server_address = get_server_address()
		player_node.register(username, password)


func _on_register_username_submitted(_text: String) -> void:
	"""Handle Enter key in register username field - move to password."""
	register_password.grab_focus()


func _on_register_password_submitted(_text: String) -> void:
	"""Handle Enter key in register password field - move to confirm."""
	register_confirm.grab_focus()


func _on_register_confirm_submitted(_text: String) -> void:
	"""Handle Enter key in confirm password field - submit registration."""
	_on_register_pressed()


func _on_player_login_success(player_id: int) -> void:
	"""Handle successful login."""
	_show_status("Login successful!", Color(0.4, 1, 0.4))
	login_success.emit(player_id)


func _on_player_login_failed(reason: String) -> void:
	"""Handle failed login."""
	_set_loading(false)
	_show_error(reason)


func _on_player_register_success(_player_id: int) -> void:
	"""Handle successful registration."""
	_set_loading(false)
	_show_status("Account created! You can now log in.", Color(0.4, 1, 0.4))
	
	# Copy username to login tab and switch to it
	login_username.text = register_username.text
	login_password.text = ""
	register_password.text = ""
	register_confirm.text = ""
	
	tab_container.current_tab = 0
	login_password.grab_focus()


func _on_player_register_failed(reason: String) -> void:
	"""Handle failed registration."""
	_set_loading(false)
	_show_error(reason)


func _on_player_connection_failed(reason: String) -> void:
	"""Handle connection failure."""
	_set_loading(false)
	_show_error("Connection failed: " + reason)


func _show_error(message: String) -> void:
	"""Show an error message in red."""
	status_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	status_label.text = message


func _show_status(message: String, color: Color = Color.WHITE) -> void:
	"""Show a status message."""
	status_label.add_theme_color_override("font_color", color)
	status_label.text = message


func _set_loading(loading: bool) -> void:
	"""Enable/disable inputs during loading."""
	login_button.disabled = loading
	register_button.disabled = loading
	login_username.editable = not loading
	login_password.editable = not loading
	register_username.editable = not loading
	register_password.editable = not loading
	register_confirm.editable = not loading
	server_input.editable = not loading
