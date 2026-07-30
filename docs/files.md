# Every file, and what it does

Seven words a file, at most. Two conventions cover the noise instead of
repeating themselves 300 times:

- **`*.uid`** (148 of them) — Godot's stable id for the script beside it.
- **`*.import`** (149) — Godot's import settings for the asset beside it.

Neither is listed below. Everything else in the repo is.

## Root

| File | What it does |
| --- | --- |
| `.editorconfig` | UTF-8 for every file in tree |
| `.gitattributes` | Normalises line endings to LF |
| `.gitignore` | Keeps build output and caches untracked |
| `.mcp.json` | Points Claude at the Supabase project |
| `CLAUDE.md` | The rules this project is built by |
| `project.godot` | Godot settings, autoloads, input map |
| `export_presets.cfg` | Windows client and dedicated server presets |
| `icon.svg` | The project's icon |
| `newBlacksmith_1.gltf` | Stray blacksmith export left at root |
| `newBlacksmith_1_0.png` | Palette texture for that stray export |

## docs/

| File | What it does |
| --- | --- |
| `accounts.md` | How login, saving and RLS work |
| `files.md` | This list |

## scripts/ — the game

### scripts/combat/

| File | What it does |
| --- | --- |
| `combat_levels.gd` | Weapon level meets enemy level: damage |

### scripts/core/

| File | What it does |
| --- | --- |
| `network_manager.gd` | Autoload Net: hosting, joining, whole protocol |
| `game_stats.gd` | Local read-only mirror of server purse |
| `input_device.gd` | Which device you last touched, for glyphs |
| `discord_notifier.gd` | Posts "somebody joined" to a webhook |

### scripts/core/account/

| File | What it does |
| --- | --- |
| `auth.gd` | Client half: Discord login over PKCE |
| `save_store.gd` | Server half: reads and writes saves |
| `supabase.gd` | The HTTP layer and the two keys |

### scripts/core/net/

| File | What it does |
| --- | --- |
| `net_registry.gd` | A player entry: bag, purse, hotbar |
| `net_world.gd` | Scene lookups: pawns, players, spawn points |
| `net_voice.gd` | Server decides who hears a packet |
| `net_upnp.gd` | Asks the router to forward a port |

### scripts/core/voice/

| File | What it does |
| --- | --- |
| `voice_chat.gd` | Autoload Voice: your mic, their voices |
| `voice_codec.gd` | Companded wire format for speech samples |

### scripts/entities/

| File | What it does |
| --- | --- |
| `player.gd` | The pawn: movement, swings, three network roles |
| `enemy.gd` | Bandit AI: chase, attack, retreat, block |
| `boss.gd` | The juggernaut: poise, phases, earned openings |
| `humanoid_visual.gd` | Shared rig and animation driver, everyone |
| `player_visual.gd` | Player's voxel body, whole clip library |
| `boss_visual.gd` | Juggernaut's body, whole clip library |
| `rouge_visual.gd` | The Rouge mesh on that same rig |
| `fighter_audio.gd` | Every noise a fighter makes, shared |

### scripts/entities/humanoid/

| File | What it does |
| --- | --- |
| `humanoid_clips.gd` | Mixamo FBX into a playable retargeted clip |

### scripts/entities/npc/

| File | What it does |
| --- | --- |
| `npc_character.gd` | A placeable NPC built from its definition |
| `npc_definition.gd` | Everything the builder saves about one NPC |
| `npc_part.gd` | One slot: model, palette, tint, nudges |
| `npc_rig.gd` | Auto-rigs voxel parts onto the humanoid skeleton |
| `npc_visual.gd` | A built voxel NPC on Rouge's skeleton |
| `npc_interactable.gd` | Makes anything talkable, with a bubble |

### scripts/entities/npc/rig/

