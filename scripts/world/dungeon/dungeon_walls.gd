@tool
extends Node3D
## Builds the stone shell of a dungeon: a wall ring around the floor slab, the
## interior walls that split it into rooms, and a mirrored pair of half-doors
## in every opening.
##
## It is generated rather than hand-placed because the shell is ~90 repeated
## segments. Hand-placing those means ninety transforms in the .tscn that
## nobody can re-derive later; here the ring comes from the floor mesh's own
## bounds and each doorway comes from the Area3D marker it belongs to, so
## nudging a marker in the editor moves its doors, and resizing the slab moves
## the whole ring.
##
## DOOR PLACEMENT reads the markers by NAME (see RUNS). That is deliberate: the
## markers already exist as the gameplay anchors for those thresholds, and
## having the art derive from them means the door can never drift away from the
## trigger that opens it.
##
## Everything is regenerated from scratch on _ready, on both the server and
## every client. That is safe precisely because it is deterministic and static
## — no networking, same geometry everywhere, nothing to replicate.

const WALL_SCENE := preload("res://Assets/Models/World/Prefab/stoneWall.gltf")
const DOOR_SCENE := preload("res://Assets/Models/World/Prefab/halfdoor.gltf")

## Raw model bounds, in voxel units, measured off the glTF. The prefabs are
## authored at voxel scale (a wall is 23 voxels long), so everything below is
## expressed in those units and multiplied by `prefab_scale` at the end.
const WALL_SIZE := Vector3(23, 19, 8)
const WALL_MIN := Vector3(-11, 0, -4)   # so the long axis is X, and Y starts at the floor
const DOOR_SIZE := Vector3(3, 13, 7)    # 3 thick, 13 tall, 7 wide along the run
const DOOR_MIN := Vector3(-1, 0, 2)

## The player capsule is 1.92 m tall. At 0.2 a wall stands 3.8 m and a doorway
## is 2.8 m wide by 2.6 m tall — comfortably over head height without the
## chunky voxel blocks dwarfing everyone.
@export var prefab_scale := 0.2: set = _set_scale

## Node holding the floor slab; the wall ring is traced around its mesh bounds.
@export var floor_path := NodePath("..")

## Tick in the editor to regenerate after changing anything above.
@export var rebuild_now := false: set = _set_rebuild

## Interior walls. Each run is a straight line across the floor in LOCAL XZ,
## with the markers whose thresholds it carries. `from`/`to` are fractions of
## the floor bounds (0 = min edge, 1 = max edge) so a resized slab keeps the
## same plan; the doors are absolute, because they come from the markers.
##
## The plan these describe:
##   A  entry room (PlayerSpawn) is cut off from the main hall
##   B  the north-west enemy room (EnemySpawn) is walled off
##   C  the boss chamber takes the eastern strip
const RUNS := [
	{"axis": "x", "at_marker": "Room1Enterence", "from": 0.0,
		"to": "BossAndEnemyEnterence", "doors": ["Room1Enterence"]},
	{"axis": "z", "at_marker": "Room2Enterence", "from": 0.0, "to": 0.36,
		"doors": ["Room2Enterence"]},
	{"axis": "z", "at_marker": "BossAndEnemyEnterence", "from": 0.0,
		"to": "Room1Enterence", "doors": ["BossAndEnemyEnterence"]},
]

var _built := false

func _ready() -> void:
	build()

func _set_scale(v: float) -> void:
	prefab_scale = maxf(0.01, v)
	if is_inside_tree():
		build()

func _set_rebuild(v: bool) -> void:
	rebuild_now = false
	if v and is_inside_tree():
		build()

# ---------------- construction ----------------

