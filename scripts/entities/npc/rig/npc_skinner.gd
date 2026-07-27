class_name NpcSkinner
## TURNING VOXELS INTO A SKINNED MESH: which bone each voxel rides, which part
## owns a shared cell, the faces the exporter never wrote, and the caps that
## stop a character opening up when a joint bends. Split out of NpcRig because
## it is by far the largest single idea in the rig and the one with the most
## hard-won detail in it.
##
## Skinning is RIGID: every triangle of a voxel is bound whole to one bone with
## weight 1. That is what keeps the blocky look — pieces rotate about the joints
## instead of bending like skin — and it is also the source of every problem the
## seam caps below exist to solve.

## Which bones each slot is allowed to bind to. Restricting per slot is what
## stops the arms model's centre section (which lives inside the torso) from
## grabbing an arm bone and flying off with it.
##
## KEEP THESE SHORT. Every bone in a set is another pivot cutting the art into
## another rigid slab, and a slab shears against its neighbour on every frame it
## is animated -- a body bound to five bones is a torso in four pieces sliding
## on each other, which is what made a walking villager look like it was coming
## apart. A humanoid rig offers far more joints than voxel art this coarse has
## any use for; the torso here is seven voxels tall and does not want four
## hinges in it. Adding a bone back is a visible cost, not a free improvement.
const BIND_SETS := {
	# Toes left out: a boot two voxels long has nothing to flex, and the joint
	# only ever sheared the front of it off the back.
	"feet": ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot"],
	# One hinge, at the waist: below it the torso rides the hips, above it the
	# chest. Spine/UpperChest/Neck used to sit in here too and bought nothing
	# except three more places for the body to come apart.
	#
	# No shoulders either: they swing with the arms, and letting them claim the
	# top of the chest would knead the whole body every stride.
	"body": ["Hips", "Chest"],
	# No CLAVICLES either, and for the mirror of the reason above: a clavicle runs
	# from the spine out to the shoulder joint, so its segment lies along the
	# inner half of the sleeve and claims it -- and a clavicle barely rotates in
	# these clips while the upper arm swings the whole way. That splits one rigid
	# sleeve between a bone that moves and a bone that does not, and the voxels
	# tear apart into a sawtooth at the shoulder. A voxel arm swings whole,
	# shoulder cap included -- and so does a voxel hand, which is why the wrist is
	# out too: a fist this size has no knuckles to bend, and a held item hangs off
	# a BoneAttachment3D on RightHand, which does not care how the mesh is skinned.
	#
	# UpperChest is NOT for the arms themselves. It is what catches the copy of
	# the torso every arms model carries, so that section stays put instead of
	# grabbing an arm bone and flying off with it.
	"arms": ["UpperChest", "LeftUpperArm", "LeftLowerArm",
			"RightUpperArm", "RightLowerArm"],
	# Head only, never Neck: Head is a child of Neck, so it already inherits the
	# neck's motion, and binding it whole keeps a voxel skull from shearing.
	"head": ["Head"],
}

# ---------------------------------------------------------------------------
# bone segments
# ---------------------------------------------------------------------------

## Bone index -> the [start, end] line segment a vertex measures its distance
## to. A bone's segment runs to its bindable children; a tip bone (hand, head,
## toes) gets a stub carrying on the way its parent pointed.
static func segments(skeleton: Skeleton3D) -> Dictionary:
	var bindable := {}
	for set_name: String in BIND_SETS:
		for bone: String in BIND_SETS[set_name]:
			var i := skeleton.find_bone(bone)
			if i >= 0:
				bindable[i] = true

	var origin := {}
	for i: int in bindable:
		origin[i] = skeleton.get_bone_global_rest(i).origin

	var kids := {}
	for i: int in bindable:
		var at := _bindable_parent(skeleton, bindable, i)
		if at >= 0:
			kids.get_or_add(at, []).append(i)

	var out := {}
	for i: int in bindable:
		var a: Vector3 = origin[i]
		var b := a
		if kids.has(i):
			var sum := Vector3.ZERO
			for c: int in kids[i]:
				sum += origin[c] as Vector3
			b = sum / float(kids[i].size())
		else:
			var at := _bindable_parent(skeleton, bindable, i)
			var dir := (a - (origin[at] as Vector3)) if at >= 0 else Vector3.UP
			b = a + (dir.normalized() if dir.length() > 0.0001 else Vector3.UP) * 0.08
		out[i] = [a, b]
	return out

