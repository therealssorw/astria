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
##
##       # Optional. Opens somewhere ELSE until a gift has been taken:
##       #   "first_time": {"line": "greet_once", "until_gift": "some_gift"},
##       # which is how an NPC says something the first time you walk up to them
##       # and never again. The condition is the SERVER's record of who has been
##       # given what (GiftData -> GameStats.gifts), not anything this screen
##       # remembers, so it survives a reconnect and cannot be faked into a
##       # second helping. The line it names still lives in "lines" like any
##       # other, and reaching it by `goto` works as normal.
##
##       # Optional. Opens somewhere else while the player is on a quest whose
##       # count has been made and is walking it back to this NPC:
##       #   "when_quest_done": {"line": "so", "quest": "kill_bandits"},
##       # It is the same idea and the same rule — the count is the SERVER's
##       # (GameStats.quest / .quest_kills mirror it), so a patched client can
##       # only talk its OWN screen into the wrong greeting. Reporting in beats
##       # "first_time" when both apply.
##       "lines": {
##           "line_id": {
##               "text": "What the NPC says.",
##               # Optional, for a scene with two people in it: the name over
##               # the box for THIS line, and the `dialog_id` of whoever in the
##               # world is saying it so the camera turns to them.
##               "speaker": "Knight",
##               "speaker_at": "knight",
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
## The ones wired up today are "open_shop" (opens the shop registered under this
## NPC's id in ShopData), "start_quest:<id>" / "finish_quest:<id>" (QuestData),
## and "take_gift:<id>" (GiftData). Every one of them only ASKS — the server
## decides, and checks you are really standing at the NPC.

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
				"text": "Ugh.
my head feels awful",
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
	# The tutorial TEACHES with popups (TutorialData.STEPS) and TALKS with
	# these: the bandit that put you on the ground, its friends arriving, and
	# the villager afterwards. The step table names them and nothing else does.
	#
	# The first thing anyone says to you, straight after "where even am I?" —
	# and the answer to it: this is who put you down.
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
				"text": "This one's a fighter.
