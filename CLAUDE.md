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
- Keys: `interact` = E / pad Y (triangle); `inventory` = Tab / pad D-pad left.
  Tab used to be a `lock_on` binding — it was removed there, so lock-on is
  middle-mouse / pad R3 only. D-pad left is also Godot's built-in `ui_left`;
  that only ever moves focus inside an open panel, so the two coexist.

## Items and shops

- Item catalogue: `scripts/items/item_db.gd` — id -> name / buy price / desc.
  Selling pays `ItemDb.SELL_RATIO` (half, rounded down) unless an item carries
  its own `"sell"`. Never hardcode a price anywhere else; two shops must not
  disagree about what a sword is worth.
- Who stocks what: `scripts/ui/shop/shop_data.gd`, keyed by the NPC's
  `dialog_id`. Optional `"buys"` list restricts what that shop will take back;
  omit it and the shop buys anything.
- Giving an NPC a shop is two steps: add a `ShopData.SHOPS` entry under its
  `dialog_id`, and give one dialog answer `"action": "open_shop"`. `ShopSystem`
  listens to `DialogSystem.action_triggered` and opens itself — no per-NPC code.
- `DialogSystem._on_answer` emits the action AFTER changing line, so an answer
  can both end the conversation and open something without `close()` undoing it.
- Trading is server-authoritative (see "Server authority"). Coins and the bag
  live in `Net.players[peer_id]["coins"/"items"]`, which only the server
  writes. The shop UI calls `Net.request_buy/request_sell`; the server checks
  the shop stocks it, that the price is ItemDb's price, affordability/holdings,
  and that the pawn is actually at the counter (`Net._at_counter`), then pushes
  the new purse back with `cl_purse`. Clients read `Net.my_coins()` /
  `my_items()` / `my_item_count()` and redraw on `Net.purse_changed`; refusals
  arrive on `Net.trade_result` and show in the shop's hint line.
- Purses and bags are stripped from the broadcast registry (`_public_players`)
  — only the owner ever sees theirs.
- `Net.STARTING_COINS` is a placeholder purse (150) so the shop is usable; drop
  it to 0 once coins can actually be earned in play.
- An item's `"icon"` in `ItemDb` is what the bag grid and the shop rows draw;
  art lives in `Assets/Textures/Items/`, grouped like the models. Items with no
  usable icon fall back to drawing their name, so a bad path never crashes a
  screen. The shipped sword icons are 64x64 placeholders — overwrite the files.

## Multiplayer

- Boot flow: main scene is `scenes/ui/main_menu.tscn` (username + host/join).
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
- Dedicated server: separate export preset "Windows Server" (custom feature
  `server`) -> `build/AstriaServer.exe`; it auto-hosts headlessly (see
  `build/run_server.bat`). Any build also accepts `--server [--port=N]`,
  and clients accept `--username=NAME --host / --join=IP[:PORT]`.
- Exports: presets in `export_presets.cfg`; templates installed under
  `%APPDATA%\Godot\export_templates\4.7.1.stable.steam`. Export with
  `--headless --export-release "Windows Client|Windows Server" <path>`.

## Workflow

- Always commit after a prompt. Every completed prompt should end with a git
  commit capturing the changes made during that prompt.