func build() -> void:
	_clear()
	var slab := _floor_bounds()
	if slab.size == Vector3.ZERO:
		push_warning("[DungeonWalls] no floor mesh found at %s — nothing built." % floor_path)
		return
	var top := slab.position.y + slab.size.y   # walls stand ON the slab, not in it
	var min_x := slab.position.x
	var max_x := slab.position.x + slab.size.x
	var min_z := slab.position.z
	var max_z := slab.position.z + slab.size.z

	# The ring. The two runs across X span the full width and so own all four
	# corner cells; the two along Z stop half a wall short at each end rather
	# than pushing a second block into a corner that is already filled.
	var inset := WALL_SIZE.z * prefab_scale * 0.5
	_run(Vector2(min_x, min_z), Vector2(max_x, min_z), top, [])
	_run(Vector2(min_x, max_z), Vector2(max_x, max_z), top, [])
	_run(Vector2(min_x, min_z + inset), Vector2(min_x, max_z - inset), top, [])
	_run(Vector2(max_x, min_z + inset), Vector2(max_x, max_z - inset), top, [])

	for spec in RUNS:
		var anchor = _marker_pos(spec["at_marker"])
		if anchor == null:
			push_warning("[DungeonWalls] marker '%s' is missing — run skipped." % spec["at_marker"])
			continue
		var doors: Array[Vector2] = []
		for name in spec["doors"]:
			var p = _marker_pos(name)
			if p != null:
				doors.append(p)
		var across_x: bool = spec["axis"] == "x"
		var lo := _extent(spec["from"], across_x, min_x, max_x, min_z, max_z)
		var hi := _extent(spec["to"], across_x, min_x, max_x, min_z, max_z)
		var a := Vector2(lo, anchor.y) if across_x else Vector2(anchor.x, lo)
		var b := Vector2(hi, anchor.y) if across_x else Vector2(anchor.x, hi)
		# Butt interior walls up against whatever they meet instead of running
		# into it. A tile pushed into the ring shares a face with the ring's own
		# tile, and two coincident faces z-fight — the wall flickers inside-out
		# exactly the way overlapping NPC parts used to.
		var toward := (b - a).normalized()
		_run(a + toward * inset, b - toward * inset, top, doors)
	_built = true

## Lay one straight wall from `a` to `b`, leaving a hole exactly the width of a
## door pair at each threshold, and standing the leaves in it.
##
## The solid stretches between openings are tiled to fit EXACTLY: the block
## count is rounded and its length stretched to divide the stretch evenly,
## rather than tiling at a fixed size and letting the last one hang over. A
## fixed size cannot do both jobs at once — the leftover either leaves a hole
## or overlaps its neighbour, and two blocks overlapping in line have coplanar
## side faces, which is the z-fighting this is all trying to avoid. Stretching
## costs at most a few percent on a block nobody measures.
func _run(a: Vector2, b: Vector2, top: float, doors: Array) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.001:
		return
	var dir := span / length
	var perp := Vector2(-dir.y, dir.x)
	var gap := DOOR_SIZE.z * 2.0 * prefab_scale   # two leaves meeting in the middle

	# How far along the run each doorway sits, in order.
	var openings: Array[float] = []
	for d in doors:
		openings.append((d - a).dot(dir))
	openings.sort()

	# The solid stretches are what is left of the run once the holes are cut.
	var solids := []
	var cursor := 0.0
	for o in openings:
		solids.append([cursor, o - gap * 0.5])
		cursor = o + gap * 0.5
	solids.append([cursor, length])

	for s in solids:
		_tile(a, dir, s[0], s[1], top)
	for o in openings:
		_door_pair(a + dir * o, dir, perp, top)

func _tile(a: Vector2, dir: Vector2, from: float, to: float, top: float) -> void:
	var length := to - from
	if length < 0.05:
		return
	var nominal := WALL_SIZE.x * prefab_scale
	var count := maxi(1, int(round(length / nominal)))
	var seg := length / count
	# Stretch only the long axis; thickness and height stay uniform, or the
	# wall would visibly change depth from one stretch to the next.
	var long_scale := seg / WALL_SIZE.x
	var yaw := atan2(-dir.y, dir.x)
	for i in count:
		var centre := a + dir * (from + (i + 0.5) * seg)
		# The mesh's long axis is centred half a voxel off its origin, so back
		# the node off by that much to make neighbours meet flush.
		var offset := (WALL_MIN.x + WALL_SIZE.x * 0.5) * long_scale
		_place(WALL_SCENE, centre - dir * offset, top, yaw,
			Vector3(long_scale, prefab_scale, prefab_scale),
			Vector3(seg, WALL_SIZE.y * prefab_scale, WALL_SIZE.z * prefab_scale), "Wall")

