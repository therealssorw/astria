class_name PlayerAnim
## Which pose a pawn is in, worked out from what it is DOING. Split out of
## player.gd because it is a decision table with no side effects: nothing here
## moves a body, spends stamina or touches the network — it reads a handful of
## flags and answers with a clip name.
##
## Being pure is the point. What is on screen is also what is REPLICATED (the
## pawn reports `last_anim`), so this is the one function that decides what
## every other peer sees a player doing, and it can be reasoned about without a
## world around it.

## `state` carries only what the choice depends on:
##   attacking, attack_is_heavy, combo_index, sliding, diving, on_floor,
##   staggered, blocking, in_stance, h_vel (Vector3), facing (Vector3)
## Returns the clip name.
static func pose(state: Dictionary) -> String:
	if state.get("attacking", false):
		return "attack_heavy" if state.get("attack_is_heavy", false) \
				else "attack_light_%d" % int(state.get("combo_index", 0))
	if state.get("sliding", false):
		return "slide"
	if state.get("diving", false):
		return "dive"
	if not state.get("on_floor", true):
		return "air"
	if state.get("staggered", false):
		return "idle" # the visual holds its own recoil pose over this
	var h_vel: Vector3 = state.get("h_vel", Vector3.ZERO)
	if h_vel.length() > 0.3:
		return locomotion(h_vel, state.get("facing", Vector3.FORWARD),
				state.get("in_stance", false), state.get("blocking", false))
	return "block" if state.get("blocking", false) else "idle"

## Directional locomotion: squared up, the legs pick a sidestep or a backpedal
## from where we are actually going relative to the guard — and keep the fists
## up while blocking. Free-running just plays the run cycle.
static func locomotion(h_vel: Vector3, facing: Vector3, in_stance: bool, blocking: bool) -> String:
	var fwd := Vector3(facing.x, 0.0, facing.z)
	if not in_stance or fwd.length_squared() < 0.001:
		return "run"
	fwd = fwd.normalized()
	var ahead := h_vel.dot(fwd)
	var to_left := h_vel.dot(Vector3.UP.cross(fwd))
	if absf(to_left) > absf(ahead): # sidestepping
		if blocking:
			return "block_l" if to_left > 0.0 else "block_r"
		return "strafe_l" if to_left > 0.0 else "strafe_r"
	if blocking:
		return "block_back" if ahead < 0.0 else "block_fwd"
	return "walk_back" if ahead < 0.0 else "run"
