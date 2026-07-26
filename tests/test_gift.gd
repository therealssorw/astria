extends Node
## Headless integration test for one-off gifts and the protection armor buys.
## Run:
##   godot --headless --path . res://tests/test_gift.tscn
## Prints GIFTTEST RESULT=PASS/FAIL and exits with the matching code.
##
## Three things, and they fail in different ways:
##
## - The CATALOGUE, which needs no server: every gift names a real NPC and real
##   items, every armor piece declares the slot it covers, and the three suits
##   line up with the three blades.
## - The PROTECTION maths, also pure: more armor lets less through, and a suit
##   of nothing changes nothing.
## - The GIFT itself, which needs a world: refused from across the island,
##   handed over at the blacksmith's feet, all four pieces arrive, and asking a
##   second time gets you nothing. Plus the half that is easy to get wrong
##   silently — the conversation opening on Bram's gift line before and on his
##   ordinary greeting after.

const GIFT := "blacksmith_armor"

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "GiftTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	const TEST_HOST := preload("res://tests/helpers/test_host.gd")
	const GIFT := "blacksmith_armor"

	var _checks := 0

	func _ready() -> void:
		_run()

	func _fail(msg: String) -> void:
		print("GIFTTEST RESULT=FAIL (%s)" % msg)
		get_tree().quit(1)

	func _check(cond: bool, msg: String) -> bool:
		_checks += 1
		if not cond:
			_fail(msg)
		return cond

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame

		if not _catalogue():
			return
		if not _protection():
			return

		var host := TEST_HOST.new()
		var pawn: Node3D = await host.boot(tree, "gift")
		if pawn == null:
			_fail(host.error)
			return
		if not await _handing_it_over(tree, pawn):
			return

		print("GIFTTEST ran %d assertions" % _checks)
		print("GIFTTEST RESULT=PASS")
		tree.quit(0)

	# ---------------- the catalogue, which needs nobody ----------------

	func _catalogue() -> bool:
		for gift_id: String in GiftData.GIFTS:
			var from := GiftData.giver(gift_id)
			if not _check(from == "" or DialogData.has(from),
					"gift '%s' comes from '%s', who has nothing to say" % [gift_id, from]):
				return false
			var items := GiftData.items(gift_id)
			if not _check(not items.is_empty(), "gift '%s' hands over nothing" % gift_id):
				return false
			for item_id: String in items:
				if not _check(ItemDb.has(item_id),
						"gift '%s' lists '%s', which is not an item" % [gift_id, item_id]):
					return false

		# Every armor item says which slot it covers, and each suit fills all
		# four exactly once — four helmets in a bag must never read as a set.
		for tier: String in ItemDb.ARMOR_SETS:
			var slots := {}
			var pieces: Array = ItemDb.ARMOR_SETS[tier]
			if not _check(pieces.size() == ItemDb.EQUIP_SLOTS.size(),
					"the %s suit has %d pieces, expected one per equipment slot (%d)"
							% [tier, pieces.size(), ItemDb.EQUIP_SLOTS.size()]):
				return false
			# ...and between them they cover every slot of the suit's ART, which
			# is the check that catches a piece being dropped rather than merged
			# — three items still have to put on all four plates.
			var covered := {}
			for item_id: String in pieces:
				if not _check(ItemDb.has(item_id), "%s names '%s', which is not an item"
						% [tier, item_id]):
					return false
				var slot := ItemDb.armor_slot(item_id)
				if not _check(ItemDb.EQUIP_SLOTS.has(slot),
						"%s is worn in '%s', which is not an equipment slot" % [item_id, slot]):
					return false
				if not _check(not slots.has(slot),
						"the %s suit has two pieces for '%s'" % [tier, slot]):
					return false
				slots[slot] = true
				for art_slot: String in ItemDb.armor_covers(item_id):
					if not _check(not covered.has(art_slot),
							"the %s suit puts two items on '%s'" % [tier, art_slot]):
						return false
					covered[art_slot] = true
			for art_slot: String in NpcDefinition.SLOTS:
				if not _check(covered.has(art_slot),
						"nothing in the %s suit covers '%s'" % [tier, art_slot]):
					return false

		# A suit is the same rank and the same price as the blade it is named
		# for. That pairing is the whole shape of the ladder, and it is the kind
		# of thing that drifts the moment a price is edited in one place.
		for pair in [["flimsy", "wooden_sword"], ["copper", "copper_sword"],
				["iron", "iron_sword"]]:
			var blade: String = pair[1]
			for item_id: String in ItemDb.ARMOR_SETS[pair[0]]:
				if not _check(ItemDb.level_of(item_id) == ItemDb.level_of(blade),
						"%s is level %d but %s is level %d"
								% [item_id, ItemDb.level_of(item_id), blade,
										ItemDb.level_of(blade)]):
					return false
				if not _check(ItemDb.buy_price(item_id) == ItemDb.buy_price(blade),
						"%s costs %d but %s costs %d"
								% [item_id, ItemDb.buy_price(item_id), blade,
										ItemDb.buy_price(blade)]):
					return false
		return true

	# ---------------- what armor is worth ----------------

	func _protection() -> bool:
		if not _check(is_equal_approx(CombatLevels.armor_protection(0), 1.0),
				"wearing nothing should let everything through"):
			return false
		var bare := CombatLevels.armor_protection(0)
		var flimsy := CombatLevels.armor_protection(4)   # full level 1 suit
		var copper := CombatLevels.armor_protection(8)
		var iron := CombatLevels.armor_protection(12)
		if not _check(flimsy < bare and copper < flimsy and iron < copper,
				"each suit should let less through than the last: %.3f %.3f %.3f"
						% [flimsy, copper, iron]):
			return false
		# It has to be worth wearing and it must not make you invulnerable.
		if not _check(flimsy < 0.85, "a full flimsy suit barely does anything (%.3f)" % flimsy):
			return false
		if not _check(iron > 0.3, "a full iron suit makes you nearly untouchable (%.3f)" % iron):
			return false

		# An enemy's level moves BOTH what it shrugs off and what it hits for.
		# Without the second half a "level 0" bandit would die faster while
		# punching exactly as hard, and the tuning target below is meaningless.
		if not _check(is_equal_approx(CombatLevels.enemy_power(CombatLevels.BASE_ENEMY_LEVEL), 1.0),
				"an ordinary enemy should hit for exactly its exported damage"):
			return false
		if not _check(CombatLevels.enemy_power(0) < 1.0,
				"a level 0 enemy should hit softer than an ordinary one"):
			return false
		if not _check(CombatLevels.enemy_toughness(0) < 1.0,
				"a level 0 enemy should die quicker than an ordinary one"):
			return false
		# The documented yardstick: two level 0s should cost about what one
		# level 1 does, which is what makes "six of them or three of those" the
		# same trip to the edge. Loose on purpose — it is a feel target, and
		# only the shape of it can be checked.
		var cost_0 := CombatLevels.enemy_power(0) * CombatLevels.enemy_toughness(0)
		var cost_1 := CombatLevels.enemy_power(1) * CombatLevels.enemy_toughness(1)
		if not _check(cost_0 > cost_1 * 0.3 and cost_0 < cost_1 * 0.7,
				"a level 0 enemy should cost roughly half a level 1 (got %.2f of it)"
						% (cost_0 / cost_1)):
			return false
		return true

	# ---------------- the gift, which needs a world ----------------

	func _handing_it_over(tree: SceneTree, pawn: Node3D) -> bool:
		var giver := GiftData.giver(GIFT)
		var npc := _npc_with(tree, giver)
		if not _check(npc != null, "the blacksmith ('%s') is not in the world" % giver):
			return false

		# 1. nothing taken yet, so his conversation opens on the gift line
		if not _check(not GameStats.gift_taken(GIFT),
				"a new player should not already have been given the armor"):
			return false
		if not _check(_opens_on(giver) == "gift",
				"Bram should open on his gift line the first time, not '%s'" % _opens_on(giver)):
			return false

		# 2. asking from the far side of the island is refused. The conversation
		# is local, so standing at him is the one part of it the server can see.
		_place(pawn, npc.global_position + Vector3(80, 0, 0))
		await tree.physics_frame
		Net.request_gift(GIFT)
		await tree.physics_frame
		if not _check(not GameStats.gift_taken(GIFT),
				"a gift should not be handed to a pawn nowhere near the giver"):
			return false
		if not _check(GameStats.item_count("flimsy_helmet") == 0,
				"a refused gift should still have handed over nothing"):
			return false

		# 3. walk up to him and it is handed over — all four pieces
		_place(pawn, npc.global_position + Vector3(1.0, 0, 0))
		await tree.physics_frame
		Net.request_gift(GIFT)
		await tree.physics_frame
		if not _check(GameStats.gift_taken(GIFT),
				"standing at the blacksmith should have handed the armor over"):
			return false
		for item_id: String in ItemDb.ARMOR_SETS["flimsy"]:
			if not _check(GameStats.item_count(item_id) == 1,
					"the gift should have handed over one %s, got %d"
							% [item_id, GameStats.item_count(item_id)]):
				return false

		# 4. carrying it protects you from NOTHING until you put it on
		if not _check(Net.armor_levels(1) == 0,
				"armor sitting in the bag should protect nobody, got %d levels"
						% Net.armor_levels(1)):
			return false

		# 5. asking again gets nothing. This is the whole point of the record:
		# a patched client can send the request as often as it likes.
		Net.request_gift(GIFT)
		await tree.physics_frame
		Net.request_gift(GIFT)
		await tree.physics_frame
		for item_id: String in ItemDb.ARMOR_SETS["flimsy"]:
			if not _check(GameStats.item_count(item_id) == 1,
					"asking twice got %d %s" % [GameStats.item_count(item_id), item_id]):
				return false

		# 6. and he stops opening on the gift line
		if not _check(_opens_on(giver) == str(DialogData.get_conversation(giver).get("start", "")),
				"Bram should open on his ordinary greeting once the armor is handed over"):
			return false

		# 7. putting it on, which is what the use button does
		if not await _equipping(tree):
			return false

		# 8. wearing it really does reduce what a hit takes off. Driven through
		# the server's own damage entry rather than the formula, so a suit that
		# never reaches the health subtraction fails here.
		return await _armor_softens_a_hit(tree, pawn)

	## Right trigger on a piece of armor puts it on, and again takes it off.
	## Driven through the ordinary use request, because that IS the feature —
	## nothing else in the game equips anything.
	func _equipping(tree: SceneTree) -> bool:
		for item_id: String in ItemDb.ARMOR_SETS["flimsy"]:
			if not await _use(tree, item_id):
				return false
			if not _check(GameStats.is_equipped(item_id), "using %s did not put it on" % item_id):
				return false
		if not _check(Net.armor_levels(1) == 3,
				"a full flimsy suit worn should be 3 armor levels, got %d" % Net.armor_levels(1)):
			return false

		# It is on your back where everyone can see it, so it rides the PUBLIC
		# registry — a peer that only ever sees that has to be able to draw it.
		var seen: Dictionary = Net._public_players().get(1, {}).get("equipped", {})
		if not _check(str(seen.get("torso", "")) == "flimsy_chestplate",
				"what a player is wearing should be public, got %s" % str(seen)):
			return false

		# Using it again takes it off — one button both ways.
		if not await _use(tree, "flimsy_helmet"):
			return false
		if not _check(not GameStats.is_equipped("flimsy_helmet"),
				"using a piece already on should have taken it off"):
			return false
		if not _check(Net.armor_levels(1) == 2,
				"taking the helmet off should drop a level, got %d" % Net.armor_levels(1)):
			return false
		if not await _use(tree, "flimsy_helmet"):
			return false

		# A chestplate is ONE item covering both the body and the arms, which is
		# what makes three pieces a suit rather than four.
		var covers := ItemDb.armor_covers("flimsy_chestplate")
		if not _check(covers.has("body") and covers.has("arms") and covers.size() == 2,
				"a chestplate should cover the body and the arms, got %s" % str(covers)):
			return false
		if not _check(ItemDb.armor_parts("flimsy_chestplate").size() == 2,
				"a chestplate should put on two plates of its suit"):
			return false

		# Losing the item takes it off: selling the breastplate off your back
		# must not leave you protected by something you no longer own.
		var bag: Dictionary = Net.players[1]["items"]
		bag.erase("flimsy_helmet")
		Net._bag_changed(1)
		await tree.physics_frame
		if not _check(not GameStats.is_equipped("flimsy_helmet"),
				"an item that left the bag should have come off with it"):
			return false
		bag["flimsy_helmet"] = 1
		Net._bag_changed(1)
		await tree.physics_frame
		return await _use(tree, "flimsy_helmet")

	## Selects the hotbar slot holding `item_id` and presses use on it.
	func _use(tree: SceneTree, item_id: String) -> bool:
		var slot := (Net.players[1]["hotbar"] as Array).find(item_id)
		if not _check(slot >= 0, "'%s' never reached the hotbar" % item_id):
			return false
		Net.request_hotbar_select(slot)
		await tree.physics_frame
		Net.request_use_item()
		await tree.physics_frame
		return true

	## The same blow with the suit on and with it gone. Nothing about this reads
	## CombatLevels — it asks the pawn what a hit cost it.
	func _armor_softens_a_hit(tree: SceneTree, pawn: Node3D) -> bool:
		var armoured := await _hit_for(tree, pawn, 20.0)
		# Stripped by taking the suit OFF rather than by emptying the bag: what
		# is worn is what protects you now, and a pawn still carrying the whole
		# suit is the sharper version of this check.
		var worn: Dictionary = Net.players[1]["equipped"].duplicate()
		Net.players[1]["equipped"] = Net._empty_equipment()
		var bare := await _hit_for(tree, pawn, 20.0)
		Net.players[1]["equipped"] = worn
		if not _check(bare > 0.0, "an unarmoured pawn should take the whole blow"):
			return false
		if not _check(armoured < bare,
				"armor should soften a hit: took %.2f in a suit, %.2f without" % [armoured, bare]):
			return false
		if not _check(is_equal_approx(armoured / bare, CombatLevels.armor_protection(3)),
				"a full flimsy suit let through %.3f of the blow, expected %.3f"
						% [armoured / bare, CombatLevels.armor_protection(3)]):
			return false
		return true

	func _hit_for(tree: SceneTree, pawn: Node3D, amount: float) -> float:
		pawn.set("health", float(pawn.get("max_health")))
		pawn.set("blocking", false)
		await tree.physics_frame
		var dealt: float = pawn.server_take_damage(amount, Vector3.ZERO, 0, null)
		pawn.set("health", float(pawn.get("max_health")))
		return dealt

	## Which line a conversation would open on right now, without opening it.
	func _opens_on(dialog_id: String) -> String:
		return DialogSystem._opening_line(DialogData.get_conversation(dialog_id))

	func _npc_with(tree: SceneTree, dialog_id: String) -> Node3D:
		for npc in tree.get_nodes_in_group("npc_interactable"):
			if is_instance_valid(npc) and str(npc.dialog_id) == dialog_id:
				return npc as Node3D
		return null

	## The server owns this pawn (we are the listen server), so moving its own
	## copy is placing the player, not a client claiming a position.
	func _place(pawn: Node3D, to: Vector3) -> void:
		pawn.global_position = to
		pawn.set("net_pos", to)
