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

func _clip_keys() -> Array:
	return CLIPS.keys()

func _build_model() -> void:
	# Set before the rig runs: NpcVisual builds against `definition`, and an
	# unset one is a bare skeleton.
	if definition == null:
		definition = load(DEFINITION) as NpcDefinition
	super()
