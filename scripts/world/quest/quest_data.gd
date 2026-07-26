class_name QuestData
extends RefCounted
## Every quest in the game, keyed by id: what it is called, what it points at,
## and who hands it out. Adding one is a single entry here plus something in the
## world wearing the matching group — the HUD marker and the cheat menu build
## themselves from this, so there is no per-quest UI code.
##
## A target is a NAME, not a coordinate, exactly like TeleportData: the marker
## reads the position off whatever is in the group at the moment it draws, so
## moving the place (or the NPC) in the editor moves the star with it. A
## coordinate written into a script goes stale the moment the level is edited.
##
## The target can be anything that is a Node3D — a `QuestAnchor` dropped at a
## place, or a character already standing in the world that joins the group in
## the scene (which is how "meet the blacksmith" points at the blacksmith
## himself rather than at a spot near him).

const QUESTS := {
	## What the tutorial hands you the moment it puts you on the island — see
	## `TutorialData.NEXT_QUEST`. Nobody gives it out (`from` is empty), so the
	## only way onto it is the server putting you there.
	"speak_to_king": {
		"name": "Speak to the King",
		"target": "king",
		"height": 2.9,
		"from": "",
		## `dialog_id` of the NPC you have to be STANDING AT to finish it. The
		## conversation is local, so this is the half the server can check.
		"done_at": "king",
		## Finishing pays enough gold to buy this, whatever ItemDb says it costs
		## today. The reward is "a first sword", not a number — writing 20 here
		## would quietly stop being a sword the moment the price moved, and
		## prices live in ItemDb alone (see "Items and shops").
		"reward_buys": "wooden_sword",
	},
	## What the King sends you off with as the conversation ends ("I'll do it
	## now."), so it is waiting on the HUD the moment you leave him.
	"kill_bandits": {
		"name": "Kill the bandits",
		"target": "bandit_camp",
		"height": 3.0,
		"from": "king",
		## Bandits to put down. A quest carrying `kills` is counted by the
		## server (`Net._credit_quest_kill`).
		"kills": 25,
		## ...and this one has a `done_at`, so the count is not the end of it:
		## the 25th bandit turns the quest round rather than clearing it, and
		## you walk back to the King to say so. The three `done_*` keys below
		## are what the HUD swaps to while it is pointing you home.
		"done_at": "king",
		"done_name": "Report back to the King",
		"done_target": "king",
		"done_height": 2.9,
	},
	## What the Knight beside the throne asks of you the moment the bandits are
	## reported in. NOTE: the catacombs are not in the level yet, so this quest
	## has no star (`target_pos` answers null, which is a normal answer here)
	## and no way to finish. When the place is built, drop a `QuestAnchor` with
	## `target_id = "catacombs"` at its door and give this entry a `kills` count
	## or a `done_at`; until then it is deliberately open-ended rather than
	## handing out a reward for walking nowhere.
	"clear_catacombs": {
		"name": "Clear out the catacombs",
		"target": "catacombs",
		"height": 2.5,
		"from": "knight",
	},
	"bandit_camp": {
		"name": "Drive off the bandits",
		"target": "bandit_camp",
		## Metres above the target's own origin to aim the star, so it floats
		## over the place instead of sitting inside it.
		"height": 3.0,
		## `dialog_id` of the NPC who gives it out. The server only hands the
		## quest over to a pawn actually standing at that NPC — see
		## `Net._server_start_quest`.
		##
		## NOTE: the blacksmith's conversation was cut down to "buy" and
		## "goodbye", so no answer offers this quest any more — the rule below
		## still holds (and test_quest walks it), but in the game only the cheat
		## menu starts it. Put an answer carrying
		## `"action": "start_quest:bandit_camp"` back in his dialog to hand it
		## out again.
		"from": "blacksmith",
	},
}

static func has(id: String) -> bool:
	return QUESTS.has(id)

## Ids in the order a menu should list them.
static func ids() -> Array:
	return QUESTS.keys()

## Name shown in the HUD heading.
static func label(id: String) -> String:
	if not QUESTS.has(id):
		return id
	return str(QUESTS[id].get("name", id))

## How many kills this quest asks for, or 0 when it is not that kind of quest.
## The server is the only thing that counts them.
static func kills_needed(id: String) -> int:
	if not QUESTS.has(id):
		return 0
	return int(QUESTS[id].get("kills", 0))

## Has the counting part been done? Only ever true for a quest that counts —
## a quest with no `kills` is never "complete", it is either on or handed in.
## The count is the SERVER's (`GameStats.quest_kills` is its mirror), so this
## is reading a decision, not making one.
static func is_complete(id: String, kills: int) -> bool:
	var needed := kills_needed(id)
	return needed > 0 and kills >= needed

## What the HUD heading reads: the name, plus "7/25" while a quest is counting,
## and the `done_name` once the counting is done and it is the walk back that is
## left. Formatting lives here so the heading has no idea which quests count.
static func progress_label(id: String, kills: int) -> String:
	var needed := kills_needed(id)
	if needed <= 0:
		return label(id)
	if is_complete(id, kills):
		return str(QUESTS[id].get("done_name", label(id)))
	return "%s  %d/%d" % [label(id), clampi(kills, 0, needed), needed]

## Group the quest's target wears. A `QuestAnchor` joins it from its own
## `_enter_tree`; a character already in the level joins it in the scene.
static func group(target: String) -> String:
	return "quest_" + target

## `dialog_id` of the NPC allowed to give this quest, or "" when nobody does —
## either because the server hands it out (the tutorial's), or because it is
## still being built and only the cheat menu can start it.
static func giver(id: String) -> String:
	if not QUESTS.has(id):
		return ""
	return str(QUESTS[id].get("from", ""))

## `dialog_id` of the NPC this quest is finished at, or "" when talking to
## somebody is not how it ends.
static func done_at(id: String) -> String:
	if not QUESTS.has(id):
		return ""
	return str(QUESTS[id].get("done_at", ""))

## Gold paid for finishing: the catalogue price of whatever `reward_buys`
## names, so the purse always covers it. 0 when the quest pays nothing.
static func reward_gold(id: String) -> int:
	if not QUESTS.has(id):
		return 0
	var buys := str(QUESTS[id].get("reward_buys", ""))
	if buys == "" or not ItemDb.has(buys):
		return 0
	return ItemDb.buy_price(buys)

## Where the star should sit, or null when this quest's target is not in the
## level — a normal answer, not an error: a quest can be written here before
## the place it points at has been built.
##
## `kills` is how far along the counting is, because a quest that has been
## COUNTED OUT points somewhere else: `done_target` is the walk home, so the
## star turns round to the King on the 25th bandit instead of still pointing at
## an empty camp. Leave it out and you get the outbound target, which is what
## the cheat menu wants when it is asking "is this quest's place in the level".
static func target_pos(tree: SceneTree, id: String, kills := 0) -> Variant:
	if not QUESTS.has(id):
		return null
	var entry: Dictionary = QUESTS[id]
	var target := str(entry.get("target", ""))
	var height := float(entry.get("height", 0.0))
	if is_complete(id, kills) and str(entry.get("done_target", "")) != "":
		target = str(entry["done_target"])
		height = float(entry.get("done_height", height))
	for node in tree.get_nodes_in_group(group(target)):
		if node is Node3D:
			return (node as Node3D).global_position + Vector3.UP * height
	return null
