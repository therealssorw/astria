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
## THE SHELL IS CLOSED: walls up to a flat ceiling, and a roof across it. The
## dungeon is a place you are INSIDE, so it gets a lid rather than open sky, and
## the ceiling is one height for the whole plan (see `ceiling_height`) so a
## staircase cannot open a slit where two different ceiling heights would meet.
## Walls are therefore not all the same height — each stands from the floor it
## borders up to that one ceiling, tiled in courses to fit exactly.
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

## The player capsule is 1.92 m tall. At 0.2 one COURSE of wall stands 3.8 m;
## how tall the dungeon actually is comes from `ceiling_height` below, which
## stacks as many courses as it takes.
@export var prefab_scale := 0.2: set = _set_scale

## Head room over the HIGHEST bit of floor, in metres, and so the height of the
## ceiling everywhere: one flat lid rather than one that steps with the stairs,
## because two ceilings at different heights meet in a slit you can see the sky
## through. Every wall is built up to it, so this is the one dial for how tall
## the dungeon feels.
@export var ceiling_height := 6.0: set = _set_ceiling

## Off leaves the dungeon open to the sky, which is what it was before it had a
## lid. Kept as a switch because a roof hides everything inside it from an
## editor camera looking down.
@export var build_roof := true: set = _set_roof

## The ceiling's own shade. It is a flat slab rather than voxel blocks — a
## roof's worth of the wall prefab is about a million triangles overhead that
## nobody can get close enough to see the bumps on.
@export var roof_colour := Color(0.30, 0.29, 0.27)

## A roofed room loses the sun, and the island's ambient alone reads as flat
## grey. These are the lamps that put some shape back; 0 turns them off.
##
## The COUNT is capped at `MAX_LIGHTS` and not by this spacing, because the
## Compatibility renderer only lets a handful of lights touch any one object
## and the dungeon floor is a single mesh — a ninth lamp would simply not light
## it. So the spacing is what the grid AIMS for, and the cap is what it gets.
@export var light_energy := 3.0
@export var light_spacing := 18.0
@export var light_colour := Color(1.0, 0.86, 0.66)

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

## No more lamps than the Compatibility renderer will apply to one mesh
## (`rendering/limits/opengl/max_lights_per_object`, 8 by default). The floor is
## one mesh, so past this the extra lights light nothing and cost anyway.
const MAX_LIGHTS := 8

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

## Y of the ceiling's underside, and so the top of every wall.
var _ceiling := 0.0

func _ready() -> void:
	build()

func _set_scale(v: float) -> void:
	prefab_scale = maxf(0.01, v)
	if is_inside_tree():
		build()

func _set_ceiling(v: float) -> void:
	ceiling_height = maxf(0.5, v)
	if is_inside_tree():
		build()

func _set_roof(v: bool) -> void:
	build_roof = v
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
	_ceiling = _highest_floor() + ceiling_height

	for run in _runs():
		_tile(run)
	if build_roof:
		_roof()
		_lamps()
	_built = true

## The top of the ceiling's underside — what every wall is built up to. Public
## so a test can assert the shell is closed without re-deriving it.
func ceiling_y() -> float:
	return _ceiling

## The highest bit of floor in the plan. The ceiling is measured off THIS rather
## than off each wall's own floor, so the lid is one flat surface with no step
## in it for a player to see daylight through.
func _highest_floor() -> float:
	var best := -INF
	for i in _solid.size():
		if _solid[i] == 1 and _top[i] > best:
			best = _top[i]
	return 0.0 if best == -INF else best

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
	var yaw := atan2(-dir.y, dir.x)
	var step := _bite() * _inward(run)

	for i in count:
		var a: Vector2 = start + dir * (i * seg)
		var b: Vector2 = start + dir * ((i + 1) * seg)
		_place_wall((a + b) * 0.5 + step, _floor_under(run, a, b), yaw, seg)

## Which way the room is, from a run's boundary line.
func _inward(run: Dictionary) -> Vector2:
	var side := float(run["inside"])
	return Vector2(0, side) if run["axis"] == "x" else Vector2(side, 0)

## How far a wall is pushed INTO the room past its boundary line — the fix for
## the crack that used to run along the bottom of every wall.
##
## The grid is deliberately conservative (see `_rasterise`), so the outline can
## sit up to one cell OUTSIDE the real edge of the floor. Centred on that line a
## block reaches only half its thickness back in, which left the floor stopping
## short of the wall's inner face by up to a fifth of a metre — a slot at ankle
## height you could see straight through into the void. Stepping in by the
## difference guarantees the inner face always lands ON floor.
##
## Derived rather than dialled: it is exactly the worst case the grid can be
## wrong by, so a finer `cells_per_wall` shrinks it to nothing by itself.
func _bite() -> float:
	return maxf(0.0, _cell - WALL_SIZE.z * prefab_scale * 0.5)