## The nearest ancestor that is in a bind set — the bones between are skipped,
## which is exactly what keeping BIND_SETS short means for the chain.
static func _bindable_parent(skeleton: Skeleton3D, bindable: Dictionary, bone: int) -> int:
	var at := skeleton.get_bone_parent(bone)
	while at >= 0 and not bindable.has(at):
		at = skeleton.get_bone_parent(at)
	return at

static func nearest_bone(point: Vector3, candidates: Array[int], segs: Dictionary) -> int:
	var best := candidates[0]
	var best_d := INF
	for i in candidates:
		var seg: Array = segs[i]
		var d := point.distance_squared_to(
				Geometry3D.get_closest_point_to_segment(point, seg[0], seg[1]))
		if d < best_d:
			best_d = d
			best = i
	return best

# ---------------------------------------------------------------------------
# claiming cells
# ---------------------------------------------------------------------------

## Which voxels this part gets, on the grid every part shares: the bone each one
## binds to, where its centre sits, and what colour it is. Nothing is drawn here
## -- see NpcRig.rig() for why ownership has to be settled for the whole
## character before the first mesh is built.
static func claim_cells(slot: String, data: Dictionary, spec: NpcPart, xf: Transform3D,
		skeleton: Skeleton3D, segs: Dictionary, voxel_scale: float,
		occupied: Dictionary) -> Dictionary:
	var candidates: Array[int] = []
	# Armor binds to the bones of the part it covers: a pauldron rides the arm
	# it is strapped to, and there is no such thing as an armor bone.
	for bone: String in BIND_SETS[NpcDefinition.covers(slot)]:
		var i := skeleton.find_bone(bone)
		if i >= 0 and segs.has(i):
			candidates.append(i)
	if candidates.is_empty():
		candidates.append(0)

	var src_verts: PackedVector3Array = data["verts"]
	var src_norms: PackedVector3Array = data["norms"]
	var entry: PackedInt32Array = data["entry"]
	var palette: PackedColorArray = data["palette"]

	var all := {}
	for t in range(0, src_verts.size() - 2, 3):
		# One bone for the whole voxel, chosen from its centre rather than from
		# each face -- picking per vertex would tear voxels in half at the joints.
		var cell := xf * (face_centre(src_verts, t) - src_norms[t] * 0.5)
		var key := cell_key(cell, voxel_scale)
		if all.has(key):
			continue
		all[key] = {
			"bone": nearest_bone(cell, candidates, segs),
			"centre": cell,
			"colour": NpcPartLoader.colour(spec, palette, entry[t]),
		}
	# Done on the WHOLE model, before anything is handed to an earlier part: a
	# part eaten down to a stump is full of holes for a flood to pour through,
	# and it is the shape as DRAWN whose inside we want.
	_fill_interior(all, candidates, segs, voxel_scale)

	var mine := {}
	for key: Vector3i in all:
		if not occupied.has(key):
			mine[key] = all[key]
	for key: Vector3i in mine:
		occupied[key] = int((mine[key] as Dictionary)["bone"])
	return mine

## Adds the voxels the exporter never wrote.
##
## Goxel writes only faces you could have seen, so a cell walled in on all six
## sides is absent from the model entirely. Fine for drawing, wrong for
## jointing: a bone boundary through the middle of a solid part then has nothing
## on it to cap, and the shell comes apart as two rings with a hole down the
## middle of each -- which is the wedge you could see through the chest even
## after the rim of it was capped.
##
## Which cells are enclosed is not a guess. Flood the air AROUND the part; what
## the flood cannot reach is inside it. Filled cells carry the colour of the one
## that found them, which is the surface they are directly under.
static func _fill_interior(cells: Dictionary, candidates: Array[int],
		segs: Dictionary, voxel_scale: float) -> void:
	if cells.is_empty():
		return
	var keys := cells.keys()
	var anchor: Vector3i = keys[0]
	var origin: Vector3 = (cells[anchor] as Dictionary)["centre"]
	var lo := anchor
	var hi := anchor
	for key: Vector3i in keys:
		lo = Vector3i(mini(lo.x, key.x), mini(lo.y, key.y), mini(lo.z, key.z))
		hi = Vector3i(maxi(hi.x, key.x), maxi(hi.y, key.y), maxi(hi.z, key.z))
	# a cell of air all the way round, to flood from. Voxel centres sit two grid
	# steps apart, so the whole walk moves in twos and stays on their lattice.
	lo -= Vector3i(2, 2, 2)
	hi += Vector3i(2, 2, 2)

	var outside := {lo: true}
	var queue: Array[Vector3i] = [lo]
	while not queue.is_empty():
		for next in _neighbours(queue.pop_back(), lo, hi):
			if not outside.has(next) and not cells.has(next):
				outside[next] = true
				queue.append(next)

	# whatever is left in the box is walled in: grow into it from the surface,
	# which is also what gives each filled cell a colour worth wearing
	var frontier := keys
	while not frontier.is_empty():
		var at: Vector3i = frontier.pop_back()
		for next in _neighbours(at, lo, hi):
			if cells.has(next) or outside.has(next):
				continue
			var centre := origin + Vector3(next - anchor) * (voxel_scale * 0.5)
			cells[next] = {
				"bone": nearest_bone(centre, candidates, segs),
				"centre": centre,
				"colour": (cells[at] as Dictionary)["colour"],
			}
			frontier.append(next)

