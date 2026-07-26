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

		# 3. and it does at his feet
		_place(pawn, npc.global_position + Vector3(1.5, 0, 0))
		await tree.physics_frame
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == "",
				"talking to him at his feet should have finished the quest"):
			return false

		# 4. and handing in a quest you are not on changes nothing
		Net.request_finish_quest(quest)
		await tree.physics_frame
		if not _check(str(GameStats.quest) == "",
				"finishing a quest you are not on should do nothing"):
			return false

		print("QUESTTEST king=", npc.global_position)
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
