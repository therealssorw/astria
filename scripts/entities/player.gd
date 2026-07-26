class_name Player
extends CharacterBody3D
## Third-person action character. All spec numbers converted UE cm -> m
## and kept as @export tunables (mirrors the EditAnywhere UPROPERTYs).
##
## Multiplayer roles (one pawn per connected player, node name = peer id):
## - OWNER (is_local): simulates its own movement/swings for feel, reports
##   cosmetic state to the server ~20 Hz and asks the server to attack.
## - SERVER: runs the authoritative combat sim for EVERY pawn — stamina,
##   swing timing, hit traces, health, kills, deaths. Client reports are
##   validated (speed caps, anim whitelist); client damage never happens.
## - PUPPET (everyone else's view): interpolates relayed state, no physics.

# --- Movement ---
@export var walk_speed := 6.5            # was 5.0 (spec 500 cm/s)
@export var block_walk_speed := 3.6      # a guard is a fighting stance, not a crawl
@export var jump_velocity := 5.0         # 500
@export var air_control := 0.35
@export var ground_accel := 40.0
@export var orient_speed_deg := 500.0    # body orient-to-movement
@export var locked_orient_speed_deg := 540.0
## Squared-up movement caps (fractions of the current speed): sidesteps and
## backpedals are slower than driving forward, so ring position is a choice.
@export var strafe_speed_mult := 0.85
@export var back_speed_mult := 0.68
## Sprint: a flat multiplier on the walk. Free by design — getting somewhere is
## not what the stamina meter is for, and arriving at a fight already spent made
## every approach a decision about walking slowly.
@export var sprint_speed_mult := 1.5
## Per second held. 0 = free, which also means the meter keeps regenerating and
## an empty bar is no bar to running; raise it to put the run back on the meter.
@export var sprint_stamina_drain := 0.0
## Stamina needed to break into a run. Only meaningful alongside a drain.
@export var sprint_min_stamina := 0.0
## Gamepad only: push the stick near full forward for this long and the sprint
## starts on its own, so a long walk doesn't need a button held down.
@export var auto_sprint_time := 0.9
@export var auto_sprint_stick_min := 0.85
## Speed kept while a swing is out — punches commit you.
@export var attack_move_mult := 0.4
## Speed kept while staggered (parried / guard broken).
@export var stagger_move_mult := 0.15
## Inside this range the body squares up to the lock target and the legs
## strafe instead of turning to follow the movement.
@export var stance_range := 8.0

# --- Attacks ---
@export var heavy_attack_hold_time := 0.28
@export var combo_input_cache_tolerance := 0.5
## Third light punch closes the chain: this much extra damage and knockback
## (and enough force to rock an enemy back — see Enemy.flinch_knockback).
@export var combo_finisher_mult := 1.5
## Step into a locked target that is out of reach when the swing starts, so a
## committed punch closes the gap instead of hitting air.
@export var attack_lunge := 3.4
@export var attack_lunge_time := 0.15
@export var light_damage := 10.0
@export var light_reach := 1.4
@export var light_radius := 0.7
@export var light_knockback := 4.5       # 450
@export var light_launch := 2.5          # 250
@export var heavy_damage := 25.0
@export var heavy_reach := 1.8
@export var heavy_radius := 0.9
@export var heavy_knockback := 7.5       # 750
@export var heavy_launch := 4.0          # 400
@export var attack_cone_deg := 70.0
@export var locked_hit_bonus := 0.4      # +40 cm guaranteed-hit slack
# Timed stand-ins for montage anim notifies (light montage played at 1.45x,
# heavy at 1.25x in the original -> these are the resulting real-time marks).
@export var light_duration := 0.45
@export var light_hit_time := 0.18
@export var heavy_duration := 0.6
@export var heavy_hit_time := 0.3

# --- Guard ---
## Blocking only covers the front: a hit landing outside this cone (measured
## from where the body faces) goes straight through the guard.
@export var block_arc_deg := 120.0
## Fraction of a blocked hit's damage that still gets through (chip).
@export var block_chip_mult := 0.15
## Stamina a blocked hit drains, per point of damage absorbed. Run dry and the
## guard breaks — the block is a resource, not an off switch.
@export var block_stamina_per_damage := 0.7
## Stamina needed to hold a guard up at all.
@export var block_min_stamina := 8.0
## Raising the guard this soon before a hit lands is a PARRY: no damage at all
## and the attacker is left wide open.
@export var parry_window := 0.22
@export var parry_stamina_refund := 30.0
## How long a parried attacker / guard-broken defender stays helpless.
@export var parry_stagger_time := 0.9
@export var guard_break_stagger_time := 1.15

# --- Stamina ---
@export var max_stamina := 100.0
@export var stamina_cost := 8.0
@export var heavy_stamina_cost := 16.0
@export var stamina_regen := 16.0
## Regen pauses this long after a swing (and entirely while guarding), so
## flurries and turtling both actually cost something.
@export var stamina_regen_delay := 0.4

# --- Slide / dive ---
@export var dive_speed := 9.5            # 950
@export var dive_down_speed := 4.5       # 450
@export var slide_duration := 1.0
@export var slide_friction_boost_mult := 1.35
@export var slide_min_boost_speed := 9.5
@export var slide_slow_cap := 1.4        # 140
@export var slide_slow_mult := 0.30
@export var slide_jump_min_speed := 13.0 # 1300
@export var slide_jump_walk_mult := 2.0
@export var slide_jump_up := 4.5         # +450 up
@export var slide_weak_hop_mult := 0.85
@export var slide_input_buffer := 0.15
@export var slide_cooldown := 0.5
@export var capsule_half_height := 0.96
@export var slide_capsule_half_height := 0.48

# --- Lock-on ---
@export var lockon_cone_deg := 55.0
@export var lockon_range := 15.0         # 1500
@export var lockon_break_range := 20.0   # 2000
## How snappily the locked camera tracks the target (higher = stiffer).
@export var lock_camera_speed := 8.0
## The lock only tracks while the target is within this half-angle of the
## camera's view; behind you, the camera is yours to turn until he's back in it.
@export var lock_view_cone_deg := 80.0

# --- Health ---
@export var max_health := 100.0
@export var death_restart_delay := 3.0
## Health comes back on its own once a fighter has gone this long without
## taking damage, at `health_regen` a second up to `max_health`. A parry costs
## no health, so it doesn't stall the heal — being hit does, chip included.
## Set the rate to 0 to turn regeneration off entirely.
@export var health_regen := 6.0
@export var health_regen_delay := 3.0
## This character's grunt pair — one random grunt plays per unblocked hit.
## Each character gets exactly one pair (player pair still unassigned).
@export var hurt_grunts: AudioStream
## Impact thud played when a punch gets through to this character.
@export var punch_impacts: AudioStream = preload("res://Assets/Audio/SFX/Impacts/Punches/punch_impacts.tres")
## Played instead when the guard eats the hit — a block sounds like a block,
## and no grunt goes with it, so blocked and clean hits never sound alike.
@export var block_impacts: AudioStream = preload("res://Assets/Audio/SFX/Impacts/Blocks/block_impacts.tres")
## Played once when this character dies.
@export var death_sounds: AudioStream = preload("res://Assets/Audio/SFX/Deaths/death_sounds.tres")
## Swing woosh — plays the moment any attack starts, whether or not it hits.
@export var swing_wooshes: AudioStream = preload("res://Assets/Audio/SFX/Wooshes/woosh_sounds.tres")

