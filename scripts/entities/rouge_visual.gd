class_name RougeVisual
extends Node3D
## Rouge model (UE Manny rig) driven by Mixamo clips — both retargeted onto
## the shared humanoid profile at import, so the clips play directly on the
## character (the Godot equivalent of the spec's live IK retargeting).

const MODEL := "res://Assets/Models/Entity/Humanoid/Human/rouge.fbx"
const TEX_DIR := "res://Assets/Textures/Humanoid/Human/Rouge/"
const ANIM_DIR := "res://Assets/Animations/Humanoid/"
const CLIPS := {
	"idle": {"path": ANIM_DIR + "Movement/Idle/Offensive Idle.fbx", "speed": 1.0, "loop": true},
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
	"light_0": {"path": ANIM_DIR + "Combat/LightM1/Punching.fbx", "speed": 1.35, "loop": false},
	"light_1": {"path": ANIM_DIR + "Combat/LightM1/Illegal Elbow Punch.fbx", "speed": 1.35, "loop": false},
	"light_2": {"path": ANIM_DIR + "Combat/LightM1/Elbow Uppercut Combo.fbx", "speed": 1.35, "loop": false},
	"heavy": {"path": ANIM_DIR + "Combat/HeavyM1/Cross Punch.fbx", "speed": 1.15, "loop": false},
}
# gameplay caps so long Mixamo tails don't make swings sluggish
const LIGHT_MAX_DUR := [0.8, 1.15, 1.35]
const HEAVY_MAX_DUR := 1.55

## Per-character scale on attack clip playback (and thus swing timings);
## lets the player punch faster than enemies sharing this visual.
@export var attack_speed_mult := 1.0

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var clip_lengths := {}
var _mats: Array[StandardMaterial3D] = []
var _flash_time := 0.0
var _current_key := ""
var _lean_target := 0.0

func _ready() -> void:
	model = (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	skeleton = _find_skeleton(model)

	_setup_materials()

	anim_player = AnimationPlayer.new()
	add_child(anim_player)
	var lib := AnimationLibrary.new()
	var skel_path := str(anim_player.get_node(anim_player.root_node).get_path_to(skeleton))
	for key: String in CLIPS:
		var cfg: Dictionary = CLIPS[key]
		var src: Node = (load(cfg.path) as PackedScene).instantiate()
		var src_ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		var anim: Animation = src_ap.get_animation("mixamo_com").duplicate(true)
		# Read the neutral standing hips off the FULL clip before any slicing:
		# a slice starting mid-motion has no neutral frame of its own.
		var neutral_hips := Vector3.ZERO
		if cfg.has("pin_hips_at"):
			neutral_hips = _sample_hips(anim, cfg.pin_hips_at)
		if cfg.has("slice"):
			anim = _slice(anim, cfg.slice[0], cfg.slice[1])
		_repath_tracks(anim, skel_path)
		if cfg.has("pin_hips_at"):
			_pin_hips(anim, neutral_hips)
		if cfg.loop:
			anim.loop_mode = Animation.LOOP_LINEAR
		clip_lengths[key] = anim.length
		lib.add_animation(key, anim)
		if not cfg.loop:
			# second name for the same clip so a restart can cross-blend
			# (see _restart) instead of snapping to the first frame
			lib.add_animation(key + "__alt", anim)
		src.free()
	# Layered strafes: keep only the legs of the strafe clips and graft the
	# upper body from Bouncing Fight Idle on top, so strafing keeps a combat
	# guard up. The fight idle is used ONLY as this upper-body source.
	var stance_src: Node = (load(ANIM_DIR + "Combat/Stances/Bouncing Fight Idle.fbx") as PackedScene).instantiate()
	var stance_ap: AnimationPlayer = stance_src.find_children("*", "AnimationPlayer", true, false)[0]
	var stance_anim: Animation = stance_ap.get_animation("mixamo_com").duplicate(true)
	_repath_tracks(stance_anim, skel_path)
	stance_src.free()
	for strafe_key in ["strafe_l", "strafe_r"]:
		_graft_upper_body(lib.get_animation(strafe_key), stance_anim)

	anim_player.add_animation_library("lib", lib)
	_play("idle")

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
## forward), so once the spine is replaced the torso would face sideways —
## sourcing the hips orientation keeps the whole torso squared at the player,
## while the hips POSITION (bounce) and leg tracks stay from the strafe.
func _graft_upper_body(target: Animation, source: Animation) -> void:
	for i in range(target.get_track_count() - 1, -1, -1):
		if _is_grafted_track(target.track_get_path(i).get_subname(0), target.track_get_type(i)):
			target.remove_track(i)
	for i in source.get_track_count():
		var path := source.track_get_path(i)
		var type := source.track_get_type(i)
		if not _is_grafted_track(path.get_subname(0), type):
			continue
		var t := target.add_track(type)
		target.track_set_path(t, path)
		for k in source.track_get_key_count(i):
			var time := source.track_get_key_time(i, k)
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
				anim.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))

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
## hips ~1m, but gameplay physics already moves the capsule — keeping that rise
## would double-count it and float the model off the collision shape.
func _pin_hips(anim: Animation, neutral: Vector3) -> void:
	for i in anim.get_track_count():
		var p := anim.track_get_path(i)
		if p.get_subname_count() > 0 and p.get_subname(0) == "Hips" \
				and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(i):
				anim.track_set_key_value(i, k, neutral)

