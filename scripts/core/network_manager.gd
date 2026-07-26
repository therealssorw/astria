extends Node
## Autoload "Net": all multiplayer plumbing — hosting/joining (ENet), UPnP
## port mapping so hosts don't need manual port forwarding, the server-
## authoritative player registry (usernames + kills/deaths) and the whole
## RPC protocol. The server never trusts clients: it validates movement,
## simulates all combat itself and is the only writer of health and stats;
## everything a client sends is treated as a request or a cosmetic claim.

const DEFAULT_PORT := 27032

## The live dedicated server every client joins on launch. It is an EC2 box in
## us-east-2, and an instance's public address is NOT stable across a stop and
## start unless an Elastic IP is attached -- if players suddenly cannot connect,
## check this still matches the instance before looking anywhere else.
const DEFAULT_SERVER := "3.137.184.94"

const MAX_PLAYERS := 16
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

const PLAYER_STATE_INTERVAL := 1.0 / 20.0  # server -> clients pawn states
const ENEMY_STATE_INTERVAL := 1.0 / 15.0   # server -> clients enemy states
const VITALS_INTERVAL := 0.5               # server -> owner stamina/health sync
const KILL_Y := 30.0                       # below the waves -> counts as a death

const GOLD_DROP_SCRIPT := preload("res://scripts/world/gold_drop.gd")
const GOLD_PICKUP_RANGE := 1.4             # walk this close to collect a pile
const GOLD_PICKUP_INTERVAL := 0.1          # server proximity check cadence
const GOLD_DESPAWN_SECONDS := 120.0        # unclaimed piles vanish after this
## How far past an NPC's interact_range the server still honours a trade, to
## cover the lag between the client's view of its position and the server's.
const SHOP_RANGE_SLACK := 2.5

## Quick-use bar: which carried item each of the 9 slots points at, and which
## slot is in hand. Server-owned like the bag itself — what you are holding is
## gameplay, not a screen decoration.
const HOTBAR_SLOTS := 9

## How far a voice carries. The server relays a speech packet only to the peers
## whose pawns are inside this of the speaker's — measured on its OWN copies of
## both — and the listener's audio fades to nothing at exactly the same distance,
## so the cut-off is never audible as a pop.
const VOICE_RANGE := 24.0

## peer_id -> {"name", "kills", "deaths", "gold", "items", "hotbar", "hot_slot"}.
## Server-owned. "gold"/"items"/"hotbar"/"hot_slot" are private to their owner:
## they are stripped before the registry is broadcast, and each owner gets
## theirs alone through cl_purse.
var players := {}
var is_dedicated := false
var active := false            # hosting or connected right now
var upnp_status := "inactive"  # inactive / searching / ok / failed
var public_ip := ""
var host_port := DEFAULT_PORT
var last_error := ""           # shown by the menu after a kick/disconnect

signal player_list_changed
signal join_failed(reason: String)
## The local player's gold/items mirror was re-synced from the server.
signal purse_changed
## Server's verdict on a trade the local player asked for.
signal trade_result(message: String, ok: bool)
## The server acted on a "use the held item" request. `item_id` is "" when
## there was nothing to use; `message` is the line to show the player.
signal item_used(item_id: String, message: String)

