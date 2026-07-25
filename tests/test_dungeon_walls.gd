extends Node
## Headless check of the starter dungeon's generated stone shell. Run with:
##   godot --headless res://tests/test_dungeon_walls.tscn
## Prints DUNGEONTEST RESULT=PASS/FAIL and sets the exit code.
##
## The shell is generated, so the things worth asserting are the ones a human
## would only catch by walking the whole dungeon: a doorway accidentally bricked
## up, a wall floating off the slab, a door too short to walk through, or a
## piece with no collision that players fall straight out of the level through.

const DUNGEON := preload("res://scenes/starterDungeon.tscn")
const PLAYER_HEIGHT := 1.92   # capsule in scenes/player.tscn
const PLAYER_WIDTH := 0.8     # capsule radius 0.4, doubled

var _failures: Array[String] = []

func _ready() -> void:
	var scene: Node = DUNGEON.instantiate()
	add_child(scene)
	var walls: Node3D = scene.find_child("Walls", true, false)
	if walls == null:
		print("  FAIL: the dungeon has no Walls node")
		print("DUNGEONTEST RESULT=FAIL (1)")
		get_tree().quit(1)
		return

	var pieces := _pieces(walls)
	_test_something_was_built(pieces)
	_test_doors_stand_at_every_entrance(scene, walls, pieces)
	_test_doorways_are_actually_open(scene, walls, pieces)
	_test_everything_sits_on_the_slab(scene, walls, pieces)
	_test_a_player_fits_through(walls)
	_test_pieces_do_not_overlap(pieces)
	_test_every_piece_has_collision(pieces)
	_test_rebuilding_does_not_duplicate(walls, pieces)

	if _failures.is_empty():
		print("DUNGEONTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		print("DUNGEONTEST RESULT=FAIL (%d)" % _failures.size())
		get_tree().quit(1)

func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)

func _pieces(walls: Node3D) -> Array:
	var out := []
	for c in walls.get_children():
		out.append(c)
	return out

func _doors(pieces: Array) -> Array:
	return pieces.filter(func(p: Node) -> bool: return p.name.begins_with("DoorLeaf"))

# ---------------- the shell exists ----------------

func _test_something_was_built(pieces: Array) -> void:
	_check(pieces.size() > 20,
		"only %d pieces were generated — the builder found no floor" % pieces.size())

## Three thresholds, two leaves each. A missing pair means a marker was renamed
## and the builder silently skipped it.
func _test_doors_stand_at_every_entrance(scene: Node, walls: Node3D, pieces: Array) -> void:
	var entrances := []
	for c in scene.find_child("StarterDungeon", true, false).get_children():
		if "Enterence" in c.name:
			entrances.append(c)
	_check(entrances.size() == 3,
		"expected 3 Enterence markers, found %d" % entrances.size())

	var doors := _doors(pieces)
	_check(doors.size() == entrances.size() * 2,
		"expected %d door leaves, found %d" % [entrances.size() * 2, doors.size()])

	# Every marker must have a pair standing within a leaf's reach of it.
	for e in entrances:
		var here := Vector2(e.position.x, e.position.z)
		var near := 0
		for d in doors:
			var p := Vector2(d.position.x, d.position.z)
			if p.distance_to(here) < 2.0:
				near += 1
		_check(near == 2, "%s has %d door leaves beside it, expected 2" % [e.name, near])

## The point of a doorway is that it is a hole. A wall tile sitting in one would
## seal the room and strand the player, which is exactly the bug that is
## invisible until someone walks there.
func _test_doorways_are_actually_open(scene: Node, walls: Node3D, pieces: Array) -> void:
	var dungeon := scene.find_child("StarterDungeon", true, false)
	for c in dungeon.get_children():
		if not "Enterence" in c.name:
			continue
		var here := Vector2(c.position.x, c.position.z)
		for p in pieces:
			if not p.name.begins_with("Wall"):
				continue
			var at := Vector2(p.position.x, p.position.z)
			_check(at.distance_to(here) > 1.2,
				"a wall tile is standing in %s's doorway" % c.name)

func _test_everything_sits_on_the_slab(scene: Node, walls: Node3D, pieces: Array) -> void:
	var slab := _slab_bounds(scene.find_child("StarterDungeon", true, false), walls)
	var top := slab.position.y + slab.size.y
	for p in pieces:
		_check(absf(p.position.y - top) < 0.01,
			"%s stands at y=%.2f, not on the floor surface (y=%.2f)" % [p.name, p.position.y, top])
		var at := Vector2(p.position.x, p.position.z)
		var inside := at.x >= slab.position.x - 2.0 \
			and at.x <= slab.position.x + slab.size.x + 2.0 \
			and at.y >= slab.position.z - 2.0 \
			and at.y <= slab.position.z + slab.size.z + 2.0
		_check(inside, "%s is off the edge of the floor at %v" % [p.name, at])