## How high the floor is on the inside of the run under this block, so a wall
## running up a staircase climbs with it instead of sinking into the steps.
##
## The LOWEST floor under the block's whole length, not the height at its
## middle: a cell records the highest floor in it, so a block spanning a step
## would otherwise stand on the top of that step with a gap under the rest of
## it — the same crack as above, turned on its side. Standing on the lowest and
## burying the difference is the right way to be wrong.
func _floor_under(run: Dictionary, from: Vector2, to: Vector2) -> float:
	var line_i: int = run["line"]
	var side: int = run["inside"]
	var along_x: bool = run["axis"] == "x"
	var steps := maxi(1, int(ceil((to - from).length() / (_cell * 0.5))))
	var best := INF
	for i in steps + 1:
		var p: Vector2 = from.lerp(to, float(i) / float(steps))
		var cx := int(floor((p.x - _origin.x) / _cell))
		var cz := int(floor((p.y - _origin.y) / _cell))
		# Step off the boundary line into the floor it belongs to.
		if along_x:
			cz = line_i if side == 1 else line_i - 1
		else:
			cx = line_i if side == 1 else line_i - 1
		cx = clampi(cx, 0, _w - 1)
		cz = clampi(cz, 0, _h - 1)
		var y := _top[cz * _w + cx]
		if y != -INF:
			best = minf(best, y)
	return 0.0 if best == INF else best

## One wall: as many courses of the prefab as it takes to reach the ceiling,
## plus the single box of collision that stops a player walking through it.
##
## Courses rather than one stretched block, so a taller dungeon does not mean
## visibly taller voxels; and tiled to fit exactly for the same reason the run
## is, so the top course lands ON the ceiling instead of poking through it or
## leaving a gap under it.
func _place_wall(at: Vector2, base: float, yaw: float, seg: float) -> void:
	var height := maxf(WALL_SIZE.y * prefab_scale * 0.5, _ceiling - base)
	var courses := maxi(1, int(round(height / (WALL_SIZE.y * prefab_scale))))
	var course := height / courses

	var root := Node3D.new()
	root.name = "Wall%d" % get_child_count()
	root.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, base, at.y))
	add_child(root)
	_own(root)

	# Stretch only along the run and up; thickness stays uniform, or the wall
	# would visibly change depth from one stretch to the next.
	var long_scale := seg / WALL_SIZE.x
	var tall_scale := course / WALL_SIZE.y
	# The mesh is centred half a voxel off its own origin on the long axis, so
	# back it off by that much to make neighbours meet flush.
	var off_x := -(WALL_MIN.x + WALL_SIZE.x * 0.5) * long_scale
	var off_z := -(WALL_MIN.z + WALL_SIZE.z * 0.5) * prefab_scale
	for c in courses:
		var node := WALL_SCENE.instantiate()
		node.name = "Course%d" % c
		node.transform = Transform3D(
			Basis().scaled(Vector3(long_scale, tall_scale, prefab_scale)),
			Vector3(off_x, c * course - WALL_MIN.y * tall_scale, off_z))
		root.add_child(node)
		_own(node)

	# One box for the whole column. The art has no collision of its own, and
	# these are rectangular blocks, so a box is exact rather than an
	# approximation. It is lifted half its height because the wall's origin sits
	# at its base.
	_collide(root, BoxShape3D.new(), Vector3(0, height * 0.5, 0),
		Vector3(seg, height, WALL_SIZE.z * prefab_scale))

# ---------------- the lid ----------------

## The ceiling: one flat slab over every cell the flood could not reach, at
## `_ceiling`.
##
## Built as a mesh rather than out of the wall prefab, which is the same
## decision the walls made the other way. A voxel block is ~3.5k triangles; a
## roof's worth of them is about a million overhead, on a surface nobody can get
## within four metres of. Cells are merged into runs along X first, so a plain
## rectangular room is a handful of quads rather than one per cell.
##
## It reaches to the boundary LINE, which is the middle of the wall, so the wall
## top and the roof always overlap by half a wall's thickness — there is no
## seam to line up and nothing to keep in step if either moves.
func _roof() -> void:
	var verts := PackedVector3Array()
	for cz in _h:
		var cx := 0
		while cx < _w:
			if not _inside(cx, cz):
				cx += 1
				continue
			var run_end := cx
			while run_end < _w and _inside(run_end, cz):
				run_end += 1
			var x0 := _origin.x + cx * _cell
			var x1 := _origin.x + run_end * _cell
			var z0 := _origin.y + cz * _cell
			var z1 := _origin.y + (cz + 1) * _cell
			# Wound so the visible face points DOWN, at the room under it.
			var a := Vector3(x0, _ceiling, z0)
			var b := Vector3(x1, _ceiling, z0)
			var c := Vector3(x1, _ceiling, z1)
			var d := Vector3(x0, _ceiling, z1)
			verts.append_array([a, b, c, a, c, d])
			cx = run_end
	if verts.is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.DOWN)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = roof_colour
	mat.roughness = 1.0
	# Seen only from below, but the dungeon is out in the open world: a
	# single-sided lid would let an editor camera looking down see straight in.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)

	var roof := Node3D.new()
	roof.name = "Roof"
	add_child(roof)
	_own(roof)
	var mi := MeshInstance3D.new()
	mi.name = "Ceiling"
	mi.mesh = mesh
	roof.add_child(mi)
	_own(mi)

	# Collision off the same triangles: a player who gets up there on a
	# staircase has to stop at the lid rather than walk out over the dungeon.
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	_collide(roof, shape, Vector3.ZERO, Vector3.ZERO)

