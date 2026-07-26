class_name HumanoidVisual
extends Node3D
## Shared rig + animation driver for every humanoid in the game.
##
## Everything here is skeleton-agnostic: it wants a Skeleton3D whose bones are
## named after Godot's SkeletonProfileHumanoid, and it builds the Mixamo clip
## library against it. Subclasses only have to supply the model:
##
##   RougeVisual  -- the UE Manny mesh straight out of rouge.fbx
##   NpcVisual    -- voxel parts auto-rigged onto a copy of that same skeleton
##
## That is what lets a built NPC animate off exactly the same clips as the
## player: both end up as a humanoid-profile skeleton with the retargeted
## tracks repathed onto it.

const ANIM_DIR := "res://Assets/Animations/Humanoid/"
const CLIPS := {
	# Two idles. "idle" is what standing still looks like; stand still long
	# enough (IDLE_LONG_AFTER) and the character drops into "idle_long" instead
	# and stays there until something moves them. Swapping which pose is which
	# is swapping these two paths — nothing else knows what is in either clip.
	"idle": {"path": ANIM_DIR + "Movement/Idle/Idle.fbx", "speed": 1.0, "loop": true},
	"idle_long": {"path": ANIM_DIR + "Movement/Idle/Offensive Idle.fbx", "speed": 1.0, "loop": true},
	"walk": {"path": ANIM_DIR + "Movement/Walking/Walking.fbx", "speed": 1.0, "loop": true},
	"run": {"path": ANIM_DIR + "Movement/Running/Running.fbx", "speed": 1.0, "loop": true},
	"slide": {"path": ANIM_DIR + "Movement/Sliding/Running Slide.fbx", "speed": 1.0, "loop": true},
	"block": {"path": ANIM_DIR + "Combat/Blocking/Boxing.fbx", "speed": 1.0, "loop": true},
	# One 1.9s Mixamo cycle: crouch, launch, apex, touchdown, recover. Only the
	# airborne slice is used. The leading crouch is anticipation the gameplay
	# never has (a jump press sets velocity.y the same frame, so a crouch would
	# play while already rising), and the trailing landing would fight the
	# grounded clips, so the slice runs from mid-extension (0.45, just before
	# the feet leave at 0.50) to touchdown (1.10). It does not loop: the last
	# frame is the legs-reaching-down pose, which holds for the rest of a fall.
	"jump": {"path": ANIM_DIR + "Movement/Jumping/Jumping.fbx", "speed": 1.0, "loop": false,
			"slice": [0.45, 1.10], "pin_hips_at": 0.0},
	"strafe_l": {"path": ANIM_DIR + "Movement/Strafing/Left Strafe Walking.fbx", "speed": 1.0, "loop": true},
	"strafe_r": {"path": ANIM_DIR + "Movement/Strafing/Right Strafe Walking.fbx", "speed": 1.0, "loop": true},
	"walk_back": {"path": ANIM_DIR + "Movement/Walking/Walking Backwards.fbx", "speed": 1.0, "loop": true},
	"light_0": {"path": ANIM_DIR + "Combat/LightM1/Punching.fbx", "speed": 1.55, "loop": false},
	"light_1": {"path": ANIM_DIR + "Combat/LightM1/Illegal Elbow Punch.fbx", "speed": 1.55, "loop": false},
	"light_2": {"path": ANIM_DIR + "Combat/LightM1/Elbow Uppercut Combo.fbx", "speed": 1.55, "loop": false},
	"heavy": {"path": ANIM_DIR + "Combat/HeavyM1/Cross Punch.fbx", "speed": 1.35, "loop": false},
	# --- with a sword in hand (Mocap Online TC pack, MotusMan rig) ---
	# The pack ships ONE 5.5s combo take, and most of it is spent in a deep
	# mocap fighting crouch: the hips sit at 1.00 standing and sink to 0.75
	# through the middle cuts and to 0.67 in the lunge at ~4.1, which on this
	# character reads as squatting. So only the FIRST cut is used — it starts
	# from the standing ready pose (~0.6), the blade goes through at ~0.8, and
	# it is out before the crouch settles. Every light swing plays it, and the
	# heavy is that same slash stretched over the longer heavy swing.
	"sword_idle": {"path": ANIM_DIR + "Sword/Idle/Sword Idle.fbx", "speed": 1.0, "loop": true},
	"sword_walk": {"path": ANIM_DIR + "Sword/Walking/Sword Walk.fbx", "speed": 1.0, "loop": true},
	"sword_run": {"path": ANIM_DIR + "Sword/Running/Sword Run.fbx", "speed": 1.0, "loop": true},
	# "speed" here only matters if something plays this clip outside an attack:
	# on_attack_started always stretches it to the punch it stands in for.
	# Trimmed to the cut itself: the arm is already moving at 0.66, peaks at
	# 0.80 and is spent by 0.90. The raise before it and the drift after are
	# not in the clip at all — the blend out of idle covers the lead-in.
	"sword_slash": {"path": ANIM_DIR + "Sword/Attack/Sword Combo.fbx", "speed": 1.55,
			"loop": false, "slice": [0.66, 0.90]},
}
## Clip swaps applied while a sword is in hand. Anything not listed keeps its
## bare-handed clip, so blocking, sliding and jumping are unchanged. Every
## swing is the same slash — the take only has one that stays standing — and
## the heavy differs only in being stretched over the heavy's longer window,
## which is what makes it read as the slow, committed version. Repeats still
## cross-blend through the "__alt" copy.
const SWORD_CLIPS := {
	# "idle_long" maps to the same sword idle as "idle" on purpose: a character
	# with a blade in hand has one standing pose, so the long-idle swap happens
	# and nothing about it shows.
	"idle": "sword_idle", "idle_long": "sword_idle",
	"walk": "sword_walk", "run": "sword_run",
	"light_0": "sword_slash", "light_1": "sword_slash",
	"light_2": "sword_slash", "heavy": "sword_slash",
}
## Guard-up movement clips built at load: legs from the locomotion clip on the
## right, upper body grafted from the block stance — so circling an opponent
## behind a guard keeps the fists up instead of swinging the arms.
const BLOCK_MOVE := {
	"block_fwd": "walk", "block_back": "walk_back",
	"block_l": "strafe_l", "block_r": "strafe_r",
}
## Ground speed each locomotion clip looks right at, as a fraction of the
## character's run speed. Playback is scaled by how far the real speed is off,
## so sidesteps and backpedals don't ice-skate.
const LOCO_NOMINAL := {
	"walk": 0.4, "run": 1.0, "walk_back": 0.45,
	"strafe_l": 0.5, "strafe_r": 0.5,
	"block_fwd": 0.4, "block_back": 0.45, "block_l": 0.5, "block_r": 0.5,
}
## How much quicker than the swing window a weapon's clip plays. Stretching the
## slash over the whole window exactly makes it drag — this runs the blade
## through a bit early and holds the finish for the rest of the window, so the
## cut snaps without touching a single gameplay timing.
const ARMED_SWING_RATE := 1.3
# gameplay caps so long Mixamo tails don't make swings sluggish
const LIGHT_MAX_DUR := [0.52, 0.6, 0.74]
const HEAVY_MAX_DUR := 1.0
# hit reactions: how hard a recoil leans back, and how fast it settles
const REACT_DECAY := 1.6
const STAGGER_LEAN := -0.3
## Animation rate during hitstop — the near-freeze that gives a punch weight.
const HITSTOP_SCALE := 0.06
## Seconds of unbroken standing still before "idle" gives way to "idle_long".
## Anything at all — a step, a swing, a guard, a hit — puts it back to zero, so
## this is time spent doing NOTHING, not time since the last idle started.
const IDLE_LONG_AFTER := 15.0

