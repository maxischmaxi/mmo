extends CanvasLayer
## Death dialog shown when the player dies.
## Allows respawning at empire spawn (full HP) or at death location (20% HP).

signal respawn_at_spawn  ## Player chose to respawn at empire spawn
signal revive_here       ## Player chose to revive at death location

const COUNTDOWN_SECONDS := 3

@onready var countdown_label: Label = $CenterContainer/Panel/VBoxContainer/Countdown
@onready var restart_button: Button = $CenterContainer/Panel/VBoxContainer/ButtonContainer/RestartAtSpawn
@onready var revive_button: Button = $CenterContainer/Panel/VBoxContainer/ButtonContainer/ReviveHere
@onready var countdown_timer: Timer = $CountdownTimer

var _countdown_remaining: int = COUNTDOWN_SECONDS


func _ready() -> void:
	# Start hidden
	hide_dialog()


## Show the death dialog and start countdown
func show_dialog() -> void:
	visible = true
	_countdown_remaining = COUNTDOWN_SECONDS
	countdown_label.text = str(_countdown_remaining)
	
	# Disable buttons during countdown
	restart_button.disabled = true
	revive_button.disabled = true
	
	# Start countdown timer
	countdown_timer.start()
	
	# Capture mouse for UI
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Hide the death dialog
func hide_dialog() -> void:
	visible = false
	countdown_timer.stop()


func _on_countdown_timer_timeout() -> void:
	_countdown_remaining -= 1
	
	if _countdown_remaining > 0:
		countdown_label.text = str(_countdown_remaining)
	else:
		countdown_label.text = "Choose your respawn"
		countdown_timer.stop()
		
		# Enable buttons
		restart_button.disabled = false
		revive_button.disabled = false


func _on_restart_at_spawn_pressed() -> void:
	hide_dialog()
	respawn_at_spawn.emit()


func _on_revive_here_pressed() -> void:
	hide_dialog()
	revive_here.emit()
