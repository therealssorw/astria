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
var _grunt_player: AudioStreamPlayer3D
var _impact_player: AudioStreamPlayer3D
var _block_player: AudioStreamPlayer3D
var _death_player: AudioStreamPlayer3D
var _woosh_player: AudioStreamPlayer3D

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
	if hurt_grunts:
		_grunt_player = AudioStreamPlayer3D.new()
		_grunt_player.stream = hurt_grunts
		_grunt_player.position.y = 1.4
		add_child(_grunt_player)
	if punch_impacts:
		_impact_player = AudioStreamPlayer3D.new()
		_impact_player.stream = punch_impacts
		_impact_player.position.y = 1.2
		add_child(_impact_player)
	if block_impacts:
		_block_player = AudioStreamPlayer3D.new()
		_block_player.stream = block_impacts
		_block_player.position.y = 1.2
		add_child(_block_player)
	if death_sounds:
		_death_player = AudioStreamPlayer3D.new()
		_death_player.stream = death_sounds
		_death_player.position.y = 1.2
		add_child(_death_player)
	if swing_wooshes:
		_woosh_player = AudioStreamPlayer3D.new()
		_woosh_player.stream = swing_wooshes
		_woosh_player.position.y = 1.2
		add_child(_woosh_player)
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

	if attacking:
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

func _acquire_player() -> void:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or p.get("dead"):
			continue
		var d := global_position.distance_to((p as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = p
	player = best

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
	body_visual.tick(delta, net_anim, net_anim_t, net_ratio)

## What the server replicates about this enemy every tick.
func net_visual_state() -> Array:
	return [String(name), global_position, body_visual.rotation.y,
			last_anim, last_anim_t, last_ratio,
			is_winding_up(), windup_progress(), attacking, attack_duration,
			is_blocking()]

func net_apply_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, windup: bool, windup_prog: float,
		is_attacking: bool, atk_duration: float, guarding := false) -> void:
	net_pos = pos
	net_yaw = yaw
	net_anim = anim
	net_anim_t = anim_t
	net_ratio = ratio
	net_windup = windup
	net_windup_prog = windup_prog
	if is_attacking and not net_attacking:
		# swing just started: play the stretched punch montage + woosh
		if _woosh_player:
			_woosh_player.play()
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
	if _death_player:
		_death_player.play()
	body_visual.play_death()

# ---------------- combat states ----------------

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
	if _woosh_player:
		_woosh_player.play()
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
		var target_pos: Vector3 = p.server_body_pos()
		var to_p: Vector3 = target_pos + Vector3.UP * 1.0 - origin
		var dist := to_p.length()
		if dist > attack_reach + attack_radius:
			continue
		var flat := Vector3(to_p.x, 0, to_p.z).normalized()
		if fwd.dot(flat) < cos(deg_to_rad(attack_cone_deg)):
			continue
		# `self` goes along so a parried swing staggers us in return
		p.server_take_damage(attack_damage, flat * 3.0 + Vector3.UP * 1.5, 0, self)

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
	if result == Player.Guard.BLOCKED:
		# the guard held: it thuds off the block and it doesn't hurt, so no
		# flesh impact and no grunt
		body_visual.flash(Color(0.4, 0.7, 1.0), 0.15)
		if _block_player:
			_block_player.play()
		return
	body_visual.flash(Color(1.0, 0.85, 0.3), 0.12)
	body_visual.hit_react(0.28)
	body_visual.hitstop(0.06)
	if _impact_player:
		_impact_player.play()
	if _grunt_player and health > 0.0:
		_grunt_player.play() # lethal hits voice the death sound instead

func _die(attacker: int) -> void:
	Net.server_record_enemy_kill(String(name), attacker) # scoreboard + tells clients
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
	body_visual.tick(delta, anim, t, ratio)
