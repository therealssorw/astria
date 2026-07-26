@tool
extends Node3D
class_name Portal
## Walk into it and you come out somewhere else: a doorway between two places
## that are nowhere near each other in the level.
##
## The destination is a NAME, never a coordinate — the same "a marker in a
## group IS the place" trick as `TeleportAnchor`, `QuestAnchor` and
## `spawn_point.gd`. So a portal points at a `TeleportData` id, the landing spot
## is whatever `TeleportAnchor` wears that id, and moving either end in the
## editor moves it. Nothing here knows where anything is.
##
## SERVER-AUTHORITATIVE, like every other way a pawn moves. The server watches
## its OWN copy of each pawn (the position it has already speed-validated),
## decides who went through, moves its copy and tells the owner where it now is.
## A client is never asked and never believed: it cannot walk through a portal
## it is standing nowhere near, and it cannot refuse to go through one it did.
##
## Deliberately NOT an Area3D. A trigger volume answers "is a body touching my
## shape", which needs the pawn on the right collision layer and reports on the
## CLIENT too, where the answer means nothing. A distance against the server's
## own copy is the thing actually being asked, and it is one line.

## Key of `TeleportData.DESTINATIONS` to send players to.
@export var destination_id := ""

## How close counts as walking in, in metres.
@export var radius := 3.5

## How far above or below the portal still counts, so a doorway on a slope
## still works and one you walk over on a bridge does not.
@export var height := 4.0

## Peers seen OUTSIDE the radius at least once, which is what makes a player
## ARRIVING inside a portal not immediately go back through it. A return
## portal and the anchor players land on are near each other by nature, and
## without this the two ends bounce a player between them forever. Walking up
## to a portal is always seen from outside first, so the ordinary case is
## unaffected.
var _seen_outside := {}

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not multiplayer.is_server():
		return
	if destination_id == "":
		return
	for pawn in get_tree().get_nodes_in_group("player"):
		if not pawn is Node3D or pawn.dead:
			continue
		var id: int = pawn.peer_id
		var to: Vector3 = (pawn as Node3D).global_position - global_position
		var near := Vector2(to.x, to.z).length() <= radius and absf(to.y) <= height
		if not near:
			_seen_outside[id] = true
			continue
		if not _seen_outside.get(id, false):
			continue  # arrived inside it rather than walked into it
		_seen_outside[id] = false
		Net.server_teleport_to(id, destination_id)
