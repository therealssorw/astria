extends Node
## Autoload: Gifts. Hooks conversations up to the server's record of what each
## player has already been given, the way `Quests` hooks them up to quest state
## — a dialog answer carrying `"action": "take_gift:<id>"` asks for that gift,
## and no NPC needs a line of code of its own.
##
## It only ASKS. The server owns which gifts a player has taken
## (`Net.players[id].gifts` -> `GameStats.gifts`), hands one over only if the
## pawn is really standing at the NPC that gives it, and refuses a second
## helping — so a patched client that spams the request still gets one suit of
## armor, once.

## Prefix of the dialog action that takes a gift, e.g. "take_gift:blacksmith_armor".
const TAKE_ACTION := "take_gift:"

func _ready() -> void:
	DialogSystem.action_triggered.connect(_on_dialog_action)

func _on_dialog_action(_dialog_id: String, action: String) -> void:
	if action.begins_with(TAKE_ACTION):
		_take(action.substr(TAKE_ACTION.length()))

func _take(gift_id: String) -> void:
	if not GiftData.has(gift_id):
		push_warning("Gifts: no gift named '%s'" % gift_id)
		return
	if GameStats.gift_taken(gift_id):
		return # already had it — asking again would just cost a round trip
	Net.request_gift(gift_id)
