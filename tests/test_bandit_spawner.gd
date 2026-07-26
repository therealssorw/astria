extends Node
## Headless test for where a bandit camp puts its bandits. Run:
##   godot --headless --path . res://tests/test_bandit_spawner.tscn
## The camp is pitched under the half-tent, which imports with collision, so
## the thing that matters is that the ground ray finds the floor UNDER the camp
## and never the canvas over it. Builds a floor with a roof 3 m above it, then
## checks every spot around the ring lands on the floor — and that a camp with
## nothing under its own feet still finds ground the old way, by dropping in
## from above. Prints SPAWNTEST RESULT=PASS/FAIL and sets the exit code.

const ROOF_Y := 3.0
const FLOOR_Y := 0.0

var _failures := 0

func _ready() -> void:
	_run()

func _expect(ok: bool, what: String) -> bool:
	if not ok:
		_failures += 1
		print("  FAIL  ", what)
	return ok

func _slab(parent: Node, centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	parent.add_child(body)
	body.global_position = centre

func _run() -> void:
	var world := Node3D.new()
	add_child(world)
	_slab(world, Vector3(0, FLOOR_Y - 0.5, 0), Vector3(60, 1, 60))
	_slab(world, Vector3(0, ROOF_Y, 0), Vector3(12, 0.2, 12)) # the tent canvas

	var camp := BanditSpawner.new()
	camp.initial_delay = 10000.0 # nothing spawns by itself during the test
	camp.spawn_interval = 10000.0
	world.add_child(camp)
	camp.global_position = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	# the fixture only proves anything if the canvas is solid: a ray dropped from
	# high above (what the camp used to do) must stop on it
	var skip: Array[RID] = []
	var from_above: Dictionary = camp.call("_ray_down", Vector3(0, 25, 0), skip)
	_expect(not from_above.is_empty() and absf((from_above["position"] as Vector3).y - ROOF_Y) < 0.4,
			"the test's canvas is not solid, so this proves nothing")

	# every spot the ring can pick has to land on the floor, not on the canvas
	var highest := -INF
	for i in 16:
		var spot: Vector3 = camp.call("_free_spot")
		var ground: Vector3 = camp.call("_ground_at", spot)
		highest = maxf(highest, ground.y)
		_expect(absf(ground.y - FLOOR_Y) < 0.4,
				"ring spot %d landed at y=%.2f, not on the floor" % [i, ground.y])
		_expect(Vector2(spot.x, spot.z).length() <= camp.spawn_radius + 0.01,
				"ring spot %d is %.2fm out, past spawn_radius" % [i, Vector2(spot.x, spot.z).length()])
	print("SPAWNTEST highest ground under the tent: y=%.2f (canvas is at %.1f)" % [highest, ROOF_Y])

	# a camp buried under the surface still finds ground: its own ray starts
	# inside the terrain and misses, and the fallback drops in from above
	camp.global_position = Vector3(20, FLOOR_Y - 3.0, 20)
	await get_tree().physics_frame
	var buried: Vector3 = camp.call("_ground_at", camp.global_position)
	_expect(absf(buried.y - FLOOR_Y) < 0.4,
			"a buried camp put its bandit at y=%.2f instead of on the floor" % buried.y)

	_check_counting_survives_a_corpse(camp)

	if _failures == 0:
		print("SPAWNTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		print("SPAWNTEST RESULT=FAIL (%d problems)" % _failures)
		get_tree().quit(1)

## Counting what is alive has to cope with the dead, which is the entire point
## of it — and it did not.
##
## `_spawned` is an `Array[Node]`, and a bandit that has died is a FREED object
## still sitting in it. A freed object cannot be passed as a `Node`: pruning the
## list with `Array.filter` and a `func(b: Node)` made the typed parameter reject
## it, `filter` gave up and returned an untyped EMPTY array, and assigning that
## back blew up with
##   Trying to assign an array of type "Array" to a variable of type "Array[Node]"
## That aborted `_alive_count` every time, so once one bandit had died the camp
## never spawned again. It needed a corpse to happen, which is why it looked
## intermittent.
func _check_counting_survives_a_corpse(camp: BanditSpawner) -> void:
	var live := Node3D.new()
	var doomed := Node3D.new()
	add_child(live)
	add_child(doomed)
	var listed: Array[Node] = [live, doomed]
	camp.set("_spawned", listed)
	remove_child(doomed)
	doomed.free()

	var count: Variant = camp.call("_alive_count")
	if not _expect(count != null,
			"_alive_count returned nothing with a freed bandit in the list — it errored out"):
		return
	_expect(int(count) == 1,
			"_alive_count says %s bandits are alive; one of the two was freed" % count)
	var left: Array = camp.get("_spawned")
	_expect(left.size() == 1 and left[0] == live,
			"the freed bandit was not pruned out of the spawner's list")
	live.queue_free()
