@tool
extends EditorPlugin

const PackerPanel := preload("res://addons/pbr_texture_packer/packer_panel.gd")

var _packer_panel: Control = null


func _enter_tree() -> void:
	_packer_panel = PackerPanel.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _packer_panel)


func _exit_tree() -> void:
	if _packer_panel:
		remove_control_from_docks(_packer_panel)
		_packer_panel.queue_free()
		_packer_panel = null
