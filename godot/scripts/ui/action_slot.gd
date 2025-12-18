extends Control
class_name ActionSlot
## A single action bar slot for abilities/spells.
## Shows keybind number, can hold an ability icon, and display cooldown.

## The keybind number (1-8)
@export var slot_number: int = 1

## Signals
signal slot_clicked(slot_number: int)
signal slot_right_clicked(slot_number: int)

## UI References
@onready var background: Panel = $Background
@onready var icon: TextureRect = $Icon
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var keybind_label: Label = $KeybindLabel
@onready var highlight: ColorRect = $Highlight

## Ability data (for future use)
var ability_id: int = -1
var is_on_cooldown: bool = false
var cooldown_remaining: float = 0.0
var cooldown_total: float = 0.0


func _ready() -> void:
	# Set up mouse events
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	
	# Set keybind label
	if keybind_label:
		keybind_label.text = str(slot_number)
	
	# Initialize display
	_update_display()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				emit_signal("slot_clicked", slot_number)
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				emit_signal("slot_right_clicked", slot_number)


func _on_mouse_entered() -> void:
	if highlight:
		highlight.visible = true


func _on_mouse_exited() -> void:
	if highlight:
		highlight.visible = false


func _update_display() -> void:
	# Update icon visibility
	if icon:
		icon.visible = ability_id > 0
	
	# Update cooldown overlay
	if cooldown_overlay:
		cooldown_overlay.visible = is_on_cooldown


## Set an ability in this slot (for future use)
func set_ability(id: int, ability_icon: Texture2D = null) -> void:
	ability_id = id
	if icon and ability_icon:
		icon.texture = ability_icon
	_update_display()


## Clear this slot
func clear_ability() -> void:
	ability_id = -1
	if icon:
		icon.texture = null
	_update_display()


## Start cooldown display (for future use)
func start_cooldown(duration: float) -> void:
	is_on_cooldown = true
	cooldown_total = duration
	cooldown_remaining = duration
	_update_display()


## Update cooldown progress (called from _process in parent)
func update_cooldown(delta: float) -> void:
	if not is_on_cooldown:
		return
	
	cooldown_remaining -= delta
	if cooldown_remaining <= 0:
		is_on_cooldown = false
		cooldown_remaining = 0.0
		_update_display()
	else:
		# Update cooldown overlay height based on remaining time
		if cooldown_overlay:
			var progress = cooldown_remaining / cooldown_total
			cooldown_overlay.scale.y = progress


## Check if slot has an ability assigned
func has_ability() -> bool:
	return ability_id > 0


## Get the slot's keybind number
func get_slot_number() -> int:
	return slot_number
