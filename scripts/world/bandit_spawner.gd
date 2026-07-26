class_name BanditSpawner
extends Node3D
## Spawns a bandit at this node's position on an interval, capped at a max
## number of its bandits alive at once. Drag the node to move the camp.
## Multiplayer: runs ONLY on the server — clients receive puppet copies
## through Net, so this node does nothing on their side.

@export var bandit_scene: PackedScene = preload("res://scenes/enemy.tscn")
## Seconds between spawn attempts (3 minutes).
@export var spawn_interval := 180.0
## No new spawns while this many of this spawner's bandits are alive.
@export var max_alive := 5
## First spawn happens this many seconds after the level starts.
@export var initial_delay := 5.0
## Bandits appear scattered up to this far from the spawner.
@export var spawn_radius := 3.5

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
	# The world-wide ceiling the server owns, on top of this camp's own cap.
	if not Net.server_can_spawn_enemy():
		return
	var bandit := bandit_scene.instantiate() as Node3D
	bandit.name = Net.next_enemy_name()
	var container := get_tree().current_scene.get_node_or_null("Enemies")
	if container == null:
		container = get_parent()
	container.add_child(bandit)
	# scatter around the spawner (golden-angle ring so spawns don't stack)
	_spawn_index += 1
	var ang := _spawn_index * 2.3999632
	var offset := Vector3(cos(ang), 0, sin(ang)) * (1.0 + fposmod(_spawn_index * 0.618, 1.0) * (spawn_radius - 1.0))
	bandit.global_position = _ground_at(global_position + offset)
	_spawned.append(bandit)
	Net.server_broadcast_enemy_spawn(bandit)

## Drops a ray to put the bandit on the terrain surface.
func _ground_at(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 25.0, pos + Vector3.DOWN * 50.0)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return pos
	return hit.position + Vector3.UP * 0.2