@export var mouse_sensitivity := 0.0025

@onready var cam_rig: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var body_visual: Node3D = $Visual
@onready var col_shape: CollisionShape3D = $CollisionShape3D

# --- Multiplayer identity (set by Net before add_child) ---
var peer_id := 1
var username := ""
var is_local := true

## How an incoming hit resolved — drives damage, feedback and the HUD.
enum Guard { HIT = 0, BLOCKED = 1, PARRIED = 2, BROKEN = 3 }

const NET_SEND_INTERVAL := 1.0 / 20.0
const ANIM_WHITELIST := ["idle", "run", "air", "block", "slide", "dive",
		"strafe_l", "strafe_r", "walk_back",
		"block_fwd", "block_back", "block_l", "block_r",
		"attack_heavy", "attack_light_0", "attack_light_1", "attack_light_2"]
# movement validation: fastest legit burst (slide jump 13 + knockback 7.5)
const MAX_H_SPEED := 26.0
const MAX_UP_SPEED := 14.0

var health: float
var stamina: float
var blocking := false
var dead := false
var ui_open := false # set by the inventory UI; freezes combat/movement input
## The player let the pointer go with Esc, with no panel asking for it.
var _free_cursor := false
## Ticks left to swallow the click that took the pointer back, so clicking into
## the window doesn't also throw a punch.
var _recapture_frames := 0
## >0: parried or guard broken — no attacking, no guard, barely any movement.
var stagger_time := 0.0
## When the guard last went UP (the parry window is measured from here).
var block_start_time := -10.0

# attack state
var attacking := false
var attack_is_heavy := false
var attack_timer := 0.0
var attack_did_hit := false
var combo_index := 0
var attack_duration := 0.45
var attack_hit_time := 0.18
var attack_combo_time := 0.3
var hit_actors := {}
var attack_face_dir := Vector3.FORWARD
var lunge_left := 0.0
var lunge_dir := Vector3.ZERO
# tap/hold
var holding_attack := false
var hold_time := 0.0
var cached_press_time := -10.0
var cached_press_heavy := false

# local-only feedback timers, read by the HUD
var fx_hitmarker_time := 0.0
var fx_parry_time := 0.0
var fx_break_time := 0.0
var _shake := 0.0
var _stam_hold := 0.0 # regen pause after spending stamina
var _hurt_hold := 0.0 # SERVER: heal pause after taking damage

# sprint state
var sprinting := false
var _auto_sprint_hold := 0.0 # how long the pad stick has been at full forward

# slide state
var sliding := false
var slide_timer := 0.0
var slide_dir := Vector3.FORWARD
var pending_landing_slide := false
var pending_slide_time := -10.0
var slide_cooldown_left := 0.0
var diving := false

# lock-on
var lock_target: Node3D = null
var look_input_time := -10.0

# what _animate last showed — this is what gets replicated
var last_anim := "idle"
var last_anim_t := 0.0
var last_ratio := 0.0

# puppet interpolation targets (on the server: the last ACCEPTED claim)
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_anim := "idle"
var net_anim_t := 0.0
var net_ratio := 0.0
var net_blocking := false
var net_sprinting := false
var _net_has_state := false
var _last_report_time := -1.0
var _net_send_accum := 0.0

# server-side combat bookkeeping for remote pawns
var _srv_pending_heavy := false
var _srv_pending_time := -10.0
var _srv_pending_lock := NodePath("")
var _srv_pending_aim := 0.0 # yaw the queued swing was aimed along
var _srv_combo_deadline := -10.0

var _time := 0.0
var _grunt_player: AudioStreamPlayer3D
var _impact_player: AudioStreamPlayer3D
var _block_player: AudioStreamPlayer3D
var _death_player: AudioStreamPlayer3D
var _woosh_player: AudioStreamPlayer3D

func _ready() -> void:
	health = max_health
	stamina = max_stamina
	add_to_group("player")
	is_local = peer_id == multiplayer.get_unique_id()
	if is_local:
		add_to_group("local_player")
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		# puppets don't collide or self-simulate — the owner + server do
		collision_layer = 0
		collision_mask = 0
		set_process_unhandled_input(false)
		cam_rig.queue_free()
		cam_rig = null
		spring_arm = null
		camera = null
		_make_nametag()
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
	# what this pawn is holding rides along with the public registry, so every
	# peer draws the same thing in its hand
	Net.player_list_changed.connect(_refresh_held_item)
	_refresh_held_item()
	if is_local:
		# the tutorial holds its bandits until the player's own client is
		# standing in the world; nothing else gates it now
		Net.report_tutorial_ready.call_deferred()

## Put the hotbar item the SERVER says this player holds into its hand. Purely
## visual: the pawn asks nobody's permission to draw it, and the id is not
## something the local client chose.
func _refresh_held_item() -> void:
	if body_visual == null or not body_visual.has_method("set_held_item"):
		return
	body_visual.set_held_item(Net.held_of(peer_id))

