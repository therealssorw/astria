class_name Boss
extends Enemy
## The juggernaut: a boss that walks through you.
##
## It is an [Enemy] SUBCLASS and not a copy, which is the whole point — the
## state machine, the puppet replication, the guard, the damage path, the kill
## credit and the drop all come from there. What a boss adds is only what a boss
## does differently:
##
##   * POISE. It does not flinch. `flinch_knockback` is what rocks an ordinary
##     bandit out of whatever it was doing, and a fighter that big being knocked
##     about by every jab is not one. So the two ways it opens up are both EARNED
##     (see `is_open`): parry it, or punish the recovery of a move it committed
##     to. Neither can be mashed for.
##   * MOVES. `MOVES` is the table and `_tick_moves` walks it — a slam in phase
##     one, a charge in phase two. Adding a third is a row, not a branch.
##   * TWO PHASES. Halfway down its health the armour comes off, it stops
##     guarding and retreating entirely, and the charge unlocks. See `_set_phase`.
##
## Server-authoritative like everything else that can be cheated: the AI, the
## phase, every move and all of its damage run on the server alone, and clients
## get the move and the phase replicated along with the rest of the enemy state
## (see `net_visual_state`). The only things a client does on its own are the
## three cosmetic ones — the health bar, the telegraph and the entrance shot.

## Which move is running, its beats and what it costs you. ONE ROW PER MOVE:
##
##   phase     — the earliest phase it is available in.
##   windup    — seconds of telegraph before anything lands. This is the whole of
##               how fair a boss is, so it is long and it is per move.
##   active    — how long the move itself takes after the wind-up (a slam is
##               instant, a charge runs).
##   recovery  — seconds WIDE OPEN afterwards. This is the punish window, and it
##               is the reason to learn which move is which rather than backing
##               off from all of them equally.
##   cooldown  — soonest it may be used again.
##   damage    — before CombatLevels scales it by the boss's own level, exactly
##               like an ordinary swing.
##   range     — the band it is chosen from, measured to the player.
##   reach     — how far the hit itself carries (a radius for the slam, the
##               width of the lane for the charge).
##   shake     — camera kick at the epicentre, falling off to nothing at `reach`.
##   telegraph — how the wind-up is drawn (see `telegraph_style`): its colour,
##               how much bigger the star gets, and whether a ground ring is
##               drawn at `reach`. Each move looks different on purpose, so the
##               player reads WHICH attack rather than just "an attack".
const MOVES := {
	"slam": {
		"phase": 1, "windup": 1.15, "active": 0.12, "recovery": 1.7, "cooldown": 6.5,
		"damage": 26.0, "range": 6.0, "reach": 4.6, "shake": 0.9,
		"telegraph": {"color": Color(1.0, 0.55, 0.15), "scale": 1.9, "ring": true},
	},
	"charge": {
		"phase": 2, "windup": 0.85, "active": 1.1, "recovery": 2.2, "cooldown": 8.0,
		"damage": 30.0, "range": 17.0, "min_range": 5.5, "reach": 1.5, "shake": 0.7,
		"speed": 15.0,
		"telegraph": {"color": Color(1.0, 0.25, 0.2), "scale": 2.4, "ring": false},
	},
}

## Gold, and the star over an ordinary bandit's head. A boss only uses it before
## it has committed to one of its own moves.
const DEFAULT_TELEGRAPH := {"color": Color(1.0, 0.85, 0.25), "scale": 1.0, "ring": false}
## How far above its own crown the star floats. Measured off the body rather than
## the 2.1m an ordinary fighter uses, which lands on this one's chest.
const TELEGRAPH_LIFT := 0.6

@export_group("Boss")
## Shown on the bar across the top of the screen.
@export var display_name := "The Juggernaut"
## POISE. Nothing short of a parry rocks this one back: `flinch_knockback` is
## the bar a hit has to clear to stagger an enemy, and putting it out of reach is
## what makes the openings below the only ones. Turn it off and the boss flinches
## like a bandit — every dial the ordinary fighter has still works underneath.
@export var poise := true
## Fraction of max health at which phase two starts.
@export_range(0.0, 1.0) var phase_two_at := 0.5
## Phase two is FASTER, not merely angrier: everything it does is scaled by this.
@export var phase_two_speed_mult := 1.35
## ...and it presses harder, so the gaps between swings close up too.
@export var phase_two_cooldown_mult := 0.7
## What it is carrying, dropped where it falls (see `_die`). Empty drops nothing
## but the gold every enemy pays.
@export var drop_item := "juggernaut_club"

