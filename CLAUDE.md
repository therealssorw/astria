# Astria — Godot 4.7 third-person action game

## This file is mine, not yours (IMPORTANT)

- Never add anything here unless I ask, in words.
- Finishing work is not permission to write it up.
- That is what comments and commit messages are for.
- A new file's index line: tell me, don't write.

## How to report back (IMPORTANT)

- Say nothing until the work is done.
- No updates during the work, only after.
- No preamble, no plan read back, no narration.
- The whole reply is a bulleted list.
- One bullet per task, SIX WORDS MAXIMUM.
- Nothing else: no heading, no closing line, no explanation.
- Caveats are bullets too: "Three tests red, not mine."

## Branches (IMPORTANT)

- Everything merges into master, the dev line.
- `release` moves only when I cut a release.
- Never park work there; it never merges back.

## The file index (IMPORTANT)

- The bottom of this file lists every file.
- Go straight to the file; don't grep for it.
- Search only for symbols, or genuinely new things.
- KEEP IT TRUE: new file, new line, same commit.
- Changed purpose means the line gets rewritten.

## Before you write anything (IMPORTANT)

**1. What is missing from the plan?**

- Read the code it lands in first.
- Write down what must be true to work.
- Include what the request implies but never says.
- A wrong step: say so, finish the rest.
- Never quietly shrink the job.

**2. What quality of life can the PLAYER never see?**

- Anything visual gets a `tests/preview_*.tscn` saving a PNG.
- Screenshots catch what assertions never will.
- A test that would catch it breaking.
- Check the server's copy of truth, not the screen.
- A safe fallback: missing texture or clip never errors.
- One named, commented dial instead of a magic number.
- Better still, derive it from something already true.
- Print the measurement next to the result, not PASS.

**3. What can be added without changing the idea?**

- Fill out the obvious edges of the asked-for thing.
- Inventories drag, lists scroll, panels open and close.
- Keyboard controls get a pad equivalent — ask which button.
- Would a player call it the same feature?
- Completing it is the job; bolting on another isn't.
- Something bigger worth doing: do this, then say so.

## Everything is a system (IMPORTANT)

- Write it once, in one place, second use free.
- Done twice means a table row or shared function.
- Judge a feature by how cheap the next is.
- **A feature is a table plus code walking it.** `ItemDb.ITEMS`,
  `QuestData.QUESTS`, `DialogData.DIALOGS`, `ShopData.SHOPS`,
  `HumanoidVisual.CLIPS`, `TeleportData.DESTINATIONS`, `TutorialData.STEPS`.
- Adding one is ONE ROW AND NO NEW CODE.
- Can't be added by editing data? Not finished.
- **One owner per fact, everything else asks it.** `UiTheme`
  owns the palette, `ItemDb` prices, `CombatLevels` the damage curve,
  `Net.voice_targets` who hears you, `InputDevice.is_menu_accept` what confirms.
- Two files holding one number will drift.
- **Generalise the MECHANISM, not the case.** `play_scripted` is
  "clip on a stateless body", not "play getting-up".
- Name it for the job; second caller costs nothing.
- **Prefer measuring to being told.** `NpcCharacter` measures its
  own speed; `NpcInteractable` measures the body it hangs off.
- **A name, never a coordinate.** Targets, destinations and spawns
  are group nodes (`quest_<id>`, `teleport_<id>`, `spawn_point`).
- Moving it in the editor moves the feature.
- **Leave an escape hatch** for what the system misses.
- Give the rule a default so it's rarely needed.
- **Two layouts both keep working.** Reaching for a sibling
  or parent copes with either, and says which; `NpcInteractable._body_node()`.

## Server authority (IMPORTANT)

- Everything that can be server-side must be.
- Every client message is a request, never a fact.
- Changes game state? The server owns and mutates it.
- Clients get a replicated read-only copy.
- Never write locally "and tell the server after".
- Client asks (`sv_*`); server answers with new state (`cl_*`).
- Server checks everything: exists, price, affords, holds, near, alive, allowed.
- Private state goes only to its owner.
- Strip it from anything broadcast to every peer.
- Never derive a check from a client-supplied value.
- Positions come from the server's own speed-validated pawn.
- The UI never applies a change optimistically.
- It asks, then redraws when the server answers.
- Cosmetic per-player things stay local: faking them gains nothing.
- Open panels, dialog lines, camera and animation state.
- In doubt whether it's cosmetic? Server.
