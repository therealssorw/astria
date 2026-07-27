# Astria — Godot 4.7 third-person action game

## This file is written by ME, not by you (IMPORTANT)

DO NOT ADD ANYTHING TO CLAUDE.md UNLESS I ASK YOU TO, IN SO MANY WORDS. Not a
section, not a bullet, not a line in the file index, not a note about the thing
you just built. Finishing a piece of work is NOT permission to write it up here
— that is what the code's comments and the commit message are for, and this
document only stays readable if it stays mine.

"Document it" / "put it in CLAUDE.md" / "add it to the index" from me is the
only permission there is, and it covers exactly what I asked for. Everything
below is still true and still binding — including KEEP IT TRUE, which now means
TELL ME the index line a new file needs and let me say yes, not write it in.

## How to report back (IMPORTANT)

Say NOTHING until the work is finished. No preamble, no plan read back, no
narration of what is being opened or tried, no summary paragraph afterwards.

When it is done, the whole reply is a bulleted list:

- **One bullet per task.** SIX WORDS MAXIMUM in a bullet. Count them.
- Nothing else in the message. No heading, no closing line, no explanation of
  how it was done — the code and its comments are where that lives.
- Anything that has to be raised is a bullet too, in the same six words:
  "Three tests red, not mine." / "Copper armor price now mismatched." /
  "Needs a pad button: ask." A caveat still gets said; it just gets said short.

Anything longer belongs in a comment, in CLAUDE.md, or in the commit message.

## The file index (IMPORTANT)

The bottom of this file lists every file in the project and what it does. It is
loaded with this document, so it is already in front of you.

- **Go to the file, do not hunt for it.** Do not grep or glob the repo for
  something the index already names — open it directly.
- Search only for what the index does not cover: a symbol inside a file, or
  something genuinely new that is not on the list yet.
- **KEEP IT TRUE.** Adding a file means adding its line in the same commit;
  changing what a file is FOR means rewriting its line. An index that lies is
  worse than no index, because it is trusted instead of checked.

## Before you write anything (IMPORTANT)

Three questions, asked BEFORE the first line and not after the last one. They
are cheap at the start and expensive to retrofit.

**1. What is missing from the plan?** The thing asked for is rarely the whole of
the thing. Read the code it lands in first, then write down what has to be true
for it to actually work — and what the request implies but does not say. Half the
work in this file exists because that question got asked: "play this animation as
the screen fades" needed a way to put a clip on a body the pawn has no STATE for
(`play_scripted`), or `tick()` would have replaced it before its first frame was
drawn; "let me scroll the hotbar" needed the whole selection moved off polling,
because a wheel press and its release land in the same frame. If a step of the
plan turns out to be wrong mid-way, say so and carry on with the rest — do not
quietly shrink the job.

**2. What quality of life can go in that the PLAYER never sees?** This is the
invisible half, and it is not optional:

- **Something to judge it by.** Anything visual gets a `tests/preview_*.tscn`
  that renders it and saves a PNG. Every visual bug in this project's history was
  invisible to assertions and obvious in a screenshot — the T-posed NPCs, the
  popup hanging off the left edge, the mic glyph drawn off the bottom of a 0x0
  control, an NPC talking to you with its back turned.
- **A test that would catch it breaking**, checked against the SERVER's copy of
  the truth rather than the screen's.
- **A safe fallback.** A missing texture must not take a screen down
  (`UiTheme.sheet()` paints a flat shade), a character without a clip must not
  error (`play_scripted` returns 0.0 and the caller carries on), a missing
  microphone is a normal state.
- **One dial instead of a magic number**, named and commented with what moves
  when you turn it — `POPUP_DROP`, `VoiceCodec.RATE`, `FRAME_SPRING_PER_METRE`.
  Better still, derive it: the intro's fade is the LENGTH OF THE CLIP, so
  retrimming the animation retimes the wake-up and nothing has to be kept in
  sync by hand.
- **Print the measurement next to the result** in a test, not just PASS.