@export_group("Sound")
## The shout. It is the ORDINARY BANDIT GRUNTS, slowed right down and put in a
## room (`voice_pitch` / `voice_reverb` below) — a boss with a voice of its own
## would be a recording to keep in step with theirs, and this way the thing that
## makes it enormous is a number rather than a file.
@export var yells: AudioStream = preload("res://Assets/Audio/SFX/Grunts/Pair1/grunt_pair_1.tres")
## Footfalls, looped and played at the speed it is really moving (FighterAudio
## .tick_steps). Heavy enough to hear it coming before it is in the room.
@export var footsteps: AudioStream = preload("res://Assets/Audio/SFX/Footsteps/Boss/boss_footsteps.mp3")
## How far down its voice is dropped. Everything it says goes through this — the
## pain it makes when hit is the sound file it was given, and the yell is the
## bandit grunts at the same pitch, so the two read as one throat.
@export_range(0.2, 1.0, 0.01) var voice_pitch := 0.55

## How close the local player has to come for the entrance shot to play, and how
## long the camera holds on it. Purely local and cosmetic — see `_tick_intro`.
const INTRO_RANGE := 22.0
const INTRO_TIME := 2.6
## A move is only chosen this often, so two never start in the same breath.
const MOVE_GAP := 1.2

## 1 or 2. Server-owned; replicated to clients with the rest of the state.
var phase := 1
## The move running right now, "" when none is. Replicated: the client draws its
## telegraph off this.
var move_id := ""
var move_timer := 0.0
var move_did_hit := false
## >0: committed and wide open. The punish window every move ends in.
var recover_left := 0.0
## move id -> seconds until it may be used again.
var _move_cooldowns := {}
var _move_gap := 0.0
## Where a charge is going and who it has already run over.
var _charge_dir := Vector3.FORWARD
var _move_hit := {}

## Client-side only: the entrance shot has played on this screen.
var _intro_done := false
var _intro_left := 0.0

func _ready() -> void:
	super()
	add_to_group("boss")
	if poise:
		# Out of reach rather than merely high: a number a heavy MIGHT clear is a
		# poise system nobody can predict.
		flinch_knockback = INF
	for id: String in MOVES:
		_move_cooldowns[id] = float(MOVES[id]["cooldown"]) * 0.5
	# it carries the thing it drops — the club is in its hand, not just in its
	# loot table
	if drop_item != "" and body_visual != null and body_visual.has_method("set_held_item"):
		body_visual.set_held_item(drop_item)

## The five every fighter has, plus the two only something this size needs.
func _audio_streams() -> Dictionary:
	var s := super()
	s["yell"] = yells
	s["steps"] = footsteps
	return s

## Slowed down and given a room to stand in. Only the VOICE — its footsteps and
## the thud of a punch landing on it are the world's noises, not its own.
func _audio_opts() -> Dictionary:
	return {"voice_pitch": voice_pitch, "voice_reverb": true}

# ---------------- what a boss does differently ----------------

## The two EARNED openings, and nothing else: parried (which staggers it through
## the ordinary path, because a parry is supposed to work on anything), or caught
## in the recovery of a move it committed to.
##
## The HUD's lock-on ring asks this rather than reading `stagger_left`, so what it
## promises is what `take_damage` actually does.
func is_open() -> bool:
	return stagger_left > 0.0 or recover_left > 0.0

## Punish damage applies to the recovery window as well as to a stagger — they
## are the same promise ("you earned this") and must pay the same.
func take_damage(amount: float, knockback: Vector3, attacker := 0,
		source: Node = null) -> float:
	if recover_left > 0.0 and stagger_left <= 0.0:
		amount *= stagger_damage_mult
	return super(amount, knockback, attacker, source)

## Health crossed the threshold: everything about phase two follows from here.
func _on_health_changed() -> void:
	if phase < 2 and health <= max_health * phase_two_at and health > 0.0:
		_set_phase(2)

