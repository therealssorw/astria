@tool
extends Node3D
## Builds the stone shell of a dungeon: a wall standing along every edge of the
## floor, following the real outline of the rooms and corridors.
##
## It is generated rather than hand-placed because the shell is ~150 repeated
## segments. Hand-placing those means a hundred and fifty transforms in the
## .tscn that nobody can re-derive later; here the walls come from the floor
## mesh itself, so reshaping the floor in Blender re-walls the dungeon with no
## scene edit at all.
##
## HOW THE OUTLINE IS FOUND, and why it is not the obvious way. The floor is
## rasterised straight DOWN into a grid — every triangle, flattened to XZ — and
## then the outside is flood-filled. A wall goes on every edge between a cell
## the flood reached and one it did not. So:
##
##   - the outline follows the ROOMS, not the model's bounding box. Tracing the
##     bounds is what the first version of this file did, and on a plan with an
##     L of rooms and a corridor it walls a rectangle around the lot: walls
##     across open floor, rooms sealed off, the corridor buried. That is the
##     bug this rewrite exists to fix.
##   - THERE ARE NO DOORWAYS AND NOTHING NEEDS ONE. An opening is simply where
##     the floor carries on, so the gap between two rooms is left by the floor
##     joining them. The old version had to cut doors back into walls it should
##     never have drawn, keyed to marker nodes that had to be kept in step by
##     hand.
##   - STAIRS AND SPLIT LEVELS COST NOTHING. Flattening throws the height away,
##     so a staircase is solid floor like anything else and gets walls down
##     both sides instead of one across every step. Height comes back per
##     block, off the floor under it, so a wall climbs with the stairs.
##
## Flood-filling from the OUTSIDE (rather than taking every inside/outside edge)
## is what fills in holes: a gap the mesh happens to leave mid-room, or a pillar
## modelled into the floor, would otherwise get its own little wall ring in the
## middle of the room. Anything enclosed is treated as floor.
##
## Everything is regenerated from scratch on _ready, on both the server and
## every client. That is safe precisely because it is deterministic and static
## — no networking, same geometry everywhere, nothing to replicate.

const WALL_SCENE := preload("res://Assets/Models/World/Prefab/stoneWall.gltf")

## Raw model bounds, in voxel units, measured off the glTF. The prefab is
## authored at voxel scale (a wall is 23 voxels long), so everything below is
## expressed in those units and multiplied by `prefab_scale` at the end.
const WALL_SIZE := Vector3(23, 19, 8)
const WALL_MIN := Vector3(-11, 0, -4)   # so the long axis is X, and Y starts at the floor

## The player capsule is 1.92 m tall. At 0.2 a wall stands 3.8 m — comfortably
## over head height without the chunky voxel blocks dwarfing everyone.
@export var prefab_scale := 0.2: set = _set_scale

## Node holding the floor mesh; its triangles are what get traced.
@export var floor_path := NodePath("..")

## How finely the floor is sampled, as a fraction of one wall's length. The
## outline can only land on a grid line, so this is how closely the walls hug
## the real edge of the floor: 4 puts that within about a metre. Raising it
## costs a quadratic number of cells and buys nothing on a plan drawn square,
## which dungeon floors are.
@export var cells_per_wall := 4

## Tick in the editor to regenerate after changing anything above.
@export var rebuild_now := false: set = _set_rebuild

var _built := false

## The flattened floor plan, held in members for the duration of a build.
##
## NOT passed between the functions below, and that is deliberate: a Packed
## array is a VALUE type in GDScript, so a helper handed one fills in a COPY
## and the caller sees no change at all. Marking cells through a parameter
## silently did nothing, and a dungeon whose every cell reads as empty builds
## no walls while reporting no error.
var _cell := 1.0
var _origin := Vector2.ZERO
var _w := 0
var _h := 0
var _solid := PackedByteArray()      # 1 where the floor covers the cell
var _top := PackedFloat32Array()     # highest floor Y in the cell
var _outside := PackedByteArray()    # 1 where the flood from the edge reached

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
	var tris := _floor_triangles()
	if tris.is_empty():
		push_warning("[DungeonWalls] no floor mesh found at %s — nothing built." % floor_path)
		return

	if not _rasterise(tris):
		push_warning("[DungeonWalls] the floor has no footprint — nothing built.")
		return
	_flood_outside()

	for run in _runs():
		_tile(run)
	_built = true

## Every triangle of the floor, in this node's own space.
##
## Collected into an Array rather than a PackedVector3Array on purpose: a
## Packed array is a VALUE type, so `_gather` would fill in a copy of it and
## hand nothing back — which looks from outside exactly like a dungeon with no
## floor in it.
func _floor_triangles() -> Array:
	var root := get_node_or_null(floor_path)
	if root == null:
		return []
	# Our own transform is usually identity, but honour it rather than assume:
	# the walls have to land on the floor wherever this node has been dragged.
	var to_local := transform.affine_inverse()
	var out: Array[Vector3] = []
	_gather(root, to_local * _relative_to(root), out)
	return out

