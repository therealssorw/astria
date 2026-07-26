class_name ArmorLibrary
extends RefCounted
## The saved suits on disk: where they live, what is there, and how one is
## written. Both the Items tab (which makes them) and the NPC Builder (which
## wears them) go through here, so neither invents a path of its own.
##
## A SUIT is not the same thing as an armor MODEL SET. `NpcRig.ARMOR_ROOT` holds
## the raw art — the pieces as drawn, in the colours they were drawn in. A suit
## is one of those dressed: pieces chosen, palette overridden, tinted, named,
## and saved as a thing you can put on a character in one move.

const DIR := "res://Assets/Data/Armor/"

## Suit files, as res:// paths, sorted so menus are stable between runs.
static func paths() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for f in DirAccess.get_files_at(DIR):
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if file.get_extension().to_lower() == "tres" and not out.has(DIR + file):
			out.append(DIR + file)
	out.sort()
	return out

## A suit, or null when the file is gone or is not a suit at all. Never trust a
## .tres in the folder to be one: the NPC definitions live one folder over and
## get dragged around.
static func load_suit(path: String) -> ArmorDefinition:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ArmorDefinition

## What to call it in a menu — the suit's own name, falling back to the file so
## a suit saved before it was named is still findable.
static func title_of(path: String) -> String:
	var suit := load_suit(path)
	if suit != null and not suit.display_name.strip_edges().is_empty():
		return suit.display_name
	return path.get_file().get_basename().replace("_", " ").capitalize()

static func slug_for(display_name: String) -> String:
	var out := ""
	for ch in display_name.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges(true, true).trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "armor"

static func path_for(display_name: String) -> String:
	return DIR + slug_for(display_name) + ".tres"

## Writes the suit. Returns {"ok": bool, "message": String}.
static func save(suit: ArmorDefinition) -> Dictionary:
	if not suit.has_pieces():
		return {"ok": false, "message": "Nothing to save — the suit has no pieces on it."}
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := path_for(suit.display_name)
	# Saved as a copy: the builder carries on editing its own working suit, and
	# a save must not leave it writing through to the file afterwards.
	var stored := suit.copy()
	stored.take_over_path(path)
	var err := ResourceSaver.save(stored, path)
	if err != OK:
		return {"ok": false, "message": "Could not write %s (error %d)" % [path, err]}
	return {"ok": true, "message": "Saved %s" % path.get_file()}
