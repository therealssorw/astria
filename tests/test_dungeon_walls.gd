extends Node
## Headless check of the starter dungeon's generated stone shell. Run with:
##   godot --headless res://tests/test_dungeon_walls.tscn
## Prints DUNGEONTEST RESULT=PASS/FAIL and sets the exit code.
##
## The shell is generated, so the things worth asserting are the ones a human
## would only catch by walking the whole dungeon: a wall standing across a room
## you were meant to walk through, a stretch of floor with no wall on it at all,
## a wall sunk into the stairs, or a piece with no collision that players fall
## out of the level through.
##
## THE MAIN ONE IS `_test_no_wall_stands_in_open_floor`. Walling the model's
## bounding box instead of its outline is exactly how the first version of this
## went wrong — a rectangle around an L-shaped plan puts walls straight across
## open rooms — and it is invisible from outside the dungeon, in a screenshot,
## or in any count of how many blocks were built.
##
## The floor is re-measured HERE, by sampling the mesh triangles, rather than
## asking the builder where it thought the floor was. A test that reads the
## builder's own grid back only ever agrees with itself.

const DUNGEON := preload("res://scenes/starterDungeon.tscn")
const PLAYER_HEIGHT := 1.92   # capsule in scenes/player.tscn

## Resolution of this file's own copy of the floor plan, in metres.
const SAMPLE := 0.5

var _failures: Array[String] = []
var _floor := {}          # Vector2i cell -> highest floor Y in it
var _walls: Array = []    # {node, at, perp, half_len, half_thick}

func _ready() -> void:
	var scene: Node = DUNGEON.instantiate()
	add_child(scene)
	var walls: Node3D = scene.find_child("Walls", true, false)
	if walls == null:
		print("  FAIL: the dungeon has no Walls node")
		print("DUNGEONTEST RESULT=FAIL (1)")
		get_tree().quit(1)
		return

	_sample_floor(walls.get_parent(), walls)
	_measure_walls(walls)

	_test_something_was_built()
	_test_the_floor_was_found()
	_test_no_wall_stands_in_open_floor()
	_test_the_floor_is_walled_all_the_way_round()
	_test_walls_stand_on_the_floor_they_border()
	_test_a_player_cannot_see_over_them(walls)
	_test_pieces_do_not_overlap()
	_test_every_piece_has_collision(walls)
	_test_rebuilding_does_not_duplicate(walls)

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

# ---------------- our own copy of the floor plan ----------------

