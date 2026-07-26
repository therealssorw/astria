extends Node
## Headless integration test for buying and selling. Run:
##   godot --headless --path . res://tests/test_shop.tscn
## Prints SHOPTEST RESULT=PASS/FAIL and exits with the matching code.
##
## Two halves, because a shop breaks in two unrelated places:
##
## - THE COUNTER IS WHERE THE SHOPKEEPER IS. Everything about a shop hangs off
##   the NpcInteractable's position: the speech bubble, the conversation, and
##   the server's `_near_npc` check. Nothing draws that node, so it can be
##   dragged off its own NPC in the editor and the only symptom is that the
##   shop cannot be reached — which is exactly what happened to the blacksmith,
##   whose interactable ended up 54 m from the man standing at the anvil. So
##   every talkable NPC is measured against its OWN geometry here.
## - The trade itself is server-authoritative (see CLAUDE.md "Server
##   authority"): the client only ever asks. The refusals are the point —
##   too far, too poor, not stocked, not held — because each of them is a thing
##   a patched client would otherwise hand itself.

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "ShopTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	const TEST_HOST := preload("res://tests/helpers/test_host.gd")

	## What a shop's dialog answer must carry to be reachable at all.
	const OPEN_ACTION := "open_shop"

	var _failed := false

	func _ready() -> void:
		_run()

	func _fail(msg: String) -> void:
		_failed = true
		print("SHOPTEST RESULT=FAIL (%s)" % msg)
		get_tree().quit(1)

	func _check(cond: bool, msg: String) -> bool:
		if not cond:
			_fail(msg)
		return cond

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame

		if not _catalogue():
			return

		var host := TEST_HOST.new()
		var pawn: Node3D = await host.boot(tree, "shop")
		if pawn == null:
			_fail(host.error)
			return

		if not _npcs_stand_at_their_own_bodies(tree):
			return
		if not await _trading(tree, pawn):
			return

		print("SHOPTEST RESULT=PASS")
		tree.quit(0)

	# ---------------- the tables, before anything is hosted ----------------

	## A shop nobody can name, stocking something that does not exist, or with no
	## answer anywhere that opens it, is a shop that cannot be shopped at.
	func _catalogue() -> bool:
		for shop_id: String in ShopData.SHOPS:
			if not _check(DialogData.has(shop_id),
					"shop '%s' has no conversation to be opened from" % shop_id):
				return false
			for item_id: String in ShopData.stock(shop_id):
				if not _check(ItemDb.has(item_id),
						"shop '%s' stocks '%s', which is not in ItemDb" % [shop_id, item_id]):
					return false
			if not _check(_opens_shop(shop_id),
					"no answer in '%s's dialog carries \"%s\", so the shop cannot be opened"
					% [shop_id, OPEN_ACTION]):
				return false
		return true

	func _opens_shop(dialog_id: String) -> bool:
		var lines: Dictionary = DialogData.get_conversation(dialog_id).get("lines", {})
		for line_id: String in lines:
			for answer: Dictionary in lines[line_id].get("answers", []):
				if str(answer.get("action", "")) == OPEN_ACTION:
					return true
		return false

	# ---------------- where the counter actually is ----------------

	## The bug this file exists for. An NpcInteractable draws nothing, so being
	## dragged away from its NPC is invisible in the editor and in a screenshot:
	## the shopkeeper stands at his anvil, and the only place you can talk to him
	## (and therefore buy anything) is an empty patch of field.
	##
	## "His own body" = every piece of geometry in his family — the subtree the
	## interactable shares with the model, whether the model hangs UNDER the
	## interactable (the blacksmith) or the interactable is a child of the NPC
	## (the King). An NPC with no geometry of its own is skipped rather than
	## failed: a bare marker is a legitimate thing to talk to.
	func _npcs_stand_at_their_own_bodies(tree: SceneTree) -> bool:
		var measured := 0
		for npc in tree.get_nodes_in_group("npc_interactable"):
			if not is_instance_valid(npc) or not (npc is Node3D):
				continue
			var body: Variant = _body_bounds(_npc_family(npc))
			if body == null:
				continue # nothing drawn: a marker, not a character
			measured += 1
			var here: Vector3 = (npc as Node3D).global_position
			var gap := _distance_to_box(here, body as AABB)
			var reach: float = float(npc.get("interact_range"))
			if not _check(gap <= reach,
					"'%s's interactable stands %.1f m from the NPC it belongs to, "
					% [str(npc.get("dialog_id")), gap]
					+ "which is past its own %.1f m interact_range — nobody can talk to it "
					% reach
					+ "(interactable at %v, body around %v)" % [here, (body as AABB).get_center()]):
				return false
		return _check(measured > 0, "no talkable NPC in the world has a body to measure")

	## The node the NPC's geometry hangs off: the interactable's parent when it
	## is a child of the character, and the interactable itself when the
	## character hangs off it. Never the world root — that would measure the
	## whole island.
	func _npc_family(npc: Node) -> Node:
		var parent := npc.get_parent()
		if parent == null or parent == get_tree().current_scene:
			return npc
		return parent

	## World-space bounds of everything drawn under `root`, or null if nothing is.
	func _body_bounds(root: Node) -> Variant:
		var box: Variant = null
		for vis in root.find_children("*", "VisualInstance3D", true, false):
			var world: AABB = (vis as VisualInstance3D).global_transform \
					* (vis as VisualInstance3D).get_aabb()
			box = world if box == null else (box as AABB).merge(world)
		return box

	## 0 when the point is inside the box, else how far outside it is.
	func _distance_to_box(p: Vector3, box: AABB) -> float:
		var lo := box.position
		var hi := box.end
		var nearest := Vector3(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y),
				clampf(p.z, lo.z, hi.z))
		return p.distance_to(nearest)

	# ---------------- who moves the coins ----------------

	func _trading(tree: SceneTree, pawn: Node3D) -> bool:
		var shop_id: String = ShopData.SHOPS.keys()[0]
		var item: String = ShopData.stock(shop_id)[0]
		var price := ItemDb.buy_price(item)
		var counter := _npc_with(tree, shop_id)
		if not _check(counter != null, "'%s' has no NPC in the world" % shop_id):
			return false

		# 1. money enough, but on the far side of the island: refused. The
		# conversation is local, so standing there is the one half of it the
		# server can check for itself.
		_set_gold(price * 4)
		_place(pawn, counter.global_position + Vector3(80, 0, 0))
		await tree.physics_frame
		Net.request_buy(shop_id, item)
		await tree.physics_frame
		if not _check(GameStats.item_count(item) == 0,
				"a shop should not sell to a pawn 80 m from the counter"):
			return false
		if not _check(GameStats.coins == price * 4, "a refused trade must not cost anything"):
			return false

		# 2. at the counter it goes through, and the price is ItemDb's price
		_place(pawn, counter.global_position + Vector3(1.0, 0, 0))
		await tree.physics_frame
		Net.request_buy(shop_id, item)
		await tree.physics_frame
		if not _check(GameStats.item_count(item) == 1,
				"standing at the counter should have bought one %s" % item):
			return false
		if not _check(GameStats.coins == price * 3,
				"buying should have cost %d, purse reads %d" % [price, GameStats.coins]):
			return false

		# 3. something he does not stock is refused even at the counter
		var absent := _unstocked(shop_id)
		if absent != "":
			Net.request_buy(shop_id, absent)
			await tree.physics_frame
			if not _check(GameStats.item_count(absent) == 0,
					"a shop sold '%s', which it does not stock" % absent):
				return false

		# 4. and so is anything you cannot afford
		_set_gold(price - 1)
		await tree.physics_frame
		Net.request_buy(shop_id, item)
		await tree.physics_frame
		if not _check(GameStats.item_count(item) == 1,
				"a shop sold on credit"):
			return false
		if not _check(GameStats.coins == price - 1, "a refused trade must not cost anything"):
			return false

		# 5. selling pays ItemDb's sell price and takes the item away
		var sell := ItemDb.sell_price(item)
		Net.request_sell(shop_id, item)
		await tree.physics_frame
		if not _check(GameStats.item_count(item) == 0, "selling should have taken the %s" % item):
			return false
		if not _check(GameStats.coins == price - 1 + sell,
				"selling should have paid %d, purse reads %d" % [sell, GameStats.coins]):
			return false

		# 6. selling what you do not have pays nothing
		var before := GameStats.coins
		Net.request_sell(shop_id, item)
		await tree.physics_frame
		if not _check(GameStats.coins == before, "a shop paid for an item nobody handed over"):
			return false

		print("SHOPTEST counter=%v item=%s price=%d" % [counter.global_position, item, price])
		return true

	## An item the catalogue has and this shop does not, or "" when it stocks
	## everything there is.
	func _unstocked(shop_id: String) -> String:
		for id: String in ItemDb.ITEMS:
			if not ShopData.stock(shop_id).has(id):
				return id
		return ""

	func _npc_with(tree: SceneTree, dialog_id: String) -> Node3D:
		for npc in tree.get_nodes_in_group("npc_interactable"):
			if is_instance_valid(npc) and str(npc.get("dialog_id")) == dialog_id:
				return npc as Node3D
		return null

	## We are the listen server, so this is the server moving its own copy of the
	## pawn — placing the player, not a client claiming a position.
	func _place(pawn: Node3D, to: Vector3) -> void:
		pawn.global_position = to
		pawn.set("net_pos", to)

	func _set_gold(amount: int) -> void:
		Net.players[1]["gold"] = amount
		Net._send_purse(1)