| File | What it does |
| --- | --- |
| `npc_layout.gd` | Measures the art to place each part |
| `npc_part_library.gd` | Where part art lives, and its listing |
| `npc_part_loader.gd` | Loads a model, flattens it, reads palette |
| `npc_reproportion.gd` | Reshapes the skeleton onto the art |
| `npc_skinner.gd` | Rigid voxel skinning, and the seam caps |

### scripts/entities/player/

| File | What it does |
| --- | --- |
| `player_anim.gd` | Picks the clip from what you're doing |
| `player_camera.gd` | Third-person camera, lock-on and impact shake |
| `player_net_state.gd` | Speed-caps and whitelists a client's claims |

### scripts/items/

| File | What it does |
| --- | --- |
| `item_db.gd` | The catalogue: level, price, art, grip |
| `armor/armor_definition.gd` | One saved suit of wearable armor |
| `armor/armor_library.gd` | Where suits live, listed and written |
| `icons/item_icon_renderer.gd` | Autoload ItemIcons: photographs every item's art |

### scripts/ui/

| File | What it does |
| --- | --- |
| `hud.gd` | Bars, reticle, and every HUD overlay |
| `inventory_ui.gd` | Bag, hotbar, equipment slots, stats tab |
| `main_menu.gd` | Boot screen: sign in, then join |
| `scoreboard.gd` | Hold-P table of the server's stats |
| `theme/ui_theme.gd` | The palette every screen is built from |
| `boss/boss_bar.gd` | Boss health, with a notch at phase |
| `cutscene/cinematic.gd` | Letterbox bars and camera on the speaker |
| `cutscene/intro_cutscene.gd` | Waking up: black, two lines, fade |
| `debug/cheat_menu.gd` | Editor-only cheats, every one server-checked |
| `dialog/dialog_data.gd` | Every conversation in the game, as data |
| `dialog/dialog_system.gd` | Typewriter dialog box with answer buttons |
| `dialog/npc_prompt_overlay.gd` | Draws the bubble over anything interactable |
| `items/item_prompt.gd` | Bottom-right buttons for what you hold |
| `prompt/prompt_target.gd` | The contract for "press interact here" |
| `quest/quest_marker_overlay.gd` | Gold star, and how far away |
| `quest/quest_tracker.gd` | The quest heading in the corner |
| `shop/shop_data.gd` | Who sells what, keyed by dialog |
| `shop/shop_ui.gd` | Autoload ShopSystem: buy and sell tabs |
| `tutorial/tutorial_overlay.gd` | The control popup and the nudging banner |
| `voice/voice_overlay.gd` | Mic glyph: yours, and over talkers |

### scripts/world/

| File | What it does |
| --- | --- |
| `world.gd` | Island root: collision, fog, intro hook |
| `main.gd` | Test arena root; bakes the navmesh |
| `ocean.gd` | Grid of wave tiles following the player |
| `bandit_spawner.gd` | Server-only camp: bandits on a timer |
| `gold_drop.gd` | Bobbing pile; the server pays it |
| `item_drop.gd` | Item on the ground; server awards it |
| `spawn_point.gd` | Marks where players spawn and respawn |
| `boss/boss_spawner.gd` | One boss at the marker, long respawn |
| `dungeon/dungeon_walls.gd` | Generates walls along the floor's real outline |
| `portal/portal.gd` | A doorway: walk-in, or press-to-enter |
| `gift/gift_data.gd` | Things an NPC hands over once |
| `gift/gift_system.gd` | Autoload Gifts: asks the server for one |
| `quest/quest_data.gd` | Every quest: name, target, giver |
| `quest/quest_system.gd` | Autoload Quests: asks the server to start |
| `quest/quest_anchor.gd` | Marks where a quest target is |
| `teleport/teleport_data.gd` | The places the teleport cheat reaches |
| `teleport/teleport_anchor.gd` | Marks a named teleport destination |
| `tutorial/tutorial_system.gd` | Autoload Tutorial: the server walks the lesson |
| `tutorial/tutorial_data.gd` | The tutorial script, step by step |
| `tutorial/tutorial_arena.gd` | One player's private copy of the island |

