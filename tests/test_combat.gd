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
	print("=== combo ===")
	await _test_combo()
	print("=== stance ===")
	await _test_stance()
	print("=== enemy ===")
	await _test_enemy()
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
	for anim in Player.ANIM_WHITELIST:
		v.tick(0.016, anim, 0.0, 0.8)
		ok(v.anim_player.current_animation != "", "tick(%s)" % anim,
				"-> %s @%.2f" % [v.anim_player.current_animation, v.anim_player.speed_scale])
	var light: Dictionary = v.get_attack_info(false, 0)
	var light2: Dictionary = v.get_attack_info(false, 2)
	ok(light.duration < 0.5, "light punch is fast", "dur=%.3f" % light.duration)
	ok(light.hit < light.combo and light.combo < light.duration,
			"chain point sits between contact and recovery")
	ok(light.combo + light2.combo < 0.75, "3-punch chain starts inside 0.75s",
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
	ok(a._locomotion_anim(Vector3(0, 0, 3.0)) == "run", "toward the target -> run")
	ok(a._locomotion_anim(Vector3(0, 0, -3.0)) == "walk_back", "away -> backpedal")
	ok(a._locomotion_anim(Vector3(3.0, 0, 0.2)) == "strafe_l"
			and a._locomotion_anim(Vector3(-3.0, 0, 0.2)) == "strafe_r",
			"sideways -> matching strafe")
	a.blocking = true
	ok(a._locomotion_anim(Vector3(0, 0, -3.0)) == "block_back"
			and a._locomotion_anim(Vector3(3.0, 0, 0)) == "block_l",
			"guarding keeps the fists up while moving")
	a.blocking = false

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