func _set_phase(next: int) -> void:
	if phase == next:
		return
	phase = next
	if next == 2:
		move_speed *= phase_two_speed_mult
		strafe_speed *= phase_two_speed_mult
		attack_cooldown *= phase_two_cooldown_mult
		turn_speed_deg *= phase_two_speed_mult
		# it stops defending the moment it stops being careful
		if state == CombatState.BLOCK or state == CombatState.RETREAT:
			_enter(CombatState.ATTACK, 2.0)
	net_apply_phase(next)

## The look of a phase, run on EVERY peer (the server calls it through
## `_set_phase`, a client when the replicated phase changes). The armour coming
## off is the read: you can see from across the room which half of the fight you
## are in.
func net_apply_phase(next: int) -> void:
	phase = next
	if next < 2:
		return
	_sfx.play_yell() # every peer, because everyone in the room hears it
	if body_visual != null and body_visual.has_method("strip_armor"):
		body_visual.strip_armor()

# ---------------- phase two: it never backs off ----------------
#
# The inherited state machine cycles attack / retreat / block. In phase two the
# retreat and the guard are simply gone: it closes and it keeps closing, which is
# the whole character of a juggernaut. Phase one still fights like a very large
# bandit, so the change is something the player watches happen.

func _decide(dist: float) -> void:
	if phase < 2:
		super(dist)
		return
	_enter(CombatState.ATTACK, 2.5)

func _decide_after_swing() -> void:
	if phase < 2:
		super()
		return
	aggression = 1.2
	swings_since_retreat = 0
	_enter(CombatState.ATTACK, 2.0)

## No reflex guard in phase two — there is no guard left to reflex into.
func _reflex_check(dist: float) -> void:
	if phase < 2:
		super(dist)
		return
	_player_was_attacking = bool(player.get("attacking"))

func is_blocking() -> bool:
	if puppet:
		return net_blocking
	return phase < 2 and super()

# ---------------- the moves ----------------

## Called by Enemy._physics_process before the ordinary state machine gets the
## frame. True means the move owns it. The shared tail (gravity, separation,
## move_and_slide, animation) still runs either way.
func _tick_moves(delta: float, dist: float) -> bool:
	for id: String in _move_cooldowns:
		_move_cooldowns[id] = maxf(0.0, float(_move_cooldowns[id]) - delta)
	_move_gap = maxf(0.0, _move_gap - delta)

	if recover_left > 0.0:
		recover_left -= delta
		_brake(delta)
		return true
	if move_id != "":
		_tick_move(delta)
		return true
	if attacking or stagger_left > 0.0 or _move_gap > 0.0:
		return false
	var pick := _pick_move(dist)
	if pick == "":
		return false
	_start_move(pick)
	return true

## The first move whose phase is up, whose cooldown has run out and whose band
## the player is standing in. Ordered by the table, so which move takes priority
## is something you can read off `MOVES` rather than out of a chain of ifs.
func _pick_move(dist: float) -> String:
	for id: String in MOVES:
		var m: Dictionary = MOVES[id]
		if phase < int(m["phase"]) or float(_move_cooldowns[id]) > 0.0:
			continue
		if dist > float(m["range"]) or dist < float(m.get("min_range", 0.0)):
			continue
		return id
	return ""

func _start_move(id: String) -> void:
	var m: Dictionary = MOVES[id]
	move_id = id
	move_timer = 0.0
	move_did_hit = false
	_move_hit = {}
	_move_cooldowns[id] = float(m["cooldown"])
	attacking = false
	_sfx.play_swing()
	_sfx.play_yell() # it announces the big ones; clients do the same off `move_id`
	if body_visual.has_method("on_attack_started"):
		# no clip of its own yet: the heavy swing stretched over the wind-up and
		# the strike, which is what `on_attack_started` is for
		body_visual.on_attack_started(true, 0, float(m["windup"]) + float(m["active"]))

func _tick_move(delta: float) -> void:
	var m: Dictionary = MOVES[move_id]
	move_timer += delta
	var windup := float(m["windup"])
	if move_timer < windup:
		# still telegraphing: plant it and let it turn, so the move is aimed at
		# where the player is NOW and not where they were when it started
		if is_instance_valid(player):
			_face_player(delta)
		_brake(delta)
		return
	if not move_did_hit:
		move_did_hit = true
		_commit_move(m)
	if move_id == "charge":
		_tick_charge(delta, m)
	if move_timer >= windup + float(m["active"]):
		_end_move(m)

