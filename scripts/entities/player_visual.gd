class_name PlayerVisual
extends NpcVisual
## The player's own body: the voxel character built in the NPC Builder as
## "Player", rigged onto the same skeleton and driven by the same clips as
## everybody else in the game.
##
## It is an NpcVisual with two differences, and both are the point:
##
##   * the definition is fixed (DEFINITION) rather than set per instance --
##     which body a player wears is not a level-editing decision, and every
##     pawn in the world, local or remote, is built from that one file. Recolour
##     "Player" in the builder and every player in the game changes with it.
##   * it builds the WHOLE clip library. NpcVisual trims it to idle/walk/run
##     because villagers stand around and never fight; a player blocks, slides,
##     jumps and swings, so it needs every entry in CLIPS.

const DEFINITION := "res://Assets/Data/Npcs/player.tres"

## The armor currently on this body, as ItemDb slot -> item id. Kept so
## `set_armor` can do nothing when nothing changed — re-rigging is a whole
## character rebuilt, and the registry re-syncs on every hotbar press.
var _worn := {}

func _clip_keys() -> Array:
	return CLIPS.keys()

func _build_model() -> void:
	# Set before the rig runs: NpcVisual builds against `definition`, and an
	# unset one is a bare skeleton.
	if definition == null:
		definition = load(DEFINITION) as NpcDefinition
	super()

## Dress this body in what the SERVER says the player has on: `worn` is an
## armor slot -> item id map straight out of the public registry.
##
## Each item names a suit and the plates of it that item is (`ItemDb`), and they
## are hung on the character's own armor layer — the same four slots the NPC
## Builder's "Wears armor" switch fills, so a chestplate here is exactly the
## chestplate a guard would be built with, in the colours the suit was painted.
## Nothing about the body underneath moves: armor rides the bones of what it
## covers and feeds no landmark, so putting a helmet on cannot make anyone
## taller.
##
## Safe to call every frame — it returns immediately unless something changed,
## because the alternative is re-rigging a whole character on every registry
## sync.
func set_armor(worn: Dictionary) -> void:
	if skeleton == null or _same_armor(worn):
		return
	_worn = worn.duplicate()
	var def := (load(DEFINITION) as NpcDefinition).copy()
	def.clear_armor()
	for slot: String in ItemDb.EQUIP_SLOTS:
		var item_id := str(worn.get(slot, ""))
		if item_id == "":
			continue
		var parts := ItemDb.armor_parts(item_id)
		for covered: String in parts:
			# A COPY, for the reason ArmorDefinition.wear documents: handing the
			# character a live reference would let one player's body write back
			# into the shared suit file.
			def.set_part(NpcDefinition.armor_of(covered),
					(parts[covered] as NpcPart).duplicate(true))
	rebuild(def)

func _same_armor(worn: Dictionary) -> bool:
	for slot: String in ItemDb.EQUIP_SLOTS:
		if str(_worn.get(slot, "")) != str(worn.get(slot, "")):
			return false
	return true
