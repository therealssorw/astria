extends Node
## Autoload: Quests. Hooks conversations up to the server's quest state, the way
## `ShopSystem` hooks them up to shops — a dialog answer carrying
## `"action": "start_quest:<id>"` puts the player on that quest, and no NPC
## needs a line of code of its own.
##
## It only ASKS. The server owns which quest you are on (`Net.players[id].quest`
## -> `GameStats.quest`) and hands it over only if your pawn is really standing
## at the NPC that gives it out, so this file cannot put anyone on a quest by
## itself — which is the whole point of it being this small.

## Prefix of the dialog action that starts a quest, e.g. "start_quest:hunt".
const START_ACTION := "start_quest:"
## And the one that hands it in, on the answer that ends the conversation with
## whoever the quest sent you to.
const FINISH_ACTION := "finish_quest:"

func _ready() -> void:
	DialogSystem.action_triggered.connect(_on_dialog_action)

func _on_dialog_action(_dialog_id: String, action: String) -> void:
	if action.begins_with(START_ACTION):
		_start(action.substr(START_ACTION.length()))
	elif action.begins_with(FINISH_ACTION):
		_finish(action.substr(FINISH_ACTION.length()))

func _start(quest_id: String) -> void:
	if not _known(quest_id):
		return
	if str(GameStats.quest) == quest_id:
		return # already on it — asking again would just cost a round trip
	Net.request_start_quest(quest_id)

func _finish(quest_id: String) -> void:
	if not _known(quest_id):
		return
	if str(GameStats.quest) != quest_id:
		return # not on it, so there is nothing to hand in
	Net.request_finish_quest(quest_id)

func _known(quest_id: String) -> bool:
	if QuestData.has(quest_id):
		return true
	push_warning("Quests: no quest named '%s'" % quest_id)
	return false