## The frame the move lands on. A slam is over at once; a charge starts running.
func _commit_move(m: Dictionary) -> void:
	if move_id == "slam":
		_slam(m)
		return
	if is_instance_valid(player):
		var to_p := player.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.001:
			_charge_dir = to_p.normalized()
	Net.server_broadcast_boss_move(String(name), move_id, global_position)

## Everyone standing in the ring takes it. Checked against the SERVER's own copy
## of each pawn, like every other trace in the game.
func _slam(m: Dictionary) -> void:
	var reach := float(m["reach"])
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or p.get("dead"):
			continue
		var target: Vector3 = p.server_body_pos()
		var away := target - global_position
		away.y = 0.0
		if away.length() > reach:
			continue
		var dir := away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		p.server_take_damage(float(m["damage"]) * CombatLevels.enemy_power(level),
				dir * 6.0 + Vector3.UP * 4.0, 0, self)
	Net.server_broadcast_boss_move(String(name), move_id, global_position)

## Running. Anything in the lane is run over ONCE — `_move_hit` is what stops a
## charge grinding the same player down at sixty hits a second.
func _tick_charge(delta: float, m: Dictionary) -> void:
	var speed := float(m["speed"])
	velocity.x = _charge_dir.x * speed
	velocity.z = _charge_dir.z * speed
	var reach := float(m["reach"])
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or p.get("dead") or _move_hit.has(p.get_instance_id()):
			continue
		var away: Vector3 = p.server_body_pos() - global_position
		away.y = 0.0
		if away.length() > reach:
			continue
		_move_hit[p.get_instance_id()] = true
		var dir := away.normalized() if away.length() > 0.01 else _charge_dir
		p.server_take_damage(float(m["damage"]) * CombatLevels.enemy_power(level),
				dir * 9.0 + Vector3.UP * 3.0, 0, self)
	# nudged toward the player as it runs, but only a little: a charge you cannot
	# sidestep is not a charge
	if is_instance_valid(player):
		var to_p := player.global_position - global_position
		to_p.y = 0.0
		if to_p.length_squared() > 0.001:
			_charge_dir = _charge_dir.slerp(to_p.normalized(), minf(delta * 1.2, 1.0))

func _end_move(m: Dictionary) -> void:
	move_id = ""
	move_timer = 0.0
	move_did_hit = false
	recover_left = float(m["recovery"])
	cooldown_left = maxf(cooldown_left, recover_left)

func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 22.0 * delta)

# ---------------- telegraph, replication, presentation ----------------

## True through the wind-up of a move as well as of an ordinary swing, so the
## star over its head means the same thing it always did.
func is_winding_up() -> bool:
	if puppet:
		return net_windup
	if move_id != "":
		return not move_did_hit
	return super()

func windup_progress() -> float:
	if puppet:
		return net_windup_prog
	if move_id != "":
		return clampf(move_timer / maxf(float(MOVES[move_id]["windup"]), 0.01), 0.0, 1.0)
	return super()

## How this fighter's wind-up is DRAWN. Every enemy answers this (see
## Enemy.telegraph_style); a boss answers per move, which is what lets the player
## read the attack rather than just its timing. `ring` is a radius in metres — a
## circle on the ground where a radial move is about to land — and 0 means the
## move has no footprint to draw.
func telegraph_style() -> Dictionary:
	var lift := body_height() + TELEGRAPH_LIFT
	if move_id == "" or not MOVES.has(move_id):
		var plain := DEFAULT_TELEGRAPH.duplicate()
		plain["ring"] = 0.0
		plain["height"] = lift
		return plain
	var t: Dictionary = MOVES[move_id]["telegraph"]
	return {
		"color": t["color"],
		"scale": float(t["scale"]),
		"ring": float(MOVES[move_id]["reach"]) if bool(t["ring"]) else 0.0,
		"height": lift,
	}

## Read by the client when a move lands, to decide how hard the lens kicks.
static func move_shake(id: String, distance: float) -> float:
	if not MOVES.has(id):
		return 0.0
	var m: Dictionary = MOVES[id]
	var reach := float(m["reach"])
	if distance >= reach * 2.0:
		return 0.0
	return float(m["shake"]) * (1.0 - distance / (reach * 2.0))

