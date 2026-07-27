extends Node
## BOSSTEST: the juggernaut. Run:
##   godot --headless --path . res://tests/test_boss.tscn
## Prints BOSSTEST RESULT=PASS/FAIL and exits with the matching code.
##
## Two halves, and the split is deliberate. The first needs no world at all — the
## move table, the levels and the catalogue are data, and a test that has to host
## a server to read a dictionary is a slow test that fails for unrelated reasons.
## The second hosts a REAL listen server and fights it: poise, the two earned
## openings, the phase flip, the moves landing on the server's own copy of a
## pawn, the club really lying on the floor afterwards, and that the spawner in
## the catacombs is standing over a floor at all.
##
## What it deliberately does NOT check is how any of it LOOKS — the ring on the
## ground, the bar across the top, the armour coming off. Every one of those is
## invisible to an assertion and obvious in a screenshot, which is what
## tests/preview_boss.tscn is for.

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "BossTestRunner"
	get_tree().root.add_child.call_deferred(runner)


class Runner:
	extends Node

	const TEST_HOST := preload("res://tests/helpers/test_host.gd")
	const BOSS_SCENE := preload("res://scenes/boss.tscn")

	var failures: Array[String] = []
	var checks := 0

	func _ready() -> void:
		_run()

	func _run() -> void:
		await get_tree().process_frame
		_check_move_table()
		_check_club()
		await _check_fight()
		_report()

	# ---------------- the table (no world needed) ----------------

	func _check_move_table() -> void:
		for id: String in Boss.MOVES:
			var m: Dictionary = Boss.MOVES[id]
			for key: String in ["phase", "windup", "active", "recovery", "cooldown",
					"damage", "range", "reach", "shake", "telegraph"]:
				_ok(m.has(key), "move '%s' declares '%s'" % [id, key])
			# A move with no wind-up is one nobody can answer, and one with no
			# recovery is one nobody can punish — the two halves of a fair boss.
			_ok(float(m["windup"]) >= 0.6, "move '%s' telegraphs for %.2fs" % [id, m["windup"]])
			_ok(float(m["recovery"]) >= 1.0, "move '%s' leaves %.2fs of punish" % [id, m["recovery"]])
			var t: Dictionary = m["telegraph"]
			_ok(t.has("color") and t.has("scale") and t.has("ring"),
					"move '%s' says how it is drawn" % id)
		_ok(int(Boss.MOVES["slam"]["phase"]) == 1, "the slam is phase one")
		_ok(int(Boss.MOVES["charge"]["phase"]) == 2, "the charge is phase two")
		# every move looks different, or the telegraph is only a timer
		var seen := {}
		for id: String in Boss.MOVES:
			var c: Color = Boss.MOVES[id]["telegraph"]["color"]
			_ok(not seen.has(str(c)), "move '%s' has a colour of its own" % id)
			seen[str(c)] = true
		# and the shake falls off with distance rather than shaking the island
		var reach := float(Boss.MOVES["slam"]["reach"])
		var near := Boss.move_shake("slam", 0.0)
		var far := Boss.move_shake("slam", reach * 1.5)
		_ok(near > far and far > 0.0,
				"slam shake %.2f at the centre, %.2f at the edge" % [near, far])
		_ok(is_equal_approx(Boss.move_shake("slam", reach * 4.0), 0.0),
				"nothing felt from across the room")
		_ok(is_equal_approx(Boss.move_shake("nonsense", 0.0), 0.0),
				"an unknown move shakes nothing")

	func _check_club() -> void:
		_ok(ItemDb.has("juggernaut_club"), "the club is in the catalogue")
		_ok(ItemDb.level_of("juggernaut_club") > ItemDb.level_of("iron_sword"),
				"club (Lv %d) out-classes the iron sword (Lv %d)" % [
						ItemDb.level_of("juggernaut_club"), ItemDb.level_of("iron_sword")])
		_ok(ItemDb.is_holdable("juggernaut_club"), "the club can be held")
		_ok(ItemDb.art_source("juggernaut_club") != "", "the club has art to photograph")
		# it is loot, not stock: no shop may sell the thing you had to kill for
		for shop_id: String in ShopData.SHOPS:
			var stock: Array = ShopData.SHOPS[shop_id].get("sells", [])
			_ok(not stock.has("juggernaut_club"), "'%s' does not stock the club" % shop_id)

	# ---------------- the fight (real listen server) ----------------

	func _check_fight() -> void:
		var host := TEST_HOST.new()
		var pawn: Node3D = await host.boot(get_tree(), "boss")
		if pawn == null:
			failures.append(host.error)
			return
		var world := get_tree().current_scene
		var enemies: Node = world.get_node("Enemies")
		var boss := BOSS_SCENE.instantiate() as Boss
		boss.name = Net.next_enemy_name()
		boss.enemy_kind = "juggernaut"
		enemies.add_child(boss)
		boss.global_position = pawn.global_position + Vector3(0, 0, 6)
		await get_tree().physics_frame

		_ok(boss.is_in_group("boss"), "it is in the 'boss' group, so the bar can find it")
		_ok(boss.is_in_group("enemies"), "and still an enemy, so every swing already hits it")
		_ok(boss.phase == 1, "it starts in phase one")
		_ok(boss.body_visual is BossVisual, "it wears a body of its own")
		_ok(boss.body_height() > 2.0, "it stands %.2fm tall" % boss.body_height())

		# --- poise: no ordinary hit rocks it back ---
		var before := boss.health
		boss.take_damage(30.0, Vector3.FORWARD * 999.0, 0, null)
		_ok(boss.stagger_left <= 0.0, "a huge hit does not stagger it (poise)")
		_ok(boss.health < before,
				"...but it still takes the damage (%.0f -> %.0f)" % [before, boss.health])
		_ok(not boss.is_open(), "and it is not open for having been hit")

		# --- opening one: a parry, through the ordinary path ---
		boss.net_stagger(0.5)
		_ok(boss.is_open(), "a parry's stagger opens it")
		boss.stagger_left = 0.0

		# --- opening two: the recovery of a move it committed to ---
		boss.player = pawn
		boss.aggroed = true
		boss._start_move("slam")
		_ok(boss.move_id == "slam", "it commits to the slam")
		_ok(boss.is_winding_up(), "and telegraphs it")
		var style := boss.telegraph_style()
		_ok(float(style["ring"]) > 0.0, "the slam draws a ring %.1fm across" % style["ring"])
		_ok(style["color"] != Boss.DEFAULT_TELEGRAPH["color"], "in a colour of its own")
		var slam: Dictionary = Boss.MOVES["slam"]
		var hp_before: float = pawn.health
		await _run_move(boss, float(slam["windup"]) + float(slam["active"]) + 0.05)
		_ok(pawn.health < hp_before, "the slam lands on a player stood in it (%.0f -> %.0f)" % [
				hp_before, pawn.health])
		_ok(boss.move_id == "", "the move ends")
		_ok(boss.recover_left > 0.0, "and leaves it open for %.2fs" % boss.recover_left)
		_ok(boss.is_open(), "which the lock-on ring reports as open")
		var punish_before := boss.health
		boss.take_damage(10.0, Vector3.FORWARD, 0, null)
		var punished := punish_before - boss.health
		_ok(punished > 10.0, "a hit in the recovery pays %.1f for a 10.0 swing" % punished)

		# --- the slam is a RING: standing out of it is the answer to it ---
		boss.recover_left = 0.0
		boss._move_cooldowns["slam"] = 0.0
		pawn.global_position = boss.global_position + Vector3(0, 0, float(slam["reach"]) + 4.0)
		pawn.net_pos = pawn.global_position
		var far_hp: float = pawn.health
		boss._start_move("slam")
		await _run_move(boss, float(slam["windup"]) + float(slam["active"]) + 0.05)
		_ok(is_equal_approx(pawn.health, far_hp), "standing outside the ring takes nothing")

		# --- phase two ---
		_ok(boss._pick_move(10.0) != "charge", "no charge while it is still careful")
		var walk_before := boss.move_speed
		boss.health = boss.max_health * boss.phase_two_at - 1.0
		boss._on_health_changed()
		_ok(boss.phase == 2, "past the threshold it turns")
		_ok(boss.move_speed > walk_before,
				"and speeds up (%.1f -> %.1f)" % [walk_before, boss.move_speed])
		_ok(not boss.is_blocking(), "it stops guarding entirely")
		boss._decide(4.0)
		_ok(boss.state == Enemy.CombatState.ATTACK, "and every decision is to close")
		boss._decide_after_swing()
		_ok(boss.state == Enemy.CombatState.ATTACK, "...including after a swing")
		boss.recover_left = 0.0
		boss._move_cooldowns["charge"] = 0.0
		_ok(boss._pick_move(12.0) == "charge", "the charge unlocks at 12m")
		_ok(boss._pick_move(2.0) != "charge", "but is never thrown from arm's length")

		# --- the drop ---
		var drops_before := _drop_count()
		boss.health = 1.0
		boss.take_damage(50.0, Vector3.ZERO, 1, null)
		await get_tree().physics_frame
		_ok(boss.dead, "it dies like anything else")
		var club := _find_drop("juggernaut_club")
		_ok(club != null, "and leaves its club on the floor (%d -> %d drops)" % [
				drops_before, _drop_count()])
		if club != null:
			Net.players[1]["items"] = {}
			Net._server_award_item(1, club)
			_ok(int(Net.players[1]["items"].get("juggernaut_club", 0)) == 1,
					"which goes into the bag of whoever walks over it")

		_check_lair(world)

	## Where it actually LIVES. A boss parked off the edge of the dungeon's floor
	## falls out of the world and is never seen by anybody, and that floor is a
	## model — so this is measured against the real level rather than trusted.
	## Move the BossSpawner node in the editor; this is what says whether you
	## moved it somewhere there is a floor.
	func _check_lair(world: Node) -> void:
		var spawner: Node3D = null
		for n in world.find_children("*", "BossSpawner", true, false):
			spawner = n
			break
		_ok(spawner != null, "the catacombs have a BossSpawner in them")
		if spawner == null:
			return
		var from: Vector3 = spawner.global_position + Vector3.UP * float(spawner.head_room)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		_ok(not hit.is_empty(), "and it stands over solid floor")
		if hit.is_empty():
			_scan_floor(world, spawner)
		# far enough in that arriving in the dungeon is not arriving in the fight
		var arrival := get_tree().get_first_node_in_group("teleport_catacombs")
		if arrival != null:
			var gap: float = (arrival as Node3D).global_position.distance_to(spawner.global_position)
			_ok(gap > Boss.INTRO_RANGE,
					"and is %.0fm from the way in (past the %.0fm entrance shot)" % [
							gap, Boss.INTRO_RANGE])

	## Only ever runs when the check above FAILED: prints where in the dungeon
	## there IS floor, so "move the spawner" comes with somewhere to move it to
	## rather than another round of guessing at coordinates.
	func _scan_floor(world: Node, spawner: Node3D) -> void:
		var parent := spawner.get_parent() as Node3D
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		var rows := PackedStringArray()
		for zi in range(-12, 18):
			var row := "z=%4d  " % (zi * 4)
			for xi in range(-4, 20):
				var local := Vector3(xi * 4, 4.0, zi * 4)
				var from: Vector3 = parent.global_transform * local
				var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
				row += "#" if not space.intersect_ray(q).is_empty() else "."
			rows.append(row)
		print("  FLOOR MAP (x from -16 to 76 in 4m steps):")
		for r in rows:
			print("    ", r)

	## Ticks the boss's own moves by hand in frame-sized steps. A move's timings
	## are SECONDS, and neither a headless run nor a windowed one is 60fps —
	## counting frames measures the machine, not the move.
	func _run_move(boss: Boss, seconds: float) -> void:
		var step := 1.0 / 60.0
		var steps := int(ceil(seconds / step))
		for i in steps:
			var dist := 0.0
			if is_instance_valid(boss.player):
				dist = boss.global_position.distance_to(boss.player.global_position)
			boss._tick_moves(step, dist)
			if i % 6 == 0:
				await get_tree().physics_frame

	func _drop_count() -> int:
		var dn := get_tree().current_scene.get_node_or_null("Drops")
		return dn.get_child_count() if dn else 0

	func _find_drop(item_id: String) -> Node:
		var dn := get_tree().current_scene.get_node_or_null("Drops")
		if dn == null:
			return null
		for d in dn.get_children():
			if d is ItemDrop and String(d.item_id) == item_id:
				return d
		return null

	# ---------------- plumbing ----------------

	func _ok(cond: bool, label: String) -> void:
		checks += 1
		print("  %s %s" % ["[ok]  " if cond else "[FAIL]", label])
		if not cond:
			failures.append(label)

	func _report() -> void:
		print("BOSSTEST %d checks, %d failed" % [checks, failures.size()])
		for f in failures:
			print("  - %s" % f)
		print("BOSSTEST RESULT=%s" % ("PASS" if failures.is_empty() else "FAIL"))
		get_tree().quit(0 if failures.is_empty() else 1)
