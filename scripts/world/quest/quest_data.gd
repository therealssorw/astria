class_name QuestData
extends RefCounted
## Every quest in the game, keyed by id: what it is called, what it points at,
## and who hands it out. Adding one is a single entry here plus something in the
## world wearing the matching group — the HUD marker and the cheat menu build
## themselves from this, so there is no per-quest UI code.
##
## A target is a NAME, not a coordinate, exactly like TeleportData: the marker
## reads the position off whatever is in the group at the moment it draws, so
## moving the place (or the NPC) in the editor moves the star with it. A
## coordinate written into a script goes stale the moment the level is edited.
##
## The target can be anything that is a Node3D — a `QuestAnchor` dropped at a
## place, or a character already standing in the world that joins the group in
## the scene (which is how "meet the blacksmith" points at the blacksmith
## himself rather than at a spot near him).

const QUESTS := {
	"bandit_camp": {
		"name": "Drive off the bandits",
		"target": "bandit_camp",
		## Metres above the target's own origin to aim the star, so it floats
		## over the place instead of sitting inside it.
		"height": 3.0,
		## `dialog_id` of the NPC who gives it out. The server only hands the
		## quest over to a pawn actually standing at that NPC — see
		## `Net._server_start_quest`.
		"from": "blacksmith",
	},
}

static func has(id: String) -> bool:
	return QUESTS.has(id)

## Ids in the order a menu should list them.
static func ids() -> Array:
	return QUESTS.keys()

## Name shown in the HUD heading.
static func label(id: String) -> String:
	if not QUESTS.has(id):
		return id
	return str(QUESTS[id].get("name", id))

## Group the quest's target wears. A `QuestAnchor` joins it from its own
## `_enter_tree`; a character already in the level joins it in the scene.
static func group(target: String) -> String:
	return "quest_" + target

## `dialog_id` of the NPC allowed to give this quest, or "" when nobody does
## (a quest only the cheat menu hands out while it is being built).
static func giver(id: String) -> String:
	if not QUESTS.has(id):
		return ""
	return str(QUESTS[id].get("from", ""))

## Where the star should sit, or null when this quest's target is not in the
## level — a normal answer, not an error: a quest can be written here before
## the place it points at has been built.
static func target_pos(tree: SceneTree, id: String) -> Variant:
	if not QUESTS.has(id):
		return null
	var entry: Dictionary = QUESTS[id]
	for node in tree.get_nodes_in_group(group(str(entry.get("target", "")))):
		if node is Node3D:
			return (node as Node3D).global_position \
					+ Vector3.UP * float(entry.get("height", 0.0))
	return null
