extends Control
class_name ActionSlot
## A single action bar slot for abilities/spells.
## Shows keybind number, ability name, mana cost, and cooldown.

## The keybind number (1-8)
@export var slot_number: int = 1

## Signals
signal slot_clicked(slot_number: int)
signal slot_right_clicked(slot_number: int)

## UI References
@onready var background: Panel = $Background
@onready var icon: TextureRect = $Icon
@onready var ability_label: Label = $AbilityLabel
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var cooldown_label: Label = $CooldownLabel
@onready var mana_label: Label = $ManaLabel
@onready var keybind_label: Label = $KeybindLabel
@onready var highlight: ColorRect = $Highlight
@onready var use_flash: ColorRect = $UseFlash

## Ability data
var ability_id: int = -1
var ability_name: String = ""
var ability_description: String = ""
var mana_cost: int = 0
var ability_cooldown: float = 0.0
var ability_range: float = 0.0
var ability_target_type: String = ""
var is_on_cooldown: bool = false
var cooldown_remaining: float = 0.0
var cooldown_total: float = 0.0

## Flash animation
var flash_timer: float = 0.0
const FLASH_DURATION: float = 0.15


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


func _process(delta: float) -> void:
	# Handle flash animation
	if flash_timer > 0:
		flash_timer -= delta
		if flash_timer <= 0:
			if use_flash:
				use_flash.visible = false
		else:
			# Fade out the flash
			if use_flash:
				use_flash.modulate.a = flash_timer / FLASH_DURATION


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
	# Update icon visibility (for future use with actual icons)
	if icon:
		icon.visible = ability_id > 0 and icon.texture != null
	
	# Update ability name label
	if ability_label:
		if ability_id > 0 and ability_name != "":
			ability_label.visible = true
			# Shorten long names
			var display_name = ability_name
			if display_name.length() > 8:
				# Try to abbreviate
				display_name = _abbreviate_name(display_name)
			ability_label.text = display_name
		else:
			ability_label.visible = false
	
	# Update mana cost label
	if mana_label:
		if ability_id > 0 and mana_cost > 0:
			mana_label.visible = true
			mana_label.text = str(mana_cost)
		else:
			mana_label.visible = false
	
	# Update cooldown overlay
	if cooldown_overlay:
		cooldown_overlay.visible = is_on_cooldown


## Abbreviate long ability names
func _abbreviate_name(name: String) -> String:
	# Common abbreviations
	var abbrevs = {
		"Power Strike": "PWR",
		"Recuperate": "REC",
		"Shadow Strike": "SHD",
		"Poison Blade": "PSN",
		"Crushing Blow": "CRSH",
		"Battle Cry": "CRY",
		"Dark Slash": "DRK",
		"Life Drain": "DRN",
		"Lightning Bolt": "LTN",
		"Healing Wave": "HEAL",
	}
	if abbrevs.has(name):
		return abbrevs[name]
	# Default: first 4 chars
	return name.substr(0, 4).to_upper()


## Set ability data in this slot
func set_ability_data(id: int, name: String, cost: int, ability_icon: Texture2D = null) -> void:
	ability_id = id
	ability_name = name
	mana_cost = cost
	if icon and ability_icon:
		icon.texture = ability_icon
	_update_display()


## Set full ability data including tooltip info
func set_full_ability_data(data: Dictionary) -> void:
	ability_id = data.get("id", -1)
	ability_name = data.get("name", "")
	ability_description = data.get("description", "")
	mana_cost = data.get("mana_cost", 0)
	ability_cooldown = data.get("cooldown", 0.0)
	ability_range = data.get("range", 0.0)
	ability_target_type = data.get("target_type", "")
	
	# Update tooltip
	_update_tooltip()
	_update_display()


## Update the tooltip text
func _update_tooltip() -> void:
	if ability_id <= 0:
		tooltip_text = ""
		return
	
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % ability_name)
	
	if ability_description != "":
		lines.append(ability_description)
	
	var stats: Array[String] = []
	if mana_cost > 0:
		stats.append("%d Mana" % mana_cost)
	if ability_cooldown > 0:
		stats.append("%.0fs CD" % ability_cooldown)
	if ability_range > 0:
		stats.append("%.0f Range" % ability_range)
	
	if stats.size() > 0:
		lines.append(" | ".join(stats))
	
	# Target type info
	match ability_target_type:
		"enemy":
			lines.append("Requires enemy target")
		"self":
			lines.append("Self-cast")
		"ally":
			lines.append("Requires friendly target")
	
	tooltip_text = "\n".join(lines)


## Set an ability in this slot (legacy method)
func set_ability(id: int, ability_icon: Texture2D = null) -> void:
	ability_id = id
	if icon and ability_icon:
		icon.texture = ability_icon
	_update_display()


## Clear this slot
func clear_ability() -> void:
	ability_id = -1
	ability_name = ""
	ability_description = ""
	mana_cost = 0
	ability_cooldown = 0.0
	ability_range = 0.0
	ability_target_type = ""
	if icon:
		icon.texture = null
	is_on_cooldown = false
	cooldown_remaining = 0.0
	cooldown_total = 0.0
	tooltip_text = ""
	_update_display()


## Start cooldown display
func start_cooldown(duration: float) -> void:
	is_on_cooldown = true
	cooldown_total = duration
	cooldown_remaining = duration
	_update_display()


## Update cooldown progress (called from _process in parent)
func update_cooldown(delta: float) -> void:
	if not is_on_cooldown:
		if cooldown_label:
			cooldown_label.visible = false
		return
	
	cooldown_remaining -= delta
	if cooldown_remaining <= 0:
		is_on_cooldown = false
		cooldown_remaining = 0.0
		if cooldown_label:
			cooldown_label.visible = false
		_update_display()
	else:
		# Update cooldown overlay size based on remaining time
		if cooldown_overlay:
			cooldown_overlay.visible = true
			var progress = cooldown_remaining / cooldown_total if cooldown_total > 0 else 0
			# Scale from top down (anchor at top, scale Y)
			cooldown_overlay.anchor_top = 0
			cooldown_overlay.anchor_bottom = progress
			cooldown_overlay.offset_top = 0
			cooldown_overlay.offset_bottom = 0
		
		# Update cooldown text
		if cooldown_label:
			cooldown_label.visible = true
			if cooldown_remaining >= 1.0:
				cooldown_label.text = str(int(ceil(cooldown_remaining)))
			else:
				cooldown_label.text = "%.1f" % cooldown_remaining


## Trigger use flash effect
func trigger_use_flash() -> void:
	if use_flash:
		use_flash.visible = true
		use_flash.modulate.a = 1.0
		flash_timer = FLASH_DURATION


## Check if slot has an ability assigned
func has_ability() -> bool:
	return ability_id > 0


## Get the slot's keybind number
func get_slot_number() -> int:
	return slot_number
