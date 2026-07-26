class_name TeleportData
extends RefCounted
## The places the teleport cheat can send you, keyed by id. Adding one is a
## single entry here plus a `TeleportAnchor` dropped in the world — the cheat
## menu builds its list from this, so there is no per-destination UI code.
##
## A destination is a NAME, not a coordinate: the position comes from the
## anchor in the world at the time you use it, so moving the place in the
## editor moves the teleport with it. Nothing is hardcoded here because a
## coordinate in a script goes stale the moment the level is edited.

const DESTINATIONS := {
	"mini_dungeon": {"name": "Mini dungeon"},
	## Inside the catacombs, a few steps in from the door. What the entrance
	## `Portal` on the island sends you to, and listed here so the cheat menu
	## can get there without the walk.
	"catacombs": {"name": "Catacombs"},
	## Back out on the island, beside the catacombs door. The return `Portal`
	## down in the dungeon points at this, which is what stops the place being
	## a hole you cannot climb out of.
	"catacombs_exit": {"name": "Catacombs entrance"},
}

static func has(id: String) -> bool:
	return DESTINATIONS.has(id)

## Ids in the order the menu should list them.
static func ids() -> Array:
	return DESTINATIONS.keys()

static func label(id: String) -> String:
	if not DESTINATIONS.has(id):
		return id
	return str(DESTINATIONS[id].get("name", id))

## Group a `TeleportAnchor` for `id` puts itself in.
static func group(id: String) -> String:
	return "teleport_" + id

## The anchor for `id`, or null when that place is not in the world yet —
## which is a normal answer, not an error: a destination can be listed here
## before the level it belongs to has been built.
static func anchor(tree: SceneTree, id: String) -> Node3D:
	for node in tree.get_nodes_in_group(group(id)):
		if node is Node3D:
			return node as Node3D
	return null
