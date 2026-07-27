class_name PlayerCamera
extends RefCounted
## The third-person camera and the lock-on that steers it. Split out of
## player.gd because none of it is the BODY: mouse and stick look, the tracking
## that keeps a locked opponent framed, the shake an impact puts on the lens,
## and picking who to lock onto in the first place.
##
## The pawn still OWNS `lock_target` — the HUD's red ring and a test both read it
## off the Player, and a swing's facing is decided by the body, not the lens. All
## this owns is where the camera points.
##
## Nothing here exists on a puppet: only the local pawn has a camera rig at all,
## so a Player builds one of these only when `is_local`.

## The lock-on tuning, ASSIGNED BY THE PAWN from its own `@export`s in `_ready`
## (`Player.lockon_cone_deg` and friends). They stay exports on the pawn on
## purpose: gameplay numbers in this project are tuned in the editor, and moving
## them in here as constants would have quietly taken that away. The defaults
## below only matter to a camera built without a pawn.
var pick_cone_deg := 55.0
var pick_range := 15.0
var break_range := 20.0
var track_speed := 8.0
var view_cone_deg := 80.0

const PITCH_MIN_DEG := -75.0
const PITCH_MAX_DEG := 60.0
## Stick look, radians per second at full deflection.
const STICK_YAW_RATE := 2.5
const STICK_PITCH_RATE := 1.8
const STICK_DEADZONE := 0.15

## An impact kicks the lens by this much, decaying at DECAY per second.
const SHAKE_DECAY := 3.2
const SHAKE_H := 0.07
const SHAKE_V := 0.05

var rig: Node3D
var arm: SpringArm3D
var cam: Camera3D
## When the player last moved the view themselves. The pawn reads it.
var look_input_time := -10.0

var _shake := 0.0

func _init(camera_rig: Node3D, spring_arm: SpringArm3D, camera: Camera3D) -> void:
	rig = camera_rig
	arm = spring_arm
	cam = camera

func alive() -> bool:
	return is_instance_valid(rig) and is_instance_valid(arm) and is_instance_valid(cam)

## Where the camera looks, flattened. The aim of an unlocked punch.
func forward() -> Vector3:
	return -cam.global_transform.basis.z

# ---------------- looking ----------------

## Mouse motion. `tracking` is true while the tracking camera owns the yaw —
## the pitch stays the player's either way.
func look_mouse(rel: Vector2, sensitivity: float, tracking: bool, now: float) -> void:
	if not tracking:
		rig.rotation.y -= rel.x * sensitivity
	_pitch(-rel.y * sensitivity)
	if rel.length_squared() > 0.5:
		look_input_time = now

func look_stick(delta: float, tracking: bool, now: float) -> void:
	var x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(x) <= STICK_DEADZONE and absf(y) <= STICK_DEADZONE:
		return
	if not tracking:
		rig.rotation.y -= x * STICK_YAW_RATE * delta
	_pitch(-y * STICK_PITCH_RATE * delta)
	look_input_time = now

func _pitch(by: float) -> void:
	arm.rotation.x = clampf(arm.rotation.x + by,
			deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG))

# ---------------- lock-on ----------------

## True when `target` is inside the tracking cone of the current view — the one
## condition under which the camera takes the yaw over.
func tracking(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	var to_t := target.global_position - cam.global_position
	to_t.y = 0
	if to_t.length_squared() < 0.01:
		return true
	var fwd := forward()
	fwd.y = 0
	if fwd.length_squared() < 0.001:
		return true
	return fwd.normalized().angle_to(to_t.normalized()) <= deg_to_rad(view_cone_deg)

## Hard lock: while a target is locked AND in view the camera owns the yaw and
## keeps them framed; the body stays fully player-driven. A target behind the
## view must be brought back by hand before tracking resumes.
func track(target: Node3D, delta: float) -> void:
	if not tracking(target):
		return
	var to_t := target.global_position - cam.global_position
	to_t.y = 0
	if to_t.length_squared() < 0.01:
		return
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-to_t.x, -to_t.z),
			1.0 - exp(-track_speed * delta))

## Has this lock let go on its own — target gone, dead, or walked out of range?
func lock_lost(target: Node3D, from: Vector3) -> bool:
	return not is_instance_valid(target) or target.get("dead") \
			or from.distance_to(target.global_position) > break_range

## Who a fresh lock-on press should grab: the nearest thing inside the cone and
## in range, falling back to the nearest thing at all so a press is never a
## no-op. `candidates` is whatever the pawn considers lockable.
func pick(candidates: Array, from: Vector3) -> Node3D:
	var cam_fwd := forward()
	var cone_cos := cos(deg_to_rad(pick_cone_deg))
	var best: Node3D = null
	var best_dist := INF
	var nearest: Node3D = null
	var nearest_dist := INF
	for e: Node3D in candidates:
		if not is_instance_valid(e) or e.get("dead"):
			continue
		var dist := from.distance_to(e.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e
		var to_e: Vector3 = e.global_position - cam.global_position
		if dist <= pick_range and cam_fwd.dot(to_e.normalized()) >= cone_cos and dist < best_dist:
			best_dist = dist
			best = e
	return best if best else nearest

# ---------------- shake ----------------

func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.0)

func clear_shake() -> void:
	_shake = 0.0
	if is_instance_valid(cam):
		cam.h_offset = 0.0
		cam.v_offset = 0.0

## Offsets, not rotation: a shake must never fight the player's aim.
func tick_shake(delta: float, now: float) -> void:
	if _shake <= 0.0 or not is_instance_valid(cam):
		return
	_shake = maxf(0.0, _shake - delta * SHAKE_DECAY)
	var s := _shake * _shake
	cam.h_offset = sin(now * 61.0) * SHAKE_H * s
	cam.v_offset = cos(now * 47.0) * SHAKE_V * s