## Per-character scale on attack clip playback (and thus swing timings);
## lets the player punch faster than enemies sharing this visual.
@export var attack_speed_mult := 1.0

## Bone a carried item hangs off. Every rig here is retargeted onto
## SkeletonProfileHumanoid, so the name is the same for Rouge and for NPCs.
const HOLD_BONE := "RightHand"

var model: Node3D
var skeleton: Skeleton3D
var held_id := ""          # item currently drawn in the hand ("" = empty)
var _held_node: Node3D     # the BoneAttachment3D carrying it
var anim_player: AnimationPlayer
var clip_lengths := {}
var _mats: Array[StandardMaterial3D] = []
var _flash_time := 0.0
var _current_key := ""
var _lean_target := 0.0
var _react_lean := 0.0     # transient recoil from a hit, decays back to 0
var _hitstop_time := 0.0   # >0: animation nearly frozen (impact emphasis)
var _stagger_time := 0.0   # >0: helpless recoil pose overrides the clip
var _idle_time := 0.0      # seconds stood still; past IDLE_LONG_AFTER, idle_long

## Whether entering the tree builds the Mixamo clip library as well as the
## model. Set it before add_child; a static editor preview does not need
## fifteen FBX loads.
var build_clips := true

var _built := false

func _ready() -> void:
	build(build_clips)

