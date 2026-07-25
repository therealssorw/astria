extends Marker3D
class_name TeleportAnchor
## Marks where a named `TeleportData` destination actually is. Drop
## `scenes/world/teleport_anchor.tscn` wherever the place ends up, set
## `destination_id` to the matching key of `TeleportData.DESTINATIONS`, and the
## teleport cheat lands on it — the same "a marker in a group IS the place"
## trick `spawn_point.gd` uses.
##
## Put it where a player should STAND: the pawn is dropped on this exact spot.

## Key of `TeleportData.DESTINATIONS` this anchor is the place for.
@export var destination_id := "mini_dungeon"

func _enter_tree() -> void:
	add_to_group(TeleportData.group(destination_id))
