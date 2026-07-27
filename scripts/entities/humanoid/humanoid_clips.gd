class_name HumanoidClips
## THE ANIMATION IMPORT PIPELINE: taking a Mixamo (or sword-pack) FBX and
## turning it into a clip this game's skeleton can actually play. Split out of
## humanoid_visual.gd, which was the rig, the playback state machine and this
## all at once — and this half runs ONCE per character build and then never
## again, while the rest runs every frame.
##
## Everything a clip needs doing to it before it is playable lives here:
##
##   * REPATH. Imported tracks target %GeneralSkeleton:<bone>; they have to be
##     rewritten onto this skeleton's real path, and tracks for bones the target
##     rig does not have are dropped.
##   * DE-ROOT. The Mixamo clips are not "in place": the Hips position track
##     carries real root motion, which drags the visual off the collision
##     capsule and snaps it back on loop. Gameplay code moves the capsule, so
##     the horizontal hips motion is pinned and only the vertical bounce kept.
##   * SLICE. One imported cycle can provide a phase of itself (the jump's
##     airborne portion) instead of needing a pre-trimmed FBX.
##   * GRAFT. An upper body from one clip over the legs of another, which is how
##     a guarding fighter circles without dropping their hands.
##
## All static: a clip is data in and data out, and none of it needs to know
## which character asked.

## Resampling rate for a slice — the FBX import rate, so nothing is lost.
const SLICE_FPS := 30.0

## The one animation out of an imported clip FBX, as a copy we can chew on.
## Mixamo exports call theirs "mixamo_com"; the sword pack names its take after
## the file, so take whatever single animation is in there rather than a name.
static func load_clip(path: String) -> Animation:
	var src: Node = (load(path) as PackedScene).instantiate()
	var src_ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var take := "mixamo_com"
	if not src_ap.has_animation(take):
		for candidate in src_ap.get_animation_list():
			if candidate != "RESET":
				take = candidate
				break
	var anim: Animation = src_ap.get_animation(take).duplicate(true)
	src.free()
	return anim

static func find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := find_skeleton(c)
		if r:
			return r
	return null

## Points an imported clip's tracks at `skel_path` and drops any for bones this
## rig does not have. `adapt_hips` is the character's own hips remap — a rig
## that moved its pelvis (a stubby-legged voxel NPC) rebases the motion through
## it, and it is the identity for a human-proportioned one.
static func repath(anim: Animation, skeleton: Skeleton3D, skel_path: String,
		adapt_hips: Callable) -> void:
	for i in range(anim.get_track_count() - 1, -1, -1):
		var p := anim.track_get_path(i)
		if p.get_subname_count() < 1:
			anim.remove_track(i)
			continue
		var bone := p.get_subname(0)
		if skeleton.find_bone(bone) == -1:
			anim.remove_track(i)
			continue
		anim.track_set_path(i, NodePath(skel_path + ":" + bone))
		# De-root: keep the vertical bounce, pin the horizontal travel. Without
		# it the visual walks off its own collision capsule and snaps back every
		# loop, which is what rubber-banding looked like.
		if bone == "Hips" and anim.track_get_type(i) == Animation.TYPE_POSITION_3D \
				and anim.track_get_key_count(i) > 0:
			var first: Vector3 = anim.track_get_key_value(i, 0)
			for k in anim.track_get_key_count(i):
				var v: Vector3 = anim.track_get_key_value(i, k)
				anim.track_set_key_value(i, k, adapt_hips.call(Vector3(first.x, v.y, first.z)))

## Hips position at `time` in an un-repathed imported clip — the neutral pose
## reference `pin_hips` freezes to. Read off the FULL clip before any slicing:
## a slice starting mid-motion has no neutral frame of its own.
static func sample_hips(anim: Animation, time: float) -> Vector3:
	for i in anim.get_track_count():
		var p := anim.track_get_path(i)
		if p.get_subname_count() > 0 and p.get_subname(0) == "Hips" \
				and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			return anim.position_track_interpolate(i, time)
	return Vector3.ZERO

## Freezes the hips at `neutral`, killing the clip's VERTICAL root motion too
## (unlike `repath`, which keeps the Y bounce). The jump clip lifts the hips
## ~1 m, but gameplay physics already moves the capsule — keeping that rise
## would double-count it and float the model off the collision shape.
static func pin_hips(anim: Animation, neutral: Vector3) -> void:
	for i in anim.get_track_count():
		var p := anim.track_get_path(i)
		if p.get_subname_count() > 0 and p.get_subname(0) == "Hips" \
				and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(i):
				anim.track_set_key_value(i, k, neutral)

## Extracts [from, to] of `anim` as a standalone clip, resampled at the import
## rate so nothing is lost.
static func slice(anim: Animation, from: float, to: float) -> Animation:
	var out := Animation.new()
	var dur := to - from
	out.length = dur
	for i in anim.get_track_count():
		var type := anim.track_get_type(i)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
				Animation.TYPE_SCALE_3D]:
			continue
		var t := out.add_track(type)
		out.track_set_path(t, anim.track_get_path(i))
		for s in int(ceil(dur * SLICE_FPS)) + 1:
			var local := minf(float(s) / SLICE_FPS, dur)
			var at := from + local
			match type:
				Animation.TYPE_POSITION_3D:
					out.track_insert_key(t, local, anim.position_track_interpolate(i, at))
				Animation.TYPE_ROTATION_3D:
					out.track_insert_key(t, local, anim.rotation_track_interpolate(i, at))
				_:
					out.track_insert_key(t, local, anim.scale_track_interpolate(i, at))
	return out

## Replaces target's upper-body tracks with source's (legs keep target's).
## The Hips ROTATION also comes from source: the strafe clips turn the hips
## toward the travel direction (with the spine counter-rotating to face
## forward), so once the spine is replaced the torso would face sideways --
## sourcing the hips orientation keeps the whole torso squared at the player,
## while the hips POSITION (bounce) and leg tracks stay from the strafe.
## The source loop is TILED over the target's length: a short guard bob keeps
## cycling under a longer stride instead of freezing on its last pose.
static func graft_upper_body(target: Animation, source: Animation) -> void:
	for i in range(target.get_track_count() - 1, -1, -1):
		if _is_grafted(target.track_get_path(i).get_subname(0), target.track_get_type(i)):
			target.remove_track(i)
	var cycles := 1
	if source.length > 0.05:
		cycles = clampi(ceili(target.length / source.length), 1, 8)
	for i in source.get_track_count():
		var path := source.track_get_path(i)
		var type := source.track_get_type(i)
		if not _is_grafted(path.get_subname(0), type):
			continue
		var t := target.add_track(type)
		target.track_set_path(t, path)
		for c in cycles:
			for k in source.track_get_key_count(i):
				var time := c * source.length + source.track_get_key_time(i, k)
				if time > target.length:
					break
				target.track_insert_key(t, time, source.track_get_key_value(i, k))

static func _is_grafted(bone: String, type: int) -> bool:
	if bone == "Hips":
		return type == Animation.TYPE_ROTATION_3D
	return is_upper_bone(bone)

## Upper body = spine chain and everything hanging off it; legs + hips stay.
static func is_upper_bone(bone: String) -> bool:
	if bone in ["Spine", "Chest", "UpperChest", "Neck", "Head"]:
		return true
	for part in ["Shoulder", "Arm", "Hand", "Thumb", "Index", "Middle", "Ring", "Little"]:
		if bone.contains(part):
			return true
	return false