## scenes/

| File | What it does |
| --- | --- |
| `world.tscn` | The starter island level |
| `starterDungeon.tscn` | Catacombs level: walls, exit, boss spawner |
| `main.tscn` | Test arena with lights and navmesh |
| `player.tscn` | Player pawn: body, camera rig, collision |
| `enemy.tscn` | Bandit pawn: body, nav agent, collision |
| `boss.tscn` | Juggernaut pawn: body, nav agent, collision |
| `ui/main_menu.tscn` | Boot scene wrapping the menu script |
| `effects/furnace_fire.tscn` | Flames, smoke and embers for the furnace |
| `world/catacombs_entrance.tscn` | The island door into the catacombs |
| `world/quest_anchor.tscn` | Droppable quest-target marker |
| `world/teleport_anchor.tscn` | Droppable teleport-destination marker |
| `world/tutorial/tutorial_arena.tscn` | Island copy with its own spawn marker |
| `entities/npc/npc_interactable.tscn` | Droppable talk marker for any NPC |

Built by the NPC Builder, one node each, ready to drag into a level:

| File | What it does |
| --- | --- |
| `entities/npc/built/player.tscn` | The player's body, as a scene |
| `entities/npc/built/villager.tscn` | Placeable villager |
| `entities/npc/built/knight.tscn` | Placeable knight |
| `entities/npc/built/king.tscn` | Placeable king |
| `entities/npc/built/kingnpc.tscn` | Placeable king, second variant |

| File | What it does |
| --- | --- |
| `entities/npc/Boss/BigZombie/fatass_zombie (1) (1).gltf` | Unused big-zombie boss model |
| `entities/npc/Boss/BigZombie/fatass_zombie (1) (1)_0.png` | Its palette texture |

## tests/

Every script below has a matching `.tscn` of the same name — the launcher you
point Godot at. Only the scripts are listed; the scene is the same thing.

`test_*` print `RESULT=PASS/FAIL` and set the exit code. `preview_*` save PNGs
and need a real window. `diag_*` are throwaway measuring aids.

| File | What it does |
| --- | --- |
| `helpers/test_host.gd` | Shared boot: host, wait for pawn |
| `test_accounts.gd` | Key leaks, private fields, save queue |
| `test_armor_suits.gd` | A suit survives disk, copies when worn |
| `test_bandit_spawner.gd` | Camp finds floor under it, not canvas |
| `test_boss.gd` | Poise, openings, phases, drop, spawner floor |
| `test_catacombs.gd` | Door in, dungeon elsewhere, way back out |
| `test_combat.gd` | Clips, guard, parry, combos, squared stance |
| `test_dialog.gd` | A loop back must not retype lines |
| `test_discord.gd` | The message, and only dedicated servers post |
| `test_dungeon_walls.gd` | No wall in open floor, nothing unwalled |
| `test_gift.gd` | Catalogue, protection maths, one gift only |
| `test_gold_drops.gd` | One pile, rolled amount, paid on pickup |
| `test_hotbar.gd` | Auto-place, wrap, swap, clear, empty refused |
| `test_intro_cutscene.gd` | Black, lines, fade, frozen, not replayed |
| `test_item_icons.gd` | Every item has the right art |
| `test_menu_scroll.gd` | Long lists follow the gamepad highlight |
| `test_npc_builder.gd` | Whole rig pipeline, colours, save and reload |
| `test_quest.gd` | Quest state, and the marker's maths |
| `test_server_export.gd` | Server export still ships the island floor |
| `test_server_swing_timing.gd` | Server build can still time a swing |
| `test_shop.gd` | Counter is at the shopkeeper; buying, selling |
| `test_teleport.gd` | Missing anchor refused, real one lands pawn |
| `test_tutorial.gd` | Private island, gated steps, handover afterwards |
| `test_ui_theme.gd` | Palette really on screen, nothing black |
| `test_voice_chat.gd` | Who hears you, and flood protection |
| `preview_boss.gd` | Boss scale, telegraphs, ring, phase armour |
| `preview_dialog_camera.gd` | What the camera frames per talking character |
| `preview_dungeon.gd` | Seams, ceiling holes, room and stairs |
| `preview_get_up.gd` | Does the getting-up clip retarget |
| `preview_held_item.gd` | Lining up a new weapon's grip |
| `preview_item_icons.gd` | Every real icon on one sheet |
| `preview_npc_armor.gd` | Bare, in suit, in recoloured suit |
| `preview_player.gd` | Idle contact sheet, two angles, hole count |
| `preview_sword_swings.gd` | Every swing as an eight-frame strip |
| `preview_ui.gd` | Real screens shot over a stand-in world |
| `preview_voice.gd` | The voice HUD in each of its states |
| `diag_blade_clip.gd` | Does a swing put blade through body |
| `diag_grip_fit.gd` | Where the blade belongs in the hand |
| `diag_sword.gd` | Scores windows for cutting swings out |

