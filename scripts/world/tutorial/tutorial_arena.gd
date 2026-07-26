class_name TutorialArena
extends Node3D
## One player's private copy of the starter island. It IS the starter island —
## the same Island1 mesh at the same transform, with the spawn marker in the
## same place on it — instanced far to the east and rebuilt per player. You
## wake up somewhere that looks exactly like home, and at the end you are moved
## to the real one.
##
## Instanced by `tutorial_system.gd` on the server, and again on the client
## that is in it at the same coordinates, the same way every peer loads the
## world scene: the ground exists on both peers and only the bandits are
## replicated.
##
## Collision is generated at runtime from the meshes, exactly as `world.gd`
## does for the real island — a glTF ships none, and a copy is no different.
## That is the one real cost of a copy, which is why TutorialData.MAX_SLOTS is
## small: each one is a whole island's worth of trimesh.
##
## Copies sit at the island's own height rather than above it, so the ocean
## (which follows the local player and reaches 3.6km) and the distance fog
## behave exactly as they do at home.

## Whose copy this is. Set by the tutorial system right after instancing.
var owner_peer := 0

## Bandits arrive in a ring this far out.
const BANDIT_RING := 7.5

func _ready() -> void:
	_build_collision()

## A glTF has no collision shapes; the real island grows its own the same way.
func _build_collision() -> void:
	for mi: MeshInstance3D in $Island1.find_children("*", "MeshInstance3D", true, false):
		mi.create_trimesh_collision()

## Where the player wakes up — the island's own spawn marker, in the same spot
## as the real one, so the tutorial starts where the game would.
func player_spawn() -> Vector3:
	return ($Island1/PlayerSpawn as Node3D).global_position

## Bandits come at you from around the spawn. Positions are worked out at
## spawn time and dropped onto the terrain, rather than being markers placed by
## hand — the ground under a copy is a whole island, and a marker hanging in
## the air (or buried) is not something you would notice until a bandit fell
## through the world.
func bandit_spawn(i: int) -> Vector3:
	var ang := float(i) * 2.3999632 # golden angle: a spread-out ring, not a line
	var reach := BANDIT_RING + fposmod(float(i) * 0.618, 1.0) * 3.0
	return _ground_at(player_spawn() + Vector3(cos(ang), 0.0, sin(ang)) * reach)

## Drop a point onto the terrain. Characters are excluded, or someone standing
## on the spot puts the next bandit on their head.
func _ground_at(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
			pos + Vector3.UP * 30.0, pos + Vector3.DOWN * 60.0)
	var skip: Array[RID] = []
	for node in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player"):
		if node is CollisionObject3D:
			skip.append((node as CollisionObject3D).get_rid())
	query.exclude = skip
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return pos
	return hit.position + Vector3.UP * 0.2
