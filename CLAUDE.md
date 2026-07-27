# Astria — Godot 4.7 third-person action game

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

## File organization (IMPORTANT)

Being organized is very important in this project. Within reason, the more
folders the better — the more specific, the better. If a folder has more than
5 things in it that are not very similar (or wouldn't make sense grouped
together), it must be broken down into new subfolders.

Current structure to follow and extend:

- `Assets/` — all imported content
  - `Animations/Humanoid/` — animation FBX clips, grouped by purpose
	(`Combat/LightM1`, `Combat/HeavyM1`, `Combat/Blocking`, `Movement/Idle`,
	`Movement/Walking`, `Movement/Running`, `Movement/Sliding`, ...)
  - `Models/` — `Entity/Humanoid/Human/` for characters, `World/Islands/...`
	for level geometry; skeleton bone maps live in `Models/Entity/Humanoid/`;
	NPC part models in `Entity/Humanoid/VoxelNpc/Parts/<Set>/<Slot>/`
  - `Textures/` — mirrors the model grouping (e.g. `Humanoid/Human/Rouge/`);
	`Textures/UI/` is screen furniture rather than anything in the world
  - `Fonts/<Family>/` — a typeface and the licence it shipped with, kept
	together (`EBGaramond/` holds the .ttf files and its OFL.txt)
  - `Data/Npcs/` — `NpcDefinition` resources written by the NPC Builder
- `scenes/` — .tscn scene files; reusable building blocks go in subfolders
  (`scenes/entities/npc/`, `scenes/effects/`, `scenes/ui/`); built NPCs land
  in `scenes/entities/npc/built/`
- `scripts/` — GDScript, grouped by domain: `entities/` (player, enemy,
  character visuals, `npc/` interaction + rigging), `ui/` (HUD, `dialog/`,
  `voice/`, `theme/` — the palette every screen is built from), `combat/` (the
  rules two fighters meet under, e.g. levels), `world/` (level/world logic),
  `core/` (autoloads, plus `voice/` for the microphone and the wire format)
- `addons/` — editor plugins (`npc_builder/`, `item_builder/`, `grass_brush/`,
  ...)
- `tools/` — command-line asset pipeline scripts, e.g. `voxel/gox_to_gltf.py`

When adding new assets or code, place them in the most specific folder that
makes sense; create new subfolders rather than letting a folder grow into a
mixed pile.

## Controls (IMPORTANT)

- Never pick a gamepad binding yourself. Any new control that a player presses
  must be brought back to the user first: ask which button it should be on a
  PS5 pad and on an Xbox pad, and only then write it into `project.godot`'s
  input map. Keyboard/mouse bindings can be proposed as usual, but the pad half
  is always the user's call — the layout is a design decision, and a clash with
  slide/lock-on/interact is invisible from the code.
- `block` (RMB / LT) is ALSO the item SPECIAL — see "Two buttons: use and
  special". It is one binding doing both on purpose: an item that declares a
  special takes that button over while it is in hand and cannot guard, and
  everything else (fists, every blade) blocks exactly as it always did. Adding
  a second binding for it would be a control that means the same thing twice
  and can drift.
- Bindings today: `attack` = LMB / RT, `block` = RMB / LT, `jump` = Space /
  A (cross), `slide` = Space or Ctrl / A (cross) — the SAME button as jump,
  `lock_on` = MMB / R3, `interact` = E / Y (triangle), `inventory` = Tab /
  D-pad up, `sprint` = Shift, with no pad button by request,
  `hotbar_next` / `hotbar_prev` = ] and [, the mouse WHEEL (down = next, up =
  back) / R1 and L1, `use_item` = F / R2 —
  the SAME trigger as attack, so a swing is also a use (which is why the
  server's use replies carry no message yet), `cheat_menu` = Z / Options
  (Menu), `voice_talk` = V / L3 (click the left stick), `voice_mode` = M, with
  no pad button yet — like sprint and the scoreboard.
- Picking an entry in any menu (dialog answers, shop rows, cheat rows, bag and
  hotbar slots) is `ui_accept`: on a pad strictly the bottom face button — PS5
  Cross, Xbox A, the same physical place — and E or Enter on a keyboard. The
  interact button is NOT a menu confirm on a pad: Y / triangle is "press at a
  thing" in the world and the two blurred together. Ask with
  `InputDevice.is_menu_accept(event)` rather than testing the actions by hand;
  it is what keeps that split in one place. Panels still swallow an interact
  press they ignore, or it reaches the NPC standing behind them.
- `ui_accept` is written out IN FULL in `project.godot` (Enter, Kp Enter, Space,
  pad button 0). Godot's built-in default for it carries no pad button at all,
  which is a silent one: every menu worked on a keyboard and no controller
  could confirm anything anywhere in the game. If a `ui_*` action is ever
  relied on for a pad, check `InputMap.action_get_events()` for it rather than
  assuming the engine's default has a button on it — `ui_cancel` is still
  Escape only.

## How every screen looks (IMPORTANT)

- ONE file owns the look: `scripts/ui/theme/ui_theme.gd` (`UiTheme`). No screen
  may mix a background colour of its own again — six screens each inventing
  their own black is exactly how they drifted apart, and a palette that lives
  in six files is not a palette. Adding a screen means calling
  `UiTheme.panel()` / `UiTheme.backdrop()`, not writing a StyleBoxFlat.
- Three greys, and they are a DEPTH ORDER, not a set of options — pick by how
  far forward the thing sits: `INK` #232323 is the furthest back (backdrops and
  panel bodies), `SLATE` #343434 is anything sitting ON a panel (rows, tabs,
  slots), `STONE` #464646 is edges and whatever should read as raised (a
  panel's border, the row under the pointer). `UiTheme.row_fill(hot)` is the
  row/tab/slot fill so a list never invents its own two shades.
- Gold (`0.95, 0.79, 0.42`) is deliberately NOT in the palette. It is the
  game's "pay attention" accent — the wind-up star, the quest marker, an NPC
  bubble — and it means something. The greys mean nothing, which is their job.
  The cheat menu and the tutorial popup pass gold as their `edge` on purpose:
  neither is an ordinary screen.
- WHERE THE CONTROLLER IS, is WHITE, and never gold — the one place the accent
  is deliberately not used. In a grid, gold is already saying something about
  the slots themselves (in the inventory it means "this one is on the hotbar",
  and half the bag wears it), so a gold focus ring is one gold box among nine
  and the cursor vanishes. The focused slot also draws a thicker ring OUTSIDE
  its own rect and lifts itself above its neighbours with `z_index`
  (`InventoryUi.FOCUS_EDGE` / `FOCUS_RING_OUT` / `FOCUS_Z`): a container paints
  its children in tree order, so without the lift the slot drawn next covers
  the edge and the ring loses a side. Any future grid a pad can walk should do
  the same rather than trusting the theme's default focus box.
- Behind and inside everything is one sheet of cracked paint,
  `Assets/Textures/UI/panel_grunge.jpg` — full strength as the backdrop behind
  an open panel (what used to be a flat black dim), and at `PANEL_GRAIN` over a
  panel body, where text has to stay readable. A tint MULTIPLIES the texture,
  so `UiTheme.sheet()` divides by the sheet's own average grey (`SHEET_MEAN`)
  first: paint it with a shade straight and the result lands far under that
  shade (0.14 * 0.56 is nearly black) instead of ON it.
- A missing texture is survivable by design — `sheet()` falls back to a flat
  rectangle of the shade. A screen must never fail to build over its wallpaper.
- `UiTheme.panel()` returns the FRAME; content goes into `UiTheme.body(frame)`.
  The padding lives in that inner MarginContainer rather than in the stylebox's
  content margins, and that is not a style choice: a PanelContainer fits its
  children to the rect MINUS those margins, so padding written the obvious way
  insets the sheet too and leaves an untextured border ring around every panel.
- The font is EB Garamond (`Assets/Fonts/EBGaramond/`, OFL licence kept beside
  it), set ONCE as `gui/theme/custom_font` in `project.godot`. That is what
  makes it reach both the panels and the vector HUD — the drawn overlays ask
  for `get_theme_default_font()`, so there is nothing per-screen to update.
  The variable font is used as shipped; Godot renders the weight it needs.
- Cinematic's letterbox bars stay pure black on purpose: they are the edge of
  the shot, not a surface with UI on it. They are the one exception the test
  below skips.
- ANY SCROLLING LIST SETS `follow_focus = true` ON ITS ScrollContainer. Six rows
  are on screen, the shop's stock and the cheat menu's item list are both longer
  than that, and A PAD HAS NO WHEEL AND NO SCROLLBAR TO DRAG: the only way down
  a list is the highlight walking there, so a view that does not follow it makes
  the list simply END at row six for anyone on a controller, with the focus on
  something they cannot see. It is one line and it is not optional.
- A list rebuilt in the same frame it is re-focused needs an extra nudge:
  `follow_focus` scrolls the instant focus lands, and rows built this frame have
  not been sorted yet, so they all still claim to be at the top and the view
  scrolls home while the highlight sits on row twelve. The shop asks again
  (`ensure_control_visible`) one frame later, after the container has laid itself
  out — see `_restore_focus`. A list that always re-focuses its FIRST row (the
  cheat menu) needs none of this, because home is where the view belongs anyway.
- Test: `--headless res://tests/test_menu_scroll.tscn` (prints
  `SCROLLTEST RESULT=PASS/FAIL`) — walks the shop's stock down with REAL
  `ui_down` events (the pad's d-pad and stick) and checks at EVERY step that the
  highlighted row is still inside the visible window, and that the list really
  scrolled rather than being tall enough to cheat. Needs no server: a shop panel
  is local. Checked every step and not just at the end, because a list that
  jumps a page at a time passes an end-state check while flickering the row you
  are on off the top.
- Test: `--headless res://tests/test_ui_theme.tscn` (prints
  `UITEST RESULT=PASS/FAIL`) — the three hexes, the sheet loading, the font
  really reaching a Control, a panel's structure (paint behind the content,
  padding out of the stylebox), and then a walk over every live screen that
  FAILS on anything still painted black, naming the node. That last one is the
  regression guard: it is what stops a new screen quietly going back to black.
- Eyeballing it: `godot --path . res://tests/preview_ui.tscn` (NO `--headless`
  — it renders) opens the REAL shop, dialog box and quest corner over a
  stand-in world and
  saves a PNG of each, plus a swatch sheet of the three shades and the font at
  every size the game uses, into `user://ui_preview`. The shop is shot TWICE —
  as opened, and after walking nine rows down it the way a pad walks it. If
  `shop_scrolled.png` looks the same as `shop.png`, the list is stuck at the top.

## The mouse pointer

- NOTHING sets `Input.mouse_mode` except `player.gd::_tick_mouse_mode`, which
  re-asserts it every tick: visible while a panel wants it or the player let it
  go with Esc, captured otherwise. Panels used to capture and release it
  themselves on open/close, and any pair that ran out of order left the cursor
  loose with no way back into the game.
- A panel says it wants the pointer by joining the group `"ui_panel"` (in its
  `_ready`) and answering `is_open()`. That is the whole contract — a new panel
  never touches the mouse mode itself.
- Esc frees the pointer only when nothing is open; an open panel owns Esc and
  closes with it. Clicking in the world takes the pointer back, and that click
  is swallowed (`_recapture_frames`) so it isn't also a punch.
- The tick leaves the pointer alone while the window is unfocused, or alt-tabbing
  out would drag it back into the game.
- The main menu and a dropped connection still show the cursor directly — there
  is no local pawn then, so nothing is re-asserting anything.

## Movement: sliding

- Slide and jump share a button on purpose, and there is no standing slide:
  a press with both feet down is the jump, a press in the air is the dive, and
  the dive turns into the slide when you land (`_handle_slide_input` returns
  early on `is_on_floor`). Pressing it just before touching down counts too —
  `slide_input_buffer` is what makes a jump-then-slide feel forgiving.
- So every slide is landed into. If a slide is ever wanted from a standing
  start again, it needs its own button first (see Controls).

## Movement: sprinting

- Sprint is `sprint_speed_mult` over the walk and needs forward input, both feet
  on the ground, guard down and no swing (`_can_sprint`). It is FREE:
  `sprint_stamina_drain` is 0, which the code reads as "don't touch the meter
  at all" — no drain, no regen pause, no minimum to start, and the server skips
  its copy of the drain too. Set the export above 0 to put running back on the
  same meter combat spends; every branch is already written for that.
- On a gamepad there is no sprint button: holding the stick near full forward
  for `auto_sprint_time` starts the run by itself (`_stick_full_forward` reads
  the raw joy axes, so a keyboard — which reports 0 there — never auto-sprints).
- Server-authoritative like everything else: the owner reports a `sprinting`
  flag with its state, the server only believes it if its OWN two accepted
  positions show more ground covered than a walk. That check is what a drain
  would be charged off if one is ever turned back on — never the client's word.
- No new animation: `_animate` already replicates `ratio = speed / walk_speed`,
  and `HumanoidVisual.tick` picks the run clip and scales stride rate from it.

## Standing still: the two idles

