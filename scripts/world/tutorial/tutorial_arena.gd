class_name TutorialArena
extends Node3D
## One player's private copy of the tutorial city. Instanced by
## `tutorial_system.gd` — on the server, and again on the client that is in it,
## at the same coordinates, exactly like the world scene itself: the buildings
## exist on both peers and only the bandits are replicated.
##
## The art is PLACEHOLDER: boxes for houses, a wall ring, and a capsule for the
## villager who sees you afterwards. Replace the scene wholesale (or drop a
## built NPC in place of the capsule) without touching the tutorial logic —
## everything it needs is looked up by node name through the accessors below.
##
## The villager walking over at the end is cosmetic, so every peer runs it
## locally and nobody replicates it. It walks toward the pawn of the player
## whose city this is, NOT "the local player" — on the server that pawn belongs
## to somebody else entirely.

signal villager_arrived

## Whose copy this is. Set by the tutorial system right after instancing.
var owner_peer := 0

## How close the villager gets before it says its piece.
const VILLAGER_REACH := 2.4
const VILLAGER_SPEED := 3.2

var _villager: Node3D
var _walking := false

func _ready() -> void:
	_villager = $Villager
	_villager.visible = false
	set_process(false)

## Where the player wakes up.
func player_spawn() -> Vector3:
	return ($PlayerSpawn as Node3D).global_position

## Bandit spawn markers, cycled if a wave is bigger than the marker count.
func bandit_spawn(i: int) -> Vector3:
	var marks := $BanditSpawns.get_children()
	if marks.is_empty():
		return global_position
	return (marks[i % marks.size()] as Node3D).global_position

## Cosmetic: the villager appears at the gate and walks over. `villager_arrived`
## fires once it is close enough to talk.
func send_villager() -> void:
	if _walking:
		return
	_villager.global_position = ($VillagerStart as Node3D).global_position
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
		_villager.look_at(Vector3(pawn.global_position.x, _villager.global_position.y,
				pawn.global_position.z), Vector3.UP)
		villager_arrived.emit()
		return
	_villager.global_position += to.normalized() * VILLAGER_SPEED * delta
	_villager.look_at(Vector3(pawn.global_position.x, _villager.global_position.y,
			pawn.global_position.z), Vector3.UP)

func _owner_pawn() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p.get("peer_id") == owner_peer:
			return p as Node3D
	return null
