extends Node
## Headless integration test for the world-wide bandit cap. Run:
##   godot --headless --path . res://tests/test_enemy_cap.tscn
## Hosts a listen server in-process, then hammers the island's BanditSpawner
## with spawn attempts and checks the world never holds more than
## Net.MAX_LIVE_ENEMIES bandits — including that killing one frees a slot and
## that a second spawner cannot push the total past the ceiling.
## Prints CAPTEST RESULT=PASS/FAIL and exits with the matching code.

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "CapTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	func _fail(msg: String) -> void:
		print("CAPTEST RESULT=FAIL (%s)" % msg)
		get_tree().quit(1)

	func _ready() -> void:
		_run()

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame
		# a free port: the live server may be holding the default one
		if Net.host_game("Tester", false, 28741) != OK:
			_fail("could not host: %s" % Net.last_error)
			return

		var world: Node = null
		for i in 900:
			await tree.physics_frame
			var cur := tree.current_scene
			if cur and String(cur.name) == "World":
				world = cur
				break
		if world == null:
			_fail("world never loaded")
			return

		var spawner := world.get_node_or_null("BanditSpawner")
		if spawner == null:
			_fail("no BanditSpawner in the world")
			return

		# 1. hammer one spawner well past the cap
		for i in 40:
			spawner._try_spawn()
			await tree.physics_frame
		var n := Net.live_enemy_count()
		if n > Net.MAX_LIVE_ENEMIES:
			_fail("one spawner made %d bandits, cap is %d" % [n, Net.MAX_LIVE_ENEMIES])
			return
		if n != Net.MAX_LIVE_ENEMIES:
			_fail("expected the cap %d to fill, got %d" % [Net.MAX_LIVE_ENEMIES, n])
			return

		# 1b. the camp's OWN tally must survive pruning. Array[Node].filter()
		# with a typed-parameter lambda errors at runtime and silently empties
		# the list, which reported 0 alive forever and defeated max_alive.
		var own: int = spawner._alive_count()
		if own != Net.MAX_LIVE_ENEMIES:
			_fail("spawner counts %d of its own, expected %d" % [own, Net.MAX_LIVE_ENEMIES])
			return

		# 2. a SECOND camp must not raise the total
		var extra := BanditSpawner.new()
		extra.name = "ExtraSpawner"
		world.add_child(extra)
		extra.global_position = spawner.global_position + Vector3(12, 0, 0)
		for i in 20:
			extra._try_spawn()
			await tree.physics_frame
		n = Net.live_enemy_count()
		if n > Net.MAX_LIVE_ENEMIES:
			_fail("a second camp pushed the world to %d bandits" % n)
			return

		# 3. killing one frees exactly one slot
		var en := world.get_node_or_null("Enemies")
		var victim: Node = null
		for e in en.get_children():
			if not e.dead:
				victim = e
				break
		if victim == null:
			_fail("no living bandit to kill")
			return
		victim.take_damage(1e9, Vector3.ZERO, 0)
		for i in 10:
			await tree.physics_frame
		if Net.live_enemy_count() != Net.MAX_LIVE_ENEMIES - 1:
			_fail("killing one left %d alive" % Net.live_enemy_count())
			return
		if not Net.server_can_spawn_enemy():
			_fail("a freed slot did not reopen spawning")
			return
		spawner._try_spawn()
		await tree.physics_frame
		n = Net.live_enemy_count()
		if n != Net.MAX_LIVE_ENEMIES:
			_fail("refilling the freed slot gave %d" % n)
			return

		print("CAPTEST RESULT=PASS (world holds at most %d bandits)" % Net.MAX_LIVE_ENEMIES)
		get_tree().quit(0)
