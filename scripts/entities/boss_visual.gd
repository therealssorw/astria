class_name BossVisual
extends NpcVisual
## The juggernaut's body: the voxel character saved as "Juggernaut", rigged and
## animated by exactly the machinery every villager and every player uses.
##
## It is an NpcVisual with two differences, and they are the same two the
## player's body has:
##
##   * the definition is FIXED (DEFINITION) rather than set per instance — what
##     the boss looks like is not a level-editing decision, and recolouring it in
##     the NPC Builder recolours every copy in the game.
##   * it builds the WHOLE clip library. NpcVisual trims to idle/walk/run because
##     villagers stand around; this one fights, so it needs the combat clips (and
##     the sword set, because it is carrying a club).
##
## The clips are the shared humanoid ones for now. A dedicated set would be a
## `CLIPS`-style table of its own, imported through the same BoneMap retarget
## every other pack in the project uses — nothing here would change but the paths.
const DEFINITION := "res://Assets/Data/Npcs/juggernaut.tres"

func _clip_keys() -> Array:
	return CLIPS.keys()

func _build_model() -> void:
	# Set before the rig runs: NpcVisual builds against `definition`, and an unset
	# one is a bare skeleton.
	if definition == null:
		definition = load(DEFINITION) as NpcDefinition
	super()

## Phase two: the armour comes off. That is the whole visual read of the phase —
## you can see from across the room which half of the fight you are in — and it
## is a rebuild from the definition MINUS its armor layer rather than anything
## that touches the body underneath, exactly like taking a suit off a player.
##
## Safe to call twice: a definition with no armor left rebuilds to the same thing.
func strip_armor() -> void:
	if skeleton == null or definition == null or not definition.wears_armor():
		return
	var bare := definition.copy()
	bare.clear_armor()
	rebuild(bare)