## Assembles the character. Entering the tree does this by itself -- including
## under the editor, where tool code that says `SomeVisual.new()` gets a live
## instance whose notifications fire like any other. Building is therefore
## strictly once per node: a second call would parent a second model, a second
## skeleton and a second set of meshes in exactly the same place, and the two
## copies would z-fight over every pixel.
func build(with_animations := true) -> void:
	if _built:
		return
	_built = true
	_build_model()
	if skeleton == null:
		push_error("%s built no skeleton" % get_script().resource_path)
		return
	if not with_animations:
		return

	anim_player = AnimationPlayer.new()
	add_child(anim_player)
	build_animations()
	_play("idle")

## Rebuilds the clip library against the current skeleton. Called once at
## _ready, and again by anything that moves the rig's pelvis afterwards -- the
## Hips track is baked per-rig by _adapt_hips, so it goes stale when that does.
func build_animations() -> void:
	if anim_player == null:
		return
	if anim_player.has_animation_library("lib"):
		anim_player.remove_animation_library("lib")
	_current_key = ""
	clip_lengths.clear()
	var lib := AnimationLibrary.new()
	var skel_path := str(anim_player.get_node(anim_player.root_node).get_path_to(skeleton))
	var keys := _clip_keys()
	for key in keys:
		var cfg: Dictionary = CLIPS[key]
		var anim := _load_clip(cfg.path)
		# Read the neutral standing hips off the FULL clip before any slicing:
		# a slice starting mid-motion has no neutral frame of its own.
		var neutral_hips := Vector3.ZERO
		if cfg.has("pin_hips_at"):
			neutral_hips = _sample_hips(anim, cfg.pin_hips_at)
		if cfg.has("slice"):
			anim = _slice(anim, cfg.slice[0], cfg.slice[1])
		_repath_tracks(anim, skel_path)
		if cfg.has("pin_hips_at"):
			_pin_hips(anim, _adapt_hips(neutral_hips))
		if cfg.loop:
			anim.loop_mode = Animation.LOOP_LINEAR
		clip_lengths[key] = anim.length
		lib.add_animation(key, anim)
		if not cfg.loop:
			# second name for the same clip so a restart can cross-blend
			# (see _restart) instead of snapping to the first frame
			lib.add_animation(key + "__alt", anim)
	# Guard-up movement: the block stance's upper body over walking/strafing
	# legs, so a guarding fighter can circle without dropping their hands.
	if "block" in keys:
		var block_anim := lib.get_animation("block")
		for key: String in BLOCK_MOVE:
			var base_key: String = BLOCK_MOVE[key]
			if base_key not in keys:
				continue
			var moving: Animation = lib.get_animation(base_key).duplicate(true)
			_graft_upper_body(moving, block_anim)
			clip_lengths[key] = moving.length
			lib.add_animation(key, moving)
	# Layered strafes: keep only the legs of the strafe clips and graft the
	# upper body from Bouncing Fight Idle on top, so strafing keeps a combat
	# guard up. The fight idle is used ONLY as this upper-body source.
	if "strafe_l" in keys or "strafe_r" in keys:
		var stance_anim := _load_clip(ANIM_DIR + "Combat/Stances/Bouncing Fight Idle.fbx")
		_repath_tracks(stance_anim, skel_path)
		for strafe_key in ["strafe_l", "strafe_r"]:
			if strafe_key in keys:
				_graft_upper_body(lib.get_animation(strafe_key), stance_anim)

	anim_player.add_animation_library("lib", lib)

