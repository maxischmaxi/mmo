extends Control
## Login/Register screen UI controller
## Handles authentication before showing the game

signal login_success(player_id: int)
signal login_started()

## Hardcoded server address (localhost for development)
const SERVER_ADDRESS = "127.0.0.1"

## Colors for UI theming
const COLOR_ACTIVE = Color(0.83, 0.66, 0.29)  # Gold
const COLOR_INACTIVE = Color(0.6, 0.53, 0.4)  # Muted
const COLOR_ERROR = Color(0.91, 0.33, 0.33)   # Red
const COLOR_SUCCESS = Color(0.33, 0.91, 0.48) # Green

# Node references - Tab system
@onready var login_tab_btn: Button = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/TabSection/TabButtons/LoginTabBtn
@onready var register_tab_btn: Button = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/TabSection/TabButtons/RegisterTabBtn
@onready var tab_indicator: ColorRect = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/TabSection/TabIndicator

# Node references - Forms
@onready var login_form: VBoxContainer = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/LoginForm
@onready var register_form: VBoxContainer = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/RegisterForm
@onready var status_label: Label = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/StatusLabel

# Node references - Login inputs
@onready var login_username: LineEdit = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/LoginForm/UsernameField/UsernameContainer/UsernameInput
@onready var login_password: LineEdit = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/LoginForm/PasswordField/PasswordContainer/PasswordInput
@onready var login_button: Button = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/LoginForm/LoginButton

# Node references - Login input containers (for focus styling)
@onready var login_username_container: PanelContainer = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/LoginForm/UsernameField/UsernameContainer
@onready var login_password_container: PanelContainer = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/LoginForm/PasswordField/PasswordContainer

# Node references - Register inputs
@onready var register_username: LineEdit = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/RegisterForm/UsernameField/UsernameContainer/UsernameInput
@onready var register_password: LineEdit = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/RegisterForm/PasswordField/PasswordContainer/PasswordInput
@onready var register_confirm: LineEdit = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/RegisterForm/ConfirmField/ConfirmContainer/ConfirmInput
@onready var register_button: Button = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/RegisterForm/RegisterButton

# Node references - Register input containers (for focus styling)
@onready var register_username_container: PanelContainer = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/RegisterForm/UsernameField/UsernameContainer
@onready var register_password_container: PanelContainer = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/RegisterForm/PasswordField/PasswordContainer
@onready var register_confirm_container: PanelContainer = $ContentContainer/MainVBox/LoginPanel/PanelMargin/PanelVBox/FormContainer/RegisterForm/ConfirmField/ConfirmContainer

# Node references - Particles
@onready var particle_effect: GPUParticles2D = $ParticleEffect

## Reference to the player node (set by main scene)
var player_node: Node = null

## Currently active tab (0 = Login, 1 = Register)
var current_tab: int = 0

## StyleBox for normal input state
var normal_input_style: StyleBoxFlat
## StyleBox for focused input state
var focused_input_style: StyleBoxFlat

## Settings key for remembering last username
const SETTINGS_SECTION := "auth"
const SETTINGS_KEY_USERNAME := "last_username"


func _ready() -> void:
	# Clear any status
	status_label.text = ""
	
	# Setup input focus styles
	_setup_input_styles()
	
	# Connect focus signals for all inputs
	_connect_focus_signals()
	
	# Setup particle effect
	_setup_particles()
	
	# Load last used username
	_load_last_username()
	
	# Focus appropriate field on start
	if login_username.text.is_empty():
		login_username.grab_focus()
	else:
		login_password.grab_focus()


func _setup_input_styles() -> void:
	"""Create stylebox resources for input focus effects."""
	# Normal style (copy from existing)
	normal_input_style = StyleBoxFlat.new()
	normal_input_style.bg_color = Color(0.03, 0.04, 0.06, 0.9)
	normal_input_style.set_border_width_all(1)
	normal_input_style.border_color = Color(0.29, 0.25, 0.21)
	normal_input_style.set_corner_radius_all(4)
	normal_input_style.set_content_margin_all(0)
	normal_input_style.content_margin_left = 10
	normal_input_style.content_margin_right = 10
	normal_input_style.content_margin_top = 8
	normal_input_style.content_margin_bottom = 8
	
	# Focused style (gold border)
	focused_input_style = StyleBoxFlat.new()
	focused_input_style.bg_color = Color(0.03, 0.04, 0.06, 0.9)
	focused_input_style.set_border_width_all(2)
	focused_input_style.border_color = Color(0.83, 0.66, 0.29)  # Gold
	focused_input_style.set_corner_radius_all(4)
	focused_input_style.set_content_margin_all(0)
	focused_input_style.content_margin_left = 10
	focused_input_style.content_margin_right = 10
	focused_input_style.content_margin_top = 8
	focused_input_style.content_margin_bottom = 8


func _connect_focus_signals() -> void:
	"""Connect focus entered/exited signals for all input fields."""
	# Login form inputs
	login_username.focus_entered.connect(_on_input_focus_entered.bind(login_username_container))
	login_username.focus_exited.connect(_on_input_focus_exited.bind(login_username_container))
	login_password.focus_entered.connect(_on_input_focus_entered.bind(login_password_container))
	login_password.focus_exited.connect(_on_input_focus_exited.bind(login_password_container))
	
	# Register form inputs
	register_username.focus_entered.connect(_on_input_focus_entered.bind(register_username_container))
	register_username.focus_exited.connect(_on_input_focus_exited.bind(register_username_container))
	register_password.focus_entered.connect(_on_input_focus_entered.bind(register_password_container))
	register_password.focus_exited.connect(_on_input_focus_exited.bind(register_password_container))
	register_confirm.focus_entered.connect(_on_input_focus_entered.bind(register_confirm_container))
	register_confirm.focus_exited.connect(_on_input_focus_exited.bind(register_confirm_container))


