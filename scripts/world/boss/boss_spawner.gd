class_name BossSpawner
extends Node3D
## Puts a boss where this node is standing, and puts it back once it has been
## dead a while. Drag the node to move the fight.
##
## It is NOT the bandit camp with the numbers changed, and the differences are
## the point: there is exactly ONE of it, it goes at the marker rather than
## scattered around it (a boss arena is placed by hand, not sprinkled), and it
## comes back on a long timer so the dungeon is not empty for whoever walks in
## next. Set `respawn_delay` to 0 for a boss that stays dead.
##
## Multiplayer: runs ONLY on the server, exactly like BanditSpawner. Clients are
## told about the fighter through Net and rebuild it from `enemy_kind`.

## Which body to spawn — a key of `Net.ENEMY_SCENES`, so the client can rebuild
## the same one. A scene set here without a matching key would come out as a
## bandit on every other screen, which is why the KIND is what is stored.
@export var boss_kind := "juggernaut"
## Seconds after the level loads before the first one appears.
@export var initial_delay := 2.0
## Seconds after a boss dies before the next stands up. 0 = never again.
@export var respawn_delay := 300.0
## How far above the marker the ground ray starts — under any roof it is stood
## beneath, for the reason BanditSpawner documents at length (a dungeon has a
## ceiling and a ray from high above finds it first).
@export var head_room := 2.5
## How often the corpse is checked for, and the respawn clock ticked.
const CHECK_INTERVAL := 5.0

var _boss: Node3D
var _dead_for := 0.0

func _ready() -> void:
	if not multiplayer.is_server():
		return
	var timer := Timer.new()
	timer.wait_time = CHECK_INTERVAL
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()
	get_tree().create_timer(initial_delay).timeout.connect(_spawn)

## The one it spawned, or null. Read by the test.
func boss() -> Node3D:
	return _boss if is_instance_valid(_boss) else null

func _tick() -> void:
	if is_instance_valid(_boss) and not bool(_boss.get("dead")):
		_dead_for = 0.0
		return
	if respawn_delay <= 0.0:
		return
	_dead_for += CHECK_INTERVAL
	if _dead_for >= respawn_delay:
		_dead_for = 0.0
		_spawn()

func _spawn() -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(_boss) and not bool(_boss.get("dead")):
		return
	var scene: PackedScene = Net.ENEMY_SCENES.get(boss_kind, null)
	if scene == null:
		push_warning("BossSpawner: no scene registered for kind '%s'" % boss_kind)
		return
	var boss_node := scene.instantiate() as Node3D
	boss_node.name = Net.next_enemy_name()
	boss_node.enemy_kind = boss_kind
	var container := get_tree().current_scene.get_node_or_null("Enemies")
	if container == null:
		container = get_parent()
	container.add_child(boss_node)
	boss_node.global_position = _ground_at(global_position)
	_boss = boss_node
	Net.server_broadcast_enemy_spawn(boss_node)

## Drops it onto whatever is under the marker. Characters are excluded, or a
## player standing on the spot has a boss land on their head.
func _ground_at(pos: Vector3) -> Vector3:
	var skip: Array[RID] = []
	for node in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player"):
		if node is CollisionObject3D:
			skip.append((node as CollisionObject3D).get_rid())
	var from := pos + Vector3.UP * head_room
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
	query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return pos
	return hit.position + Vector3.UP * 0.2
