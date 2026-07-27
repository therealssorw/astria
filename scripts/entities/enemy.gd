class_name Enemy
extends CharacterBody3D
## Combat AI: chases from afar, then cycles between three fight states —
## ATTACK (swoop in and punch), RETREAT (strafing around the player, still
## engaged) and BLOCK. Decisions are context-driven (distance, player swings,
## hits taken, a building aggression meter) mixed with a golden-ratio
## sequence: deterministic and logical, but aperiodic — so the alternation
## has reasons without being easily guessable.
##
## Multiplayer: the AI runs ONLY on the server, which owns health, damage
## and kill credit. Clients get a PUPPET copy (spawned by Net) that just
## interpolates the replicated state and plays the same animations.

# --- Stats: all tunable per-instance in the inspector (select the Enemy
# node in the scene and edit under "Enemy" — overrides these defaults) ---
@export_group("Level")
## This enemy's rank, which is how much a weapon has to out-class it before it
## starts dying faster (`CombatLevels`). Level 1 (`BASE_ENEMY_LEVEL`) is the
## ORDINARY enemy, and at that level nothing is scaled at all: the exported
## numbers below are exactly what it has and exactly what it takes, against a
## level 0 fist. Raising it here is the one dial that makes something tougher
## without touching a single stat.
##
## THE BANDIT ITSELF IS LEVEL 0, set on `scenes/enemy.tscn` rather than here —
## one rung UNDER the baseline, so the common enemy of the starter island both
## dies quicker and hits softer than the numbers below say. The default stays
## on the baseline so anything new is an ordinary enemy until it says otherwise.
@export var level := CombatLevels.BASE_ENEMY_LEVEL
@export_group("Health")
@export var max_health := 100.0
@export_range(0.0, 1.0) var knockback_resistance := 0.6
@export_group("Movement")
@export var move_speed := 4.0
@export var turn_speed_deg := 360.0
@export var repath_interval := 0.5
## Personal space: bandits inside this of each other drift apart (metres).
@export var separation_radius := 1.1
## How hard that drift pushes, at its strongest (m/s).
@export var separation_push := 2.5
@export_group("Attack")
@export var attack_damage := 20.0
@export var attack_range := 1.6          # stops and swings inside this
@export var attack_cone_deg := 80.0
@export var attack_reach := 1.0
@export var attack_radius := 0.55
## Seconds into the swing when the hit lands. Short enough to demand a real
## reaction, long enough to read off the telegraph star.
@export var attack_windup := 0.45
## Total swing length — the punch animation stretches to fit this.
@export var attack_duration := 1.05
## Minimum time between swing starts.
@export var attack_cooldown := 1.15
@export_group("Sound")
## This character's grunt pair — played (one random grunt) whenever it takes
## damage. Each character gets exactly one pair.
@export var hurt_grunts: AudioStream
## Impact thud played when a punch gets through to this character.
@export var punch_impacts: AudioStream = preload("res://Assets/Audio/SFX/Impacts/Punches/punch_impacts.tres")
## Played instead when its guard eats the hit — no flesh thud, no grunt.
@export var block_impacts: AudioStream = preload("res://Assets/Audio/SFX/Impacts/Blocks/block_impacts.tres")
## Played once when this character dies.
@export var death_sounds: AudioStream = preload("res://Assets/Audio/SFX/Deaths/death_sounds.tres")
## Swing woosh — plays the moment any attack starts, whether or not it hits.
@export var swing_wooshes: AudioStream = preload("res://Assets/Audio/SFX/Wooshes/woosh_sounds.tres")
@export_group("Perception")
## The bandit only turns hostile once it SEES the player: within this range,
## inside its forward vision cone, with clear line of sight. Sneaking past
## means using cover or staying behind them, not just keeping your distance.
@export var sight_range := 22.0
@export var sight_fov_deg := 140.0
## Loses interest and stands down beyond this distance. Keep this comfortably
## above sight_range or aggro flickers on and off at the boundary.
@export var deaggro_range := 34.0
@export_group("Combat AI")
## Inside this distance the enemy fights (attack/retreat/block cycle).
@export var engage_range := 7.0
## Speed multiplier while swooping in for a punch.
@export var swoop_speed_mult := 1.5
## Movement speed while strafing in RETREAT.
@export var strafe_speed := 3.0
## Preferred circling distance band while retreating.
@export var retreat_min_dist := 2.8
@export var retreat_max_dist := 4.6
## Damage multiplier while blocking (0 = full negate).
@export_range(0.0, 1.0) var block_damage_mult := 0.25
## The guard only covers this cone in front — go around it and it's worthless.
@export var block_arc_deg := 120.0
## How fast the urge to attack builds while circling.
@export var aggression_rate := 0.45
## Extra urge per second while the player just sits behind a raised guard:
## turtling invites pressure instead of stalling the fight.
@export var block_bait_rate := 0.6
## Player swings starting within this range can trigger a reflex block/dodge.
@export var block_reflex_dist := 3.5
## Flat knockback that rocks it out of whatever it was doing — heavies and
## combo enders clear this bar, ordinary jabs don't (so no stun-locking).
@export var flinch_knockback := 6.5
@export var flinch_time := 0.4
## Damage taken while staggered (parried, or rocked by a heavy) — the payoff
## for reading the fight instead of mashing.
@export var stagger_damage_mult := 1.4
@export_group("Death")
@export var despawn_delay := 5.0
## Gold dropped at the corpse — the SERVER rolls a whole number in
## [gold_min, gold_max]; whoever walks over the pile first gets it.
@export var gold_min := 5
@export var gold_max := 15

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var body_visual: Node3D = $Visual