Don't worry, we'll put you down.",
				"auto": 1.6,
				"goto": END,
			},
		},
	},
	# The villager who walks over once the raid is beaten, and hands you on.
	"tut_mayor": {
		"speaker": "Villager",
		"start": "alright",
		"lines": {
			"alright": {
				"text": "Are you alright?",
				"answers": [
					{"text": "Yes, it's just my head.", "goto": "standing"},
				],
			},
			"standing": {
				"text": "You look way better than you should be after taking out those thugs.\nI'm surprised you're even standing.",
				"answers": [
					{"text": "Who even were they?", "goto": "thugs"},
					{"text": "What should I do now?", "goto": "mayor"},
				],
			},
			# back to the question it was asked from, so the other one is still
			# there to ask
			"thugs": {
				"text": "They're the thugs who keep raiding our village.\nI'm sure they'll be back.",
				"goto": "standing",
			},
			"mayor": {
				"text": "Head to the King.\nTell him what just happened so he knows everything is safe.",
				"answers": [
					{"text": "Sounds good!", "goto": END},
				],
			},
		},
	},
	"blacksmith": {
		"speaker": "Bram, the Blacksmith",
		"start": "greeting",
		# The first time you walk up to Bram he has something for you; every time
		# after that he opens on the shop greeting like anyone else. What "the
		# first time" means is the SERVER's record of whether the armor has been
		# handed over, not anything this screen remembers — so it survives a
		# reconnect, and clearing it locally earns nothing.
		"first_time": {"line": "gift", "until_gift": "blacksmith_armor"},
		"lines": {
			# Taking it comes back to the greeting rather than closing the box:
			# he has just been handed a reason to talk to you, and the shop is
			# the next thing you want.
			"gift": {
				"text": "Good work out there beating the bandits up.\nHere\nI have a pair of old armor\nYou deserve it for what you did",
				"answers": [
					{"text": "Thank you.", "goto": "greeting",
							"action": "take_gift:blacksmith_armor"},
				],
			},
			"greeting": {
				"text": "What can I do for ya",
				"answers": [
					{"text": "Show me your goods (Buy)", "goto": END, "action": "open_shop"},
					{"text": "I'm gonna leave now", "goto": "farewell"},
				],
			},
			"farewell": {
				"text": "Suit yourself",
				"goto": END,
			},
		},
	},
	# The first thing the island asks of you: the tutorial hands out
	# "speak_to_king" as it puts you ashore, and the star leads you here. The
	# answer that reports in carries `finish_quest`, which is only a REQUEST —
	# the server checks you are actually standing in front of him.
	"king": {
		"speaker": "The King",
		"start": "greeting",
		# Walk back with the 25 bandits done and he does not ask what you want —
		# he asks "So?". The condition is the SERVER's count (GameStats.quest /
		# .quest_kills are its mirrors), and the answer under it only ASKS to
		# hand the quest in; the server checks the tally and that you are really
		# standing here before it agrees.
		"when_quest_done": {"line": "so", "quest": "kill_bandits"},
		"lines": {
			"so": {
				"text": "So?",
				"answers": [
					{"text": "I did it.", "goto": "service",
							"action": "finish_quest:kill_bandits"},
				],
			},
			"service": {
				"text": "Very well.\nI hope this means we no longer have to deal with them.\nThank you for your service.",
				# ENDS HERE while the catacombs are being built. The Knight's offer
				# below is still written and still correct — it is just nothing's
				# `goto` any more, so no conversation reaches it and the quest
				# cannot be taken. Point this back at "catacombs" to hand it out
				# again, and put the place back in world.tscn at the same time.
				"goto": END,
			},
			# The Knight standing beside the throne cuts in. A line may name its
			# own speaker, and `speaker_at` is the dialog_id of who in the WORLD
			# is saying it, so the camera turns to him and back afterwards — see
			# DialogSystem._focus_speaker. He is a real NPC you can also walk up
			# to ("knight" below); this is the same character speaking up while
			# you are already stood in front of the King.
			"catacombs": {
				"speaker": "Knight",
				"speaker_at": "knight",
				"text": "Now that I think of it. We are experiencing a bit of an overflow of the dead inside of our catacombs. If you would be willing to defeat them, I am sure we will reward you greatly.",
				"answers": [
					{"text": "I'll do it.", "goto": "good_luck",
							"action": "start_quest:clear_catacombs"},
				],
			},
			"good_luck": {
				"speaker": "Knight",
				"speaker_at": "knight",
				"text": "Very well, good luck soldier.",
				"goto": END,
			},
			"greeting": {
				"text": "Yes?\nWhat do you want?",
				"answers": [
					{"text": "I defeated the bandits.", "goto": "caravan",
							"action": "finish_quest:speak_to_king"},
				],
			},
			"caravan": {
				"text": "Ah, very well.\nThey've been a sort of a problem.\nThey recently just raided our caravan full of food and supplies, and now I am unsure if we are able to survive next season.",
				"answers": [
					{"text": "I want to help stop that.", "goto": "hideout"},
				],
			},
			# the three questions all come back here, so none of them is a dead
			# end and "I'll do it now" is always the way out — and it is the way
			# out that takes the job, so the kill count is on the HUD the moment
			# the box closes behind you
			"hideout": {
				"text": "Then you must find their hideout and defeat them for our town.\nBut first, here's some gold.\nGo to the blacksmith and buy yourself a sword.\nYou're gonna need it.",
				"answers": [
					{"text": "Where do I find them?", "goto": "rumors"},
					{"text": "During the fight I woke up with no memory. I don't even know who I am, or what village this is.", "goto": "rancor"},
					{"text": "I'll do it now.", "goto": END,
							"action": "start_quest:kill_bandits"},
				],
			},
			"rumors": {
				"text": "I've heard rumors that they're hiding alongside a mountain, but those are just rumors — I am quite honestly not sure.",
				"goto": "hideout",
			},
			"rancor": {
				"text": "You're right now in the town of Rancor.\nYour other question, I am unable to answer. All I know is we recently had a shipment of immigrants — you likely would have got here from that.",
				"goto": "hideout",
			},
		},
	},
	# The King's guard. He hands out "clear_catacombs", which is why he needs a
	# dialog_id and an NpcInteractable of his own at all: the server only gives
	# a quest to a pawn standing at the NPC that gives it out, and it finds that
	# NPC by this id. Because he stands beside the throne, taking the quest
	# inside the King's conversation passes that check too.
	"knight": {
		"speaker": "Knight",
		"start": "greeting",
		"lines": {
			"greeting": {
				"text": "Something you need, soldier?",
				"answers": [
					{"text": "What's down in the catacombs?", "goto": "dead"},
					{"text": "Nothing.", "goto": END},
				],
			},
			# back to the question it was asked from, like every other branch in
			# this file — so "Nothing." is still there as the way out
			"dead": {
				"text": "The dead, and more of them every week.\nWe seal the doors and hope. It is not a plan.",
				"goto": "greeting",
			},
		},
	},
}

static func has(dialog_id: String) -> bool:
	return DIALOGS.has(dialog_id)

static func get_conversation(dialog_id: String) -> Dictionary:
	return DIALOGS.get(dialog_id, {})
