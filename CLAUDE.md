# Astria — Godot 4.7 third-person action game

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
  - `Textures/` — mirrors the model grouping (e.g. `Humanoid/Human/Rouge/`)
  - `Data/Npcs/` — `NpcDefinition` resources written by the NPC Builder
- `scenes/` — .tscn scene files; reusable building blocks go in subfolders
  (`scenes/entities/npc/`, `scenes/effects/`, `scenes/ui/`); built NPCs land
  in `scenes/entities/npc/built/`
- `scripts/` — GDScript, grouped by domain: `entities/` (player, enemy,
  character visuals, `npc/` interaction + rigging), `ui/` (HUD, `dialog/`),
  `world/` (level/world logic), `core/` (autoloads)
- `addons/` — editor plugins (`npc_builder/`, `grass_brush/`, ...)
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
- Bindings today: `attack` = LMB / RT, `block` = RMB / LT, `jump` = Space /
  A (cross), `slide` = Space or Ctrl / A (cross) — the SAME button as jump,
  `lock_on` = MMB / R3, `interact` = E / Y (triangle), `inventory` = Tab /
  D-pad up, `sprint` = Shift, with no pad button by request,
  `hotbar_next` / `hotbar_prev` = ] and [ / R1 and L1, `use_item` = F / R2 —
  the SAME trigger as attack, so a swing is also a use (which is why the
  server's use replies carry no message yet), `cheat_menu` = Z / Options
  (Menu).
- Picking an entry in any menu (dialog answers, shop rows, cheat rows, bag and
  hotbar slots) is `ui_accept`: on a pad strictly the bottom face button — PS5
  Cross, Xbox A, the same physical place — and E or Enter on a keyboard. The
  interact button is NOT a menu confirm on a pad: Y / triangle is "press at a
  thing" in the world and the two blurred together. Ask with
  `InputDevice.is_menu_accept(event)` rather than testing the actions by hand;
  it is what keeps that split in one place. Panels still swallow an interact
  press they ignore, or it reaches the NPC standing behind them.

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
  (light 1.35x, heavy 1.15x) via `rouge_visual.get_attack_info()`; a punch
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
- Anchored HUD pieces set `offset_*`, never `position`: `position` is
  parent-relative, so on a right-anchored control it lands off the left edge.
- `set_anchors_preset()` KEEPS THE CONTROL'S CURRENT RECT, baking offsets to
  match it — and a code-built Control has never been sized, so the preset
  leaves it 0x0 with the anchors merely looking right. The drawing overlays get
  away with it (a `_draw()` is not clipped to the rect, which is why the
  wind-up star and NPC bubbles were fine), but anything that LAYS OUT CHILDREN
  must set its anchors and all four offsets by hand. The tutorial popup was
  centring itself inside nothing and hanging half off the left edge.

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
- THE TUTORIAL DOES NOT TALK. It teaches with POPUPS: a control name, the
  button for whatever device is in hand, and one line saying what the thing
  does — `popup: {title, body}` on the gate step, drawn by
  `scripts/ui/tutorial/tutorial_overlay.gd`. Nothing to dismiss, and it never
  takes the controls off the player the way a dialog box would. There is no
  story in it, no `tut_*` dialog and no spoken word anywhere in it.
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
- There is no hand-off at the end and no quest: the last bandit going down IS
  the end, and you are put on the real island. The villager who used to walk
  over was removed with it.
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
- All conversation text lives in `scripts/ui/dialog/dialog_data.gd` — the file
  header documents the format (speaker / start / lines, each line with `text`
  plus either `answers` or a plain `goto`; `goto: END` closes the box). An
  answer may carry `"action"`, which the `DialogSystem.action_triggered` signal
  reports so gameplay code (shops, quests) can hook in.
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
  `"action": "start_quest:<id>"`, and `QuestSystem` (autoload `Quests`) turns it
  into the request — exactly how `"open_shop"` and `ShopSystem` work. No NPC
  needs code of its own.
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
  them, the heading follows the mirror, and it can be dropped again.

## Items and shops

- Item catalogue: `scripts/items/item_db.gd` — id -> name / buy price / desc /
  icon. Selling pays `ItemDb.SELL_RATIO` (half, rounded down) unless an item
  carries its own `"sell"`. Never hardcode a price anywhere else; two shops
  must not disagree about what a sword is worth.
- An item's `"icon"` is what the bag grid and the shop rows draw; art lives in
  `Assets/Textures/Items/`, grouped like the models. Items with no usable icon
  fall back to drawing their name, so a bad path never crashes a screen. The
  shipped sword icons are 64x64 placeholders — overwrite the files to replace.
- Who stocks what: `scripts/ui/shop/shop_data.gd`, keyed by the NPC's
  `dialog_id`. Optional `"buys"` list restricts what that shop will take back;
  omit it and the shop buys anything.
- Giving an NPC a shop is two steps: add a `ShopData.SHOPS` entry under its
  `dialog_id`, and give one dialog answer `"action": "open_shop"`. `ShopSystem`
  listens to `DialogSystem.action_triggered` and opens itself — no per-NPC code.
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
- Requests: `request_hotbar_select(slot)` (R1/L1 in the world, a click in the
  panel), `request_hotbar_assign(slot, id)` ("" clears; assigning something
  already on the bar swaps rather than duplicating) and `request_use_item()`.
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
- Those clips are the Mocap Online TC Sword pack on the MotusMan rig, whose
  bones are Mixamo's names minus the `mixamorig_` prefix — hence
  `bonemap_motusman.tres`, the Mixamo map with the prefix stripped, wired into
  each clip's `.import` exactly like the Mixamo ones.
- The pack ships ONE 5.5s combo take, and most of it is danced in a deep mocap
  crouch: the hips stand at 1.00, sink to ~0.75 through the middle cuts and to
  0.67 in the lunge near 4.1s, which on this character reads as squatting. So
  only the FIRST cut is used, trimmed to the strike itself —
  `"slice": [0.66, 0.90]`, the arm already moving at 0.66, peaking at 0.80 and
  spent by 0.90, with the blend out of idle standing in for the raise. EVERY swing plays
  that one slash (`sword_slash`); the heavy differs only in the longer window
  it is stretched over. If more sword moves are ever wanted they need a take
  that stays on its feet, not another slice of this one.
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

## Development cheats

- Z (or the PS5 Options / Xbox Menu button) opens the cheat menu —
  `scripts/ui/debug/cheat_menu.gd`, autoload `CheatMenu`. It offers "Give item"
  (everything in `ItemDb.ITEMS`; picking one asks the server for a copy),
  "Quest" (everything in `QuestData.QUESTS`, plus "Clear quest"),
  "Teleport" (everything in `TeleportData.DESTINATIONS`) and "Start tutorial".
  Adding a cheat is one row in `_build_root`.
- "Start tutorial" goes through the server like everything else, and is a real
  restart: a fresh copy of the island with its own bandits.
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
  metadata to register. A set needs all four slots: `test_npc_builder` builds
  one NPC per set out of that set alone and fails if a slot is empty.
- Keep the `.gox` next to the `.gltf` it was exported from (as
  `king_head.gox` / `king_head.gltf`), so the source of a part is never a
  question of which Downloads folder it came from.
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
- `NpcVisual._adapt_hips` rebases the clips' Hips position track per NPC — it
  was authored around a human pelvis and would otherwise yank a short-legged
  voxel NPC up to Rouge's hip height.
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
  plus that Rouge still builds his own rig and full clip set.

## Dungeons

- `scenes/starterDungeon.tscn` is a floor slab plus Area3D markers; the stone
  shell around it is GENERATED at load by `scripts/world/dungeon/
  dungeon_walls.gd` on the `Walls` node. Nothing is hand-placed, so do not add
  wall transforms to the .tscn — change `RUNS` or move a marker instead.
- The ring comes from the floor mesh's own bounds and each doorway comes from
  the `*Enterence` marker it belongs to, so moving a marker moves its doors and
  resizing the slab moves the ring. A run's `from`/`to` is either a fraction of
  the floor or another marker's NAME, which is how two walls meet exactly.
- `prefab_scale` (0.2) converts the raw voxel prefabs to player scale: wall
  3.8m tall, doorway 2.8m x 2.6m against a 1.92m capsule. Tune it there, not by
  scaling nodes in the scene.
- Solid stretches are tiled to FIT (count rounded, length stretched), never at
  a fixed size with the last block hanging over — the overhang both widens
  doorways past the doors filling them and pushes blocks through each other at
  junctions, giving coplanar faces that z-fight exactly like overlapping NPC
  parts. Door leaves are mirrored with a 180-degree turn, not a negative scale,
  which would flip the winding and light them inside out.
- Test: `--headless res://tests/test_dungeon_walls.tscn` (prints
  `DUNGEONTEST RESULT=PASS/FAIL`). It checks every threshold has its pair, that
  no doorway is bricked up, that nothing floats off the slab, that no two
  blocks share space, that every piece has collision, and that a player fits.

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
