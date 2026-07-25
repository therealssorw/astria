@tool
extends EditorPlugin
## Adds the "NPC Builder" tab next to 2D / 3D / Script.

const Screen := preload("res://addons/npc_builder/ui/npc_builder_screen.gd")

var _screen: Control

func _enter_tree() -> void:
	_screen = Screen.new()
	_screen.name = "NpcBuilder"
	EditorInterface.get_editor_main_screen().add_child(_screen)
	_screen.hide()

func _exit_tree() -> void:
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "NPC Builder"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Skeleton3D", &"EditorIcons")

func _make_visible(next: bool) -> void:
	if is_instance_valid(_screen):
		_screen.visible = next