## Sample every triangle of the floor into cells. Points are taken across the
## face AND along its edges, so an upright triangle — a stair riser, which
## flattens to a line with no area — still registers the ground it stands on.
func _sample_floor(root: Node, skip: Node) -> void:
	for n in _all(root, skip):
		if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
			continue
		var xf := _relative(n as Node3D, root)
		var mesh := (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := idx.size() if not idx.is_empty() else verts.size()
			for i in range(0, count - 2, 3):
				var a := xf * (verts[idx[i]] if not idx.is_empty() else verts[i])
				var b := xf * (verts[idx[i + 1]] if not idx.is_empty() else verts[i + 1])
				var c := xf * (verts[idx[i + 2]] if not idx.is_empty() else verts[i + 2])
				_sample_tri(a, b, c)

## Subdivided to the SAMPLE grid, not a fixed count: the floor is drawn as a
## handful of very large triangles, and a fixed subdivision spreads points
## metres apart on those and leaves a sieve of holes — which reads downstream
## as a floor with ten times the perimeter it really has.
func _sample_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var longest := maxf((b - a).length(), maxf((c - b).length(), (a - c).length()))
	var steps := clampi(int(ceil(longest / (SAMPLE * 0.5))), 4, 400)
	for u in steps + 1:
		for v in range(0, steps + 1 - u):
			var wa := float(u) / steps
			var wb := float(v) / steps
			var p := a * (1.0 - wa - wb) + b * wa + c * wb
			var cell := Vector2i(int(floor(p.x / SAMPLE)), int(floor(p.z / SAMPLE)))
			if not _floor.has(cell) or _floor[cell] < p.y:
				_floor[cell] = p.y

func _is_floor(x: float, z: float) -> bool:
	return _floor.has(Vector2i(int(floor(x / SAMPLE)), int(floor(z / SAMPLE))))

func _floor_top(x: float, z: float):
	var cell := Vector2i(int(floor(x / SAMPLE)), int(floor(z / SAMPLE)))
	return _floor[cell] if _floor.has(cell) else null

# ---------------- what the builder produced ----------------

func _measure_walls(walls: Node3D) -> void:
	for p in walls.get_children():
		# By TYPE, not by name: a runtime-built node can end up auto-named
		# "@CollisionShape3D@48", and a name lookup then silently matches
		# nothing — which reads as "no walls were built" rather than as a
		# broken test.
		var shape := _find_shape(p)
		if shape == null or not shape.shape is BoxShape3D:
			continue
		var size: Vector3 = (shape.shape as BoxShape3D).size
		var yaw: float = (p as Node3D).rotation.y
		# The block's long axis is local X; the wall's face normal is local Z.
		var along := Vector2(cos(yaw), -sin(yaw))
		_walls.append({
			"node": p,
			"at": Vector2((p as Node3D).position.x, (p as Node3D).position.z),
			"y": (p as Node3D).position.y,
			"along": along,
			"perp": Vector2(-along.y, along.x),
			"half_len": size.x * 0.5,
			"half_thick": size.z * 0.5,
			"height": size.y,
		})

# ---------------- the tests ----------------

func _test_something_was_built() -> void:
	_check(_walls.size() > 20,
		"only %d wall pieces were generated — the builder found no floor" % _walls.size())

func _test_the_floor_was_found() -> void:
	_check(_floor.size() > 200,
		"the test only found %d cells of floor — the model moved or is empty" % _floor.size())

## A wall belongs on the EDGE of the floor: floor on one side of it, nothing on
## the other. One with floor on both sides is standing in the middle of a room,
## which is the bounding-box bug this file exists to catch.
func _test_no_wall_stands_in_open_floor() -> void:
	var stranded := []
	for w in _walls:
		var reach: float = w["half_thick"] + 1.0
		var inside: bool = _is_floor(w["at"].x + w["perp"].x * reach,
			w["at"].y + w["perp"].y * reach)
		var outside: bool = _is_floor(w["at"].x - w["perp"].x * reach,
			w["at"].y - w["perp"].y * reach)
		if inside and outside:
			stranded.append(w)
	# A handful at corners and doorway mouths genuinely have floor both sides —
	# an inside corner is floor wrapping round the block. A bounding-box shell
	# strands a large fraction, so the bug is nowhere near this threshold.
	var ratio := float(stranded.size()) / maxf(1.0, float(_walls.size()))
	_check(ratio < 0.12, "%d of %d walls stand in open floor (%.0f%%) — the shell is not following the rooms; first at %v"
		% [stranded.size(), _walls.size(), ratio * 100.0,
			stranded[0]["at"] if not stranded.is_empty() else Vector2.ZERO])

## The other half of the same coin: the floor's whole perimeter should have a
## wall on it. Measured as total wall length against the perimeter this file
## measures for itself, so a shell that covers only one side of the dungeon
## fails even though every piece it did build is in a legal place.
func _test_the_floor_is_walled_all_the_way_round() -> void:
	var perimeter := 0.0
	for cell in _floor:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _floor.has(cell + d):
				perimeter += SAMPLE
	var built := 0.0
	for w in _walls:
		built += w["half_len"] * 2.0
	_check(perimeter > 0.0, "the floor plan has no perimeter at all")
	var frac := built / maxf(0.001, perimeter)
	_check(frac > 0.7,
		"only %.0f m of wall for a %.0f m perimeter (%.0f%%) — the dungeon is open to the world"
			% [built, perimeter, frac * 100.0])
	_check(frac < 2.0,
		"%.0f m of wall for a %.0f m perimeter (%.0f%%) — walls are being built on top of each other"
			% [built, perimeter, frac * 100.0])

## A wall sunk into the stairs, or floating over the lower level, is the failure
## mode of flattening the plan — the height has to come back from the floor the
## wall actually borders.
func _test_walls_stand_on_the_floor_they_border() -> void:
	var wrong := 0
	for w in _walls:
		var reach: float = w["half_thick"] + 1.0
		var top = _floor_top(w["at"].x + w["perp"].x * reach, w["at"].y + w["perp"].y * reach)
		if top == null:
			top = _floor_top(w["at"].x - w["perp"].x * reach, w["at"].y - w["perp"].y * reach)
		if top == null:
			continue
		# One step of the staircase is 0.25; allow a step and a bit of slack.
		if absf(w["y"] - float(top)) > 0.6:
			wrong += 1
	_check(wrong == 0, "%d walls do not stand at the height of the floor beside them" % wrong)

## The "scale it to the players" half of the job, asserted rather than
## eyeballed: a wall a player can see over is scenery, not a dungeon.
func _test_a_player_cannot_see_over_them(walls: Node3D) -> void:
	var s: float = walls.prefab_scale
	var wall_h: float = walls.WALL_SIZE.y * s
	_check(wall_h > PLAYER_HEIGHT * 1.5,
		"walls are %.2f m — a %.2f m player sees straight over them" % [wall_h, PLAYER_HEIGHT])
	_check(wall_h < PLAYER_HEIGHT * 4.0,
		"walls are %.2f m — so tall the dungeon reads as a canyon" % wall_h)
	for w in _walls:
		_check(absf(w["height"] - wall_h) < 0.01,
			"%s is %.2f m tall, not %.2f m" % [w["node"].name, w["height"], wall_h])

## Two blocks sharing a cell means two coincident surfaces fighting over the
## same pixels, which reads in game as the wall flickering inside out.
##
## Only PARALLEL blocks are checked. Perpendicular ones interpenetrate at every
## corner by design — the two runs meeting there both cover it, which is what
## makes a corner solid rather than notched — and they share no coplanar face,
## so there is nothing to fight.
func _test_pieces_do_not_overlap() -> void:
	for i in _walls.size():
		for j in range(i + 1, _walls.size()):
			var a: Dictionary = _walls[i]
			var b: Dictionary = _walls[j]
			if absf((a["along"] as Vector2).dot(b["along"] as Vector2)) < 0.9:
				continue  # perpendicular: a corner, not a clash
			var d: Vector2 = (a["at"] as Vector2) - (b["at"] as Vector2)
			var along := absf(d.dot(a["along"] as Vector2))
			var across := absf(d.dot(a["perp"] as Vector2))
			var reach_len: float = a["half_len"] + b["half_len"]
			var reach_thick: float = a["half_thick"] + b["half_thick"]
			var hit: bool = along < reach_len - 0.05 and across < reach_thick - 0.05
			_check(not hit, "%s and %s occupy the same space at %v"
				% [a["node"].name, b["node"].name, a["at"]])

func _test_every_piece_has_collision(walls: Node3D) -> void:
	for p in walls.get_children():
		var body: Node = p.find_child("Body", true, false)
		_check(body != null and body is StaticBody3D,
			"%s has no collision — players walk through it" % p.name)
		if body == null:
			continue
		var shape := _find_shape(body)
		_check(shape != null and shape.shape != null,
			"%s's collision body has no shape" % p.name)

## Rebuilding is how the editor button works, so it has to be idempotent —
## otherwise every tweak doubles the geometry, which is the same class of bug
## the NPC builder had.
func _test_rebuilding_does_not_duplicate(walls: Node3D) -> void:
	var before := walls.get_child_count()
	walls.build()
	_check(walls.get_child_count() == before,
		"rebuilding changed the piece count from %d to %d" % [before, walls.get_child_count()])

# ---------------- helpers ----------------

func _find_shape(n: Node) -> CollisionShape3D:
	if n is CollisionShape3D:
		return n as CollisionShape3D
	for c in n.get_children():
		var got := _find_shape(c)
		if got != null:
			return got
	return null

func _relative(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur is Node3D and cur != root:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

func _all(n: Node, skip: Node) -> Array:
	if n == skip:
		return []
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c, skip))
	return out