# ---------------- the player fits ----------------

## The whole "scale it to the players" half of the job, asserted rather than
## eyeballed. A doorway shorter than the capsule is impassable, and one barely
## wider than it is miserable to walk through with a camera behind you.
func _test_a_player_fits_through(walls: Node3D) -> void:
	var s: float = walls.prefab_scale
	var door_h: float = walls.DOOR_SIZE.y * s
	var door_w: float = walls.DOOR_SIZE.z * 2.0 * s
	var wall_h: float = walls.WALL_SIZE.y * s

	_check(door_h > PLAYER_HEIGHT * 1.2,
		"doorway is %.2f m tall — too low for a %.2f m player" % [door_h, PLAYER_HEIGHT])
	_check(door_w > PLAYER_WIDTH * 2.0,
		"doorway is %.2f m wide — too narrow for a %.2f m player" % [door_w, PLAYER_WIDTH])
	_check(wall_h > door_h,
		"walls (%.2f m) are shorter than the doors (%.2f m) they contain" % [wall_h, door_h])
	_check(wall_h < PLAYER_HEIGHT * 4.0,
		"walls are %.2f m — so tall the dungeon reads as a canyon" % wall_h)

## Two blocks sharing a cell means two coincident surfaces fighting over the
## same pixels, which reads in game as the wall flickering inside out. The
## junctions where an interior wall meets the ring are where it happens.
func _test_pieces_do_not_overlap(pieces: Array) -> void:
	# Read the footprint off each piece's own collision box, so the check stays
	# honest when the builder stretches a block to fit its stretch of wall.
	var boxes := []
	for p in pieces:
		if not p.name.begins_with("Wall"):
			continue  # door leaves sit inside their opening by design
		var shape: CollisionShape3D = p.find_child("CollisionShape3D", true, false)
		if shape == null or not shape.shape is BoxShape3D:
			continue
		var size: Vector3 = (shape.shape as BoxShape3D).size
		var half := Vector2(size.x, size.z) * 0.5
		# Runs along Z are yawed 90 degrees, which swaps the footprint's axes.
		if absf(sin(p.rotation.y)) > 0.5:
			half = Vector2(half.y, half.x)
		boxes.append({"name": p.name, "at": Vector2(p.position.x, p.position.z), "half": half})

	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var a: Dictionary = boxes[i]
			var b: Dictionary = boxes[j]
			var d: Vector2 = (a["at"] as Vector2) - (b["at"] as Vector2)
			var reach: Vector2 = (a["half"] as Vector2) + (b["half"] as Vector2)
			# Touching is fine and expected; sharing volume is not.
			var hit := absf(d.x) < reach.x - 0.05 and absf(d.y) < reach.y - 0.05
			_check(not hit, "%s and %s occupy the same space at %v"
				% [a["name"], b["name"], a["at"]])

func _test_every_piece_has_collision(pieces: Array) -> void:
	for p in pieces:
		var body: Node = p.find_child("Body", true, false)
		_check(body != null and body is StaticBody3D,
			"%s has no collision — players walk through it" % p.name)
		if body == null:
			continue
		var shape: Node = body.find_child("*", true, false)
		_check(shape is CollisionShape3D and (shape as CollisionShape3D).shape != null,
			"%s's collision body has no shape" % p.name)

## Rebuilding is how the editor button works, so it has to be idempotent —
## otherwise every tweak doubles the geometry, which is the same class of bug
## the NPC builder had.
func _test_rebuilding_does_not_duplicate(walls: Node3D, pieces: Array) -> void:
	var before := pieces.size()
	walls.build()
	_check(walls.get_child_count() == before,
		"rebuilding changed the piece count from %d to %d" % [before, walls.get_child_count()])

func _slab_bounds(root: Node, walls: Node) -> AABB:
	var out := AABB()
	var have := false
	for n in _all(root, walls):
		if not (n is MeshInstance3D) or n.mesh == null:
			continue
		var box: AABB = (n as MeshInstance3D).mesh.get_aabb()
		out = box if not have else out.merge(box)
		have = true
	return out

func _all(n: Node, skip: Node) -> Array:
	if n == skip:
		return []
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c, skip))
	return out
