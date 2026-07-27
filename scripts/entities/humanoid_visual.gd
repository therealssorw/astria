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
	# The intro's wake-up: flat on the ground to standing. Played as a SCRIPTED
	# one-shot (play_scripted) rather than off any pawn state — nothing in the
	# game puts a character on the floor, so there is no state for it to be.
	#
	# The FBX ships two takes and the loader picks "mixamo_com", which runs 8.60s
	# — and only the middle of that is the animation. The hips lie flat at 0.05
	# until 1.7, climb to 0.52 by about 6.2, and then it stands there doing
	# nothing for the last 2.4s. Sliced to the rise itself: a beat on the floor as
	# the black starts lifting, and up on both feet as it clears. It ends a little
	# hunched because the take does; the blend into the idle covers it, and paying
	# another 0.7s for the rest of the take buys no more posture than that.
	#
	# The intro's fade is the length of THIS, so re-trimming it retimes the whole
	# wake-up (see IntroCutscene).
	"get_up": {"path": ANIM_DIR + "Cutscene/GettingUp/Getting Up.fbx", "speed": 1.0,
			"loop": false, "slice": [1.50, 6.25]},
	"strafe_l": {"path": ANIM_DIR + "Movement/Strafing/Left Strafe Walking.fbx", "speed": 1.0, "loop": true},
	"strafe_r": {"path": ANIM_DIR + "Movement/Strafing/Right Strafe Walking.fbx", "speed": 1.0, "loop": true},
	"walk_back": {"path": ANIM_DIR + "Movement/Walking/Walking Backwards.fbx", "speed": 1.0, "loop": true},
	"light_0": {"path": ANIM_DIR + "Combat/LightM1/Punching.fbx", "speed": 1.55, "loop": false},
	"light_1": {"path": ANIM_DIR + "Combat/LightM1/Illegal Elbow Punch.fbx", "speed": 1.55, "loop": false},
	"light_2": {"path": ANIM_DIR + "Combat/LightM1/Elbow Uppercut Combo.fbx", "speed": 1.55, "loop": false},
	"heavy": {"path": ANIM_DIR + "Combat/HeavyM1/Cross Punch.fbx", "speed": 1.35, "loop": false},
	# --- standing and walking with a sword (Mocap Online TC pack, MotusMan rig) ---
	"sword_idle": {"path": ANIM_DIR + "Sword/Idle/Sword Idle.fbx", "speed": 1.0, "loop": true},
	"sword_walk": {"path": ANIM_DIR + "Sword/Walking/Sword Walk.fbx", "speed": 1.0, "loop": true},
	"sword_run": {"path": ANIM_DIR + "Sword/Running/Sword Run.fbx", "speed": 1.0, "loop": true},
	# --- swinging it (Mocap Online TC pack, the same one the idle and the walk
	# come from) ---
	# FOUR SLASHES, one per swing, and PLAIN ones: a blade lifted, swung across
	# the fighter and brought to rest. Nothing here spins, vaults or flourishes.
	#
	# ALL FOUR COME OUT OF ONE TAKE, and that is not laziness — it is the only
	# take in the project whose grip can be trusted. This FBX ships the sword it
	# was performed with (`TonySword_01` on a prop bone in the hand), which is
	# what ItemDb.HOLD_DEFAULTS is fitted to; the other pack ships none, and a
	# retarget does not preserve the wrist's ROLL between two source rigs. So a
	# blade lined up with this pack sits a quarter turn wrong in that one's
	# swings, and the sword sails through the cut edge-up. Its swings looked
	# right in every still and wrong the moment the blade was in shot.
	#
	# So: a new sword clip wants to come from a take that carries its own sword,
	# or the grip has to be re-fitted against whatever pack it does come from
	# (tests/diag_grip_fit.tscn), and then every OTHER clip re-checked against
	# the new grip.
	#
	# EVERY ONE IS UNSPUN — see HumanoidClips.unspin. Without it a strike cut out
	# of the middle of a combo plays with the fighter's back to whatever they are
	# swinging at, which is what these used to do.
	#
	# THE UNSPIN IS ALSO WHY A SLICE CANNOT BE PICKED BY THE HAND'S SPEED. Where
	# a strike IS the spin — and the other pack's fastest hand is exactly that —
	# taking the yaw out takes the cut out with it, and what is left on screen is
	# a fighter waving a sword over their head. Nor by the hand's TRAVEL: a hand
	# that slides without turning carries the blade broadside. What a slash needs
	# is both, the hand crossing the body AND the grip rotating through it,
	# measured after the yaw is gone. tests/diag_sword.tscn scores every window
	# of every take on exactly that, and prints where the strike lands inside the
	# window — because a window that ENDS on the strike is all wind-up and no cut.
	#
	# Each slice is cut WIDE and the strike sits in the MIDDLE of it: blade
	# lifting, the cut, the follow-through. Trimmed tight to the strike (the
	# first pass, by the peak of the arm's angular speed) a clip starts and ends
	# mid-motion, and the body snaps into a pose instead of swinging.
	#
	# AND THE BLADE HAS TO MISS THE FIGHTER. Two of this take's five strikes
	# bring the hand across the chest, which on the actor is a blade passing in
	# FRONT of it — his arms are long and he is narrow. Ours are voxel people,
	# wide with short arms, so the same motion drags a metre of sword straight
	# through the torso. Neither is fixable by shortening the blade (the clash is
	# at the grip, not the point), so those strikes are simply not used, and the
	# heavy is the opening cut again over a longer wind-up rather than the
	# overhead chop that reads best and clips worst.
	# tests/diag_blade_clip.tscn measures it: the blade against the body, every
	# frame of every clip, and it wants to stay positive.
	#
	# Judge them with tests/preview_sword_swings.tscn, which lays each one out as
	# a strip of eight frames. A single still cannot tell a slash from a wave.
	#
	# "speed" only matters if something plays one outside an attack:
	# on_attack_started always stretches it onto the punch's own window.
	"sword_light_0": {"path": ANIM_DIR + "Sword/Attack/Sword Combo.fbx", "speed": 1.55,
			"loop": false, "unspin": true,
			"slice": [0.50, 1.00]},                  # across, right to left
	"sword_light_1": {"path": ANIM_DIR + "Sword/Attack/Sword Combo.fbx", "speed": 1.55,
			"loop": false, "unspin": true,
			"slice": [2.30, 2.80]},                  # back the other way
	"sword_light_2": {"path": ANIM_DIR + "Sword/Attack/Sword Combo.fbx", "speed": 1.55,
			"loop": false, "unspin": true,
			"slice": [4.30, 4.80]},                  # the ender, coming down
	"sword_heavy": {"path": ANIM_DIR + "Sword/Attack/Sword Combo.fbx", "speed": 1.35,
			"loop": false, "unspin": true,
			"slice": [0.30, 1.05]},                  # the opener again, with the whole wind-up
}
## Clip swaps applied while a sword is in hand. Anything not listed keeps its
## bare-handed clip, so blocking, sliding and jumping are unchanged. Each swing
## has a cut of its OWN — the three lights chain through three different
## slashes, and the heavy is a fourth stretched over the heavy's longer window,
## which is what makes it read as the slow, committed version. Repeats still
## cross-blend through the "__alt" copy.
const SWORD_CLIPS := {
	# "idle_long" maps to the same sword idle as "idle" on purpose: a character
	# with a blade in hand has one standing pose, so the long-idle swap happens
	# and nothing about it shows.
	"idle": "sword_idle", "idle_long": "sword_idle",
	"walk": "sword_walk", "run": "sword_run",
	"light_0": "sword_light_0", "light_1": "sword_light_1",
	"light_2": "sword_light_2", "heavy": "sword_heavy",
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
## >0: a SCRIPTED clip owns the body for that long and the state-driven picking
## in tick() stands down. tick() runs every frame off the pawn's own state, so a
## clip started from outside would otherwise be replaced before its first frame
## was ever drawn.
var _scripted_time := 0.0
var _scripted_key := ""
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
		var anim := HumanoidClips.load_clip(cfg.path)
		# Read the neutral standing hips off the FULL clip before any slicing:
		# a slice starting mid-motion has no neutral frame of its own.
		var neutral_hips := Vector3.ZERO
		if cfg.has("pin_hips_at"):
			neutral_hips = HumanoidClips.sample_hips(anim, cfg.pin_hips_at)
		if cfg.has("slice"):
			anim = HumanoidClips.slice(anim, cfg.slice[0], cfg.slice[1])
		if cfg.get("unspin", false):
			HumanoidClips.unspin(anim)
		_repath_tracks(anim, skel_path)
		if cfg.has("pin_hips_at"):
			HumanoidClips.pin_hips(anim, _adapt_hips(neutral_hips))
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
			HumanoidClips.graft_upper_body(moving, block_anim)
			clip_lengths[key] = moving.length
			lib.add_animation(key, moving)
	# Layered strafes: keep only the legs of the strafe clips and graft the
	# upper body from Bouncing Fight Idle on top, so strafing keeps a combat
	# guard up. The fight idle is used ONLY as this upper-body source.
	if "strafe_l" in keys or "strafe_r" in keys:
		var stance_anim := HumanoidClips.load_clip(ANIM_DIR + "Combat/Stances/Bouncing Fight Idle.fbx")
		_repath_tracks(stance_anim, skel_path)
		for strafe_key in ["strafe_l", "strafe_r"]:
			if strafe_key in keys:
				HumanoidClips.graft_upper_body(lib.get_animation(strafe_key), stance_anim)

	anim_player.add_animation_library("lib", lib)

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

func _find_skeleton(n: Node) -> Skeleton3D:
	return HumanoidClips.find_skeleton(n)

## Onto OUR skeleton, and through THIS character's hips remap — which is the
## only part of the import pipeline that varies per rig.
func _repath_tracks(anim: Animation, skel_path: String) -> void:
	HumanoidClips.repath(anim, skeleton, skel_path, _adapt_hips)

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
	# The same tint the item's icon is taken with, from the same place: what is
	# in the hand and what is in the bag must never be two different colours.
	ItemDb.tint_model(inst, cfg["tint"])
	_held_node = attach

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

## Hand the body to a one-shot clip and keep it there for the clip's own length,
## returning how long that is (0.0 if this character was not built with it, which
## is every villager — their clip list is idle/walk/run).
##
## For anything the pawn has no STATE for: the intro's getting-up is the first,
## and a cutscene is exactly the case where what is on screen is not what the
## player is doing. It ends by itself, so nothing has to remember to cancel it.
func play_scripted(key: String) -> float:
	if anim_player == null or not anim_player.has_animation("lib/" + _clip_for(key)):
		return 0.0
	var length := float(clip_lengths.get(key, 0.0)) / maxf(_clip_speed(key), 0.01)
	if length <= 0.0:
		return 0.0
	_scripted_key = key
	_scripted_time = length
	_restart(key, 0.0) # from its first frame, no blend: it starts on the floor
	return length

## True while a scripted clip still owns the body.
func is_scripted() -> bool:
	return _scripted_time > 0.0

## Give the body back early — an aborted cutscene, a death mid-clip.
func stop_scripted() -> void:
	_scripted_time = 0.0
	_scripted_key = ""

## Ground speed that a `speed_ratio` of 1.0 means, in m/s — the player's own
## walk_speed, which is what every ratio in this file is measured against.
const WALK_REFERENCE := 6.5
## Below this ratio a character counts as standing still.
const MOVING_RATIO := 0.03

## False for a visual built without its clip library (the editor's preview, and
## anything built with build_clips off) — there is nothing to tick.
func has_clips() -> bool:
	return anim_player != null and model != null

## Animate something that is simply being MOVED about rather than driven by a
## pawn's state machine — a villager walking over, and anything else that is
## pushed around by a script. Hand it the ground speed in m/s and it picks the
## pose and the stride rate itself.
func tick_motion(delta: float, speed: float) -> void:
	var ratio := speed / WALK_REFERENCE
	# "run" is the locomotion key; tick() picks walk or run off the ratio
	tick(delta, "run" if ratio > MOVING_RATIO else "idle", 0.0, ratio)

func tick(delta: float, anim: String, _t := 0.0, speed_ratio := 0.0) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			for m in _mats:
				m.emission_enabled = false
	_hitstop_time = maxf(0.0, _hitstop_time - delta)
	_stagger_time = maxf(0.0, _stagger_time - delta)
	_scripted_time = maxf(0.0, _scripted_time - delta)
	_react_lean = move_toward(_react_lean, 0.0, delta * REACT_DECAY)

	# A scripted clip outranks everything, including the state the pawn thinks it
	# is in. It is only ever set by a cutscene, and a cutscene has already taken
	# the controls away.
	if _scripted_time > 0.0:
		_play(_scripted_key, 0.0)
		if anim_player:
			anim_player.speed_scale = 1.0
		model.rotation.x = lerpf(model.rotation.x, 0.0, minf(delta * 12.0, 1.0))
		return

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
