class_name BanditSpawner
extends Node3D
## Spawns a bandit at this node's position on an interval, capped at a max
## number of its bandits alive at once. Drag the node to move the camp.
## Multiplayer: runs ONLY on the server — clients receive puppet copies
## through Net, so this node does nothing on their side.

@export var bandit_scene: PackedScene = preload("res://scenes/enemy.tscn")
## Seconds between spawn attempts. A camp cleared down to nothing is back to
## `max_alive` in about five minutes at this rate, not a quarter of an hour.
@export var spawn_interval := 60.0
## No new spawns while this many of this spawner's bandits are alive.
@export var max_alive := 5
## First spawn happens this many seconds after the level starts.
@export var initial_delay := 5.0
## Bandits appear scattered up to this far from the spawner.
@export var spawn_radius := 3.5
## A spot is only used if nothing living is within this of it (metres).
@export var spawn_clearance := 1.6
## How far above the camp the ground ray starts. It has to clear a rise in the
## terrain across `spawn_radius`, but stay UNDER anything the camp is pitched
## beneath: the half-tent imports with collision, so a ray dropped from high
## above finds its canvas before the floor and stands the bandit on the roof.
@export var head_room := 1.5

## How many ring positions to try before settling for the roomiest of them.
const PLACEMENT_TRIES := 8

var _spawned: Array[Node] = []
var _spawn_index := 0

func _ready() -> void:
	if not multiplayer.is_server():
		return
	var timer := Timer.new()
	timer.wait_time = spawn_interval
	timer.timeout.connect(_try_spawn)
	add_child(timer)
	timer.start()
	get_tree().create_timer(initial_delay).timeout.connect(_try_spawn)

func _alive_count() -> int:
	_spawned = _spawned.filter(func(b: Node) -> bool:
		return is_instance_valid(b) and not b.get("dead"))
	return _spawned.size()

func _try_spawn() -> void:
	if _alive_count() >= max_alive:
		return
	var bandit := bandit_scene.instantiate() as Node3D
	bandit.name = Net.next_enemy_name()
	var container := get_tree().current_scene.get_node_or_null("Enemies")
	if container == null:
		container = get_parent()
	container.add_child(bandit)
	bandit.global_position = _ground_at(_free_spot())
	_spawned.append(bandit)
	Net.server_broadcast_enemy_spawn(bandit)

## Walks the golden-angle ring until it finds a spot with nobody standing in it,
## because the ring alone is not enough: a bandit that has wandered (or a player
## camping the spawner) can be sitting exactly where the sequence says next, and
## a body dropped into another body has no way to push itself back out.
func _free_spot() -> Vector3:
	var roomiest := global_position
	var best_gap := -1.0
	for i in PLACEMENT_TRIES:
		_spawn_index += 1
		var ang := _spawn_index * 2.3999632
		var reach := 1.0 + fposmod(_spawn_index * 0.618, 1.0) * (spawn_radius - 1.0)
		var spot := global_position + Vector3(cos(ang), 0, sin(ang)) * reach
		var gap := _nearest_body_distance(spot)
		if gap >= spawn_clearance:
			return spot
		if gap > best_gap:
			best_gap = gap
			roomiest = spot
	return roomiest

## Flat distance from `spot` to the closest living bandit or player.
func _nearest_body_distance(spot: Vector3) -> float:
	var nearest := INF
	for node in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(node) or node.get("dead"):
			continue
		var away: Vector3 = (node as Node3D).global_position - spot
		away.y = 0
		nearest = minf(nearest, away.length())
	return nearest

## Drops a ray to put the bandit on the ground under `pos`. It starts just over
## the camp rather than high above it (see `head_room`), so a roof over the camp
## is never mistaken for its floor. Characters are excluded from the ray too, or
## a spot with someone under it lands the bandit on their head.
func _ground_at(pos: Vector3) -> Vector3:
	var skip: Array[RID] = []
	for node in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player"):
		if node is CollisionObject3D:
			skip.append((node as CollisionObject3D).get_rid())
	var hit := _ray_down(pos + Vector3.UP * head_room, skip)
	if hit.is_empty():
		# A camp sitting below the surface starts its ray inside the terrain and
		# hits nothing, so fall back to dropping in from well above: back to the
		# old behaviour, and a roof is the lesser problem when there is no floor.
		hit = _ray_down(pos + Vector3.UP * 25.0, skip)
	if hit.is_empty():
		return pos
	return hit.position + Vector3.UP * 0.2

func _ray_down(from: Vector3, skip: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 50.0)
	query.exclude = skip
	return get_world_3d().direct_space_state.intersect_ray(query)