## The six cells touching `at`, clipped to the box. Two grid steps apart,
## because that is the lattice voxel centres sit on.
static func _neighbours(at: Vector3i, lo: Vector3i, hi: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for axis in 3:
		for step in [-2, 2]:
			var next := at
			next[axis] += step
			if next[axis] >= lo[axis] and next[axis] <= hi[axis]:
				out.append(next)
	return out

# ---------------------------------------------------------------------------
# building the mesh
# ---------------------------------------------------------------------------

static func build_mesh(data: Dictionary, spec: NpcPart, xf: Transform3D,
		mine: Dictionary, occupied: Dictionary, voxel_scale: float) -> MeshInstance3D:
	var src_verts: PackedVector3Array = data["verts"]
	var src_norms: PackedVector3Array = data["norms"]
	var entry: PackedInt32Array = data["entry"]
	var palette: PackedColorArray = data["palette"]

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()

	# Which sides the ART already draws, so the cap pass does not write a second
	# face over one of them -- two coplanar faces pointing the SAME way is the
	# z-fighting this whole file works to avoid.
	var drawn := {}

	for t in range(0, src_verts.size() - 2, 3):
		var out := (xf.basis * src_norms[t]).normalized().round()
		var key := cell_key(xf * (face_centre(src_verts, t) - src_norms[t] * 0.5), voxel_scale)
		if not mine.has(key):
			continue
		drawn["%s|%s" % [key, Vector3i(out)]] = true
		var bone := int((mine[key] as Dictionary)["bone"])
		for c in 3:
			var src := t + c
			verts.append(xf * src_verts[src])
			norms.append((xf.basis * src_norms[src]).normalized())
			cols.append(NpcPartLoader.colour(spec, palette, entry[src]))
			bind(bones, weights, bone)

	add_seam_caps(mine, occupied, drawn, xf.basis.get_scale().x, voxel_scale,
			winding_sign(data), verts, norms, cols, bones, weights)
	if verts.is_empty():
		return null

	var mi := MeshInstance3D.new()
	mi.mesh = surface({
		Mesh.ARRAY_VERTEX: verts, Mesh.ARRAY_NORMAL: norms, Mesh.ARRAY_COLOR: cols,
		Mesh.ARRAY_BONES: bones, Mesh.ARRAY_WEIGHTS: weights,
	}, false)
	return mi

## An ArrayMesh of one surface with the voxel material on it. `srgb` decodes the
## vertex colours, which the ICON path needs and the rigged path deliberately
## does not — see NpcRig.preview_mesh.
static func surface(channels: Dictionary, srgb: bool) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	for channel: int in channels:
		arrays[channel] = channels[channel]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = srgb
	mat.roughness = 0.85
	mat.metallic = 0.0
	mesh.surface_set_material(0, mat)
	return mesh

## The centre of the square face a triangle is half of.
##
## NOT the triangle's own centroid, which sits a sixth of a voxel off it: a
## voxel face is two triangles and each one leans towards its own three corners.
## That was close enough to identify which voxel a face belongs to (the cell
## grid is far coarser than a sixth) and nowhere near close enough to BUILD on,
## which is what the seam caps do -- they were landing a sixth of a voxel proud
## of the model and pushing its bounding box out with them. Taking the corners'
## own min and max recovers the square exactly, because either triangle of a
## square still spans the whole of it.
static func face_centre(verts: PackedVector3Array, t: int) -> Vector3:
	var lo := verts[t].min(verts[t + 1]).min(verts[t + 2])
	var hi := verts[t].max(verts[t + 1]).max(verts[t + 2])
	return (lo + hi) * 0.5

## One vertex bound whole to one bone. Rigid on purpose -- it is what keeps the
## blocky look, pieces rotating about the joints instead of bending like skin.
static func bind(bones: PackedInt32Array, weights: PackedFloat32Array, bone: int) -> void:
	bones.append(bone)
	weights.append(1.0)
	for _i in 3:
		bones.append(0)
		weights.append(0.0)

## Identifies the voxel a point sits in, on a grid shared by every part. Half a
## voxel of resolution, so a part deliberately offset by half a step is treated
## as its own geometry rather than a duplicate.
static func cell_key(point: Vector3, voxel_scale: float) -> Vector3i:
	if voxel_scale <= 0.0:
		return Vector3i.ZERO
	return Vector3i((point / voxel_scale * 2.0).round())

## Which way round Godot wants a front face, read off the art rather than
## assumed: the exporter already wound its own triangles correctly, so whether
## (v1-v0)x(v2-v0) runs with the face normal or against it is a fact to look up
## rather than a convention this file can get wrong. The caps below are the only
## geometry the rig invents, and a cap wound backwards is invisible -- which
## looks exactly like not having written it.
static func winding_sign(data: Dictionary) -> float:
	var verts: PackedVector3Array = data["verts"]
	var norms: PackedVector3Array = data["norms"]
	for t in range(0, verts.size() - 2, 3):
		var facing := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).dot(norms[t])
		if absf(facing) > 0.0001:
			return signf(facing)
	return 1.0

