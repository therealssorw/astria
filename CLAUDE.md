# Astria — Godot 4.7 third-person action game

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
    for level geometry; skeleton bone maps live in `Models/Entity/Humanoid/`
  - `Textures/` — mirrors the model grouping (e.g. `Humanoid/Human/Rouge/`)
- `scenes/` — .tscn scene files; reusable building blocks go in subfolders
  (`scenes/entities/npc/`, `scenes/effects/`, `scenes/ui/`)
- `scripts/` — GDScript, grouped by domain: `entities/` (player, enemy,
  character visuals, `npc/` interaction), `ui/` (HUD, `dialog/`),
  `world/` (level/world logic), `core/` (autoloads)

When adding new assets or code, place them in the most specific folder that
makes sense; create new subfolders rather than letting a folder grow into a
mixed pile.

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

## NPC dialog

- To make an NPC talkable: instance `scenes/entities/npc/npc_interactable.tscn`
  next to it in the world and set `dialog_id`. Tunables: `interact_range`,
  `prompt_offset` (where the bubble's tail points).
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
- Keys: `interact` = E / pad Y (triangle); `inventory` = Tab. Lock-on lost
  its Tab binding for that — it is middle mouse / R3 only now.

## Multiplayer

- Boot flow: main scene is `scenes/ui/main_menu.tscn` (username + host/join).
  All networking lives in the `Net` autoload (`scripts/core/network_manager.gd`):
  ENet host/join, UPnP port mapping (so hosts don't need manual port
  forwarding; falls back to LAN with a message), the server-authoritative
  player registry (usernames, kills, deaths) and the entire RPC protocol.
- Never trust the client: the server simulates ALL combat (stamina, swing
  timing, hit traces, health, deaths, kill credit) on its copy of each pawn.
  Clients only send attack *requests* and cosmetic state reports; position
  reports are speed-validated (`Player.net_report_state`) and teleports are
  snapped back. Stats exist only in the server registry (`Net.players`),
  replicated read-only — the scoreboard (hold P) and inventory read those.
- Pawn roles in `player.gd`: owner (is_local) simulates + reports, server
  validates + runs authoritative combat for every pawn, everyone else gets
  an interpolated puppet. Enemies (`enemy.gd`): AI runs only on the server;
  clients get puppets spawned/driven through Net. World containers:
  `World/Players` and `World/Enemies`; spawn point = `scripts/world/
  spawn_point.gd` on the island Marker3D (group "spawn_point").
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
- Exports: presets in `export_presets.cfg`; templates installed under
  `%APPDATA%\Godot\export_templates\4.7.1.stable.steam`. Export with
  `--headless --export-release "Windows Client|Windows Server" <path>`.

## Workflow

- Always commit after a prompt. Every completed prompt should end with a git
  commit capturing the changes made during that prompt.