## Lamps under the ceiling. A roof takes the sun away, and the island's sky
## ambient on its own renders the whole dungeon one flat grey.
##
## The grid is sized to `light_spacing` but CAPPED at `MAX_LIGHTS`, because the
## Compatibility renderer only applies a few lights to any one mesh and the
## floor is a single mesh — see the export above.
func _lamps() -> void:
	if light_energy <= 0.0:
		return
	var cells := _inside_bounds()
	if cells == Rect2i():
		return
	var span := Vector2(cells.size.x, cells.size.y) * _cell
	var nx := clampi(int(round(span.x / maxf(1.0, light_spacing))), 1, MAX_LIGHTS)
	var nz := clampi(int(round(span.y / maxf(1.0, light_spacing))), 1, MAX_LIGHTS)
	while nx * nz > MAX_LIGHTS:
		if nx >= nz:
			nx -= 1
		else:
			nz -= 1

	var lamps := Node3D.new()
	lamps.name = "Lamps"
	add_child(lamps)
	_own(lamps)
	var reach := maxf(span.x / nx, span.y / nz)
	for ix in nx:
		for iz in nz:
			var cx := cells.position.x + int((ix + 0.5) * cells.size.x / nx)
			var cz := cells.position.y + int((iz + 0.5) * cells.size.y / nz)
			var at := _nearest_floor(cx, cz)
			if at.x < 0:
				continue
			var lamp := OmniLight3D.new()
			lamp.name = "Lamp%d" % lamps.get_child_count()
			lamp.light_color = light_colour
			lamp.light_energy = light_energy
			lamp.omni_range = reach
			# Just under the ceiling, so the light reads as coming off it.
			lamp.position = Vector3(_origin.x + (at.x + 0.5) * _cell,
				_ceiling - ceiling_height * 0.25,
				_origin.y + (at.y + 0.5) * _cell)
			lamps.add_child(lamp)
			_own(lamp)

## The cell bounds of everything the flood could not reach — the plan itself,
## without the padding the grid carries around it.
func _inside_bounds() -> Rect2i:
	var lo := Vector2i(_w, _h)
	var hi := Vector2i(-1, -1)
	for cz in _h:
		for cx in _w:
			if not _inside(cx, cz):
				continue
			lo = Vector2i(mini(lo.x, cx), mini(lo.y, cz))
			hi = Vector2i(maxi(hi.x, cx), maxi(hi.y, cz))
	if hi.x < 0:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)

## The nearest cell of REAL floor to a point, so a lamp placed on an even grid
## over an L-shaped plan does not end up hanging over a courtyard the plan has
## no floor in. Solid, not merely `_inside`: the flood counts an enclosed hole
## as inside, which is right for walling it and wrong for hanging a lamp in it.
## Returns (-1, -1) if there is none.
func _nearest_floor(cx: int, cz: int) -> Vector2i:
	for r in range(0, maxi(_w, _h)):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue  # only the new ring
				var nx := cx + dx
				var nz := cz + dz
				if nx < 0 or nx >= _w or nz < 0 or nz >= _h:
					continue
				if _open_floor(nx, nz):
					return Vector2i(nx, nz)
	return Vector2i(-1, -1)

## Floor with floor all around it. A single solid cell can be one an edge
## clipped the corner of — the rasteriser is deliberately generous — and its
## middle is then out over nothing. Asking for the whole neighbourhood is what
## puts a lamp over a room rather than over its lip.
func _open_floor(cx: int, cz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := cx + dx
			var nz := cz + dz
			if nx < 0 or nx >= _w or nz < 0 or nz >= _h:
				return false
			if _solid[nz * _w + nx] != 1:
				return false
	return true

# ---------------- shared plumbing ----------------

## A static body carrying one shape, under `parent`. `size` is only read for a
## BoxShape3D; anything else arrives already built.
func _collide(parent: Node3D, shape_res: Shape3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	# Named explicitly. A node parented before its parent is in the tree gets an
	# auto-name like "@CollisionShape3D@48", which nothing can look up by name —
	# an old test quietly matched none of them and passed on an empty set.
	shape.name = "Shape"
	if shape_res is BoxShape3D:
		(shape_res as BoxShape3D).size = size
	shape.shape = shape_res
	shape.position = at
	body.add_child(shape)
	parent.add_child(body)
	_own(body)
	_own(shape)

## Anything built in the editor has to be owned by the scene being edited or it
## is invisible in the tree and lost on save.
func _own(n: Node) -> void:
	if Engine.is_editor_hint():
		n.owner = get_tree().edited_scene_root

func _clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_built = false