- There are TWO standing poses, and which one is on screen is a matter of how
  long the character has been doing nothing. `idle` (Mixamo's plain `Idle.fbx`)
  is what standing still looks like; after `HumanoidVisual.IDLE_LONG_AFTER`
  (15s) of unbroken idle they drop into `idle_long` (`Offensive Idle.fbx`, the
  fighting stance that used to be the only idle) and stay there until something
  moves them.
- The clock is time spent doing NOTHING, not time since the last idle started:
  `tick` adds to `_idle_time` only while `anim == "idle"` and nothing is
  staggering them, and zeroes it otherwise. A single step, swing, guard, jump
  or hit puts them back on the short idle.
- Which pose is which is the two paths in `CLIPS` and nothing else — no code
  knows what is in either clip, so swapping them (or pointing `idle_long` at a
  new "bored" animation) is a one-line change.
- A sword in hand hides the whole thing: `SWORD_CLIPS` maps BOTH idles to
  `sword_idle`, so the swap still happens and nothing shows. Do the same for
  any future weapon set — an idle that has no armed version would otherwise
  yank the blade out of the character's hands at 15s.
- Built NPCs never do it. `NpcVisual.NPC_CLIPS` is idle/walk/run, so villagers
  do not load the clip; `_idle_key` checks `has_animation` and stays on the
  short idle rather than erroring. A villager taking a boxing stance because
  nobody talked to them for 15s is not the behaviour.
- Covered by `--headless res://tests/test_npc_builder.tscn` (`_check_long_idle`,
  driven through the real `tick` with frame-sized deltas): not before the wait,
  yes after it, reset by one step, invisible with a sword, and not loaded for
  villagers.

## Combat: where a swing goes

- An unlocked punch goes where the CAMERA is pointed. It used to prefer the
  direction you were moving whenever you were moving at all, so strafing past
  someone threw the punch off sideways and backing away threw it behind you —
  which is what made unlocked punching feel like it never connected.
- A swing snaps the body to its aim rather than turning toward it at
  `locked_orient_speed_deg`. This is not cosmetic: the body yaw IS what the
  server aims an unlocked trace along, and at 540 deg/s a punch thrown mid-turn
  landed up to a right angle away from what the player saw.
- The aim rides WITH the attack request (`sv_request_attack`'s `aim_yaw`)
  instead of being read off `net_yaw` when the request lands. Both are sent in
  the same frame and the state report can arrive second, which aimed the trace
  at wherever the body had been. It is no more trusted than before — the
  reported yaw was already the client's word, and there is nowhere else a
  server could learn where someone was looking. Everything the trace CHECKS
  (position, reach, who exists) is still the server's own.
- The cone is skipped at point blank (`dist <= radius`): inside that, it is only
  measuring which way two overlapping capsules lean, and it ate the punch every
  time an enemy closed all the way in.

## Combat: lock-on

- Lock-on is ALWAYS the player's own press (MMB / R3) — nothing locks on for
  them. Swinging near an enemy used to grab the nearest one silently
  (`_auto_lockon`, within `auto_lockon_range`), which stole the aim of a swing
  meant to miss and quietly turned you to face someone you had not chosen.
- So `lock_target` is set in exactly one place, `_update_lockon`, and the
  server only ever honours the target the client claims with its swing — no
  copy of the aiming rule lives on the server side.
- Everything that reads `lock_target` (the swing's facing, the lunge, the
  guaranteed hit inside `locked_hit_bonus`, the camera tracking, the red HUD
  ring) is therefore a reward for locking on deliberately, not a default.

## Combat: health regeneration

- Go `health_regen_delay` (3s) without taking damage and health climbs back at
  `health_regen` (6/s) to full — both `@export`s on `player.gd`, and a rate of
  0 turns it off. There is no item, no button and no cooldown: walking away
  from a fight IS the heal.
- Anything that gets through stalls it, chip through a raised guard included
  (`server_take_damage` sets `_hurt_hold` whenever `dealt > 0`). A clean parry
  deals no damage, so it deliberately does NOT stall the heal — perfect
  defence keeps you healing.
- Server-owned like the rest of combat: `_regen_health` is ticked from
  `_physics_process` behind `multiplayer.is_server()`, so it runs on the
  server's copy of EVERY pawn (its own included) and never on a client's. The
  owner's bar catches up through the existing `cl_vitals` sync twice a second
  — the client never adds a point to its own health.
- Bandits do not regenerate; only players do. If enemies ever should, it needs
  its own exports on `enemy.gd`, and note it makes disengaging mid-fight
  pointless.
- Covered by `--headless res://tests/test_combat.tscn` (the `=== regen ===`
  section): the stall, the climb rate, stopping at full, corpses not healing,
  and the parry/chip split.

## Technical notes

- Rendering: GL Compatibility; physics: Jolt. Main scene: `scenes/world.tscn`.
- The Rouge character (UE Manny rig) and the Mixamo animation clips are made
  compatible via import-time retargeting: each FBX's `.import` file references
  a BoneMap (`bonemap_manny.tres` / `bonemap_mixamo.tres`) mapping the rig to
  Godot's SkeletonProfileHumanoid. If an FBX is moved or reimported fresh,
  that `_subresources` retarget config in the `.import` file must be restored
  or animations will break.
- Rouge's textures live in `Assets/Textures/Humanoid/Human/Rouge/` (not next
  to the FBX), so `rouge_visual.gd` binds them to surfaces at runtime by
  matching material names to texture filenames.
- Gameplay numbers (speeds, damage, stamina, slide/lock-on tuning) are
  `@export` vars on `scripts/entities/player.gd` and `enemy.gd` — tune in the
  editor, not by hardcoding.
- Attack swing timings derive from the actual clip lengths at montage rates
  (light 1.35x, heavy 1.15x) via `HumanoidVisual.get_attack_info()`; a punch
  must finish before the next combo punch starts (queued input chains at
  swing end).
- Headless validation: run the Steam Godot binary with `--headless --import`
  then `--headless --quit-after 120` to catch script/scene errors.
- Every in-world HUD marker is vector-drawn and camera-projected in `hud.gd` /
  `npc_prompt_overlay.gd` — no glyph textures. Colour carries meaning: gold =
  "pay attention" (enemy wind-up star, talkable-NPC bubble), red = lock-on
  ring, steel blue = "defended" (the shield in the ring when the locked target
  has its guard up). Keep new markers on that split rather than inventing a
  colour per feature.
- Screen HUD layout: health and stamina bars in the top-left (x 24, y 24 and
  52, 280x20 each), and the "Current Quest" heading
  (`scripts/ui/quest/quest_tracker.gd`) under them on the opposite side, pinned
  24 px in from the right. Its star is a drawn polygon, the same one as the
  wind-up star: Godot's default font has NO U+2605, so a typed ★ renders as
  tofu — any symbol in the HUD has to be drawn, which is the rule above anyway.
- The quest corner is a REAL `UiTheme.panel()` — the same INK body, STONE edge
  and sheet of paint every screen is built from — not two gold labels floating
  over the water. It breaks the "panels are SOLID" rule on purpose and only on
  opacity: a screen is opened over the world, whereas this is up the whole time
  you are playing and a solid slab in the corner is a hole in the view. That is
  the only dial it turns; the shades, the edge and the frame come from the
  theme. Any future always-on HUD panel should do the same rather than mixing
  a colour of its own.
- Its width is FIXED. A panel that hugged its text would resize every time a
  counting quest ticked over — the corner breathing while you fight — so the
  labels clip instead (`clip_text`), and the star sits in a box of its own on
  the heading row. The star has to be a NODE now rather than the tracker's own
  `_draw()`: a Control paints itself BEFORE its children, so a star drawn by
  the tracker would be behind its own panel.
- The tutorial's banner is measured off `QuestTracker.MARGIN`/`SIZE` rather
  than a typed y, so growing the panel never parks it on top of the banner.
- Anchored HUD pieces set `offset_*`, never `position`: `position` is
  parent-relative, so on a right-anchored control it lands off the left edge.
- `set_anchors_preset()` KEEPS THE CONTROL'S CURRENT RECT, baking offsets to
  match it — and a code-built Control has never been sized, so the preset
  leaves it 0x0 with the anchors merely looking right. The drawing overlays get
  away with it (a `_draw()` is not clipped to the rect, which is why the
  wind-up star and NPC bubbles were fine), but anything that LAYS OUT CHILDREN
  must set its anchors and all four offsets by hand. The tutorial popup was
  centring itself inside nothing and hanging half off the left edge.

## Intro cutscene

- Loading into the island opens on a black screen: you hear your own head
  complain, the world fades up over ~4.5s, and then you ask where you are.
  `IntroCutscene` (autoload, `scripts/ui/cutscene/intro_cutscene.gd`) owns the
  black rect and the timing; the two lines are ordinary DialogData entries
  (`intro_wake`, `intro_where`) so all writing still happens in one file.
- YOU GET UP OFF THE FLOOR as the black lifts. The pawn plays `get_up`
  (`Assets/Animations/Humanoid/Cutscene/GettingUp/`) and THE FADE IS THE LENGTH
  OF THAT CLIP, so the screen clears at the moment the player finishes standing
  rather than on an unrelated count — retrimming the clip retimes the wake-up.
  `FADE_TIME` is only the fallback for a pawn built without it.
- The clip is played through `HumanoidVisual.play_scripted`, which is the general
  way to put a clip on a body the pawn has no STATE for: `tick()` runs every frame
  off the pawn's own state and would otherwise replace it before its first frame
  was drawn. It owns the body for the clip's own length and hands it back by
  itself, so nothing has to remember to cancel it.
- The FBX ships two takes and the loader picks the 8.60s one, of which only the
  middle is the animation — hence the `slice` in `CLIPS` (see the comment there).
  Judge it with `godot --path . res://tests/preview_get_up.tscn` (NO
  `--headless`), which SEEKS the clip at four points and photographs each: flat
  on the floor through to up on both feet. Do not step such a preview by counting
  frame-sized deltas — a windowed run of an empty scene goes far faster than
  60 fps, and the clip was a third through when the counter said it had finished.
- Three hooks, nothing else: `world.gd` calls `arm()` from `_ready` (before a
  frame of the island is drawn, which is the whole point), `player.gd` calls
  `on_local_pawn_ready()` for the local pawn, and `main_menu.gd` calls
  `abort()` so a drop mid-cutscene never leaves the menu behind a black screen.
  Only an armed cutscene plays, so a respawn cannot replay it.
- Its ending is also what tells the tutorial the player can see
  (`Net.report_tutorial_ready`), so nothing swings at somebody still looking at
  black.
- It is purely local and cosmetic — nothing about it is networked.
- Its black rect is exempt from the "nothing is painted black" theme test, for
  the same reason Cinematic's bars are: it is the shot, not a surface with UI
  on it.
- Test: `--headless res://tests/test_intro_cutscene.tscn` (prints
  `INTROTEST RESULT=PASS/FAIL`).

## The tutorial

- What happens: you load onto the starter island while it is being raided, you
  are taught one fighting button at a time with the bandits switched on a piece
  at a time to suit, and when the last of them is down you are put on the REAL
  island. It runs on every join.
- Each player gets their OWN copy of the starter island — the "cloned world".
  A copy IS the island: the same `Island1` mesh at the same transform with the
  spawn marker in the same place on it, instanced at
  `TutorialData.slot_origin(slot)` — a row of slots 3km apart, 4km east, at the
  island's own height. One physics space, a private island each; nobody in the
  tutorial can see, hit or interrupt anybody else.
- Copies sit at sea level rather than up in the sky on purpose: the ocean
  follows the local player and the fog is measured from the camera, so a copy
  down here has water and a horizon, and one parked overhead would have
  neither.
- A copy grows its own collision at load (`tutorial_arena.gd::_build_collision`,
  the same trimesh pass `world.gd` runs on the real island) — a glTF ships
  none. That is the real cost of a copy, and why `MAX_SLOTS` is only 4: past
  that a joining player starts on the island instead.
- Bandit and villager positions are worked out from the spawn marker and
  dropped onto the terrain with a ray, not hand-placed: the ground under a copy
  is a whole island, and a marker left hanging in the air is not something you
  would notice until a bandit fell through the world.
- Server-authoritative like everything else (`scripts/world/tutorial/`):
  `tutorial_system.gd` (autoload `Tutorial`) owns the copy, its bandits and
  which step you are on; the client owns the screen and nothing else. The
  client instances its own copy of the arena scene at the same coordinates —
  exactly how the world scene itself works — and only the bandits are
  replicated.
- A tutorial bandit carries `owner_peer`: it is spawned and updated ONLY for
  that player (`Net.server_spawn_tutorial_bandit`, the private batches in
  `_broadcast_enemy_states`, the filter in `_handle_world_ready`), only fights
  that player, and can only hit that player. `owner_peer == 0` means an
  ordinary bandit of the shared world.
- The lesson is a table: `TutorialData.STEPS`. `wave` spawns bandits, `gate`
  teaches one button, `clear` is just a fight and ends when the wave is dead,
  `talk` is the villager, `end` sends you to the island. Reordering the lesson
  is reordering that array.
- THE FIGHT IS BUILT UP A PIECE AT A TIME, and that is the design. Every step
  carries an `ai` level saying how much of the bandit is switched on
  (`Enemy.Hold`): `still` is a dummy that does not move, turn or swing (what a
  line is spoken over); `circler` circles you but never swings; `attacker`
  circles AND throws one punch every `hold_attack_period` (3s); `full` is an
  ordinary bandit. The order that makes: it can only punch, so BLOCK is the
  first thing you are taught; then it stops punching and only circles, so you
  learn to swing at something that moves; the heavy and lock-on are taught
  against it standing still; then it wakes all the way up for a 1v1, and only
  when that is won does the rest of the raid arrive.
- It TEACHES with POPUPS: the control's name and its button on ONE gold line
  ("BLOCK — HOLD RIGHT MOUSE"), and one line under it saying what the thing
  does — `popup: {title, body}` on the gate step, drawn by
  `scripts/ui/tutorial/tutorial_overlay.gd`. Nothing to dismiss, and it never
  takes the controls off the player the way a dialog box would. Its size and
  placement are two dials, `POPUP_WIDTH` and `POPUP_DROP` (how far below the
  middle of the screen it sits) — everything else about the box sizes itself to
  its text. It is deliberately small and low: the lesson is read WHILE a bandit
  is circling, so the box stays out of the reticle and off the fight. Judge it
  with the `tutorial_popup` shot from `res://tests/preview_ui.tscn`. There is no
  and it TALKS with dialog: `tut_taunt` as the bandit that put you down opens
  its mouth, `tut_reinforcements` as its friends arrive, and `tut_mayor` when
  the villager sees you off. A step's line plays first and its popup follows,
  so the two are never on screen at once.
- Nobody is hit through a box they cannot close: a wave that arrives talking
  carries `await_dialog: true` and lands STILL until the line has been read.
- A gate still waits for the action to FINISH (`FINISH_GRACE`, capped so
  holding block cannot stall it) before moving on, so the next popup does not
  replace the last one while the swing it asked for is still playing.
- Measured, hands off the controls: the first punch lands 3.7s in, it circles
  about one and a half times around you in 15s, and three punches cost 16 hp.
  The dials are `held_circle_mult` (how fast it orbits), `hold_attack_period`
  (the beat) and `held_step_mult` (how fast it closes). An ATTACKER orbits
  INSIDE its own reach on purpose — park the circle on the edge of it and the
  punch it exists to demonstrate never gets thrown, which is exactly what
  happened the first time.
- A tutorial bandit hits for `TutorialData.DAMAGE_MULT` (0.4) of an ordinary
  one. That is the ONLY thing softened about them — same reach, wind-up and
  timings — so what you learn there is what the island does, at a price a
  first fight can afford.
- A HELD bandit cannot be HURT (`Enemy.take_damage` returns early on any
  `hold_mode` but NONE). Three gates' worth of practice swings otherwise left the
  first bandit nearly dead before the duel it exists for, and the "one on one"
  the lesson promises was over in a punch. It still flinches and still grunts —
  a swing that lands has to feel like it landed, or the attack lesson teaches
  nothing — and nothing is held once the duel starts, so the real fight is real.
- Tutorial bandits PAY NOTHING (`_die` skips the drop when `owner_peer != 0`).
  The lesson runs on every join and restarts from the cheat menu, so a payout
  would be the cheapest gold in the game.
- A WAVE ARRIVES IN FRONT OF YOU, and any wave after the first arrives closer
  (`TutorialArena.wave_spawns`, `REINFORCEMENT_RING`, `WAVE_ARC_DEG`). Bandits
  used to be dealt around a full ring by golden angle from the spawn MARKER,
  which put some of them squarely behind you and the rest wherever you happened
  to start — an enemy you never saw arrive is an ambush, not a lesson. The arc is
  centred on the server's own copy of where that player is and which way they are
  looking, never a claim from the client.
- A gate holds the BANDITS, never the player: you can walk and look around
  while the lesson waits. It opens on the real action, read off the server's
  own copy of the pawn (`attacking` / `attack_is_heavy` / `blocking`), so it
  cannot be clicked past without doing it. Lock-on lives entirely in the
  client's camera, so that one step carries `client_gate: true` and is taken on
  trust — the most a patched client wins is skipping its own lesson.
- An `attacker` really does hit you (`Enemy._tick_held` walks it the last step
  into reach and swings on the real timings, star and damage included) — a
  block lesson with nothing coming at you teaches nothing. Which is why that
  gate carries its own shorter `patience`: a lesson nobody answers is also a
  lesson that is punching them.
- Tutorial bandits are spawned facing the player and already awake
  (`Enemy.face_toward` + `aggroed`, in `Net.server_spawn_tutorial_bandit`).
  An ordinary bandit only wakes when the player walks into its vision cone, so
  one dropped in facing the other way would stand there until it was punched —
  which is exactly how the first lesson used to read: nothing happened until
  you hit it.
- Pacing rule to keep: a pause only ever buys a NEW button, the fight resumes
  the instant it is pressed, and the last wave is fought without a single
  interruption. Steps that are just a fight get a `banner` line instead — no
  box, no pause, nothing to dismiss.
- A gate must never brick the game. `TutorialData.GATE_PATIENCE` (25s) gives in
  and moves the lesson on if nobody answers, because a gate that cannot be
  passed leaves a player in front of bandits frozen in place with no way out —
  which is exactly what the heavy-swing gate did: a heavy is the attack button
  HELD, so tapping it only ever jabbed and the gate never opened. Hence also
  `gate_is_hold()`, which makes the prompt read "HOLD <button>" instead of the
  button alone.
- Rewriting a lesson is rewriting its `popup` in `TutorialData.STEPS`. The
  banners (`banner`) are the other text: one line under the quest heading
  during the parts that are just a fight.
- A villager walks over once the raid is beaten and points you at the King,
  which is where `NEXT_QUEST` is sending you anyway. She is the NPC Builder's
  `scenes/entities/npc/built/villager.tscn`, so recolouring her in the builder
  recolours her here.
- Test: `--headless res://tests/test_tutorial.tscn` (prints
  `TUTTEST RESULT=PASS/FAIL`) — hosts a real listen server and walks the whole
  lesson: joining lands on a copy and not the real island, the copy has the
  island's geometry, its spawn and its collision, nothing moves until the
  client reports in, the block lesson really throws a punch, the punch lesson
  really stands still, the duel is one on one with everything switched on,
  reinforcements come after it, finishing leaves no copy and no bandits behind,
  the cheat restarts it on a fresh copy, and an unanswered gate gives in
  instead of bricking. It also TIMES the block gate, because a gate that opened
  on the patience valve and one that opened on a real block look identical from
  outside.
- The gates are driven with REAL input events (`Input.parse_input_event`), not
  by setting `attacking`/`blocking` behind the game's back. That is the only
  reason the heavy-gate stall was caught — every flag-level test of it passed.
- Hosting and waiting for the pawn is `tests/helpers/test_host.gd`, shared by
  every integration test that needs a world — see "Integration tests" below.

## Cinematic framing

- `Cinematic` (autoload, `scripts/ui/cutscene/cinematic.gd`) is the shared
  "this is a scene" look: two black bars top and bottom, and the camera turning
  to whoever is speaking. Reusable by anything, not cutscene-only.
- Two switches on purpose. `focus(node)` / `unfocus()` turns the camera onto a
  character and brings the bars in with them; `hold_bars(true/false)` is bars
  alone, for a scene with nobody in it to look at. Bars show while EITHER is
  on. Nothing calls `hold_bars` today — the intro cutscene that used to is
  gone — but it is the other half of the switch and costs two lines.
- `DialogSystem.start(id, speaker_node)` is what drives it: pass the node that
  is talking and it gets framed for as long as the box is up. NpcInteractable
  passes itself, which is the only caller today. A line with NO speaker node
  gets neither bars nor a camera move.
- It only NUDGES the pawn's own camera rig (the same yaw and pitch the mouse
  drives) toward the target, so when it lets go the player carries on from
  where the shot ended instead of being snapped somewhere. It takes no input
  away — the dialog box already does that.
- THE SHOT IS A HIGH ANGLE, looking down on the pair of them: `FRAME_PITCH_DEG`
  is stated outright rather than worked out from where the speaker's face is.
  Only the YAW follows them. A pitch derived from an aim point is whatever the
  geometry happens to make — level ground nearly always, and a different shot for
  every character's height and every distance the player stopped at.
- The camera also PULLS IN, borrowing the pawn's `spring_length` and handing it
  back when the shot ends (`_tick_spring`, which is why nothing else in the game
  may own that property). The distance is sized off the speaker's own height
  (`FRAME_SPRING_PER_METRE`): a 2.40 m King and a 1.85 m villager framed from one
  fixed distance cannot both fill the shot.
- THE SPEAKER TURNS TO FACE THE PLAYER while the box is up
  (`NpcInteractable.turn_toward`, nudged from here every frame). Without it they
  answer you with their back turned — an NPC is a prop facing whichever way it
  was dropped into the level, and the player walks up from wherever they like, so
  being talked to from behind was the ORDINARY case. Note the yaw is
  `atan2(-x, -z) + PI`, the same as `Enemy.face_toward`: these rigs are modelled
  facing +Z, so the plain look-at yaw turns their back to you.
- Where the camera looks and how tall the speaker is are both MEASURED off the
  body, not constants — `NpcInteractable.look_anchor()` / `body_height()`, taken
  once from the meshes. The old flat 1.5 m was the King's waist. That code has to
  cope with both layouts in the world: the interactable is either the NPC's own
  root with the body under it (the blacksmith) or a child at the NPC's origin
  (the King, and every built NPC), so it measures itself first and its parent
  second — and only when the parent is a character, or a sibling arrangement
  would measure the whole island.
- Eyeballing it: `godot --path . res://tests/preview_dialog_camera.tscn` (NO
  `--headless`) stands the player in front of each talking character, TURNED
  AWAY as the world leaves them, and saves the shot each conversation opens on.
  A preview that stood them already facing you would prove nothing.
