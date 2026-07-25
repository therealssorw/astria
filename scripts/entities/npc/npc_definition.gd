class_name NpcDefinition
extends Resource
## Everything the NPC Builder saves about one NPC. It is pure data: hand it to
## an NpcCharacter (or the builder's preview) and you get the rigged, coloured,
## talkable villager back.
##
## Authored with the "NPC Builder" tab in the editor; the tool writes one of
## these next to a ready-to-place scene. Editing the .tres by hand works too.

## Slot order is also stacking order: feet on the ground, body on the feet,
## head on the body. Arms share the body's base -- the arms model is a T-bar
## that overlaps the torso rather than a piece that sits on top of it.
const SLOTS := ["feet", "body", "arms", "head"]

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
	return null

func set_part(slot: String, part: NpcPart) -> void:
	match slot:
		"feet": feet = part
		"body": body = part
		"arms": arms = part
		"head": head = part

## A deep copy -- @export'd sub-resources are shared by reference otherwise, so
## the builder would edit the saved file live.
func copy() -> NpcDefinition:
	var out := NpcDefinition.new()
	out.display_name = display_name
	out.dialog_id = dialog_id
	out.height = height
	out.interact_range = interact_range
	out.prompt_lift = prompt_lift
	for slot: String in SLOTS:
		out.set_part(slot, get_part(slot).duplicate_part())
	return out
