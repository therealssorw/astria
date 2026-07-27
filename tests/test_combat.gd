extends Node3D
## Headless integration test for melee combat. Run:
##   godot --headless --path . res://tests/test_combat.tscn
## Drives two pawns and a bandit offline (OfflineMultiplayerPeer makes this
## peer the server) and checks the four systems that have to hold together:
## the clip library, the guard (chip / parry / guard break), combo chaining
## and the squared-up stance. Prints COMBATTEST RESULT=PASS/FAIL and exits
## with the matching code.

const PLAYER := preload("res://scenes/player.tscn")
const ENEMY := preload("res://scenes/enemy.tscn")

var fails := 0

func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	call_deferred("_run")

# ---------------- helpers ----------------

func ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		print("  PASS  %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL  %s %s" % [label, detail])

func about(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol

func _spawn_player(id: int, pos: Vector3) -> Player:
	var p: Player = PLAYER.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.username = "T%d" % id
	$Players.add_child(p)
	p.global_position = pos
	p.net_pos = pos
	p.set_physics_process(false) # driven by hand, for determinism
	return p

func _spawn_enemy() -> Enemy:
	var e: Enemy = ENEMY.instantiate()
	e.name = "TestBandit"
	$Enemies.add_child(e)
	e.global_position = Vector3.ZERO
	e.set_physics_process(false)
	return e

func _face(p: Player, toward: Vector3) -> void:
	var d := toward - p.global_position
	d.y = 0
	p.body_visual.rotation.y = atan2(-d.x, -d.z) + PI

func _hit(attacker: Player, victim: Player, heavy := false, section := 0) -> void:
	attacker.attack_is_heavy = heavy
	attacker.combo_index = section
	attacker.hit_actors = {}
	var dir := victim.global_position - attacker.global_position
	dir.y = 0
	attacker.attack_face_dir = dir.normalized()
	attacker._do_attack_trace()

func _silence(n: Node) -> void:
	for key in ["_block_player", "_impact_player", "_grunt_player"]:
		var sp: AudioStreamPlayer3D = n.get(key)
		if sp:
			sp.stop()

func _sounds(n: Node) -> String:
	var out := []
	for key in ["_block_player", "_impact_player", "_grunt_player"]:
		var sp: AudioStreamPlayer3D = n.get(key)
		if sp and sp.playing:
			out.append(key.trim_prefix("_").trim_suffix("_player"))
	return "[%s]" % ", ".join(out) if out.size() > 0 else "[silent]"

# ---------------- run ----------------

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("=== clips ===")
	await _test_clips()
	print("=== guard ===")
	await _test_guard()
	print("=== regen ===")
	await _test_regen()
	print("=== combo ===")
	await _test_combo()
	print("=== remote ===")
	await _test_remote()
	print("=== stance ===")
	await _test_stance()
	print("=== enemy ===")
	await _test_enemy()
	print("=== levels ===")
	await _test_levels()
	print("COMBATTEST RESULT=%s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _test_clips() -> void:
	var p := _spawn_player(9, Vector3.ZERO)
	var v: HumanoidVisual = p.body_visual
	var lib: AnimationLibrary = v.anim_player.get_animation_library("lib")
	for key in ["block_fwd", "block_back", "block_l", "block_r"]:
		var a: Animation = lib.get_animation(key)
		ok(a != null and a.length > 0.1, "guard-move clip " + key,
				"len=%.2f" % (a.length if a else -1.0))
	# every anim string a pawn can report has to map to a real clip
	for anim in PlayerNetState.ANIM_WHITELIST:
		v.tick(0.016, anim, 0.0, 0.8)
		ok(v.anim_player.current_animation != "", "tick(%s)" % anim,
				"-> %s @%.2f" % [v.anim_player.current_animation, v.anim_player.speed_scale])
	var light: Dictionary = v.get_attack_info(false, 0)
	var light2: Dictionary = v.get_attack_info(false, 2)
	# Every Mixamo punch runs long (0.67 / 1.31 / 1.57s at montage rate), so it
	# is LIGHT_MAX_DUR in humanoid_visual.gd — not the clip — that decides how
	# fast a swing is: [0.52, 0.6, 0.74] today, giving a 0.52s jab and a 0.78s
	# chain. These bounds sit a little above that so a small retune doesn't
	# fail the run; what they guard is a swing going sluggish again (the
	# pre-rework caps of [0.8, 1.15, 1.35] gave 0.80s and 1.33s).
	ok(light.duration < 0.6, "light punch is fast", "dur=%.3f" % light.duration)
	ok(light.hit < light.combo and light.combo < light.duration,
			"chain point sits between contact and recovery")
	ok(light.combo + light2.combo < 0.85, "3-punch chain starts inside 0.85s",
			"%.3f" % (light.combo + light2.combo))
	v.hitstop(0.05)
	v.tick(0.016, "idle")
	ok(v.anim_player.speed_scale < 0.2, "hitstop freezes the clip")
	v.tick(0.2, "idle")
	ok(v.anim_player.speed_scale == 1.0, "hitstop releases")
	v.tick(0.016, "strafe_l", 0.0, 0.85)
	var fast := v.anim_player.speed_scale
	v.tick(0.016, "strafe_l", 0.0, 0.25)
	ok(fast > v.anim_player.speed_scale, "stride rate tracks ground speed",
			"%.2f vs %.2f" % [fast, v.anim_player.speed_scale])
	p.free()
	await get_tree().process_frame

func _test_guard() -> void:
	var a := _spawn_player(1, Vector3.ZERO)
	var b := _spawn_player(2, Vector3(0, 0, 1.2))
	await get_tree().process_frame

	# guard facing the attacker: chip only, and it thuds off the block
	_face(b, a.global_position)
	b.health = 100.0
	b.stamina = 100.0
	b.blocking = true
	b.block_start_time = -100.0 # up a while: no parry
	b._time = 0.0
	_silence(b)
	_hit(a, b)
	ok(about(b.health, 100.0 - a.light_damage * b.block_chip_mult, 0.01),
			"front block chips only", "hp=%.2f" % b.health)
	ok(b.stamina < 100.0, "blocking drains the guard meter", "stam=%.1f" % b.stamina)
	ok(b._block_player.playing and not b._grunt_player.playing
			and not b._impact_player.playing,
			"blocked hit: block thud, no grunt", _sounds(b))

	# same guard, hit from behind: nothing is blocked
	b.health = 100.0
	b.stamina = 100.0
	_face(b, a.global_position + Vector3(0, 0, 10.0))
	_silence(b)
	_hit(a, b)
	ok(about(b.health, 90.0, 0.01), "guard doesn't cover the back", "hp=%.2f" % b.health)
	ok(b._impact_player.playing and b._grunt_player.playing,
			"clean hit: flesh impact + grunt", _sounds(b))

	# parry: guard raised on the beat
	b.health = 100.0
	b.stamina = 50.0
	b.blocking = true
	b._time = 10.0
	b.block_start_time = 10.0 - b.parry_window * 0.5
	_face(b, a.global_position)
	a.stagger_time = 0.0
	a.attacking = true
	_silence(b)
	_hit(a, b)
	ok(b.health == 100.0, "parry takes zero damage", "hp=%.2f" % b.health)
	ok(b.stamina > 50.0, "parry refunds stamina", "stam=%.1f" % b.stamina)
	ok(a.stagger_time > 0.0, "parry staggers the attacker", "%.2fs" % a.stagger_time)
	ok(not a.attacking, "the parried swing is cancelled")
	ok(b._block_player.playing and b._block_player.pitch_scale > 1.1,
			"parry: block thud pitched up", "pitch=%.2f" % b._block_player.pitch_scale)

	# guard break: meter too low to absorb it
	a.stagger_time = 0.0
	b.health = 100.0
	b.stamina = 2.0
	b.blocking = true
	b.block_start_time = -100.0
	b._time = 20.0
	b.stagger_time = 0.0
	_silence(b)
	_hit(a, b)
	ok(about(b.health, 90.0, 0.01), "broken guard eats the full hit", "hp=%.2f" % b.health)
	ok(b.stagger_time > 0.0, "guard break staggers the defender", "%.2fs" % b.stagger_time)
	ok(not b.blocking, "broken guard drops")
	ok(b._impact_player.playing and b._grunt_player.playing,
			"guard break sounds like a hit that landed", _sounds(b))

	# staggered fighters can't swing
	b.stamina = 100.0
	b._try_start_attack(false)
	ok(not b.attacking, "no attacking while staggered")

	a.free()
	b.free()
	await get_tree().process_frame

## Health comes back by itself after a quiet spell. It is the SERVER's copy
## that heals (_regen_health is only ever ticked behind an is_server check),
## so this drives it by hand the way the server's physics frame would.
func _test_regen() -> void:
	var a := _spawn_player(1, Vector3.ZERO)
	var b := _spawn_player(2, Vector3(0, 0, 1.2))
	await get_tree().process_frame
	var dt := 1.0 / 60.0

	# a hit that lands stalls the heal for the full delay
	b.health = 50.0
	b.stamina = 100.0
	b.blocking = false
	b._hurt_hold = 0.0
	_face(b, a.global_position)
	_silence(b)
	_hit(a, b)
	ok(about(b.health, 40.0, 0.01), "the hit lands", "hp=%.2f" % b.health)
	ok(about(b._hurt_hold, b.health_regen_delay, 0.001), "a hit stalls the heal",
			"%.2fs" % b._hurt_hold)

	# nothing comes back until the delay is up, then it climbs at the rate
	var hurt: float = b.health
	var stalled := int(b.health_regen_delay / dt) - 2 # just short of the delay
	for i in stalled:
		b._regen_health(dt)
	ok(b.health == hurt, "nothing comes back inside the %.0fs" % b.health_regen_delay,
			"hp=%.2f" % b.health)
	var healing := 120
	for i in healing:
		b._regen_health(dt)
	var healed_for: float = float(stalled + healing) * dt - b.health_regen_delay
	ok(about(b.health, hurt + b.health_regen * healed_for, 0.2),
			"then it climbs at the regen rate",
			"hp=%.2f after %.2fs of %.1f/s" % [b.health, healed_for, b.health_regen])

	# it stops at full, and a corpse doesn't heal at all
	b.health = b.max_health - 1.0
	b._hurt_hold = 0.0
	for i in 120:
		b._regen_health(dt)
	ok(b.health == b.max_health, "the heal stops at full", "hp=%.2f" % b.health)
	b.dead = true
	b.health = 10.0
	b._hurt_hold = 0.0
	for i in 60:
		b._regen_health(dt)
	ok(b.health == 10.0, "a corpse doesn't heal", "hp=%.2f" % b.health)
	b.dead = false

	# a parry costs no health, so it must not stall the heal either
	b.health = 50.0
	b.stamina = 50.0
	b.blocking = true
	b._time = 10.0
	b.block_start_time = 10.0 - b.parry_window * 0.5
	b._hurt_hold = 0.0
	a.stagger_time = 0.0
	_silence(b)
	_hit(a, b)
	ok(b.health == 50.0 and b._hurt_hold == 0.0,
			"a clean parry doesn't stall the heal",
			"hp=%.2f hold=%.2fs" % [b.health, b._hurt_hold])

	# chip damage is still damage
	b.blocking = true
	b.block_start_time = -100.0
	b.stamina = 100.0
	b._hurt_hold = 0.0
	_silence(b)
	_hit(a, b)
	ok(b.health < 50.0 and about(b._hurt_hold, b.health_regen_delay, 0.001),
			"chip through the guard stalls it too",
			"hp=%.2f hold=%.2fs" % [b.health, b._hurt_hold])

	a.free()
	b.free()
	await get_tree().process_frame

func _test_combo() -> void:
	var a := _spawn_player(1, Vector3.ZERO)
	await get_tree().process_frame
	a.stamina = a.max_stamina
	a._time = 100.0
	a._start_swing(false, 0)
	var combo_at: float = a.attack_combo_time
	var duration: float = a.attack_duration
	var t := 0.0
	var chained_at := -1.0
	for i in 200:
		t += 1.0 / 120.0
		a._time += 1.0 / 120.0
		a.cached_press_time = a._time - 0.05 # hold a queued press
		a._tick_attack(1.0 / 120.0)
		if a.combo_index == 1:
			chained_at = t
			break
	ok(chained_at > 0.0, "a queued press chains the combo", "at %.3fs" % chained_at)
	ok(about(chained_at, combo_at, 0.03),
			"chain fires at the combo point, not the clip end",
			"%.3f vs combo %.3f / duration %.3f" % [chained_at, combo_at, duration])

	# one tap must throw exactly one punch
	a.attacking = false
	a.combo_index = 0
	a.stamina = a.max_stamina
	a._start_swing(false, 0)
	for i in 200:
		a._time += 1.0 / 120.0
		a._tick_attack(1.0 / 120.0)
	ok(a.combo_index == 0 and not a.attacking, "a single tap throws one punch",
			"combo=%d attacking=%s" % [a.combo_index, a.attacking])
	a.free()
	await get_tree().process_frame

## The server's copy of somebody ELSE's pawn — the half of combat a listen server
## never runs, because the host's own pawn simulates itself. Everything here was
## invisible in the editor and only wrong for a player connected over a wire.
##
## `_spawn_player` with an id that is not this peer's makes `is_local` false, so
## these are exactly the pawns `_server_sim_tick` drives.
func _test_remote() -> void:
	var p := _spawn_player(7, Vector3(0, 0, 60.0)) # away from anything punchable
	await get_tree().process_frame
	p._time = 100.0
	p.stamina = p.max_stamina

	# --- which punch of the chain the server runs ---
	# a jab, seen through to the end, then a FRESH press a beat later: the owner
	# starts its chain over, and so must the server. It used to read the press as
	# the next punch of the old chain — different clip, different timing, and one
	# more of them away from the ender's damage.
	p.server_handle_attack_request(false, NodePath(""), 0.0, 0)
	ok(p.attacking and p.combo_index == 0, "a first punch is punch one",
			"combo=%d" % p.combo_index)
	var swing: float = p.attack_duration
	_srv_run(p, swing + 0.05)
	ok(not p.attacking, "the swing finishes", "%.2fs" % swing)
	_srv_run(p, 0.1) # well inside combo_input_cache_tolerance
	p.server_handle_attack_request(false, NodePath(""), 0.0, 0)
	ok(p.combo_index == 0, "a fresh press restarts the chain, not continues it",
			"combo=%d" % p.combo_index)

	# ...and a press the owner really did chain still chains
	_srv_run(p, p.attack_combo_time + 0.01)
	p.server_handle_attack_request(false, NodePath(""), 0.0, 1)
	_srv_run(p, 1.0 / 60.0)
	ok(p.combo_index == 1, "a chained press runs the next punch",
			"combo=%d" % p.combo_index)

	# a claim the server's own chain doesn't back is worth nothing: the ender
	# hits for combo_finisher_mult, so it has to be earned twice over
	_srv_run(p, 2.0)
	p.stamina = p.max_stamina
	p.server_handle_attack_request(false, NodePath(""), 0.0, 2)
	ok(p.combo_index == 0, "an unearned ender claim is refused",
			"combo=%d" % p.combo_index)
	_srv_run(p, p.attack_duration + 2.0)

	# --- the parry window re-arms on the server too ---
	# The guard drops for your own punch and comes back up after it, and a guard
	# that comes back up parries. No state report carries that edge — the button
	# never moved — so the server has to notice it the same way the owner does.
	p.stamina = p.max_stamina
	p.net_blocking = true
	_srv_run(p, 1.0 / 60.0)
	ok(p.blocking, "the reported button raises the guard")
	_srv_run(p, p.parry_window * 3.0)
	ok(p._time - p.block_start_time > p.parry_window,
			"a guard held a while is past its parry window",
			"%.2fs up" % (p._time - p.block_start_time))
	p.server_handle_attack_request(false, NodePath(""), 0.0, 0)
	_srv_run(p, 1.0 / 60.0)
	ok(not p.blocking, "punching drops the guard")
	_srv_run(p, p.attack_duration + 0.05)
	ok(p.blocking, "the guard comes back up after the swing")
	ok(p._time - p.block_start_time <= p.parry_window,
			"...and it can parry again",
			"%.3fs up" % (p._time - p.block_start_time))
	p.free()
	await get_tree().process_frame

## One server physics frame for a pawn it does not own, as _physics_process
## would run it: the clock, the stagger countdown, then the sim.
func _srv_run(p: Player, seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(ceilf(seconds / dt)):
		p._time += dt
		p.stagger_time = maxf(0.0, p.stagger_time - dt)
		p._server_sim_tick(dt)

func _test_stance() -> void:
	var a := _spawn_player(1, Vector3.ZERO)
	var b := _spawn_player(2, Vector3(0, 0, 4.0))
	await get_tree().process_frame
	a.lock_target = b
	ok(a._in_stance(), "a lock-on inside range squares us up")
	b.global_position = Vector3(0, 0, a.stance_range + 5.0)
	ok(not a._in_stance(), "a distant lock still free-runs")
	b.global_position = Vector3(0, 0, 4.0)

	_face(a, b.global_position)
	# the pose table is pure now (PlayerAnim), so it is asked directly with the
	# same facing and stance the pawn would hand it
	var step := func(v: Vector3, guard: bool) -> String:
		return PlayerAnim.locomotion(v, a._body_forward(), a._in_stance(), guard)
	ok(step.call(Vector3(0, 0, 3.0), false) == "run", "toward the target -> run")
	ok(step.call(Vector3(0, 0, -3.0), false) == "walk_back", "away -> backpedal")
	ok(step.call(Vector3(3.0, 0, 0.2), false) == "strafe_l"
			and step.call(Vector3(-3.0, 0, 0.2), false) == "strafe_r",
			"sideways -> matching strafe")
	ok(step.call(Vector3(0, 0, -3.0), true) == "block_back"
			and step.call(Vector3(3.0, 0, 0), true) == "block_l",
			"guarding keeps the fists up while moving")

	var fwd: float = a._directional_mult(Vector3(0, 0, 1))
	var side: float = a._directional_mult(Vector3(1, 0, 0))
	var back: float = a._directional_mult(Vector3(0, 0, -1))
	ok(fwd > side and side > back, "advance > sidestep > backpedal",
			"%.2f / %.2f / %.2f" % [fwd, side, back])

	# a swing at range steps in; the step has to survive the movement code.
	# Integrate velocity ourselves: move_and_slide() uses the IDLE delta when
	# driven from outside a physics frame, so positions here aren't the 1/60
	# step the real game runs at.
	a.velocity = Vector3.ZERO
	a.stamina = a.max_stamina
	a._start_swing(false, 0)
	ok(a.lunge_left > 0.0, "an out-of-reach swing lunges")
	var closed := 0.0
	for i in 30:
		a._move(1.0 / 60.0)
		closed += Vector2(a.velocity.x, a.velocity.z).length() / 60.0
	ok(closed > 0.35 and closed < 1.5, "the lunge closes real ground", "%.2f m" % closed)
	ok(a.lunge_left == 0.0 and Vector2(a.velocity.x, a.velocity.z).length() < 0.5,
			"the step settles instead of sliding on")

	a.lunge_left = 0.0
	b.global_position = a.global_position + Vector3(0, 0, 0.9)
	a.attacking = false
	a.stamina = a.max_stamina
	a._start_swing(false, 1)
	ok(a.lunge_left == 0.0, "point blank doesn't lunge")
	a.free()
	b.free()
	await get_tree().process_frame

func _test_enemy() -> void:
	var e := _spawn_enemy()
	await get_tree().process_frame
	e.state = Enemy.CombatState.BLOCK
	e.health = 100.0
	e.body_visual.rotation.y = 0.0 # facing +Z: a front attacker pushes it -Z
	_silence(e)
	e.take_damage(20.0, Vector3(0, 1.5, -3.0), 0, null)
	ok(about(e.health, 100.0 - 20.0 * e.block_damage_mult, 0.01),
			"bandit front block chips", "hp=%.2f" % e.health)
	ok(e._block_player.playing and not e._grunt_player.playing,
			"bandit doesn't grunt through a block", _sounds(e))

	e.health = 100.0
	_silence(e)
	e.take_damage(20.0, Vector3(0, 1.5, 3.0), 0, null) # from behind
	ok(about(e.health, 80.0, 0.01), "bandit guard doesn't cover the back",
			"hp=%.2f" % e.health)
	ok(e._grunt_player.playing, "bandit still grunts on a clean hit", _sounds(e))

	e.state = Enemy.CombatState.RETREAT
	e.stagger_left = 0.0
	e.health = 100.0
	e.take_damage(10.0, Vector3(0, 2.5, 4.5), 0, null)
	ok(e.stagger_left <= 0.0, "a jab doesn't stagger")
	e.take_damage(25.0, Vector3(0, 4.0, 7.5), 0, null)
	ok(e.stagger_left > 0.0, "a heavy rocks it back", "%.2fs" % e.stagger_left)
	var before := e.health
	e.take_damage(10.0, Vector3(0, 2.5, 4.5), 0, null)
	ok(before - e.health > 10.0, "hits land harder in the punish window",
			"%.1f dmg" % (before - e.health))
	e.free()
	await get_tree().process_frame

## Weapons have levels, enemies have levels, and exactly one place multiplies
## the two together. The number that must never drift is the FIRST one here:
## bare-handed against an ordinary bandit is the game as it was tuned, and
## everything else in this section is measured against it.
func _test_levels() -> void:
	for id: String in ItemDb.ITEMS:
		ok(ItemDb.ITEMS[id].has("level"), "%s declares a level" % id,
				ItemDb.level_label(id))
	ok(ItemDb.FIST_LEVEL == 0 and ItemDb.level_of("") == ItemDb.FIST_LEVEL,
			"an empty hand is level 0")
	ok(ItemDb.level_of("no_such_item") == ItemDb.FIST_LEVEL,
			"an unknown item is worth no more than punching")
	ok(ItemDb.level_of("wooden_sword") == 1 and ItemDb.level_of("copper_sword") == 2
			and ItemDb.level_of("iron_sword") == 3, "the swords rank 1 / 2 / 3")
	ok(about(CombatLevels.damage_mult(ItemDb.FIST_LEVEL,
			CombatLevels.BASE_ENEMY_LEVEL), 1.0, 0.0001),
			"fists against an ordinary enemy scale nothing at all")
	ok(CombatLevels.damage_mult(1, 1) > 1.0
			and CombatLevels.damage_mult(2, 1) > CombatLevels.damage_mult(1, 1)
			and CombatLevels.damage_mult(3, 1) > CombatLevels.damage_mult(2, 1),
			"each level of weapon hits harder than the last")
	ok(CombatLevels.damage_mult(3, 3) < CombatLevels.damage_mult(3, 1),
			"a higher-level enemy shrugs more of the same blade off")
	ok(CombatLevels.level_of_target(null) == CombatLevels.BASE_ENEMY_LEVEL,
			"anything with no level of its own is an ordinary target")

	# ...and now through the real swing, with the level read off the SERVER's
	# own hotbar — the only copy of it a swing is ever allowed to believe.
	var a := _spawn_player(1, Vector3.ZERO)
	var e := _spawn_enemy()
	await get_tree().process_frame
	e.global_position = Vector3(0, 0, 1.0)
	ok(e.level == 0, "a bandit ships one rung under the baseline",
			"level=%d" % e.level)
	# ...and everything below is measured against the BASELINE enemy, which is
	# the line the exported numbers are written for. A bandit is softer than
	# that by design, so measuring the ladder on one would be measuring two
	# changes at once.
	e.level = CombatLevels.BASE_ENEMY_LEVEL
	ok(CombatLevels.level_of_target(a) == CombatLevels.BASE_ENEMY_LEVEL,
			"a player defends as an ordinary target, whatever they carry")

	var had_entry: bool = Net.players.has(1)
	var saved: Variant = Net.players.get(1)
	var fists := _swing_damage(a, e)
	ok(about(fists, a.light_damage, 0.01), "bare-handed deals the exported jab",
			"%.2f vs %.2f" % [fists, a.light_damage])
	var by_level := {}
	for id in ["wooden_sword", "copper_sword", "iron_sword"]:
		Net.players[1] = {"hotbar": [id], "hot_slot": 0}
		ok(Net.held_of(1) == id, "the server sees %s in hand" % id)
		by_level[id] = _swing_damage(a, e)
	ok(by_level["wooden_sword"] > fists
			and by_level["copper_sword"] > by_level["wooden_sword"]
			and by_level["iron_sword"] > by_level["copper_sword"],
			"a bandit dies faster the better the blade",
			"fists %.1f -> %.1f -> %.1f -> %.1f" % [fists, by_level["wooden_sword"],
					by_level["copper_sword"], by_level["iron_sword"]])
	ok(about(by_level["iron_sword"], a.light_damage
			* CombatLevels.damage_mult(3, CombatLevels.BASE_ENEMY_LEVEL), 0.01),
			"the swing uses the shared curve, not one of its own",
			"%.2f" % by_level["iron_sword"])

	# a tougher enemy takes the same blade better, without any stat of its own
	# being touched. Both halves are measured against the SAME level 3 enemy:
	# the weapon ladder is deliberately shallower than the enemy one, so an iron
	# sword is not asked to out-damage a punch thrown at something three levels
	# weaker — only to beat bare hands against the thing in front of it.
	e.level = 3
	var vs_tough := _swing_damage(a, e)
	Net.players[1] = {"hotbar": [""], "hot_slot": 0}
	var fists_vs_tough := _swing_damage(a, e)
	ok(vs_tough < by_level["iron_sword"] and vs_tough > fists_vs_tough,
			"a level 3 enemy eats some of the level 3 blade",
			"%.2f, against %.2f bare-handed" % [vs_tough, fists_vs_tough])
	Net.players[1] = {"hotbar": ["iron_sword"], "hot_slot": 0}
	e.level = CombatLevels.BASE_ENEMY_LEVEL

	# damage only: a jab with the best weapon in the game is still a jab, so
	# what rocks an enemy back never changes with what you are carrying
	e.stagger_left = 0.0
	_swing_damage(a, e)
	ok(e.stagger_left <= 0.0, "a levelled jab still doesn't stagger")

	if had_entry:
		Net.players[1] = saved
	else:
		Net.players.erase(1)
	a.free()
	e.free()
	await get_tree().process_frame

## One light punch at a bandit stood in front of the player, through the real
## server trace — returns the health it actually cost.
func _swing_damage(a: Player, e: Enemy) -> float:
	e.health = 1000.0
	e.state = Enemy.CombatState.RETREAT
	e.stagger_left = 0.0
	a.attack_is_heavy = false
	a.combo_index = 0
	a.hit_actors = {}
	var dir := e.global_position - a.global_position
	dir.y = 0
	a.attack_face_dir = dir.normalized()
	_silence(e)
	a._do_attack_trace()
	return 1000.0 - e.health