func _make_nametag() -> void:
	var tag := Label3D.new()
	tag.text = username
	tag.position = Vector3(0, 2.3, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 64
	tag.pixel_size = 0.004
	tag.outline_size = 16
	tag.visibility_range_end = 60.0
	add_child(tag)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if not _lock_in_view(): # tracking camera owns yaw; pitch stays free
			cam_rig.rotation.y -= event.relative.x * mouse_sensitivity
		spring_arm.rotation.x = clampf(spring_arm.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(-75), deg_to_rad(60))
		if event.relative.length_squared() > 0.5:
			look_input_time = _time
	elif event.is_action_pressed("ui_cancel"):
		# an open panel owns Esc — it closes with it, and the pointer comes back
		# on its own. The pawn only uses Esc to let go when nothing is up, or a
		# press aimed at a panel would leave the cursor freed behind it
		if not _ui_wants_cursor():
			_free_cursor = not _free_cursor
	elif _free_cursor and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# clicking back into the world takes the pointer again: Esc alone as the
		# way home is how a loose cursor turned into a stuck one
		_free_cursor = false
		_recapture_frames = 2

func _physics_process(delta: float) -> void:
	_time += delta
	stagger_time = maxf(0.0, stagger_time - delta)
	# health belongs to the server for every pawn, its own included — so the
	# heal is ticked here rather than in either role's branch below
	if multiplayer.is_server():
		_regen_health(delta)
	if is_local:
		_tick_local_fx(delta)
		_local_tick(delta)
	else:
		_puppet_tick(delta)
		if multiplayer.is_server():
			_server_sim_tick(delta)

## The pointer has ONE owner. It is visible while a panel wants it or while the
## player let it go with Esc, and captured every other tick. Panels used to set
## the mode themselves on open and on close, so any pair that ran out of order —
## a shop opening over a dialog that then closed, a panel closed by something
## other than its own key — left the cursor loose with no way back. Re-asserting
## it every tick means a stray release repairs itself the next frame.
func _tick_mouse_mode() -> void:
	if not get_window().has_focus():
		return # alt-tabbed away: the pointer belongs to whatever is in front
	var want := Input.MOUSE_MODE_VISIBLE if _free_cursor or _ui_wants_cursor() \
			else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want

## True while any open panel needs the pointer. Panels declare themselves by
## joining the "ui_panel" group and answering `is_open()`, so this never has to
## know which panels exist — a new one only has to join the group.
func _ui_wants_cursor() -> bool:
	for panel in get_tree().get_nodes_in_group("ui_panel"):
		if panel.has_method("is_open") and panel.is_open():
			return true
	return false

# ---------------- owner simulation ----------------

func _local_tick(delta: float) -> void:
	_tick_mouse_mode()
	_recapture_frames = maxi(0, _recapture_frames - 1)
	if dead:
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= _gravity() * delta
		move_and_slide()
		return

	if not ui_open:
		_gamepad_look(delta)
		_update_lockon(delta)
		_camera_assist(delta)
		_handle_hotbar_input()
		# helpless: no guard, no swings, no slides — and nothing on the frame the
		# pointer came back, or that click lands as a punch
		if stagger_time <= 0.0 and _recapture_frames <= 0:
			_handle_block()
			_handle_attack_input(delta)
			_handle_slide_input()
		else:
			blocking = false
	_tick_attack(delta)
	_tick_slide(delta)
	_handle_sprint(delta)
	_move(delta)
	_orient_body(delta)
	_regen_stamina(delta)
	_animate(delta)
	_net_send(delta)

## R1/L1 (or ] and [) walk the hotbar selection, and use_item uses whatever
## that slot holds. Both are requests: the server owns the bar and decides what
## using an item does, so nothing is applied here.
func _handle_hotbar_input() -> void:
	var step := 0
	if Input.is_action_just_pressed("hotbar_next"):
		step += 1
	if Input.is_action_just_pressed("hotbar_prev"):
		step -= 1
	if step != 0:
		var slots: int = Net.HOTBAR_SLOTS
		Net.request_hotbar_select(posmod(GameStats.hot_slot + step, slots))
	if Input.is_action_just_pressed("use_item"):
		Net.request_use_item()

## Owner-only presentation: HUD cue timers and the camera kick from impacts.
func _tick_local_fx(delta: float) -> void:
	fx_hitmarker_time = maxf(0.0, fx_hitmarker_time - delta)
	fx_parry_time = maxf(0.0, fx_parry_time - delta)
	fx_break_time = maxf(0.0, fx_break_time - delta)
	if _shake <= 0.0 or camera == null:
		return
	_shake = maxf(0.0, _shake - delta * 3.2)
	# offsets, not rotation: a shake must never fight the player's aim
	var s := _shake * _shake
	camera.h_offset = sin(_time * 61.0) * 0.07 * s
	camera.v_offset = cos(_time * 47.0) * 0.05 * s

func _add_shake(amount: float) -> void:
	if is_local:
		_shake = minf(_shake + amount, 1.0)

func _net_send(delta: float) -> void:
	_net_send_accum += delta
	if _net_send_accum >= NET_SEND_INTERVAL:
		_net_send_accum = 0.0
		Net.send_player_state(global_position, body_visual.rotation.y,
				last_anim, last_anim_t, last_ratio, blocking, sprinting)

func _gravity() -> float:
	return ProjectSettings.get_setting("physics/3d/default_gravity")

# ---------------- puppet / server views ----------------

func _puppet_tick(delta: float) -> void:
	if _net_has_state:
		if global_position.distance_to(net_pos) > 6.0:
			global_position = net_pos
		else:
			global_position = global_position.lerp(net_pos, minf(delta * 12.0, 1.0))
		body_visual.rotation.y = lerp_angle(body_visual.rotation.y, net_yaw, minf(delta * 14.0, 1.0))
	if dead:
		return
	body_visual.tick(delta, net_anim, net_anim_t, net_ratio)

## SERVER: authoritative stamina/swing/blocking sim for a remote pawn.
func _server_sim_tick(delta: float) -> void:
	if dead:
		return
	blocking = net_blocking and not attacking and stagger_time <= 0.0 \
			and stamina >= block_min_stamina
	# a run costs the same on the server's copy of the meter as on the owner's,
	# so a sprint across the island reaches the fight with the stamina it should
	# (nothing at all while sprint_stamina_drain is 0 — the run is free)
	if net_sprinting and not blocking and sprint_stamina_drain > 0.0:
		stamina = maxf(0.0, stamina - sprint_stamina_drain * delta)
		_stam_hold = stamina_regen_delay
		if stamina <= 0.0:
			net_sprinting = false
	_regen_stamina(delta) # same rule as the owner: none while guarding/swinging
	if not attacking:
		return
	attack_timer += delta
	if not attack_did_hit and attack_timer >= attack_hit_time:
		attack_did_hit = true
		_do_attack_trace()
	# a queued request chains at the combo point, matching the owner's predicted
	# timing — otherwise the server would lag a punch behind every chain
	if attack_did_hit and not attack_is_heavy and attack_timer >= attack_combo_time \
			and _time - _srv_pending_time <= combo_input_cache_tolerance:
		var pending_heavy := _srv_pending_heavy
		var pending_lock := _srv_pending_lock
		var pending_aim := _srv_pending_aim
		_srv_pending_time = -10.0
		_srv_try_start(pending_heavy, pending_lock, pending_aim)
		return
	if attack_timer >= attack_duration:
		attacking = false
		if attack_is_heavy:
			combo_index = 0
			_srv_combo_deadline = -10.0
		else:
			_srv_combo_deadline = _time + combo_input_cache_tolerance
		if _time - _srv_pending_time <= combo_input_cache_tolerance:
			var h := _srv_pending_heavy
			var lp := _srv_pending_lock
			var aim := _srv_pending_aim
			_srv_pending_time = -10.0
			_srv_try_start(h, lp, aim)

## True while the guard is up. Mirrors Enemy.is_blocking() so the HUD can ask
## any lock-on target the same question; `blocking` is already replicated.
func is_blocking() -> bool:
	return blocking and not dead

## SERVER: last position accepted from the owner (never the interpolated one).
func server_body_pos() -> Vector3:
	if not is_local and _net_has_state:
		return net_pos
	return global_position

## Where the body faces, from the server's point of view (the owner's last
## accepted yaw claim for a remote pawn). Guard arcs are judged against this.
func server_facing() -> Vector3:
	if not is_local and _net_has_state:
		return Vector3(sin(net_yaw), 0.0, cos(net_yaw))
	return _body_forward()

## SERVER: apply + validate an owner's state report. False = rejected.
func net_report_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, blocking_flag: bool, sprint_flag := false) -> bool:
	if not pos.is_finite() or not is_finite(yaw):
		return false
	var prev := net_pos if _net_has_state else global_position
	var dt := 0.1
	if _last_report_time >= 0.0:
		dt = clampf(_time - _last_report_time, 1.0 / 60.0, 0.5)
	_last_report_time = _time
	var dv := pos - prev
	if Vector2(dv.x, dv.z).length() > MAX_H_SPEED * dt + 0.4:
		return false
	if dv.y > MAX_UP_SPEED * dt + 0.5:
		return false # falling (negative) is unrestricted
	net_pos = pos
	net_yaw = yaw
	net_anim = anim if ANIM_WHITELIST.has(anim) else "idle"
	net_anim_t = clampf(anim_t, 0.0, 10.0)
	net_ratio = clampf(ratio, 0.0, 3.0)
	# the guard going up is what the parry window is measured from; a report
	# lands within 50 ms of the press, well inside the window
	if blocking_flag and not net_blocking:
		block_start_time = _time
	net_blocking = blocking_flag
	# a sprint claim is only believed if the pawn actually covered more ground
	# than a walk would — the drain below is charged off the server's own
	# measurement, never off the client saying "I'm running"
	net_sprinting = sprint_flag \
			and Vector2(dv.x, dv.z).length() > walk_speed * dt * 0.9
	_net_has_state = true
	return true

