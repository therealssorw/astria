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
## Where on a character the camera looks — head height, not their feet.
const LOOK_HEIGHT := 1.5
## Pitch is clamped to the same range the mouse is allowed.
const PITCH_MIN := -1.309 # -75 degrees
const PITCH_MAX := 1.047  #  60 degrees

var _target: Node3D
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
	if is_instance_valid(_target):
		_aim_at(_target, delta)

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
	var at: Vector3 = target.global_position + Vector3.UP * LOOK_HEIGHT
	var to := at - eye
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.05:
		return
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := clampf(atan2(to.y, flat), PITCH_MIN, PITCH_MAX)
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
