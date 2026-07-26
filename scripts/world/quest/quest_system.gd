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

func _ready() -> void:
	DialogSystem.action_triggered.connect(_on_dialog_action)

func _on_dialog_action(_dialog_id: String, action: String) -> void:
	if not action.begins_with(START_ACTION):
		return
	var quest_id := action.substr(START_ACTION.length())
	if not QuestData.has(quest_id):
		push_warning("Quests: no quest named '%s'" % quest_id)
		return
	if str(GameStats.quest) == quest_id:
		return # already on it — asking again would just cost a round trip
	Net.request_start_quest(quest_id)
