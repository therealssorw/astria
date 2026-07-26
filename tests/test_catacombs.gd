extends Node
## Headless integration test for the catacombs entrance. Run:
##   godot --headless --path . res://tests/test_catacombs.tscn
## Prints CATATEST RESULT=PASS/FAIL and exits with the matching code.
##
## What it covers is the round trip, which is the part nobody notices is broken
## until they are stuck: walking into the door on the island really puts you
## inside the dungeon, the dungeon is somewhere else entirely rather than
## under the town, the way back really comes out beside the door, and — the
## one that is easy to get wrong — arriving does NOT immediately throw you
## back through the portal you landed next to.
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

		# 1. walk into the door and you are in the dungeon
		pawn.net_teleport(entrance.global_position + Vector3(12, 0, 0))
		await _wait(tree, 2)
		pawn.net_teleport(entrance.global_position)
		await _wait(tree, SETTLE)
		var landed: Vector3 = pawn.global_position
		if not _check(_flat_gap(landed, inside.global_position) < 3.0,
				"walking into the door left the pawn at %v, not in the dungeon at %v"
					% [landed, inside.global_position]):
			_report()
			return

		# 2. ...and standing there does NOT bounce you straight back out. The
		# way home is a few steps away, and a portal that fires on arrival
		# makes the pair of them a loop nobody can get out of.
		await _wait(tree, SETTLE)
		_check(_flat_gap(pawn.global_position, inside.global_position) < 6.0,
			"the pawn was thrown back out of the dungeon without walking anywhere")

		# 3. the way back really comes out beside the door on the island
		pawn.net_teleport(inside.global_position + Vector3(20, 0, 0))
		await _wait(tree, 2)
		var back: Node3D = dungeon.find_child("ExitPortal", true, false)
		if not _check(back != null, "the dungeon has no way out"):
			_report()
			return
		pawn.net_teleport(back.global_position)
		await _wait(tree, SETTLE)
		_check(_flat_gap(pawn.global_position, outside.global_position) < 3.0,
			"the way out left the pawn at %v, not beside the door at %v"
				% [pawn.global_position, outside.global_position])
		_report()

	func _report() -> void:
		if _failures.is_empty():
			print("CATATEST RESULT=PASS")
			get_tree().quit(0)
		else:
			for f in _failures:
				print("  FAIL: %s" % f)
			print("CATATEST RESULT=FAIL (%d)" % _failures.size())
			get_tree().quit(1)
