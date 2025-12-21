@tool
extends EditorPlugin

const ExporterPanel := preload("res://addons/server_data_exporter/exporter_panel.gd")

var _exporter_panel: Control = null


func _enter_tree() -> void:
	_exporter_panel = ExporterPanel.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _exporter_panel)


func _exit_tree() -> void:
	if _exporter_panel:
		remove_control_from_docks(_exporter_panel)
		_exporter_panel.queue_free()
		_exporter_panel = null
