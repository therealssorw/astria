class_name NpcPartLibrary
## WHERE THE ART IS. The folder layout voxel parts and armor plates are filed
## under, and the listing every menu builds itself from. Split out of NpcRig
## because none of it rigs anything — it is a directory walk, and it is what
## the builder tabs call fifty times while nothing is being rigged at all.
##
## There is no metadata and no registry: drop a Goxel glTF export into the right
## folder and it is offered. That is the whole contract.

const PARTS_ROOT := "res://Assets/Models/Entity/Humanoid/VoxelNpc/Parts/"
## Armor lives in its OWN library rather than as another character set. A suit
## is not a family of villager: filed under Parts/ it would show up in the set
## picker, and "use whole set" would build a walking empty suit with no head,
## no hands and no one inside it.
const ARMOR_ROOT := "res://Assets/Models/Entity/Humanoid/VoxelNpc/Armor/"
const MODEL_EXTS := ["gltf", "glb", "obj", "res", "scn", "tscn"]

static func root(armor: bool) -> String:
	return ARMOR_ROOT if armor else PARTS_ROOT

## Part models are filed Parts/<Category>/<Slot>/, so a whole character family
## ("Base", "Undead", ...) is one folder and shows up in the builder as its own
## section. Slots can still be mixed across categories.
static func list_categories(armor := false) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := root(armor)
	if DirAccess.dir_exists_absolute(dir):
		for d in DirAccess.get_directories_at(dir):
			out.append(d)
	out.sort()
	return out

## The sets a given slot can be filled from: armor suits for an armor slot,
## character families for a skin one. Menus ask this instead of choosing a
## library themselves, which is what keeps a helmet out of the head picker.
static func categories_for(slot: String) -> PackedStringArray:
	return list_categories(NpcDefinition.is_armor(slot))

## An armor slot's models sit in its OWN library under the folder of the slot
## they cover — Armor/<Suit>/Head/ holds what goes over Parts/<Set>/Head/.
static func slot_dir(category: String, slot: String) -> String:
	return "%s%s/%s/" % [root(NpcDefinition.is_armor(slot)), category,
			NpcDefinition.covers(slot).capitalize()]

## Every model available for a slot, as res:// paths; all categories unless one
## is named. Editor-side only — a built NPC stores the path it chose and loads
## that directly.
static func list_parts(slot: String, category := "") -> PackedStringArray:
	var out := PackedStringArray()
	var categories := PackedStringArray([category]) if category != "" else categories_for(slot)
	for cat in categories:
		var dir := slot_dir(cat, slot)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			var file := f.trim_suffix(".import").trim_suffix(".remap")
			if file.get_extension().to_lower() in MODEL_EXTS and not out.has(dir + file):
				out.append(dir + file)
	return out

static func category_of(model_path: String) -> String:
	for r in [PARTS_ROOT, ARMOR_ROOT]:
		if model_path.begins_with(r):
			return model_path.trim_prefix(r).get_slice("/", 0)
	return ""

## What a slot's mesh is called under the skeleton: "feet" -> "Feet",
## "feet_armor" -> "FeetArmor". NOT String.capitalize(), which turns the second
## one into "Feet Armor" — a name with a space in it no longer says which slot
## it came from, and finding a part by its slot is how everything downstream
## (the tests, anything reaching for a piece) does it.
static func mesh_name(slot: String) -> String:
	var out := ""
	for chunk in slot.split("_", false):
		out += chunk.substr(0, 1).to_upper() + chunk.substr(1)
	return out

## "skeleton_head.gltf" -> "Skeleton Head", for menus.
static func part_title(model_path: String) -> String:
	return model_path.get_file().get_basename().replace("_", " ").capitalize()