enum CombatState { CHASE, ATTACK, RETREAT, BLOCK }

var puppet := false   # true on clients: no AI, just replicated state
## WHICH SCENE a client rebuilds this fighter from — a key of Net.ENEMY_SCENES,
## and "" for the ordinary bandit. The server picks it when it spawns one; a
## client is told it with the spawn, because a bandit and a boss are not the same
## body and the puppet has to be the right one.
var enemy_kind := ""
## 0 = a bandit of the shared world. Anything else is a tutorial bandit
## belonging to that peer's private copy of the city: it only ever fights that
## player, and only that player is told it exists (see Net).
var owner_peer := 0
## How much of this bandit is switched on. The tutorial builds a fight up one
## piece at a time — a lesson is only teachable when the enemy is doing exactly
## the thing being taught and nothing else — so the AI arrives in levels rather
## than being all-or-nothing:
##
##   NONE     — an ordinary bandit: the whole state machine, as in the world.
##   STILL    — completely still. No turning, no stepping, no swinging: a
##              training dummy that can still be hit, staggered and killed.
##              What a line is spoken over, so nobody is punched through a box
##              they cannot close.
##   CIRCLER  — circles you like an ATTACKER but never swings. A moving target
##              to learn to hit, rather than a post.
##   ATTACKER — circling you and throwing ONE punch every `hold_attack_period`
##              and nothing else: no closing the fight down, no guard, no
##              retreat. That metronome IS the block lesson — a punch you can
##              see coming, on a beat slow enough to answer — and the circling
##              is there so it reads as a fight from the very first second
##              rather than a target dummy that hits back.
enum Hold { NONE, STILL, CIRCLER, ATTACKER }

## Grace before a bandit that has just been let loose may swing — long enough
## for the line it says as it wakes up.
const WAKE_GRACE := 1.8
## Roughly how long an ATTACKER circles one way before switching.
const HOLD_CIRCLE_TIME := 2.2

var hold_mode: Hold = Hold.NONE
## Seconds between an ATTACKER's punches — the beat the block lesson stands on.
@export var hold_attack_period := 3.0
## How fast an ATTACKER closes the last step into reach: a walk, not a charge.
## It has to be able to actually land the punch it is demonstrating.
@export var held_step_mult := 0.45
## ...and how fast it circles you between those punches, against `strafe_speed`.
@export var held_circle_mult := 0.5

var _hold_swing_left := 0.0
var _hold_turn_left := 0.0

var health: float
var dead := false
## >0: wide open — parried or rocked back, no AI, no guard, free hits.
var stagger_left := 0.0
var cooldown_left := 0.0
var repath_left := 0.0
var attacking := false
var attack_timer := 0.0
var attack_did_hit := false
var player: Node3D

var aggroed := false

# combat state machine
var state: CombatState = CombatState.CHASE
var state_time := 0.0
var state_duration := 1.5
var strafe_side := 1.0        # -1 left / +1 right around the player
var strafe_depth := 0.0       # -1 drift in ... +1 drift out (0 = pure strafe)
var aggression := 0.5
var swings_since_retreat := 0
var _pattern := 0.0           # golden-ratio low-discrepancy sequence
var _player_was_attacking := false
var _retarget_left := 0.0
## Every noise this fighter makes (see FighterAudio, shared with the player).
var _sfx: FighterAudio

# what _animate last showed — this is what the server replicates
var last_anim := "idle"
var last_anim_t := 0.0
var last_ratio := 0.0

# puppet interpolation targets
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_anim := "idle"
var net_anim_t := 0.0
var net_ratio := 0.0
var net_windup := false
var net_windup_prog := 0.0
var net_attacking := false
var net_blocking := false
var _net_has_state := false

