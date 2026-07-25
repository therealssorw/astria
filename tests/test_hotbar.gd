extends Node
## Headless integration test for the hotbar. Run:
##   godot --headless --path . res://tests/test_hotbar.tscn
## Hosts a listen server in-process and drives the same requests the UI sends:
## items handed out land on the bar by themselves, the selection walks and
## wraps, assigning an item that is already on the bar swaps rather than
## duplicates, clearing a slot leaves the item in the bag, and using an empty
## slot is refused. Everything is checked against the SERVER registry, not the
## local mirror. Prints HOTBARTEST RESULT=PASS/FAIL and exits with the code.

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "HotbarTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	var _used: Array = [] # [item_id, message] from the server's use replies

	func _ready() -> void:
		_run()

	func _fail(msg: String) -> void:
		print("HOTBARTEST RESULT=FAIL (%s)" % msg)
		get_tree().quit(1)

	func _bar() -> Array:
		return Net.players[1]["hotbar"]

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
		Net.item_used.connect(func(id: String, msg: String) -> void: _used.append([id, msg]))

		if _bar().size() != Net.HOTBAR_SLOTS:
			_fail("bar is not %d slots" % Net.HOTBAR_SLOTS)
			return

		# 1. handed-out items land on the bar without anyone touching the UI
		var ids: Array = ItemDb.ITEMS.keys()
		for id: String in ids:
			Net.request_cheat_give(id)
			await tree.physics_frame
		for i in ids.size():
			if _bar()[i] != ids[i]:
				_fail("slot %d holds '%s', expected '%s'" % [i, _bar()[i], ids[i]])
				return
		if GameStats.hotbar != _bar():
			_fail("mirror did not match the registry")
			return
		# a second copy of something already on the bar must not take a slot
		Net.request_cheat_give(ids[0])
		await tree.physics_frame
		if _bar().count(ids[0]) != 1:
			_fail("duplicate slot for a second copy")
			return

		# 2. selection walks and wraps (what R1/L1 ask for)
		Net.request_hotbar_select(2)
		await tree.physics_frame
		if int(Net.players[1]["hot_slot"]) != 2 or GameStats.hot_slot != 2:
			_fail("select did not take")
			return
		Net.request_hotbar_select(-1) # out of range: refused, not clamped
		await tree.physics_frame
		if int(Net.players[1]["hot_slot"]) != 2:
			_fail("out-of-range slot was accepted")
			return

		# 3. assigning an item that is already on the bar swaps the two slots
		var moved: String = ids[0]
		Net.request_hotbar_assign(4, moved)
		await tree.physics_frame
		if _bar()[4] != moved or _bar().count(moved) != 1 or _bar()[0] != "":
			_fail("assign duplicated or lost an entry: %s" % str(_bar()))
			return

		# 4. an item the player does not carry can never reach the bar
		Net.request_hotbar_assign(0, "not_a_real_item")
		await tree.physics_frame
		if _bar()[0] != "":
			_fail("bar took an item that isn't carried")
			return

		# 5. using the held slot reports the item; clearing leaves it in the bag.
		# Assigning also takes you to that slot, so the held one is now 4.
		var slot := int(Net.players[1]["hot_slot"])
		if slot != 4:
			_fail("assigning did not move the hand to that slot")
			return
		Net.request_use_item()
		await tree.physics_frame
		var held: String = _bar()[slot]
		if _used.is_empty() or _used[-1][0] != held:
			_fail("use did not report the held item")
			return
		Net.request_hotbar_assign(slot, "")
		await tree.physics_frame
		if _bar()[slot] != "":
			_fail("clearing a slot did nothing")
			return
		# and a cleared slot stays cleared when something else changes the bag
		Net.request_cheat_give(ids[-1])
		await tree.physics_frame
		if _bar().has(held):
			_fail("a cleared item put itself back on the bar")
			return
		if int(Net.players[1]["items"].get(held, 0)) <= 0:
			_fail("clearing a slot ate the item")
			return
		Net.request_use_item()
		await tree.physics_frame
		if _used[-1][0] != "":
			_fail("using an empty slot was not refused")
			return

		# 6. selling the last copy of an item takes it off the bar
		var bar_before: Array = _bar().duplicate()
		var sold := ""
		for slot_id: String in bar_before:
			if slot_id != "" and int(Net.players[1]["items"].get(slot_id, 0)) == 1:
				sold = slot_id
				break
		if sold != "":
			Net.players[1]["items"].erase(sold)
			Net._bag_changed(1)
			await tree.physics_frame
			if _bar().has(sold):
				_fail("an item that left the bag stayed on the bar")
				return

		print("HOTBARTEST bar=", _bar(), " slot=", Net.players[1]["hot_slot"])
		print("HOTBARTEST RESULT=PASS")
		get_tree().quit(0)