## The one animation out of an imported clip FBX, as a copy we can chew on.
## Mixamo exports call theirs "mixamo_com"; the sword pack names its take after
## the file, so take whatever single animation is in there rather than a name.
func _load_clip(path: String) -> Animation:
	var src: Node = (load(path) as PackedScene).instantiate()
	var src_ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var name := "mixamo_com"
	if not src_ap.has_animation(name):
		for candidate in src_ap.get_animation_list():
			if candidate != "RESET":
				name = candidate
				break
	var anim: Animation = src_ap.get_animation(name).duplicate(true)
	src.free()
	return anim

## Override to create `model` (added as a child, holding `skeleton`) and fill
## `_mats` with the materials `flash` should tint.
func _build_model() -> void:
	push_error("HumanoidVisual._build_model is abstract")

## Which CLIPS entries to build. Characters that never fight can skip the
## combat clips and save the FBX loads.
func _clip_keys() -> Array:
	return CLIPS.keys()

## Hook for rigs whose hips do not sit where the clips expect. The Mixamo
## tracks were authored around a human-proportioned pelvis; a rig that moved
## it (a stubby-legged voxel NPC) remaps the motion here. Identity by default.
func _adapt_hips(v: Vector3) -> Vector3:
	return v

## Upper body = spine chain and everything hanging off it; legs + hips stay.
func _is_upper_bone(bone: String) -> bool:
	if bone in ["Spine", "Chest", "UpperChest", "Neck", "Head"]:
		return true
	for part in ["Shoulder", "Arm", "Hand", "Thumb", "Index", "Middle", "Ring", "Little"]:
		if bone.contains(part):
			return true
	return false

## Replaces target's upper-body tracks with source's (legs keep target's).
## The Hips ROTATION also comes from source: the strafe clips turn the hips
## toward the travel direction (with the spine counter-rotating to face
## forward), so once the spine is replaced the torso would face sideways --
## sourcing the hips orientation keeps the whole torso squared at the player,
## while the hips POSITION (bounce) and leg tracks stay from the strafe.
## The source loop is TILED over the target's length: a short guard bob keeps
## cycling under a longer stride instead of freezing on its last pose.
func _graft_upper_body(target: Animation, source: Animation) -> void:
	for i in range(target.get_track_count() - 1, -1, -1):
		if _is_grafted_track(target.track_get_path(i).get_subname(0), target.track_get_type(i)):
			target.remove_track(i)
	var cycles := 1
	if source.length > 0.05:
		cycles = clampi(ceili(target.length / source.length), 1, 8)
	for i in source.get_track_count():
		var path := source.track_get_path(i)
		var type := source.track_get_type(i)
		if not _is_grafted_track(path.get_subname(0), type):
			continue
		var t := target.add_track(type)
		target.track_set_path(t, path)
		for c in cycles:
			for k in source.track_get_key_count(i):
				var time := c * source.length + source.track_get_key_time(i, k)
				if time > target.length:
					break
				target.track_insert_key(t, time, source.track_get_key_value(i, k))

func _is_grafted_track(bone: String, type: int) -> bool:
	if bone == "Hips":
		return type == Animation.TYPE_ROTATION_3D
	return _is_upper_bone(bone)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _repath_tracks(anim: Animation, skel_path: String) -> void:
	# imported tracks target %GeneralSkeleton:<bone>; rewrite to our skeleton's
	# real path and drop tracks for bones the target rig doesn't have
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
		# The Mixamo clips are not "in place": the Hips position track carries
		# real root motion, which drags the visual off the collision capsule
		# and snaps it back on loop (rubber banding). Gameplay code moves the
		# capsule, so pin the horizontal hips motion to the first frame and
		# keep only the vertical bounce.
		if bone == "Hips" and anim.track_get_type(i) == Animation.TYPE_POSITION_3D \
				and anim.track_get_key_count(i) > 0:
			var first: Vector3 = anim.track_get_key_value(i, 0)
			for k in anim.track_get_key_count(i):
				var v: Vector3 = anim.track_get_key_value(i, k)
				anim.track_set_key_value(i, k, _adapt_hips(Vector3(first.x, v.y, first.z)))