func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	puppet = not multiplayer.is_server()
	_sfx = FighterAudio.new(self, _audio_streams(), _audio_opts())
	if puppet:
		collision_layer = 0
		collision_mask = 0
		return
	nav_agent.path_desired_distance = 0.5
	# acceptance radius = AttackRange - 60cm
	nav_agent.target_desired_distance = maxf(0.5, attack_range - 0.6)
	# per-enemy seed so multiple enemies don't move in sync
	_pattern = fposmod(float(get_instance_id() % 1009) * 0.618, 1.0)

## Low-discrepancy sequence in [0,1): deterministic and non-repeating, so
## decisions follow the same "dice" every fight but never form a short cycle.
func _next_pattern() -> float:
	_pattern = fposmod(_pattern + 0.6180339887, 1.0)
	return _pattern

func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_tick(delta)
		return

	if dead:
		if not is_on_floor():
			velocity.y -= _gravity() * delta
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		move_and_slide()
		return

	# held by a tutorial step: still solid, still hittable, but only doing the
	# one thing that lesson is about
	if hold_mode != Hold.NONE:
		_tick_held(delta)
		return

	# staggered: no decisions, no guard, no swing — just stumble it out
	if stagger_left > 0.0:
		stagger_left -= delta
		attacking = false
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		if not is_on_floor():
			velocity.y -= _gravity() * delta
		move_and_slide()
		_animate(delta)
		return

	# always fight the nearest living player; re-checked on an interval so a
	# closer challenger steals aggro
	_retarget_left -= delta
	if _retarget_left <= 0.0 or not is_instance_valid(player) or player.get("dead"):
		_retarget_left = 1.0
		_acquire_player()
	if player == null:
		_idle(delta)
		return

	var dist := global_position.distance_to(player.global_position)

	# passive until it actually sees the player (or gets hit)
	if not aggroed:
		if _can_see_player(dist):
			aggroed = true
		else:
			_idle(delta)
			return
	elif dist > deaggro_range:
		aggroed = false
		state = CombatState.CHASE
		_idle(delta)
		return

	cooldown_left = maxf(0.0, cooldown_left - delta)
	state_time += delta
	_face_player(delta)
	_reflex_check(dist)

	if _tick_moves(delta, dist):
		pass # a fighter with moves of its own has taken this frame (see Boss)
	elif attacking:
		_tick_attack(delta)
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if not attacking:
			swings_since_retreat += 1
			_decide_after_swing()
	else:
		match state:
			CombatState.CHASE:
				if dist <= engage_range:
					_decide(dist)
				else:
					_chase(delta)
			CombatState.ATTACK:
				_tick_swoop(delta, dist)
			CombatState.RETREAT:
				_tick_retreat(delta, dist)
			CombatState.BLOCK:
				_tick_block(delta)
		# fight broke off entirely -> resume the chase
		if dist > engage_range * 1.5 and state != CombatState.CHASE:
			_enter(CombatState.CHASE, 1.0)

	if not is_on_floor():
		velocity.y -= _gravity() * delta
	_separate()
	move_and_slide()
	_animate(delta)

## Bandits are solid, but being solid is not enough to keep them apart: a crowd
## all walking at the same player converges on one spot, and two that come to
## rest overlapping stay overlapping — a kinematic body only depenetrates while
## it is moving. So the living ones always drift out of each other's personal
## space, strongest when they are closest.
func _separate() -> void:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other) or other.get("dead"):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0
		var d := away.length()
		if d >= separation_radius:
			continue
		if d < 0.01:
			# exactly coincident: shove along a per-enemy fixed heading, so the
			# two of them pick different directions instead of staying welded
			away = Vector3(sin(_pattern * TAU), 0, cos(_pattern * TAU))
			d = separation_radius * 0.5
		push += away.normalized() * (1.0 - d / separation_radius)
	if push == Vector3.ZERO:
		return
	push = push.normalized() * separation_push * minf(push.length(), 1.0)
	velocity.x = clampf(velocity.x + push.x, -move_speed, move_speed)
	velocity.z = clampf(velocity.z + push.z, -move_speed, move_speed)

