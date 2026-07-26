extends Node
## Headless integration test for quest tracking and the HUD star. Run:
##   godot --headless --path . res://tests/test_quest.tscn
## Prints QUESTTEST RESULT=PASS/FAIL and exits with the matching code.
##
## Covers the two halves separately, because they fail in different ways:
##
## - The STATE: you start on no quest, the server refuses a quest that does not
##   exist, refuses to hand one over to a pawn standing nowhere near the NPC
##   that gives it out, and grants it once the pawn is at them. The heading
##   follows the mirror rather than deciding anything itself.
## - The MARKER's placement, which is pure maths and gets its own checks — in
##   particular that a target BEHIND the camera clamps to the side you would
##   turn towards. That one is invisible in a screenshot and wrong by a whole
##   screen width if the mirroring is dropped.

const QUEST := "bandit_camp"
const MARKER := preload("res://scripts/ui/quest/quest_marker_overlay.gd")

func _ready() -> void:
	# the runner must live on /root — Net.host_game() frees this test scene
	var runner := Runner.new()
	runner.name = "QuestTestRunner"
	get_tree().root.add_child.call_deferred(runner)

class Runner:
	extends Node

	const TEST_HOST := preload("res://tests/helpers/test_host.gd")

	var _failed := false

	func _ready() -> void:
		_run()

	func _fail(msg: String) -> void:
		_failed = true
		print("QUESTTEST RESULT=FAIL (%s)" % msg)
		get_tree().quit(1)

	func _check(cond: bool, msg: String) -> bool:
		if not cond:
			_fail(msg)
		return cond

	func _run() -> void:
		var tree := get_tree()
		await tree.physics_frame

		if not _marker_maths():
			return

		var host := TEST_HOST.new()
		var pawn: Node3D = await host.boot(tree, "quest")
		if pawn == null:
			_fail(host.error)
			return
		if not await _quest_state(tree, pawn):
			return

		print("QUESTTEST RESULT=PASS")
		tree.quit(0)

	# ---------------- where the star lands ----------------

	func _marker_maths() -> bool:
		var rect := Rect2(Vector2.ZERO, Vector2(1280, 720))
		var center := rect.size * 0.5

		# in front and comfortably inside the screen: drawn where it really is
		var inside: Dictionary = MARKER.place_marker(Vector2(700, 300), false, rect)
		if not _check(inside["on_screen"], "a target in view should be on screen"):
			return false
		if not _check(inside["pos"] == Vector2(700, 300),
				"an on-screen target should be drawn where it projects"):
			return false

		# in front but off the right of the screen: pinned to the edge, still
		# out to the right, so it points the way you have to turn
		var off: Dictionary = MARKER.place_marker(Vector2(2400, 360), false, rect)
		if not _check(not off["on_screen"], "a target off the screen is not on screen"):
			return false
		var off_pos: Vector2 = off["pos"]
		if not _check(rect.has_point(off_pos), "a clamped star must stay on screen: %s" % off_pos):
			return false
		if not _check(off_pos.x > center.x, "a target off to the right belongs on the right"):
			return false

		# BEHIND you and to the right. Godot's unprojection of a point behind
		# the camera lands mirrored through the centre — taken at face value the
		# star would sit on the LEFT while the thing is over your right
		# shoulder, and following it would turn you the long way round.
		var behind: Dictionary = MARKER.place_marker(Vector2(400, 360), true, rect)
		if not _check(not behind["on_screen"], "a target behind you is never on screen"):
			return false
		if not _check(behind["pos"].x > center.x,
				"a target behind-right belongs on the right edge, not %s" % behind["pos"]):
			return false

		# dead behind: no direction to point, but it still has to be ON the
		# screen rather than at some infinity
		var dead: Dictionary = MARKER.place_marker(center, true, rect)
		if not _check(rect.has_point(dead["pos"]),
				"a target dead behind you must still be drawn somewhere sane"):
			return false
		return true

	# ---------------- who decides what you are on ----------------

	func _quest_state(tree: SceneTree, pawn: Node3D) -> bool:
		var tracker: Node = _tracker(tree)
		if not _check(tracker != null, "the HUD has no quest heading"):
			return false

		# 1. a fresh player is on nothing, and the heading is not up
		if not _check(str(GameStats.quest) == "", "a new player should have no quest"):
			return false
		if not _check(not tracker.visible, "the heading should be hidden with no quest"):
			return false

		# 2. the world really does anchor this quest's target — the group is set
		# on the bandit camp in world.tscn, so a renamed group fails here rather
		# than silently drawing no star in the game
		if not _check(QuestData.target_pos(tree, QUEST) != null,
				"nothing in the world wears the '%s' target group" % QUEST):
			return false

		# 3. a quest that does not exist is refused
		Net.request_cheat_quest("no_such_quest")
		await tree.physics_frame
		if not _check(str(GameStats.quest) == "", "an unknown quest should be refused"):
			return false

		# 4. asking for a real one from the far side of the island is refused:
		# the conversation is local, so standing at the NPC is the one part of
		# it the server can check
		var npc := _quest_giver(tree)
		if not _check(npc != null, "the quest giver is not in the world"):
			return false
		_place(pawn, npc.global_position + Vector3(80, 0, 0))
		await tree.physics_frame
		Net.request_start_quest(QUEST)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == "",
				"a quest should not be handed to a pawn nowhere near the giver"):
			return false

		# 5. walk up to them and it is granted
		_place(pawn, npc.global_position + Vector3(1.0, 0, 0))
		await tree.physics_frame
		Net.request_start_quest(QUEST)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == QUEST,
				"standing at the giver should have granted the quest"):
			return false
		if not _check(tracker.visible, "the heading should be up while on a quest"):
			return false
		if not _check(str(tracker._label.text) == QuestData.label(QUEST),
				"the heading shows '%s', expected the quest's name" % tracker._label.text):
			return false

		# 6. and it can be dropped again
		Net.request_cheat_quest("")
		await tree.physics_frame
		if not _check(str(GameStats.quest) == "", "clearing should leave no quest"):
			return false
		if not _check(not tracker.visible, "the heading should go away with the quest"):
			return false

		print("QUESTTEST target=", QuestData.target_pos(tree, QUEST))
		return await _king_quest(tree, pawn)

	## The hand-off the tutorial makes, and handing it back in at the other end.
	func _king_quest(tree: SceneTree, pawn: Node3D) -> bool:
		var quest := TutorialData.NEXT_QUEST
		if not _check(quest != "" and QuestData.has(quest),
				"the tutorial's follow-up quest '%s' is not in the catalogue" % quest):
			return false
		# the King has to actually be standing in the world, or graduating hands
		# out a quest whose star points at nothing
		if not _check(QuestData.target_pos(tree, quest) != null,
				"nothing in the world wears quest '%s's target group" % quest):
			return false
		var at := QuestData.done_at(quest)
		var npc := _npc_with(tree, at)
		if not _check(npc != null, "the NPC this quest ends at ('%s') is not in the world" % at):
			return false
		if not _check(DialogData.has(at), "the NPC this quest ends at has nothing to say"):
			return false

		# 1. the server puts you on it, the way the tutorial does on graduating
		Net.server_grant_quest(1, quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == quest,
				"the server should be able to hand out the follow-up quest"):
			return false

		# 2. handing it in from across the island does nothing: the conversation
		# is local, so standing there is the half the server can check
		_place(pawn, npc.global_position + Vector3(60, 0, 0))
		await tree.physics_frame
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == quest,
				"a quest should not hand in from 60 m away"):
			return false

		# 3. and it does at his feet, and it pays
		var purse := int(GameStats.coins)
		var reward := QuestData.reward_gold(quest)
		if not _check(reward > 0, "the King's quest should pay something"):
			return false
		_place(pawn, npc.global_position + Vector3(1.5, 0, 0))
		await tree.physics_frame
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == "",
				"talking to him at his feet should have finished the quest"):
			return false
		if not _check(int(GameStats.coins) == purse + reward,
				"finishing should have paid %d, purse went %d -> %d"
						% [reward, purse, GameStats.coins]):
			return false
		# the point of the reward: it covers a first sword at ItemDb's price
		if not _check(int(GameStats.coins) >= ItemDb.buy_price("wooden_sword"),
				"the reward should cover a wooden sword"):
			return false

		# 4. and handing in a quest you are not on changes nothing — least of
		# all paying again, which is what "the FIRST time you talk to him" means
		var paid := int(GameStats.coins)
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == "",
				"finishing a quest you are not on should do nothing"):
			return false
		if not _check(int(GameStats.coins) == paid,
				"handing in twice paid twice: %d -> %d" % [paid, GameStats.coins]):
			return false

		print("QUESTTEST king=", npc.global_position)
		return await _kill_count(tree)

	## The King's follow-up: a quest that counts kills AND is reported back. The
	## count belongs to the SERVER — a client saying it has killed twenty-five
	## bandits has said nothing at all.
	func _kill_count(tree: SceneTree) -> bool:
		var quest := "kill_bandits"
		var needed := QuestData.kills_needed(quest)
		if not _check(needed > 0, "'%s' should be a counting quest" % quest):
			return false
		var tracker: Node = _tracker(tree)

		# 1. kills while on no quest count towards nothing
		Net.request_cheat_quest("")
		await tree.physics_frame
		Net.server_record_enemy_kill("Bandit_ghost", 1)
		await tree.physics_frame
		if not _check(GameStats.quest_kills == 0,
				"a kill with no quest should not be counted"):
			return false

		# 2. on the quest, every kill moves the count, and the heading with it
		Net.server_grant_quest(1, quest)
		await tree.physics_frame
		if not _check(GameStats.quest_kills == 0, "a fresh quest starts at zero"):
			return false
		for i in 3:
			Net.server_record_enemy_kill("Bandit_%d" % i, 1)
		await tree.physics_frame
		if not _check(GameStats.quest_kills == 3,
				"three kills should read 3, not %d" % GameStats.quest_kills):
			return false
		if not _check(str(tracker._label.text) == QuestData.progress_label(quest, 3),
				"the heading reads '%s', expected the count with it" % tracker._label.text):
			return false

		# 3. taking a different quest starts from scratch, so kills never carry
		# over from the quest before
		Net.request_cheat_quest("bandit_camp")
		await tree.physics_frame
		if not _check(GameStats.quest_kills == 0,
				"switching quest should reset the count"):
			return false

		# 4. the last kill TURNS THE QUEST ROUND rather than finishing it: this
		# one has a `done_at`, so the King is owed an answer
		Net.server_grant_quest(1, quest)
		await tree.physics_frame
		for i in needed - 1:
			Net.server_record_enemy_kill("Bandit_run_%d" % i, 1)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == quest,
				"one kill short should still be on the quest"):
			return false
		Net.server_record_enemy_kill("Bandit_last", 1)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == quest,
				"the %dth kill should have kept the quest, not cleared it" % needed):
			return false
		if not _check(GameStats.quest_kills == needed,
				"the count should read %d, not %d" % [needed, GameStats.quest_kills]):
			return false
		if not _check(tracker.visible, "the heading should still be up, pointing home"):
			return false
		# ...and the HUD says so: the heading is the walk back, and the star has
		# turned round to the King instead of still pointing at an empty camp
		if not _check(str(tracker._label.text) == QuestData.progress_label(quest, needed),
				"the heading still reads the count: '%s'" % tracker._label.text):
			return false
		if not _check(not str(tracker._label.text).contains("/"),
				"a counted-out quest should not still read a tally: '%s'" % tracker._label.text):
			return false
		var home: Variant = QuestData.target_pos(tree, quest, needed)
		var camp: Variant = QuestData.target_pos(tree, quest, 0)
		if not _check(home != null and camp != null and home != camp,
				"the star should have turned round to the quest's `done_target`"):
			return false
		return await _report_back(tree, quest, needed)

	## Walking it back to the King. Everything the server can check is checked
	## here: the count, and that the pawn is really at him.
	func _report_back(tree: SceneTree, quest: String, needed: int) -> bool:
		var tracker: Node = _tracker(tree)
		var npc := _npc_with(tree, QuestData.done_at(quest))
		if not _check(npc != null, "the NPC '%s' ends this quest is not in the world"
				% QuestData.done_at(quest)):
			return false
		var pawn: Node3D = tree.get_nodes_in_group("local_player")[0]

		# 1. from across the town it does nothing, same as any other hand-in
		_place(pawn, npc.global_position + Vector3(60, 0, 0))
		await tree.physics_frame
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == quest,
				"a counted-out quest should not hand in from 60 m away"):
			return false

		# 2. at his feet it does
		_place(pawn, npc.global_position + Vector3(1.5, 0, 0))
		await tree.physics_frame
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == "",
				"reporting in at the King should have finished the quest"):
			return false
		if not _check(not tracker.visible, "the heading goes away with the quest"):
			return false

		# 3. THE ONE THAT MATTERS: the answer offering the hand-in lives in a
		# LOCAL conversation, so a patched client can pick it whenever it likes.
		# Standing in front of him with no bandits killed must buy nothing.
		Net.server_grant_quest(1, quest)
		await tree.physics_frame
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == quest,
				"the King took a report of %d kills from a player with 0" % needed):
			return false
		# ...and one short is still short
		for i in needed - 1:
			Net.server_record_enemy_kill("Bandit_short_%d" % i, 1)
		await tree.physics_frame
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == quest,
				"the King took a report one kill short of %d" % needed):
			return false
		Net.request_cheat_quest("")
		await tree.physics_frame

		print("QUESTTEST kill count=", needed)
		return await _catacombs(tree)

	## The quest the Knight beside the throne hands over the moment the bandits
	## are reported in. Its PLACE is not built yet, which is a normal state — so
	## what is checked is the part that does exist: he is really standing in the
	## world with that dialog_id, and the dialog really offers it.
	func _catacombs(tree: SceneTree) -> bool:
		var quest := "clear_catacombs"
		if not _check(QuestData.has(quest), "'%s' is not in the catalogue" % quest):
			return false
		var giver := QuestData.giver(quest)
		var knight := _npc_with(tree, giver)
		if not _check(knight != null,
				"the Knight who gives '%s' ('%s') is not in the world" % [quest, giver]):
			return false
		if not _check(DialogData.has(giver), "the Knight has nothing to say"):
			return false

		# He is offered inside the KING's conversation ("Now that I think of
		# it..."), and the server checks you are standing at the giver — so the
		# two of them have to be close enough that being at one is being at the
		# other, or taking the quest silently does nothing.
		var king := _npc_with(tree, "king")
		if not _check(king != null, "the King is not in the world"):
			return false
		var apart := king.global_position.distance_to(knight.global_position)
		var reach: float = float(knight.interact_range) + Net.SHOP_RANGE_SLACK
		var talk: float = float(king.interact_range)
		if not _check(apart + talk <= reach,
				"the Knight is %.1f m from the King: standing at the King can be %.1f m from him, past his %.1f m reach"
						% [apart, apart + talk, reach]):
			return false

		# and it really is granted from there
		var pawn: Node3D = tree.get_nodes_in_group("local_player")[0]
		_place(pawn, king.global_position + Vector3(0, 0, 1.0))
		await tree.physics_frame
		Net.request_start_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == quest,
				"the Knight should hand '%s' over to a pawn stood at the throne" % quest):
			return false
		print("QUESTTEST knight=", apart, "m from the King")
		return true

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

	func _quest_giver(tree: SceneTree) -> Node3D:
		return _npc_with(tree, QuestData.giver(QUEST))

	func _tracker(tree: SceneTree) -> Node:
		var found := tree.root.find_children("*", "QuestTracker", true, false)
		return found[0] if found.size() > 0 else null
