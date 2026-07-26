@tool
class_name NpcDefinition
extends Resource
## Everything the NPC Builder saves about one NPC. It is pure data: hand it to
## an NpcCharacter (or the builder's preview) and you get the rigged, coloured,
## talkable villager back.
##
## Authored with the "NPC Builder" tab in the editor; the tool writes one of
## these next to a ready-to-place scene. Editing the .tres by hand works too.
##
## @tool IS LOAD-BEARING, and not because anything here wants to run in the
## editor. When the editor loads a .tres whose script is not a tool script it
## attaches a PLACEHOLDER instance: the exported properties still hold their
## values, but every method call fails with "Attempt to call a method on a
## placeholder instance". So `get_part()` threw for any NPC placed in a level,
## NpcRig collected no parts, and the NPC came out as a correctly proportioned
## skeleton with nothing on it -- while the builder's own preview, whose
## definition is a live `NpcDefinition.new()` rather than a loaded file, looked
## perfect. Same for [NpcPart]: it is reached through these methods.

## Slot order is also stacking order: feet on the ground, body on the feet,
## head on the body. Arms share the body's base -- the arms model is a T-bar
## that overlaps the torso rather than a piece that sits on top of it.
const SLOTS := ["feet", "body", "arms", "head"]

## Armor is a second LAYER over those four, never a fifth slot and never a
## character set of its own. A breastplate is drawn as a shell around the torso
## it was modelled over -- one voxel out on each side, in the same Goxel grid --
## so it has to be worn WITH a body rather than instead of one, and a helmet
## must not make the character taller. Both fall out of it being a layer:
## nothing here feeds the height stack (see NpcRig._layout), and an empty
## model_path is simply "no armor on that slot".
const ARMOR_SLOTS := ["feet_armor", "body_armor", "arms_armor", "head_armor"]

## Every slot, in the order they are rigged -- which is also the order they
## claim voxels: skin first, then the armor laid over it, so a plate model that
## still carries the reference body it was drawn against loses that copy rather
## than z-fighting the real one.
const ALL_SLOTS := ["feet", "body", "arms", "head",
		"feet_armor", "body_armor", "arms_armor", "head_armor"]

## "feet" -> "feet_armor".
static func armor_of(slot: String) -> String:
	return slot + "_armor"

## "feet_armor" -> "feet"; anything else is returned unchanged, so callers can
## ask for "the slot this one is really about" without checking first.
static func covers(slot: String) -> String:
	return slot.trim_suffix("_armor")

static func is_armor(slot: String) -> bool:
	return slot.ends_with("_armor")

@export var display_name := "Villager"

## Key of DialogData.DIALOGS; empty means the NPC is scenery and shows no
## speech-bubble prompt.
@export var dialog_id := ""

## Sole-to-crown height in metres. The voxel size follows from this and the
## parts' own proportions, so every part keeps square voxels.
@export_range(0.5, 3.0, 0.01) var height := 1.85

@export_group("Parts")
@export var feet: NpcPart = NpcPart.new()
@export var body: NpcPart = NpcPart.new()
@export var arms: NpcPart = NpcPart.new()
@export var head: NpcPart = NpcPart.new()

## Worn OVER the four above, each with its own palette and tint, so a suit can
## be recoloured without touching the character inside it. All four empty means
## an unarmoured villager, which is what a new definition is.
@export_group("Armor")
@export var feet_armor: NpcPart = NpcPart.new()
@export var body_armor: NpcPart = NpcPart.new()
@export var arms_armor: NpcPart = NpcPart.new()
@export var head_armor: NpcPart = NpcPart.new()

@export_group("Interaction")
@export var interact_range := 3.5
## Extra lift for the speech bubble above the crown, in metres.
@export var prompt_lift := 0.35

func get_part(slot: String) -> NpcPart:
	match slot:
		"feet": return feet
		"body": return body
		"arms": return arms
		"head": return head
		"feet_armor": return feet_armor
		"body_armor": return body_armor
		"arms_armor": return arms_armor
		"head_armor": return head_armor
	return null

func set_part(slot: String, part: NpcPart) -> void:
	match slot:
		"feet": feet = part
		"body": body = part
		"arms": arms = part
		"head": head = part
		"feet_armor": feet_armor = part
		"body_armor": body_armor = part
		"arms_armor": arms_armor = part
		"head_armor": head_armor = part

## Is there anything on the armor layer at all? The builder's Armor switch and
## the writer both ask this rather than testing four paths by hand.
func wears_armor() -> bool:
	for slot: String in ARMOR_SLOTS:
		var part := get_part(slot)
		if part != null and not part.model_path.is_empty():
			return true
	return false

## Strip the whole armor layer, leaving the character underneath alone.
func clear_armor() -> void:
	for slot: String in ARMOR_SLOTS:
		set_part(slot, NpcPart.new())

## A deep copy -- @export'd sub-resources are shared by reference otherwise, so
## the builder would edit the saved file live.
func copy() -> NpcDefinition:
	var out := NpcDefinition.new()
	out.display_name = display_name
	out.dialog_id = dialog_id
	out.height = height
	out.interact_range = interact_range
	out.prompt_lift = prompt_lift
	for slot: String in ALL_SLOTS:
		out.set_part(slot, get_part(slot).duplicate_part())
	return out