func _setup_particles() -> void:
	"""Configure the particle system for floating ember effect."""
	var material = ParticleProcessMaterial.new()
	
	# Emission from bottom of screen, spreading across width
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(get_viewport().get_visible_rect().size.x / 2, 50, 0)
	
	# Direction: upward with slight spread
	material.direction = Vector3(0, -1, 0)
	material.spread = 15.0
	
	# Velocity
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 40.0
	
	# Gravity (slight upward float)
	material.gravity = Vector3(0, -5, 0)
	
	# Scale variation
	material.scale_min = 2.0
	material.scale_max = 6.0
	
	# Color with fade out
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.83, 0.58, 0.29, 1.0))  # Gold/amber
	gradient.set_color(1, Color(0.83, 0.58, 0.29, 0.0))  # Fade to transparent
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	particle_effect.process_material = material
	particle_effect.position = Vector2(get_viewport().get_visible_rect().size.x / 2, get_viewport().get_visible_rect().size.y + 50)


func _on_input_focus_entered(container: PanelContainer) -> void:
	"""Apply focused style when input gains focus."""
	container.add_theme_stylebox_override("panel", focused_input_style)


func _on_input_focus_exited(container: PanelContainer) -> void:
	"""Apply normal style when input loses focus."""
	container.add_theme_stylebox_override("panel", normal_input_style)


func _switch_tab(index: int) -> void:
	"""Switch between login and register tabs with animation."""
	current_tab = index
	
	# Animate tab indicator
	var tween = create_tween()
	var target_x = 0.0 if index == 0 else login_tab_btn.size.x
	tween.tween_property(tab_indicator, "position:x", target_x, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# Update tab button colors
	login_tab_btn.add_theme_color_override("font_color", COLOR_ACTIVE if index == 0 else COLOR_INACTIVE)
	register_tab_btn.add_theme_color_override("font_color", COLOR_ACTIVE if index == 1 else COLOR_INACTIVE)
	
	# Show/hide forms
	login_form.visible = (index == 0)
	register_form.visible = (index == 1)
	
	# Clear status when switching tabs
	status_label.text = ""
	
	# Focus first input of active form
	if index == 0:
		login_username.grab_focus()
	else:
		register_username.grab_focus()


func _on_login_tab_pressed() -> void:
	"""Handle login tab button press."""
	_switch_tab(0)


func _on_register_tab_pressed() -> void:
	"""Handle register tab button press."""
	_switch_tab(1)


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
	_show_status("Connecting...", Color.WHITE)
	
	# Update player's server address and attempt login
	if player_node:
		player_node.server_address = SERVER_ADDRESS
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
	_show_status("Creating account...", Color.WHITE)
	
	# Update player's server address and attempt registration
	if player_node:
		player_node.server_address = SERVER_ADDRESS
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
	_show_status("Login successful!", COLOR_SUCCESS)
	
	# Save the username for next time
	_save_last_username(login_username.text.strip_edges())
	
	login_success.emit(player_id)


func _on_player_login_failed(reason: String) -> void:
	"""Handle failed login."""
	_set_loading(false)
	_show_error(reason)


func _on_player_register_success(_player_id: int) -> void:
	"""Handle successful registration."""
	_set_loading(false)
	_show_status("Account created! You can now log in.", COLOR_SUCCESS)
	
	# Copy username to login tab and switch to it
	login_username.text = register_username.text
	login_password.text = ""
	register_password.text = ""
	register_confirm.text = ""
	
	_switch_tab(0)
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
	status_label.add_theme_color_override("font_color", COLOR_ERROR)
	status_label.text = message


func _show_status(message: String, color: Color = Color.WHITE) -> void:
	"""Show a status message."""
	status_label.add_theme_color_override("font_color", color)
	status_label.text = message


func _set_loading(loading: bool) -> void:
	"""Enable/disable inputs during loading and update button text."""
	login_button.disabled = loading
	register_button.disabled = loading
	login_username.editable = not loading
	login_password.editable = not loading
	register_username.editable = not loading
	register_password.editable = not loading
	register_confirm.editable = not loading
	
	# Update button text to show loading state
	if loading:
		if current_tab == 0:
			login_button.text = "CONNECTING..."
		else:
			register_button.text = "CONNECTING..."
	else:
		login_button.text = "ENTER REALM"
		register_button.text = "CREATE ACCOUNT"


func _load_last_username() -> void:
	"""Load the last used username from settings."""
	var last_username = SettingsManager.get_setting(SETTINGS_SECTION, SETTINGS_KEY_USERNAME, "")
	if not last_username.is_empty():
		login_username.text = last_username


func _save_last_username(username: String) -> void:
	"""Save the username to settings for next time."""
	SettingsManager.set_setting(SETTINGS_SECTION, SETTINGS_KEY_USERNAME, username)
	SettingsManager.save_settings()


func clear_form() -> void:
	"""Clear all form fields except username, and reset UI state.
	Called when returning to login screen from character select."""
	# Guard against being called before @onready vars are initialized
	if not is_node_ready():
		return
	
	# Clear passwords (but keep username for convenience)
	login_password.text = ""
	register_username.text = ""
	register_password.text = ""
	register_confirm.text = ""
	
	# Clear status
	status_label.text = ""
	
	# Reset loading state
	_set_loading(false)
	
	# Switch to login tab
	_switch_tab(0)
	
	# Focus password field if username is filled, otherwise username
	if login_username.text.is_empty():
		login_username.grab_focus()
	else:
		login_password.grab_focus()