## addons/ — editor tooling

### addons/npc_builder/ — the "NPC Builder" tab

| File | What it does |
| --- | --- |
| `plugin.cfg` | Plugin manifest |
| `plugin.gd` | Adds the tab to the main screen |
| `ui/npc_builder_screen.gd` | Turntable, slot editors, and Save |
| `ui/npc_preview.gd` | Live orbiting turntable of a real rig |
| `ui/part_slot_editor.gd` | One slot's model, swatches and nudges |
| `io/npc_writer.gd` | Writes the definition and its scene |

### addons/item_builder/ — the "Items" tab

| File | What it does |
| --- | --- |
| `plugin.cfg` | Plugin manifest |
| `plugin.gd` | Adds the tab to the main screen |
| `ui/item_builder_screen.gd` | Menu of makeable things; armor editor |

### addons/grass_brush/

| File | What it does |
| --- | --- |
| `plugin.cfg` | Plugin manifest |
| `grass_brush_plugin.gd` | Viewport brush: paint, erase, size keys |
| `grass_paint.gd` | Paintable grass layer in one MultiMesh |

### addons/sky_cloud_remover/

| File | What it does |
| --- | --- |
| `plugin.cfg` | Plugin manifest |
| `cloud_remover_plugin.gd` | Adds the Project > Tools menu entry |
| `cloud_scrub.gd` | Blends clouds into the sky gradient |

### addons/MagicaVoxel_Importer_with_Extensions/ — third-party `.vox` importer

| File | What it does |
| --- | --- |
| `plugin.cfg` | Plugin manifest |
| `.gitignore` | The addon's own ignores |
| `plugin.gd` | Registers both importers and the node |
| `vox-importer-common.gd` | Shared parse-then-mesh path |
| `vox-importer-mesh.gd` | Imports a `.vox` as a Mesh |
| `vox-importer-meshLibrary.gd` | Imports a `.vox` as a MeshLibrary |
| `VoxFile.gd` | Chunk-counting reader over a FileAccess |
| `Faces.gd` | The six cube faces as triangles |
| `CulledMeshGenerator.gd` | One quad per exposed voxel face |
| `GreedyMeshGenerator.gd` | Merges coplanar faces into bigger quads |
| `framed_mesh_instance.gd` | MeshInstance that steps through a MeshLibrary |
| `VoxFormat/VoxData.gd` | The whole parsed file in memory |
| `VoxFormat/Model.gd` | One model's size and its voxels |
| `VoxFormat/VoxNode.gd` | A scene-graph node and its transforms |
| `VoxFormat/VoxLayer.gd` | A layer's id and visibility |
| `VoxFormat/VoxMaterial.gd` | Voxel material properties to a StandardMaterial3D |
| `Metadata/LICENSE` | The addon's licence |
| `Metadata/README.md` | The addon's own documentation |
| `Metadata/vox-icon.png` | Icon for the custom node |
| `Metadata/vox-icon.vox` | The source it was drawn in |
| `framed_mesh_instance.png` | Icon for FramedMeshInstance |

