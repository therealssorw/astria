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
	"strafe_l": {"path": ANIM_DIR + "Movement/Strafing/Left Strafe Walking.fbx", "speed": 1.0, "loop": true},
	"strafe_r": {"path": ANIM_DIR + "Movement/Strafing/Right Strafe Walking.fbx", "speed": 1.0, "loop": true},
	"walk_back": {"path": ANIM_DIR + "Movement/Walking/Walking Backwards.fbx", "speed": 1.0, "loop": true},
	"light_0": {"path": ANIM_DIR + "Combat/LightM1/Punching.fbx", "speed": 1.55, "loop": false},
	"light_1": {"path": ANIM_DIR + "Combat/LightM1/Illegal Elbow Punch.fbx", "speed": 1.55, "loop": false},
	"light_2": {"path": ANIM_DIR + "Combat/LightM1/Elbow Uppercut Combo.fbx", "speed": 1.55, "loop": false},
	"heavy": {"path": ANIM_DIR + "Combat/HeavyM1/Cross Punch.fbx", "speed": 1.35, "loop": false},
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
# gameplay caps so long Mixamo tails don't make swings sluggish
const LIGHT_MAX_DUR := [0.52, 0.6, 0.74]
const HEAVY_MAX_DUR := 1.0
# hit reactions: how hard a recoil leans back, and how fast it settles
const REACT_DECAY := 1.6
const STAGGER_LEAN := -0.3
## Animation rate during hitstop — the near-freeze that gives a punch weight.
const HITSTOP_SCALE := 0.06

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
var _react_lean := 0.0     # transient recoil from a hit, decays back to 0
var _hitstop_time := 0.0   # >0: animation nearly frozen (impact emphasis)
var _stagger_time := 0.0   # >0: helpless recoil pose overrides the clip

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
		_repath_tracks(anim, skel_path)
		if cfg.loop:
			anim.loop_mode = Animation.LOOP_LINEAR
		clip_lengths[key] = anim.length
		lib.add_animation(key, anim)
		if not cfg.loop:
			# second name for the same clip so a restart can cross-blend
			# (see _restart) instead of snapping to the first frame
			lib.add_animation(key + "__alt", anim)
		src.free()
	# Guard-up movement: the block stance's upper body over walking/strafing
	# legs, so a guarding fighter can circle without dropping their hands.
	var block_anim := lib.get_animation("block")
	for key: String in BLOCK_MOVE:
		var moving: Animation = lib.get_animation(BLOCK_MOVE[key]).duplicate(true)
		_graft_upper_body(moving, block_anim)
		clip_lengths[key] = moving.length
		lib.add_animation(key, moving)
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
				anim.track_set_key_value(i, k, Vector3(first.x, v.y, first.z))

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
	if not CLIPS.has(key):
		return 1.0 # generated guard-movement variant, played at clip rate
	var cfg: Dictionary = CLIPS[key]
	return cfg.speed if cfg.loop else cfg.speed * attack_speed_mult

## Gameplay timing for a swing, derived from the actual clip at montage rate:
## "hit" is when contact lands, "combo" the earliest the NEXT punch may start
## (well before the clip's recovery tail, which is what makes a chain flow).
func get_attack_info(heavy: bool, combo_index: int) -> Dictionary:
	if heavy:
		var dur: float = minf(clip_lengths["heavy"] / CLIPS["heavy"].speed, HEAVY_MAX_DUR) / attack_speed_mult
		return {"duration": dur, "hit": dur * 0.45, "combo": dur * 0.85}
	var i := clampi(combo_index, 0, 2)
	var key := "light_%d" % i
	var d: float = minf(clip_lengths[key] / CLIPS[key].speed, LIGHT_MAX_DUR[i]) / attack_speed_mult
	return {"duration": d, "hit": d * 0.34, "combo": d * 0.62}

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

	_lean_target = 0.0
	var loco := "" # locomotion clip, if any — its playback tracks ground speed
	if _stagger_time > 0.0:
		_play("idle")
		_lean_target = STAGGER_LEAN
	else:
		match anim:
			"idle":
				_play("idle")
			"run":
				loco = "run" if speed_ratio > 0.65 else "walk"
			"air":
				_play("idle")
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

	if _hitstop_time > 0.0:
		anim_player.speed_scale = HITSTOP_SCALE
	elif loco.is_empty():
		anim_player.speed_scale = 1.0
	else:
		# stride rate follows real ground speed, so strafes and backpedals at
		# their own speed caps still plant their feet
		anim_player.speed_scale = clampf(speed_ratio / float(LOCO_NOMINAL[loco]), 0.7, 1.75)
	model.rotation.x = lerpf(model.rotation.x, _lean_target + _react_lean, minf(delta * 12.0, 1.0))

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
	anim_player.speed_scale = 1.0
	_current_key = ""
	_play("idle", 0.0)