## CLIENT: relayed state of someone else's pawn.
func net_apply_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, blocking_flag: bool, sprint_flag := false) -> void:
	net_pos = pos
	net_yaw = yaw
	net_sprinting = sprint_flag
	net_anim = anim if ANIM_WHITELIST.has(anim) else "idle"
	net_anim_t = anim_t
	net_ratio = ratio
	net_blocking = blocking_flag
	if not multiplayer.is_server():
		blocking = blocking_flag
	_net_has_state = true

## What the server relays to everyone about this pawn.
func net_collect_state() -> Array:
	if is_local:
		return [peer_id, global_position, body_visual.rotation.y,
				last_anim, last_anim_t, last_ratio, blocking, sprinting]
	return [peer_id, net_pos, net_yaw, net_anim, net_anim_t, net_ratio,
			net_blocking, net_sprinting]

# ---------------- movement ----------------

func _input_dir() -> Vector3:
	if ui_open:
		return Vector3.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v == Vector2.ZERO:
		return Vector3.ZERO
	return (Basis(Vector3.UP, cam_rig.rotation.y) * Vector3(v.x, 0, v.y)).normalized()

func _move(delta: float) -> void:
	# floor state BEFORE this frame's move — landing is detected by comparing
	# against the state AFTER move_and_slide() below (is_on_floor() only
	# changes inside move_and_slide, so a pre-move comparison never fires)
	var was_on_floor := is_on_floor()
	if not was_on_floor:
		velocity.y -= _gravity() * delta

	if sliding:
		var half := slide_timer < slide_duration * 0.5
		var speed := maxf(slide_min_boost_speed, walk_speed * slide_friction_boost_mult) if half \
				else minf(slide_slow_cap, walk_speed * slide_slow_mult)
		velocity.x = slide_dir.x * speed
		velocity.z = slide_dir.z * speed
		if Input.is_action_just_pressed("jump"):
			_slide_jump(half)
		move_and_slide()
		return

	var dir := _input_dir()
	var speed := block_walk_speed if blocking else walk_speed
	if sprinting:
		speed *= sprint_speed_mult
	if attacking:
		speed *= attack_move_mult
	if stagger_time > 0.0:
		speed *= stagger_move_mult
	if dir != Vector3.ZERO and _in_stance():
		speed *= _directional_mult(dir)
	var target := dir * speed
	if lunge_left > 0.0:
		lunge_left = maxf(0.0, lunge_left - delta)
		target = lunge_dir * attack_lunge # the step into a swing owns movement
	var accel := ground_accel if was_on_floor else ground_accel * air_control
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if not ui_open and Input.is_action_just_pressed("jump") and was_on_floor:
		velocity.y = jump_velocity

	move_and_slide()

	# just touched down: the dive is over either way; start the buffered slide
	if is_on_floor() and not was_on_floor:
		diving = false
		if pending_landing_slide or (_time - pending_slide_time) <= slide_input_buffer:
			pending_landing_slide = false
			_start_ground_slide()

## Sprint is a straight-line commitment: forward input, on the ground, guard
## down, no swing. It ends the moment any of those goes. It is free at the
## current tuning; with a `sprint_stamina_drain` set it also ends on an empty
## meter.
func _handle_sprint(delta: float) -> void:
	if not _can_sprint():
		sprinting = false
		_auto_sprint_hold = 0.0
		return
	# a pad that has been pushed flat forward for a while starts running by
	# itself; keyboards read zero on the stick axes, so this never fires there
	if _stick_full_forward():
		_auto_sprint_hold += delta
	else:
		_auto_sprint_hold = 0.0
	var want := Input.is_action_pressed("sprint") or _auto_sprint_hold >= auto_sprint_time
	# breaking into a run needs a bit in the bank; keeping one only needs a drop
	sprinting = want and (sprinting or stamina >= sprint_min_stamina)
	if not sprinting or sprint_stamina_drain <= 0.0:
		return # a free run must not pause regen either, or it still costs
	stamina = maxf(0.0, stamina - sprint_stamina_drain * delta)
	_stam_hold = stamina_regen_delay
	if stamina <= 0.0:
		sprinting = false
		_auto_sprint_hold = 0.0

func _can_sprint() -> bool:
	if ui_open or dead or sliding or diving or blocking or attacking:
		return false
	if stagger_time > 0.0 or not is_on_floor():
		return false
	return _forward_input() >= 0.4

## How hard the movement input pushes away from the camera (0 = sideways or
## back). Sprinting is forward only — a backpedal at run speed is not a thing.
func _forward_input() -> float:
	if ui_open:
		return 0.0
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return maxf(0.0, -v.y)

func _stick_full_forward() -> bool:
	var x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	return Vector2(x, y).length() >= auto_sprint_stick_min \
			and -y >= auto_sprint_stick_min * 0.6

## Squared-up fighting stance: the body holds its guard toward the threat and
## the legs sidestep/backpedal, instead of the body turning to chase movement.
## Guarding always counts; a lock-on only once the fight is actually close.
func _in_stance() -> bool:
	if sliding or diving:
		return false
	if blocking:
		return true
	return is_instance_valid(lock_target) \
			and global_position.distance_to(lock_target.global_position) <= stance_range

## The direction the stance is squared up to: the locked opponent, else wherever
## the camera looks (guarding without a lock still faces the threat).
func _stance_forward() -> Vector3:
	if is_instance_valid(lock_target):
		var to_t := lock_target.global_position - global_position
		to_t.y = 0
		if to_t.length_squared() > 0.001:
			return to_t.normalized()
	if camera:
		var cam_fwd := -camera.global_transform.basis.z
		cam_fwd.y = 0
		if cam_fwd.length_squared() > 0.001:
			return cam_fwd.normalized()
	return _body_forward()