## supabase/migrations/

| File | What it does |
| --- | --- |
| `0001_accounts.sql` | Profiles and saves tables, RLS locked |
| `0002_save_everything.sql` | The rest of a player persisted |
| `0003_lock_down_the_trigger_functions.sql` | Takes trigger functions out of the API |

## tools/

| File | What it does |
| --- | --- |
| `voxel/gox_to_gltf.py` | Converts `.gox` to Goxel-flavoured glTF |

## Assets/Data/ — authored resources

| File | What it does |
| --- | --- |
| `Armor/flimsy_armor.tres` | Level-one suit, as coloured |
| `Armor/copper_armor.tres` | Level-two suit, copper |
| `Armor/iron_armor.tres` | Level-three suit, iron |
| `Npcs/player.tres` | The body every player wears |
| `Npcs/juggernaut.tres` | The boss's body |
| `Npcs/villager.tres` | Villager definition |
| `Npcs/knight.tres` | Knight definition |
| `Npcs/king.tres` | King definition |
| `Npcs/kingnpc.tres` | King definition, second variant |

## Assets/Animations/Humanoid/ — Mixamo and mocap FBX takes

Each is one imported clip; `humanoid_clips.gd` retargets them.

| File | What it does |
| --- | --- |
| `Movement/Idle/Idle.fbx` | Standing still |
| `Movement/Idle/Offensive Idle.fbx` | Standing still, squared up |
| `Movement/Walking/Walking.fbx` | Walk forwards |
| `Movement/Walking/Walking Backwards.fbx` | Walk backwards |
| `Movement/Running/Running.fbx` | Run forwards |
| `Movement/Strafing/Left Strafe Walking.fbx` | Sidestep left |
| `Movement/Strafing/Right Strafe Walking.fbx` | Sidestep right |
| `Movement/Jumping/Jumping.fbx` | Jump |
| `Movement/Sliding/Running Slide.fbx` | Slide out of a run |
| `Combat/Stances/Bouncing Fight Idle.fbx` | Fighting stance |
| `Combat/Blocking/Boxing.fbx` | Guard up |
| `Combat/LightM1/Punching.fbx` | Light punch |
| `Combat/LightM1/Elbow Uppercut Combo.fbx` | Light combo continuation |
| `Combat/LightM1/Illegal Elbow Punch.fbx` | Light combo finisher |
| `Combat/HeavyM1/Cross Punch.fbx` | Heavy punch |
| `Cutscene/GettingUp/Getting Up.fbx` | Standing up off the floor |
| `Sword/Idle/Sword Idle.fbx` | Standing still holding a sword |
| `Sword/Walking/Sword Walk.fbx` | Walk holding a sword |
| `Sword/Running/Sword Run.fbx` | Run holding a sword |
| `Sword/Attack/Sword Combo.fbx` | Mocap take swings are cut from |
| `Sword/Attack/SwordCombo3.fbx` | Another take, another swing |
| `Sword/Attack/SwordCombo5.fbx` | Another take, another swing |
| `Sword/Attack/SwordCombo6.fbx` | Another take, another swing |
| `Sword/Attack/SwordCombo10.fbx` | Another take, another swing |

## Assets/Audio/SFX/

The `.tres` files are AudioStreamRandomizers — one noise, several takes.

