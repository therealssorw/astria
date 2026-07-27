extends Marker3D
class_name TeleportAnchor
## Marks where a named `TeleportData` destination actually is. Drop
## `scenes/world/teleport_anchor.tscn` wherever the place ends up, set
## `destination_id` to the matching key of `TeleportData.DESTINATIONS`, and the
## teleport cheat lands on it — the same "a marker in a group IS the place"
## trick `spawn_point.gd` uses.
##
## Put it roughly where a player should STAND. It does not have to be exactly on
## the floor: `landing_point()` finds the floor under it, so an anchor dragged
## into place by eye still lands the pawn on its feet.

## Key of `TeleportData.DESTINATIONS` this anchor is the place for.
@export var destination_id := "mini_dungeon"

## How far above the marker the floor-finding ray starts. Enough to clear a
## marker sunk slightly into the ground, low enough to stay UNDER a ceiling —
## the catacombs have one, and a ray dropped from high above would find it and
## stand the player on the roof. The same trap `BanditSpawner.head_room`
## documents for a camp pitched under a tent.
const HEAD_ROOM := 1.0
## How far DOWN a floor is still accepted. A landing spot is meant to be roughly
## where the marker is, so this is short on purpose: past it, something is wrong
## with the level rather than with the marker, and dropping the player into a
## hole ten metres down would be worse than leaving them where the marker says.
const MAX_DROP := 12.0
## Stood this far clear of the surface, so the first physics frame settles the
## capsule down rather than starting it inside the floor.
const FOOT_CLEARANCE := 0.08

func _enter_tree() -> void:
	add_to_group(TeleportData.group(destination_id))

## WHERE A PAWN ACTUALLY LANDS: the floor under this marker, not the marker
## itself. Arriving in mid-air was the catacombs bug — the anchor there sits 3 m
## over the dungeon floor, so every entry began with a fall, and a fall is the
## one moment a character can be somewhere the floor is not. It also made the
## arrival read as "falling through the floor", because that is what a 3 m drop
## into a dark room looks like.
##
## Falls back to the marker's own position when there is no floor to find, which
## is the honest answer for a destination whose place is still being built.
func landing_point() -> Vector3:
	if not is_inside_tree():
		return global_position
	var space := get_world_3d().direct_space_state
	if space == null:
		return global_position
	var from := global_position + Vector3.UP * HEAD_ROOM
	var query := PhysicsRayQueryParameters3D.create(from,
			from + Vector3.DOWN * (HEAD_ROOM + MAX_DROP))
	# characters are excluded, or arriving on top of whoever came through first
	# would count as arriving on the floor
	var skip: Array[RID] = []
	for node in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemies"):
		if node is CollisionObject3D:
			skip.append((node as CollisionObject3D).get_rid())
	query.exclude = skip
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return global_position
	return (hit["position"] as Vector3) + Vector3.UP * FOOT_CLEARANCE
