extends Node
## Headless integration test for the catacombs entrance. Run:
##   godot --headless --path . res://tests/test_catacombs.tscn
## Prints CATATEST RESULT=PASS/FAIL and exits with the matching code.
##
## What it covers is the round trip, which is the part nobody notices is broken
## until they are stuck: the door on the island really puts you inside the
## dungeon, the dungeon is somewhere else entirely rather than under the town,
## the way back really comes out beside the door, and — the one that is easy to
## get wrong — arriving does NOT immediately throw you back through the portal
## you landed next to.
##
## The door is PRESS-TO-ENTER, so the first thing checked is that standing in it
## does nothing at all: a door that swallows anyone who walks past it is the
## thing this replaced. The press goes through the server exactly like every
## other request, so the test also stands the pawn 60 m away and presses, which
## must do nothing.
##
## And it checks WHERE YOU LAND. Arriving 3 m over the dungeon floor is what
## "falling through the floor on first entry" actually was: the anchor is in the
## air, so every entry began with a drop into a dark room. The pawn now has to be
## standing on something within a second of arriving, and still be there a second
## later — a check against the FLOOR, not against the anchor.
##
## It also checks the quest's star has something to point at, since the whole
## point of putting the place in the level is that "Clear out the catacombs"
## stops pointing at nothing.

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "CatacombsTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	const TEST_HOST := preload("res://tests/helpers/test_host.gd")

	## Long enough for the portal to have polled several times, so "it did not
	## fire" means it really did not rather than that we looked too early.
	const SETTLE := 8
	## About a second of physics — long enough for anything that is going to fall
	## to have fallen, which is what the landing check is asking.
	const LAND_FRAMES := 60

	var _failures: Array[String] = []

	func _ready() -> void:
		_run()

	func _check(condition: bool, what: String) -> bool:
		if not condition:
			_failures.append(what)
		return condition

	func _flat_gap(a: Vector3, b: Vector3) -> float:
		return Vector2(a.x - b.x, a.z - b.z).length()

	func _wait(tree: SceneTree, frames: int) -> void:
		for _i in frames:
			await tree.physics_frame

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame
		var host := TEST_HOST.new()
		var pawn: Node3D = await host.boot(tree, "catacombs")
		if pawn == null:
			print("CATATEST RESULT=FAIL (%s)" % host.error)
			tree.quit(1)
			return

		# OFF THE LESSON FIRST. A joining player wakes up in their own copy of
		# the city, where the tutorial is talking to them — and a dialog box owns
		# the interact button while it is up, which is correct and is not what
		# this test is about. Graduating is the same exit the last step uses.
		Tutorial.server_end(1, true)
		DialogSystem.close()
		IntroCutscene.abort() # the wake-up holds ui_open while it plays
		await _wait(tree, SETTLE)
		var scene := tree.current_scene
		var entrance: Node3D = scene.find_child("CatacombsEntrance", true, false)
		var dungeon: Node3D = scene.find_child("Catacombs", true, false)
		if entrance == null or dungeon == null:
			print("CATATEST RESULT=FAIL (the entrance or the dungeon is not in world.tscn)")
			tree.quit(1)
			return

		var inside := TeleportData.anchor(tree, "catacombs")
		var outside := TeleportData.anchor(tree, "catacombs_exit")
		_check(inside != null, "nothing in the level anchors 'catacombs'")
		_check(outside != null, "nothing in the level anchors 'catacombs_exit'")
		# The quest pointed at nothing until the place was built; that is the
		# reason it is in the level at all.
		_check(QuestData.target_pos(tree, "clear_catacombs") != null,
			"'clear out the catacombs' still has no star to point at")
		if inside == null or outside == null:
			_report()
			return

		# The dungeon is a place of its own, not a room under the town: if the
		# two ends are near each other the portals sit in each other's radius
		# and the round trip below proves nothing.
		_check(_flat_gap(inside.global_position, entrance.global_position) > 100.0,
			"the dungeon is only %.0f m from its own door" %
				_flat_gap(inside.global_position, entrance.global_position))

		# 1. THE DOOR IS A PRESS. Standing in it does nothing — you can walk over
		# the entrance to the catacombs on your way somewhere else.
		_check(entrance.require_interact, "the catacombs door is not press-to-enter")
		pawn.net_teleport(entrance.global_position + Vector3(12, 0, 0))
		await _wait(tree, 2)
		pawn.net_teleport(entrance.global_position)
		await _wait(tree, SETTLE)
		if not _check(_flat_gap(pawn.global_position, entrance.global_position) < 3.0,
				"standing in the doorway took the pawn through it without a press"):
			_report()
			return
		# ...and the bubble is up while you stand there. A door that has to be
		# pressed and does not say so is a door nobody opens.
		_check(entrance.prompt_alpha > 0.0, "no prompt over a door you are standing in")

		# 2. a press from 60 m away is not a press at the door. The request names
		# no portal at all, so this is the whole of what the server checks.
		pawn.net_teleport(entrance.global_position + Vector3(60, 0, 0))
		await _wait(tree, 2)
		Net.request_portal_enter()
		await _wait(tree, SETTLE)
		_check(_flat_gap(pawn.global_position, inside.global_position) > 100.0,
			"pressing interact 60 m from the door still opened it")

		# 3. press it where it is, and you are in the dungeon
		pawn.net_teleport(entrance.global_position)
		await _wait(tree, 2)
		Net.request_portal_enter()
		await _wait(tree, SETTLE)
		var landed: Vector3 = pawn.global_position
		if not _check(_flat_gap(landed, inside.global_position) < 3.0,
				"pressing at the door left the pawn at %v, not in the dungeon at %v"
					% [landed, inside.global_position]):
			_report()
			return

		# 4. ON THE FLOOR, not in the air over it. Given a second to settle, the
		# pawn has to be standing on something and still be standing on it — a
		# fall-through shows up as either "never landed" or "landed and kept
		# going", and both are caught by measuring twice.
		await _wait(tree, LAND_FRAMES)
		var floor_y := _floor_under(scene, landed)
		var settled: float = pawn.global_position.y
		print("  landing: floor %.2f, feet %.2f, drop from the anchor %.2f m" % [
				floor_y, settled, inside.global_position.y - floor_y])
		_check(pawn.is_on_floor(), "the pawn is not standing on anything after arriving")
		_check(floor_y > -INF and absf(settled - floor_y) < 1.0,
			"the pawn settled at %.2f, %.2f m off the floor at %.2f" % [
					settled, settled - floor_y, floor_y])
		await _wait(tree, LAND_FRAMES)
		_check(absf(pawn.global_position.y - settled) < 0.5,
			"the pawn is still moving %.2f m a second after landing" %
				(pawn.global_position.y - settled))

		# 5. ...and standing there does NOT bounce you straight back out. The
		# way home is a few steps away, and a portal that fires on arrival
		# makes the pair of them a loop nobody can get out of.
		await _wait(tree, SETTLE)
		_check(_flat_gap(pawn.global_position, inside.global_position) < 6.0,
			"the pawn was thrown back out of the dungeon without walking anywhere")

		# 6. the way back really comes out beside the door on the island — and it
		# is still WALK-IN: nobody wants to press a button to leave a room.
		pawn.net_teleport(inside.global_position + Vector3(20, 0, 0))
		await _wait(tree, 2)
		var back: Node3D = dungeon.find_child("ExitPortal", true, false)
		if not _check(back != null, "the dungeon has no way out"):
			_report()
			return
		_check(not back.require_interact, "the way out now needs a button press too")
		pawn.net_teleport(back.global_position)
		await _wait(tree, SETTLE)
		_check(_flat_gap(pawn.global_position, outside.global_position) < 3.0,
			"the way out left the pawn at %v, not beside the door at %v"
				% [pawn.global_position, outside.global_position])
		# 7. and coming home does not walk you straight back in. The exit anchor
		# is a few steps from the door on purpose, but the door is a press now, so
		# this is belt and braces: standing there must do nothing.
		await _wait(tree, SETTLE)
		_check(_flat_gap(pawn.global_position, outside.global_position) < 6.0,
			"arriving back on the island fed the pawn into the door again")
		_report()

	## The floor under `at`, or -INF if there is nothing under it at all. Rayed
	## from head height so a pawn standing inside its own capsule is not the
	## answer, and characters are excluded for the same reason.
	func _floor_under(scene: Node, at: Vector3) -> float:
		var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
		var from := at + Vector3.UP * 1.6
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
		var skip: Array[RID] = []
		for node in scene.get_tree().get_nodes_in_group("player"):
			if node is CollisionObject3D:
				skip.append((node as CollisionObject3D).get_rid())
		query.exclude = skip
		var hit: Dictionary = space.intersect_ray(query)
		return (hit["position"] as Vector3).y if not hit.is_empty() else -INF

	func _report() -> void:
		if _failures.is_empty():
			print("CATATEST RESULT=PASS")
			get_tree().quit(0)
		else:
			for f in _failures:
				print("  FAIL: %s" % f)
			print("CATATEST RESULT=FAIL (%d)" % _failures.size())
			get_tree().quit(1)
