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

	## Hosting and waiting for the pawn is shared with the other integration
	## tests, private band of ports and all — hosting on Net.DEFAULT_PORT is
	## what made this test fight a game running from the editor.
	const TEST_HOST := preload("res://tests/helpers/test_host.gd")

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
		var host := TEST_HOST.new()
		var pawn: Node3D = await host.boot(tree, "hotbar")
		if pawn == null:
			_fail(host.error)
			return
		Net.item_used.connect(func(id: String, msg: String) -> void: _used.append([id, msg]))

		if _bar().size() != Net.HOTBAR_SLOTS:
			_fail("bar is not %d slots" % Net.HOTBAR_SLOTS)
			return

		# 1. handed-out items land on the bar without anyone touching the UI.
		# Only as many as there are slots: the catalogue outgrew the bar the
		# moment armor was added to it, and a bar that is full is a normal state
		# (see 1b), not the end of the test.
		var ids: Array = (ItemDb.ITEMS.keys() as Array).slice(0, Net.HOTBAR_SLOTS)
		for id: String in ids:
			Net.request_cheat_give(id)
			await tree.physics_frame
		# only as far as the bar goes: the catalogue is bigger than nine now (the
		# armor pieces), and _refill_hotbar fills free slots until it runs out.
		# Indexing past the end used to abort this function mid-run, which read as
		# the whole test hanging rather than failing.
		for i in mini(ids.size(), Net.HOTBAR_SLOTS):
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

		# 1b. with the bar full, the next thing picked up is CARRIED and not
		# dropped on the floor — auto-placement is a convenience, and running
		# out of room must not cost you the item.
		var spare := ""
		for id: String in ItemDb.ITEMS:
			if not ids.has(id):
				spare = id
				break
		if spare == "":
			_fail("the catalogue no longer has more items than the bar has slots")
			return
		var full: Array = _bar().duplicate()
		Net.request_cheat_give(spare)
		await tree.physics_frame
		if _bar() != full:
			_fail("a full bar was rearranged to fit '%s'" % spare)
			return
		if GameStats.item_count(spare) != 1:
			_fail("'%s' was lost when the bar had no room for it" % spare)
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

		# 3. assigning an item that is already on the bar SWAPS the two slots —
		# whatever was in the target comes back to the slot it left, and neither
		# is duplicated. Checked against the real occupant rather than against
		# "": the bar used to be mostly empty here, so the swap was only ever
		# exercised against a hole, which is the easy half of it.
		var moved: String = ids[0]
		var from_slot: int = _bar().find(moved)
		var displaced: String = _bar()[4]
		if displaced == "" or displaced == moved:
			_fail("slot 4 holds '%s', so this does not test a swap" % displaced)
			return
		Net.request_hotbar_assign(4, moved)
		await tree.physics_frame
		if _bar()[4] != moved or _bar().count(moved) != 1 				or _bar()[from_slot] != displaced:
			_fail("assign duplicated or lost an entry: %s (slot %d should hold '%s')"
					% [str(_bar()), from_slot, displaced])
			return
		if _bar()[0] != displaced or _bar().count(displaced) != 1:
			_fail("what was in slot 4 should be in slot 0 now: %s" % str(_bar()))
			return

		# 4. an item the player does not carry can never reach the bar. Slot 0 is
		# checked as UNCHANGED rather than empty — with a full bar it holds the
		# item the swap above displaced into it.
		var slot0: String = _bar()[0]
		Net.request_hotbar_assign(0, "not_a_real_item")
		await tree.physics_frame
		if _bar()[0] != slot0 or _bar().has("not_a_real_item"):
			_fail("bar took an item that isn't carried: %s" % str(_bar()))
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

		# 7. dragging. The gesture itself is Godot's (_get_drag_data / _drop_data);
		# what is ours is what a drop MEANS, so that is what is checked — through
		# the real screen in the world, which asks the same server the clicks do.
		var inv := tree.current_scene.get_node_or_null("InventoryUI")
		if inv == null:
			_fail("the world has no InventoryUI to drag in")
			return
		var carried := ""
		for item_id: String in Net.players[1]["items"]:
			if int(Net.players[1]["items"][item_id]) > 0:
				carried = item_id
				break

		# bag -> bar: it lands on the slot it was dropped on, not the held one
		Net.request_hotbar_select(0)
		await tree.physics_frame
		inv._on_slot_drop(_at("bar", 6), _from("bag", -1, carried))
		await tree.physics_frame
		if _bar()[6] != carried:
			_fail("a bag item dragged onto slot 6 did not land there: %s" % str(_bar()))
			return

		# bar -> bar: moved, and never duplicated
		inv._on_slot_drop(_at("bar", 7), _from("bar", 6, carried))
		await tree.physics_frame
		if _bar()[7] != carried or _bar().count(carried) != 1:
			_fail("dragging along the bar duplicated or lost it: %s" % str(_bar()))
			return

		# dropped back on itself: nothing happens, and the slot says so BEFORE the
		# drop — a panel that accepts a drop and then ignores it feels broken
		var settled: Array = _bar().duplicate()
		if inv._drop_allowed(_at("bar", 7), _from("bar", 7, carried)):
			_fail("a slot should refuse a drop from itself")
			return
		inv._on_slot_drop(_at("bar", 7), _from("bar", 7, carried))
		await tree.physics_frame
		if _bar() != settled:
			_fail("dropping a slot on itself changed the bar: %s" % str(_bar()))
			return

		# bar -> bag: off the bar, still in the bag
		inv._on_slot_drop(_at("bag", -1), _from("bar", 7, carried))
		await tree.physics_frame
		if _bar()[7] != "":
			_fail("dragging an item off the bar did not clear its slot")
			return
		if int(Net.players[1]["items"].get(carried, 0)) <= 0:
			_fail("dragging an item off the bar ate it")
			return

		# bag -> bag is deliberately nothing: a bag slot's position is not stored
		settled = _bar().duplicate()
		if inv._drop_allowed(_at("bag", -1), _from("bag", -1, carried)):
			_fail("the bag should refuse a drop that came out of the bag")
			return
		inv._on_slot_drop(_at("bag", -1), _from("bag", -1, carried))
		await tree.physics_frame
		if _bar() != settled:
			_fail("a bag-to-bag drag changed the bar: %s" % str(_bar()))
			return

		if not await _equipment_drags(tree, inv):
			return

		if not await _number_keys(tree, pawn):
			return

		print("HOTBARTEST bar=", _bar(), " slot=", Net.players[1]["hot_slot"])
		print("HOTBARTEST RESULT=PASS")
		get_tree().quit(0)

	## 1-9 jump straight to a slot. Driven with REAL key events through the pawn's
	## own handler rather than by calling the request: the binding, the action
	## table and the handler are three places this can break and only an event
	## goes through all of them.
	func _number_keys(tree: SceneTree, pawn: Node3D) -> bool:
		# every join lands in the tutorial, whose opening lines hold `ui_open` —
		# and an open panel owns the keyboard, which is the rule being relied on
		# rather than worked around. Put the pawn back in the world first.
		if DialogSystem.is_open():
			DialogSystem.close()
		pawn.ui_open = false
		await tree.process_frame
		for slot in [4, 0, 8]:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_1 + slot
			ev.pressed = true
			Input.parse_input_event(ev)
			Input.flush_buffered_events()
			await tree.process_frame
			await tree.physics_frame
			if int(Net.players[1]["hot_slot"]) != slot:
				_fail("key %d did not select slot %d (on %d)"
						% [slot + 1, slot, int(Net.players[1]["hot_slot"])])
				return false
		return true

	## Where a drop LANDED, and where it came FROM — the two halves of a drag as
	## the slots themselves describe them (DragSlot.where(), plus the item id).
	func _at(kind: String, slot: int, equip := "") -> Dictionary:
		return {"kind": kind, "slot": slot, "equip": equip}

	func _from(kind: String, slot: int, id: String, equip := "") -> Dictionary:
		return {"kind": kind, "slot": slot, "equip": equip, "id": id}

	## Dragging armor onto and off the equipment cross. The piece MOVES: onto your
	## back is out of the bag, so the checks are about the bag as much as the
	## equipment, and a helmet over the wrong slot has to be refused BEFORE the
	## drop rather than quietly doing nothing.
	func _equipment_drags(tree: SceneTree, inv: Node) -> bool:
		var helmet := "flimsy_helmet"
		if int(Net.players[1]["items"].get(helmet, 0)) <= 0:
			NetRegistry.add_item(Net.players[1], helmet)
			Net._bag_changed(1)
			await tree.physics_frame

		# a helmet is refused by every slot but the one it is worn in
		if inv._drop_allowed(_at("equip", -1, "pants"), _from("bag", -1, helmet)):
			_fail("a helmet should not be droppable onto the Pants slot")
			return false
		if not inv._drop_allowed(_at("equip", -1, "helmet"), _from("bag", -1, helmet)):
			_fail("a helmet should be droppable onto the Helmet slot")
			return false
		# and nothing that is not armor may go on at all
		if inv._drop_allowed(_at("equip", -1, "torso"), _from("bag", -1, "wooden_sword")):
			_fail("a sword should not be droppable onto an equipment slot")
			return false

		inv._on_slot_drop(_at("equip", -1, "helmet"), _from("bag", -1, helmet))
		await tree.physics_frame
		if str(Net.players[1]["equipped"].get("helmet", "")) != helmet:
			_fail("dragging a helmet onto its slot did not put it on")
			return false
		if int(Net.players[1]["items"].get(helmet, 0)) != 0:
			_fail("a helmet put on should have left the bag")
			return false
		if _bar().has(helmet):
			_fail("a helmet put on should have left the bar")
			return false

		# dragged back out, it comes off and returns to the bag — wherever it was
		# dropped, because a piece taken off has only one place to go
		inv._on_slot_drop(_at("bag", -1), _from("equip", -1, helmet, "helmet"))
		await tree.physics_frame
		if str(Net.players[1]["equipped"].get("helmet", "")) != "":
			_fail("dragging a helmet out of its slot did not take it off")
			return false
		if int(Net.players[1]["items"].get(helmet, 0)) != 1:
			_fail("a helmet taken off should be back in the bag")
			return false
		return true
