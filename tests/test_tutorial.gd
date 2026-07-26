extends Node
## Headless integration test for the tutorial. Run:
##   godot --headless --path . res://tests/test_tutorial.tscn
## Hosts a listen server in-process and walks the whole lesson: joining puts
## the player on their own copy of the starter island rather than the real one,
## nothing moves until the client reports in, and then the fight is
## built up a piece at a time — one bandit that can only punch you (and really
## does) while block is taught, the same bandit completely still while the
## swings are taught, a full duel, and only then the rest of the raid. Each
## gate waits for the button to be really pressed. Finishing hands the player
## to the real island with the copy and its bandits gone; the cheat restarts it
## on a fresh copy; and a gate nobody answers gives in rather than trapping the
## player in a lesson that is hitting them.
##
## Every gate must carry the popup that teaches its control: the tutorial does
## not talk, so a gate with nothing to show is a gate that teaches nothing.
##
## The gates are worked with REAL input events. That matters: the heavy gate
## used to be unpassable by tapping the button, which left three bandits frozen
## and no way forward, and no amount of setting flags directly would have
## caught it.
## Prints TUTTEST RESULT=PASS/FAIL and exits with the matching code.

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "TutorialTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	const ME := 1 # a listen server's own player is peer 1
	## Not Net.DEFAULT_PORT: the test must not fight a game running from the
	## editor for the port, or it fails with "pawn never spawned" and blames
	## the tutorial for someone else playing.
	const TEST_PORT := 27140

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

	## Angle between where the camera rig is pointing and the speaker.
	func _camera_off_by(rig: Node3D, pawn: Node3D, speaker: Node3D) -> float:
		if rig == null or not is_instance_valid(speaker):
			return TAU
		var to: Vector3 = speaker.global_position - pawn.global_position
		to.y = 0.0
		if to.length() < 0.01:
			return 0.0
		var facing := -rig.global_transform.basis.z
		facing.y = 0.0
		return absf(facing.normalized().signed_angle_to(to.normalized(), Vector3.UP))

	func _any_swinging() -> bool:
		for b in _my_bandits():
			if b.attacking:
				return true
		return false

	func _kill_all_bandits() -> void:
		# the tutorial's contract is "nothing of that wave is still standing",
		# which is exactly the flag a real kill sets on the server
		for b in _my_bandits():
			b.dead = true

	## Real input, not a flag set behind the game's back. A gate reads what the
	## pawn is DOING, and the road from "the button is down" to "attack_is_heavy
	## is true" is where the interesting mistakes live — the heavy gate was
	## unpassable by tapping, and only pressing the real button showed it.
	func _press(action: String, down: bool) -> void:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		Input.parse_input_event(ev)

	## Work the button the way a player would until the step moves on: taps for
	## an ordinary press, ~0.6s holds for the ones that need holding.
	func _work_button(action: String, hold: bool, was: String, seconds := 6.0) -> bool:
		var period := 40 if hold else 20
		var release_at := 36 if hold else 10
		for i in int(seconds * 60.0):
			if i % period == 0:
				_press(action, true)
			elif i % period == release_at:
				_press(action, false)
			await get_tree().physics_frame
			if _step_id() != was:
				_press(action, false)
				return true
		_press(action, false)
		return false

	## Walk one gate: check the fight is frozen, do the action for real, check
	## it moved on. Returns "" on success or the failure reason.
	func _pass_gate(step_id: String, action: String, client_gate := false) -> String:
		if not await _until(func() -> bool: return _step_id() == step_id):
			return "%s never came up (stuck on '%s')" % [step_id, _step_id()]
		var step := TutorialData.step(TutorialData.index_of(step_id))
		var held := _my_bandits()
		if held.is_empty():
			return "%s has nothing to fight" % step_id
		# every gate must actually TEACH something: the popup is the whole
		# lesson now that the tutorial does not talk
		var popup: Dictionary = step.get("popup", {})
		if str(popup.get("title", "")) == "" or str(popup.get("body", "")) == "":
			return "%s has no popup explaining the control" % step_id
		# ...and it is actually ON SCREEN, which is a different claim
		var overlay := get_tree().current_scene.find_child("TutorialOverlay", true, false)
		if overlay == null:
			return "the HUD has no tutorial overlay"
		if not await _until(overlay.showing_popup, 120):
			return "%s never put its popup on screen" % step_id
		# ...and all of it is on screen, not half off an edge
		if not overlay.popup_fully_visible():
			return "%s drew its popup partly off screen" % step_id
		# each lesson switches the bandits down to exactly what it teaches
		# against: a metronome for the block gate, a dummy for the swings
		for b in held:
			if b.hold_mode != TutorialData.hold_for(step):
				return "%s did not set the bandit's AI to '%s'" % [step_id, step.get("ai", "")]
		# a gate must not open on its own
		await get_tree().physics_frame
		if _step_id() != step_id:
			return "%s opened without the player doing anything" % step_id
		if client_gate:
			Net.report_tutorial_pressed(step_id)
			if not await _until(func() -> bool: return _step_id() != step_id):
				return "%s never opened after the action" % step_id
			return ""
		var binding := TutorialData.gate_action_binding(action)
		if not await _work_button(binding, TutorialData.gate_is_hold(action), step_id):
			return "%s never opened after pressing %s" % [step_id, binding]
		return ""

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame
		Net.host_game("Tester", false, TEST_PORT)

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

		# 1. joining lands in a private COPY OF THE ISLAND, not on the real one
		if not Tutorial.server_running(ME):
			_fail("tutorial did not start on join")
			return
		var arena := tree.current_scene.get_node_or_null("TutorialArena_0")
		if arena == null:
			_fail("no copy of the island was built")
			return
		var first_arena_id := arena.get_instance_id()
		var island := Net.spawn_position(0)
		if pawn.global_position.distance_to(island) < 100.0:
			_fail("player woke up on the real island instead of a copy")
			return
		if pawn.global_position.distance_to(arena.player_spawn()) > 3.0:
			_fail("player did not wake up at the copy's spawn")
			return
		# the copy IS the starter island: same geometry, and the spawn sits in
		# the same place on it (the slot offset is the only difference)
		if arena.get_node_or_null("Island1") == null:
			_fail("the copy has no island in it")
			return
		var offset: Vector3 = arena.player_spawn() - island
		if Vector2(offset.x - TutorialData.SLOT_ORIGIN.x, offset.z).length() > 1.0:
			_fail("the copy's spawn is not the island's own spawn (off by %s)" % offset)
			return
		# a glTF ships no collision — without the runtime trimesh the player
		# would fall through the copy forever
		var solid := false
		for mi: MeshInstance3D in arena.find_children("*", "MeshInstance3D", true, false):
			if mi.find_children("*", "StaticBody3D", false, false).size() > 0:
				solid = true
				break
		if not solid:
			_fail("the copy of the island has no collision")
			return

		# 2. the bandits wait for the player's own client to report in

		# 3. ONE bandit, switched on a piece at a time. Block first, against an
		#    enemy that can do nothing but punch you on a slow count.
		if not await _until(func() -> bool: return _step_id() == "teach_block", 600):
			_fail("the block lesson never came up (at '%s')" % _step_id())
			return
		if _my_bandits().size() != 1:
			_fail("the lesson should open one on one, found %d" % _my_bandits().size())
			return
		# it really throws the punch there is to block — waited out, not assumed
		var began := Time.get_ticks_msec()
		if not await _until(_any_swinging, 480):
			_fail("the block lesson never threw a punch to block")
			return
		var why := await _pass_gate("teach_block", "block")
		if why != "":
			_fail(why)
			return
		# ...and it opened because we blocked, not because the patience valve
		# gave up on us. Those look identical from the outside, so time it.
		var spent := float(Time.get_ticks_msec() - began) / 1000.0
		var patience := TutorialData.patience(TutorialData.step(
				TutorialData.index_of("teach_block")))
		if spent >= patience - 2.0:
			_fail("the block gate ran out its %.0fs patience (%.1fs) instead of opening on a block"
					% [patience, spent])
			return

		# then it stops PUNCHING and lets you learn to hit it back. It still
		# circles: the first thing you swing at should be a target that moves.
		if not await _until(func() -> bool: return _step_id() == "teach_attack"):
			_fail("the punch lesson did not follow the block lesson")
			return
		var circler: Node3D = _my_bandits()[0]
		var was_at: Vector3 = circler.global_position
		var wandered := 0.0
		for i in 120:
			await tree.physics_frame
			if circler.attacking:
				_fail("the bandit swung during the punch lesson")
				return
			wandered = maxf(wandered, circler.global_position.distance_to(was_at))
		if wandered < 0.5:
			_fail("the bandit stood rooted during the punch lesson instead of circling")
			return
		why = await _pass_gate("teach_attack", "attack")
		if why != "":
			_fail(why)
			return

		# the heavy is taught against something completely still
		if not await _until(func() -> bool: return _step_id() == "teach_heavy"):
			_fail("the heavy lesson did not follow the punch lesson")
			return
		var dummy: Node3D = _my_bandits()[0]
		var stood_at: Vector3 = dummy.global_position
		for i in 90:
			await tree.physics_frame
			if dummy.attacking:
				_fail("the bandit swung during the heavy lesson")
				return
		if dummy.global_position.distance_to(stood_at) > 0.35:
			_fail("the bandit was not completely still for the heavy lesson")
			return
		why = await _pass_gate("teach_heavy", "attack_heavy")
		if why != "":
			_fail(why)
			return
		why = await _pass_gate("teach_lock_on", "lock_on", true)
		if why != "":
			_fail(why)
			return

		# 3b. the duel: everything switched on, still one on one
		if not await _until(func() -> bool: return _step_id() == "duel"):
			_fail("the duel never started")
			return
		if _my_bandits().size() != 1:
			_fail("the duel is not one on one (%d bandits)" % _my_bandits().size())
			return
		for b in _my_bandits():
			if b.hold_mode != Enemy.Hold.NONE:
				_fail("the duel left the bandit still held back")
				return
		_kill_all_bandits()

		# 3c. and only then the rest of the raid
		# they arrive talking and hold still until the line is read, so give
		# this one room for the line as well as the walk-on
		if not await _until(func() -> bool: return _step_id() == "clear_raid", 900):
			_fail("the reinforcements never arrived (stuck at '%s')" % _step_id())
			return
		if _my_bandits().size() != 3:
			_fail("expected three more bandits, found %d" % _my_bandits().size())
			return
		_kill_all_bandits()

		# 4. the raid being beaten IS the end: no quest, no hand-off
		if not await _until(func() -> bool: return not Tutorial.server_running(ME)):
			_fail("the tutorial never ended")
			return
		if not await _until(func() -> bool:
				return tree.current_scene.get_node_or_null("TutorialArena_0") == null):
			_fail("the copy of the island was left standing")
			return
		if Vector2(pawn.global_position.x - island.x,
				pawn.global_position.z - island.z).length() > 3.0:
			_fail("player was not put on the island (at %s)" % pawn.global_position)
			return
		var en := tree.current_scene.get_node_or_null("Enemies")
		if en:
			for e in en.get_children():
				# already on its way out is gone: queue_free lands next frame
				if int(e.owner_peer) == ME and not e.is_queued_for_deletion():
					_fail("a tutorial bandit outlived the tutorial")
					return

		# 5. the cheat starts it again — on a FRESH copy, not the one that was
		#    just torn down (queue_free is deferred, so the dying island is
		#    still in the tree and still answering to its name this frame)
		TutorialData.GATE_PATIENCE = 1.5 # the valve, without the wait
		Net.request_cheat_tutorial()
		if not await _until(func() -> bool: return Tutorial.server_running(ME)):
			_fail("the tutorial cheat did not restart it")
			return
		var again := tree.current_scene.get_node_or_null("TutorialArena_0")
		if again == null or not is_instance_valid(again):
			_fail("the restart left no copy of the island")
			return
		if again.get_instance_id() == first_arena_id:
			_fail("the restart handed back the copy it had just freed")
			return
		if not await _until(func() -> bool: return _step_id() == "teach_block", 600):
			_fail("the restarted tutorial never reached its first gate (at '%s')" % _step_id())
			return

		# 6. nobody presses anything: the gate must give in rather than leave
		#    the player being punched by a lesson with no way out
		if not await _until(func() -> bool: return _step_id() != "teach_block", 1500):
			_fail("an unanswered gate never gave in — the tutorial can be bricked")
			return
		for b in _my_bandits():
			if b.hold_mode == Enemy.Hold.ATTACKER:
				_fail("the lesson stayed on its metronome after the gate gave in")
				return

		print("TUTTEST RESULT=PASS")
		tree.quit(0)