## Hips position at `time` in an un-repathed imported clip (the neutral pose
## reference for _pin_hips).
func _sample_hips(anim: Animation, time: float) -> Vector3:
	for i in anim.get_track_count():
		var p := anim.track_get_path(i)
		if p.get_subname_count() > 0 and p.get_subname(0) == "Hips" \
				and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			return anim.position_track_interpolate(i, time)
	return Vector3.ZERO

## Extracts [from, to] of `anim` as a standalone clip, resampled at the 30 fps
## import rate so nothing is lost. Lets one imported cycle provide a phase of
## itself (the jump's airborne portion) instead of needing a pre-trimmed FBX.
func _slice(anim: Animation, from: float, to: float) -> Animation:
	const FPS := 30.0
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
		for s in int(ceil(dur * FPS)) + 1:
			var local := minf(float(s) / FPS, dur)
			var at := from + local
			match type:
				Animation.TYPE_POSITION_3D:
					out.track_insert_key(t, local, anim.position_track_interpolate(i, at))
				Animation.TYPE_ROTATION_3D:
					out.track_insert_key(t, local, anim.rotation_track_interpolate(i, at))
				_:
					out.track_insert_key(t, local, anim.scale_track_interpolate(i, at))
	return out

## Freezes the hips at `neutral`, killing the clip's vertical root motion too
## (unlike _repath_tracks, which keeps the Y bounce). The jump clip lifts the
## hips ~1m, but gameplay physics already moves the capsule -- keeping that rise
## would double-count it and float the model off the collision shape.
func _pin_hips(anim: Animation, neutral: Vector3) -> void:
	for i in anim.get_track_count():
		var p := anim.track_get_path(i)
		if p.get_subname_count() > 0 and p.get_subname(0) == "Hips" \
				and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(i):
				anim.track_set_key_value(i, k, neutral)

## The clip actually played for a logical key: with a sword in hand the sword
## set stands in wherever it has an entry, and falls back to the bare-handed
## clip if that one wasn't built (an enemy with a trimmed clip list).
func _clip_for(key: String) -> String:
	if not _sword_style() or not SWORD_CLIPS.has(key):
		return key
	var swapped: String = SWORD_CLIPS[key]
	if anim_player and anim_player.has_animation("lib/" + swapped):
		return swapped
	return key

## Is what's in this character's hand something with its own animation set?
func _sword_style() -> bool:
	return str(ItemDb.hold_config(held_id).get("anim_set", "")) == "sword"

func _play(base_key: String, blend := 0.2) -> void:
	var key := _clip_for(base_key)
	if anim_player == null or _current_key == key:
		return
	_current_key = key
	anim_player.play("lib/" + key, blend, _clip_speed(key))

func _restart(base_key: String, blend := 0.18, speed_override := -1.0) -> void:
	var key := _clip_for(base_key)
	# No stop() here -- stopping kills the cross-blend and makes the new clip
	# pop in at its first pose. Restarting the SAME clip can't blend into
	# itself either, so each attack clip is registered twice ("key" and
	# "key__alt") and we alternate names to force a real tweened transition.
	_current_key = key
	var anim_name := "lib/" + key
	if anim_player.current_animation == anim_name:
		anim_name = "lib/" + key + "__alt"
	anim_player.play(anim_name, blend, speed_override if speed_override > 0.0 else _clip_speed(key))

func _clip_speed(key: String) -> float:
	# attack clips (the non-looping ones) scale with the character's mult;
	# an explicit speed_override (inspector-timed enemy swings) bypasses this
	if not CLIPS.has(key):
		return 1.0 # generated guard-movement variant, played at clip rate
	var cfg: Dictionary = CLIPS[key]
	return cfg.speed if cfg.loop else cfg.speed * attack_speed_mult