## Sidesteps and backpedals are slower than a straight advance; the two caps
## blend by how much of the input runs along the facing axis (so diagonals sit
## in between instead of snapping between speeds).
func _directional_mult(dir: Vector3) -> float:
	var fwd := _stance_forward()
	if fwd.length_squared() < 0.001:
		return 1.0
	var along := dir.dot(fwd)
	var axial := 1.0 if along >= 0.0 else back_speed_mult
	return lerpf(strafe_speed_mult, axial, absf(along))

func _orient_body(delta: float) -> void:
	var target_dir := Vector3.ZERO
	var rate := orient_speed_deg
	# a lock-on alone doesn't steer the body — but a fighting stance does:
	# it holds the front toward the threat so the legs can strafe around it
	if attacking:
		target_dir = attack_face_dir
		rate = locked_orient_speed_deg
	elif _in_stance():
		target_dir = _stance_forward()
		rate = locked_orient_speed_deg
	else:
		var h := Vector3(velocity.x, 0, velocity.z)
		if h.length() > 0.5:
			target_dir = h
	target_dir.y = 0
	if target_dir.length_squared() < 0.001:
		return
	body_visual.rotation.y = rotate_toward(body_visual.rotation.y, _yaw_of(target_dir), deg_to_rad(rate) * delta)

## Body yaw that faces `dir`. Inverse of the Vector3(sin(yaw), 0, cos(yaw)) the
## server uses to read a reported yaw back into a direction.
func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z) + PI

func _body_forward() -> Vector3:
	# facing dir is +Z: the orient yaw (atan2 + PI) turns basis.z toward the target
	return body_visual.global_transform.basis.z

# ---------------- block ----------------

func _handle_block() -> void:
	# punching overrides blocking: the guard only holds while not swinging,
	# and comes back up on its own after the swing if block is still held.
	# An empty guard meter can't hold anything up (see server_take_damage).
	var want := Input.is_action_pressed("block") and not attacking \
			and stamina >= block_min_stamina
	if want and not blocking:
		block_start_time = _time # a fresh guard can parry
	blocking = want

# ---------------- attacks ----------------

