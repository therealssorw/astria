class_name NpcReproportion
## RESHAPING THE SKELETON onto the art, rather than stretching the art onto the
## skeleton. Split out of NpcRig because it is the one idea that makes the whole
## approach work and deserves to be readable alone.
##
## It is only safe because the retargeted clips are ROTATION-ONLY: every bone
## but Hips has just a rotation track, so bone rest POSITIONS define the
## silhouette and nothing in an animation fights them. Legs get stubby, the head
## gets big, and the clips still play correctly. If the animations are ever
## reimported with per-bone position tracks this breaks silently — which is why
## test_npc_builder checks that animating still moves the reshaped bones.

## Where the untouched bone rests are stashed on a skeleton we have reshaped.
const SOURCE_REST_META := "npc_rig_source_rest"

## Moves every bone's rest POSITION onto the voxel model's proportions, keeping
## each bone's rest ORIENTATION untouched so the clips' local rotations still
## mean what they meant on Rouge.
static func apply(skeleton: Skeleton3D, layout: Dictionary) -> void:
	# Always fit from the ORIGINAL rig, never from the last fit, so re-rigging
	# the same skeleton (which the builder's preview does on every keystroke)
	# converges instead of compounding.
	var src: Dictionary = skeleton.get_meta(SOURCE_REST_META, {})
	if src.is_empty():
		for i in skeleton.get_bone_count():
			src[i] = skeleton.get_bone_global_rest(i)
		skeleton.set_meta(SOURCE_REST_META, src)

	var ref := _reference_landmarks(skeleton, src)
	# Kept so NpcVisual can rebase the clips' Hips position track: it was
	# authored around a pelvis at this height, and ours has just moved.
	layout["ref_hip_y"] = ref["hip_y"]
	# Height is remapped through the shared landmarks; width is a per-chain
	# factor, because arms, legs and torso widen by different amounts.
	var y_from: Array[float] = [0.0, ref["hip_y"], ref["arm_y"], ref["neck_y"], ref["head_y"], ref["crown"]]
	var y_to: Array[float] = [0.0, layout["hip_y"], layout["arm_y"], layout["neck_y"],
			layout["head_y"], layout["crown"]]
	var k := {
		"leg": _ratio(layout["leg_x"], ref["leg_x"]),
		"body": _ratio(layout["shoulder_x"], ref["shoulder_x"]),
	}
	# The arm is fitted at TWO points -- the shoulder and the hand -- where the
	# other chains get away with one scale. One factor can only ever put the hand
	# in the right place OR the shoulder, and the human rig it is scaled from has
	# its shoulders a quarter of the way out to its hands; a voxel character,
	# being nearly as wide as its arms are long, needs them most of the way out.
	# Scaled to land the hands, its shoulders end up buried in its chest.
	var arm_from: Array[float] = [0.0, ref["upper_arm_x"], ref["hand_x"]]
	var arm_to: Array[float] = [0.0, layout["arm_root_x"], layout["hand_x"]]
	var depth: float = _ratio(layout["crown"], ref["crown"])

	var fitted := {}
	for i in skeleton.get_bone_count():
		var g: Transform3D = src[i]
		var chain: String = _chain_of(skeleton, i)
		# Sign carries the side: the ladder is measured on the left and mirrored.
		var x: float = signf(g.origin.x) * _remap(absf(g.origin.x), arm_from, arm_to) \
				if chain == "arm" else g.origin.x * k[chain]
		fitted[i] = Transform3D(g.basis, Vector3(x, _remap(g.origin.y, y_from, y_to), g.origin.z * depth))
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		var local: Transform3D = fitted[i]
		if parent >= 0:
			local = (fitted[parent] as Transform3D).affine_inverse() * local
		skeleton.set_bone_rest(i, local)
	skeleton.reset_bone_poses()

static func _reference_landmarks(skeleton: Skeleton3D, src: Dictionary) -> Dictionary:
	var crown := 0.0
	for i in skeleton.get_bone_count():
		crown = maxf(crown, (src[i] as Transform3D).origin.y)
	return {
		"hip_y": _bone(skeleton, src, "Hips", 0.96, true),
		"arm_y": _bone(skeleton, src, "LeftUpperArm", 1.44, true),
		"neck_y": _bone(skeleton, src, "Neck", 1.53, true),
		"head_y": _bone(skeleton, src, "Head", 1.63, true),
		# The topmost bone is the skull base, not the crown; the mesh carries on
		# above it, so allow for that when scaling depth and total height.
		"crown": crown * 1.07,
		"hand_x": _bone(skeleton, src, "LeftHand", 0.74, false),
		"upper_arm_x": _bone(skeleton, src, "LeftUpperArm", 0.19, false),
		"leg_x": _bone(skeleton, src, "LeftUpperLeg", 0.10, false),
		"shoulder_x": _bone(skeleton, src, "LeftShoulder", 0.015, false),
	}

## A landmark off the ORIGINAL rest pose: the bone's height (`vertical`) or its
## distance out from the centre line.
static func _bone(skeleton: Skeleton3D, src: Dictionary, bone: String,
		fallback: float, vertical: bool) -> float:
	var i := skeleton.find_bone(bone)
	if i < 0:
		return fallback
	var o: Vector3 = (src[i] as Transform3D).origin
	return o.y if vertical else absf(o.x)

static func _ratio(target: float, reference: float) -> float:
	return target / reference if absf(reference) > 0.0001 else 1.0

static func _remap(y: float, from: Array[float], to: Array[float]) -> float:
	for i in range(1, from.size()):
		if y <= from[i] or i == from.size() - 1:
			var span := from[i] - from[i - 1]
			var t := 0.0 if absf(span) < 0.0001 else (y - from[i - 1]) / span
			return to[i - 1] + (to[i] - to[i - 1]) * t
	return y

## Which limb a bone belongs to, so it widens with that limb. Covers the rig's
## non-humanoid extras too (UE Manny's twist and IK bones), which have no
## animation tracks but still have to end up somewhere sane.
static func _chain_of(skeleton: Skeleton3D, bone: int) -> String:
	var bone_name := skeleton.get_bone_name(bone)
	if bone_name.begins_with("ik_hand"):
		return "arm"
	if bone_name.begins_with("ik_foot"):
		return "leg"
	var at := bone
	while at >= 0:
		var n := skeleton.get_bone_name(at)
		if n == "LeftShoulder" or n == "RightShoulder":
			return "arm"
		if n == "LeftUpperLeg" or n == "RightUpperLeg":
			return "leg"
		at = skeleton.get_bone_parent(at)
	return "body"
