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

## How far out the first bandit arrives, and the villager from a little beyond.
const BANDIT_RING := 7.5
## Reinforcements arrive CLOSER than that. They turn up in the middle of a fight
## the player is already winning, so they have to be on you rather than a walk
## away — at the first bandit's distance the raid arriving read as three figures
## standing about in the distance.
const REINFORCEMENT_RING := 5.0
## Half-width of the arc a wave is spread across, centred on where the player is
## looking. The camera's horizontal field is about 100 degrees at this FOV, so
## this keeps every bandit of a wave ON SCREEN as it arrives. They used to be
## dealt around a full ring by golden angle, which put some of them squarely
## behind you — an enemy you never saw arrive is not a lesson, it is an ambush.
const WAVE_ARC_DEG := 32.0
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

## A glTF has no collision shapes; the real island grows its own the same way —
## the same function, so a copy of the island can never end up with a different
## floor from the island.
func _build_collision() -> void:
	IslandWorld.grow_collision($Island1)

## Where the player wakes up — the island's own spawn marker, in the same spot
## as the real one, so the tutorial starts where the game would.
func player_spawn() -> Vector3:
	return ($Island1/PlayerSpawn as Node3D).global_position

## Where a wave of `count` bandits arrives: spread across an arc IN FRONT of
## `facing`, `reach` away from `from`, so the player watches them turn up instead
## of discovering one behind them. A single bandit lands dead ahead.
##
## Measured off where the player actually IS and which way they are looking, not
## off the spawn marker: reinforcements come after a duel the player has been
## circling through, and by then the marker is wherever they happened to start.
##
## Positions are worked out at spawn time and dropped onto the terrain rather
## than placed as markers by hand — the ground under a copy is a whole island,
## and a marker left hanging in the air (or buried) is not something you would
## notice until a bandit fell through the world.
func wave_spawns(count: int, from: Vector3, facing: Vector3, reach: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	var base := atan2(flat.x, flat.z)
	var arc := deg_to_rad(WAVE_ARC_DEG)
	for i in count:
		# -arc .. +arc across the wave; one on its own goes straight ahead
		var t := 0.0 if count <= 1 else (float(i) / float(count - 1)) * 2.0 - 1.0
		var ang := base + t * arc
		out.append(_ground_at(from + Vector3(sin(ang), 0.0, cos(ang)) * reach))
	return out

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

## Turn her toward the player. NOT look_at: that points a node's -Z at the
## target, and these rigs are modelled facing +Z, so look_at walked her over
## backwards and then talked to the player with her back turned. Same yaw as
## Enemy.face_toward, +PI and all.
func _face(pawn: Node3D) -> void:
	var to := pawn.global_position - _villager.global_position
	to.y = 0.0
	if to.length_squared() < 0.0025:
		return
	_villager.rotation.y = atan2(-to.x, -to.z) + PI

func _owner_pawn() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p.get("peer_id") == owner_peer:
			return p as Node3D
	return null