func _handle_attack_input(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		cached_press_time = _time
		cached_press_heavy = false
		holding_attack = true
		hold_time = 0.0
	if holding_attack:
		hold_time += delta
		if hold_time >= heavy_attack_hold_time:
			holding_attack = false
			# a hold that matured mid-swing queues a HEAVY as the chain ender
			cached_press_heavy = true
			cached_press_time = _time
			_try_start_attack(true)
		elif Input.is_action_just_released("attack"):
			holding_attack = false
			_try_start_attack(false)

func _try_start_attack(heavy: bool) -> void:
	if dead or sliding or stagger_time > 0.0:
		return
	if attacking:
		return # press already cached for the combo check
	if stamina < (heavy_stamina_cost if heavy else stamina_cost):
		return
	_start_swing(heavy, 0 if heavy else combo_index)

## Shared swing bookkeeping — the owner's prediction and the server's
## authoritative copy must start from identical numbers.
func _begin_swing(heavy: bool, section: int) -> void:
	stamina -= heavy_stamina_cost if heavy else stamina_cost
	_stam_hold = stamina_regen_delay
	attacking = true
	blocking = false # guard drops the moment the punch starts
	attack_is_heavy = heavy
	attack_timer = 0.0
	attack_did_hit = false
	combo_index = section
	hit_actors = {}
	# swing timing comes from the actual clip at montage rate when the visual
	# provides it; exports are the fallback
	if body_visual.has_method("get_attack_info"):
		var info: Dictionary = body_visual.get_attack_info(heavy, section)
		attack_duration = info.duration
		attack_hit_time = info.hit
		attack_combo_time = info.combo
	else:
		attack_duration = heavy_duration if heavy else light_duration
		attack_hit_time = heavy_hit_time if heavy else light_hit_time
		attack_combo_time = attack_duration * 0.7

func _start_swing(heavy: bool, section: int) -> void:
	_begin_swing(heavy, section)
	# the press that fed this swing is spent — otherwise one tap would keep
	# chaining itself now that a chain starts well before the clip ends
	cached_press_time = -10.0
	cached_press_heavy = false
	if _woosh_player:
		_woosh_player.play()
	if body_visual.has_method("on_attack_started"):
		body_visual.on_attack_started(heavy, section)
	# Facing: the locked target if there is one, otherwise straight down the
	# camera — where you are LOOKING, which is the only aim an unlocked punch
	# has. It used to prefer the direction you were moving whenever you were
	# moving at all, so strafing past someone threw the punch off sideways and
	# backing away threw it behind you.
	if lock_target:
		attack_face_dir = lock_target.global_position - global_position
	else:
		attack_face_dir = -camera.global_transform.basis.z
	attack_face_dir.y = 0
	if attack_face_dir.length_squared() > 0.001:
		attack_face_dir = attack_face_dir.normalized()
		# A swing commits the stance: turn to it NOW instead of catching up at
		# orient speed. The body yaw is what the server aims the trace along, and
		# at 540 deg/s a swing thrown mid-turn landed up to a right angle away
		# from what the player saw.
		body_visual.rotation.y = _yaw_of(attack_face_dir)
	_attack_lunge_step(heavy)
	# the owner's swing is a prediction — only the server's copy of this
	# swing (host pawn, or _srv_start_swing for remote pawns) deals damage
	if multiplayer.is_server():
		Net.server_broadcast_swing(peer_id, heavy, section)
	else:
		var lock_path := NodePath("")
		if is_instance_valid(lock_target):
			lock_path = lock_target.get_path()
		Net.request_attack(heavy, lock_path, body_visual.rotation.y)

## A committed swing steps into a locked opponent that is out of reach, so
## punching at the edge of the ring closes the gap instead of hitting air.
func _attack_lunge_step(heavy: bool) -> void:
	if attack_lunge <= 0.0 or sliding or not is_instance_valid(lock_target):
		return
	var reach := heavy_reach if heavy else light_reach
	if global_position.distance_to(lock_target.global_position) <= reach:
		return
	# held for a beat by _move — a one-frame impulse would be scrubbed out by
	# the ground accel long before it moved anyone
	lunge_left = attack_lunge_time
	lunge_dir = attack_face_dir
	velocity.x = lunge_dir.x * attack_lunge
	velocity.z = lunge_dir.z * attack_lunge

func _tick_attack(delta: float) -> void:
	if not attacking:
		return
	attack_timer += delta

	if not attack_did_hit and attack_timer >= attack_hit_time:
		attack_did_hit = true
		if multiplayer.is_server(): # only the server's trace deals damage
			_do_attack_trace()

	# a press cached during the swing chains at the combo point — after contact
	# but before the clip's recovery tail, which is what makes punches flow.
	# A matured hold chains into a heavy as the ender.
	var queued := _time - cached_press_time
	if not attack_is_heavy and attack_did_hit and attack_timer >= attack_combo_time \
			and queued <= combo_input_cache_tolerance and queued > 0.01:
		var next_heavy := cached_press_heavy
		if stamina >= (heavy_stamina_cost if next_heavy else stamina_cost):
			_start_swing(next_heavy, 0 if next_heavy else (combo_index + 1) % 3)
			return

	if attack_timer >= attack_duration:
		attacking = false
		combo_index = 0

## SERVER: a remote client pressed attack. Validate, don't trust.
func server_handle_attack_request(heavy: bool, lock_path: NodePath, aim_yaw: float) -> void:
	if dead or sliding or stagger_time > 0.0:
		return
	if attacking:
		# cache it like the local combo buffer does
		_srv_pending_heavy = heavy
		_srv_pending_time = _time
		_srv_pending_lock = lock_path
		_srv_pending_aim = aim_yaw
		return
	_srv_try_start(heavy, lock_path, aim_yaw)

func _srv_try_start(heavy: bool, lock_path: NodePath, aim_yaw: float) -> void:
	if dead or stagger_time > 0.0:
		return
	if stamina < (heavy_stamina_cost if heavy else stamina_cost):
		return
	var section := 0
	if not heavy and _time <= _srv_combo_deadline:
		section = (combo_index + 1) % 3
	elif not heavy and attacking:
		section = (combo_index + 1) % 3 # chaining straight out of a live swing
	# resolve the claimed lock target; the trace still range-checks it
	lock_target = null
	if not lock_path.is_empty():
		var t := get_node_or_null(lock_path)
		if t is Node3D and t != self \
				and (t.is_in_group("enemies") or t.is_in_group("player")):
			lock_target = t
	_begin_swing(heavy, section)
	if lock_target:
		attack_face_dir = lock_target.global_position - server_body_pos()
	else:
		# the yaw the swing was thrown along, not whatever the last state report
		# happened to say the body was doing when the request landed
		attack_face_dir = Vector3(sin(aim_yaw), 0, cos(aim_yaw))
	attack_face_dir.y = 0
	if attack_face_dir.length_squared() > 0.001:
		attack_face_dir = attack_face_dir.normalized()
	Net.server_broadcast_swing(peer_id, heavy, section)

## Cosmetic swing on a puppet (the server already validated it).
func puppet_play_swing(heavy: bool, section: int) -> void:
	if _woosh_player:
		_woosh_player.play()
	if body_visual.has_method("on_attack_started"):
		body_visual.on_attack_started(heavy, clampi(section, 0, 2))

## SERVER ONLY: the single place a player swing deals damage. Uses the
## server's own positions and damage numbers — nothing client-supplied.
func _do_attack_trace() -> void:
	var reach := heavy_reach if attack_is_heavy else light_reach
	var radius := heavy_radius if attack_is_heavy else light_radius
	var damage := heavy_damage if attack_is_heavy else light_damage
	var knockback := heavy_knockback if attack_is_heavy else light_knockback
	var launch := heavy_launch if attack_is_heavy else light_launch
	# the third light punch is the ender: it hits like a heavy, which is also
	# what lets it rock an enemy back (Enemy.flinch_knockback)
	if not attack_is_heavy and combo_index == 2:
		damage *= combo_finisher_mult
		knockback *= combo_finisher_mult
		launch *= combo_finisher_mult

	var origin := server_body_pos() + Vector3.UP * 1.0
	var fwd := attack_face_dir
	if fwd.length_squared() < 0.001:
		fwd = _body_forward()
	fwd.y = 0
	fwd = fwd.normalized()
	var cone_cos := cos(deg_to_rad(attack_cone_deg))

	var targets := []
	for e in get_tree().get_nodes_in_group("enemies"):
		targets.append(e)
	for p in get_tree().get_nodes_in_group("player"):
		if p != self:
			targets.append(p) # PvP: other players can be punched too
	for e: Node3D in targets:
		if not is_instance_valid(e) or e.get("dead"):
			continue
		if hit_actors.has(e):
			continue
		var target_pos: Vector3 = e.server_body_pos() if e is Player else e.global_position
		var to_target: Vector3 = target_pos + Vector3.UP * 1.0 - origin
		var dist := to_target.length()
		var flat := Vector3(to_target.x, 0, to_target.z).normalized()
		var in_range := dist <= reach + radius
		var in_cone := fwd.dot(flat) >= cone_cos
		# nobody misses a body they are stood inside. At that distance the cone is
		# only measuring which way two overlapping capsules lean, and it is what
		# ate the punch every time an enemy closed all the way in
		var point_blank := dist <= radius
		# locked target is guaranteed within reach + radius + slack, even off-angle
		var guaranteed: bool = e == lock_target and dist <= reach + radius + locked_hit_bonus
		if (in_range and (in_cone or point_blank)) or guaranteed:
			hit_actors[e] = true
			var away := flat if flat.length_squared() > 0.001 else fwd
			var kb := away * knockback + Vector3.UP * launch
			# `self` goes along so a parry can stagger whoever swung
			if e is Player:
				e.server_take_damage(damage, kb, peer_id, self)
			else:
				e.take_damage(damage, kb, peer_id, self)

# ---------------- slide / dive ----------------

func _handle_slide_input() -> void:
	if not Input.is_action_just_pressed("slide"):
		return
	pending_slide_time = _time
	if sliding or slide_cooldown_left > 0.0:
		return
	# A press with both feet down does nothing: slide shares the jump button, so
	# on the ground that press IS the jump. Every slide is landed into — dive out
	# of the air, or press just before touching down (slide_input_buffer below).
	if is_on_floor():
		return
	# air press: dive, then slide on landing
	var dir := _input_dir()
	if dir == Vector3.ZERO:
		dir = _body_forward()
		dir.y = 0
		dir = dir.normalized()
	slide_dir = dir
	velocity = dir * dive_speed + Vector3.DOWN * dive_down_speed
	diving = true
	pending_landing_slide = true

func _start_ground_slide() -> void:
	# clear the dive BEFORE the cooldown gate — otherwise a blocked slide
	# leaves `diving` true forever (stuck lean-forward pose)
	diving = false
	if slide_cooldown_left > 0.0:
		return
	sliding = true
	slide_timer = 0.0
	attacking = false
	lunge_left = 0.0
	var shape: CapsuleShape3D = col_shape.shape
	shape.height = slide_capsule_half_height * 2.0
	col_shape.position.y = slide_capsule_half_height

func _tick_slide(delta: float) -> void:
	slide_cooldown_left = maxf(0.0, slide_cooldown_left - delta)
	if not sliding:
		return
	slide_timer += delta
	if slide_timer >= slide_duration:
		_end_slide()

func _end_slide() -> void:
	sliding = false
	diving = false
	slide_cooldown_left = slide_cooldown
	var shape: CapsuleShape3D = col_shape.shape
	shape.height = capsule_half_height * 2.0
	col_shape.position.y = capsule_half_height

func _slide_jump(in_boost_half: bool) -> void:
	if in_boost_half:
		# the core trick: huge launch preserving direction
		var speed := maxf(slide_jump_min_speed, walk_speed * slide_jump_walk_mult)
		velocity = slide_dir * speed + Vector3.UP * slide_jump_up
	else:
		# weak hop, no speed carry
		var h := Vector3(velocity.x, 0, velocity.z)
		var cap := walk_speed * slide_weak_hop_mult
		if h.length() > cap:
			h = h.normalized() * cap
		velocity = Vector3(h.x, jump_velocity, h.z)
	_end_slide()

# ---------------- lock-on ----------------

func _update_lockon(_delta: float) -> void:
	if Input.is_action_just_pressed("lock_on"):
		if lock_target:
			lock_target = null
		else:
			lock_target = _pick_lockon_target()
	if lock_target:
		if not is_instance_valid(lock_target) or lock_target.get("dead") \
				or global_position.distance_to(lock_target.global_position) > lockon_break_range:
			lock_target = null

## Enemies plus every other living player (PvP lock-on).
func _lockon_candidates() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		out.append(e)
	for p in get_tree().get_nodes_in_group("player"):
		if p != self:
			out.append(p)
	return out

func _pick_lockon_target() -> Node3D:
	var cam_fwd := -camera.global_transform.basis.z
	var cone_cos := cos(deg_to_rad(lockon_cone_deg))
	var best: Node3D = null
	var best_dist := INF
	var nearest: Node3D = null
	var nearest_dist := INF
	for e: Node3D in _lockon_candidates():
		if not is_instance_valid(e) or e.get("dead"):
			continue
		var to_e: Vector3 = e.global_position - camera.global_position
		var dist := global_position.distance_to(e.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = e
		if dist <= lockon_range and cam_fwd.dot(to_e.normalized()) >= cone_cos and dist < best_dist:
			best_dist = dist
			best = e
	return best if best else nearest

func _gamepad_look(delta: float) -> void:
	var x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(x) > 0.15 or absf(y) > 0.15:
		if not _lock_in_view(): # tracking camera owns yaw; pitch stays free
			cam_rig.rotation.y -= x * 2.5 * delta
		spring_arm.rotation.x = clampf(spring_arm.rotation.x - y * 1.8 * delta, deg_to_rad(-75), deg_to_rad(60))
		look_input_time = _time

## True when the locked target is within the tracking cone of the camera view.
func _lock_in_view() -> bool:
	if not lock_target:
		return false
	var to_t := lock_target.global_position - camera.global_position
	to_t.y = 0
	if to_t.length_squared() < 0.01:
		return true
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0
	if fwd.length_squared() < 0.001:
		return true
	return fwd.normalized().angle_to(to_t.normalized()) <= deg_to_rad(lock_view_cone_deg)

func _camera_assist(delta: float) -> void:
	# hard lock: while a target is locked AND in view the camera owns yaw and
	# keeps the enemy framed; the body stays fully player-driven. A target
	# behind the view must be brought back manually before tracking resumes.
	if not _lock_in_view():
		return
	var to_t := lock_target.global_position - camera.global_position
	to_t.y = 0
	if to_t.length_squared() < 0.01:
		return
	var target_yaw := atan2(-to_t.x, -to_t.z)
	var weight := 1.0 - exp(-lock_camera_speed * delta)
	cam_rig.rotation.y = lerp_angle(cam_rig.rotation.y, target_yaw, weight)

# ---------------- stamina / health ----------------

func _regen_stamina(delta: float) -> void:
	_stam_hold = maxf(0.0, _stam_hold - delta)
	# a raised guard is holding the meter, and a swing just spent from it
	if attacking or blocking or _stam_hold > 0.0:
		return
	stamina = minf(max_stamina, stamina + stamina_regen * delta)

## SERVER ONLY: health climbs back once nothing has landed on this fighter for
## `health_regen_delay`. The owner never adds a point to its own bar — it gets
## the new number in the vitals sync, exactly the way damage arrives, so a
## patched client can only lie to its own screen about how healthy it is.
func _regen_health(delta: float) -> void:
	_hurt_hold = maxf(0.0, _hurt_hold - delta)
	if dead or _hurt_hold > 0.0 or health >= max_health:
		return
	health = minf(max_health, health + health_regen * delta)

## The guard only covers the front. `away` is the hit's push direction, i.e.
## attacker -> me, so the attacker sits opposite it.
func _guard_covers(knockback: Vector3) -> bool:
	var away := Vector3(knockback.x, 0.0, knockback.z)
	if away.length_squared() < 0.0001:
		return true # no direction to judge (environment) — don't punish it
	var facing := server_facing()
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return true
	return facing.normalized().dot(-away.normalized()) >= cos(deg_to_rad(block_arc_deg * 0.5))

## SERVER ONLY: all player damage funnels through here. The guard resolves in
## one of three ways — parried (guard raised on the beat: nothing gets through
## and the attacker is left open), blocked (chip damage, guard meter drains) or
## broken (meter empty: the hit lands clean and leaves you helpless).
func server_take_damage(amount: float, knockback: Vector3, attacker := 0,
		source: Node = null) -> float:
	if not multiplayer.is_server() or dead:
		return 0.0
	var result := Guard.HIT
	var dealt := amount
	var kb := knockback
	if blocking and _guard_covers(knockback):
		if _time - block_start_time <= parry_window:
			result = Guard.PARRIED
			dealt = 0.0
			kb = Vector3.ZERO
			stamina = minf(max_stamina, stamina + parry_stamina_refund)
			if source and source.has_method("server_stagger"):
				source.server_stagger(parry_stagger_time)
		else:
			var guard_cost := amount * block_stamina_per_damage
			if stamina >= guard_cost:
				result = Guard.BLOCKED
				stamina -= guard_cost
				dealt = amount * block_chip_mult
				kb = knockback * 0.3 # pushed back, but still standing
			else:
				result = Guard.BROKEN
				stamina = 0.0
				blocking = false
				server_stagger(guard_break_stagger_time)
	health -= dealt
	if dealt > 0.0:
		_hurt_hold = health_regen_delay # anything that got through stalls the heal
	Net.server_broadcast_player_damage(peer_id, health, result, kb, stamina, attacker)
	if health <= 0.0:
		_server_die(attacker)
	return dealt

## SERVER ONLY: unconditional kill (fell off the island, admin, ...).
func server_kill(attacker: int) -> void:
	if not multiplayer.is_server() or dead:
		return
	health = 0.0
	Net.server_broadcast_player_damage(peer_id, 0.0, Guard.HIT, Vector3.ZERO,
			stamina, attacker)
	_server_die(attacker)

## SERVER: leave this fighter wide open (parried, or their guard broke).
func server_stagger(duration: float) -> void:
	if not multiplayer.is_server() or dead:
		return
	Net.server_broadcast_player_stagger(peer_id, duration)

## Helpless for a beat — runs on every peer so the pose matches everywhere.
## Players are only ever staggered by a parry or a guard break: raw hits don't
## stun, so a flurry can't lock someone down in PvP.
func net_stagger(duration: float) -> void:
	if dead:
		return
	stagger_time = maxf(stagger_time, duration)
	attacking = false
	blocking = false
	holding_attack = false
	combo_index = 0
	lunge_left = 0.0
	cached_press_time = -10.0
	block_start_time = -10.0
	_srv_pending_time = -10.0
	_srv_combo_deadline = -10.0
	if sliding:
		if is_local:
			_end_slide()
		else:
			sliding = false
	body_visual.play_stagger(duration)
	_add_shake(0.4)

## A hit the guard ate thuds off the block; only one that got through sounds
## like flesh. A parry is the same thud pitched up — it IS a block, just a
## perfect one, and the gold flash and banner carry the rest of the read.
func _play_impact_sound(result: int) -> void:
	if result == Guard.BLOCKED or result == Guard.PARRIED:
		if _block_player:
			_block_player.pitch_scale = 1.25 if result == Guard.PARRIED else 1.0
			_block_player.play()
	elif _impact_player:
		_impact_player.play()

## Damage feedback on every peer; the owner also takes the knockback.
func net_apply_damage(new_health: float, result: int, knockback: Vector3,
		new_stamina: float, attacker := 0) -> void:
	health = new_health
	stamina = new_stamina # the guard meter is server-owned, no drift allowed
	_play_impact_sound(result)
	match result:
		Guard.PARRIED:
			body_visual.flash(Color(1.0, 0.95, 0.6), 0.25)
			if is_local:
				fx_parry_time = 0.55
			_add_shake(0.35)
		Guard.BLOCKED:
			body_visual.flash(Color(0.4, 0.7, 1.0), 0.2) # BlockedDamage event
			_add_shake(0.2)
			if is_local and not dead:
				velocity += knockback * 0.5 # already softened server-side
		Guard.BROKEN:
			body_visual.flash(Color(1.0, 0.55, 0.15), 0.3)
			body_visual.hit_react(0.35)
			if is_local:
				fx_break_time = 0.9
			_add_shake(0.6)
			if _grunt_player and health > 0.0:
				_grunt_player.play()
			if is_local and not dead:
				velocity += knockback * 0.5
		_:
			body_visual.flash(Color(1.0, 0.3, 0.3), 0.15)
			body_visual.hit_react(0.3)
			body_visual.hitstop(0.06)
			_add_shake(0.5)
			if _grunt_player and health > 0.0:
				_grunt_player.play() # lethal hits voice the death sound instead
			if is_local and not dead:
				velocity += knockback * 0.5
	if attacker != 0 and attacker == multiplayer.get_unique_id():
		local_hit_feedback(get_tree(), result)

## Impact feedback for whoever threw the punch, wherever their pawn is.
static func local_hit_feedback(tree: SceneTree, result: int) -> void:
	var puncher := tree.get_first_node_in_group("local_player")
	if puncher is Player:
		(puncher as Player).on_hit_landed(result)

## One of our punches connected: freeze the swing for a beat and mark it.
func on_hit_landed(result: int) -> void:
	if not is_local or result == Guard.PARRIED:
		return # a parried swing gets a stagger, not a hit confirm
	var solid: bool = result == Guard.HIT or result == Guard.BROKEN
	fx_hitmarker_time = 0.18
	body_visual.hitstop(0.07 if solid else 0.05)
	_add_shake(0.28 if solid else 0.16)

func _server_die(attacker: int) -> void:
	# records the death/kill on the server scoreboard AND broadcasts the
	# death (which also runs net_die on this server-side pawn)
	Net.server_record_player_death(peer_id, attacker)
	get_tree().create_timer(death_restart_delay + 1.5).timeout.connect(func() -> void:
		if is_instance_valid(self) and dead:
			Net.server_respawn_player(peer_id))

## Death presentation + state, runs on every peer.
func net_die() -> void:
	if dead:
		return
	dead = true
	attacking = false
	sliding = false
	diving = false
	pending_landing_slide = false
	blocking = false
	holding_attack = false
	stagger_time = 0.0
	lunge_left = 0.0
	lock_target = null
	collision_layer = 0
	if is_local:
		_restore_capsule() # dying mid-slide must not leave the short capsule
	if _death_player:
		_death_player.play()
	body_visual.play_death()

func _restore_capsule() -> void:
	var shape: CapsuleShape3D = col_shape.shape
	shape.height = capsule_half_height * 2.0
	col_shape.position.y = capsule_half_height

## SERVER: drop this pawn somewhere else at once, with no travel in between.
## `net_pos` moves with it or the owner's next honest report — sent from the
## far side of the island — reads as a speedhack and gets snapped back; other
## peers' puppets snap by themselves, since `_puppet_tick` stops interpolating
## past 6 m. Any slide in progress is cancelled, so nobody arrives skidding.
func net_teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	net_pos = pos
	if sliding or diving:
		_end_slide()
	pending_landing_slide = false

## Respawn, runs on every peer (position is server-chosen).
func net_respawn(pos: Vector3) -> void:
	dead = false
	health = max_health
	stamina = max_stamina
	attacking = false
	attack_did_hit = false
	hit_actors = {}
	sliding = false
	diving = false
	pending_landing_slide = false
	slide_cooldown_left = 0.0
	stagger_time = 0.0
	lunge_left = 0.0
	blocking = false
	holding_attack = false
	block_start_time = -10.0
	cached_press_time = -10.0
	_stam_hold = 0.0
	_hurt_hold = 0.0
	if is_local:
		_restore_capsule()
		_shake = 0.0
		fx_hitmarker_time = 0.0
		fx_parry_time = 0.0
		fx_break_time = 0.0
		if camera:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
	_srv_combo_deadline = -10.0
	net_pos = pos
	net_anim = "idle"
	global_position = pos
	velocity = Vector3.ZERO
	if body_visual.has_method("revive"):
		body_visual.revive()
	if is_local:
		collision_layer = 1

# ---------------- animation ----------------

## Directional locomotion: squared up, the legs pick a sidestep or a backpedal
## from where we are actually going relative to the guard — and keep the fists
## up while blocking. Free-running just plays the run cycle.
func _locomotion_anim(h_vel: Vector3) -> String:
	if not _in_stance():
		return "run"
	var fwd := _body_forward()
	fwd.y = 0
	if fwd.length_squared() < 0.001:
		return "run"
	fwd = fwd.normalized()
	var ahead := h_vel.dot(fwd)
	var to_left := h_vel.dot(Vector3.UP.cross(fwd))
	var lateral := absf(to_left) > absf(ahead)
	if blocking:
		if lateral:
			return "block_l" if to_left > 0.0 else "block_r"
		return "block_back" if ahead < 0.0 else "block_fwd"
	if lateral:
		return "strafe_l" if to_left > 0.0 else "strafe_r"
	return "walk_back" if ahead < 0.0 else "run"

func _animate(delta: float) -> void:
	var h_vel := Vector3(velocity.x, 0, velocity.z)
	var h_speed := h_vel.length()
	var ratio := h_speed / walk_speed
	var anim := "idle"
	var t := 0.0
	if attacking:
		anim = "attack_heavy" if attack_is_heavy else "attack_light_%d" % combo_index
		t = attack_timer / attack_duration
	elif sliding:
		anim = "slide"
	elif diving:
		anim = "dive"
	elif not is_on_floor():
		anim = "air"
	elif stagger_time > 0.0:
		anim = "idle" # the visual holds its own recoil pose over this
	elif h_speed > 0.3:
		anim = _locomotion_anim(h_vel)
	elif blocking:
		anim = "block"
	last_anim = anim
	last_anim_t = t
	last_ratio = ratio
	body_visual.tick(delta, anim, t, ratio)
