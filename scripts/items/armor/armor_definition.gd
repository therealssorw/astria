@tool
class_name ArmorDefinition
extends Resource
## One suit of armor, saved on its own so it can be worn by any NPC.
##
## It is the same four [NpcPart]s an NPC's armor layer holds — model, palette
## overrides, tint, placement — lifted out of the character and given a name.
## That is the whole point of it existing: a suit coloured once in the Items tab
## is worn by twenty guards, and recolouring the suit is one file rather than
## twenty NPCs.
##
## Authored with the "Items" tab (Create armor); saved to
## `ArmorLibrary.DIR`. Editing the .tres by hand works too.
##
## @tool IS LOAD-BEARING, for exactly the reason [NpcDefinition] documents: the
## editor hands back a PLACEHOLDER instance for a loaded .tres whose script is
## not a tool script, and every method call on it fails. `wear()` is called from
## the builder on a suit loaded off disk, so without this a saved suit would
## come back as a resource that cannot be worn.

@export var display_name := "Armor"

## What it is worn over is fixed by which piece it is, so the fields are named
## for the body, not for the armor: `head` is the helmet.
@export_group("Pieces")
@export var feet: NpcPart = NpcPart.new()
@export var body: NpcPart = NpcPart.new()
@export var arms: NpcPart = NpcPart.new()
@export var head: NpcPart = NpcPart.new()

## Takes either the armor slot ("head_armor") or the slot it covers ("head"),
## so callers never have to convert between the two.
func get_piece(slot: String) -> NpcPart:
	match NpcDefinition.covers(slot):
		"feet": return feet
		"body": return body
		"arms": return arms
		"head": return head
	return null

func set_piece(slot: String, part: NpcPart) -> void:
	match NpcDefinition.covers(slot):
		"feet": feet = part
		"body": body = part
		"arms": arms = part
		"head": head = part

## True once any piece names a model — an empty suit is not worth saving.
func has_pieces() -> bool:
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var piece := get_piece(slot)
		if piece != null and not piece.model_path.is_empty():
			return true
	return false

## Put this suit on an NPC. COPIES, so dressing a character does not hand it a
## live reference to the shared suit — recolouring that NPC afterwards must not
## quietly rewrite the suit file and every other guard wearing it.
func wear(def: NpcDefinition) -> void:
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		def.set_part(slot, get_piece(slot).duplicate_part())

## Read a suit back OFF an NPC, for "make a suit out of what this one is
## wearing".
func take_from(def: NpcDefinition) -> void:
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		set_piece(slot, def.get_part(slot).duplicate_part())

func copy() -> ArmorDefinition:
	var out := ArmorDefinition.new()
	out.display_name = display_name
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		out.set_piece(slot, get_piece(slot).duplicate_part())
	return out