## Gameplay timing for a swing, derived from the actual clip at montage rate:
## "hit" is when contact lands, "combo" the earliest the NEXT punch may start
## (well before the clip's recovery tail, which is what makes a chain flow).
## Deliberately measured off the BARE-HANDED clip even with a weapon out: a
## sword swings on exactly the same clock as a punch, so what you are carrying
## never changes how fast you fight. The weapon's own clip is stretched to fit
## in on_attack_started.
func get_attack_info(heavy: bool, combo_index: int) -> Dictionary:
	if heavy:
		var dur: float = minf(clip_lengths["heavy"] / CLIPS["heavy"].speed, HEAVY_MAX_DUR) / attack_speed_mult
		return {"duration": dur, "hit": dur * 0.45, "combo": dur * 0.85}
	var i := clampi(combo_index, 0, 2)
	var key := "light_%d" % i
	var d: float = minf(clip_lengths[key] / CLIPS[key].speed, LIGHT_MAX_DUR[i]) / attack_speed_mult
	return {"duration": d, "hit": d * 0.34, "combo": d * 0.62}

## duration > 0 stretches the clip playback to exactly that many seconds
## (used by enemies whose swing timing is set in the inspector). A weapon clip
## is stretched too, to whatever the punch it replaces takes — the swing is the
## same length armed or not, so the animation has to be as well.
func on_attack_started(heavy: bool, combo_index: int, duration := -1.0) -> void:
	var base_key := "heavy" if heavy else "light_%d" % clampi(combo_index, 0, 2)
	var key := _clip_for(base_key)
	var target := duration
	if target <= 0.0 and key != base_key:
		target = float(get_attack_info(heavy, combo_index)["duration"]) / ARMED_SWING_RATE
	var speed := -1.0
	if target > 0.0:
		speed = clip_lengths[key] / target
	_restart(base_key, 0.18, speed)

# ---------------- held item ----------------
#
# What a character carries is a model parented to the hand BONE, so it follows
# every clip without any of them knowing about it. The id comes from the server
# (see Net's public registry) — this only draws it.

## Put `id` in this character's hand, or "" for empty hands. Items with no
## "hold" entry in ItemDb are carried invisibly, which is what the icons in the
## bag are for. Safe to call every frame: the same id twice does nothing.
func set_held_item(id: String) -> void:
	if id == held_id:
		return
	held_id = id
	if is_instance_valid(_held_node):
		# unparent before freeing: queue_free leaves it hanging off the bone
		# until the frame ends, and swapping items twice in one frame would
		# then briefly draw both
		var parent := _held_node.get_parent()
		if parent:
			parent.remove_child(_held_node)
		_held_node.queue_free()
	_held_node = null
	if id == "" or skeleton == null:
		return
	var cfg := ItemDb.hold_config(id)
	if cfg.is_empty():
		return
	var bone := skeleton.find_bone(HOLD_BONE)
	if bone < 0:
		push_warning("HumanoidVisual: no '%s' bone to hold %s with" % [HOLD_BONE, id])
		return
	var scene := load(str(cfg["model"])) as PackedScene
	if scene == null:
		push_warning("HumanoidVisual: %s has no model at %s" % [id, cfg["model"]])
		return

	var attach := BoneAttachment3D.new()
	attach.name = "HeldItem"
	attach.bone_name = HOLD_BONE
	skeleton.add_child(attach)
	var inst: Node3D = scene.instantiate()
	attach.add_child(inst)
	inst.transform = Transform3D(
			Basis.from_euler(Vector3(
				deg_to_rad(cfg["rot"].x), deg_to_rad(cfg["rot"].y), deg_to_rad(cfg["rot"].z))),
			cfg["pos"])
	# "scale" is a plain number for a uniform blow-up, or a Vector3 when a model
	# needs its cross-section fattened without growing longer as well
	var s: Variant = cfg["scale"]
	inst.scale = s if s is Vector3 else Vector3.ONE * float(s)
	_tint_held(inst, cfg["tint"])
	_held_node = attach

## One model serves several items, so a tint stands in for different metals
## until each has art of its own. White leaves the material alone.
func _tint_held(root: Node, tint: Color) -> void:
	if tint == Color(1, 1, 1):
		return
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		for i in mesh_inst.get_surface_override_material_count():
			var mat := mesh_inst.mesh.surface_get_material(i)
			var over := (mat.duplicate() if mat else StandardMaterial3D.new()) as BaseMaterial3D
			over.albedo_color = over.albedo_color * tint
			mesh_inst.set_surface_override_material(i, over)

