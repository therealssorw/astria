extends Node
## Headless integration test for the tutorial. Run:
##   godot --headless --path . res://tests/test_tutorial.tscn
## Hosts a listen server in-process and walks the whole lesson: joining puts
## the player in their own copy of the city rather than on the island, nothing
## moves until the intro cutscene reports in, each gate holds the fight frozen
## until the player really does that action, clearing a wave moves it on by
## itself, and finishing hands the player to the island with the copy and its
## bandits gone.
## Prints TUTTEST RESULT=PASS/FAIL and exits with the matching code.

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "TutorialTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	const ME := 1 # a listen server's own player is peer 1

	func _ready() -> void:
		_run()

	func _fail(msg: String) -> void:
		print("TUTTEST RESULT=FAIL (%s)" % msg)
		get_tree().quit(1)

	## Frames until `cond` holds. Everything here is driven by Tutorial's own
	## _process, so nothing is instant.
	func _until(cond: Callable, frames := 240) -> bool:
		for i in frames:
			if cond.call():
				return true
			await get_tree().physics_frame
		return false

	func _step_id() -> String:
		return str(Tutorial.client_step_data().get("id", ""))

	## Every bandit belonging to my copy of the city.
	func _my_bandits() -> Array:
		var out := []
		var en := get_tree().current_scene.get_node_or_null("Enemies")
		if en == null:
			return out
		for e in en.get_children():
			if int(e.owner_peer) == ME and not e.dead:
				out.append(e)
		return out

	func _kill_all_bandits() -> void:
		# the tutorial's contract is "nothing of that wave is still standing",
		# which is exactly the flag a real kill sets on the server
		for b in _my_bandits():
			b.dead = true

	## Stand in for the player doing the thing. These are the SERVER's own
	## fields on its copy of the pawn — the same ones a real swing or a raised
	## guard set, and the only ones the gates ever read.
	func _do_action(pawn: Node, action: String) -> void:
		match action:
			"attack":
				pawn.attacking = true
				pawn.attack_is_heavy = false
			"attack_heavy":
				pawn.attacking = true
				pawn.attack_is_heavy = true
			"block":
				pawn.blocking = true

	func _stop_action(pawn: Node) -> void:
		pawn.attacking = false
		pawn.blocking = false

	## Walk one gate: check the fight is frozen, do the action, check it moved
	## on and let go. Returns "" on success or the failure reason.
	func _pass_gate(pawn: Node, step_id: String, action: String,
			client_gate := false) -> String:
		if not await _until(func() -> bool: return _step_id() == step_id):
			return "%s never came up (stuck on '%s')" % [step_id, _step_id()]
		var held := _my_bandits()
		if held.is_empty():
			return "%s has nothing to fight" % step_id
		for b in held:
			if not b.frozen:
				return "%s did not freeze the fight" % step_id
		# a gate must not open on its own
		await get_tree().physics_frame
		if _step_id() != step_id:
			return "%s opened without the player doing anything" % step_id
		if client_gate:
			Net.report_tutorial_pressed(step_id)
		else:
			_do_action(pawn, action)
		var moved := await _until(func() -> bool: return _step_id() != step_id)
		_stop_action(pawn)
		if not moved:
			return "%s never opened after the action" % step_id
		return ""

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame
		Net.host_game("Tester")

		var pawn: Node3D = null
		for i in 900:
			await tree.physics_frame
			var world := tree.current_scene
			if world and String(world.name) == "World":
				var pn := world.get_node_or_null("Players")
				if pn and pn.get_child_count() > 0:
					pawn = pn.get_child(0)
					break
		if pawn == null:
			_fail("pawn never spawned")
			return

		# 1. joining lands in a private copy of the city, not on the island
		if not Tutorial.server_running(ME):
			_fail("tutorial did not start on join")
			return
		var arena := tree.current_scene.get_node_or_null("TutorialArena_0")
		if arena == null:
			_fail("no copy of the city was built")
			return
		var island := Net.spawn_position(0)
		if pawn.global_position.distance_to(island) < 100.0:
			_fail("player woke up on the island instead of the city")
			return
		if pawn.global_position.distance_to(arena.player_spawn()) > 3.0:
			_fail("player did not wake up at the city's spawn")
			return

		# 2. nothing moves until the cutscene says the player can see
		await tree.physics_frame
		if not _my_bandits().is_empty():
			_fail("bandits attacked during the cutscene")
			return
		Net.report_tutorial_ready()

		# 3. the four gates, in order, each holding the fight still
		var why := await _pass_gate(pawn, "teach_attack", "attack")
		if why != "":
			_fail(why)
			return
		if not await _until(func() -> bool: return _step_id() == "kill_first"):
			_fail("the fight never resumed after the first gate")
			return
		for b in _my_bandits():
			if b.frozen:
				_fail("bandits stayed frozen after the gate opened")
				return
		_kill_all_bandits()

		why = await _pass_gate(pawn, "teach_block", "block")
		if why != "":
			_fail(why)
			return
		why = await _pass_gate(pawn, "teach_lock_on", "lock_on", true)
		if why != "":
			_fail(why)
			return
		if not await _until(func() -> bool: return _step_id() == "kill_pair"):
			_fail("the pair never became a fight")
			return
		if _my_bandits().size() != 2:
			_fail("expected two bandits in the second wave, found %d" % _my_bandits().size())
			return
		_kill_all_bandits()

		why = await _pass_gate(pawn, "teach_heavy", "attack_heavy")
		if why != "":
			_fail(why)
			return
		if not await _until(func() -> bool: return _step_id() == "clear_city"):
			_fail("the last wave never became a fight")
			return
		if _my_bandits().size() != 3:
			_fail("expected three bandits in the last wave, found %d" % _my_bandits().size())
			return
		_kill_all_bandits()

		# 4. the villager step, then out of the city
		if not await _until(func() -> bool: return _step_id() == "mayor"):
			_fail("the villager never came after the city was clear")
			return
		Net.report_tutorial_pressed("mayor")
		if not await _until(func() -> bool: return not Tutorial.server_running(ME)):
			_fail("the tutorial never ended")
			return
		if not await _until(func() -> bool:
				return tree.current_scene.get_node_or_null("TutorialArena_0") == null):
			_fail("the copy of the city was left standing")
			return
		if Vector2(pawn.global_position.x - island.x,
				pawn.global_position.z - island.z).length() > 3.0:
			_fail("player was not put on the island (at %s)" % pawn.global_position)
			return
		var en := tree.current_scene.get_node_or_null("Enemies")
		if en:
			for e in en.get_children():
				if int(e.owner_peer) == ME:
					_fail("a tutorial bandit outlived the tutorial")
					return

		print("TUTTEST RESULT=PASS")
		tree.quit(0)
