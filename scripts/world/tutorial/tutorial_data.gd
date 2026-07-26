class_name TutorialData
extends RefCounted
## The tutorial script, and where the per-player copies of the island live.
## Changing the lesson is changing this table — `tutorial_system.gd` only walks
## it, and nothing else in the game knows what step 3 is.
##
## Every step is one dictionary with a "kind":
##
##   "wait_ready" — hold until that player's client says the intro cutscene is
##                  over. Nothing moves before the player can see.
##   "wave"       — spawn `count` bandits around the spawn, switched on to that
##                  step's `ai` level.
##   "gate"       — teach ONE button. Its `dialog` plays first (see DialogData),
##                  then the prompt goes up and the step waits until the player
##                  really does it. `action` is the input map name; the server
##                  watches for the real thing (a swing, a raised guard) rather
##                  than believing a "I pressed it" message, except where it
##                  cannot see it — those carry `client_gate: true`, and the
##                  worst a patched client wins there is skipping its own
##                  lesson.
##   "clear"      — no prompt, no pause: fight. Ends when every bandit spawned
##                  so far is dead.
##   "talk"       — a villager walks over and talks (the mayor hand-off). Ends
##                  when the conversation closes.
##   "end"        — out of the copy and onto the real island; it is torn down.
##
## Every step carries an `ai` level that says how much of the bandits is
## switched on for it (see Enemy.Hold):
##
##   "attacker" — rooted, punching once every three seconds and nothing else.
##   "still"    — a training dummy: it does not move, turn or swing.
##   "full"     — an ordinary bandit, everything on.
##
## That ladder IS the lesson. A fight is built one piece at a time: you meet a
## bandit that can only punch and learn to block it, it stops dead and you
## learn to hit it back, then it wakes all the way up for a straight duel, and
## only when that is won does the rest of the raid arrive. A step never teaches
## a button against an enemy doing something else at the same time.
##
## `patience` (seconds) overrides GATE_PATIENCE for one gate — the block gate
## uses it, because there a lesson nobody answers is also a lesson that is
## hitting you.

## Scene instanced once per player in the tutorial: a copy of the starter
## island, spawn marker and all.
const ARENA_SCENE := preload("res://scenes/world/tutorial/tutorial_arena.tscn")

## Copies sit in a row far to the east, at the island's OWN height — the ocean
## follows the local player and the distance fog is measured from the camera,
## so a copy down here has water and horizon exactly like home, where one
## parked in the sky would have neither. This is the "cloned world": one
## physics space, but a private island each, well past fog range from the real
## one and from each other.
const SLOT_ORIGIN := Vector3(4000.0, 0.0, 0.0)
const SLOT_SPACING := 3000.0
## Beyond this many at once, the newest player waits on the island instead.
## Deliberately small: a copy is a whole island's worth of trimesh collision,
## generated when it is built (see tutorial_arena.gd).
const MAX_SLOTS := 4

## A gate that has been up this long gives in: the fight starts moving again
## and the lesson carries on. Nothing about a tutorial is worth being stuck in
## front of forever — a player who cannot find the button (or who wandered off,
## or cheated themselves out of the city) must never end up staring at bandits
## frozen in place with no way out.
## (A `static var` so the test can turn it down; nothing in the game writes it.)
static var GATE_PATIENCE := 25.0

const STEPS := [
	{"id": "wake", "kind": "wait_ready"},

	# ONE bandit for the whole lesson, switched on a piece at a time.
	# First it can only punch, on a slow count — so the first thing you are
	# taught is the answer to it.
	{"id": "first_bandit", "kind": "wave", "count": 1, "ai": "attacker"},
	{"id": "teach_block", "kind": "gate", "action": "block", "dialog": "tut_block",
			"ai": "attacker", "patience": 14.0},

	# now it stops dead and lets you learn what to do back
	{"id": "teach_attack", "kind": "gate", "action": "attack", "dialog": "tut_attack",
			"ai": "still"},
	{"id": "teach_heavy", "kind": "gate", "action": "attack_heavy", "dialog": "tut_heavy",
			"ai": "still"},
	{"id": "teach_lock_on", "kind": "gate", "action": "lock_on", "dialog": "tut_lock_on",
			"client_gate": true, "ai": "still"},

	# everything it knows, one on one, with no interruptions left
	{"id": "duel", "kind": "clear", "ai": "full", "dialog": "tut_duel",
			"banner": "One on one. Finish him."},

	# and only then the rest of the raid
	{"id": "reinforcements", "kind": "wave", "count": 3, "ai": "full",
			"dialog": "tut_reinforcements"},
	{"id": "clear_raid", "kind": "clear", "ai": "full", "banner": "Drive them out."},

	{"id": "mayor", "kind": "talk", "dialog": "tut_mayor"},
	{"id": "leave", "kind": "end"},
]

## Where player `slot`'s copy of the city sits.
static func slot_origin(slot: int) -> Vector3:
	return SLOT_ORIGIN + Vector3(float(slot) * SLOT_SPACING, 0.0, 0.0)

static func step_count() -> int:
	return STEPS.size()

static func step(i: int) -> Dictionary:
	if i < 0 or i >= STEPS.size():
		return {}
	return STEPS[i]

static func index_of(step_id: String) -> int:
	for i in STEPS.size():
		if str(STEPS[i]["id"]) == step_id:
			return i
	return -1

## Short line under the prompt telling you what the button is FOR. The button
## itself is drawn from the input map, so this never names a key.
static func gate_hint(step_id: String) -> String:
	match step_id:
		"teach_attack":
			return "Swing"
		"teach_block":
			return "Hold to guard"
		"teach_lock_on":
			return "Lock on"
		"teach_heavy":
			return "A heavy swing — tapping it only jabs"
	return ""

## How much of a bandit a step switches on.
static func hold_for(step: Dictionary) -> Enemy.Hold:
	match str(step.get("ai", "full")):
		"still":
			return Enemy.Hold.STILL
		"attacker":
			return Enemy.Hold.ATTACKER
	return Enemy.Hold.NONE

## How long this gate waits before giving in and moving the lesson on.
static func patience(step: Dictionary) -> float:
	return float(step.get("patience", GATE_PATIENCE))

## True when the button has to be HELD, not tapped. The prompt says so in the
## button itself, because a tap and a hold are the same button here and a
## player who taps gets a light punch and no idea why nothing happened.
static func gate_is_hold(action: String) -> bool:
	return action in ["attack_heavy", "block"]

## Input action whose button glyph the prompt draws. "attack_heavy" is not a
## binding of its own — a heavy is the attack button held down — so the glyph
## comes from `attack` and the hint says to hold it.
static func gate_action_binding(action: String) -> String:
	return "attack" if action == "attack_heavy" else action
