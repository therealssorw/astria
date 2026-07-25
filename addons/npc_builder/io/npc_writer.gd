@tool
extends RefCounted
## Turns an NpcDefinition into the two files the game actually consumes:
## the definition itself, and a one-node scene wrapping it so an NPC can be
## dragged into a level like any other prop.

const DEFINITION_DIR := "res://Assets/Data/Npcs/"
const SCENE_DIR := "res://scenes/entities/npc/built/"

static func slug_for(display_name: String) -> String:
	var out := ""
	for ch in display_name.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges(true, true).trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "npc"

static func definition_path(display_name: String) -> String:
	return DEFINITION_DIR + slug_for(display_name) + ".tres"

static func scene_path(display_name: String) -> String:
	return SCENE_DIR + slug_for(display_name) + ".tscn"

## Writes both files. Returns {"ok": bool, "message": String}.
static func save(def: NpcDefinition) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(DEFINITION_DIR)
	DirAccess.make_dir_recursive_absolute(SCENE_DIR)
	var res_path := definition_path(def.display_name)
	var tscn_path := scene_path(def.display_name)

	# Saved as a copy: the builder keeps editing its own working definition,
	# and it must not keep mutating the file after a save.
	var stored := def.copy()
	stored.take_over_path(res_path)
	var err := ResourceSaver.save(stored, res_path)
	if err != OK:
		return {"ok": false, "message": "Could not write %s (error %d)" % [res_path, err]}

	var root := NpcCharacter.new()
	root.name = _node_name(def.display_name)
	# Setting `definition` before the node is in a tree only stores it -- the
	# rig is built at load time, so nothing generated gets packed into the file.
	root.definition = stored
	var packed := PackedScene.new()
	err = packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, tscn_path)
	root.free()
	if err != OK:
		return {"ok": false, "message": "Could not write %s (error %d)" % [tscn_path, err]}
	return {"ok": true, "message": "Saved %s and %s" % [res_path.get_file(), tscn_path.get_file()]}

static func _node_name(display_name: String) -> String:
	var out := ""
	for chunk in slug_for(display_name).split("_", false):
		out += chunk.capitalize()
	return out if not out.is_empty() else "Npc"
