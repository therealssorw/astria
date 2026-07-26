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
##
## The villager who sees you off at the end is cosmetic, so every peer runs it
## locally and nobody replicates it. It walks toward the pawn of the player
## whose island this is, NOT "the local player" — on the server that pawn
## belongs to somebody else entirely. It is the NPC Builder's `villager.tscn`,
## so recolouring her in the builder recolours her here.

signal villager_arrived

## Whose copy this is. Set by the tutorial system right after instancing.
var owner_peer := 0

## Bandits arrive in a ring this far out, and the villager from a little beyond.
const BANDIT_RING := 7.5
const VILLAGER_START := 16.0
## How close the villager gets before it says its piece.
const VILLAGER_REACH := 2.4
const VILLAGER_SPEED := 3.2

var _villager: Node3D
var _walking := false

func _ready() -> void:
	_villager = $Villager
	_villager.visible = false
	set_process(false)
	_build_collision()

## The villager itself, for the camera to frame while it talks.
func villager() -> Node3D:
	return _villager

func villager_start() -> Vector3:
	return _ground_at(player_spawn() + Vector3(0.6, 0.0, 0.8).normalized() * VILLAGER_START)

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

## Cosmetic: the villager appears and walks over. `villager_arrived` fires once
## it is close enough to talk.
func send_villager() -> void:
	if _walking:
		return
	_villager.global_position = villager_start()
	_villager.visible = true
	_walking = true
	set_process(true)

func _process(delta: float) -> void:
	if not _walking:
		return
	var pawn := _owner_pawn()
	if pawn == null:
		return
	var to := pawn.global_position - _villager.global_position
	to.y = 0.0
	if to.length() <= VILLAGER_REACH:
		_walking = false
		set_process(false)
		_face(pawn)
		villager_arrived.emit()
		return
	var step := to.normalized() * VILLAGER_SPEED * delta
	_villager.global_position = _ground_at(_villager.global_position + step)
	_face(pawn)

func _face(pawn: Node3D) -> void:
	var at := Vector3(pawn.global_position.x, _villager.global_position.y,
			pawn.global_position.z)
	if at.distance_to(_villager.global_position) > 0.05:
		_villager.look_at(at, Vector3.UP)

func _owner_pawn() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p.get("peer_id") == owner_peer:
			return p as Node3D
	return null
