class_name PlayerNetState
## What the server will believe about a pawn it does not simulate, and what a
## pose is called. Split out of player.gd because it is the SECURITY half of
## movement and deserves to be readable on its own: a client's position report
## is a claim, and this is the whole of what turns one into a fact.
##
## Static and pure — it takes two positions and a time and answers yes or no,
## which is also what makes the speed cap testable without a server.

## Poses a client is allowed to claim it is in. Anything else becomes "idle",
## so a patched client cannot put a pose on its pawn that the game has no clip
## for — or one that would read as something it is not doing.
const ANIM_WHITELIST := ["idle", "run", "air", "block", "slide", "dive",
		"strafe_l", "strafe_r", "walk_back",
		"block_fwd", "block_back", "block_l", "block_r",
		"attack_heavy", "attack_light_0", "attack_light_1", "attack_light_2"]

## The fastest a pawn can legitimately be moving: a slide jump (13) plus the
## knockback of a heavy (7.5), with room over the top. Anything past it is a
## teleport or a speedhack and the report is rejected outright.
const MAX_H_SPEED := 26.0
const MAX_UP_SPEED := 14.0
## Slack on each cap, to cover a report that straddles a frame boundary.
const H_SLACK := 0.4
const UP_SLACK := 0.5
## A report gap is clamped into this before it is used as a distance budget, so
## neither a burst of reports nor a long stall hands out free movement.
const MIN_DT := 1.0 / 60.0
const MAX_DT := 0.5

static func clip_name(anim: String) -> String:
	return anim if ANIM_WHITELIST.has(anim) else "idle"

static func report_dt(now: float, last: float) -> float:
	return clampf(now - last, MIN_DT, MAX_DT) if last >= 0.0 else 0.1

## Could a pawn honestly have got from `prev` to `pos` in `dt`? Falling is
## unrestricted — gravity is not something a client has to be believed about,
## and a long drop is a normal thing to do.
static func plausible_move(prev: Vector3, pos: Vector3, dt: float) -> bool:
	if not pos.is_finite():
		return false
	var dv := pos - prev
	if Vector2(dv.x, dv.z).length() > MAX_H_SPEED * dt + H_SLACK:
		return false
	return dv.y <= MAX_UP_SPEED * dt + UP_SLACK

## Is a "I am sprinting" claim believable? Only if the pawn actually covered
## more ground than a walk would have. The drain the server charges for a run
## comes off this measurement, never off the client saying so.
static func plausible_sprint(prev: Vector3, pos: Vector3, dt: float, walk_speed: float) -> bool:
	var dv := pos - prev
	return Vector2(dv.x, dv.z).length() > walk_speed * dt * 0.9