func net_visual_state() -> Array:
	var row := super()
	row.append(move_id)
	row.append(phase)
	return row

func net_apply_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, windup: bool, windup_prog: float,
		is_attacking: bool, atk_duration: float, guarding := false,
		move := "", boss_phase := 1) -> void:
	super(pos, yaw, anim, anim_t, ratio, windup, windup_prog, is_attacking,
			atk_duration, guarding, move, boss_phase)
	# a move STARTING is the shout, on this screen as on the server's: the id is
	# replicated, so the transition is all a client needs to know about it
	if move != "" and move != move_id:
		_sfx.play_swing()
		_sfx.play_yell()
	move_id = move
	if boss_phase != phase:
		net_apply_phase(boss_phase)

## Its own moves outrank the inherited pose picking: a slam is a heavy swing held
## through its wind-up, a charge is a run.
func _animate(delta: float) -> void:
	if move_id == "" and recover_left <= 0.0:
		super(delta)
		return
	var h_speed := Vector3(velocity.x, 0, velocity.z).length()
	var anim := "attack_heavy"
	var t := 0.0
	if move_id == "charge" and move_did_hit:
		anim = "run"
	elif move_id == "":
		anim = "idle" # the recovery: caught leaning on the swing it just threw
	else:
		t = move_timer / maxf(float(MOVES[move_id]["windup"]), 0.01)
	last_anim = anim
	last_anim_t = t
	last_ratio = h_speed / move_speed
	_sfx.tick_steps(last_ratio)
	body_visual.tick(delta, anim, t, last_ratio)

# ---------------- the entrance (local, cosmetic) ----------------

## Where a camera should look on this body, and how tall it is — the two things
## Cinematic sizes a shot from. Measured off the rig the way NpcInteractable does
## rather than assumed, so a boss rebuilt at a different height frames itself.
func look_anchor() -> Vector3:
	return global_position + Vector3.UP * (body_height() * 0.82)

## Sole to crown, off the rig's own measurements ("crown" is what NpcLayout calls
## it) rather than a number written twice. The fallback is only for a body that
## has not been built yet.
func body_height() -> float:
	if body_visual != null and body_visual.get("layout") != null:
		var h := float((body_visual.layout as Dictionary).get("crown", 0.0))
		if h > 0.1:
			return h
	return 2.6

## Turned toward the player for the shot, the same yaw convention every rig in
## this project uses (modelled facing +Z, so a plain look-at shows its back).
func turn_toward(pos: Vector3, delta: float) -> void:
	var to := pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.001:
		return
	body_visual.rotation.y = rotate_toward(body_visual.rotation.y,
			atan2(-to.x, -to.z) + PI, deg_to_rad(turn_speed_deg) * delta)

## The one thing here that runs on every peer regardless of authority: walking
## into the room for the first time frames the thing you have walked into. Purely
## local (see "Server authority" in CLAUDE.md) — where one player's camera points
## changes nothing anyone else can see — so it is per screen and never networked.
func _process(delta: float) -> void:
	if _intro_left > 0.0:
		_intro_left -= delta
		if _intro_left <= 0.0:
			Cinematic.unfocus()
		return
	if _intro_done or dead:
		return
	var pawn := get_tree().get_first_node_in_group("local_player")
	if pawn == null or not is_instance_valid(pawn) or pawn.get("dead"):
		return
	if global_position.distance_to((pawn as Node3D).global_position) > INTRO_RANGE:
		return
	_intro_done = true
	_intro_left = INTRO_TIME
	Cinematic.focus(self)
	_sfx.play_yell()
	Player.local_shake(get_tree(), 0.35)

func net_die() -> void:
	if _intro_left > 0.0:
		_intro_left = 0.0
		Cinematic.unfocus()
	super()

## Everything a bandit drops, plus what it was carrying. The club is a real drop
## on the floor rather than a line of text: `Net.server_spawn_item` is the same
## machinery the gold uses, so whoever walks over it gets it.
func _die(attacker: int) -> void:
	if drop_item != "" and owner_peer == 0:
		var side := randf() * TAU
		Net.server_spawn_item(global_position
				+ Vector3(cos(side), 0, sin(side)) * 1.2, drop_item)
	super(attacker)
