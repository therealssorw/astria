extends CanvasLayer
## Cinematic framing, shared by everything that wants a scene to look like a
## scene: the two black bars top and bottom, and the camera turning to whoever
## is speaking. Autoload: Cinematic.
##
## Two independent switches, because they are wanted separately:
##
##   focus(node) / unfocus()  — the camera turns to `node` and the bars come
##                              in. This is what a talking character gets.
##   hold_bars(true/false)    — bars with no camera move, for a cutscene with
##                              nobody in it to look at (the intro monologue).
##
## Bars are drawn whenever EITHER is on, so a cutscene that opens a
## conversation halfway through does not flap them.
##
## Purely local and cosmetic (see "Server authority" in CLAUDE.md): where one
## player's camera points changes nothing anyone else can see.
##
## The camera it moves is the local pawn's rig — the same yaw and pitch the
## mouse drives. It only ever nudges them toward the target, so when it lets go
## the player carries on from wherever the shot ended rather than being snapped
## somewhere. Nothing here takes input away: the dialog box already does that.

## Height of each bar, as a fraction of the screen.
const BAR_FRACTION := 0.11
## Seconds for the bars to slide in or out.
const SLIDE_TIME := 0.35
## How quickly the camera swings onto the speaker.
const TURN_SPEED := 3.5
## Where the camera looks on a speaker that cannot say where its own face is
## (see NpcInteractable.look_anchor, which every NPC in the world can).
const LOOK_HEIGHT := 1.5
## The shot is a HIGH ANGLE: the camera sits above the two of them and looks DOWN
## at whoever is speaking.
##
## Set as a fixed pitch rather than worked out from where their face is, and that
## is the point: an aim point gives whatever angle the geometry happens to make,
## which is level ground most of the time and a different shot for every
## character's height and every distance the player happened to stop at. "From
## above" is the shot, so it is stated as one, and only the YAW still follows the
## speaker.
const FRAME_PITCH_DEG := -24.0
##
## Distance is SIZED OFF THE SPEAKER, because the cast is not one height: a 2.40 m
## King and a 1.85 m villager framed from one fixed distance cannot both fill the
## shot, so a taller character is framed from further back and everybody ends up
## about the same size on screen.
const FRAME_SPRING_PER_METRE := 1.33
const FRAME_SPRING_MIN := 1.8
const FRAME_SPRING_MAX := 4.0
## For a speaker that cannot say how tall it is — about a person.
const DEFAULT_HEIGHT := 1.85
const SPRING_SPEED := 4.0
## Pitch is clamped to the same range the mouse is allowed.
const PITCH_MIN := -1.309 # -75 degrees
const PITCH_MAX := 1.047  #  60 degrees

var _target: Node3D
## The arm length the pawn walks around with, remembered while the shot borrows
## it. -1 = not borrowed, so a focus during a restore does not capture the
## half-restored length as home.
var _spring_home := -1.0
var _bars_held := false
var _shown := 0.0 # 0 = no bars, 1 = fully in
var _top: ColorRect
var _bottom: ColorRect

func _ready() -> void:
	layer = 18 # under the dialog box (20) and the intro's black rect (19)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_top = _make_bar()
	_top.anchor_right = 1.0
	_bottom = _make_bar()
	_bottom.anchor_right = 1.0
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_apply_bars()

## Frame `node`: bars in, camera onto them. Passing null just holds the bars,
## which is what a speaker with no body in the world gets.
func focus(node: Node3D) -> void:
	_target = node

func unfocus() -> void:
	_target = null

## Bars without a camera move, for a cutscene that has nobody to look at.
func hold_bars(on: bool) -> void:
	_bars_held = on

func is_framing() -> bool:
	return _bars_held or is_instance_valid(_target)

## How far in the bars are, 0 to 1. Read by the test.
func bar_amount() -> float:
	return _shown