**3. What can be added without changing the idea?** Fill out the obvious edges of
the thing that was asked for. An inventory is a thing you DRAG in; a list is a
thing you scroll; a control that exists on a keyboard has a pad equivalent (ask
which button — see Controls); a panel opens AND closes AND says what it wants.
The test is whether a player would call it part of the same feature or a
different one. Making the requested thing complete is the job; bolting a second
feature onto it is not, and neither is quietly widening the scope — if something
bigger is worth doing, do the asked-for work and say so.

## Everything is a system (IMPORTANT)

Write it ONCE, in ONE place, and make the second use free. If a thing is done
twice, it becomes a table row or a shared function — not a copy with two lines
changed. The measure of a feature here is how cheap the NEXT one of its kind is.

- **A feature is a table plus the code that walks it.** The lesson is
  `TutorialData.STEPS`, the quests are `QuestData.QUESTS`, the items are
  `ItemDb.ITEMS`, the conversations are `DialogData.DIALOGS`, the shops are
  `ShopData.SHOPS`, the animations are `HumanoidVisual.CLIPS`, the places are
  `TeleportData.DESTINATIONS`. Adding a quest, a step, an item, an NPC's
  conversation or a shop is ONE ROW AND NO NEW CODE — no per-quest UI, no
  per-NPC script. If a new feature cannot be added by editing data, it is not
  finished.
- **One owner per fact, and everything else asks it.** `UiTheme` owns the
  palette, `ItemDb` owns prices, `CombatLevels` owns the damage curve,
  `Net.voice_targets` owns who can hear you, `InventoryUI._on_slot_drop` owns
  what a drop means, `InputDevice.is_menu_accept` owns what confirms a menu.
  Two files holding the same number will drift; six screens each inventing their
  own black is exactly how the palette got written.
- **Generalise the MECHANISM, not the case.** `play_scripted` is "put a clip on
  a body that has no state for it", not "play the getting-up".
  `TutorialArena.wave_spawns` is "put a wave in front of someone", not "put the
  reinforcements down". Name it for the job, and the second caller costs nothing.
- **Prefer measuring to being told.** `NpcCharacter` measures its own ground
  speed and animates itself, so anything that MOVES an NPC gets the walk for free
  with no code at the other end. `NpcInteractable` measures the body it hangs off
  rather than trusting a hard-coded height, so a 2.40 m King and a 1.85 m
  villager both frame correctly.
- **A name, never a coordinate.** Quest targets, teleport destinations and spawns
  are nodes in a group (`quest_<id>`, `teleport_<id>`, `spawn_point`), so moving
  the thing in the editor moves the feature with it.
- **Leave an escape hatch** for the case the system does not cover — a per-slot
  "Adjust placement" in the NPC Builder, `patience` overriding `GATE_PATIENCE` on
  one gate — and give the rule a default so the hatch is rarely needed.
- **Two layouts of the same thing both have to keep working.** Code that reaches
  for a sibling or a parent should cope with either arrangement and say which it
  found; `NpcInteractable._body_node()` is the pattern.

## Server authority (IMPORTANT)

Everything that can be server-side must be server-side. The client is never
trusted. Treat every message from a client as a *request* to be validated, not
a fact to be applied.

Rules for any new feature:

- If it changes game state — health, stamina, currency, items, quests, kills,
  progression, anything a player could gain by cheating — the server owns the
  variable, the server mutates it, and clients get a replicated read-only copy.
  Never write it locally "and tell the server after".
- A client asks (`sv_*` RPC); the server checks *everything* it could lie
  about: does the thing exist, is the price the server's price, can it afford
  it, does it hold it, is its pawn actually close enough, is it alive, is it
  allowed. Then the server applies it and pushes the new state back (`cl_*`).
- Private state (a purse, a bag) goes only to its owner — strip it from
  anything broadcast to every peer.
- Never derive a check from a value the client supplied. Positions come from
  the server's own copy of the pawn (which is already speed-validated), not
  from whatever the client claims in the request.
- The UI never applies a change optimistically. It asks, then redraws when the
  server answers. That way a patched client can only lie to its own screen.

"Within reason" means purely cosmetic, per-player things stay local, because
faking them gains nothing: which dialog line is on screen, whether the NPC
prompt is drawn, the inventory panel being open, camera and animation state.
If in doubt about whether something is cosmetic, put it on the server.
