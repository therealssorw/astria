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
	# The intro cutscene talks to nobody: IntroCutscene plays these two on its
	# own, the first over the black screen and the second once the island has
	# faded up. They are separate conversations because the fade happens
	# BETWEEN them — the cutscene waits for the first to close.
	"intro_wake": {
		"start": "ugh",
		"lines": {
			"ugh": {
				"text": "Ugh.\nmy head feels awful",
				"auto": 1.8,
				"goto": END,
			},
		},
	},
	"intro_where": {
		"start": "where",
		"lines": {
			"where": {
				"text": "where even am I?",
				"auto": 2.0,
				"goto": END,
			},
		},
	},
	# --- tutorial ---
	# The step table in scripts/world/tutorial/tutorial_data.gd names these and
	# nothing else does, so rewriting a "text" below rewrites the tutorial
	# without touching a line of code. Keep the "auto" beats (they are what
	# makes a line play by itself while the lesson waits) and keep each id, or
	# the step that asks for it will find nothing to say.
	#
	# The four teaching lines are the player's own head — no speaker — and name
	# their buttons in the text. The prompt drawn under them names the same
	# button for whichever device is in use, so a pad player is never left
	# reading about a mouse.
	"tut_attack": {
		"start": "line",
		"lines": {
			"line": {
				"text": "He's punching me. Let me fight back (Left Click or R2 on controller)",
				"auto": 1.6,
				"goto": END,
			},
		},
	},
	"tut_block": {
		"start": "line",
		"lines": {
			"line": {
				"text": "I think I remember how to block (Right Click or L2 on controller)",
				"auto": 1.6,
				"goto": END,
			},
		},
	},
	"tut_lock_on": {
		"start": "line",
		"lines": {
			"line": {
				"text": "My eyes are getting better, let me focus on him (Middle Mouse button or R3 to lock target)",
				"auto": 1.6,
				"goto": END,
			},
		},
	},
	"tut_heavy": {
		"start": "line",
		"lines": {
			"line": {
				"text": "Let me give him a real hard hit (Hold Attack for Heavy)",
				"auto": 1.6,
				"goto": END,
			},
		},
	},
	# The first thing anyone says to you, straight after "where even am I?" —
	# and the answer to it: this is who put you on the ground.
	"tut_taunt": {
		"speaker": "Bandit",
		"start": "line",
		"lines": {
			"line": {
				"text": "Still not down, huh?",
				"auto": 1.5,
				"goto": END,
			},
		},
	},
	# ...and its friends arriving once it is beaten.
	"tut_reinforcements": {
		"speaker": "Bandit",
		"start": "line",
		"lines": {
			"line": {
				"text": "This one's a fighter.\nDon't worry, we'll put you down.",
				"auto": 1.6,
				"goto": END,
			},
		},
	},
	# The villager who walks over once the raid is beaten. This is the hand-off
	# to the mayor — the mayor's own conversation is not written yet.
	"tut_mayor": {
		"speaker": "Villager",
		"start": "alright",
		"lines": {
			"alright": {
				"text": "Are you alright?",
				"answers": [
					{"text": "Yes — it's just my head.", "goto": "standing"},
				],
			},
			"standing": {
				"text": "You look way better than you should be after taking out those thugs.",
				"answers": [
					{"text": "Who even were they?", "goto": "thugs"},
					{"text": "What should I do now?", "goto": "mayor"},
				],
			},
			# back to the question it was asked from, so the other one is still
			# there to ask
			"thugs": {
				"text": "They're thugs who keep raiding our village.\nSadly, I'm sure they'll come back.",
				"goto": "standing",
			},
			"mayor": {
				"text": "Head to the Mayor's office. I'm sure he'll reward you for this fight.",
				"answers": [
					{"text": "Sounds good!", "goto": END},
				],
			},
		},
	},
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
				"text": "From the old mine east of the ridge — or I did, before the bandits made a camp of it. Now I melt down whatever the tide brings in.",
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