## Two leaves facing each other across the threshold.
##
## They are mirrored with a 180-degree turn rather than a negative scale: a
## negative scale flips the mesh's winding, and Godot then culls the visible
## face and lights what is left inside out. Turning the second leaf gets the
## same silhouette — hinges to the outside, edges meeting in the middle —
## while staying a normal, correctly-lit mesh.
func _door_pair(at: Vector2, dir: Vector2, perp: Vector2, top: float) -> void:
	var along := DOOR_MIN.z * prefab_scale                       # leaf starts 2 voxels out
	var side := (DOOR_MIN.x + DOOR_SIZE.x * 0.5) * prefab_scale  # centre it on the wall
	var facing := atan2(dir.x, dir.y)
	var leaf := Vector3(DOOR_SIZE.x, DOOR_SIZE.y, DOOR_SIZE.z) * prefab_scale
	var s := Vector3(prefab_scale, prefab_scale, prefab_scale)

	_place(DOOR_SCENE, at - dir * along - perp * side, top, facing, s, leaf, "DoorLeafA")
	_place(DOOR_SCENE, at + dir * along + perp * side, top, facing + PI, s, leaf, "DoorLeafB")

## One prefab instance, plus the collision that stops a player walking through
## it. The art has no collision of its own, so a box per piece is added here —
## these are rectangular blocks, so a box is exact, not an approximation.
func _place(scene: PackedScene, at: Vector2, top: float, yaw: float,
		scale3: Vector3, size: Vector3, prefix: String) -> void:
	var node := scene.instantiate()
	node.name = "%s%d" % [prefix, get_child_count()]
	node.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(scale3),
		Vector3(at.x, top, at.y))
	add_child(node)
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root

	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	# The art sits with its base on the floor and its origin at the base, so the
	# box has to be lifted half its height to line up with it.
	shape.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	node.add_child(body)

func _clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_built = false

# ---------------- reading the scene ----------------

func _floor_bounds() -> AABB:
	var root := get_node_or_null(floor_path)
	if root == null:
		return AABB()
	return _mesh_bounds(root, Transform3D.IDENTITY, root)

func _mesh_bounds(n: Node, xf: Transform3D, root: Node) -> AABB:
	var here := xf
	if n is Node3D and n != root:
		here = xf * (n as Node3D).transform
	var out := AABB()
	var have := false
	if n is MeshInstance3D and n.mesh and not n.is_ancestor_of(self) and not is_ancestor_of(n):
		out = here * (n.mesh.get_aabb() as AABB)
		have = true
	for c in n.get_children():
		if c == self:
			continue  # never measure the walls we are building
		var sub := _mesh_bounds(c, here, root)
		if sub.size == Vector3.ZERO:
			continue
		out = sub if not have else out.merge(sub)
		have = true
	return out

## Where a run starts or stops. A number is a fraction of the floor (0 = min
## edge, 1 = max edge), so a resized slab keeps the plan. A marker NAME instead
## means "stop where that wall is" — which is how two dividers meet exactly
## rather than approximately, and keeps working if the marker moves.
func _extent(spec, across_x: bool, min_x: float, max_x: float,
		min_z: float, max_z: float) -> float:
	if spec is String:
		var p = _marker_pos(spec)
		if p != null:
			# A run across X stops at the other wall's X, and vice versa.
			return p.x if across_x else p.y
		push_warning("[DungeonWalls] run endpoint '%s' is missing." % spec)
		return min_x if across_x else min_z
	return lerpf(min_x, max_x, float(spec)) if across_x else lerpf(min_z, max_z, float(spec))

## A marker's position on the floor plane, or null if it is not there.
func _marker_pos(marker_name: String):
	var parent := get_parent()
	if parent == null:
		return null
	var n := parent.find_child(marker_name, true, false)
	if n == null or not n is Node3D:
		return null
	return Vector2((n as Node3D).position.x, (n as Node3D).position.z)