func _process(delta: float) -> void:
	_shown = move_toward(_shown, 1.0 if is_framing() else 0.0, delta / SLIDE_TIME)
	_apply_bars()
	_tick_spring(delta)
	if is_instance_valid(_target):
		_aim_at(_target, delta)
		_face_player(_target, delta)

## Turn the speaker to the player. Half of "this is a scene" is the character
## looking at whoever they are talking to — they used to answer you with their
## back turned, facing whichever way they were dropped into the level.
func _face_player(target: Node3D, delta: float) -> void:
	if not target.has_method("turn_toward"):
		return
	var pawn := get_tree().get_first_node_in_group("local_player")
	if pawn == null or not is_instance_valid(pawn):
		return
	target.turn_toward((pawn as Node3D).global_position, delta)

## Where the camera looks on `target`: whatever it says its face is, and a plain
## height above its origin for anything that cannot answer.
func look_point(target: Node3D) -> Vector3:
	if target.has_method("look_anchor"):
		return target.look_anchor()
	return target.global_position + Vector3.UP * LOOK_HEIGHT

## How tall the thing being framed is, which is what sizes the shot.
func speaker_height(target: Node3D) -> float:
	if target != null and target.has_method("body_height"):
		return maxf(float(target.call("body_height")), 0.5)
	return DEFAULT_HEIGHT

## Camera distance for this speaker: further back for a taller one, clamped so a
## mis-measured body cannot shove the camera into their face or out to sea.
func frame_spring(target: Node3D) -> float:
	return clampf(speaker_height(target) * FRAME_SPRING_PER_METRE,
			FRAME_SPRING_MIN, FRAME_SPRING_MAX)

## Borrow the pawn's camera arm for the shot and give it back afterwards. Handed
## back rather than left short, for the reason the whole file only ever nudges:
## the player carries on from where the shot ended, and a camera left pulled in
## would be a change they never asked for and cannot undo.
func _tick_spring(delta: float) -> void:
	var arm := _arm()
	if arm == null:
		return
	if is_framing():
		if _spring_home < 0.0:
			_spring_home = arm.spring_length
		arm.spring_length = move_toward(arm.spring_length, frame_spring(_target),
				SPRING_SPEED * delta)
	elif _spring_home >= 0.0:
		arm.spring_length = move_toward(arm.spring_length, _spring_home, SPRING_SPEED * delta)
		if absf(arm.spring_length - _spring_home) < 0.001:
			arm.spring_length = _spring_home
			_spring_home = -1.0

func _arm() -> SpringArm3D:
	var pawn := get_tree().get_first_node_in_group("local_player")
	if pawn == null or not is_instance_valid(pawn):
		return null
	return pawn.get("spring_arm") as SpringArm3D

## Turn the local pawn's camera rig toward the target. The rig sits on the
## pawn with the camera behind it, so pointing the rig frames the speaker over
## the player's shoulder — which is the shot we want anyway.
func _aim_at(target: Node3D, delta: float) -> void:
	var pawn := get_tree().get_first_node_in_group("local_player")
	if pawn == null or not is_instance_valid(pawn):
		return
	var rig: Node3D = pawn.get("cam_rig")
	var arm: Node3D = pawn.get("spring_arm")
	if rig == null or arm == null:
		return
	var eye: Vector3 = rig.global_position
	var to := look_point(target) - eye
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.05:
		return
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := clampf(deg_to_rad(FRAME_PITCH_DEG), PITCH_MIN, PITCH_MAX)
	var t := minf(delta * TURN_SPEED, 1.0)
	rig.rotation.y = lerp_angle(rig.rotation.y, want_yaw, t)
	arm.rotation.x = lerp_angle(arm.rotation.x, want_pitch, t)

func _apply_bars() -> void:
	var height := get_viewport().get_visible_rect().size.y * BAR_FRACTION * _shown
	_top.offset_bottom = height
	_bottom.offset_top = -height
	_top.visible = height > 0.5
	_bottom.visible = height > 0.5

func _make_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 0.0
	add_child(bar)
	return bar