func flash(color: Color, duration := 0.15) -> void:
	_flash_time = duration
	for m in _mats:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.6

## Near-freeze the animation for a moment — the impact emphasis that makes a
## landed punch feel like it connected with something solid.
func hitstop(duration := 0.07) -> void:
	_hitstop_time = maxf(_hitstop_time, duration)

## Snap recoil from taking a hit (leans back, settles on its own).
func hit_react(strength := 0.3) -> void:
	_react_lean = -strength

## Helpless pose for a parried / guard-broken fighter: rocked back, no clip
## of their own, for as long as the punish window lasts.
func play_stagger(duration: float) -> void:
	_stagger_time = maxf(_stagger_time, duration)
	_react_lean = STAGGER_LEAN

func tick(delta: float, anim: String, _t := 0.0, speed_ratio := 0.0) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			for m in _mats:
				m.emission_enabled = false
	_hitstop_time = maxf(0.0, _hitstop_time - delta)
	_stagger_time = maxf(0.0, _stagger_time - delta)
	_react_lean = move_toward(_react_lean, 0.0, delta * REACT_DECAY)

	# Standing still is the only thing that runs the long-idle clock, and being
	# rocked back by a hit is not standing still.
	if anim == "idle" and _stagger_time <= 0.0:
		_idle_time += delta
	else:
		_idle_time = 0.0

	_lean_target = 0.0
	var loco := "" # locomotion clip, if any — its playback tracks ground speed
	if _stagger_time > 0.0:
		_play("idle")
		_lean_target = STAGGER_LEAN
	else:
		match anim:
			"idle":
				_play(_idle_key())
			"run":
				loco = "run" if speed_ratio > 0.65 else "walk"
			"air":
				# short blend so the push-off reads snappy instead of fading in
				_play("jump", 0.1)
			"block":
				_play("block")
			"strafe_l", "strafe_r", "walk_back", \
			"block_fwd", "block_back", "block_l", "block_r":
				loco = anim
			"slide":
				_play("slide")
			"dive":
				_play("slide")
				_lean_target = 0.5
			"attack_heavy":
				_play("heavy")
			_:
				if anim.begins_with("attack_light"):
					_play("light_%d" % clampi(int(anim.get_slice("_", 2)), 0, 2))
	if not loco.is_empty():
		_play(loco)

	if anim_player:
		if _hitstop_time > 0.0:
			anim_player.speed_scale = HITSTOP_SCALE
		elif loco.is_empty():
			anim_player.speed_scale = 1.0
		else:
			# stride rate follows real ground speed, so strafes and backpedals
			# at their own speed caps still plant their feet
			anim_player.speed_scale = clampf(speed_ratio / float(LOCO_NOMINAL[loco]), 0.7, 1.75)
	model.rotation.x = lerpf(model.rotation.x, _lean_target + _react_lean, minf(delta * 12.0, 1.0))

## Which of the two standing poses belongs on screen this frame. Falls back to
## the short one for anything built without the long clip — a villager's clip
## list is idle/walk/run, and they have no business taking a fighting stance.
func _idle_key() -> String:
	if _idle_time < IDLE_LONG_AFTER:
		return "idle"
	if anim_player and anim_player.has_animation("lib/" + _clip_for("idle_long")):
		return "idle_long"
	return "idle"

func play_death() -> void:
	anim_player.pause()
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_property(self, "rotation:x", -PI / 2.0, 0.7)
	tw.parallel().tween_property(self, "position:y", 0.15, 0.7)

## Undo play_death for a respawn (multiplayer: players come back).
func revive() -> void:
	rotation.x = 0.0
	position.y = 0.0
	model.rotation.x = 0.0
	_react_lean = 0.0
	_hitstop_time = 0.0
	_stagger_time = 0.0
	_idle_time = 0.0
	if anim_player:
		anim_player.speed_scale = 1.0
	_current_key = ""
	_play("idle", 0.0)
