extends Node
## Headless integration test for gold drops. Run:
##   godot --headless --path . res://tests/test_gold_drops.tscn
## Hosts a listen server in-process, kills a bandit next to the pawn with
## kill credit for peer 1, then checks: exactly one pile spawns, the rolled
## amount is 5..15, walking onto it pays that amount into the registry and
## the GameStats.coins mirror. Prints GOLDTEST RESULT=PASS/FAIL and exits
## with the matching code.

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "GoldTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	func _ready() -> void:
		_run()

	func _fail(msg: String) -> void:
		print("GOLDTEST RESULT=FAIL (%s)" % msg)
		get_tree().quit(1)

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame
		Net.host_game("Tester")

		# wait for the world scene and our own pawn
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

		# drop a bandit next to the pawn and kill it, credited to peer 1
		var bandit: Node3D = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
		bandit.name = Net.next_enemy_name()
		tree.current_scene.get_node("Enemies").add_child(bandit)
		bandit.global_position = pawn.global_position + Vector3(3, 0.5, 0)
		Net.server_broadcast_enemy_spawn(bandit)
		for i in 5:
			await tree.physics_frame
		bandit.take_damage(99999.0, Vector3.ZERO, 1)
		await tree.physics_frame

		var dn: Node = tree.current_scene.get_node_or_null("Drops")
		if dn == null or dn.get_child_count() != 1:
			_fail("expected exactly one gold drop")
			return
		var drop: Node3D = dn.get_child(0)
		var amount: int = drop.amount
		print("GOLDTEST rolled=", amount)
		if amount < 5 or amount > 15:
			_fail("amount out of range")
			return

		# brief pause with the pile on the ground — running this scene
		# WITHOUT --headless makes it a visual check of the drop too
		for i in 300:
			await tree.physics_frame

		# step onto the pile (teleporting the host pawn is authoritative)
		pawn.global_position = drop.global_position
		var gold := 0
		for i in 120:
			await tree.physics_frame
			gold = int(Net.players[1].get("gold", 0))
			if gold > 0:
				break
		print("GOLDTEST registry_gold=", gold, " coins_mirror=", GameStats.coins,
				" kills=", Net.players[1]["kills"])
		if gold == amount and GameStats.coins == amount and int(Net.players[1]["kills"]) == 1:
			print("GOLDTEST RESULT=PASS")
			get_tree().quit(0)
		else:
			_fail("award mismatch")
