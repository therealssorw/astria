extends Marker3D
class_name QuestAnchor
## Marks where a `QuestData` target actually is, for quests that point at a
## PLACE rather than at somebody. Drop `scenes/world/quest_anchor.tscn` where
## the objective is and set `target_id` to the `"target"` of the quest — the
## same "a marker in a group IS the place" trick `teleport_anchor.gd` and
## `spawn_point.gd` use.
##
## A quest that points at a character needs none of this: put that character in
## the `quest_<target>` group in the scene and the star follows them around.

## The `"target"` field of the QuestData entries this anchor stands for.
@export var target_id := ""

func _enter_tree() -> void:
	if target_id != "":
		add_to_group(QuestData.group(target_id))