func _setup_materials() -> void:
	# The FBX references its textures by filename, but they live in TEX_DIR
	# (not next to the model), so bind them here by matching material names
	# like "..._8_L_Calf_1_palette1.002" to files like "...-8-L_Calf-1.png".
	var tex_by_key := {}
	for f in DirAccess.get_files_at(TEX_DIR):
		var base := f.trim_suffix(".import")
		if base.ends_with(".png"):
			tex_by_key[_norm(base.trim_suffix(".png"))] = TEX_DIR + base
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is StandardMaterial3D:
				var dup: StandardMaterial3D = mat.duplicate()
				if dup.albedo_texture == null:
					var key := _norm(mat.resource_name.split("_palette")[0])
					if tex_by_key.has(key):
						dup.albedo_texture = load(tex_by_key[key])
						# the FBX material's albedo color is near-black; the
						# texture is meant to carry the color
						dup.albedo_color = Color.WHITE
				mi.set_surface_override_material(s, dup)
				_mats.append(dup)

func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out

func _play(key: String, blend := 0.2) -> void:
	if _current_key == key:
		return
	_current_key = key
	anim_player.play("lib/" + key, blend, _clip_speed(key))

func _restart(key: String, blend := 0.18, speed_override := -1.0) -> void:
	# No stop() here — stopping kills the cross-blend and makes the new clip
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
	var cfg: Dictionary = CLIPS[key]
	return cfg.speed if cfg.loop else cfg.speed * attack_speed_mult

## Gameplay timing for a swing, derived from the actual clip at montage rate.
func get_attack_info(heavy: bool, combo_index: int) -> Dictionary:
	if heavy:
		var dur: float = minf(clip_lengths["heavy"] / CLIPS["heavy"].speed, HEAVY_MAX_DUR) / attack_speed_mult
		return {"duration": dur, "hit": dur * 0.5, "combo": dur}
	var i := clampi(combo_index, 0, 2)
	var key := "light_%d" % i
	var d: float = minf(clip_lengths[key] / CLIPS[key].speed, LIGHT_MAX_DUR[i]) / attack_speed_mult
	return {"duration": d, "hit": d * 0.4, "combo": d * 0.7}

## duration > 0 stretches the clip playback to exactly that many seconds
## (used by enemies whose swing timing is set in the inspector).
func on_attack_started(heavy: bool, combo_index: int, duration := -1.0) -> void:
	var key := "heavy" if heavy else "light_%d" % clampi(combo_index, 0, 2)
	var speed := -1.0
	if duration > 0.0:
		speed = clip_lengths[key] / duration
	_restart(key, 0.18, speed)

func flash(color: Color, duration := 0.15) -> void:
	_flash_time = duration
	for m in _mats:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.6

func tick(delta: float, anim: String, _t := 0.0, speed_ratio := 0.0) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			for m in _mats:
				m.emission_enabled = false

	_lean_target = 0.0
	match anim:
		"idle":
			_play("idle")
		"run":
			_play("run" if speed_ratio > 0.65 else "walk")
		"air":
			# short blend so the push-off reads snappy instead of fading in
			_play("jump", 0.1)
		"block":
			_play("block")
		"strafe_l", "strafe_r", "walk_back":
			_play(anim)
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
	model.rotation.x = lerpf(model.rotation.x, _lean_target, minf(delta * 12.0, 1.0))

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
	_current_key = ""
	_play("idle", 0.0)
