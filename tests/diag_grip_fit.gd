extends Node
## Throwaway, and the one that answers the question: WHERE DOES THE BLADE
## ACTUALLY BELONG IN THE HAND — read off the animation pack instead of guessed.
##   godot --headless --path . res://tests/diag_grip_fit.tscn
##
## The Mocap Online FBXs ship the sword they were performed with: `TonySword_01`
## hanging off a prop bone in the hand, and it is the SAME model the game
## carries. So the animator's own grip is sitting in the file — every sword clip
## was authored around it, and the game only has to agree.
##
## It cannot be copied across as a transform, because the game's skeleton is the
## retargeted humanoid profile and its hand bone does not rest the way the
## MotusMan one does. So it is FITTED: play the same clip on both rigs, and for
## each frame ask what the blade's direction is in the character's own frame
## (source) and what rotation of the game's hand bone would point it there.
## Average that over the clip. If the fit is right the answer barely moves from
## frame to frame, which is what the spread is for — and then it is CHECKED
## against a second clip it was never fitted on, which is what the errors are
## for.

## Pack files that ship their own sword: [fbx, the clip the game cut out of it,
## where that slice starts in the source].
const PAIRS := [
	["res://Assets/Animations/Humanoid/Sword/Idle/Sword Idle.fbx", "sword_idle", 0.0],
	["res://Assets/Animations/Humanoid/Sword/Attack/Sword Combo.fbx", "sword_heavy", 3.73],
]
const ITEM := "iron_sword"
const STEPS := 24

var _vis: Node3D
var _skel: Skeleton3D

func _ready() -> void:
	_vis = (load("res://scripts/entities/player_visual.gd") as Script).new()
	add_child(_vis)
	await get_tree().process_frame
	_skel = _vis.skeleton

	var blades: Array[Vector3] = []
	var edges: Array[Vector3] = []
	var offsets: Array[Vector3] = []
	await _sample(PAIRS[0], blades, edges, offsets)
	print("FIT blade axis in the hand: %s (spread %.3f)" % [_mean(blades), _spread(blades)])
	print("FIT edge  axis in the hand: %s (spread %.3f)" % [_mean(edges), _spread(edges)])
	var y := _mean(blades).normalized()
	var x := _mean(edges).normalized()
	x = (x - y * x.dot(y)).normalized()
	var rot := Basis(x, y, x.cross(y)).get_euler()
	print("FIT rot for ItemDb = Vector3(%.1f, %.1f, %.1f)"
			% [rad_to_deg(rot.x), rad_to_deg(rot.y), rad_to_deg(rot.z)])

	# The offset is a LENGTH, so unlike the rotation it does not carry across
	# unchanged: it was measured on a full-sized mocap actor and the game's
	# characters are short-limbed voxel people. Scale it by the two rigs'
	# forearms, the bone the hand hangs off in both.
	var src: Node = (load(str(PAIRS[0][0])) as PackedScene).instantiate()
	add_child(src)
	var ratio := _forearm(_skel) / maxf(_forearm(
			src.find_children("*", "Skeleton3D", true, false)[0]), 0.001)
	src.queue_free()
	print("FIT grip offset: %s -> %s (x%.2f for the shorter forearm)"
			% [_mean(offsets), _mean(offsets) * ratio, ratio])

	for pair in PAIRS:
		var worst: float = await _error(pair, Basis.from_euler(rot))
		print("FIT %-12s worst blade error %.1f deg" % [pair[1], worst])
	get_tree().quit()

## Walks a clip on both rigs at once, collecting the blade's axis, the edge's
## axis and the grip's offset in the GAME hand bone's own frame.
func _sample(pair: Array, blades: Array[Vector3], edges: Array[Vector3],
		offsets: Array[Vector3]) -> void:
	var src: Node = (load(str(pair[0])) as PackedScene).instantiate()
	add_child(src)
	var s_skel: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var s_ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var sword := _sword_of(src)
	s_ap.play(_take_of(s_ap))
	var length: float = _vis.play_scripted(str(pair[1]))
	_vis.anim_player.pause()
	for i in STEPS:
		var t := length * float(i) / float(STEPS)
		s_ap.seek(float(pair[2]) + t, true)
		_vis.anim_player.seek(t, true)
		await get_tree().process_frame
		var local := _grip_in_hand(s_skel, sword)
		blades.append(local.basis.y.normalized())
		edges.append(local.basis.x.normalized())
		offsets.append(local.origin)
	_vis.stop_scripted()
	src.queue_free()

## Worst angle, over a clip, between where `grip` points the blade and where the
## pack's own sword is.
func _error(pair: Array, grip: Basis) -> float:
	var src: Node = (load(str(pair[0])) as PackedScene).instantiate()
	add_child(src)
	var s_skel: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var s_ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var sword := _sword_of(src)
	s_ap.play(_take_of(s_ap))
	var length: float = _vis.play_scripted(str(pair[1]))
	_vis.anim_player.pause()
	var worst := 0.0
	for i in STEPS:
		var t := length * float(i) / float(STEPS)
		s_ap.seek(float(pair[2]) + t, true)
		_vis.anim_player.seek(t, true)
		await get_tree().process_frame
		var want := _grip_in_hand(s_skel, sword).basis.y.normalized()
		worst = maxf(worst, rad_to_deg((grip * Vector3.UP).normalized().angle_to(want)))
	_vis.stop_scripted()
	src.queue_free()
	return worst

## The source's sword, expressed in the GAME hand bone's frame — which is the
## frame ItemDb's "rot" and "pos" live in.
func _grip_in_hand(s_skel: Skeleton3D, sword: Node3D) -> Transform3D:
	var s_pelvis := s_skel.get_bone_global_pose(s_skel.find_bone("Hips"))
	var s_grip := s_skel.global_transform.affine_inverse() * sword.global_transform
	var in_body := s_pelvis.affine_inverse() * s_grip
	var pelvis := _skel.get_bone_global_pose(_skel.find_bone("Hips"))
	var h := pelvis.affine_inverse() * _skel.get_bone_global_pose(_skel.find_bone("RightHand"))
	return h.affine_inverse() * in_body

func _sword_of(src: Node) -> Node3D:
	for m in src.find_children("*", "MeshInstance3D", true, false):
		if String(m.name).contains("Sword"):
			return m
	return null

func _take_of(ap: AnimationPlayer) -> String:
	for c in ap.get_animation_list():
		if c != "RESET":
			return c
	return ""

## Elbow to wrist on a rig, in its own units.
func _forearm(skel: Skeleton3D) -> float:
	var elbow := skel.find_bone("RightLowerArm")
	var wrist := skel.find_bone("RightHand")
	if elbow < 0 or wrist < 0:
		return 0.0
	return skel.get_bone_global_pose(elbow).origin.distance_to(
			skel.get_bone_global_pose(wrist).origin)

func _mean(v: Array[Vector3]) -> Vector3:
	var out := Vector3.ZERO
	for a in v:
		out += a
	return out / float(v.size())

## Mean distance from the average — how much the answer wanders frame to frame.
func _spread(v: Array[Vector3]) -> float:
	var m := _mean(v)
	var out := 0.0
	for a in v:
		out += (a - m).length()
	return out / float(v.size())