- Purely local and cosmetic: where one player's camera points changes nothing
  anyone else can see.

## NPC dialog

- To make an NPC talkable: instance `scenes/entities/npc/npc_interactable.tscn`
  next to it in the world and set `dialog_id`. Tunables: `interact_range`,
  `prompt_offset` (where the bubble's tail points).
- Every NPC in the world also belongs to the node group `"npc"` — set it on the
  node itself (Node dock -> Groups), the way `BlacksmithNPC` in `world.tscn`
  does, so `get_tree().get_nodes_in_group("npc")` is the way to ask for all of
  them. It is a scene-level group on purpose: it says "this node is an NPC",
  which is a level-editing fact, not something a script should decide. Put new
  NPCs in it when you place them, alongside the code-set groups
  (`enemies`, `player`, `npc_interactable`, `spawn_point`, `teleport_<id>`).
- A `
` in a line's `text` is a PAGE BREAK, not a line break: the box types up
  to it, holds a beat (the line's `auto`, or a press), then wipes and types the
  rest in the same box. It is how the intro's "Ugh." lands before "my head
  feels awful". Never use it for wrapping — the box wraps by itself.
- A `goto` back to a line already read in this conversation does NOT say it
  again: the reply you just finished stays on screen and only the choices come
  back (`_read` in `dialog_system.gd`, cleared per conversation). Every branch
  in the game ends by returning to the question it came from, and retyping that
  question each time read as though the NPC had forgotten saying it — worse, it
  wiped the answer you had actually asked for as you finished reading it.
  Reopening the conversation later types everything afresh.
- All conversation text lives in `scripts/ui/dialog/dialog_data.gd` — the file
  header documents the format (speaker / start / lines, each line with `text`
  plus either `answers` or a plain `goto`; `goto: END` closes the box). An
  answer may carry `"action"`, which the `DialogSystem.action_triggered` signal
  reports so gameplay code (shops, quests) can hook in.
- A conversation can open somewhere OTHER than its `start`, and there are two
  conditions for it — `first_time` (until a gift has been taken) and
  `when_quest_done` (while the player is on a named quest with its count made,
  which is how the King asks "So?" instead of "Yes? What do you want?").
  Reporting in wins when both apply. BOTH read the SERVER's own record through
  the `GameStats` mirror, never anything the box remembers, so the worst a
  patched client wins is the wrong greeting on its own screen.
- A line may name its own `"speaker"`, and `"speaker_at"` (a `dialog_id`) puts
  the camera on whoever in the world is saying it. That is what makes a scene
  with two people in it — the King thanks you, the Knight beside him cuts in —
  one conversation rather than two. Without the speaker swap the second half
  reads as the first person still talking.
- Test: `--headless res://tests/test_dialog.tscn` (prints
  `DIALOGTEST RESULT=PASS/FAIL`) — needs no server, since a conversation is
  local. It walks down a branch and back out of it, which is the loop-back rule
  above, checks reopening still says everything, and walks the throne scene: the
  count-made opener (and that one kill short is still the plain greeting), and
  the name over the box really changing when the Knight speaks.
- `DialogSystem` (autoload) owns the box: semi-transparent black panel,
  typewriter reveal with the looping keyboard clatter in
  `Assets/Audio/SFX/UI/Typing/`, and answer buttons driven by mouse,
  WASD/arrows + E/Enter, or gamepad stick + A. It sets the player's `ui_open`
  while it is showing. Purely local — nothing about dialog is networked.
- `NpcInteractable` opens the box from `_unhandled_input`, NEVER by polling
  `is_action_just_pressed`: the box marks its own interact presses handled, and
  polling let the press that walked off the last line reopen the conversation
  in the same frame — you could not leave. Any future "press E at a thing" must
  read the event, not the action state, for the same reason.
- The in-world marker is a HUD overlay, not a 3D node: `NpcInteractable` only
  keeps a `prompt_alpha` and a `prompt_anchor()`, and
  `scripts/ui/dialog/npc_prompt_overlay.gd` (added by `hud.gd`) projects that
  anchor with the camera and draws a speech bubble there. It is deliberately
  the same technique as the enemy wind-up star in `hud.gd`'s
  `TelegraphControl`, down to the gold accent — keep the two consistent.
- The button inside the bubble follows the last-used device via the
  `InputDevice` autoload: `E` on keyboard, `Y` on Xbox pads, a drawn triangle
  on PlayStation pads. Everything is vector-drawn, so there are no glyph
  textures. Hint text in the dialog box uses `InputDevice.interact_label()` /
  `accept_label()` for the same reason.
- Keys: `interact` = E / pad Y (triangle); `inventory` = Tab / pad D-pad up.
  Tab used to be a `lock_on` binding — it was removed there, so lock-on is
  middle-mouse / pad R3 only. D-pad up is also Godot's built-in `ui_up`;
  that only ever moves focus inside an open panel, so the two coexist.

## Proximity voice chat

- Hold V (L3 on a pad) and the players standing near you hear you. Their voices
  come out of their bodies, so walking away from a conversation is how you leave
  it. M switches between push-to-talk and an open mic, and the choice is
  remembered in `user://settings.cfg` next to the username — the main menu has
  the same switch, which is where it can be set BEFORE walking into a world with
  a hot mic.
- WHO HEARS YOU IS THE SERVER'S DECISION, and that is the whole security story.
  A packet is sent to the server and nowhere else; the server measures the
  distance on its OWN copy of both pawns (`Player.server_body_pos` — the last
  position it accepted, already speed-validated) and relays only to the peers
  inside `Net.VOICE_RANGE`. So a patched client can shout, but it cannot pick an
  audience, and it cannot listen in on a conversation across the island: those
  packets are never sent to it. `Net.voice_targets` is that decision and it is
  the only place it is made.
- Nothing about a voice is validated, because there is nothing to validate — no
  amount of talking changes a single thing in the game. What CAN be abused is
  the RELAY, so `Net.voice_accepts` caps a packet's size and gives each talker a
  budget of bytes a second (`VoiceCodec.MAX_BYTES_PER_SECOND`). Overspend still
  counts against the budget even though it is dropped, or a flooder would get a
  free packet every time the window turned.
- Players inside the tutorial need no special case at all: their copy of the
  city is kilometres east, so the distance rules them out by itself.
- `scripts/core/voice/voice_codec.gd` is the wire format: mono at
  `VoiceCodec.RATE` (11025), one companded byte a sample — µ-law's curve in
  floats, since both ends are this file and G.711's tables buy nothing. EVERY
  PACKET STANDS ALONE, which is why a predictive codec is not used despite being
  half the bandwidth: voice rides an unreliable channel, and one lost packet
  would poison a predictor for as long as somebody kept talking. RATE is the
  bandwidth dial — one byte a sample means RATE bytes a second per talker.
- The same file owns the resampler, and its phase is kept ACROSS calls: the mic
  hands over blocks at whatever the machine mixes at (44100 here, 48000 on
  plenty of others, and not the game's choice), so a resampler that restarted at
  each block would click on every seam.
- `Voice` (autoload, `scripts/core/voice/voice_chat.gd`) owns the microphone and
  the playback. The mic is an `AudioStreamMicrophone` on a bus of its own turned
  down to -80 dB rather than MUTED — a capture is an EFFECT, and an inaudible
  bus certainly still runs its effects. It needs `audio/driver/enable_input` in
  `project.godot`, which is read ONCE at startup: with it off every other part
  of voice chat works and nobody can talk.
- The capture is drained every frame whether or not the mic is open. That is not
  wasted work: a buffer left to fill up hands back the room's noise from a
  minute ago the moment the button goes down, and then overflows.
- A voice is played by an `AudioStreamGenerator` on an `AudioStreamPlayer3D`
  parented to the SPEAKER'S PAWN (named `Voice` in their tree), so the 3D mix
  does the proximity falloff for free and it follows them as they move. It fades
  to nothing at exactly `Net.VOICE_RANGE`, which is where the server stops
  relaying, so the cut-off is never audible as a pop. The node is rebuilt when
  the pawn it hung on goes.
- The HUD is `scripts/ui/voice/voice_overlay.gd`: a drawn microphone in the
  bottom-left for your own mic (with a level meter, and struck through in red
  when there is no microphone to talk into), and the SAME glyph over the head of
  anybody being heard. Gold, because somebody talking is "pay attention". An
  open mic draws its glyph even when quiet, on purpose — a hot mic the player
  has forgotten about is the thing to avoid.
- Test: `--headless res://tests/test_voice_chat.tscn` (prints
  `VOICETEST RESULT=PASS/FAIL`) — the format, the resampler at three mix rates,
  and then the routing end to end through the real listen-server relay: a
  neighbour is heard, the same words from across the island are not, height
  counts, a listener is placed by the SERVER's copy of its pawn and not its own
  claim, nobody hears themselves, and a flooder is cut off. What it cannot
  cover is the two-process RPC hop and whether any of it SOUNDS right — that
  needs two machines and two microphones.
- Eyeballing the HUD: `godot --path . res://tests/preview_voice.tscn` (NO
  `--headless` — it renders, and a `_draw()` never runs without a window) saves
  a shot of each state into `user://voice_preview`, and prints whether the
  playback generator really built on a speaker's body. It is also the only
  check that the overlay's drawing code runs at all.

## Quests

- A quest is a name and a THING TO WALK TO. `scripts/world/quest/quest_data.gd`
  is the catalogue: id -> `{name, target, height, from}`. Adding one is that
  entry plus something in the world wearing the `quest_<target>` group — the HUD
  and the cheat menu build themselves from the table, so there is no per-quest
  UI code anywhere.
- A target is a NAME, never a coordinate, exactly like `TeleportData`: the star
  reads the position off whatever is in the group as it draws, so moving the
  place (or the NPC) in the editor moves the marker with it. Point a quest at a
  PLACE by dropping `scenes/world/quest_anchor.tscn` there, or at a CHARACTER by
  putting them in the group in the scene — which is how "drive off the bandits"
  points at the bandit camp with no new node at all.
- Server-owned like everything else you could gain by cheating:
  `Net.players[id]["quest"]` rides the private purse slice into
  `GameStats.quest`, a read-only mirror. Talking is local (see "NPC dialog"), so
  the server cannot see the conversation — it checks the one thing it can, the
  same thing a shop checks: `_near_npc`, is that pawn really standing at the NPC
  who hands this quest out. So the dialog answer only ASKS.
- Giving an NPC a quest to hand out is one dialog answer carrying
  `"action": "start_quest:<id>"`, and finishing one at an NPC is an answer
  carrying `"action": "finish_quest:<id>"`. `QuestSystem` (autoload `Quests`)
  turns both into requests — exactly how `"open_shop"` and `ShopSystem` work.
  No NPC needs code of its own. `done_at` is the `dialog_id` the server insists
  you are standing at to hand it in; `from` is the one it insists you are
  standing at to start it, and an empty `from` means only the SERVER hands that
  quest out.
- A COUNTING quest (`kills`) either ends where it stands or turns round, and
  which one is whether it has a `done_at`. `kill_bandits` has one, so the 25th
  bandit does NOT clear it: the count is capped, the heading becomes the entry's
  `done_name` ("Report back to the King"), the star swaps to its `done_target`
  and you walk it home. Only standing in front of the King clears it. A counting
  quest with no `done_at` still finishes itself on the last kill — there is
  nobody to report to.
- The server checks the COUNT as well as the distance on a hand-in. The answer
  that reports in lives in a local conversation, so a patched client can pick it
  whenever it likes; `_server_finish_quest` refusing anything short of
  `QuestData.is_complete` is the only thing between "I did it." and 25 bandits
  nobody killed.
- Finishing the tutorial puts you straight on `TutorialData.NEXT_QUEST`
  ("Speak to the King") as it puts you ashore, through
  `Net.server_grant_quest` — the server deciding, so there is nothing to
  validate. Before that the lesson ended by dropping you in the middle of a
  large quiet island with no reason to walk anywhere. Set `NEXT_QUEST` to ""
  for no hand-off.
- The King is the built voxel NPC (`scenes/entities/npc/built/kingnpc.tscn`)
  placed beside the TownHall, in the groups `npc` and `quest_king` — the group
  is what the star reads, so moving him in the editor moves the objective. His
  `NpcInteractable` is a CHILD of him rather than a sibling (the blacksmith's
  way round), which is the better of the two: at the origin of its parent it
  needs no transform of its own and it follows him wherever he is dragged.
- The Knight beside the throne (`Island1/Knight3` in `world.tscn`, group `npc`)
  hands out `clear_catacombs`. He is offered INSIDE the King's conversation —
  he speaks up as the King finishes thanking you — but the server still checks
  you are standing at HIM, because `from` is `"knight"`. That works only
  because he is 2.4 m from the King: his `interact_range` is 5.0 rather than
  the default 3.5 so the check has room (talking to the King can put you 5.9 m
  from the Knight, against his 7.5 m reach). `test_quest` asserts that sum
  rather than trusting it — move either of them apart and taking the quest
  would otherwise silently do nothing.
- THE CATACOMBS ARE A PLACE NOW: `scenes/world/catacombs_entrance.tscn` is the
  door on the island (it carries the `QuestAnchor`, so `clear_catacombs` has a
  star at last) and `Catacombs` in `world.tscn` is the dungeon itself, parked
  3 km west. Walking into the door puts you inside — see "Dungeons" for the
  portal. It still has no `kills` count and no `done_at`, so there is nothing
  to finish yet; give the entry one when the place has something in it to
  fight.
- The HUD: `quest_tracker.gd` is the heading (the quest's name, and nothing at
  all when you are on none — it used to read "Current Quest ★" whether or not
  there was one), and `quest_marker_overlay.gd` is the star out in the world
  with the distance under it. Same drawn star and same gold as the wind-up star,
  because gold is "pay attention".
- The star does NOT hide when the objective is off screen — that is when it is
  working. It slides to the screen edge in the direction you would have to turn.
  A target BEHIND the camera unprojects mirrored through the centre, so
  `place_marker` mirrors it back before clamping; skip that and the star sits on
  the wrong side and walks you the long way round. That is why the placement is
  a pure static function — it is the half that is invisible in a screenshot.
- Test: `--headless res://tests/test_quest.tscn` (prints
  `QUESTTEST RESULT=PASS/FAIL`) — the marker maths including the behind-you
  case, and the state: a new player is on nothing, an unknown quest is refused,
  a quest is refused to a pawn stood 80 m from the giver and granted next to
  them, the heading follows the mirror, and it can be dropped again. Then the
  King one end to end: the tutorial's follow-up is a real quest whose target
  and quest-giver NPC are both in the level, the server can hand it out, it
  will not hand IN from 60 m away, it does at his feet, and handing in a quest
  you are not on does nothing. Then the counting quest: the last kill keeps the
  quest and turns the heading and the star round, the King refuses a report
  from 60 m and one from a player with 0 kills, takes it at his feet, and the
  Knight really is close enough to the throne to hand out his own quest from
  inside the King's conversation.

## Items and shops

- Item catalogue: `scripts/items/item_db.gd` — id -> name / buy price / desc /
  level. Selling pays `ItemDb.SELL_RATIO` (half, rounded down) unless an item
  carries its own `"sell"`. Never hardcode a price anywhere else; two shops
  must not disagree about what a sword is worth.
- AN ITEM CARRIES NO ICON. Its picture is a PHOTOGRAPH OF ITS OWN ART FILE,
  taken at run time — see "Item icons" below.
- Who stocks what: `scripts/ui/shop/shop_data.gd`, keyed by the NPC's
  `dialog_id`. Optional `"buys"` list restricts what that shop will take back;
  omit it and the shop buys anything.
- Giving an NPC a shop is two steps: add a `ShopData.SHOPS` entry under its
  `dialog_id`, and give one dialog answer `"action": "open_shop"`. `ShopSystem`
  listens to `DialogSystem.action_triggered` and opens itself — no per-NPC code.
- Armor is in the catalogue a PIECE at a time, and an armor item carries
  `"armor"`: the EQUIPMENT slot it is worn in — one of `ItemDb.EQUIP_SLOTS`
  (`helmet` / `torso` / `pants`), the three the inventory's cross draws.
  `ItemDb.ARMOR_SETS` names the three that make each suit, so "a full set" is
  one list rather than three ids written out wherever a set is handed over or
  stocked — the forge's stock and Bram's gift are both built from it. What a
  piece is WORTH is in "Levels" below.
- AN EQUIPMENT SLOT IS NOT AN ART SLOT, and `ItemDb.EQUIP_COVERS` is the map
  between them. A suit is modelled in the same four slots an NPC's armor layer
  holds (`head`/`body`/`arms`/`feet`), but a CHESTPLATE is one item and puts on
  both the body and the arms: a breastplate and the sleeves that come with it
  are not two things anybody would strap on separately, and a pair of gauntlets
  you could lose track of is an inventory slot nobody wanted. Three items still
  cover all four plates, which `test_gift` asserts — merging must not quietly
  drop one.

## Two buttons: use and special

- EVERYTHING YOU HOLD HAS TWO BUTTONS, and every item may declare either:
  - USE is `use_item` (F / R2). It shares a trigger with `attack` on purpose,
	so a swing is also a use — which is why a blade's use IS its swing.
  - SPECIAL is `block` (RMB / L2). Anything that declares no special of its own
	falls back to the GUARD, so for fists and swords that button is the block it
	has always been and nothing about a fight changed when specials arrived.
- Declared in `ItemDb` as `"use": "<verb>"` and
  `"special": {"action": "<id>", "name": "<verb>"}`. The ACTION is what runs and
  the NAME is only ever shown. `Net._server_use_special` is the ONE place that
  turns an action id into something happening — add a case there, not a branch
  in the player.
- SPECIAL IS NOT A NEW BINDING. It is the block action, so there is one button
  to rebind and the two can never drift apart. That is also why an item with a
  special CANNOT guard while it is in hand — L2 is spoken for, and a breastplate
  is not a shield. Deliberate, and the reason the corner prompt exists.
- The request names NOTHING: `request_use_special()` carries no item and no
  action. The server reads its own bar and the catalogue, so the worst a patched
  client can do is press a button it is already holding down.
- THE PROMPT IN THE BOTTOM-RIGHT is what tells the player which two they have —
  `scripts/ui/items/item_prompt.gd`, added by `hud.gd`. Use on top, special
  INDENTED under it, each with the button's name for whatever device was last
  touched (`InputDevice.action_label`, so nothing there knows a binding). A use
  that does nothing shows no line at all rather than a line saying "nothing",
  which is most of the catalogue today.
- Its rows are LEFT-aligned inside a block that sits in the right-hand corner,
  and that is load-bearing: flushed right, indenting the special line only makes
  its row wider and both lines still end on the same column, so the indent is
  invisible. Anything else stacking a hint under a hint in a corner has the same
  trap.
- Armor's prompt reads "Equip" or "Take off" depending on whether that piece is
  already on. One button, two meanings, and a prompt that always said "Equip"
  would be lying half the time.

## Equipping

- LEFT TRIGGER PUTS IT ON — the SPECIAL button (see "Two buttons" below), not
  the use one. Pressing it on a piece equips it, pressing it again on the same
  piece takes it off. There is no separate equip button and no drag-and-drop,
  so one control both dresses and undresses you.
- Server-owned like the bag it comes out of. `Net.players[id]["equipped"]` is
  armor slot -> item id; `Net._server_equip` is the only thing that writes it,
  and it checks the item really is armor, that the player is really carrying
  it, and takes the SLOT from the item rather than from the request. The client
  sends `request_use_item()` and nothing else — it never says what it is
  wearing.
- What you have on rides BOTH syncs, and that is deliberate: privately in
  `cl_purse` (so your own panel can draw it) and publicly in `_public_players`
  next to `held` (so every other pawn can draw it on you). Armor is on your
  back where everyone can see it, exactly like the sword in your hand.
- Selling or losing a piece takes it off. `_drop_unowned_equipment`, called from
  `_bag_changed`, is what stops "sell the breastplate, keep the protection".
- The body really wears it: `PlayerVisual.set_armor` hangs the item's plates on
  the character's own armor layer — the same four slots the NPC Builder's
  "Wears armor" switch fills, in the colours the suit was painted in the Items
  tab — and re-rigs. So recolouring a suit redresses every player wearing it.
  It is a whole character rebuild, so it returns early unless something actually
  changed; the registry re-syncs on every hotbar press.
- Nothing about the armor layer moves a bone or a landmark (see "Armor on a
  built NPC"), so putting a helmet on cannot make a player taller or change how
  they fight. The protection is the level maths, server-side, and the plates are
  only the picture of it.
- The equipment cross draws from `GameStats.equipped`, and the slot's own name
  ("Helmet", "Torso", "Pants") shows through only while it is empty. "R Hand"
  mirrors the held hotbar slot; "L Hand" has nothing to put in it yet.

## Gifts

- A gift is something an NPC hands over ONCE: nothing is asked for and nothing
  is paid. `scripts/world/gift/gift_data.gd` is the catalogue — id ->
  `{from, items}` — and giving an NPC one is that entry plus one dialog answer
  carrying `"action": "take_gift:<id>"`. `GiftSystem` (autoload `Gifts`) turns
  it into a request, exactly the way `QuestSystem` does for a quest. No NPC
  needs code of its own.
- Server-owned like anything else you could gain by cheating.
  `Net.players[id]["gifts"]` is the record of what has been handed over; it
  rides the private purse slice into `GameStats.gifts`, a read-only mirror.
  `Net.server_grant_gift` marks it taken BEFORE the items go in, which is the
  only thing between a client that asks twice in one frame and two suits of
  armor. `from` is what the server checks — the conversation is local, so it
  cannot see the offer was made, only whether your pawn is really standing at
  that NPC. A gift with no `from` can only be handed over by the server itself.
- WHAT "THE FIRST TIME YOU TALK TO SOMEBODY" MEANS. A conversation may carry
  `"first_time": {"line": ..., "until_gift": ...}` — it opens on that line until
  that gift has been taken, and on its ordinary `start` afterwards. The
  condition is the SERVER's record, not anything the dialog box remembers, so it
  survives a reconnect and a patched client that clears its mirror gets the line
  back and no second suit. Bram the blacksmith is the one today: he hands over a
  full flimsy suit the first time you speak to him.
- It is per CONNECTION, not per character: nothing about a player is saved to
  disk yet (`Net.players` is built fresh in `_make_entry` when you join), so
  rejoining the server is a new first time. When saving arrives, `gifts` is one
  of the fields that has to go in it.
- Test: `--headless res://tests/test_gift.tscn` (prints
  `GIFTTEST RESULT=PASS/FAIL`) — the catalogue, then the gift end to end on a
  real listen server: refused from 80 m away, handed over at Bram's feet, all
  four pieces arriving, asking twice getting nothing, and the conversation
  opening on the gift line before and the greeting after.
- `DialogSystem._on_answer` emits the action AFTER changing line, so an answer
  can both end the conversation and open something without `close()` undoing it.
- Trading is server-authoritative (see "Server authority"). Gold and the bag
  live in `Net.players[peer_id]["gold"/"items"]`, which only the server writes
  — the same registry gold that enemy drops pay into. The shop UI calls
  `Net.request_buy/request_sell`; the server checks the shop stocks it, that
  the price is ItemDb's price, affordability/holdings, and that the pawn is
  actually at the counter (`Net._at_counter`), then pushes the owner's slice
  back with `cl_purse`. Refusals arrive on `Net.trade_result` and show in the
  shop's hint line.
- Gold and items are stripped from the broadcast registry (`_public_players`)
  — only the owner ever sees theirs, and only through `cl_purse`. Anything on
  the server that changes them (a trade, a gold pickup) must call
  `_send_purse(id)` or the owner's screen goes stale.
- `GameStats.coins` / `.items` are read-only MIRRORS that `cl_purse` fills, so
  UI code reads them instead of the network layer. Writing to them changes
  nothing real.

## Item icons

- An item's picture is a PHOTOGRAPH OF ITS OWN ART FILE, taken when the game
  starts: the iron sword's icon is `tony_sword.fbx` at the size and tint that
  item wears, and the copper helmet's is `Armor1`'s head model in the colours
  `copper_armor.tres` paints it. There are no icon PNGs and no `"icon"` key —
  an item is described in ONE place, so a blade that gets fatter or a suit
  repainted in the Items tab cannot leave a stale drawing of itself behind on
  the shop rows. (The three shipped 64x64 sword placeholders are gone with it.)
- Which file gets photographed is `ItemDb.art_source(id)`, and it is the art the
  GAME uses: the `"hold"` model for anything carried, and for armor the piece of
  the suit named by its `"suit"` — `ItemDb.SUITS` maps the three tiers onto
  `Assets/Data/Armor/*.tres`. `ItemDb.build_model(id)` is that art as a node —
  its own colours, facing +Z, with nothing about a hand or a body applied — and
  is what to instance if an item is ever dropped on the ground.
- `ItemIcons` (autoload, `scripts/items/icons/item_icon_renderer.gd`) takes the
  shot: one small `SubViewport` with its OWN world (or the icon is taken inside
  the island, sky and all), an ORTHOGONAL camera three quarters on and slightly
  above, framed on the art's own bounding box so a boot and a greatsword both
  fill the frame, on a transparent background. Nothing is told how big it is.
- Anything much taller than it is wide is laid over diagonally (`LEAN_RATIO` /
  `LEAN_DEG`): a sword stood upright in a square icon is a thin line with two
  empty margins, and framing it to fill the height makes it unrecognisable. The
  stage is reset to upright before each shot is measured — measuring the next
  item while the last one's lean is still on it decides the angle off the wrong
  shape, which came out as two of three identical swords at different angles.
- THE STUDIO LIGHT IS NEUTRAL AND METERED, because the picture has to be of the
  ITEM's colour and not of the lighting. A coloured ambient tints everything
  towards itself and light totalling over 1.0 clips: the first version lit with a
  blue-ish ambient at full strength plus a 1.5 key, and a grey suit photographed
  as white while the copper one washed out to pale pink. White ambient
  (`AMBIENT`) plus one white key (`KEY_ENERGY`) adding to about 1.0 on the lit
  face is what makes an authored 0.729 grey come out at 0.729.
- The other half of that is `vertex_color_is_srgb` on the preview material. A
  part's colours are sRGB — a Goxel palette PNG and a Godot colour picker are
  both display values — so without decoding them every part renders about a
  tenth too bright no matter how the lights are set. NOTE: the RIGGED path
  (`_build_mesh`) does not set it, so voxel characters in the world are still
  drawn that tenth bright; making them match is a one-line change that would
  visibly darken every villager, so it is deliberately not bundled in here.
- A suit that photographs colourless IS colourless: the shipped `Armor1` art is
  red and white, and the flimsy/copper/iron suits repaint the plate grey, copper
  and white respectively. Recolour a suit in the Items tab and its four items
  follow — that is the point of the icons being renders.
- Rendered at 256 and shrunk to 64 with a filter rather than rendered at 64:
  cheaper than MSAA and the voxel edges come out cleaner. 64 is also what the
  old placeholders were, so no screen's layout changed.
- Asked for early, an item hands back an EMPTY `ImageTexture` and the art
  appears in it a frame or two later. The texture object never changes, so
  whatever is already drawing it redraws itself — that is what lets a
  synchronous `ItemDb.icon()` sit in front of something that needs a frame to
  happen. Every catalogue item is queued at startup, so a bag opened in the
  first second is already full of pictures.
- A tint is applied in one place, `ItemDb.tint_model()`, shared with the copy in
  a character's hand: what is being swung and what is in the bag must never be
  two different colours. White leaves the material alone rather than
  multiplying by it.
- HEADLESS RUNS TAKE NO PICTURES AT ALL — a dedicated server and every test in
  `tests/` have nothing to draw into, and `icon()` answers null there, which
  every screen already handles by drawing the item's name instead. So a test
  asks `ItemDb.art_source()` ("does this item HAVE a picture") rather than for
  the picture.
- Armor is photographed through `NpcRig.preview_mesh()`: the plate as drawn, in
  the suit's colours, bound to nothing. It skips the cell-claiming and the seam
  caps a rigged part needs, because both of those exist for the sake of
  MOVEMENT and nothing here can move.
- Test: `--headless res://tests/test_item_icons.tscn` (prints
  `ICONTEST RESULT=PASS/FAIL`) — every item HAS art and the file is there (the
  guard the hand-drawn icons never had: an item added with no art used to be a
  silent nameplate), each armor item is the right piece of its own suit, every
  item builds a model with triangles in it, the three tiers photograph in three
  different colours, a tint reaches the blade and an untinted item is left
  alone, and a headless run renders nothing.
- Eyeballing them: `godot --path . res://tests/preview_item_icons.tscn` (NO
  `--headless` — an icon IS a render) lays every item's real icon out on a sheet
  with its name and saves `user://item_icons_preview.png`. Framing, the angle
  and whether a boot is recognisable at 64 pixels are invisible headless.
  It also PRINTS a colour report — each plate's photographed colour against the
  colour its suit paints it, flagged `WASHED` past 0.12 — because a wash is hard
  to see and easy to measure, and that is the one thing about an icon a headless
  test cannot check.

## Hotbar

- Nine slots, server-owned like the bag: `Net.players[id]["hotbar"]` (item id
  or "" per slot) and `["hot_slot"]` (which one is in hand). They ride along
  with `cl_purse` into `GameStats.hotbar` / `.hot_slot`, so the UI reads the
  mirror and never writes it.
- Picking anything up drops it on the first free slot — `Net._refill_hotbar`,
  called from `_bag_changed(id)`, which every bag mutation must go through
  instead of `_send_purse` directly. It only does this the FIRST time an item
  is carried (`entry["seen"]`), so clearing a slot by hand stays cleared;
  losing the item entirely forgets it again.
- Requests: `request_hotbar_select(slot)` (the mouse wheel, R1/L1 or ] and [ in
  the world, a click in the panel), `request_hotbar_assign(slot, id)` ("" clears;
  assigning something already on the bar swaps rather than duplicating) and
  `request_use_item()`.
- WALKING the bar is event-driven, in `player.gd::_hotbar_event`, and that is the
  only place it happens. It cannot be polled: a wheel press and its release land
  in the same frame, so `is_action_just_pressed` on the physics step either misses
  the notch or sees it twice — and once the wheel is in the input map, leaving the
  poll in as well would count every notch on both paths. Wheel up steps back,
  wheel down steps forward. A scroll is also excluded from the "click back into
  the world to recapture the pointer" branch, since a scroll is not a click.
- DRAG AND DROP in the panel, on top of clicking rather than instead of it —
  there is nothing to drag with on a pad, which still walks the slots with the
  focus and takes them with `ui_accept`. It uses Godot's own
  `_get_drag_data`/`_can_drop_data`/`_drop_data` (hence `InventoryUI.DragSlot`,
  a Button subclass — those can only be overridden on a script), and every drop
  goes through `_on_slot_drop`, which is the one place the rules live: bag -> bar
  puts it there, bar -> bar moves it (the server's swap handles an occupied
  destination), bar -> bag takes it off. bag -> bag is deliberately nothing,
  because a bag slot's position is not stored anywhere — it is just where that
  item fell in `owned_ids()` this frame, so a "move" would be undone by the next
  redraw.
- Using is server-side: `Net._server_use_item` checks the pawn is alive and
  the slot really holds a carried item, then answers on the `item_used`
  signal. No item has an effect yet — that branch is the hook, and anything
  that changes the bag there must end in `_bag_changed(id)`.
- `inventory_ui.gd` draws both copies of the bar (the always-on one and the
  labelled "Hotbar" row at the top of the panel) from the same mirror. Slots
  are Buttons so the mouse clicks them and a gamepad walks them with focus;
  `ui_accept` (PS5 Cross / Xbox A) selects. A bag slot puts its item in the
  held hotbar slot; the held slot again clears it.
- Test: `--headless res://tests/test_hotbar.tscn` (prints
  `HOTBARTEST RESULT=PASS/FAIL`) — auto-placement, wrap/refusal of bad slots,
  swap-not-duplicate, cleared slots staying cleared, and use replies.

## Held items (what you can see in a hand)

- An item is drawn in the hand when its `ItemDb` entry has a `"hold"` block:
  `{"model", "scale", "pos", "rot" (degrees), "tint", "anim_set"}`, everything
  but the model falling back to `ItemDb.HOLD_DEFAULTS`. The defaults are where
  the grip meets the hand bone — fix a bad fit there once rather than per
  item. `"scale"` takes a Vector3 as well as a number, which is how the swords
  are broad enough to read at this art scale without growing to two metres.
  The three swords share one model and differ only by size and tint until each
  has art of its own.
- `"anim_set": "sword"` swaps in the clips in `HumanoidVisual.SWORD_CLIPS`
  while that item is held — idle, walk, run, the light swings and the heavy.
  `_clip_for()` does the swap inside `_play`/`_restart`, so anything with no
  sword version (block, slide, jump) keeps the bare-handed clip, and a
  character built without the sword clips falls back instead of erroring.
- STANDING and WALKING with a blade are the Mocap Online TC Sword pack on the
  MotusMan rig, whose bones are Mixamo's names minus the `mixamorig_` prefix —
  hence `bonemap_motusman.tres`, the Mixamo map with the prefix stripped, wired
  into each clip's `.import` exactly like the Mixamo ones.
- SWINGING it is Awesome Sword Animations V4, on the UE mannequin — so it reuses
  `bonemap_manny.tres`, the map Rouge already needed, with no new map to write.
  There are FOUR cuts, one per swing: three lights that chain and a heavy. Each
  is trimmed to its strike, and the slices were not eyeballed — the peak of the
  right arm's angular speed was measured and widened out to where it falls under
  a quarter of that peak.
- It replaced a real limitation, which is worth knowing if a future pack is being
  judged: the Mocap Online take is ONE 5.5s combo danced in a deep mocap crouch
  (hips from 1.00 down to 0.67 in the lunge), so exactly one cut of it was usable
  and every swing played that same slash. The V4 clips are the IN-PLACE (`_IP`)
  variants and their hips do not move at all, so there is no crouch to dodge and
  no root track to fight the lunge the game drives itself.
- The `_IP` / `_RM` split matters: `_RM` is root motion, and this game moves its
  own characters. Take the in-place half of any pack that offers both.
- A RETARGET IS KEYED BY NODE PATH, and getting it wrong fails SILENTLY: the
  `_subresources` block names the skeleton (`"PATH:SKM_Manny_Simple/Skeleton3D"`
  here, not the bare `"PATH:Skeleton3D"` the Mixamo clips use, because these
  exports put the skeleton under a mesh node). Point it at a path that does not
  exist and the clip imports perfectly with its ORIGINAL bone names, animating
  nothing — check a track path, not just that the import succeeded.
- Eyeballing them: `godot --path . res://tests/preview_sword_swings.tscn` (NO
  `--headless`) puts the iron sword in the player's hand and photographs each
  swing going in, at the strike, and coming out.
- A weapon never changes how fast you fight: `get_attack_info` measures the
  bare-handed clip even when one is held, and `on_attack_started` stretches
  the weapon's clip onto that window — so damage, hit time and the combo gate
  are the punch's, armed or not. `ARMED_SWING_RATE` runs the blade through a
  little quicker than the window and holds the finish, purely so the cut snaps
  instead of dragging; it is the dial to turn if a weapon feels sluggish, and
  it touches no gameplay timing.
- `HumanoidVisual.set_held_item(id)` parents the model to a `BoneAttachment3D`
  on `RightHand`, so it follows every clip and both Rouge and voxel NPCs get
  it for free. Calling it with the same id twice does nothing.
- Which item that is comes from the SERVER: `held` is the one part of a bag in
  `_public_players`, because it is in your hand where everyone can see it. Any
  bar change goes through `Net._hotbar_changed`, which re-syncs the owner's
  purse AND rebroadcasts the registry; `player.gd` redraws on
  `player_list_changed`. Read it with `Net.held_of(peer_id)` — that works on
  the server (which has the real bar) and on a client (which has `held`).
- Fitting a new weapon: put its `"hold"` block in, set `ITEM` in
  `tests/preview_held_item.gd`, and run
  `godot --path . res://tests/preview_held_item.tscn` (NO `--headless` — it
  renders). It writes `user://hold_preview.png` for eyeballing the grip.

## Levels

- EVERY item has a `"level"` in `ItemDb.ITEMS` — it is the item's rank. On
  anything you swing it is the damage it deals; on armor it is the damage it
  stops. Today: wooden sword and the flimsy suit 1, copper 2, iron 3, each suit
  matched to the blade it is named for in BOTH level and price (20 / 125 / 250
  a piece, so a full suit costs four blades). FISTS ARE LEVEL 0
  (`ItemDb.FIST_LEVEL`), which is also what an empty hand, an unknown id and an
  item that forgot the key all come out as, so a missing level is never a free
  upgrade. Every enemy has a `level` too (an `@export` on `enemy.gd`) and every
  bandit in the game is level 1.
- The maths lives in exactly ONE file, `scripts/combat/combat_levels.gd`, and
  nothing else may invent a curve of its own or two weapons will disagree about
  what a level is worth. Three ladders that never have to know about each
  other: `weapon_power(level)` (fists = 1.0, +21% a level) over
  `enemy_toughness(level)` (an ordinary level 1 enemy = 1.0, ±35% a level),
  multiplied into the swing's damage; and `armor_protection(total)` dividing
  what a blow takes off YOU.
- EVERYTHING HITS 40% SOFTER THAN THE LADDERS FIRST SAID, and it is done at BOTH
  ends of a blow rather than by cutting the exported damage numbers: a weapon
  level is worth 40% less than it was (0.35 -> 0.21) and an armor level 40% more
  (0.09 -> 0.126). Fists against an ordinary bandit are therefore still EXACTLY
  the exported numbers — the one line everything else here is measured against
  never moves — and only what your gear does to that baseline changed. The
  weapon ladder is now deliberately SHALLOWER than the enemy one, so a level 3
  blade no longer fully makes up for three levels of enemy: what is promised is
  that a blade beats bare hands against the SAME enemy, not that it out-damages
  a punch thrown at something far weaker. `test_combat`'s tough-enemy check
  measures both halves at the same enemy level for exactly that reason.
- An enemy's level moves what it SHRUGS OFF and what it HITS FOR, by the same
  factor (`enemy_scale`, floored at `MIN_ENEMY_SCALE`). Level 1 is still exactly
  the exported numbers, so nothing in the game changed — but a level 0 bandit
  now dies quicker AND punches softer, which is what makes it a weaker enemy
  rather than just a squishier one. Before this it only died quicker.
- ARMOR IS THE DEFENSIVE HALF, and it is protection, never health: your 100 hp
  is your 100 hp, a plate only makes each blow take less of it. Levels add up
  across the four slots — `Net.armor_levels(peer_id)`, the BEST piece per slot,
  so four helmets in a bag are not a suit — and `armor_protection(total)`
  divides what lands by `1 + 0.126 * total`. A full flimsy suit (4) is about a
  third less taken, copper (8) about half, iron (12) leaves about two fifths of
  a blow getting through.
  Applied in `Player.server_take_damage` to the HEALTH only, AFTER the guard has
  taken its cut and been charged for it: a plate stops a blow reaching you, it
  does not make holding a shield up cheaper.
- YOU HAVE TO PUT IT ON. Armor in the bag protects you from nothing;
  `Net.armor_levels` adds up the three EQUIPMENT slots
  (`Net.players[id]["equipped"]`), never the bag, so a mule carrying four
  helmets is as naked as one carrying none.
- WHAT THE LADDERS ARE TUNED TO, so a change to any number above can be checked
  against something: carrying a full level 1 set — wooden sword and all four
  flimsy pieces — you should be able to take on SIX level 0 enemies, or THREE
  level 1 enemies, and finish almost dead either way. Twice as many of the
  weaker ones for the same trip to the edge is what falling one level below the
  baseline is worth: a level 0 enemy both dies quicker and hits softer, so it
  costs about `0.65 * 0.65 = 0.42` of a level 1, and six of them come to about
  three. Where that lands today, with everything 40% softer: a level 1 bandit
  takes 9 light swings to put down and costs you 13.3 a hit, so you can afford
  about 2.5 hits from each of three; a level 0 takes 6 swings and costs 8.6,
  about 1.9 hits from each of six. Fights are longer and more forgiving than the
  original tuning, which is the point of the change. It is a TARGET, not a promise the code can keep — how much you actually
  take depends on how well you block and dodge, and on the health you regen
  between fights, neither of which a formula here can know. Play it, don't
  assert it.
- Both baselines are 1.0 today ON PURPOSE. Fists against a bandit scale
  *nothing*, so the exported numbers on `player.gd` and `enemy.gd` are still
  literally what happens — "base the stats off fists" and "the bandits are
  level 1" are the same statement — and a weapon is the first thing that ever
  moves that fraction. It is why the whole system could be added without
  retuning a single fight.
- ONLY DAMAGE SCALES. Knockback is deliberately left alone: which hits rock an
  enemy back (`Enemy.flinch_knockback`, the combo ender's
  `combo_finisher_mult`) is a readability promise to the player, and a good
  weapon must not quietly turn every jab into a stagger.
- Server-authoritative like the rest of combat: `_do_attack_trace` (server
  only) reads the level off `Net.held_of(peer_id)` — the server's OWN hotbar —
  and the target's level off the server's own pawn. Nothing in a swing request
  says what is in the hand.
- A target with no `level` at all counts as an ordinary one, so PvP is defended
  exactly as it always was and only the attacker's weapon matters.
- Making something tougher is now ONE number: raise its `level`. Do not start
  scaling health or damage by hand alongside it, or the two systems will fight.
- The level shows on screen wherever an item is named — shop rows, the bag
  tooltip, the cheat menu's give list — through `ItemDb.level_label()`, so the
  wording can never drift apart between them.
- Test: the `=== levels ===` section of `--headless res://tests/test_combat.tscn`
  — every catalogue item declaring one, the curve's shape, and then real swings
  through `_do_attack_trace` with the server's bar loaded: bare hands dealing
  precisely `light_damage`, each blade beating the last, a level 3 enemy eating
  part of a level 3 blade, and a levelled jab still not staggering. The
  defensive half is in `--headless res://tests/test_gift.tscn`: each suit
  letting less through than the last, every suit matching its blade in level and
  price, a level 0 enemy costing roughly half a level 1, and the same blow
  measured through the real `Player.server_take_damage` with the suit on and
  with it gone.

## Discord join notifications

- When somebody joins the dedicated server, `Discord` (autoload,
  `scripts/core/discord_notifier.gd`) posts an embed to a webhook: who joined,
  when, how many are on and who they are. The point is people seeing there is
  somebody playing and coming to join them, so the roster matters as much as
  the name.
- THE WEBHOOK URL IS A SECRET AND IS NOT IN THE REPO — anyone holding it can
  post to the channel as the server, and this repository is public. It is read
  at runtime from `ASTRIA_DISCORD_WEBHOOK`, or from `discord_webhook.txt` beside
  the server binary (or in the project folder in the editor), which `.gitignore`
  keeps out of git. No URL means no posting, which is a normal state, not an
  error. If it ever does get committed, rotate it in Discord — editing the
  commit away does not un-leak it.
- ONLY the dedicated server posts (`Net.is_dedicated`). A listen server is
  somebody's own machine: playing from the editor, a LAN game and every headless
  test in `tests/` all host one and register a player, so without that check a
  test run would post to a real Discord channel every time anyone ran the suite.
- Times are sent as Discord's own `<t:unix:F>` / `<t:unix:R>` markup rather than
  a formatted string, so every reader sees the join in THEIR timezone and the
  "3 minutes ago" keeps counting without the message being edited.
- A failed post is logged and dropped — it is a notification, not game state, so
  nothing retries into a loop. Posts queue behind a `MIN_GAP` and stop being
  queued past `MAX_QUEUED`, so a client stuck in a reconnect cycle cannot flood
  the channel.
- Test: `--headless res://tests/test_discord.tscn` (prints
  `DISCORDTEST RESULT=PASS/FAIL`). It POSTS NOTHING: it checks the message that
  would be sent, and that a non-dedicated run queues nothing even with a URL
  configured.

## Development cheats

- Z (or the PS5 Options / Xbox Menu button) opens the cheat menu —
  `scripts/ui/debug/cheat_menu.gd`, autoload `CheatMenu`. It offers "Give item"
  (everything in `ItemDb.ITEMS`; picking one asks the server for a copy),
  "Quest" (everything in `QuestData.QUESTS`, plus "Clear quest"),
  "Teleport" (everything in `TeleportData.DESTINATIONS`, plus "Enter starter
  town") and "Start tutorial". Adding a cheat is one row in `_build_root`.
- "Start tutorial" goes through the server like everything else, and is a real
  restart: a fresh copy of the island with its own bandits.
- "Enter starter town" sits under Teleport but is not a `TeleportData`
  destination, because it is not only a place: inside the tutorial it
  GRADUATES you (`Tutorial.server_end(id, true)`), so the copy of the city is
  torn down, its bandits go with it and the follow-up quest is handed over —
  the same exit the last lesson uses. Teleporting out would leave the lesson
  running behind you. Outside the tutorial it is a plain hop to the island
  spawn.
- A conversation does not keep the menu shut (the box is closed on the way in).
  Half of what these cheats are for is getting out of something that is talking
  to you — an NPC, or a gate you cannot find the button for.
- It is editor-only at BOTH ends: the menu doesn't build unless
  `OS.has_feature("editor")`, and every `Net._server_cheat_*` refuses unless the
  SERVER is an editor run (`Net.cheats_allowed`). So an exported dedicated
  server ignores cheats however the client is patched — cheats still go
  through the server like any other bag change, never applied locally.
- Teleport destinations are NAMES, never coordinates: `TeleportData` (in
  `scripts/world/teleport/`) lists the places, and each one's position comes
  from a `TeleportAnchor` (`scenes/world/teleport_anchor.tscn`) dropped in the
  level, found through the group `teleport_<id>` — the same "a marker in a
  group IS the place" trick as `spawn_point.gd`. Move the anchor in the editor
  and the teleport moves with it; a destination with no anchor yet answers
  "has no anchor in this level yet" and is listed as such, which is what you
  want while the place is still being built.
- The teleport itself is server-authoritative like everything else: the server
  moves ITS copy (`Player.net_teleport`, which also moves `net_pos`) and then
  tells the owner where it is with `cl_force_position`. Doing it the other way
  round is exactly what the position validator exists to reject.
- Test: `--headless res://tests/test_teleport.tscn` (prints
  `TPTEST RESULT=PASS/FAIL`) — refusals when unanchored or unknown, and the
  pawn plus `net_pos` landing on the anchor.
- A dedicated server launched with `--dev-items` instead hands every player
  one of each catalogue item at registration (`Net._starting_items`).

## Building NPCs

- The "NPC Builder" tab (editor plugin in `addons/npc_builder/`) assembles a
  villager from voxel parts, colours it, rigs it and saves it. Saving writes a
  pair: the data (`Assets/Data/Npcs/<name>.tres`, an `NpcDefinition`) and a
  placeable scene (`scenes/entities/npc/built/<name>.tscn`). Drag the scene
  into the world like any other prop — everything under it is rebuilt from the
  definition at load, so recolouring an NPC updates every copy already placed.
- Part models live in `Assets/Models/Entity/Humanoid/VoxelNpc/Parts/<Set>/
  <Slot>/`. `<Set>` is a character family (`Base`, `Undead`, `King`) and becomes
  its own section in the builder's menus; `<Slot>` is Head/Body/Arms/Feet. Drop a
  Goxel glTF export in the right folder and press "Rescan parts" — there is no
  metadata to register. Armor is the same idea in a SEPARATE library,
  `VoxelNpc/Armor/<Suit>/<Slot>/` — see "Armor" below for why it is not just
  another set. A set needs all four slots: `test_npc_builder` builds
  one NPC per set out of that set alone and fails if a slot is empty.
- Keep the `.gox` next to the `.gltf` it was exported from (as
  `king_head.gox` / `king_head.gltf`), so the source of a part is never a
  question of which Downloads folder it came from.
- AN UPDATED PART OVERWRITES ITS FILE. It does NOT land beside the old one under
  a new name. A slot's models are all offered in the builder's menu and the
  DEFAULT is whichever sorts first, so a new `arms_base1.gltf` next to
  `arms_base.gltf` does not replace anything — it just means every new character
  silently starts with the superseded arms while the head (`basic_head.gltf`,
  which sorts before `head_base.gltf`) starts with the new one. That mongrel is
  what "the character creator is using the wrong files" looks like from the
  outside, and re-exporting from Goxel never fixes it because the file being
  updated is not the file being used. When someone sends a new version of a part,
  copy it over the existing filename.
- Several models in ONE slot is for genuine variants — the Undead's `skeleton_*`
  and `zombie_*`, which are two characters, not two drafts of one. If the new
  file is not a thing you would want to pick between, it is an update, so see
  above.
- The builder only ever reads the **glTF**. Editing a `.gox` and saving it
  changes nothing on its own — Goxel's "Export as glTF" has to be run again, or
  `python tools/voxel/gox_to_gltf.py <in.gox> <out.gltf>` used instead. If a
  part looks like an edit you know you made never landed, check whether the
  `.gox` is newer than the `.gltf`.
- Parts are auto-fitted, never hand-placed. Left-to-right each is centred by
  matching the art against its own mirror image rather than by its bounding box
  (a stray voxel off to one side is common in a work-in-progress model, and a
  bbox centre would let it drag the whole model sideways). Front-to-back it is
  the plain bbox middle: nothing about a character is symmetric on that axis —
  a foot has toes at one end — so a mirror fit there scores noise and used to
  stand the feet a voxel ahead of the torso. Feet/body/head then stack, while the
  arms are anchored to the TORSO's frame — which is why the undead arms, drawn
  up at shoulder height, land there instead of at the hips. "Adjust placement"
  per slot is the escape hatch when art needs a nudge.
- Parts never draw over each other. A voxel an earlier slot already fills is
  dropped from the later one (slot order: feet, body, arms, head), because
  models get drawn with their neighbours in view for reference and exported
  with them still there — the base arms carry a complete copy of the torso.
  Two parts painting one cell means two coincident surfaces z-fighting, which
  looks like the NPC flickering inside out. The test asserts it never happens.
  Ownership is settled for the WHOLE character before any mesh is built, so a
  part can see which bone the voxel next door binds to — which is what the seam
  caps below need, and next door is often the next part along.
- Voxel art carries no faces BETWEEN two touching voxels: Goxel exports only the
  outside of a model, and nothing needs any while the pair cannot move apart.
  Rigid skinning moves them apart. A voxel bound to Chest and the one beside it
  bound to Hips separate the moment the spine bends, and with no face on either
  side of the join you are looking straight THROUGH the character — the row of
  dark wedges that opened across the chest and down the arms of every built NPC
  as soon as anything animated. Worse in armor, which rides the same bones from
  a voxel further out and so swings further.
- THE RULE: what one bone carries has to be a CLOSED surface on its own, because
  a bone is what moves as a unit. So `NpcRig._add_seam_caps` gives a voxel a face
  on any side the art left bare, UNLESS the voxel next to it is the same part on
  the same bone — only then can the two never part. Where two of them meet, the
  pair sits back to back on one plane facing opposite ways, so each is the
  other's backface and neither is drawn until the joint actually opens.
- Three ways a side ends up bare, and only the first is a bone boundary: the
  neighbour is the same part on a DIFFERENT bone (the chest join); the neighbour
  was this model's own voxel and got dropped because an earlier part filled that
  cell (every arms model carries a copy of the torso it was drawn against, the
  torso wins those cells, and what is left is an arm with no end on it — the
  hole at the shoulder); or the neighbour is a different MESH on the same bone
  (nothing moves apart, but nothing of ours covers the join either — a helmet
  cut around a head is open all the way round its rim).
- Sides the art ALREADY draws are left alone. A second face pointing the same way
  as an existing one is exactly the z-fighting the rest of this file avoids.
- `NpcRig._fill_interior` adds the voxels the exporter never wrote at all: Goxel
  writes only faces you could have seen, so a cell walled in on six sides is
  absent from the model. Capping the rim is then not enough — a bone boundary
  through the middle of a solid part has nothing on it, and the shell comes apart
  as two rings with a hole down the middle of each. Which cells are enclosed is
  not a guess: flood the air AROUND the part and whatever the flood cannot reach
  is inside it. Filled cells wear the colour of the surface cell that found them,
  and it runs on the shape as DRAWN, before anything is handed to an earlier part
  — a part eaten down to a stump is full of holes for a flood to pour through.
- Both halves are load-bearing: without the caps a plain villager leaves 304 open
  edges and an armoured one 1000; with the caps but no interior fill, still 120
  and 162. Together, zero. It costs a villager about 60% more triangles and a
  head nothing at all (one bone, no seams).
- Fixing it in the art instead would mean re-exporting every part ever made with
  interior faces on, tripling the triangles, and writing faces at every join
  when only the ones straddling a bone can ever come apart.
- The winding of those caps is read off the art (`_winding_sign`) rather than
  assumed: the exporter already wound its own triangles correctly, and a cap
  wound backwards is invisible — which looks exactly like not having written it.
- A face's centre is the min/max of its triangle's corners, NOT the triangle's
  centroid, which sits a sixth of a voxel off it (a square is two triangles and
  each leans towards its own three corners). That was close enough to say which
  voxel a face belongs to and nowhere near close enough to build on: the caps
  landed a sixth of a voxel proud and dragged the mesh's bounding box with them.
- Test: `_check_joins_are_capped` / `_open_edges` in `test_npc_builder` — every
  edge of every BONE GROUP is shared by exactly two of its triangles, which is
  what "closed" means; an edge used once is the rim of a hole. Per bone group,
  not per mesh: a mesh can be perfectly closed and still open up the moment two
  of its bones part. Edges used more than twice are NOT holes — that is two
  surfaces meeting along a line, which is what a cap does in a concave corner.
  Checked on the rest pose (a holed group is holed whether or not the clip is
  pulling it open this frame), bare and armoured.
- When comparing vertices by name, force zero positive: negative zero prints as
  `-0.0000` and positive as `0.0000`, so every vertex on the centre line matches
  nothing and every part looks split down the middle. That cost a round of
  chasing holes that were not there.
- That reference copy is also why a SET IS WORN WHOLE. An arms model carries the
  torso it was drawn against, and only the cells its own body covers get dropped
  — put it over another set's body and the leftover reference torso sticks out
  of the chest (the King's robe against the Base arms is the case that showed
  it). The Base arms are a modelling backdrop, not a universal part. So
  `test_npc_builder` checks each model against the rest of ITS OWN set, and the
  builder's freedom to mix sets is for authoring, not a promise that any two
  families fit.
- Colour: a model's Goxel palette becomes one swatch per entry. Past 8 entries
  the model is hand-shaded (the zombie parts run to dozens of noise shades) and
  only the per-part tint is offered — the tint multiplies over everything and
  is always available.

## How built NPCs are rigged

- Built NPCs animate off the SAME clips as the player. `NpcVisual` and
  `RougeVisual` are both `HumanoidVisual` (`scripts/entities/humanoid_visual.gd`),
  which owns the skeleton, the Mixamo clip library and the tick/attack/death
  API; subclasses only supply a model. An NPC's skeleton IS Rouge's — rouge.fbx
  is instanced, its meshes are thrown away, and the bones are kept.
- `NpcRig` (`scripts/entities/npc/npc_rig.gd`) then does two things:
  - Reshapes the skeleton onto the voxel proportions instead of stretching the
	art onto human ones. That is only safe because the retargeted clips are
	rotation-only — every bone but Hips has just a rotation track, so rest
	positions are free to move. If the animations are ever reimported with
	per-bone position tracks this silently breaks; the test catches it.
  - Rigidly skins each part: one bone per voxel, weight 1, picked by nearest
	bone segment within that slot's allowed bone set (`BIND_SETS`). Whole
	voxels are bound as units, so they rotate about joints instead of tearing.
- KEEP `BIND_SETS` SHORT. Every bone in a set is another pivot cutting the art
  into another rigid slab, and a slab shears against its neighbour on every
  frame it animates — a body bound to Hips/Spine/Chest/UpperChest/Neck is a
  seven-voxel torso in four pieces sliding on each other, which is what made a
  walking villager look like it was coming apart. A humanoid rig offers far more
  joints than voxel art this coarse has any use for. Today: legs keep
  hip/knee/ankle (no toes — a two-voxel boot has nothing to flex), the body has
  ONE hinge at the waist, the arms keep shoulder and elbow (no wrist — a voxel
  fist has no knuckles, and a held item hangs off a `BoneAttachment3D` on
  RightHand, which does not care how the mesh is skinned), and the head is one
  piece. Adding a bone back is a visible cost, not a free improvement.
- `UpperChest` stays in the ARMS set and is not for the arms: it is what catches
  the copy of the torso every arms model carries, so that section stays put
  instead of grabbing an arm bone and flying off with it.
- `NpcVisual._adapt_hips` rebases the clips' Hips position track per NPC — it
  was authored around a human pelvis and would otherwise yank a short-legged
  voxel NPC up to Rouge's hip height.
- The ARM is fitted at TWO points where every other chain gets away with one
  scale, and that is what keeps a character's arms outside its own chest. Height
  is remapped through shared landmarks and width is one factor per chain, but a
  single factor can only ever land the HAND or the SHOULDER, not both — and a
  voxel character is a third as wide as it is tall where the human rig it
  borrows its skeleton from is not. Scaled to land the hands, its shoulder joint
  came out a good way INSIDE the torso, so every clip swung the arms through the
  body and the hands hung down in the hips where the two met in front. So
  `arm_root_x` is measured off the ART — the torso's own half-width plus half
  the arm's thickness, which is the pivot an arm can swing DOWN about and land
  flush beside the body rather than in it — and the chain is remapped piecewise
  through [0, shoulder, hand] exactly the way heights already are.
- No CLAVICLES in `BIND_SETS["arms"]`, for the mirror of the reason there are no
  shoulders in the body set. A clavicle runs from the spine out to the shoulder
  joint, so once the joint moved out its segment lay along the inner half of the
  sleeve and claimed it — and a clavicle barely rotates in these clips while the
  upper arm swings the whole way. One rigid sleeve split between a bone that
  moves and a bone that does not tore into a sawtooth at the shoulder. A voxel
  arm swings whole, shoulder cap included.
- What is LEFT is inherent and worth knowing before chasing it: rigid voxel
  blocks with no gap between them interpenetrate slightly wherever a joint bends
  — at the elbow and the knee, and where the head meets the shoulders.
  The art is drawn flush on purpose (a gap reads as a floating head in the bind
  pose), so short of authoring joint clearance into the models there is nothing
  to fix there. The bind pose is clean; only bent joints show it.
- Only ever judged in MOTION. Every one of the faults above is invisible in the
  bind pose, which is the only pose a still frame of the builder shows — the
  T-posed character looked perfect the entire time its arms were pivoting inside
  its chest. `tests/preview_npc_armor.tscn` and a posed render are what catch
  this class of thing; the bind pose alone will not.
- A rigged part is BOTH skinned and POINTED at the skeleton
  (`mi.skeleton = NodePath("..")`). A code-made `MeshInstance3D` starts with
  that path empty and being a child of the `Skeleton3D` does not fill it in, so
  without the line every part drew its bind pose while the bones underneath
  animated perfectly — every built NPC in the game was a T-posed statue, and no
  bone-level assertion could see it. The test now checks the path itself.
- AN NPC ANIMATES ITSELF, off its own movement: `NpcCharacter._process` measures
  its own ground speed and hands it to `HumanoidVisual.tick_motion`, which picks
  the pose and the stride rate. Nothing was ticking a placed NPC's visual at all,
  so every villager and King in the world stood in whatever pose its
  AnimationPlayer loaded with, and the tutorial's villager slid across the island
  without moving her legs. Measuring rather than being told means anything that
  MOVES an NPC gets the walk for free — the tutorial arena just changes her
  position, as it always did.
- Anything that turns an NPC to face something uses `atan2(-x, -z) + PI`, the
  same as `Enemy.face_toward`: these rigs are modelled facing +Z, so a plain
  `look_at` turns their back to whoever they are looking at. That is what had the
  tutorial's villager walk over backwards.
- A visual builds itself when it enters the tree, and never twice. `_ready`
  fires in the editor too: `HumanoidVisual` has no `@tool`, but that only
  governs scripts the editor loads with a scene — tool code that says
  `NpcVisual.new()` gets a live instance whose notifications run normally. So
  editor callers (the builder preview, `NpcCharacter` in the world view) just
  `add_child` and are done; calling `build()` as well used to parent a second
  model, skeleton and mesh set over the first, which is what made an NPC look
  like its meshes overlapped. To skip the clip library for a static preview,
  set `build_clips = false` BEFORE adding the node.
- `NpcDefinition` and `NpcPart` MUST stay `@tool`, and it has nothing to do
  with wanting to run in the editor. A resource the editor LOADS FROM DISK gets
  a PLACEHOLDER instance when its script is not a tool script: the exported
  properties are all present, but every method call dies with "Attempt to call
  a method on a placeholder instance". `NpcRig.rig()` reaches its parts through
  `def.get_part(slot)`, so an NPC dragged into a level collected no parts at
  all and came out as a correctly proportioned skeleton with no body — while
  the builder's preview, whose definition is a live `NpcDefinition.new()` and
  not a loaded file, looked perfect. Any new Resource whose methods are called
  from tool code (a builder, an `@tool` node like `NpcCharacter`) needs the
  same. Nothing in a headless run is ever a placeholder, so the test asserts
  `is_tool()` directly rather than trying to rig one.
- Test: `--headless res://tests/test_npc_builder.tscn` (prints
  `NPCTEST RESULT=PASS/FAIL`). It rigs every part model in the library, checks
  the bind sets, that animation still moves the reshaped bones, that re-rigging
  is idempotent, that building twice still leaves one of everything, that
  colours reach the mesh, and that a saved NPC reloads as a talkable scene —
  plus that Rouge still builds his own rig and full clip set, and that the
  player's own body builds, animates and can hold a sword. It also checks, for
  every set, that an arm swung down to the character's side clears the torso and
  that one sleeve rides one bone — measured off the RIGGED skeleton rather than
  out of the layout that placed it, or the assertion would only be agreeing with
  itself.

## The player's body

- The player IS a built NPC: `scripts/entities/player_visual.gd` (`PlayerVisual`
  on the `Visual` node of `scenes/player.tscn`) is an `NpcVisual` fixed to
  `Assets/Data/Npcs/player.tres`, the "Player" character saved out of the NPC
  Builder. So the player is rigged, proportioned and animated by exactly the
  machinery every villager uses, and recolouring "Player" in the builder
  redresses every pawn in the game — local and remote alike, since all of them
  are `scenes/player.tscn`.
- The definition is a const in the script, not an export on the node: which body
  a player wears is not a level-editing decision, and one file is what keeps
  every pawn identical.
- The one thing it overrides is the clip list — `_clip_keys()` returns the WHOLE
  of `CLIPS`. `NpcVisual` trims it to idle/walk/run because a villager stands
  around; a player blocks, slides, jumps and swings.
- Rouge (`rouge_visual.gd`) is still the ENEMIES' model and still the source of
  the skeleton every voxel character is rigged onto — `NpcVisual` instances
  rouge.fbx for its bones. Deleting him is not an option.
- Fitting a weapon is previewed on the player's hand now
  (`tests/preview_held_item.gd`), because the player is the only thing in the
  game that carries anything and a voxel fist is not the shape Rouge's was.

## The Items tab

- `addons/item_builder/` adds the **Items** tab beside 2D / 3D / Script / NPC
  Builder. It is where the things characters carry and wear are MADE. It opens
  on a menu of what can be made rather than on an editor, because "Items" is not
  one thing: armor is the first kind, and the next (a weapon, a shield) is
  another button on that menu and another pane beside the armor one.
- "Create armor" opens the armor pane: a name, the four pieces, a colour swatch
  per palette entry and a tint each, on a turntable. **Save** writes one file,
  `Assets/Data/Armor/<slug>.tres` — an `ArmorDefinition`.
- MADE here, WORN in the NPC Builder, and that split is the point. A suit is
  authored and coloured once and then put on any number of characters in one
  move, so recolouring the town guard is one file instead of twenty NPCs.
- A SUIT is not an armor MODEL SET. `NpcRig.ARMOR_ROOT` is the raw art in the
  colours it was drawn in; a suit is that art dressed — pieces chosen, palette
  overridden, tinted, named. The NPC Builder's picker offers both, under
  "Saved suits" and "Armor sets", and the metadata says which so applying one
  never has to guess from the label.
- BOTH HALVES ARE ONE EDITOR SESSION, and the NPC Builder tab is built ONCE when
  the plugin loads. So its suit list has to be REBUILT on the way into the tab
  (`_notification(NOTIFICATION_VISIBILITY_CHANGED)`) or it is a snapshot of
  `ArmorLibrary.DIR` as it stood at editor startup: every suit made afterwards is
  simply absent, and the only way to reach your own armor is knowing that a
  button called "Rescan parts" rescans suits too. Whatever is picked survives
  that rebuild, or returning to the tab would swap the suit under the character
  you left half-dressed. Anything else that lists files made by the OTHER tab
  needs the same treatment.
- `ArmorDefinition.wear()` hands the character COPIES of its pieces. If it
  handed references, recolouring one guard in the NPC Builder would rewrite the
  suit file and every other guard wearing it. `take_from()` is the other
  direction, for making a suit out of what a character already has on.
- `ArmorLibrary` (`scripts/items/armor/`) owns the folder, the listing, the slug
  and the save, so neither tab invents a path of its own. It refuses to hand
  back anything that is not an `ArmorDefinition` — the NPC definitions live one
  folder over and files get dragged around.
- The suit is previewed ON a Base villager, never floating on its own: the rig
  builds its height stack from feet, body and head, so a character made only of
  armor has no height to be rigged by — and a suit hanging in the air tells you
  nothing about whether it fits.
- The tab REUSES the NPC Builder's part-picker and turntable rather than copying
  them (a suit is made of the same `NpcPart`s an NPC's armor layer holds), so
  `item_builder` depends on `npc_builder` being enabled. Both ship together and
  are enabled together in `project.godot`.
- `ArmorDefinition` MUST stay `@tool`, for the reason `NpcDefinition` documents:
  a loaded .tres whose script is not a tool script comes back as a placeholder
  and `wear()` dies on it.
- Test: `--headless res://tests/test_armor_suits.tscn` (prints
  `ARMORTEST RESULT=PASS/FAIL`) — an empty suit is refused, a saved one comes
  back with its colours, wearing copies instead of linking, a worn suit really
  rigs in its own colours, the library refuses an NPC definition, the Items tab
  builds and its Create armor button produces something, and the NPC Builder
  offers the saved suit and puts it on in the colours it was authored in while a
  raw set still arrives as drawn. The tab is also opened BEFORE a suit is saved
  and shown afterwards, which is the only way to catch the stale-list case above
  — a test that builds the screen after the save passes either way.

## Armor on a built NPC

- Armor is a LAYER over a character, never a character set of its own. The
  builder's "Wears armor" switch reveals four more slots — `feet_armor`,
  `body_armor`, `arms_armor`, `head_armor` in `NpcDefinition.ARMOR_SLOTS` — each
  worn over the slot it names, each with its own palette and tint. Switching it
  on puts the first suit straight on (a switch that visibly does nothing reads
  as broken); switching it off calls `clear_armor()` and the character
  underneath is untouched.
- Suits live in their own library, `VoxelNpc/Armor/<Suit>/<Slot>/`, NOT under
  `Parts/`. Filed as a character set, a suit would appear in the set picker and
  "use whole set" would build a walking empty suit with no head, no hands and
  nobody inside it. `NpcRig.categories_for(slot)` is what keeps the two menus
  apart, so a helmet can never be picked as a head.
- A plate is drawn IN PLACE around the part it covers — same Goxel grid, one
  voxel out on each side — so the rig takes the covered part's centre wholesale
  instead of re-centring the plate on its own bounding box, which would slide a
  breastplate off the chest it was drawn around. It is the same trick the arms
  already use to sit in the torso's frame. Draw armor over the body it is for,
  delete the body, export: the fit is then whatever you drew.
- NOTHING on the armor layer feeds the height stack, so a helmet cannot make an
  NPC taller and no plate moves a single bone. Armor rides the bones of the slot
  it covers (`BIND_SETS[covers(slot)]`) — there is no such thing as an armor
  bone — and an armor part's `scale` is RELATIVE to what it covers, so scaling a
  body carries its plate with it.
- Armor is rigged LAST (`NpcDefinition.ALL_SLOTS` is skin then armor), which is
  also the order voxels are claimed: a suit exported with part of the reference
  body still in it loses that copy rather than z-fighting the real one.
- Recolouring is per piece: each armor slot gets the same swatch-per-palette-
  entry treatment as any part, so a suit is recoloured without touching the
  character wearing it. Keep an armor model's Goxel palette at or under
  `SlotEditor.SWATCH_LIMIT` (8) entries or the builder can only offer the tint —
  the test asserts this, because a suit you can only tint is not a suit you can
  recolour.
- Shipped: `Armor1`, all four pieces, in `Armor/Armor1/`, with the `.gox`
  sources beside the exports as everywhere else.
- Test: the armor sections of `--headless res://tests/test_npc_builder.tscn` —
  the library is complete and separate, a suit adds four meshes and changes no
  landmark and no bone, each plate is concentric with and wraps what it covers
  (the check that catches a helmet re-centred off the head), armour and skin
  never paint the same voxel, colours and tint reach the plate and nothing
  leaks onto the body, and taking the suit off leaves no meshes behind.
- Eyeballing it: `godot --path . res://tests/preview_npc_armor.tscn` (NO
  `--headless`) stands the same villager bare, in the suit, and in a recoloured
  suit, and writes `user://npc_armor_preview.png`.

## Dungeons

- `scenes/starterDungeon.tscn` is the floor model (`dungeon1.glb`) and nothing
  else; the stone shell around it is GENERATED at load by `scripts/world/
  dungeon/dungeon_walls.gd` on the `Walls` node under it. Nothing is
  hand-placed, so do not add wall transforms to the .tscn — reshape the floor
  in Blender and the walls follow it.
- THE WALLS COME FROM THE FLOOR'S OWN OUTLINE. Every triangle is rasterised
  straight DOWN into a grid, the outside is flood-filled, and a wall goes on
  each edge between a cell the flood reached and one it did not. There is no
  plan, no marker and no list of runs to keep in step with the art.
- THAT REPLACED WALLING THE BOUNDING BOX, which is worth knowing before anyone
  "simplifies" it back. Tracing the model's bounds plus a few hand-written
  interior runs works only on a rectangular slab: on a real plan — an L of
  rooms, a corridor, a staircase — it walls a rectangle round the lot, putting
  walls across open rooms and burying the corridor. That is what the first
  version did and why it was thrown away.
- THERE ARE NO DOORWAYS AND NOTHING NEEDS ONE. An opening is simply where the
  floor carries on, so rooms join wherever the floor joins them. The old
  version had to cut doors back into walls it should never have drawn, keyed to
  `*Enterence` markers that had to be kept in step by hand. `halfdoor.gltf` is
  consequently unused — if real doors are ever wanted they are a new feature,
  not a resurrection of that machinery.
- STAIRS AND SPLIT LEVELS COST NOTHING. Flattening throws the height away, so a
  staircase is solid floor and gets walls down both sides rather than one
  across every step; the height comes back per block off the floor beside it,
  so a wall climbs with the stairs. A stair riser is upright and flattens to a
  LINE with no area, so triangle EDGES are stamped as well as triangle area —
  sample by area alone and a staircase punches a hole through the footprint.
- Flood-filling from the OUTSIDE rather than taking every inside/outside edge
  is what fills holes in: a gap the mesh happens to leave, or a pillar modelled
  into the floor, would otherwise get its own little wall ring mid-room.
- `prefab_scale` (0.2) converts the raw voxel prefab to player scale: one COURSE
  of wall 3.8 m tall against a 1.92 m capsule. `cells_per_wall` (4) is how
  closely the outline hugs the real floor edge. Tune both there, not by scaling
  nodes.
- HOW TALL THE DUNGEON IS, is `ceiling_height` (6 m) and nothing else. It is
  head room over the HIGHEST bit of floor, so the lid is one flat surface for
  the whole plan and walls are NOT all the same height — each runs from the
  floor it borders up to that one ceiling, stacking courses of the prefab to
  reach it. A ceiling that stepped with the stairs would meet itself in a slit
  you could see the sky through; courses rather than one stretched block is so
  that a taller dungeon does not mean visibly taller voxels.
- THE ROOF IS A FLAT MESH, not blocks. A voxel wall is ~3.5k triangles, and a
  roof's worth of them is about a million overhead on a surface nobody can get
  within four metres of; the ceiling is quads (merged into runs along X) in
  `roof_colour`, with collision off the same triangles. It reaches to the
  boundary LINE, which is the middle of a wall, so roof and wall always overlap
  by half a wall's thickness and there is no seam to keep in step.
- A ROOFED ROOM LOSES THE SUN. The island's sky ambient still reaches inside, so
  it is not black, but it reads flat — hence the lamps under the ceiling
  (`light_energy`, `light_spacing`, `light_colour`; 0 energy turns them off).
  Their COUNT is capped at `MAX_LIGHTS` (8) rather than by the spacing, because
  the Compatibility renderer only applies a handful of lights to any one mesh
  and the dungeon floor is a single mesh — a ninth lamp would light nothing.
  Each is nudged to the nearest cell of floor with floor all round it, or an
  even grid over an L-shaped plan hangs lamps in the courtyard.
- THE CRACK ALONG THE BOTTOM, and why `_bite()` exists. The grid is deliberately
  conservative (stair risers, above), so a boundary line can sit up to one cell
  OUTSIDE the real floor edge; a block centred on that line reached only half
  its thickness back in, and the floor stopped short of its inner face by up to
  0.2 m — a slot at ankle height with the void behind it, the length of the
  wall. Every wall is therefore stepped INTO the room by exactly the worst case
  the grid can be wrong by, which is derived rather than dialled: a finer
  `cells_per_wall` shrinks it to nothing by itself. The same fault turned on its
  side is why a block stands on the LOWEST floor under its whole length rather
  than the height at its middle.
- Solid stretches are tiled to FIT (count rounded, length stretched), never at
  a fixed size with the last block hanging over — the overhang pushes blocks
  through each other at junctions, giving coplanar faces that z-fight exactly
  like overlapping NPC parts. Perpendicular blocks DO interpenetrate at every
  corner, on purpose: both runs cover it, which is what makes a corner solid
  instead of notched, and they share no coplanar face.
- PACKED ARRAYS ARE VALUE TYPES, which cost two rounds of debugging here. A
  `PackedByteArray`/`PackedVector3Array` handed to a helper is COPIED, so the
  helper fills in the copy and the caller sees nothing — the builder reported
  no error and built no walls. Hence the grid lives in members and the
  triangles are collected into a plain `Array`. Anything new that accumulates
  into a Packed array through a function call has the same trap.
- YOU GET IN BY WALKING INTO THE DOOR. `scripts/world/portal/portal.gd` is a
  `Portal`: stand within its `radius` and you come out at whatever
  `TeleportAnchor` wears its `destination_id`. Both ends are NAMES, so moving
  either in the editor moves it — the same trick as `TeleportAnchor`,
  `QuestAnchor` and `spawn_point.gd`. Today: `catacombs_entrance.tscn` on the
  island sends you to `catacombs`, and the `ExitPortal` inside the dungeon
  sends you back to `catacombs_exit` beside the door.
- Server-authoritative like every other way a pawn moves. The portal is polled
  on the SERVER against its own speed-validated copy of each pawn, and moves it
  through `Net.server_teleport_to` — the same call the teleport cheat uses, so
  there is one place that knows how a pawn crosses the level. Deliberately NOT
  an Area3D: a trigger volume answers "is a body touching my shape", which
  needs the pawn on the right collision layer and reports on the CLIENT too,
  where the answer means nothing.
- A portal does NOT fire on somebody who ARRIVED inside it (`_seen_outside`), and
  that is load-bearing rather than tidy: a return portal and the anchor players
  land on are near each other by nature, so without it the two ends bounce a
  player between them forever. Walking up to a portal is always seen from
  outside first, so the ordinary case is unaffected. Any new portal pair
  inherits this; do not "simplify" it away.
- The dungeon is parked at `-3000, 0, 0` — far enough that the two ends of the
  portal cannot sit in each other's radius, which `test_catacombs` asserts. It
  is at its natural height rather than buried; now that it has a lid, burying it
  is a level-editing decision nothing in the code cares about either way. Where
  it belongs is the same kind of decision: drag the `Catacombs` node.
- Test: `--headless res://tests/test_catacombs.tscn` (prints
  `CATATEST RESULT=PASS/FAIL`) — the round trip on a real listen server: the
  door really lands you in the dungeon, the dungeon really is somewhere else,
  standing where you arrived does not throw you back out, and the way home
  comes out beside the door. Plus that the quest finally has a star.
- Test: `--headless res://tests/test_dungeon_walls.tscn` (prints
  `DUNGEONTEST RESULT=PASS/FAIL`). It re-measures the floor ITSELF off the mesh
  rather than reading the builder's grid back, then checks that no wall stands
  in open floor (the bounding-box bug), that there is enough wall to go round
  the perimeter, that walls sit at the height of the floor beside them, that no
  two parallel blocks share space, that every piece has collision, and that
  rebuilding does not duplicate. Note the collision shape is found by TYPE: a
  node parented before its parent is in the tree auto-names to
  `@CollisionShape3D@48`, and the old test's name lookup silently matched none
  of them, so its overlap check passed on an empty set. It also walks in from
  outside each wall to find where the floor really starts, which is the crack
  along the bottom measured the way a player sees it, and checks every wall
  reaches the ceiling, that the ceiling is flat and covers the plan, and that
  the lamps hang over rooms.
- Eyeballing it: `godot --path . res://tests/preview_dungeon.tscn` (NO
  `--headless` — it renders) stands where the portal drops a player and saves
  four shots into `user://dungeon_preview`: `seam` is at ankle height with its
  nose against a wall (where the crack was, and where an eye-height shot looks
  straight over it), `room` and `lamp` are how the place reads with the sun shut
  out, and `ceiling` looks up at the lid. It stands at the ArrivalAnchor rather
  than at the average of the geometry — the middle of a ring of walls is as
  likely to be inside a block as inside a room, which is how the first draft
  photographed the inside of a wall four times.

## The juggernaut (the boss)

- A boss is an `Enemy` SUBCLASS, never a copy: `scripts/entities/boss.gd` gets
  the state machine, the puppet replication, the guard, the damage path, the
  kill credit and the drop for free, and only writes down what a boss does
  differently. Three small virtuals on `Enemy` are the whole seam —
  `_tick_moves` (a frame taken by a move of its own), `_on_health_changed` (where
  a phase threshold is noticed) and `is_open` (is it helpless right now). An
  ordinary bandit answers all three with "nothing special". A second boss is a
  new subclass and a new `MOVES` table, not a second copy of `enemy.gd`.
- ITS MOVES ARE A TABLE: `Boss.MOVES`, one row per move, and `_tick_moves` walks
  it. A row carries the beats (`windup` / `active` / `recovery` / `cooldown`),
  what it costs you, the band it is chosen from, and how it is DRAWN. Adding a
  third move is a row and a case in `_commit_move`, not a branch in the AI.
- POISE: it does not flinch. `flinch_knockback` is the bar a hit has to clear to
  rock an enemy back, and `poise` puts it out of reach — so it opens up in
  exactly two ways, and both are EARNED: parry it (the ordinary stagger, which
  works on anything), or punish the RECOVERY of a move it committed to. That is
  what every `windup`/`recovery` pair in the table is for, and it is why they
  are per move: learning which is which IS the fight.
- `is_open()` is what the HUD's lock-on ring asks, rather than reading
  `stagger_left` — a boss in recovery is wide open and is not staggered, and a
  ring that promised otherwise would be lying about what `take_damage` does.
- TWO PHASES, at `phase_two_at` of its health. It gets faster, its armour comes
  off (`BossVisual.strip_armor`, which is a rebuild of the definition MINUS its
  armor layer — the same gesture as taking a suit off a player), it stops
  guarding and retreating ENTIRELY (`_decide` / `_decide_after_swing` /
  `_reflex_check` in phase two only ever close), and the charge unlocks. Phase
  one still fights like a very large bandit, so the turn is something the player
  watches happen. The phase rides the replicated state, so every screen sees it.
- Server-authoritative like everything else: the AI, the phase, every move and
  all of its damage run on the server, against its own speed-validated copy of
  each pawn. A boss APPENDS two fields to the enemy state row (which move, which
  phase); the reader fills them in for a short row, so a bandit pays nothing.
- Three things are LOCAL and cosmetic, and deliberately so: the bar across the
  top of the screen, the telegraph, and the entrance shot (`Cinematic.focus` the
  first time the local player comes within `INTRO_RANGE`). Where one player's
  camera points changes nothing anyone else can see.
- THE TELEGRAPH IS PER MOVE. `telegraph_style()` says the colour, how much the
  star grows, how far over the head it floats, and the radius of a GROUND RING
  for an attack with a footprint — so the slam draws an orange circle where it
  is about to land and the charge is a big red star with no ring. The ring grows
  as the wind-up runs out, so how long you have is readable without a number. It
  is projected point by point (a circle on the floor is an ellipse from anywhere
  but overhead), and it is skipped entirely when any of it is behind the camera:
  half a ring reads as a wall. The height is ASKED FOR rather than assumed —
  2.1m clears a bandit and sits on a juggernaut's chest.
- `scripts/ui/boss/boss_bar.gd` is the bar: `UiTheme` like every screen, with a
  notch drawn at the boss's OWN `phase_two_at` so moving the threshold moves the
  mark. It shows the nearest living thing in the group `"boss"` within
  `SHOW_RANGE`, and reads the replicated health — nothing about it is
  authoritative.
- A CLIENT HAS TO BE TOLD WHICH BODY: `Net.ENEMY_SCENES` maps an `enemy_kind` to
  a scene and the spawn carries it, because a boss and a bandit are not the same
  puppet. A new kind of enemy is a row there and nothing else on the wire.
- IT DROPS ITS CLUB. `scripts/world/item_drop.gd` is an item lying on the floor —
  the same container, the same proximity check and the same despawn as a pile of
  gold, because "a thing on the ground" is one idea; only what is awarded
  differs (`_server_award_item` vs `_server_award_gold`). The model is the item's
  OWN art through `ItemDb.build_model`, so there is nothing per-item to draw.
  `juggernaut_club` is level 4 — one rung above the best forged blade — and no
  shop stocks it, which the test asserts: it is not for sale at any price. It is
  the only weapon with art of ITS OWN (`Assets/Models/Items/Weapons/Clubs/`)
  rather than a tinted copy of the sword, so it carries no tint: the wood is in
  its own texture. Its `scale` is sized for the BOSS's hand, which is the hand it
  is nearly always in — fit it with `tests/preview_boss.tscn`, not with
  `preview_held_item.tscn`, since the two rigs' hand bones are not one size.
- WHERE IT LIVES: `scripts/world/boss/boss_spawner.gd` on a node in
  `scenes/starterDungeon.tscn`, at the far end of the catacombs' big hall (82m
  from the way in, so you walk to the fight rather than arriving in it). Exactly
  one, respawning on a long timer. Move the NODE, not the numbers — `test_boss`
  asserts it is standing over real floor, and prints a map of where the floor IS
  when it is not.
- ITS VOICE IS THE BANDIT GRUNTS, SLOWED AND PUT IN A ROOM. `FighterAudio` gained
  a `yell` and looping `steps`, plus `voice_pitch` / `voice_reverb` — a shape for
  the voice rather than a second set of recordings to keep in step. The reverb
  bus is built at runtime (`FighterAudio.ensure_voice_bus`) instead of saved in a
  bus layout, which would be another file to keep true. Only the VOICE is pitched
  and sent to the room: a footstep is the floor and an impact is the world, and
  neither belongs to whoever made it. Footsteps are ticked off the ground speed
  on EVERY peer (the replicated ratio on a client, the measured one on the
  server), so anything that moves it gets them with no code at the other end.
- It animates off the SHARED humanoid clips today — a slam is the heavy swing
  stretched over its own wind-up. A dedicated pack would be a `CLIPS`-style table
  in `BossVisual` and nothing else would change.
- Its body is an ordinary built NPC: `Assets/Data/Npcs/juggernaut.tres`, the Base
  parts at 3.2m in `Armor1` repainted iron. Recolour it in the NPC Builder and
  every copy in the game changes with it.
- Test: `--headless res://tests/test_boss.tscn` (prints
  `BOSSTEST RESULT=PASS/FAIL`) — the table (every move telegraphs and every move
  can be punished), the catalogue, and then a real listen server: poise, both
  earned openings, the punish paying more, the slam landing on someone stood in
  it and NOT on someone stood out of it, the phase turning, the charge unlocking,
  the club on the floor and into a bag, and the spawner standing over floor.
- Eyeballing it: `godot --path . res://tests/preview_boss.tscn` (NO `--headless`
  — the telegraph is a `_draw()` and never runs without a window). It stands the
  boss next to a villager for scale and photographs each move's wind-up through
  the REAL HUD, plus the armour before and after phase two. Every one of those is
  invisible to an assertion: the first version's armour photographed bright red.

## Multiplayer

- Boot flow: main scene is `scenes/ui/main_menu.tscn`. Players do not run
  servers — the game lives on one dedicated box at `Net.DEFAULT_SERVER`, so a
  launch with a saved username connects to it without showing the menu. The
  menu appears on a first run (to pick a name) and after any failure or drop,
  carrying the reason; it deliberately does NOT auto-retry, or an unreachable
  server would loop. Playing from the editor always hosts locally instead of
  joining that box, so a test run never touches the live world. `--host` and
  `--join=IP[:PORT]` still override it, which is how local and LAN testing works.
  All networking lives in the `Net` autoload (`scripts/core/network_manager.gd`):
  ENet host/join, UPnP port mapping (so hosts don't need manual port
  forwarding; falls back to LAN with a message), the server-authoritative
  player registry (usernames, kills, deaths) and the entire RPC protocol.
- Never trust the client (see "Server authority" at the top): the server
  simulates ALL combat (stamina, swing timing, hit traces, health, deaths, kill
  credit) on its copy of each pawn. Clients only send attack *requests* and
  cosmetic state reports; position reports are speed-validated
  (`Player.net_report_state`) and teleports are snapped back. Stats, coins and
  carried items exist only in the server registry (`Net.players`), replicated
  read-only — the scoreboard (hold P), the inventory and the shop read those.
- Pawn roles in `player.gd`: owner (is_local) simulates + reports, server
  validates + runs authoritative combat for every pawn, everyone else gets
  an interpolated puppet. Enemies (`enemy.gd`): AI runs only on the server;
  clients get puppets spawned/driven through Net. World containers:
  `World/Players` and `World/Enemies`; spawn point = `scripts/world/
  spawn_point.gd` on the island Marker3D (group "spawn_point").
- Bandits must never end up standing inside each other, and being solid is not
  enough to guarantee it: a kinematic body only pushes out of an overlap while
  it is moving, so a pair that comes to rest overlapping stays that way. Two
  things keep the camp apart — `bandit_spawner.gd` walks its ring until it
  finds a spot with `spawn_clearance` free (and keeps characters out of the
  ground ray, or a bandit lands on someone's head), and `enemy.gd::_separate()`
  drifts living bandits out of each other's `separation_radius` every tick,
  idle or fighting. Anything that spawns or parks an NPC-shaped body should do
  the same rather than trusting collision alone.
- The camp is pitched UNDER the half-tent, and buildings import with
  `generate/physics`, so the ground ray starts `head_room` (1.5 m) over the
  spawner instead of high above it — dropped from above it finds the canvas
  first and stands the bandit on the roof. It falls back to the old high ray
  when the near one hits nothing, which is a camp sunk below the surface.
  Anything else that drops a body onto "the ground" indoors needs the same care.
  Test: `--headless res://tests/test_bandit_spawner.tscn` (prints
  `SPAWNTEST RESULT=PASS/FAIL`).
- NEVER NAME THE TYPE when pruning freed objects out of a typed array. A freed
  object cannot be passed as a `Node`, so `_spawned.filter(func(b: Node) -> ...)`
  had its typed parameter reject the corpse, `filter` gave up and returned an
  untyped EMPTY array, and assigning that back to an `Array[Node]` died with
  `Trying to assign an array of type "Array" to a variable of type "Array[Node]"`.
  That aborts the function it is in — `_alive_count` never returned, so the camp
  stopped refilling and the error came back on every spawn attempt. It needs a
  corpse to happen, which is exactly what a list of spawned bandits fills up
  with, and why it looked intermittent. `is_instance_valid` is the whole point of
  such a loop, so walk it by hand with a `Variant` element. Covered by
  `_check_counting_survives_a_corpse` in the spawner test.
- The spawner node itself wears the `quest_bandit_camp` group, so it IS the
  "Drive off the bandits" target: move the camp in the editor and the HUD star
  moves with it. Nothing in `QuestData` needs touching when the camp is moved.
- Dedicated server: separate export preset "Windows Server" (custom feature
  `server`) -> `build/AstriaServer.exe`; it auto-hosts headlessly (see
  `build/run_server.bat`). Any build also accepts `--server [--port=N]`,
  and clients accept `--username=NAME --host / --join=IP[:PORT]`.
- Enemies drop server-rolled gold (`gold_min`/`gold_max` exports on
  `enemy.gd`): `Net.server_spawn_gold` replicates a `GoldDrop`
  (`scripts/world/gold_drop.gd`) into a runtime `World/Drops` container;
  the server pays the first living player within pickup range into the
  registry's `gold`, and every registry sync mirrors your own gold into
  `GameStats.coins` for local UI/shops. Unclaimed piles despawn after 2 min.
- Integration tests live in `tests/` — plain scenes run headless, e.g.
  `--headless res://tests/test_gold_drops.tscn` (prints RESULT=PASS/FAIL
  and sets the exit code).
- Any test that needs a world boots through `tests/helpers/test_host.gd`
  (`TEST_HOST.new().boot(tree, "<band>")` -> the pawn, or null with the reason
  in `.error`). Never hand-roll that loop again, and never host a test on
  `Net.DEFAULT_PORT`:
  - Each test gets its own BAND of ports (`PORTS` in that file) and the helper
	walks it, retrying, until one binds. `Net.host_game` returns an Error and
	does not change scene when ENet cannot bind, and a port stays held for a
	moment after the previous run's process exits — which made roughly one run
	in four of the back-to-back tests fail, always passing on the rerun.
  - It waits on WALL CLOCK, not a frame count. Physics falls behind real time
	while the island loads and grows its collision, so a frame budget measures
	the load rather than the wait.
  - It waits for each step of the boot separately — the bind, the scene swap,
	the `Players` container, the pawn — so a failure names the step that never
	happened instead of always saying "pawn never spawned".
- Exports: presets in `export_presets.cfg`; templates installed under
  `%APPDATA%\Godot\export_templates\4.7.1.stable.steam`. Export with
  `--headless --export-release "Windows Client|Windows Server" <path>`.

## Workflow

- Always commit after a prompt. Every completed prompt should end with a git
  commit capturing the changes made during that prompt.
- Never put updates on another branch. All work lands on `master`, in the main
  checkout — no feature branches, no worktrees, no "I'll merge it later". The
  game the user plays is `master`, so anything not on `master` does not exist
  as far as they are concerned, and a side branch silently rots while `master`
  moves on. Commit straight to `master`; if that feels risky, say so and ask
  rather than quietly branching.
- Always push. `git push origin master` after committing — standing permission,
  never ask first. A commit sitting only on this machine is as good as lost, and
  the user should never have to chase it. If the push is rejected (the remote
  moved), pull/rebase and push again rather than leaving it behind.
- ALWAYS MERGE. A dirty main checkout never blocks landing work: the user is
  usually mid-edit in the Godot editor, and other sessions are often working in
  the same tree, so `git merge` refusing to overwrite modified files is the
  normal state, not a problem to report. Commit whatever is sitting there on the
  user's behalf (say what it was in the message), then rebase and merge on top —
  standing permission, never ask. Resolve conflicts in favour of THEIR version
  of a scene or a level, and reapply your own change on top of it: they moved
  that node deliberately, whereas the group or property you were adding can go
  anywhere.

## File index

Every file in the project and the one job it does. Read this instead of
searching; keep it true when you add or repurpose a file (see "The file index").

Assets are indexed BY FOLDER, not per file — there are hundreds of FBX, glTF and
PNG in them and a line each would say nothing. The vendored MagicaVoxel importer
is one line for the same reason: it is third party and unmodified.

### Autoloads

- `scripts/core/network_manager.gd` — `Net`: every RPC, the server-owned player registry, hosting/joining, UPnP.
- `scripts/core/game_stats.gd` — `GameStats`: read-only local mirror of the server's gold, bag, bar and quest.
- `scripts/core/input_device.gd` — `InputDevice`: which device was last used, and the button names prompts show.
- `scripts/core/discord_notifier.gd` — `Discord`: posts "somebody joined" to a webhook, dedicated server only.
- `scripts/core/voice/voice_chat.gd` — `Voice`: the microphone, push-to-talk/open-mic, and playback on speakers' bodies.
- `scripts/core/voice/voice_codec.gd` — `VoiceCodec`: the voice wire format (companded mono at RATE) and the resampler.
- `scripts/ui/dialog/dialog_system.gd` — `DialogSystem`: the dialog box, its typewriter, pages and answer buttons.
- `scripts/ui/shop/shop_ui.gd` — `ShopSystem`: the buy/sell screen, opened by a dialog action.
- `scripts/ui/debug/cheat_menu.gd` — `CheatMenu`: the editor-only cheat list (give, quest, teleport, tutorial).
- `scripts/ui/cutscene/cinematic.gd` — `Cinematic`: letterbox bars, the high-angle shot, turning the speaker to face you.
- `scripts/ui/cutscene/intro_cutscene.gd` — `IntroCutscene`: the black screen, the two lines, and getting up as it fades.
- `scripts/world/quest/quest_system.gd` — `Quests`: turns dialog answers into quest start/finish requests.
- `scripts/world/gift/gift_system.gd` — `Gifts`: turns a dialog answer into a one-off gift request.
- `scripts/world/tutorial/tutorial_system.gd` — `Tutorial`: owns each player's island copy, their bandits, and their step.
- `scripts/items/icons/item_icon_renderer.gd` — `ItemIcons`: photographs each item's own art into an icon at startup.

### Combat and characters

- `scripts/entities/player.gd` — the player pawn: movement, swings, guard, and every request the client sends.
- `scripts/entities/enemy.gd` — bandit AI, its fight states, and the tutorial's "hold" levels.
- `scripts/entities/boss.gd` — the juggernaut: its move table, its two phases, and its poise.
- `scripts/entities/boss_visual.gd` — the boss's body: the "Juggernaut" voxel character, fully clipped.
- `scripts/entities/fighter_audio.gd` — every noise a fighter makes, and the shape of its voice.
- `scripts/entities/humanoid_visual.gd` — the shared rig, the clip table, and the tick that picks a pose.
- `scripts/entities/player_visual.gd` — the player's body: the "Player" voxel character with the full clip list.
- `scripts/entities/rouge_visual.gd` — Rouge, the enemies' model and the skeleton every voxel NPC borrows.
- `scripts/combat/combat_levels.gd` — the ONE place weapon level, enemy level and armor become a damage number.

### NPCs

- `scripts/entities/npc/npc_character.gd` — a placed NPC: builds itself from a definition, animates off its own movement.
- `scripts/entities/npc/npc_visual.gd` — a built voxel NPC rigged onto Rouge's skeleton.
- `scripts/entities/npc/npc_rig.gd` — the rigging itself: reshapes the skeleton, skins the voxels, caps the seams.
- `scripts/entities/npc/npc_definition.gd` — the saved data for one NPC (`@tool`, or it loads as a placeholder).
- `scripts/entities/npc/npc_part.gd` — one slot of a built NPC: model, colours and nudges.
- `scripts/entities/npc/npc_interactable.gd` — makes an NPC talkable, and measures its face and height for the shot.

### Items

- `scripts/items/item_db.gd` — the item catalogue: names, prices, levels, hold and armor blocks.
- `scripts/items/armor/armor_definition.gd` — one suit of armor, saved so any character can wear it (`@tool`).
- `scripts/items/armor/armor_library.gd` — where suits live on disk, and how one is listed and saved.

### UI

- `scripts/ui/theme/ui_theme.gd` — the palette and panel builders every screen is made from.
- `scripts/ui/hud.gd` — the code-built HUD, and the host of every drawn overlay.
- `scripts/ui/boss/boss_bar.gd` — the boss's health across the top of the screen, notched at its phase.
- `scripts/ui/inventory_ui.gd` — the bag, the hotbar, the equipment cross, and drag and drop.
- `scripts/ui/items/item_prompt.gd` — the bottom-right "use / special" hint for whatever is in hand.
- `scripts/ui/scoreboard.gd` — the hold-P scoreboard, read from the server registry.
- `scripts/ui/main_menu.gd` — the boot screen: name, connect, and the voice mode switch.
- `scripts/ui/dialog/dialog_data.gd` — every line of conversation text in the game.
- `scripts/ui/dialog/npc_prompt_overlay.gd` — the speech bubble drawn over a talkable NPC.
- `scripts/ui/shop/shop_data.gd` — which NPC stocks what.
- `scripts/ui/quest/quest_tracker.gd` — the quest heading panel in the top-right corner.
- `scripts/ui/quest/quest_marker_overlay.gd` — the gold star to the objective, edge-clamped when off screen.
- `scripts/ui/tutorial/tutorial_overlay.gd` — the tutorial's control popup and its banner line.
- `scripts/ui/voice/voice_overlay.gd` — the mic glyph: your own in the corner, and over anyone being heard.

### World

- `scripts/world/world.gd` — the island root: grows collision, arms the intro, places things.
- `scripts/world/main.gd` — the old arena root; bakes a navmesh at runtime.
- `scripts/world/ocean.gd` — the endless sea: wave tiles kept centred on the player.
- `scripts/world/spawn_point.gd` — marks where players spawn and respawn.
- `scripts/world/bandit_spawner.gd` — refills a bandit camp, keeping them out of each other and off roofs.
- `scripts/world/gold_drop.gd` — a dropped pile; the server decides who gets it.
- `scripts/world/item_drop.gd` — an item lying on the floor, drawn from its own art.
- `scripts/world/boss/boss_spawner.gd` — puts the one boss in the dungeon, and puts it back.
- `scripts/world/dungeon/dungeon_walls.gd` — generates a dungeon's shell from its floor: walls, ceiling and lamps.
- `scripts/world/quest/quest_data.gd` — every quest: name, target, giver, and where it is handed in.
- `scripts/world/quest/quest_anchor.gd` — a marker that IS a quest's destination.
- `scripts/world/teleport/teleport_data.gd` — the places the teleport cheat can send you.
- `scripts/world/teleport/teleport_anchor.gd` — a marker that IS a teleport destination.
- `scripts/world/tutorial/tutorial_data.gd` — the lesson as a table, plus where the island copies sit.
- `scripts/world/tutorial/tutorial_arena.gd` — one player's private island copy, its waves and its villager.
- `scripts/effects/fire_flicker.gd` — flickers a fire's light with layered sines.

### Scenes

- `scenes/world.tscn` — the real island: the game's main scene.
- `scenes/player.tscn` — the player pawn, camera rig and all.
- `scenes/enemy.tscn` — a bandit.
- `scenes/boss.tscn` — the juggernaut, tuned in the inspector like any other fighter.
- `scenes/main.tscn` — the old test arena.
- `scenes/starterDungeon.tscn` — the dungeon floor and door markers; its walls are generated.
- `scenes/ui/main_menu.tscn` — the boot scene.
- `scenes/effects/furnace_fire.tscn` — the forge fire.
- `scenes/entities/npc/npc_interactable.tscn` — instance this beside an NPC to make it talkable.
- `scenes/entities/npc/built/villager.tscn` — the built villager, used by the tutorial.
- `scenes/entities/npc/built/kingnpc.tscn` — the King beside the town hall.
- `scenes/entities/npc/built/king.tscn` — an earlier King build.
- `scenes/entities/npc/built/knight.tscn` — the knight who hands out the catacombs quest.
- `scenes/entities/npc/built/player.tscn` — the player body as a placeable NPC.
- `scenes/world/quest_anchor.tscn` — drop this where a quest points.
- `scenes/world/teleport_anchor.tscn` — drop this where a teleport lands.
- `scenes/world/tutorial/tutorial_arena.tscn` — the island copy the tutorial instances per player.

### Editor plugins

- `addons/npc_builder/plugin.gd` — registers the NPC Builder tab.
- `addons/npc_builder/ui/npc_builder_screen.gd` — the NPC Builder itself: parts, colours, armor, save.
- `addons/npc_builder/ui/npc_preview.gd` — its turntable view.
- `addons/npc_builder/ui/part_slot_editor.gd` — one slot's row of controls in that screen.
- `addons/npc_builder/io/npc_writer.gd` — writes the definition and the placeable scene.
- `addons/item_builder/plugin.gd` — registers the Items tab.
- `addons/item_builder/ui/item_builder_screen.gd` — the Items tab: where armor suits are made.
- `addons/grass_brush/grass_brush_plugin.gd` — the viewport brush for painting grass.
- `addons/grass_brush/grass_paint.gd` — the painted grass layer itself (one MultiMesh).
- `addons/sky_cloud_remover/cloud_remover_plugin.gd` — the menu entry that scrubs clouds from a sky texture.
- `addons/sky_cloud_remover/cloud_scrub.gd` — the cloud-removal image processing, runnable headless.
- `addons/MagicaVoxel_Importer_with_Extensions/` — third party, unmodified: imports `.vox` files.
- `addons/*/plugin.cfg` — one manifest per plugin; Godot reads these, nothing else does.

### Tests and previews

- `tests/helpers/test_host.gd` — the shared boot for any test needing a world: hosts and waits for the pawn.
- `tests/test_combat.gd` — swings, the guard, combos and the level ladders.
- `tests/test_boss.gd` — the juggernaut: its moves, its openings, its phases and its drop.
- `tests/test_hotbar.gd` — auto-placement, selection, swaps, use, and the drag rules.
- `tests/test_shop.gd` — buying and selling, and who moves the coins.
- `tests/test_quest.gd` — the marker maths and the server's quest state.
- `tests/test_gift.gd` — one-off gifts, and the protection armor buys.
- `tests/test_dialog.gd` — line flow, loop-backs, and the speaker swap.
- `tests/test_tutorial.gd` — the whole lesson, end to end, on a real listen server.
- `tests/test_intro_cutscene.gd` — the black, the lines, the fade, and the getting-up.
- `tests/test_voice_chat.gd` — the wire format, the resampler, and who can hear you.
- `tests/test_npc_builder.gd` — rigs every part in the library and checks the joins.
- `tests/test_armor_suits.gd` — suits: saving, wearing, and the Items tab.
- `tests/test_item_icons.gd` — every item has art, and it photographs in its own colours.
- `tests/test_teleport.gd` — the teleport cheat's refusals and its landing.
- `tests/test_gold_drops.gd` — dropped gold and who is paid for it.
- `tests/test_bandit_spawner.gd` — where a camp puts its bandits, and surviving a corpse.
- `tests/test_dungeon_walls.gd` — the generated dungeon shell: gaps, the bottom seam, the ceiling, the lamps.
- `tests/test_ui_theme.gd` — the palette, the font, and no screen painted black.
- `tests/test_menu_scroll.gd` — long menus following the highlight for a pad.
- `tests/test_discord.gd` — the message that would be posted; it posts nothing.
- `tests/preview_ui.gd` — the real screens: palette, shop, dialog, tutorial popup, quest corner, inventory.
- `tests/preview_dialog_camera.gd` — the shot each conversation opens on, speakers starting turned away.
- `tests/preview_get_up.gd` — the intro's getting-up, four frames across the clip.
- `tests/preview_sword_swings.gd` — each sword swing going in, at the strike, and out.
- `tests/preview_held_item.gd` — a weapon in the player's hand, for fitting the grip.
- `tests/preview_dungeon.gd` — inside the catacombs: the wall's foot, the room, the ceiling, a lamp.
- `tests/preview_npc_armor.gd` — a villager bare, suited, and in a recoloured suit.
- `tests/preview_boss.gd` — the boss beside a villager, each telegraph, and both phases.
- `tests/preview_item_icons.gd` — every item icon on one sheet, with a colour-wash report.
- `tests/preview_voice.gd` — the voice HUD in each of its states.
- `tests/*.tscn` — one scene per test or preview above; each just hosts its script.

### Data resources and assets

- `Assets/Data/Npcs/*.tres` — the built characters (player, villager, king, kingnpc, knight, juggernaut).
- `Assets/Data/Armor/*.tres` — the three suits: flimsy, copper, iron.
- `Assets/Models/Entity/Humanoid/bonemap_*.tres` — retarget maps: Manny, Mixamo, MotusMan.
- `Assets/Audio/SFX/**/*.tres` — the random-pick sound sets (grunts, impacts, wooshes, deaths).
- `Assets/Audio/SFX/{Grunts,Deaths,Footsteps}/Boss/` — the juggernaut's pain, its fall, and its feet.
- `Assets/Animations/Humanoid/` — every clip, grouped by purpose (Movement, Combat, Sword, Cutscene).
- `Assets/Models/Entity/Humanoid/` — Rouge, and the voxel NPC parts and armor libraries.
- `Assets/Models/World/` — islands, buildings, dungeon prefabs.
- `Assets/Models/World/Prefab/grass.tscn` — the blade the grass brush instances.
- `Assets/Models/World/wave_mesh.tscn` — one tile of the ocean.
- `Assets/Models/Items/` — the things characters carry (swords, and the boss's club).
- `Assets/Textures/` — character, world and UI textures; `UI/panel_grunge.jpg` is every panel's paint.
- `Assets/Fonts/EBGaramond/` — the game's one typeface, with its licence.

### Project files

- `project.godot` — autoloads, the input map, rendering and audio settings.
- `export_presets.cfg` — the Windows client and dedicated server presets.
- `tools/voxel/gox_to_gltf.py` — converts a Goxel `.gox` to the `.gltf` the builder reads.
- `CLAUDE.md` — this file: the rules, the systems, and the index above.