## Nearest living player — except for a tutorial bandit, which has exactly one
## player it is allowed to care about. The copies of the city are far enough
## apart that distance alone would already do this; the check is here so that
## stays true even if they are ever moved next door to each other.
func _acquire_player() -> void:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or p.get("dead"):
			continue
		if owner_peer != 0 and p.get("peer_id") != owner_peer:
			continue
		var d := global_position.distance_to((p as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = p
	player = best

## Every noise this fighter makes, by the name FighterAudio knows it as. An
## ordinary bandit has the five every character has; a boss adds a shout and
## footsteps to the same table rather than building a second audio rig.
func _audio_streams() -> Dictionary:
	return {"grunt": hurt_grunts, "impact": punch_impacts, "block": block_impacts,
			"death": death_sounds, "woosh": swing_wooshes}

## The shape of this character's VOICE — pitch and whether it carries a room with
## it. Ordinary size, ordinary room.
func _audio_opts() -> Dictionary:
	return {}

# ---------------- hooks a bigger fighter overrides ----------------
#
# Three small virtuals rather than a second copy of this file. The ordinary
# bandit answers all of them with "nothing special", so they cost a comparison
# and a subclass gets the whole state machine, the replication and the damage
# path for free (see Boss).

## A frame taken by a move of this fighter's own. True means the state machine
## above stands down for it; the shared tail (gravity, separation, movement,
## animation) still runs either way.
func _tick_moves(_delta: float, _dist: float) -> bool:
	return false

## Health just changed inside take_damage, before anything is broadcast — where
## a phase threshold is noticed.
func _on_health_changed() -> void:
	pass

## Is this fighter helpless RIGHT NOW? The HUD's lock-on ring asks this rather
## than reading a field, so what the amber ring promises is always what
## `take_damage` actually does — a boss is also open through the recovery of a
## move, which is not a stagger.
func is_open() -> bool:
	return stagger_left > 0.0

## How this fighter's wind-up is DRAWN: the colour of the star, how much it
## grows, how far OVER ITS HEAD it floats, and the radius of a ground ring for an
## attack with a footprint (0 = none). Gold and plain for everything ordinary —
## see hud.gd. The height is asked for rather than assumed because the cast is
## not one size: 2.1m clears a bandit and sits on a boss's chest.
func telegraph_style() -> Dictionary:
	return {"color": Color(1.0, 0.85, 0.25), "scale": 1.0, "ring": 0.0, "height": 2.1}

# ---------------- puppet (client) side ----------------

func _puppet_tick(delta: float) -> void:
	if _net_has_state:
		if global_position.distance_to(net_pos) > 6.0:
			global_position = net_pos
		else:
			global_position = global_position.lerp(net_pos, minf(delta * 10.0, 1.0))
		body_visual.rotation.y = lerp_angle(body_visual.rotation.y, net_yaw, minf(delta * 12.0, 1.0))
	if dead:
		return
	# footsteps run on EVERY peer, off the replicated speed: they are the sound of
	# something walking about, and only the server ever runs _animate
	_sfx.tick_steps(net_ratio)
	body_visual.tick(delta, net_anim, net_anim_t, net_ratio)

## What the server replicates about this enemy every tick. A boss APPENDS two
## more of its own (which move is running, which phase it is in); the reader
## fills those in for a short row, so a bandit pays nothing for them.
func net_visual_state() -> Array:
	return [String(name), global_position, body_visual.rotation.y,
			last_anim, last_anim_t, last_ratio,
			is_winding_up(), windup_progress(), attacking, attack_duration,
			is_blocking()]

func net_apply_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, windup: bool, windup_prog: float,
		is_attacking: bool, atk_duration: float, guarding := false,
		_move := "", _phase := 1) -> void:
	net_pos = pos
	net_yaw = yaw
	net_anim = anim
	net_anim_t = anim_t
	net_ratio = ratio
	net_windup = windup
	net_windup_prog = windup_prog
	if is_attacking and not net_attacking:
		# swing just started: play the stretched punch montage + woosh
		_sfx.play_swing()
		if body_visual.has_method("on_attack_started"):
			body_visual.on_attack_started(false, 0, atk_duration)
	net_attacking = is_attacking
	net_blocking = guarding
	_net_has_state = true

func net_apply_damage(new_health: float, result: int, attacker := 0) -> void:
	health = new_health
	_damage_fx(result)
	if attacker != 0 and attacker == multiplayer.get_unique_id():
		Player.local_hit_feedback(get_tree(), result)

func net_die() -> void:
	if dead:
		return
	dead = true
	attacking = false
	stagger_left = 0.0
	collision_layer = 0
	_sfx.play_death()
	body_visual.play_death()

# ---------------- combat states ----------------

## A bandit with only part of itself switched on, for one tutorial lesson.
## STILL is a training dummy — it does not even turn — and ATTACKER is a
## metronome: face the player, circle them, and land one punch every
## `hold_attack_period` with the real wind-up, star and damage. Everything else
## the state machine would do — hunting you across the island, guarding,
## retreating, choosing when to press — stays off in both.
func _tick_held(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	# ONE place decides where it wants to go this frame and one applies it:
	# damping at the top and steering underneath it were pulling against each
	# other, and the damping won — the circle came out a shuffle.
	var want := Vector3.ZERO
	# rocked back or parried: wide open, exactly as in a real fight
	if stagger_left > 0.0:
		stagger_left -= delta
		attacking = false
		_hold_swing_left = maxf(_hold_swing_left, stagger_left)
	elif hold_mode == Hold.STILL:
		attacking = false # a dummy does nothing at all, not even look at you
	else:
		if not is_instance_valid(player) or player.get("dead"):
			_acquire_player()
		if is_instance_valid(player):
			aggroed = true # being held in a fight means it has seen you
			_face_player(delta)
			if attacking:
				_tick_attack(delta) # planted: a punch is thrown from the spot
			else:
				_hold_swing_left -= delta
				var to_p := player.global_position - global_position
				to_p.y = 0.0
				var dist := to_p.length()
				to_p = to_p.normalized()
				if dist > attack_range * 1.2:
					# still crossing the ground between you: walk in. It closes
					# properly first and only then starts circling — spiralling
					# in from range takes so long the lesson looks broken.
					want = to_p * move_speed * held_step_mult
				elif hold_mode == Hold.ATTACKER and _hold_swing_left <= 0.0 and dist <= attack_range:
					_hold_swing_left = hold_attack_period
					_start_swing()
				else:
					# between punches it CIRCLES you — arcing in while it is
					# out of reach, drifting out when it is on top of you — so
					# even the first lesson is a fight to move with rather than
					# a post to stand at. Swapping sides now and then keeps it
					# from being a treadmill.
					_hold_turn_left -= delta
					if _hold_turn_left <= 0.0:
						_hold_turn_left = HOLD_CIRCLE_TIME * (0.7 + _next_pattern() * 0.8)
						strafe_side = -strafe_side
					# mostly sideways: the in/out correction only nudges, or the
					# circle collapses into walking at you and reads as a
					# shuffle. It orbits INSIDE its own reach on purpose — park
					# the circle on the edge of it and the punch it is meant to
					# be demonstrating never gets thrown.
					var steer := Vector3.UP.cross(to_p) * strafe_side
					if dist > attack_range * 0.8:
						steer += to_p * 0.4
					elif dist < attack_range * 0.5:
						steer -= to_p * 0.4
					want = steer.normalized() * strafe_speed * held_circle_mult
	velocity.x = move_toward(velocity.x, want.x, 25.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 25.0 * delta)
	if not is_on_floor():
		velocity.y -= _gravity() * delta
	_separate() # two held bandits must still not stand inside each other
	move_and_slide()
	_animate(delta)

## Switch this bandit's AI down to one lesson's worth (or back up to all of it).
func set_hold(mode: Hold) -> void:
	if hold_mode == mode:
		return
	hold_mode = mode
	if mode == Hold.ATTACKER:
		# the first punch comes a beat after the lesson starts, not instantly:
		# nobody can block something that arrives with the instruction
		_hold_swing_left = hold_attack_period
	elif mode == Hold.STILL:
		attacking = false
	else:
		# waking all the way up: it says its piece before it swings. A bandit
		# let loose an arm's length away while the player is held by its own
		# taunt would land a hit nobody could have answered.
		attacking = false
		cooldown_left = maxf(cooldown_left, WAKE_GRACE)

func _enter(next: CombatState, duration: float) -> void:
	state = next
	state_time = 0.0
	state_duration = duration

## ATTACK: swoop toward the player and swing once in range.
func _tick_swoop(delta: float, dist: float) -> void:
	if dist > attack_range:
		var dir := player.global_position - global_position
		dir.y = 0
		dir = dir.normalized() * move_speed * swoop_speed_mult
		velocity.x = move_toward(velocity.x, dir.x, 30.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z, 30.0 * delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)
	if cooldown_left <= 0.0:
		_start_swing()

func _start_swing() -> void:
	attacking = true
	attack_timer = 0.0
	attack_did_hit = false
	cooldown_left = attack_cooldown
	_sfx.play_swing()
	# exported windup/duration are authoritative; the punch animation
	# is stretched to match attack_duration
	if body_visual.has_method("on_attack_started"):
		body_visual.on_attack_started(false, 0, attack_duration)

## RETREAT: circle the player — sideways, in, out, or diagonals — while
## staying in the fight; the urge to attack builds the longer it circles.
func _tick_retreat(delta: float, dist: float) -> void:
	# a player parked behind a guard is baiting a stalemate — press them
	var urge := aggression_rate
	if bool(player.get("blocking")):
		urge += block_bait_rate
	aggression = minf(aggression + urge * delta, 1.2)
	var to_p := player.global_position - global_position
	to_p.y = 0
	to_p = to_p.normalized()
	var side := Vector3.UP.cross(to_p) * strafe_side
	# band-keeping overrides the chosen drift so it never wanders off
	var depth := strafe_depth
	if dist < retreat_min_dist:
		depth = 1.0
	elif dist > retreat_max_dist:
		depth = -0.8
	var dir := (side + to_p * -depth).normalized() * strafe_speed
	velocity.x = move_toward(velocity.x, dir.x, 20.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z, 20.0 * delta)
	if state_time >= state_duration:
		_decide(dist)

## BLOCK: guard up, slow backpedal, then reassess.
func _tick_block(delta: float) -> void:
	var to_p := player.global_position - global_position
	to_p.y = 0
	var dir := to_p.normalized() * -0.8
	velocity.x = move_toward(velocity.x, dir.x, 15.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z, 15.0 * delta)
	if state_time >= state_duration:
		var p := _next_pattern()
		var player_recovering: bool = bool(player.get("attacking")) == false and _player_was_attacking
		# counter-punch is likeliest right after the player whiffed near us
		if p < 0.45 + (0.3 if player_recovering else 0.0):
			_enter(CombatState.ATTACK, 2.0)
		else:
			_new_strafe()

## Weighted state pick — weights come from context, the tie-breaker from the
## pattern sequence.
func _decide(dist: float) -> void:
	var p := _next_pattern()
	var attack_w := 0.2 + aggression * 0.7
	var retreat_w := 0.45 + float(swings_since_retreat) * 0.25
	var block_w := 0.25 if dist < block_reflex_dist else 0.04
	var total := attack_w + retreat_w + block_w
	var r := p * total
	if r < attack_w:
		_enter(CombatState.ATTACK, 2.5)
	elif r < attack_w + retreat_w:
		_new_strafe()
	else:
		_enter(CombatState.BLOCK, 0.7 + _next_pattern() * 0.8)

## After finishing a punch: sometimes press with a second one, usually back off.
func _decide_after_swing() -> void:
	aggression = maxf(aggression - 0.55, 0.0)
	var p := _next_pattern()
	if swings_since_retreat < 2 and p > 0.62:
		_enter(CombatState.ATTACK, 2.0) # double-tap
		return
	swings_since_retreat = 0
	_new_strafe()

## Pick a fresh strafe: left or right, drifting in, out, or neither —
## so the movement mixes pure sidesteps with diagonals.
func _new_strafe() -> void:
	strafe_side = 1.0 if _next_pattern() > 0.5 else -1.0
	var p := _next_pattern()
	if p < 0.25:
		strafe_depth = -0.6  # diagonal: strafe while creeping in
	elif p > 0.75:
		strafe_depth = 0.6   # diagonal: strafe while backing off
	else:
		strafe_depth = 0.0   # pure sidestep
	_enter(CombatState.RETREAT, 1.1 + _next_pattern() * 1.6)

## Reacts the moment the player starts a swing nearby: usually guard,
## sometimes a sharp direction flip, sometimes ignores it entirely.
func _reflex_check(dist: float) -> void:
	var p_att := bool(player.get("attacking"))
	if p_att and not _player_was_attacking and not attacking \
			and state != CombatState.BLOCK and dist < block_reflex_dist:
		var p := _next_pattern()
		if p < 0.5:
			_enter(CombatState.BLOCK, 0.6 + _next_pattern() * 0.6)
		elif p < 0.75 and state == CombatState.RETREAT:
			strafe_side = -strafe_side # juke instead of guarding
			state_duration += 0.4
	_player_was_attacking = p_att

func _gravity() -> float:
	return ProjectSettings.get_setting("physics/3d/default_gravity")

func _idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	if not is_on_floor():
		velocity.y -= _gravity() * delta
	_separate() # a camp standing around is exactly where they pile up
	move_and_slide()
	_animate(delta)

## Turn to something NOW rather than at turn_speed — for a bandit dropped into
## a fight that is already happening. A bandit only wakes when the player walks
## into its vision cone, so one spawned facing the other way would stand there
## until it was hit, which is not what a raider does.
func face_toward(pos: Vector3) -> void:
	var to := pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.001:
		return
	body_visual.rotation.y = atan2(-to.x, -to.z) + PI

func _face_player(delta: float) -> void:
	var to_p := player.global_position - global_position
	to_p.y = 0
	if to_p.length_squared() < 0.001:
		return
	var target_yaw := atan2(-to_p.x, -to_p.z) + PI
	body_visual.rotation.y = rotate_toward(body_visual.rotation.y, target_yaw, deg_to_rad(turn_speed_deg) * delta)

func _chase(delta: float) -> void:
	repath_left -= delta
	if repath_left <= 0.0:
		repath_left = repath_interval
		nav_agent.target_position = player.global_position
	var next := nav_agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0
	# no navmesh (or degenerate path) -> walk straight at the player
	if dir.length() < 0.05:
		dir = player.global_position - global_position
		dir.y = 0
	dir = dir.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

func _tick_attack(delta: float) -> void:
	attack_timer += delta
	if not attack_did_hit and attack_timer >= attack_windup:
		attack_did_hit = true
		_attack_trace()
	if attack_timer >= attack_duration:
		attacking = false

func _attack_trace() -> void:
	# same cone/sweep hit math as the player, 80 deg half-angle — checked
	# against EVERY player in the arc, using server-accepted positions
	var origin := global_position + Vector3.UP * 1.0
	# facing dir is +Z: the orient yaw (atan2 + PI) turns basis.z toward the target
	var fwd := body_visual.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or p.get("dead"):
			continue
		if owner_peer != 0 and p.get("peer_id") != owner_peer:
			continue # a tutorial bandit can only ever hit its own student
		var target_pos: Vector3 = p.server_body_pos()
		var to_p: Vector3 = target_pos + Vector3.UP * 1.0 - origin
		var dist := to_p.length()
		if dist > attack_reach + attack_radius:
			continue
		var flat := Vector3(to_p.x, 0, to_p.z).normalized()
		if fwd.dot(flat) < cos(deg_to_rad(attack_cone_deg)):
			continue
		# `self` goes along so a parried swing staggers us in return.
		# Scaled by our level the same way our health is: a level 1 enemy is
		# the baseline and hits for exactly the exported number, and anything
		# above or below hits harder or softer to match how long it lives.
		# A bandit is level 0, so it lands under the number exported above.
		p.server_take_damage(attack_damage * CombatLevels.enemy_power(level),
				flat * 3.0 + Vector3.UP * 1.5, 0, self)

## Sees the player only when close, in front, and unobstructed.
func _can_see_player(dist: float) -> bool:
	if dist > sight_range:
		return false
	var to_p := player.global_position - global_position
	to_p.y = 0
	if to_p.length_squared() < 0.001:
		return true
	var fwd := body_visual.global_transform.basis.z
	fwd.y = 0
	if fwd.normalized().dot(to_p.normalized()) < cos(deg_to_rad(sight_fov_deg * 0.5)):
		return false
	# line of sight: walls and terrain block the view
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.5,
		player.global_position + Vector3.UP * 1.5)
	query.exclude = [get_rid(), player.get_rid()]
	return space.intersect_ray(query).is_empty()

## True during the wind-up: the swing has started but the hit hasn't landed.
func is_winding_up() -> bool:
	if puppet:
		return net_windup
	return attacking and not attack_did_hit

## True while the guard is up — the same condition that actually reduces
## incoming damage in take_damage, so the HUD shield can't promise a block
## the server won't honour. Replicated, because the AI only runs server-side.
func is_blocking() -> bool:
	if puppet:
		return net_blocking
	# staggered counts as no guard, exactly as take_damage treats it — a
	# rocked bandit must not still be showing a shield
	return state == CombatState.BLOCK and not attacking and not dead \
			and stagger_left <= 0.0

## 0 -> 1 progress through the wind-up, for telegraph intensity.
func windup_progress() -> float:
	if puppet:
		return net_windup_prog
	return clampf(attack_timer / maxf(attack_windup, 0.01), 0.0, 1.0)

## SERVER ONLY: all enemy damage funnels through here (attacker = peer id
## of the puncher, for kill credit; 0 = environment). `source` is the node
## that swung, so a parry can be paid back — enemies don't parry, but the
## same signature keeps the player and enemy damage paths interchangeable.
func take_damage(amount: float, knockback: Vector3, attacker := 0,
		_source: Node = null) -> float:
	if puppet or dead:
		return 0.0
	# A HELD bandit cannot be hurt. It is a demonstration dummy while the lesson
	# it is standing in for is being taught — three gates' worth of practice
	# swings would otherwise leave it nearly dead before the duel it exists for,
	# and the "one on one" the tutorial promises would be over in a punch.
	# It still FLINCHES and still makes a noise: a swing that lands has to feel
	# like it landed, or the attack lesson teaches nothing. Nothing is held by
	# the time the duel starts (Hold.NONE), so the real fight is a real fight.
	if hold_mode != Hold.NONE:
		aggroed = true
		_damage_fx(Player.Guard.HIT)
		if attacker != 0 and attacker == multiplayer.get_unique_id():
			Player.local_hit_feedback(get_tree(), Player.Guard.HIT)
		return 0.0
	aggroed = true # getting hit always wakes it up
	var blocked := state == CombatState.BLOCK and not attacking \
			and stagger_left <= 0.0 and _guard_covers(knockback)
	var result := Player.Guard.BLOCKED if blocked else Player.Guard.HIT
	if blocked:
		# guarded hit: chip damage, barely budges
		amount *= block_damage_mult
		knockback *= 0.25
	else:
		if stagger_left > 0.0:
			amount *= stagger_damage_mult # punish window: hits land harder
		# getting tagged makes it warier: sometimes an immediate guard,
		# and it stews toward a comeback swing
		aggression = minf(aggression + 0.15, 1.2)
		if not attacking and state == CombatState.RETREAT and _next_pattern() < 0.35:
			_enter(CombatState.BLOCK, 0.5 + _next_pattern() * 0.5)
		# a heavy or a combo ender rocks it back out of whatever it was doing
		if Vector2(knockback.x, knockback.z).length() >= flinch_knockback:
			server_stagger(flinch_time)
	health -= amount
	_on_health_changed() # where a boss notices it has crossed into phase two
	velocity += knockback * (1.0 - knockback_resistance)
	Net.server_broadcast_enemy_damage(String(name), health, result, attacker)
	_damage_fx(result)
	if attacker != 0 and attacker == multiplayer.get_unique_id():
		Player.local_hit_feedback(get_tree(), result) # host punched it itself
	if health <= 0.0:
		_die(attacker)
	return amount

## The guard only covers the front — `knockback` points attacker -> us, so
## the attacker sits opposite it. Circle behind a blocking bandit and the
## block stops mattering.
func _guard_covers(knockback: Vector3) -> bool:
	var away := Vector3(knockback.x, 0.0, knockback.z)
	if away.length_squared() < 0.0001:
		return true
	var fwd := body_visual.global_transform.basis.z
	fwd.y = 0
	if fwd.length_squared() < 0.0001:
		return true
	return fwd.normalized().dot(-away.normalized()) >= cos(deg_to_rad(block_arc_deg * 0.5))

## SERVER: wide open for a beat — parried, or rocked by a big hit.
func server_stagger(duration: float) -> void:
	if puppet or dead:
		return
	Net.server_broadcast_enemy_stagger(String(name), duration)

## Runs on every peer so the helpless pose matches the server's punish window.
func net_stagger(duration: float) -> void:
	if dead:
		return
	stagger_left = maxf(stagger_left, duration)
	attacking = false
	if not puppet:
		cooldown_left = maxf(cooldown_left, duration)
		aggression = minf(aggression + 0.3, 1.2)
		_enter(CombatState.RETREAT, 0.9) # comes back circling, not swinging
	body_visual.play_stagger(duration)

## Flash + sounds — runs on the server (host view) and on every client.
func _damage_fx(result: int) -> void:
	_sfx.play_impact(result)
	if result == Player.Guard.BLOCKED:
		# the guard held: it thuds off the block and it doesn't hurt, so no
		# flesh impact and no grunt
		body_visual.flash(Color(0.4, 0.7, 1.0), 0.15)
		return
	body_visual.flash(Color(1.0, 0.85, 0.3), 0.12)
	body_visual.hit_react(0.28)
	body_visual.hitstop(0.06)
	_sfx.play_grunt(health > 0.0) # a lethal hit voices the death sound instead

func _die(attacker: int) -> void:
	Net.server_record_enemy_kill(String(name), attacker) # scoreboard + tells clients
	# A tutorial bandit pays nothing. The lesson is not a source of income — it
	# runs on every join and it can be restarted from the cheat menu, so paying
	# out would make it the cheapest gold in the game. `owner_peer` is what says
	# this one belongs to somebody's private copy of the island.
	if owner_peer == 0:
		# drop the pile a step to the side so the corpse doesn't lie on top of it
		var side := randf() * TAU
		Net.server_spawn_gold(global_position + Vector3(cos(side), 0, sin(side)) * 0.7,
				randi_range(gold_min, maxi(gold_min, gold_max)))
	net_die() # local presentation on the host
	get_tree().create_timer(despawn_delay).timeout.connect(func() -> void:
		if is_instance_valid(self):
			Net.server_remove_enemy(String(name))
			queue_free())

func _animate(delta: float) -> void:
	var h_speed := Vector3(velocity.x, 0, velocity.z).length()
	var anim := "idle"
	var t := 0.0
	var ratio := h_speed / move_speed
	if stagger_left > 0.0:
		anim = "idle" # the visual holds its own recoil pose over this
	elif attacking:
		anim = "attack_light_0"
		t = attack_timer / attack_duration
	elif state == CombatState.BLOCK:
		anim = "block"
	elif h_speed > 0.3:
		anim = "run"
		# in combat, pick the clip from the movement direction relative to
		# the player we're squared up against
		if state == CombatState.RETREAT and is_instance_valid(player):
			var to_p := player.global_position - global_position
			to_p.y = 0
			to_p = to_p.normalized()
			var fwd_comp := velocity.dot(to_p)
			var side_comp := velocity.dot(Vector3.UP.cross(to_p)) # + = our left
			if absf(side_comp) >= absf(fwd_comp):
				anim = "strafe_l" if side_comp > 0.0 else "strafe_r"
			elif fwd_comp < 0.0:
				anim = "walk_back"
	last_anim = anim
	last_anim_t = t
	last_ratio = ratio
	_sfx.tick_steps(ratio)
	body_visual.tick(delta, anim, t, ratio)