## The transform taking `root`'s space to our parent's space. `floor_path` is
## normally ".." — the model we hang under — so this is normally identity.
func _relative_to(root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := root
	var stop := get_parent()
	while n is Node3D and n != stop:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

func _gather(n: Node, xf: Transform3D, out: Array[Vector3]) -> void:
	if n == self or is_ancestor_of(n):
		return  # never trace the walls we are building
	var here := xf
	if n is Node3D and n != get_node_or_null(floor_path):
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh := (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				for i in verts.size():
					out.append(here * verts[i])
			else:
				for i in idx.size():
					out.append(here * verts[idx[i]])
	for c in n.get_children():
		_gather(c, here, out)

## Flatten the floor into a grid of cells, recording which are covered and how
## high the floor is in each.
##
## Both the triangle's AREA and its three EDGES are stamped. The edges are what
## make a vertical triangle count: a stair riser is upright, so flattened it is
## a LINE with no area at all and no cell centre inside it — sample by area
## alone and a staircase modelled mostly as risers punches a ragged hole
## through the middle of the footprint. Stamping edges too makes the cover
## conservative, which is the right way to be wrong here: an extra cell of
## floor moves a wall out by a metre, a missing one puts a wall across a room.
func _rasterise(tris: Array) -> bool:
	_cell = WALL_SIZE.x * prefab_scale / maxf(1.0, float(cells_per_wall))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in tris.size():
		var v: Vector3 = tris[i]
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	if lo.x > hi.x:
		return false

	# Two cells of margin all round, so the outside flood has somewhere to
	# start and can get right around the footprint.
	const PAD := 2
	_origin = lo - Vector2(_cell, _cell) * PAD
	_w = int(ceil((hi.x - lo.x) / _cell)) + PAD * 2 + 1
	_h = int(ceil((hi.y - lo.y) / _cell)) + PAD * 2 + 1

	_solid = PackedByteArray()
	_solid.resize(_w * _h)
	_top = PackedFloat32Array()
	_top.resize(_w * _h)
	_top.fill(-INF)

	for t in range(0, tris.size() - 2, 3):
		var a: Vector3 = tris[t]
		var b: Vector3 = tris[t + 1]
		var c: Vector3 = tris[t + 2]
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var c2 := Vector2(c.x, c.z)
		var y := maxf(a.y, maxf(b.y, c.y))

		var t_lo := Vector2(minf(a2.x, minf(b2.x, c2.x)), minf(a2.y, minf(b2.y, c2.y)))
		var t_hi := Vector2(maxf(a2.x, maxf(b2.x, c2.x)), maxf(a2.y, maxf(b2.y, c2.y)))
		var x0 := maxi(0, int(floor((t_lo.x - _origin.x) / _cell)))
		var x1 := mini(_w - 1, int(floor((t_hi.x - _origin.x) / _cell)))
		var z0 := maxi(0, int(floor((t_lo.y - _origin.y) / _cell)))
		var z1 := mini(_h - 1, int(floor((t_hi.y - _origin.y) / _cell)))
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var p := _origin + Vector2(cx + 0.5, cz + 0.5) * _cell
				if _in_triangle(p, a2, b2, c2):
					_mark(cx, cz, y)
		_stamp_edge(a2, b2, y)
		_stamp_edge(b2, c2, y)
		_stamp_edge(c2, a2, y)
	return true

func _mark(cx: int, cz: int, y: float) -> void:
	var i := cz * _w + cx
	_solid[i] = 1
	if y > _top[i]:
		_top[i] = y

## Walk a flattened edge cell by cell, so a triangle with no area still covers
## the ground it stands on.
func _stamp_edge(a: Vector2, b: Vector2, y: float) -> void:
	var steps := int(ceil((b - a).length() / (_cell * 0.5))) + 1
	for i in steps + 1:
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		var cx := int(floor((p.x - _origin.x) / _cell))
		var cz := int(floor((p.y - _origin.y) / _cell))
		if cx >= 0 and cx < _w and cz >= 0 and cz < _h:
			_mark(cx, cz, y)

func _in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-9:
		return false
	var u := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d
	var v := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d
	return u >= 0.0 and v >= 0.0 and u + v <= 1.0

## Mark everything reachable from the edge of the grid as outside. What is left
## unreached and unsolid is an enclosed hole, and counts as floor — see the
## header for why holes are filled rather than walled around.
func _flood_outside() -> void:
	_outside = PackedByteArray()
	_outside.resize(_w * _h)
	var queue: Array[int] = [0]
	_outside[0] = 1
	var steps: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		var cx := i % _w
		var cz := i / _w
		for d in steps:
			var nx := cx + d.x
			var nz := cz + d.y
			if nx < 0 or nx >= _w or nz < 0 or nz >= _h:
				continue
			var n := nz * _w + nx
			if _outside[n] == 1 or _solid[n] == 1:
				continue
			_outside[n] = 1
			queue.append(n)

func _inside(cx: int, cz: int) -> bool:
	if cx < 0 or cx >= _w or cz < 0 or cz >= _h:
		return false
	return _outside[cz * _w + cx] == 0

## Every straight stretch of wall, found by merging the boundary edges that lie
## on the same grid line with the floor on the same side of them.
##
## Doing it per line means no loop-chaining and no winding to get wrong: a run
## is just a maximal row of consecutive boundary edges, and a corner is simply
## where a run across X and a run along Z both stop.
func _runs() -> Array:
	var out := []
	# Runs across X: a horizontal line with floor on one side of it only.
	for cz in range(_h + 1):
		for side in [1, -1]:
			var start := -1
			for cx in range(_w + 1):
				var here: bool = cx < _w \
					and _inside(cx, cz if side == 1 else cz - 1) \
					and not _inside(cx, cz - 1 if side == 1 else cz)
				if here and start < 0:
					start = cx
				elif not here and start >= 0:
					out.append({"axis": "x", "line": cz, "from": start, "to": cx,
						"inside": side})
					start = -1
	# Runs along Z.
	for cx in range(_w + 1):
		for side in [1, -1]:
			var start := -1
			for cz in range(_h + 1):
				var here: bool = cz < _h \
					and _inside(cx if side == 1 else cx - 1, cz) \
					and not _inside(cx - 1 if side == 1 else cx, cz)
				if here and start < 0:
					start = cz
				elif not here and start >= 0:
					out.append({"axis": "z", "line": cx, "from": start, "to": cz,
						"inside": side})
					start = -1
	return out

## Lay one straight wall along a run.
##
## The blocks are tiled to fit EXACTLY: the count is rounded and the block
## stretched to divide the run evenly, rather than tiling at a fixed size and
## letting the last one hang over. A fixed size cannot do both jobs at once —
## the leftover either leaves a hole or overlaps its neighbour, and two blocks
## overlapping in line have coplanar side faces, which z-fights exactly the way
## overlapping NPC parts used to. Stretching costs at most a few percent on a
## block nobody measures.
func _tile(run: Dictionary) -> void:
	var across_x: bool = run["axis"] == "x"
	var from_i: int = run["from"]
	var to_i: int = run["to"]
	var line_i: int = run["line"]
	var length: float = float(to_i - from_i) * _cell
	if length < 0.05:
		return
	var start: Vector2
	var dir: Vector2
	if across_x:
		start = _origin + Vector2(from_i * _cell, line_i * _cell)
		dir = Vector2(1, 0)
	else:
		start = _origin + Vector2(line_i * _cell, from_i * _cell)
		dir = Vector2(0, 1)

	var nominal := WALL_SIZE.x * prefab_scale
	var count := maxi(1, int(round(length / nominal)))
	var seg := length / count
	# Stretch only the long axis; thickness and height stay uniform, or the
	# wall would visibly change depth from one stretch to the next.
	var long_scale := seg / WALL_SIZE.x
	var yaw := atan2(-dir.y, dir.x)
	# The mesh's long axis is centred half a voxel off its origin, so back the
	# node off by that much to make neighbours meet flush.
	var offset := (WALL_MIN.x + WALL_SIZE.x * 0.5) * long_scale

	for i in count:
		var centre: Vector2 = start + dir * ((i + 0.5) * seg)
		_place(centre - dir * offset, _floor_under(run, centre), yaw,
			Vector3(long_scale, prefab_scale, prefab_scale),
			Vector3(seg, WALL_SIZE.y * prefab_scale, WALL_SIZE.z * prefab_scale))

## How high the floor is on the inside of the run at this point, so a wall
## running up a staircase climbs with it instead of sinking into the steps.
func _floor_under(run: Dictionary, at: Vector2) -> float:
	var line_i: int = run["line"]
	var side: int = run["inside"]
	var cx := int(floor((at.x - _origin.x) / _cell))
	var cz := int(floor((at.y - _origin.y) / _cell))
	# Step off the boundary line into the floor it belongs to.
	if run["axis"] == "x":
		cz = line_i if side == 1 else line_i - 1
	else:
		cx = line_i if side == 1 else line_i - 1
	cx = clampi(cx, 0, _w - 1)
	cz = clampi(cz, 0, _h - 1)
	var y := _top[cz * _w + cx]
	return 0.0 if y == -INF else y

## One prefab instance, plus the collision that stops a player walking through
## it. The art has no collision of its own, so a box per piece is added here —
## these are rectangular blocks, so a box is exact, not an approximation.
func _place(at: Vector2, top: float, yaw: float, scale3: Vector3, size: Vector3) -> void:
	var node := WALL_SCENE.instantiate()
	node.name = "Wall%d" % get_child_count()
	node.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(scale3),
		Vector3(at.x, top, at.y))
	add_child(node)
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root

	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	# Named explicitly. A node parented before its parent is in the tree gets an
	# auto-name like "@CollisionShape3D@48", which nothing can look up by name —
	# the previous test quietly matched none of them and passed on an empty set.
	shape.name = "Shape"
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
