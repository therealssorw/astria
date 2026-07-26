class_name DialogData
extends RefCounted
## All NPC conversation text lives here — this is the only file you need to
## touch to write dialog. Point an NpcInteractable's `dialog_id` at a key of
## DIALOGS and it will play that conversation.
##
## Shape of one conversation:
##
##   "some_id": {
##       "speaker": "Name shown above the text",
##       "start": "line_id",            # which line opens the conversation
##       "lines": {
##           "line_id": {
##               "text": "What the NPC says.",
##               # Either give answers the player picks between...
##               "answers": [
##                   {"text": "Player's reply", "goto": "other_line"},
##                   {"text": "Bye.", "goto": END},          # END closes the box
##                   {"text": "Buy", "goto": END, "action": "open_shop"},
##               ],
##               # ...or leave answers out and just chain with "goto",
##               # which shows a single "Continue" button.
##               #
##               # A line may also carry "auto": <seconds>, which drops the
##               # button entirely — the line waits that long after it finishes
##               # typing and then follows its "goto" by itself. That is what a
##               # cutscene monologue uses; the player can still press interact
##               # to hurry it along.
##               #
##               # A "\n" inside `text` is a PAGE BREAK, not a line break: the
##               # box types up to it, holds, then wipes and types the rest in
##               # the same box. Use it for a beat between two thoughts. Never
##               # use it to control wrapping — the box wraps by itself.
##           },
##       },
##   }
##
## `action` is optional: when the player picks that answer the dialog emits
## DialogSystem.action_triggered(dialog_id, action) so gameplay code can react.
## The one action wired up today is "open_shop", which opens the shop
## registered under this NPC's id in ShopData.

## Use as a `goto` target to end the conversation.
const END := ""

const DIALOGS := {
	"blacksmith": {
		"speaker": "Bram, the Blacksmith",
		"start": "greeting",
		"lines": {
			"greeting": {
				"text": "Careful, the coals are hot. You've the look of someone who breaks more steel than they buy. What do you need?",
				"answers": [
					{"text": "Show me what's for sale.", "goto": END, "action": "open_shop"},
					{"text": "What do you make here?", "goto": "wares"},
					{"text": "Can you repair my gear?", "goto": "repair"},
					{"text": "Nothing. Just looking around.", "goto": "farewell"},
				],
			},
			"wares": {
				"text": "Blades, mostly. Axes when the woodcutters come down the hill. Give me a day and good iron and I'll make you something that outlives you.",
				"answers": [
					{"text": "Let's trade, then.", "goto": END, "action": "open_shop"},
					{"text": "I'll keep that in mind.", "goto": "greeting"},
					{"text": "Where do you get your iron?", "goto": "iron"},
				],
			},
			"iron": {
				"text": "From the old mine east of the ridge, or I did, before the bandits made a camp of it. Now I melt down whatever the tide brings in.",
				"answers": [
					{"text": "Maybe I'll clear them out.", "goto": "bandits"},
					{"text": "Rough luck.", "goto": "greeting"},
				],
			},
			"bandits": {
				"text": "Ha! Then come back with your shield still in one piece and I'll believe you. Bring me ore and I'll forge you something worth carrying.",
				"goto": "greeting",
			},
			"repair": {
				"text": "Anything that isn't snapped clean through. Leave it on the anvil and don't touch the quench barrel.",
				"goto": "greeting",
			},
			"farewell": {
				"text": "Suit yourself. Mind the sparks on your way out.",
				"goto": END,
			},
		},
	},
}

static func has(dialog_id: String) -> bool:
	return DIALOGS.has(dialog_id)

static func get_conversation(dialog_id: String) -> Dictionary:
	return DIALOGS.get(dialog_id, {})
