extends Node
## Throwaway: DOES A SWING PUT THE BLADE THROUGH THE CHARACTER? Prints, per
## sword clip and per frame, how close the blade gets to the body — where a
## negative number means it is inside it.
##   godot --headless --path . res://tests/diag_blade_clip.tscn
##
## The body is treated as an upright capsule from the hips to the neck, which is
## what a voxel torso is to within a centimetre or two, and the blade as the
## segment from the grip to its point. Both are taken in the character's own
## frame off the REAL rig with the REAL hold config, so this measures what is
## drawn, not what was authored.

const ITEM := "iron_sword"
const CLIPS := ["sword_light_0", "sword_light_1", "sword_light_2", "sword_heavy"]
const STEPS := 30
## Half-width of the torso: inside this, the blade is in the character.
const BODY_RADIUS := 0.22

func _ready() -> void:
	var vis: Node3D = (load("res://scripts/entities/player_visual.gd") as Script).new()
	add_child(vis)
	await get_tree().process_frame
	vis.set_held_item(ITEM)
	await get_tree().process_frame
	var skel: Skeleton3D = vis.skeleton
	var hand := skel.find_bone("RightHand")
	var hips := skel.find_bone("Hips")
	var neck := skel.find_bone("Neck")
	var cfg := ItemDb.hold_config(ITEM)
	var probe: Node3D = (load(str(cfg["model"])) as PackedScene).instantiate()
	add_child(probe)
	var top := _aabb(probe).end.y
	probe.queue_free()
	var s: Variant = cfg["scale"]
	var scale: Vector3 = s if s is Vector3 else Vector3.ONE * float(s)
	var grip := Transform3D(Basis.from_euler(Vector3(
			deg_to_rad(cfg["rot"].x), deg_to_rad(cfg["rot"].y), deg_to_rad(cfg["rot"].z))),
			cfg["pos"])
	var tip_local := Vector3(0.0, top * scale.y, 0.0)

	for key: String in CLIPS:
		var length: float = vis.play_scripted(key)
		vis.anim_player.pause()
		var worst := 9.0
		var worst_at := 0.0
		var inside := 0
		for i in STEPS + 1:
			var f := float(i) / float(STEPS)
			vis.anim_player.seek(length * f, true)
			await get_tree().process_frame
			var pelvis := skel.get_bone_global_pose(hips)
			var body_lo := pelvis.origin
			var body_hi := skel.get_bone_global_pose(neck).origin
			var h := skel.get_bone_global_pose(hand) * grip
			var a := h.origin
			var b := h * tip_local
			var d := _segment_gap(a, b, body_lo, body_hi) - BODY_RADIUS
			if d < 0.0:
				inside += 1
			if d < worst:
				worst = d
				worst_at = f
		print("%-14s worst %+0.3fm at %3.0f%% of the clip, inside on %d of %d frames"
				% [key, worst, worst_at * 100.0, inside, STEPS + 1])
		vis.stop_scripted()
	get_tree().quit()

## Closest approach between two segments.
func _segment_gap(a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3) -> float:
	var best := 9.0
	for i in 21:
		var p := a1.lerp(a2, float(i) / 20.0)
		best = minf(best, _point_gap(p, b1, b2))
	return best

func _point_gap(p: Vector3, b1: Vector3, b2: Vector3) -> float:
	var ab := b2 - b1
	var t := clampf((p - b1).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(b1 + ab * t)

func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.transform * mi.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out