| File | What it does |
| --- | --- |
| `Deaths/death_sounds.tres` | Randomiser over the three death takes |
| `Deaths/universfield-dramatic-death-collapse-352720.mp3` | Death collapse |
| `Deaths/vinodadora-male-death-sound-128357.mp3` | Male death cry |
| `Deaths/freesound_community-grunt2-84534.mp3` | Death grunt |
| `Deaths/Boss/boss_body_fall.mp3` | The juggernaut hitting the floor |
| `Grunts/Pair1/grunt_pair_1.tres` | Randomiser over the first grunt set |
| `Grunts/Pair1/freesound_community-grunt1-68324.mp3` | Pain grunt |
| `Grunts/Pair1/freesound_community-grunt1-84540.mp3` | Pain grunt |
| `Grunts/Pair1/freesound_community-ough-47202.mp3` | Pain grunt |
| `Grunts/Pair2/grunt_pair_2.tres` | Randomiser over the second grunt set |
| `Grunts/Pair2/Grunt 1.mp3` … `Grunt 7.mp3` | Seven pain grunts |
| `Grunts/Boss/boss_pain.mp3` | The juggernaut taking a hit |
| `Footsteps/Boss/boss_footsteps.mp3` | The juggernaut walking |
| `Impacts/Punches/punch_impacts.tres` | Randomiser over the punch takes |
| `Impacts/Punches/universfield-punch-02-123106.mp3` | Punch landing |
| `Impacts/Punches/universfield-punch-04-383965.mp3` | Punch landing |
| `Impacts/Punches/universfield-punch-140236.mp3` | Punch landing |
| `Impacts/Blocks/block_impacts.tres` | Randomiser over the block takes |
| `Impacts/Blocks/universfield-classic-punch-impact-352711.mp3` | Punch caught on a guard |
| `Wooshes/woosh_sounds.tres` | Randomiser over the swing takes |
| `Wooshes/musicholder-woosh-260275.mp3` | Swing through the air |
| `Wooshes/ribhavagrawal-woosh-230554.mp3` | Swing through the air |
| `Wooshes/u_u4pf5h7zip-woosh-345977.mp3` | Swing through the air |
| `UI/Typing/keyboard_typing.mp3` | The dialog box's typewriter clatter |

## Assets/Fonts/

| File | What it does |
| --- | --- |
| `EBGaramond/EBGaramond-VariableFont_wght.ttf` | The UI's serif face |
| `EBGaramond/EBGaramond-Italic-VariableFont_wght.ttf` | Its italic |
| `EBGaramond/OFL.txt` | Its licence |

## Assets/Models/Entity/Humanoid/

`.gox` is the Goxel source, `.gltf` its export, `_0.png` its palette texture.

| File | What it does |
| --- | --- |
| `bonemap_mixamo.tres` | Mixamo bones onto the humanoid profile |
| `bonemap_manny.tres` | UE Manny bones onto the humanoid profile |
| `bonemap_motusman.tres` | Mocap-pack bones onto the humanoid profile |
| `Human/rouge.fbx` | Rouge mesh, and the skeleton everything borrows |

Voxel character parts (`VoxelNpc/Parts/<Set>/<Slot>/`), three files each:

| Set | Slots | What it is |
| --- | --- | --- |
| `Base/` | `Head` (`head_base`, `basic_head`), `Body`, `Arms`, `Feet` | The default villager body |
| `King/` | `Head`, `Body`, `Arms`, `Feet` | The king's body |
| `Undead/` | `Head`, `Body`, `Arms`, `Feet` — `skeleton_*` and `zombie_*` | Two undead bodies |

| File | What it does |
| --- | --- |
| `VoxelNpc/Armor/Armor1/Head/head_armor1.*` | Helmet plate |
| `VoxelNpc/Armor/Armor1/Body/body_armor1.*` | Chest plate |
| `VoxelNpc/Armor/Armor1/Arms/arms_armor1.*` | Arm plates |
| `VoxelNpc/Armor/Armor1/Feet/feet_armor1.*` | Boots |

## Assets/Models/Items/

