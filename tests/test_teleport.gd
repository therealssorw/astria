extends Node
## Headless integration test for the teleport cheat. Run:
##   godot --headless --path . res://tests/test_teleport.tscn
## Hosts a listen server in-process and checks, in order: a destination with
## no anchor in the level is refused (a listed place need not exist yet), an
## unknown id is refused, and once an anchor is dropped in the world the pawn
## AND the position the server validates reports against both land on it.
## Prints TPTEST RESULT=PASS/FAIL and exits with the matching code.

const DEST := "mini_dungeon"

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "TeleportTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	var _last_message := ""
	var _last_ok := false

	func _ready() -> void:
		_run()

	func _fail(msg: String) -> void:
		print("TPTEST RESULT=FAIL (%s)" % msg)
		get_tree().quit(1)

	## Distance ignoring height: the pawn is always falling a little.
	func _flat_gap(a: Vector3, b: Vector3) -> float:
		return Vector2(a.x - b.x, a.z - b.z).length()

	func _on_result(message: String, ok: bool) -> void:
		_last_message = message
		_last_ok = ok

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame
		Net.trade_result.connect(_on_result)
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

		# 1. the destination is listed, but nothing in the level anchors it yet
		var before: Vector3 = pawn.global_position
		Net.request_cheat_teleport(DEST)
		await tree.physics_frame
		# a refused teleport leaves the pawn where it was — bar the settling a
		# physics body does on its own, which is why this is a radius, not "=="
		if _last_ok or _flat_gap(pawn.global_position, before) > 1.0:
			_fail("unanchored destination should have been refused")
			return
		print("TPTEST unanchored_reply=", _last_message)

		# 2. a place that isn't in the table at all
		Net.request_cheat_teleport("nowhere")
		await tree.physics_frame
		if _last_ok:
			_fail("unknown destination should have been refused")
			return

		# 3. anchor it, and the pawn goes there
		var anchor: Node3D = (load("res://scenes/world/teleport_anchor.tscn") as PackedScene).instantiate()
		tree.current_scene.add_child(anchor)
		anchor.global_position = before + Vector3(40, 0, -25)
		await tree.physics_frame
		Net.request_cheat_teleport(DEST)
		await tree.physics_frame
		if not _last_ok:
			_fail("anchored teleport refused: %s" % _last_message)
			return
		var landed: Vector3 = pawn.global_position
		# the pawn falls to the ground from the anchor, so only the horizontal
		# placement is checked — and net_pos must move with it, or the owner's
		# next report from over there reads as a speedhack
		if _flat_gap(landed, anchor.global_position) > 0.5:
			_fail("pawn did not land on the anchor (%s vs %s)" % [landed, anchor.global_position])
			return
		if pawn.net_pos != anchor.global_position:
			_fail("net_pos did not move with the pawn")
			return

		print("TPTEST landed=", landed, " reply=", _last_message)
		print("TPTEST RESULT=PASS")
		tree.quit(0)