## Puts back the faces voxel art does not carry.
##
## Goxel exports only the OUTSIDE of a model: where two voxels touch there is no
## geometry at all, and nothing needs any while the pair cannot move apart.
## Rigid skinning moves them apart. A voxel bound to Chest and the one beside it
## bound to Hips separate the moment the spine bends, and with no face on either
## side of the join you are looking straight through the character -- that is
## the row of dark wedges that opened across the chest and down the arms of
## every built NPC as soon as anything animated, and it is worse in armor, which
## sits a voxel further out from the bone and so swings further.
##
## The rule is that what one bone carries has to be a CLOSED surface on its own,
## because that is the thing that moves as a unit. So a voxel gets a face on any
## side the art left bare, unless the voxel next to it belongs to the same part
## AND the same bone -- only then can the two never part, and only then is the
## face guaranteed never to be seen.
##
## Three ways a side ends up bare, and only the first is a bone boundary:
##  * the neighbour is the same part on a DIFFERENT bone -- the chest join;
##  * the neighbour was this model's own voxel and got dropped, because an
##    earlier part already filled that cell. Every arms model carries a copy of
##    the torso it was drawn against, the torso wins those cells, and what is
##    left is an arm with no end on it -- the hole at the shoulder;
##  * the neighbour is a different MESH on the same bone. Nothing moves apart
##    there, but nothing of OURS covers the join either, and a helmet cut around
##    a head is open all the way round its rim.
##
## Each side gets one square, bound to its own voxel's bone. Where two of them
## meet they sit back to back on a plane facing opposite ways, so each is the
## other's backface and neither is drawn until the joint actually opens.
##
## Sides the art already draws are left alone: a second face pointing the same
## way as an existing one is the z-fighting this file works to avoid. So is a
## side facing a cell NOBODY owns -- the exporter writes a face against open
## air, so a bare side with no owner next to it can only be this model's own
## solid interior, walled in already and never seen.
static func add_seam_caps(mine: Dictionary, occupied: Dictionary, drawn: Dictionary,
		voxel: float, voxel_scale: float, winding: float, verts: PackedVector3Array,
		norms: PackedVector3Array, cols: PackedColorArray, bones: PackedInt32Array,
		weights: PackedFloat32Array) -> void:
	if voxel <= 0.0:
		return
	var half := voxel * 0.5
	for key: Vector3i in mine:
		var cell: Dictionary = mine[key]
		var at: Vector3 = cell["centre"]
		var bone := int(cell["bone"])
		for axis in 3:
			for step in [-1.0, 1.0]:
				var dir := Vector3.ZERO
				dir[axis] = step
				if drawn.has("%s|%s" % [key, Vector3i(dir)]):
					continue
				var beside := cell_key(at + dir * voxel, voxel_scale)
				if not occupied.has(beside):
					continue
				if mine.has(beside) and int((mine[beside] as Dictionary)["bone"]) == bone:
					continue
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = half
				var w := Vector3.ZERO
				w[(axis + 2) % 3] = half
				var face := at + dir * half
				var quad: Array[Vector3] = [
						face - u - w, face + u - w, face + u + w, face - u + w]
				# u x w is +axis, so that order runs anticlockwise seen from the
				# +axis side; flip it to face `dir`, then again if the art says
				# Godot wants the other winding.
				if (step > 0.0) != (winding < 0.0):
					quad.reverse()
				for corner in [0, 1, 2, 0, 2, 3]:
					verts.append(quad[corner])
					norms.append(dir)
					cols.append(cell["colour"])
					bind(bones, weights, bone)
