extends Node3D
## Throwaway: dump the player's rig proportions and look for parts overlapping
## while the clips play.

const SLOTS := ["Feet", "Body", "Arms", "Head"]

func _ready() -> void:
	var vis := PlayerVisual.new()
	add_child(vis)
	await get_tree().process_frame
	var skel: Skeleton3D = vis.skeleton
	print("=== layout ===")
	var keys: Array = vis.layout.keys()
	keys.sort()
	for k: String in keys:
		if k == "part_xf":
			continue
		print("  %s = %s" % [k, vis.layout[k]])

	print("=== bone rests (global) ===")
	for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
			"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
			"LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]:
		var i := skel.find_bone(b)
		if i < 0:
			continue
		var o := skel.get_bone_global_rest(i).origin
		print("  %-14s (%.3f, %.3f, %.3f)" % [b, o.x, o.y, o.z])

	print("=== part AABBs (rest, character space) ===")
	for s in SLOTS:
		var mi := skel.get_node_or_null(NodePath(s)) as MeshInstance3D
		if mi == null:
			print("  %s MISSING" % s)
			continue
		var ab := mi.mesh.get_aabb()
		print("  %-6s pos(%.3f..%.3f, %.3f..%.3f, %.3f..%.3f)  size %s" % [
			s, ab.position.x, ab.end.x, ab.position.y, ab.end.y,
			ab.position.z, ab.end.z, ab.size])

	# Which bone each part's vertices actually went to, and how far they sit
	# from that bone.
	print("=== binding spread ===")
	for s in SLOTS:
		var mi := skel.get_node_or_null(NodePath(s)) as MeshInstance3D
		if mi == null:
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var per := {}
		for i in verts.size():
			var b: int = bones[i * 4]
			if not per.has(b):
				per[b] = [Vector3.INF, -Vector3.INF]
			per[b][0] = (per[b][0] as Vector3).min(verts[i])
			per[b][1] = (per[b][1] as Vector3).max(verts[i])
		var names: Array = []
		for b: int in per:
			var lo: Vector3 = per[b][0]
			var hi: Vector3 = per[b][1]
			var bo := skel.get_bone_global_rest(b).origin
			var far := maxf((lo - bo).length(), (hi - bo).length())
			names.append("%s(x %.2f..%.2f, reach %.2f)" % [skel.get_bone_name(b), lo.x, hi.x, far])
		names.sort()
		print("  %s -> %s" % [s, ", ".join(names)])

	# Now play each clip and look for arm voxels ending up inside the torso box.
	print("=== interpenetration while animating ===")
	for clip in ["idle", "walk", "run", "block", "light_0", "heavy"]:
		_scan(vis, skel, clip)

	get_tree().quit()


func _scan(vis: PlayerVisual, skel: Skeleton3D, clip: String) -> void:
	var ap := vis.anim_player
	if not ap.has_animation("lib/" + clip):
		print("  %s: not built" % clip)
		return
	var anim := ap.get_animation("lib/" + clip)
	var body := _bound(skel, "Body")
	var worst := 0.0
	var worst_t := 0.0
	var steps := 24
	for s in steps:
		var t := anim.length * float(s) / float(steps)
		ap.play("lib/" + clip)
		ap.seek(t, true, true)
		var pen := _penetration(skel, "Arms", body)
		if pen > worst:
			worst = pen
			worst_t = t
	print("  %-8s worst arm-in-torso penetration %.3f m (t=%.2f)" % [clip, worst, worst_t])


## Rest-space AABB of a part, in the bone-local frames it is skinned to.
func _bound(skel: Skeleton3D, part: String) -> AABB:
	var mi := skel.get_node_or_null(NodePath(part)) as MeshInstance3D
	if mi == null:
		return AABB()
	return mi.mesh.get_aabb()


## How far the arm mesh's skinned vertices reach inside the torso's current box.
func _penetration(skel: Skeleton3D, part: String, body_rest: AABB) -> float:
	var mi := skel.get_node_or_null(NodePath(part)) as MeshInstance3D
	if mi == null:
		return 0.0
	# Torso box, moved by the chest bone.
	var chest := skel.find_bone("Chest")
	var chest_xf := skel.get_bone_global_pose(chest) * skel.get_bone_global_rest(chest).affine_inverse()
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var box := chest_xf * body_rest
	var worst := 0.0
	for i in range(0, verts.size(), 7):
		var b: int = bones[i * 4]
		var xf := skel.get_bone_global_pose(b) * skel.get_bone_global_rest(b).affine_inverse()
		var p: Vector3 = xf * verts[i]
		if not box.has_point(p):
			continue
		var d := minf(minf(p.x - box.position.x, box.end.x - p.x),
				minf(p.z - box.position.z, box.end.z - p.z))
		worst = maxf(worst, d)
	return worst