| File | What it does |
| --- | --- |
| `Weapons/Swords/wooden_sword.gltf` / `.gox` | Level-one blade |
| `Weapons/Swords/copper_sword.gltf` / `.gox` | Level-two blade |
| `Weapons/Swords/iron_sword.gltf` / `.gox` | Level-three blade |
| `Weapons/Swords/sword_base.gltf` / `.gox` | The blade the three are cut from |
| `Weapons/Swords/sword_deco.gltf` / `.gox` | Decorative sword for the world |
| `Weapons/Swords/tony_sword.fbx` | The mocap pack's own sword |
| `Weapons/Swords/MotusMan_v50B_FBX_001_v02.fbm/Refelection_03.jpg` | Texture that FBX shipped with |
| `Weapons/Clubs/club.gltf` | The juggernaut's club |
| `Weapons/Clubs/club_0.png` | Its palette texture |

## Assets/Models/World/

| File | What it does |
| --- | --- |
| `Islands/StarterIsland/Island1.glb` | The starter island terrain |
| `Dungeons/StarterDungeon/dungeon1.glb` | The catacombs floor and stairs |
| `wave_mesh.tscn` | One ocean tile, wave shader on it |
| `Prefab/grass.tscn` | Grass clump prefab |
| `Prefab/Data/Grass/grass.glb` / `.res` | Blade mesh, and its saved resource |
| `Prefab/Data/Grass/grass2.glb` / `.res` | Second blade mesh and resource |
| `Prefab/Anvil.gltf`, `Anvil_0.png` | Anvil, placed in the world |
| `Prefab/Furnace.gltf`, `Furnace_0.png` | Furnace, placed in the world |
| `Prefab/halfdoor.gltf`, `halfdoor_0.png` | Half-door prop |
| `Prefab/stoneWall.gltf`, `.gox`, `_0.png` | Dungeon wall segment |
| `Prefab/swordDeco.gltf`, `swordDeco_0.png` | Sword-in-the-ground prop |

Starter island buildings (`Islands/StarterIsland/Buildings/`):

| File | What it does |
| --- | --- |
| `Blacksmith.gltf` / `.gox` | Blacksmith, first pass |
| `Blacksmith2.gltf` | Blacksmith, second pass |
| `newBlacksmith.gltf` / `.gox` | Blacksmith, the one in use |
| `newBlacksmith2.gltf`, `newBlacksmith_1.gltf` | Further blacksmith variants |
| `BlackSmithWorkshop.gltf`, `.vox`, `_0.png` | Workshop around the blacksmith |
| `Anvil.gltf` / `.gox` | Anvil |
| `Furnace.gltf` / `.gox` | Furnace |
| `TownHall.gltf`, `TownHall_0.png` | Town hall |
| `House1.gltf`, `House1_0.png` | House |
| `house2.gltf`, `house2_0.png` | Second house |
| `halftent.gltf`, `halftent_0.png` | Tent the bandit camp sits under |
| `halfdoor.gltf` / `.gox` | Half-door |
| `crate.gltf`, `.gox`, `_0.png` | Crate |
| `woodFence.gltf` / `.gox` | Fence section |
| `WheatPatch.gltf`, `WheatPatch_0.png` | Wheat patch |

Loose art, not in the game (`Assets/Models/Storage/`):

| File | What it does |
| --- | --- |
| `Island1.blend` / `Island1.glb` | Island source and export |
| `PotionGuy.gltf` / `.gox` | Unused NPC model |
| `fatass_zombie.gltf` | Unused zombie model |

## Assets/Textures/

| File | What it does |
| --- | --- |
| `Shaders/grass.gdshader` | Wind noise on every grass blade |
| `Shaders/ocean.gdshader` | The moving waves |
| `Skyboxes/beautiful-view-sea-with-cloudy-sky-reflected-it.jpg` | Panorama sky, as downloaded |
| `Skyboxes/…_noclouds.png` | The same sky, clouds scrubbed |
| `UI/panel_grunge.jpg` | The cracked paint behind every panel |
| `Items/Weapons/Swords/sword_reflection.jpg` | Sword reflection map |
| `Humanoid/Human/Rouge/DungeonCrawler_Character_002-*.png` | Rouge's sixteen body-part textures |