var _upnp_thread: Thread
var _upnp_cleanup_thread: Thread
var _upnp_mapper = null      # UPNP instance that owns the active mapping
var _mapped_port := 0        # 0 = nothing mapped on the router right now
var _enemy_counter := 0
var _gold_counter := 0
var _player_bcast_accum := 0.0
var _enemy_bcast_accum := 0.0
var _vitals_accum := 0.0
var _gold_accum := 0.0
## Voice flood control, server-side: peer -> [window start msec, bytes spent].
var _voice_spend := {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _exit_tree() -> void:
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	if _upnp_cleanup_thread and _upnp_cleanup_thread.is_started():
		_upnp_cleanup_thread.wait_to_finish()
	_remove_upnp_mapping(true) # blocking: the app is quitting

# ---------------- session setup ----------------

func host_game(username: String, dedicated := false, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		last_error = "Could not open port %d (already in use?)." % port
		return err
	multiplayer.multiplayer_peer = peer
	is_dedicated = dedicated
	active = true
	host_port = port
	players.clear()
	if not dedicated:
		players[1] = _make_entry(_sanitize_name(username))
	_start_upnp(port)
	print("[Net] Hosting on port %d%s" % [port, " (dedicated)" if dedicated else ""])
	# deferred: host_game is typically called from the menu's _ready/signals
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)
	return OK

func join_game(ip: String, username: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		join_failed.emit("Invalid address.")
		return err
	multiplayer.multiplayer_peer = peer
	active = true
	_pending_username = username
	return OK

var _pending_username := ""

func return_to_menu(message := "") -> void:
	last_error = message
	active = false
	is_dedicated = false
	players.clear()
	_voice_spend.clear()
	Voice.reset()
	_remove_upnp_mapping(false) # the server is gone, close the router port
	upnp_status = "inactive"
	public_ip = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)

func should_run_dedicated() -> bool:
	if OS.has_feature("server"):
		return true
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	return args.has("--server")

# ---------------- connection callbacks ----------------

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[Net] Peer %d connected, waiting for registration" % id)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has(id):
		print("[Net] %s left" % players[id]["name"])
		players.erase(id)
	_voice_spend.erase(id)
	Voice.forget(id)
	Tutorial.server_end(id, false) # their copy of the city goes with them
	var pawn := _pawn(id)
	if pawn:
		pawn.queue_free()
	rpc("cl_remove_player", id)
	_sync_players()

func _on_connected_to_server() -> void:
	rpc_id(1, "sv_register", _pending_username)

func _on_connection_failed() -> void:
	active = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit("Could not reach the host.")

func _on_server_disconnected() -> void:
	return_to_menu("Connection to the host was lost.")

# ---------------- registration / world flow ----------------

## Client -> server: first thing a client sends after connecting.
@rpc("any_peer", "call_remote", "reliable")
func sv_register(username: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		return  # re-registration would reset stats — never allow it
	players[id] = _make_entry(_sanitize_name(username))
	print("[Net] %s joined (peer %d)" % [players[id]["name"], id])
	# tell Discord somebody is on, so people who would play with them find out.
	# Server-side and after registration, so the roster it reports includes them
	Discord.post_join(str(players[id]["name"]), player_names())
	_sync_players()
	rpc_id(id, "cl_load_world")

## Server -> one client: registration accepted, load into the island.
@rpc("authority", "call_remote", "reliable")
func cl_load_world() -> void:
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)

var _pending_world_ready: Array[int] = []

## Called by world.gd once the world scene is up on this peer.
func on_world_ready() -> void:
	if multiplayer.is_server():
		print("[Net] World loaded — ready for players")
		if not is_dedicated:
			_server_spawn_player(1)
		# clients that finished loading before the server's own world did
		for id in _pending_world_ready:
			_handle_world_ready(id)
		_pending_world_ready.clear()
	else:
		rpc_id(1, "sv_world_ready")

## Client -> server: my world is loaded, give me the snapshot + my pawn.
@rpc("any_peer", "call_remote", "reliable")
func sv_world_ready() -> void:
	if not multiplayer.is_server():
		return
	_handle_world_ready(multiplayer.get_remote_sender_id())

func _handle_world_ready(id: int) -> void:
	if not players.has(id):
		return
	if _players_node() == null:
		if not _pending_world_ready.has(id):
			_pending_world_ready.append(id)
		return
	# snapshot of everything that already exists, just to the newcomer
	var pn := _players_node()
	if pn:
		for pawn in pn.get_children():
			rpc_id(id, "cl_spawn_player", pawn.peer_id, pawn.username,
					pawn.net_pos if not pawn.is_local else pawn.global_position)
	var en := _enemies_node()
	if en:
		for e in en.get_children():
			# another player's tutorial bandits are not in this player's world
			if not e.dead and int(e.owner_peer) in [0, id]:
				rpc_id(id, "cl_spawn_enemy", String(e.name), e.global_position)
	var dn := _drops_node()
	if dn:
		for d in dn.get_children():
			rpc_id(id, "cl_spawn_gold", String(d.name), d.global_position, d.amount)
	# the public slice only — a newcomer has no business seeing anyone's purse
	rpc_id(id, "cl_sync_players", _public_players())
	# then their own pawn, broadcast to everyone (including them)
	_server_spawn_player(id)

func _server_spawn_player(id: int) -> void:
	var pn := _players_node()
	if pn == null or pn.has_node(str(id)):
		return
	# a player joining wakes up in their own copy of the tutorial city, not on
	# the island; only when there is no room for one do they start out here
	var pos := Tutorial.server_begin(id)
	if pos == Vector3.INF:
		pos = spawn_position(pn.get_child_count())
	rpc("cl_spawn_player", id, players[id]["name"], pos)
	_do_spawn_player(id, players[id]["name"], pos)
	_send_purse(id) # first sync of their gold/bag, now that they have a pawn

@rpc("authority", "call_remote", "reliable")
func cl_spawn_player(id: int, username: String, pos: Vector3) -> void:
	_do_spawn_player(id, username, pos)

func _do_spawn_player(id: int, username: String, pos: Vector3) -> void:
	var pn := _players_node()
	if pn == null or pn.has_node(str(id)):
		return
	var pawn := PLAYER_SCENE.instantiate()
	pawn.name = str(id)
	pawn.peer_id = id
	pawn.username = username
	pn.add_child(pawn)
	pawn.global_position = pos
	pawn.net_pos = pos

@rpc("authority", "call_remote", "reliable")
func cl_remove_player(id: int) -> void:
	var pawn := _pawn(id)
	if pawn:
		pawn.queue_free()
	Voice.forget(id) # their voice hung on that pawn, and their name on the HUD

## Registry broadcast — the ONLY source of usernames/kills/deaths anywhere.
## Gold and items are stripped out (see _public_players); your own reach you
## privately through cl_purse, which fills the GameStats mirror.
@rpc("authority", "call_remote", "reliable")
func cl_sync_players(server_players: Dictionary) -> void:
	players = server_players
	player_list_changed.emit()

func _sync_players() -> void:
	rpc("cl_sync_players", _public_players())
	player_list_changed.emit()

## What everyone is allowed to see: no one needs another player's purse or bag,
## so those never leave the server except to the peer they belong to.
func _public_players() -> Dictionary:
	var out := {}
	for id in players:
		var e: Dictionary = players[id]
		# "held" is the one part of a bag everyone can see: it is in your hand,
		# so every other pawn has to draw it. The rest of the bag stays private.
		out[id] = {"name": e["name"], "kills": e["kills"], "deaths": e["deaths"],
				"held": held_item(e)}
	return out

## This peer's pawn, or null if it has none right now. On the server this is
## the authoritative copy — the one combat and the tutorial's gates read.
func pawn_of(id: int) -> Node:
	return _pawn(id)

## What peer `id` has in hand, whichever side of the wire this is: the server
## reads its own bar, a client reads the "held" field of the public registry.
func held_of(id: int) -> String:
	var entry: Dictionary = players.get(id, {})
	if entry.has("hotbar"):
		return held_item(entry)
	return str(entry.get("held", ""))

## Total armor level a peer has on: the BEST piece carried in each of the four
## slots, added up. Nothing to do with the hotbar — armor is not something you
## hold — and best-per-slot is what stops four helmets in a bag counting as a
## suit.
##
## Read off the SERVER's own bag (`players[id].items`), like everything else a
## client could gain by lying about. On a client this reads the mirror instead,
## which is only ever used to show the number, never to decide a hit.
##
## Carried IS worn, for now: there is no equipment yet (the inventory's
## equipment slots are still decoration), so picking a piece up is what puts it
## on. When equipping arrives this is the one function that has to change —
## everything downstream asks it rather than looking in a bag itself.
func armor_levels(peer_id: int) -> int:
	var bag: Dictionary = {}
	if players.has(peer_id):
		bag = players[peer_id].get("items", {})
	elif peer_id == multiplayer.get_unique_id():
		bag = GameStats.items
	var best := {}
	for item_id: String in bag:
		if int(bag[item_id]) <= 0:
			continue
		var slot := ItemDb.armor_slot(item_id)
		if slot == "":
			continue
		best[slot] = maxi(int(best.get(slot, 0)), ItemDb.level_of(item_id))
	var total := 0
	for slot: String in best:
		total += int(best[slot])
	return total

## The item in an entry's selected hotbar slot, or "".
func held_item(entry: Dictionary) -> String:
	var bar: Array = entry.get("hotbar", [])
	var slot := int(entry.get("hot_slot", 0))
	if slot < 0 or slot >= bar.size():
		return ""
	return str(bar[slot])

func _make_entry(username: String) -> Dictionary:
	var entry := {"name": username, "kills": 0, "deaths": 0, "gold": 0,
			"items": _starting_items(), "hotbar": _empty_hotbar(), "hot_slot": 0,
			"quest": "", # id of the quest being tracked, "" for none
			"quest_kills": 0, # kills counted towards it, when it asks for kills
			"gifts": {}, # GiftData ids already handed over, so none is given twice
			"seen": {}} # items already offered a hotbar slot (server-side only)
	_refill_hotbar(entry) # --dev-items handouts land on the bar like anything else
	return entry

func _empty_hotbar() -> Array:
	var bar := []
	bar.resize(HOTBAR_SLOTS)
	bar.fill("")
	return bar

## Testing aid: launch the SERVER with --dev-items and everyone who joins it
## starts with one of every item in the catalogue. It is deliberately a server
## flag — a client passing it gains nothing, because only the server ever
## writes a bag.
func _starting_items() -> Dictionary:
	if not multiplayer.is_server():
		return {}
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if not args.has("--dev-items"):
		return {}
	var bag := {}
	for id in ItemDb.ITEMS:
		bag[id] = 1
	return bag

func _sanitize_name(raw: String) -> String:
	var cleaned := ""
	for ch in raw.strip_edges():
		if ch >= " " and cleaned.length() < 20:
			cleaned += ch
	if cleaned.is_empty():
		cleaned = "Player"
	# dedupe against everyone already registered
	var taken := []
	for id in players:
		taken.append(players[id]["name"])
	var candidate := cleaned
	var n := 2
	while taken.has(candidate):
		candidate = "%s(%d)" % [cleaned, n]
		n += 1
	return candidate

func my_stats() -> Dictionary:
	return players.get(multiplayer.get_unique_id(), _make_entry(""))

## Everybody currently registered, by name. The scoreboard reads the registry
## itself; this is for anything that just wants the roster (the Discord post).
func player_names() -> Array:
	var names: Array = []
	for id in players:
		names.append(str(players[id].get("name", "")))
	return names

# ---------------- purse and bag (server-owned) ----------------
#
# Gold and carried items live in the registry above, which only the server
# writes. Clients hold a read-only mirror in GameStats and ASK to trade; the
# server checks the shop stocks the item, that the price is its own price,
# that the player can afford it or actually holds it, and that they are
# standing at the counter. A client that lies gets a refusal and a re-sync.

# ---------------- quests ----------------
#
# The tracked quest is progression, so the server owns it and the client gets a
# read-only copy in its private purse slice — the same deal as gold and the bag.
# Talking to an NPC is purely local (see "NPC dialog" in CLAUDE.md), so the
# server cannot see the conversation; it checks the one thing it CAN check, the
# same thing a shop checks: is that pawn actually standing at that NPC.

## Client -> server: the quest giver's dialog just offered me this. Asking is
## all the client does — a patched one that asks for a quest it was never
## offered still has to be stood at the NPC that hands it out.
func request_start_quest(quest_id: String) -> void:
	if multiplayer.is_server():
		_server_start_quest(multiplayer.get_unique_id(), quest_id)
	else:
		rpc_id(1, "sv_start_quest", quest_id)

@rpc("any_peer", "call_remote", "reliable")
func sv_start_quest(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_start_quest(multiplayer.get_remote_sender_id(), quest_id)

func _server_start_quest(id: int, quest_id: String) -> void:
	if not players.has(id) or not QuestData.has(quest_id):
		return
	var giver := QuestData.giver(quest_id)
	if giver == "" or not _near_npc(id, giver):
		return # nobody hands this one out, or you are not standing at them
	_set_quest(id, quest_id)

## Client -> server: I am talking to the NPC this quest ends at, so I'd like to
## hand it in. Refused unless you are actually on it and actually stood there.
func request_finish_quest(quest_id: String) -> void:
	if multiplayer.is_server():
		_server_finish_quest(multiplayer.get_unique_id(), quest_id)
	else:
		rpc_id(1, "sv_finish_quest", quest_id)

@rpc("any_peer", "call_remote", "reliable")
func sv_finish_quest(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_finish_quest(multiplayer.get_remote_sender_id(), quest_id)

func _server_finish_quest(id: int, quest_id: String) -> void:
	if not players.has(id) or not QuestData.has(quest_id):
		return
	if str(players[id].get("quest", "")) != quest_id:
		return # not on it: nothing to hand in
	var at := QuestData.done_at(quest_id)
	if at == "" or not _near_npc(id, at):
		return
	# paid once, because handing in is what clears the quest: come back and the
	# check above sees you are not on it any more
	var reward := QuestData.reward_gold(quest_id)
	if reward > 0:
		players[id]["gold"] = int(players[id].get("gold", 0)) + reward
	_set_quest(id, "") # sends the purse, so the gold rides along with it

## Client -> server: the NPC I am talking to just offered me this. Same shape as
## a quest request and for the same reason — the conversation is local, so the
## server cannot see the offer was made and checks the part it CAN see: that the
## pawn is standing at the NPC who gives it out, and that it has not already
## been handed over.
func request_gift(gift_id: String) -> void:
	if multiplayer.is_server():
		_server_take_gift(multiplayer.get_unique_id(), gift_id)
	else:
		rpc_id(1, "sv_take_gift", gift_id)

@rpc("any_peer", "call_remote", "reliable")
func sv_take_gift(gift_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_take_gift(multiplayer.get_remote_sender_id(), gift_id)

func _server_take_gift(id: int, gift_id: String) -> void:
	if not players.has(id) or not GiftData.has(gift_id):
		return
	var giver := GiftData.giver(gift_id)
	if giver == "" or not _near_npc(id, giver):
		return # nobody hands this one out, or you are not standing at them
	server_grant_gift(id, gift_id)

## SERVER: hand `gift_id` over, once. Marking it taken BEFORE the items go in is
## deliberate — this is the only thing standing between a client that asks twice
## in one frame and two suits of armor.
func server_grant_gift(id: int, gift_id: String) -> bool:
	if not players.has(id) or not GiftData.has(gift_id):
		return false
	var taken: Dictionary = players[id].get("gifts", {})
	if taken.has(gift_id):
		return false
	taken[gift_id] = true
	players[id]["gifts"] = taken
	var bag: Dictionary = players[id]["items"]
	for item_id: String in GiftData.items(gift_id):
		if not ItemDb.has(item_id):
			push_warning("Net: gift '%s' lists an unknown item '%s'" % [gift_id, item_id])
			continue
		bag[item_id] = int(bag.get(item_id, 0)) + 1
	print("[Net] %s was given '%s'" % [players[id]["name"], gift_id])
	_bag_changed(id) # sends the purse, so the gifts record rides along with it
	return true

## Server-side code putting a player on a quest — the tutorial's hand-off. Not
## a request: this is the server deciding, so there is nothing to validate.
func server_grant_quest(id: int, quest_id: String) -> void:
	if not QuestData.has(quest_id):
		push_warning("Net: no quest named '%s'" % quest_id)
		return
	_set_quest(id, quest_id)

## Server: put a player on a quest ("" clears it) and push the change to them.
## Changing quest always restarts the count: kills are progress towards the one
## you are on, never a running total you could carry into the next quest.
func _set_quest(id: int, quest_id: String) -> void:
	if not players.has(id):
		return
	players[id]["quest"] = quest_id
	players[id]["quest_kills"] = 0
	_send_purse(id)

## SERVER: `id` just killed a bandit. It only counts while they are on a quest
## that asks for kills, and that quest finishes itself the moment the count is
## reached — it has no `done_at`, so there is nobody to report back to.
func _credit_quest_kill(id: int) -> void:
	if not players.has(id):
		return
	var quest_id := str(players[id].get("quest", ""))
	var needed := QuestData.kills_needed(quest_id)
	if needed <= 0:
		return
	var done := int(players[id].get("quest_kills", 0)) + 1
	players[id]["quest_kills"] = done
	if done < needed:
		_send_purse(id)
		return
	print("[Net] %s finished '%s' (%d kills)" % [players[id]["name"],
			QuestData.label(quest_id), done])
	_set_quest(id, "")

## Client -> server: I'd like to buy this. Never applied locally first.
func request_buy(shop_id: String, item_id: String) -> void:
	if multiplayer.is_server():
		_server_trade(multiplayer.get_unique_id(), shop_id, item_id, true)
	else:
		rpc_id(1, "sv_shop_trade", shop_id, item_id, true)

func request_sell(shop_id: String, item_id: String) -> void:
	if multiplayer.is_server():
		_server_trade(multiplayer.get_unique_id(), shop_id, item_id, false)
	else:
		rpc_id(1, "sv_shop_trade", shop_id, item_id, false)

@rpc("any_peer", "call_remote", "reliable")
func sv_shop_trade(shop_id: String, item_id: String, buying: bool) -> void:
	if not multiplayer.is_server():
		return
	_server_trade(multiplayer.get_remote_sender_id(), shop_id, item_id, buying)

func _server_trade(id: int, shop_id: String, item_id: String, buying: bool) -> void:
	if not players.has(id):
		return
	if not ShopData.has(shop_id) or not ItemDb.has(item_id):
		_trade_reply(id, "There's nothing like that for sale here.", false)
		return
	if not _near_npc(id, shop_id):
		_trade_reply(id, "You're too far from the counter.", false)
		return

	var entry: Dictionary = players[id]
	var items: Dictionary = entry["items"]
	var gold := int(entry.get("gold", 0))
	var label := ItemDb.item_name(item_id)

	if buying:
		if not ShopData.stock(shop_id).has(item_id):
			_trade_reply(id, "He doesn't stock that.", false)
			return
		var price := ItemDb.buy_price(item_id)
		if gold < price:
			_trade_reply(id, "Not enough gold — %s costs %d." % [label, price], false)
			return
		entry["gold"] = gold - price
		items[item_id] = int(items.get(item_id, 0)) + 1
		_trade_reply(id, "Bought %s for %d gold." % [label, price], true)
	else:
		if not ShopData.buys(shop_id, item_id):
			_trade_reply(id, "He won't take that.", false)
			return
		var held := int(items.get(item_id, 0))
		if held < 1:
			_trade_reply(id, "You have no %s to sell." % label, false)
			return
		var price := ItemDb.sell_price(item_id)
		if held > 1:
			items[item_id] = held - 1
		else:
			items.erase(item_id)
		entry["gold"] = gold + price
		_trade_reply(id, "Sold %s for %d gold." % [label, price], true)

	_bag_changed(id)

# ---------------- cheats (development only) ----------------
#
# The cheat menu is a testing tool, so it goes through the server like anything
# else that touches a bag — a client still cannot write its own items. The
# server refuses every request unless IT is running from the editor, so an
# exported dedicated server ignores cheats no matter what a client sends.

## Would this build honour a cheat request? False in any exported build.
func cheats_allowed() -> bool:
	return OS.has_feature("editor")

## Client -> server: put one of this item in my bag. Editor builds only.
func request_cheat_give(item_id: String) -> void:
	if multiplayer.is_server():
		_server_cheat_give(multiplayer.get_unique_id(), item_id)
	else:
		rpc_id(1, "sv_cheat_give", item_id)

@rpc("any_peer", "call_remote", "reliable")
func sv_cheat_give(item_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_cheat_give(multiplayer.get_remote_sender_id(), item_id)

func _server_cheat_give(id: int, item_id: String) -> void:
	if not players.has(id):
		return
	if not cheats_allowed():
		_trade_reply(id, "Cheats are off on this server.", false)
		return
	if not ItemDb.has(item_id):
		_trade_reply(id, "No such item.", false)
		return
	var items: Dictionary = players[id]["items"]
	items[item_id] = int(items.get(item_id, 0)) + 1
	_trade_reply(id, "Gave %s." % ItemDb.item_name(item_id), true)
	_bag_changed(id)

## Client -> server: put me back at the start of the tutorial. Editor builds
## only — and it is a real restart on the server (a fresh copy of the city, its
## own bandits), not a client pretending to be at step one.
func request_cheat_tutorial() -> void:
	if multiplayer.is_server():
		_server_cheat_tutorial(multiplayer.get_unique_id())
	else:
		rpc_id(1, "sv_cheat_tutorial")

@rpc("any_peer", "call_remote", "reliable")
func sv_cheat_tutorial() -> void:
	if not multiplayer.is_server():
		return
	_server_cheat_tutorial(multiplayer.get_remote_sender_id())

func _server_cheat_tutorial(id: int) -> void:
	if not players.has(id):
		return
	if not cheats_allowed():
		_trade_reply(id, "Cheats are off on this server.", false)
		return
	var pawn := _pawn(id)
	if pawn == null or pawn.dead:
		_trade_reply(id, "Not while you are down.", false)
		return
	var pos := Tutorial.server_begin(id)
	if pos == Vector3.INF:
		_trade_reply(id, "No room for another copy of the city.", false)
		return
	pawn.net_teleport(pos)
	if id != 1:
		rpc_id(id, "cl_force_position", pos)
	# a restart has nobody to report in for it, so the lesson starts at once
	Tutorial.server_report_ready(id)
	_trade_reply(id, "Tutorial restarted.", true)

## Client -> server: put me in the starter town. Editor builds only. It is a
## destination first and an escape hatch second: from inside the tutorial it
## GRADUATES you — the same exit the last lesson uses, so the copy of the city
## is torn down, its bandits go with it and the follow-up quest is handed over.
## A plain teleport out would leave the lesson running behind you, with its
## bandits standing in an island nobody is in.
func request_cheat_starter_town() -> void:
	if multiplayer.is_server():
		_server_cheat_starter_town(multiplayer.get_unique_id())
	else:
		rpc_id(1, "sv_cheat_starter_town")

@rpc("any_peer", "call_remote", "reliable")
func sv_cheat_starter_town() -> void:
	if not multiplayer.is_server():
		return
	_server_cheat_starter_town(multiplayer.get_remote_sender_id())

func _server_cheat_starter_town(id: int) -> void:
	if not players.has(id):
		return
	if not cheats_allowed():
		_trade_reply(id, "Cheats are off on this server.", false)
		return
	var pawn := _pawn(id)
	if pawn == null or pawn.dead:
		_trade_reply(id, "Not while you are down.", false)
		return
	if Tutorial.server_running(id):
		Tutorial.server_end(id, true) # graduating already places you on the island
	else:
		server_place_on_island(id)
	_trade_reply(id, "Off to the starter town.", true)

## Client -> server: put my pawn at a named place. Editor builds only.
## Cheat: put yourself on a quest (or "" to drop the one you have), skipping the
## NPC who normally hands it out. Editor-only at the server end like every cheat.
func request_cheat_quest(quest_id: String) -> void:
	if multiplayer.is_server():
		_server_cheat_quest(multiplayer.get_unique_id(), quest_id)
	else:
		rpc_id(1, "sv_cheat_quest", quest_id)

@rpc("any_peer", "call_remote", "reliable")
func sv_cheat_quest(quest_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_cheat_quest(multiplayer.get_remote_sender_id(), quest_id)

func _server_cheat_quest(id: int, quest_id: String) -> void:
	if not players.has(id):
		return
	if not cheats_allowed():
		_trade_reply(id, "Cheats are off on this server.", false)
		return
	if quest_id != "" and not QuestData.has(quest_id):
		_trade_reply(id, "No such quest.", false)
		return
	_set_quest(id, quest_id)
	if quest_id == "":
		_trade_reply(id, "Quest cleared.", true)
	else:
		_trade_reply(id, "Tracking %s." % QuestData.label(quest_id), true)

func request_cheat_teleport(dest_id: String) -> void:
	if multiplayer.is_server():
		_server_cheat_teleport(multiplayer.get_unique_id(), dest_id)
	else:
		rpc_id(1, "sv_cheat_teleport", dest_id)

@rpc("any_peer", "call_remote", "reliable")
func sv_cheat_teleport(dest_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_cheat_teleport(multiplayer.get_remote_sender_id(), dest_id)

## The server moves its OWN copy of the pawn and then tells the owner where it
## now is. Doing it the other way round would be a client teleport, which the
## position validator exists to reject.
func _server_cheat_teleport(id: int, dest_id: String) -> void:
	if not players.has(id):
		return
	if not cheats_allowed():
		_trade_reply(id, "Cheats are off on this server.", false)
		return
	if not TeleportData.has(dest_id):
		_trade_reply(id, "No such place.", false)
		return
	var anchor := TeleportData.anchor(get_tree(), dest_id)
	if anchor == null:
		_trade_reply(id, "%s has no anchor in this level yet." % TeleportData.label(dest_id), false)
		return
	var pawn := _pawn(id)
	if pawn == null or pawn.dead:
		_trade_reply(id, "Not while you are down.", false)
		return
	var pos: Vector3 = anchor.global_position
	pawn.net_teleport(pos)
	if id != 1:
		rpc_id(id, "cl_force_position", pos)
	_trade_reply(id, "Teleported to %s." % TeleportData.label(dest_id), true)

# ---------------- hotbar (server-owned) ----------------
#
# The bar is part of the registry, not a client-side view of it: what you are
# holding decides what "use" does, so a client only ever ASKS to move the
# selection or to put an item in a slot. Picking anything up drops it onto the
# first free slot, and an item that leaves the bag leaves the bar with it.

## Put NEWLY carried items on the first free slot, and take gone ones off.
## Called after every change to a bag, so something just picked up is in hand
## without a trip to the inventory screen. Only the first copy of an item does
## this, and only once: "seen" remembers what has already been offered a slot,
## so clearing a slot by hand stays cleared instead of filling itself back in
## the next time anything at all changes. A full bar keeps what it has, and
## dropping an item entirely forgets it — buy it again and it comes back.
func _refill_hotbar(entry: Dictionary) -> void:
	var bar: Array = entry["hotbar"]
	var items: Dictionary = entry["items"]
	var seen: Dictionary = entry["seen"]
	# an item that is gone from the bag can't stay in a slot, or be remembered
	for i in bar.size():
		if bar[i] != "" and int(items.get(bar[i], 0)) <= 0:
			bar[i] = ""
	for known: String in seen.keys():
		if int(items.get(known, 0)) <= 0:
			seen.erase(known)
	for item_id: String in items:
		if seen.has(item_id):
			continue
		seen[item_id] = true
		if bar.has(item_id):
			continue
		var free := bar.find("")
		if free < 0:
			continue # bar is full — this one waits in the bag
		bar[free] = item_id

## Anything that adds to or takes from a bag ends here: the bar is brought back
## in line with what is actually carried, then the owner is re-synced.
func _bag_changed(id: int) -> void:
	if players.has(id):
		_refill_hotbar(players[id])
	_hotbar_changed(id)

## The bar moved: the owner gets the new bar privately, and everyone gets the
## public registry again — it carries "held", which is what other players draw
## in this one's hand.
func _hotbar_changed(id: int) -> void:
	_send_purse(id)
	_sync_players()

## Client -> server: I'm holding this slot now (R1/L1, or a click in the panel).
func request_hotbar_select(slot: int) -> void:
	if multiplayer.is_server():
		_server_hotbar_select(multiplayer.get_unique_id(), slot)
	else:
		rpc_id(1, "sv_hotbar_select", slot)

@rpc("any_peer", "call_remote", "reliable")
func sv_hotbar_select(slot: int) -> void:
	if not multiplayer.is_server():
		return
	_server_hotbar_select(multiplayer.get_remote_sender_id(), slot)

func _server_hotbar_select(id: int, slot: int) -> void:
	if not players.has(id) or slot < 0 or slot >= HOTBAR_SLOTS:
		return
	players[id]["hot_slot"] = slot
	_hotbar_changed(id)

## Client -> server: put this carried item in this slot (empty id clears it).
func request_hotbar_assign(slot: int, item_id: String) -> void:
	if multiplayer.is_server():
		_server_hotbar_assign(multiplayer.get_unique_id(), slot, item_id)
	else:
		rpc_id(1, "sv_hotbar_assign", slot, item_id)

@rpc("any_peer", "call_remote", "reliable")
func sv_hotbar_assign(slot: int, item_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_hotbar_assign(multiplayer.get_remote_sender_id(), slot, item_id)

func _server_hotbar_assign(id: int, slot: int, item_id: String) -> void:
	if not players.has(id) or slot < 0 or slot >= HOTBAR_SLOTS:
		return
	var entry: Dictionary = players[id]
	var bar: Array = entry["hotbar"]
	if item_id == "":
		bar[slot] = ""
		_hotbar_changed(id)
		return
	# you can only put something on the bar that you are actually carrying
	if int(entry["items"].get(item_id, 0)) <= 0:
		_trade_reply(id, "You aren't carrying that.", false)
		_send_purse(id)
		return
	var already: int = bar.find(item_id)
	if already >= 0:
		bar[already] = bar[slot] # swap, so a drag never duplicates an entry
	bar[slot] = item_id
	entry["hot_slot"] = slot
	_hotbar_changed(id)

## Client -> server: use whatever is in the slot I'm holding.
func request_use_item() -> void:
	if multiplayer.is_server():
		_server_use_item(multiplayer.get_unique_id())
	else:
		rpc_id(1, "sv_use_item")

@rpc("any_peer", "call_remote", "reliable")
func sv_use_item() -> void:
	if not multiplayer.is_server():
		return
	_server_use_item(multiplayer.get_remote_sender_id())

## The server decides what using an item does — never the client. Right now no
## item in the catalogue has an effect, so this only validates; give an item
## one by branching on item_id here (consume a stack, heal, equip...), and
## remember to _bag_changed(id) if the bag changed.
##
## Replies carry an EMPTY message on purpose: `use_item` shares R2 with
## `attack`, so this runs on every swing, and a line on screen each time would
## be noise. Fill the message in when a use actually does something.
func _server_use_item(id: int) -> void:
	if not players.has(id):
		return
	var pawn := _pawn(id)
	if pawn == null or pawn.dead:
		return
	var entry: Dictionary = players[id]
	var slot := int(entry.get("hot_slot", 0))
	var bar: Array = entry["hotbar"]
	if slot < 0 or slot >= bar.size():
		return
	var item_id: String = bar[slot]
	if item_id == "" or int(entry["items"].get(item_id, 0)) <= 0:
		_use_reply(id, "", "")
		return
	_use_reply(id, item_id, "")

func _use_reply(id: int, item_id: String, message: String) -> void:
	if id == multiplayer.get_unique_id():
		cl_item_used(item_id, message)
	else:
		rpc_id(id, "cl_item_used", item_id, message)

@rpc("authority", "call_remote", "reliable")
func cl_item_used(item_id: String, message: String) -> void:
	item_used.emit(item_id, message)

## Is this player actually standing at that NPC? The server owns every pawn's
## position (speed-validated in sv_player_state), so this can't be spoofed. Used
## by both the shop counter and the quest giver — a conversation is local, so
## being in reach of the NPC is the only part of it the server can verify.
func _near_npc(id: int, dialog_id: String) -> bool:
	var pawn := _pawn(id)
	if pawn == null:
		return false
	for npc in get_tree().get_nodes_in_group("npc_interactable"):
		if not is_instance_valid(npc) or npc.dialog_id != dialog_id:
			continue
		var reach: float = float(npc.interact_range) + SHOP_RANGE_SLACK
		if pawn.global_position.distance_to(npc.global_position) <= reach:
			return true
	return false

func _trade_reply(id: int, message: String, ok: bool) -> void:
	if id == multiplayer.get_unique_id():
		cl_trade_result(message, ok)
	else:
		rpc_id(id, "cl_trade_result", message, ok)

@rpc("authority", "call_remote", "reliable")
func cl_trade_result(message: String, ok: bool) -> void:
	trade_result.emit(message, ok)

## Server -> one owner: here is your authoritative gold and bag. This is the
## ONLY thing that writes the GameStats mirror.
func _send_purse(id: int) -> void:
	var entry: Dictionary = players.get(id, {})
	var gold := int(entry.get("gold", 0))
	var items: Dictionary = entry.get("items", {})
	var bar: Array = entry.get("hotbar", _empty_hotbar())
	var slot := int(entry.get("hot_slot", 0))
	var quest := str(entry.get("quest", ""))
	var quest_kills := int(entry.get("quest_kills", 0))
	var gifts: Dictionary = entry.get("gifts", {})
	if id == multiplayer.get_unique_id():
		cl_purse(gold, items, bar, slot, quest, quest_kills, gifts)
	else:
		rpc_id(id, "cl_purse", gold, items, bar, slot, quest, quest_kills, gifts)

@rpc("authority", "call_remote", "reliable")
func cl_purse(gold: int, items: Dictionary, hotbar: Array, hot_slot: int,
		quest: String, quest_kills := 0, gifts := {}) -> void:
	GameStats.coins = gold
	GameStats.items = items.duplicate(true) # never alias the server's dictionary
	GameStats.hotbar = hotbar.duplicate()
	GameStats.hot_slot = hot_slot
	GameStats.quest = quest
	GameStats.quest_kills = quest_kills
	GameStats.gifts = gifts.duplicate()
	GameStats.changed.emit()

# ---------------- state replication ----------------

func _physics_process(delta: float) -> void:
	if not active or not multiplayer.is_server():
		return
	var pn := _players_node()
	if pn == null:
		return
	_player_bcast_accum += delta
	if _player_bcast_accum >= PLAYER_STATE_INTERVAL:
		_player_bcast_accum = 0.0
		_broadcast_player_states(pn)
	_enemy_bcast_accum += delta
	if _enemy_bcast_accum >= ENEMY_STATE_INTERVAL:
		_enemy_bcast_accum = 0.0
		_broadcast_enemy_states()
	_vitals_accum += delta
	if _vitals_accum >= VITALS_INTERVAL:
		_vitals_accum = 0.0
		_send_vitals(pn)
	_gold_accum += delta
	if _gold_accum >= GOLD_PICKUP_INTERVAL:
		_gold_accum = 0.0
		_check_gold_pickups(pn)
	_check_fell_off_world(pn)

func _broadcast_player_states(pn: Node) -> void:
	var batch := []
	for pawn in pn.get_children():
		batch.append(pawn.net_collect_state())
	if not batch.is_empty():
		rpc("cl_player_states", batch)

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_player_states(batch: Array) -> void:
	for row in batch:
		var pawn := _pawn(int(row[0]))
		if pawn and not pawn.is_local:
			pawn.net_apply_state(row[1], row[2], row[3], row[4], row[5], row[6],
					bool(row[7]) if row.size() > 7 else false)

## Client owner -> server: position + cosmetic state claim, ~20 Hz.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func sv_player_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, blocking: bool, sprinting := false) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var pawn := _pawn(id)
	if pawn == null or pawn.is_local:
		return
	if not pawn.net_report_state(pos, yaw, anim, anim_t, ratio, blocking, sprinting):
		# rejected (teleport / speedhack): snap the client back
		rpc_id(id, "cl_force_position", pawn.net_pos)

@rpc("authority", "call_remote", "reliable")
func cl_force_position(pos: Vector3) -> void:
	var pawn := _pawn(multiplayer.get_unique_id())
	if pawn:
		pawn.global_position = pos
		pawn.velocity = Vector3.ZERO

func send_player_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, blocking: bool, sprinting := false) -> void:
	if active and not multiplayer.is_server():
		rpc_id(1, "sv_player_state", pos, yaw, anim, anim_t, ratio, blocking, sprinting)

func _send_vitals(pn: Node) -> void:
	var connected := multiplayer.get_peers()
	for pawn in pn.get_children():
		if pawn.peer_id != 1 and connected.has(pawn.peer_id):
			rpc_id(pawn.peer_id, "cl_vitals", pawn.stamina, pawn.health)

@rpc("authority", "call_remote", "unreliable")
func cl_vitals(server_stamina: float, server_health: float) -> void:
	var pawn := _pawn(multiplayer.get_unique_id())
	if pawn:
		pawn.stamina = server_stamina
		pawn.health = server_health

func _check_fell_off_world(pn: Node) -> void:
	for pawn in pn.get_children():
		if not pawn.dead and pawn.global_position.y < KILL_Y:
			pawn.server_kill(0)
	var en := _enemies_node()
	if en:
		for e in en.get_children():
			if not e.dead and e.global_position.y < KILL_Y:
				e.take_damage(1e9, Vector3.ZERO, 0)

# ---------------- voice chat ----------------

## Owner -> server: a mouthful of speech (see VoiceCodec for the format).
##
## Unreliable on purpose. A packet is 50 ms of audio and stands alone, so a lost
## one is a hole nobody can hear over the next word; sending voice reliably would
## trade that for a stall on every retransmit, and speech that arrives late is
## worse than speech that arrives with a gap in it.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func sv_voice(packet: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	_relay_voice(multiplayer.get_remote_sender_id(), packet)

## Server -> the peers standing close enough. `from_id` comes from the SERVER's
## own view of who sent it, never from inside the packet, so a client cannot put
## words in somebody else's mouth.
@rpc("authority", "call_remote", "unreliable_ordered")
func cl_voice(from_id: int, packet: PackedByteArray) -> void:
	Voice.on_voice(from_id, packet)

## Called by Voice on the talker's machine. A listen server is its own relay, so
## it goes through exactly the same routing rather than a shortcut of its own.
func send_voice(packet: PackedByteArray) -> void:
	if not active:
		return
	if multiplayer.is_server():
		_relay_voice(multiplayer.get_unique_id(), packet)
	else:
		rpc_id(1, "sv_voice", packet)

func _relay_voice(from_id: int, packet: PackedByteArray) -> void:
	if not voice_accepts(from_id, packet):
		return
	for peer: int in voice_targets(from_id):
		if peer == multiplayer.get_unique_id():
			Voice.on_voice(from_id, packet) # the host hears it in-process
		else:
			rpc_id(peer, "cl_voice", from_id, packet)

## SERVER: is this packet one the relay will carry at all? Size, and then a
## budget per talker per second (VoiceCodec.MAX_BYTES_PER_SECOND).
##
## Voice itself cannot be validated — there is no way to tell speech from noise,
## and it does not matter, because nothing in the game changes when somebody
## talks. What CAN be abused is the relay: one patched client sending at ten
## times the rate would cost the server bandwidth for every listener near it.
## Overspend counts even though it is dropped, so a flooder stays cut off for the
## rest of its second instead of getting a free packet whenever the window turns.
func voice_accepts(from_id: int, packet: PackedByteArray) -> bool:
	if not multiplayer.is_server():
		return false
	var n := packet.size()
	if n == 0 or n > VoiceCodec.MAX_PACKET:
		return false
	var now := Time.get_ticks_msec()
	var row: Array = _voice_spend.get(from_id, [now, 0])
	if now - int(row[0]) >= 1000:
		row = [now, 0]
	var spent := int(row[1]) + n
	_voice_spend[from_id] = [row[0], spent]
	return spent <= VoiceCodec.MAX_BYTES_PER_SECOND

## SERVER: who is near enough to hear peer `from_id` right now.
##
## Read off the server's own copy of every pawn (server_body_pos — the last
## position it ACCEPTED, already speed-validated), never off anything a client
## claims: who can hear you is not the speaker's decision to make, and a client
## that could name its own audience could listen to a conversation across the
## island. Players inside the tutorial need no special case — their copy of the
## city is kilometres away, so the distance rules them out by itself.
func voice_targets(from_id: int) -> Array[int]:
	var out: Array[int] = []
	if not multiplayer.is_server():
		return out
	var speaker := _pawn(from_id)
	if speaker == null:
		return out
	var origin: Vector3 = speaker.server_body_pos()
	var reach := VOICE_RANGE * VOICE_RANGE
	for id: int in players:
		if id == from_id:
			continue # you never hear yourself
		var pawn := _pawn(id)
		if pawn == null:
			continue
		if origin.distance_squared_to(pawn.server_body_pos()) <= reach:
			out.append(id)
	return out

# ---------------- combat protocol ----------------

## Client owner -> server: "I pressed attack" (+ claimed lock-on target, which
## the server re-validates by range, and the yaw the swing was thrown along).
##
## The aim rides WITH the swing rather than being read off the last state report
## when it lands: the two are sent in the same frame and the report can arrive
## second, which aimed the trace along wherever the body had been pointing. It is
## no more trusted than before — the reported body yaw was already the client's
## word, and the trace still runs off the server's own positions and reach.
@rpc("any_peer", "call_remote", "reliable")
func sv_request_attack(heavy: bool, lock_path: NodePath, aim_yaw: float) -> void:
	if not multiplayer.is_server():
		return
	var pawn := _pawn(multiplayer.get_remote_sender_id())
	if pawn and not pawn.is_local:
		pawn.server_handle_attack_request(heavy, lock_path, aim_yaw)

func request_attack(heavy: bool, lock_path: NodePath, aim_yaw: float) -> void:
	rpc_id(1, "sv_request_attack", heavy, lock_path, aim_yaw)

## Server: tell everyone (but the swinging owner predicted it already).
func server_broadcast_swing(id: int, heavy: bool, section: int) -> void:
	rpc("cl_play_swing", id, heavy, section)

@rpc("authority", "call_remote", "reliable")
func cl_play_swing(id: int, heavy: bool, section: int) -> void:
	var pawn := _pawn(id)
	if pawn and not pawn.is_local:
		pawn.puppet_play_swing(heavy, section)

## `result` is a Player.Guard value (hit / blocked / parried / guard broken);
## stamina rides along because the guard meter is server-owned.
func server_broadcast_player_damage(id: int, health: float, result: int,
		knockback: Vector3, stamina: float, attacker: int) -> void:
	rpc("cl_player_damaged", id, health, result, knockback, stamina, attacker)
	var pawn := _pawn(id)  # host applies its own fx locally too
	if pawn:
		pawn.net_apply_damage(health, result, knockback, stamina, attacker)

@rpc("authority", "call_remote", "reliable")
func cl_player_damaged(id: int, health: float, result: int, knockback: Vector3,
		stamina: float, attacker: int) -> void:
	var pawn := _pawn(id)
	if pawn:
		pawn.net_apply_damage(health, result, knockback, stamina, attacker)

## Parried or guard-broken: everyone plays the helpless pose for the same beat.
func server_broadcast_player_stagger(id: int, duration: float) -> void:
	rpc("cl_player_staggered", id, duration)
	var pawn := _pawn(id)
	if pawn:
		pawn.net_stagger(duration)

@rpc("authority", "call_remote", "reliable")
func cl_player_staggered(id: int, duration: float) -> void:
	var pawn := _pawn(id)
	if pawn:
		pawn.net_stagger(duration)

func server_record_player_death(victim: int, attacker: int) -> void:
	var victim_name: String = players[victim]["name"] if players.has(victim) else str(victim)
	if attacker > 0 and players.has(attacker):
		print("[Net] %s killed %s" % [players[attacker]["name"], victim_name])
	else:
		print("[Net] %s died" % victim_name)
	if players.has(victim):
		players[victim]["deaths"] += 1
	if attacker > 0 and attacker != victim and players.has(attacker):
		players[attacker]["kills"] += 1
	_sync_players()
	rpc("cl_player_died", victim)
	var pawn := _pawn(victim)
	if pawn:
		pawn.net_die()

@rpc("authority", "call_remote", "reliable")
func cl_player_died(id: int) -> void:
	var pawn := _pawn(id)
	if pawn:
		pawn.net_die()

func server_respawn_player(id: int) -> void:
	var pn := _players_node()
	if pn == null:
		return
	# dying in the tutorial puts you back in the tutorial: the island is
	# somewhere you have not earned yet
	var pos := Tutorial.server_respawn_position(id)
	if pos == Vector3.INF:
		pos = spawn_position(randi() % 8)
	rpc("cl_player_respawn", id, pos)
	var pawn := _pawn(id)
	if pawn:
		pawn.net_respawn(pos)

@rpc("authority", "call_remote", "reliable")
func cl_player_respawn(id: int, pos: Vector3) -> void:
	var pawn := _pawn(id)
	if pawn:
		pawn.net_respawn(pos)

# ---------------- enemies ----------------

func next_enemy_name() -> String:
	_enemy_counter += 1
	return "Bandit_%d" % _enemy_counter

func server_broadcast_enemy_spawn(enemy: Node3D) -> void:
	rpc("cl_spawn_enemy", String(enemy.name), enemy.global_position)

@rpc("authority", "call_remote", "reliable")
func cl_spawn_enemy(enemy_name: String, pos: Vector3) -> void:
	var en := _enemies_node()
	if en == null or en.has_node(enemy_name):
		return
	var e := ENEMY_SCENE.instantiate()
	e.name = enemy_name
	en.add_child(e)
	e.global_position = pos
	e.net_pos = pos

func _broadcast_enemy_states() -> void:
	var en := _enemies_node()
	if en == null:
		return
	var batch := []
	var private := {} # peer -> its own tutorial bandits, which only it can see
	for e in en.get_children():
		if e.dead:
			continue
		var audience := int(e.owner_peer)
		if audience == 0:
			batch.append(e.net_visual_state())
		else:
			if not private.has(audience):
				private[audience] = []
			private[audience].append(e.net_visual_state())
	if not batch.is_empty():
		rpc("cl_enemy_states", batch)
	for peer: int in private:
		if peer != 1:
			rpc_id(peer, "cl_enemy_states", private[peer])

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_enemy_states(batch: Array) -> void:
	var en := _enemies_node()
	if en == null:
		return
	for row in batch:
		var e := en.get_node_or_null(String(row[0]))
		if e:
			e.net_apply_state(row[1], row[2], row[3], row[4], row[5], row[6], row[7],
					row[8], row[9], row[10])

## The host already ran its own fx inside take_damage — clients only.
func server_broadcast_enemy_damage(enemy_name: String, health: float,
		result: int, attacker: int) -> void:
	rpc("cl_enemy_damaged", enemy_name, health, result, attacker)

@rpc("authority", "call_remote", "reliable")
func cl_enemy_damaged(enemy_name: String, health: float, result: int,
		attacker: int) -> void:
	var e := _enemy(enemy_name)
	if e:
		e.net_apply_damage(health, result, attacker)

func server_broadcast_enemy_stagger(enemy_name: String, duration: float) -> void:
	rpc("cl_enemy_staggered", enemy_name, duration)
	var e := _enemy(enemy_name)  # host plays the pose locally too
	if e:
		e.net_stagger(duration)

@rpc("authority", "call_remote", "reliable")
func cl_enemy_staggered(enemy_name: String, duration: float) -> void:
	var e := _enemy(enemy_name)
	if e:
		e.net_stagger(duration)

func server_record_enemy_kill(enemy_name: String, attacker: int) -> void:
	if attacker > 0 and players.has(attacker):
		print("[Net] %s slew %s" % [players[attacker]["name"], enemy_name])
		players[attacker]["kills"] += 1
		_sync_players()
		_credit_quest_kill(attacker)
	rpc("cl_enemy_died", enemy_name)

@rpc("authority", "call_remote", "reliable")
func cl_enemy_died(enemy_name: String) -> void:
	var en := _enemies_node()
	if en == null:
		return
	var e := en.get_node_or_null(enemy_name)
	if e:
		e.net_die()

func server_remove_enemy(enemy_name: String) -> void:
	rpc("cl_remove_enemy", enemy_name)

# ---------------- tutorial ----------------
#
# The tutorial gives each player a private copy of a city (see
# scripts/world/tutorial/). The rules are the usual ones: the SERVER owns the
# copy, its bandits and which step you are on; the client owns nothing but the
# screen. What is different is the audience — a tutorial bandit is spawned and
# updated only for the one player it belongs to, because it is not in anyone
# else's world.

## SERVER: spawn one bandit into `id`'s copy of the city and tell only them.
func server_spawn_tutorial_bandit(id: int, pos: Vector3,
		hold: Enemy.Hold = Enemy.Hold.NONE) -> Node:
	if not multiplayer.is_server():
		return null
	var en := _enemies_node()
	if en == null:
		return null
	var bandit := ENEMY_SCENE.instantiate()
	bandit.name = next_enemy_name()
	bandit.owner_peer = id
	en.add_child(bandit)
	bandit.global_position = pos
	bandit.set_hold(hold)
	# a lesson should cost less than the real thing when you get it wrong
	bandit.attack_damage *= TutorialData.DAMAGE_MULT
	# these are raiders in the middle of a raid, not sentries waiting to notice
	# you: point them at the player and wake them up, or one that happens to
	# land facing the other way stands there until it is punched
	var target := _pawn(id)
	if target:
		bandit.face_toward(target.global_position)
		bandit.aggroed = true
	if id != 1:
		rpc_id(id, "cl_spawn_enemy", String(bandit.name), pos)
	return bandit

## SERVER: take a bandit out of the world entirely (the copy is being torn
## down), as opposed to killing it.
func server_despawn_enemy(enemy: Node) -> void:
	if not multiplayer.is_server() or not is_instance_valid(enemy):
		return
	var enemy_name := String(enemy.name)
	var audience := int(enemy.get("owner_peer"))
	if audience > 1:
		rpc_id(audience, "cl_remove_enemy", enemy_name)
	elif audience == 0:
		rpc("cl_remove_enemy", enemy_name)
	enemy.queue_free()

## SERVER: out of the tutorial and onto the island, wherever that is today.
func server_place_on_island(id: int) -> void:
	var pawn := _pawn(id)
	if pawn == null:
		return
	var pos := spawn_position(0)
	pawn.net_teleport(pos)
	if id != 1:
		rpc_id(id, "cl_force_position", pos)

## SERVER -> one client: build your copy of the city / step / tear it down.
## The host is both ends at once, so it calls its own client half directly —
## `call_remote` RPCs never come back round to the peer that sent them.
func tutorial_enter(id: int, slot: int) -> void:
	if id == 1:
		Tutorial.client_enter(slot)
	else:
		rpc_id(id, "cl_tutorial_enter", slot)

func tutorial_step(id: int, step_id: String) -> void:
	if id == 1:
		Tutorial.client_step(step_id)
	else:
		rpc_id(id, "cl_tutorial_step", step_id)

func tutorial_leave(id: int) -> void:
	if id == 1:
		Tutorial.client_leave()
	else:
		rpc_id(id, "cl_tutorial_leave")

@rpc("authority", "call_remote", "reliable")
func cl_tutorial_enter(slot: int) -> void:
	Tutorial.client_enter(slot)

@rpc("authority", "call_remote", "reliable")
func cl_tutorial_step(step_id: String) -> void:
	Tutorial.client_step(step_id)

@rpc("authority", "call_remote", "reliable")
func cl_tutorial_leave() -> void:
	Tutorial.client_leave()

## CLIENT -> server: I am standing in the world, the lesson can start.
func report_tutorial_ready() -> void:
	if not active:
		return
	if multiplayer.is_server():
		Tutorial.server_report_ready(multiplayer.get_unique_id())
	else:
		rpc_id(1, "sv_tutorial_ready")

@rpc("any_peer", "call_remote", "reliable")
func sv_tutorial_ready() -> void:
	if multiplayer.is_server():
		Tutorial.server_report_ready(multiplayer.get_remote_sender_id())

## CLIENT -> server: I did the thing this step asked for. Only the steps the
## server cannot watch for itself are taken on trust (see TutorialData), and
## the most a patched client wins by lying is skipping its own lesson.
func report_tutorial_pressed(step_id: String) -> void:
	if not active:
		return
	if multiplayer.is_server():
		Tutorial.server_report_pressed(multiplayer.get_unique_id(), step_id)
	else:
		rpc_id(1, "sv_tutorial_pressed", step_id)

@rpc("any_peer", "call_remote", "reliable")
func sv_tutorial_pressed(step_id: String) -> void:
	if multiplayer.is_server():
		Tutorial.server_report_pressed(multiplayer.get_remote_sender_id(), step_id)

# ---------------- gold drops ----------------
# The pile itself is cosmetic on every peer; the server owns who gets paid.

## SERVER: drop a pile of gold into the world (called by dying enemies).
func server_spawn_gold(pos: Vector3, amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0:
		return
	_gold_counter += 1
	var drop_name := "Gold_%d" % _gold_counter
	rpc("cl_spawn_gold", drop_name, pos, amount)
	_do_spawn_gold(drop_name, pos, amount)
	get_tree().create_timer(GOLD_DESPAWN_SECONDS).timeout.connect(func() -> void:
		var dn := _drops_node()
		var d: Node = dn.get_node_or_null(drop_name) if dn else null
		if d: # never claimed — quietly rot away
			rpc("cl_remove_gold", drop_name)
			d.queue_free())

@rpc("authority", "call_remote", "reliable")
func cl_spawn_gold(drop_name: String, pos: Vector3, amount: int) -> void:
	_do_spawn_gold(drop_name, pos, amount)

func _do_spawn_gold(drop_name: String, pos: Vector3, amount: int) -> void:
	var dn := _drops_node(true)
	if dn == null or dn.has_node(drop_name):
		return
	var drop: Node3D = GOLD_DROP_SCRIPT.new()
	drop.name = drop_name
	drop.amount = amount
	dn.add_child(drop)
	drop.global_position = pos

@rpc("authority", "call_remote", "reliable")
func cl_remove_gold(drop_name: String) -> void:
	var dn := _drops_node()
	if dn == null:
		return
	var d := dn.get_node_or_null(drop_name)
	if d:
		d.queue_free()

## SERVER: award piles to the first living player standing on them.
func _check_gold_pickups(pn: Node) -> void:
	var dn := _drops_node()
	if dn == null:
		return
	for d in dn.get_children():
		var dpos: Vector3 = d.global_position
		for pawn in pn.get_children():
			if pawn.dead or not players.has(pawn.peer_id):
				continue
			var ppos: Vector3 = pawn.server_body_pos()
			if Vector2(ppos.x - dpos.x, ppos.z - dpos.z).length() <= GOLD_PICKUP_RANGE \
					and absf(ppos.y - dpos.y) < 2.0:
				_server_award_gold(pawn.peer_id, d)
				break

func _server_award_gold(id: int, drop: Node) -> void:
	players[id]["gold"] = int(players[id].get("gold", 0)) + drop.amount
	print("[Net] %s picked up %d gold" % [players[id]["name"], drop.amount])
	_sync_players()
	_send_purse(id) # gold is private now, so the broadcast no longer carries it
	rpc("cl_gold_picked", String(drop.name), drop.amount, drop.global_position)
	_do_gold_picked(String(drop.name), drop.amount, drop.global_position)

@rpc("authority", "call_remote", "reliable")
func cl_gold_picked(drop_name: String, amount: int, pos: Vector3) -> void:
	_do_gold_picked(drop_name, amount, pos)

func _do_gold_picked(drop_name: String, amount: int, pos: Vector3) -> void:
	var w := _world()
	if w == null:
		return
	GOLD_DROP_SCRIPT.spawn_pickup_text(w, pos, amount)
	var dn := _drops_node()
	if dn:
		var d := dn.get_node_or_null(drop_name)
		if d:
			d.queue_free()

@rpc("authority", "call_remote", "reliable")
func cl_remove_enemy(enemy_name: String) -> void:
	var en := _enemies_node()
	if en == null:
		return
	var e := en.get_node_or_null(enemy_name)
	if e:
		e.queue_free()

# ---------------- UPnP (no manual port forwarding) ----------------

func _start_upnp(port: int) -> void:
	if not ClassDB.class_exists("UPNP"):
		upnp_status = "failed"
		return
	if _upnp_thread and _upnp_thread.is_started():
		if _upnp_thread.is_alive():
			return # previous attempt still running
		_upnp_thread.wait_to_finish()
	upnp_status = "searching"
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker.bind(port))

## 24h lease: if the server is force-killed and never cleans up, the router
## drops the mapping on its own. Some routers reject leases -> permanent
## fallback, which the explicit cleanup below then handles on normal exits.
const UPNP_LEASE := 86400

func _upnp_worker(port: int) -> void:
	var upnp := UPNP.new()
	var result := upnp.discover()
	if result != UPNP.UPNP_RESULT_SUCCESS or upnp.get_device_count() == 0 \
			or upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		call_deferred("_upnp_done", "failed", "")
		return
	var udp := upnp.add_port_mapping(port, port, "Astria", "UDP", UPNP_LEASE)
	if udp != UPNP.UPNP_RESULT_SUCCESS:
		udp = upnp.add_port_mapping(port, port, "Astria", "UDP", 0)
	if upnp.add_port_mapping(port, port, "Astria", "TCP", UPNP_LEASE) != UPNP.UPNP_RESULT_SUCCESS:
		upnp.add_port_mapping(port, port, "Astria", "TCP", 0)
	var ip := upnp.query_external_address()
	if udp == UPNP.UPNP_RESULT_SUCCESS and not ip.is_empty():
		# set from the worker thread so a quit right after hosting can still
		# clean up after wait_to_finish (the deferred call may never run)
		_upnp_mapper = upnp
		_mapped_port = port
		call_deferred("_upnp_done", "ok", ip)
	else:
		call_deferred("_upnp_done", "failed", ip)

## Remove the router mapping (async normally; blocking when quitting).
func _remove_upnp_mapping(blocking: bool) -> void:
	if _mapped_port == 0 or _upnp_mapper == null:
		return
	var mapper = _upnp_mapper
	var port := _mapped_port
	_upnp_mapper = null
	_mapped_port = 0
	if blocking:
		mapper.delete_port_mapping(port, "UDP")
		mapper.delete_port_mapping(port, "TCP")
		print("[Net] UPnP mapping for port %d removed" % port)
		return
	if _upnp_cleanup_thread and _upnp_cleanup_thread.is_started():
		_upnp_cleanup_thread.wait_to_finish()
	_upnp_cleanup_thread = Thread.new()
	_upnp_cleanup_thread.start(func() -> void:
		mapper.delete_port_mapping(port, "UDP")
		mapper.delete_port_mapping(port, "TCP")
		print("[Net] UPnP mapping for port %d removed" % port))

func _upnp_done(status: String, ip: String) -> void:
	upnp_status = status
	public_ip = ip
	if status == "ok":
		print("[Net] UPnP OK — friends can join at %s (port %d)" % [ip, host_port])
	else:
		print("[Net] UPnP unavailable — LAN joins still work; internet play needs a manual port forward of UDP %d" % host_port)

# ---------------- helpers ----------------

func spawn_position(i: int) -> Vector3:
	var markers := get_tree().get_nodes_in_group("spawn_point")
	var base := Vector3(241.0, 95.0, -204.0)
	if markers.size() > 0:
		base = (markers[0] as Node3D).global_position
	if i <= 0:
		return base
	var a := float(i) * 2.3999632
	return base + Vector3(cos(a), 0, sin(a)) * 1.6

func _world() -> Node:
	return get_tree().current_scene

func _players_node() -> Node:
	var w := _world()
	return w.get_node_or_null("Players") if w else null

func _enemies_node() -> Node:
	var w := _world()
	return w.get_node_or_null("Enemies") if w else null

## Runtime-only container for gold piles (created on demand on each peer).
func _drops_node(create := false) -> Node:
	var w := _world()
	if w == null:
		return null
	var dn := w.get_node_or_null("Drops")
	if dn == null and create:
		dn = Node3D.new()
		dn.name = "Drops"
		w.add_child(dn)
	return dn

func _pawn(id: int) -> Node:
	var pn := _players_node()
	return pn.get_node_or_null(str(id)) if pn else null

func _enemy(enemy_name: String) -> Node:
	var en := _enemies_node()
	return en.get_node_or_null(enemy_name) if en else null
