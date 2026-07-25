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
  only the FIRST cut is used — `"slice": [0.58, 0.98]`, which starts from the
  standing ready pose and is out before the crouch settles. Every light swing
  plays that one slash (`sword_slash`) and the heavy is the same slice at a
  slower `"speed"`, which is also what makes it the slower, heavier-looking
  swing. If more sword moves are ever wanted they need a take that stays on
  its feet, not another slice of this one.
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
  (everything in `ItemDb.ITEMS`; picking one asks the server for a copy) and
  "Teleport" (everything in `TeleportData.DESTINATIONS`). Adding a cheat is one
  row in `_build_root`.
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
  <Slot>/`. `<Set>` is a character family (`Base`, `Undead`) and becomes its
  own section in the builder's menus; `<Slot>` is Head/Body/Arms/Feet. Drop a
  Goxel glTF export in the right folder and press "Rescan parts" — there is no
  metadata to register.
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
- Test: `--headless res://tests/test_npc_builder.tscn` (prints
  `NPCTEST RESULT=PASS/FAIL`). It rigs every part model in the library, checks
  the bind sets, that animation still moves the reshaped bones, that re-rigging
  is idempotent, that building twice still leaves one of everything, that
  colours reach the mesh, and that a saved NPC reloads as a talkable scene —
  plus that Rouge still builds his own rig and full clip set.

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
