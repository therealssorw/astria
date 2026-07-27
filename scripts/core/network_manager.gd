extends Node
## Autoload "Net": the multiplayer WIRE — hosting/joining (ENet), the
## server-authoritative player registry and the whole RPC protocol. The server
## never trusts clients: it validates movement, simulates all combat itself and
## is the only writer of health and stats; everything a client sends is treated
## as a request or a cosmetic claim.
##
## What is NOT here, and why: an `@rpc` method has to live on a node both peers
## can name, which is this autoload — so the protocol stays. Everything that is
## only RULES moved into `scripts/core/net/`, where it can be read and tested
## without a wire underneath it:
##   NetRegistry — what a player entry IS: bag, purse, hotbar, equipment
##   NetWorld    — where things are: the containers, a pawn, a spawn
##   NetVoice    — who may be heard, and how loudly anyone may talk
##   NetUpnp     — asking the router for a port
##
## THERE IS ONE CLIENT->SERVER REQUEST RPC, not one per feature. `SERVER_REQUESTS`
## is the allowlist of what a client may ask for; `_ask` sends and `sv_request`
## receives, so "the client asks and the server checks" is written once. Adding a
## request is a row in that table plus its `_server_*` handler — never another
## copy of the three-function dance this file used to repeat thirteen times.

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

## Re-exported so callers keep saying `Net.HOTBAR_SLOTS` / `Net.VOICE_RANGE`
## rather than having to know which module now owns the number.
const HOTBAR_SLOTS := NetRegistry.HOTBAR_SLOTS
const VOICE_RANGE := NetVoice.RANGE

## Everything a client is allowed to ask the server for: request name -> the
## server-side handler, which is always called as `handler(peer_id, ...args)`.
## A name that is not in here is silently ignored, so the RPC cannot be used to
## reach any other method on this node.
##
## Anything starting "cheat_" additionally needs `cheats_allowed()`, which is
## checked once in `_serve` rather than at the top of five near-identical
## handlers.
const SERVER_REQUESTS := {
	"start_quest": "_server_start_quest",
	"finish_quest": "_server_finish_quest",
	"gift": "_server_take_gift",
	"trade": "_server_trade",
	"hotbar_select": "_server_hotbar_select",
	"hotbar_assign": "_server_hotbar_assign",
	"use_item": "_server_use_item",
	"use_special": "_server_use_special",
	"tutorial_ready": "_server_tutorial_ready",
	"tutorial_pressed": "_server_tutorial_pressed",
	"cheat_give": "_server_cheat_give",
	"cheat_quest": "_server_cheat_quest",
	"cheat_teleport": "_server_cheat_teleport",
	"cheat_tutorial": "_server_cheat_tutorial",
	"cheat_starter_town": "_server_cheat_starter_town",
}

## peer_id -> a NetRegistry entry. Server-owned. Gold, items, the hotbar and
## progress are PRIVATE to their owner: they are stripped before the registry is
## broadcast, and each owner gets theirs alone through cl_purse.
var players := {}
var is_dedicated := false
var active := false            # hosting or connected right now
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

var _upnp: NetUpnp
var _pending_username := ""
var _pending_world_ready: Array[int] = []
var _enemy_counter := 0
var _gold_counter := 0
## Voice flood control, server-side: peer -> [window start msec, bytes spent].
var _voice_spend := {}
## Accumulators for the four server broadcast cadences, keyed by the timer name
## in `_TICKS` below — one dictionary instead of four near-identical fields and
## four copies of "add delta, compare, reset".
var _accum := {}

## Server tick name -> [interval, method]. `_physics_process` walks this.
const _TICKS := [
	[PLAYER_STATE_INTERVAL, "_broadcast_player_states"],
	[ENEMY_STATE_INTERVAL, "_broadcast_enemy_states"],
	[VITALS_INTERVAL, "_send_vitals"],
	[GOLD_PICKUP_INTERVAL, "_check_gold_pickups"],
]

func _ready() -> void:
	_upnp = NetUpnp.new()
	_upnp.name = "Upnp"
	add_child(_upnp)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: rpc_id(1, "sv_register", _pending_username))
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(func() -> void: return_to_menu("Connection to the host was lost."))

## UPnP's own status, re-exported so the menu need not know about the module.
var upnp_status: String:
	get: return _upnp.status if _upnp else "inactive"
var public_ip: String:
	get: return _upnp.public_ip if _upnp else ""

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
		players[1] = _make_entry(username)
	_upnp.start(port)
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

func return_to_menu(message := "") -> void:
	last_error = message
	active = false
	is_dedicated = false
	players.clear()
	_voice_spend.clear()
	Voice.reset()
	_upnp.reset() # the server is gone, close the router port
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)

func should_run_dedicated() -> bool:
	return OS.has_feature("server") or _cmdline().has("--server")

static func _cmdline() -> PackedStringArray:
	return OS.get_cmdline_args() + OS.get_cmdline_user_args()

# ---------------- the one client -> server request ----------------

## Client side: ask the server for something in `SERVER_REQUESTS`. A listen
## server is both ends at once, so it serves itself directly rather than
## rpc-ing — `call_remote` never comes back round to the peer that sent it.
func _ask(kind: String, args := []) -> void:
	if not active:
		return
	if multiplayer.is_server():
		_serve(multiplayer.get_unique_id(), kind, args)
	else:
		rpc_id(1, "sv_request", kind, args)

@rpc("any_peer", "call_remote", "reliable")
func sv_request(kind: String, args: Array) -> void:
	if not multiplayer.is_server():
		return
	_serve(multiplayer.get_remote_sender_id(), kind, args)

## The single gate every client request passes through: is it a request that
## exists, is the sender a registered player, and — for a cheat — is this build
## allowed to honour one at all.
func _serve(id: int, kind: String, args: Array) -> void:
	var handler := str(SERVER_REQUESTS.get(kind, ""))
	if handler == "" or not players.has(id):
		return
	if kind.begins_with("cheat_") and not cheats_allowed():
		_trade_reply(id, "Cheats are off on this server.", false)
		return
	callv(handler, [id] + args)

## Server -> ONE peer, for the two-argument client halves. The host is its own
## client, so it calls the method in-process rather than through an RPC that
## would never arrive — `call_remote` never comes back round to the sender.
##
## Two of these rather than one taking an Array because `rpc_id` cannot be
## handed a variable argument list: an arity per shape is the honest way to
## write it, and there are only two shapes.
func _reply2(id: int, method: String, a: Variant, b: Variant) -> void:
	if id == multiplayer.get_unique_id():
		call(method, a, b)
	else:
		rpc_id(id, method, a, b)

func _reply1(id: int, method: String, a: Variant) -> void:
	if id == multiplayer.get_unique_id():
		call(method, a)
	else:
		rpc_id(id, method, a)

func _trade_reply(id: int, message: String, ok: bool) -> void:
	_reply2(id, "cl_trade_result", message, ok)

func _use_reply(id: int, item_id: String, message: String) -> void:
	_reply2(id, "cl_item_used", item_id, message)

@rpc("authority", "call_remote", "reliable")
func cl_trade_result(message: String, ok: bool) -> void:
	trade_result.emit(message, ok)

@rpc("authority", "call_remote", "reliable")
func cl_item_used(item_id: String, message: String) -> void:
	item_used.emit(item_id, message)

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

func _on_connection_failed() -> void:
	active = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit("Could not reach the host.")

# ---------------- registration / world flow ----------------

## Client -> server: first thing a client sends after connecting. Not part of
## `SERVER_REQUESTS` because it is what MAKES a player — every request in that
## table is refused until this has run.
@rpc("any_peer", "call_remote", "reliable")
func sv_register(username: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		return  # re-registration would reset stats — never allow it
	players[id] = _make_entry(username)
	print("[Net] %s joined (peer %d)" % [players[id]["name"], id])
	# tell Discord somebody is on, so people who would play with them find out.
	# Server-side and after registration, so the roster it reports includes them
	Discord.post_join(str(players[id]["name"]), player_names())
	_sync_players()
	rpc_id(id, "cl_load_world")

@rpc("authority", "call_remote", "reliable")
func cl_load_world() -> void:
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)

## Called by world.gd once the world scene is up on this peer.
func on_world_ready() -> void:
	if not multiplayer.is_server():
		rpc_id(1, "sv_world_ready")
		return
	print("[Net] World loaded — ready for players")
	if not is_dedicated:
		_server_spawn_player(1)
	# clients that finished loading before the server's own world did
	for id in _pending_world_ready:
		_handle_world_ready(id)
	_pending_world_ready.clear()

@rpc("any_peer", "call_remote", "reliable")
func sv_world_ready() -> void:
	if multiplayer.is_server():
		_handle_world_ready(multiplayer.get_remote_sender_id())

func _handle_world_ready(id: int) -> void:
	if not players.has(id):
		return
	var pn := _players_node()
	if pn == null:
		if not _pending_world_ready.has(id):
			_pending_world_ready.append(id)
		return
	# snapshot of everything that already exists, just to the newcomer
	for pawn in pn.get_children():
		rpc_id(id, "cl_spawn_player", pawn.peer_id, pawn.username,
				pawn.global_position if pawn.is_local else pawn.net_pos)
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
## Gold and items are stripped out (see NetRegistry.public_slice); your own
## reach you privately through cl_purse, which fills the GameStats mirror.
@rpc("authority", "call_remote", "reliable")
func cl_sync_players(server_players: Dictionary) -> void:
	players = server_players
	player_list_changed.emit()

func _sync_players() -> void:
	rpc("cl_sync_players", _public_players())
	player_list_changed.emit()

# ---------------- reading the registry ----------------

func _public_players() -> Dictionary:
	return NetRegistry.public_slice(players)

func _empty_equipment() -> Dictionary:
	return NetRegistry.empty_equipment()

func _make_entry(username: String) -> Dictionary:
	return NetRegistry.make_entry(
			NetRegistry.sanitize_name(username, NetRegistry.names(players)),
			_starting_items())

## This peer's pawn, or null if it has none right now. On the server this is
## the authoritative copy — the one combat and the tutorial's gates read.
func pawn_of(id: int) -> Node:
	return _pawn(id)

## What peer `id` has in hand, whichever side of the wire this is: the server
## reads its own bar, a client reads the "held" field of the public registry.
func held_of(id: int) -> String:
	var entry: Dictionary = players.get(id, {})
	return NetRegistry.held_item(entry) if entry.has("hotbar") else str(entry.get("held", ""))

## What a peer is WEARING, as armor slot -> item id. Public on purpose: it is
## drawn on their back, so every peer has to be able to see it.
func equipment_of(peer_id: int) -> Dictionary:
	return (players.get(peer_id, {}) as Dictionary).get("equipped", {})

func armor_levels(peer_id: int) -> int:
	return NetRegistry.armor_levels(players.get(peer_id, {}))

func held_item(entry: Dictionary) -> String:
	return NetRegistry.held_item(entry)

func my_stats() -> Dictionary:
	return players.get(multiplayer.get_unique_id(), _make_entry(""))

## Everybody currently registered, by name. The scoreboard reads the registry
## itself; this is for anything that just wants the roster (the Discord post).
func player_names() -> Array:
	return NetRegistry.names(players)

## Testing aid: launch the SERVER with --dev-items and everyone who joins it
## starts with one of every item in the catalogue. It is deliberately a server
## flag — a client passing it gains nothing, because only the server ever
## writes a bag.
func _starting_items() -> Dictionary:
	if not multiplayer.is_server() or not _cmdline().has("--dev-items"):
		return {}
	var bag := {}
	for id in ItemDb.ITEMS:
		bag[id] = 1
	return bag

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
	_ask("start_quest", [quest_id])

func request_finish_quest(quest_id: String) -> void:
	_ask("finish_quest", [quest_id])

func request_gift(gift_id: String) -> void:
	_ask("gift", [gift_id])

func _server_start_quest(id: int, quest_id: String) -> void:
	if not QuestData.has(quest_id):
		return
	var giver := QuestData.giver(quest_id)
	if giver == "" or not _near_npc(id, giver):
		return # nobody hands this one out, or you are not standing at them
	_set_quest(id, quest_id)

## Refused unless you are actually on the quest, actually made the count, and
## actually stood in front of whoever it is handed in to.
func _server_finish_quest(id: int, quest_id: String) -> void:
	if not QuestData.has(quest_id) or str(players[id].get("quest", "")) != quest_id:
		return
	# a counting quest is not handed in until the count is really made. The
	# conversation offering the answer is LOCAL, so a patched client can pick it
	# whenever it likes — this is the server's own tally, and the only thing
	# standing between "I did it." and 25 bandits nobody killed.
	if QuestData.kills_needed(quest_id) > 0 \
			and not QuestData.is_complete(quest_id, int(players[id].get("quest_kills", 0))):
		return
	var at := QuestData.done_at(quest_id)
	if at == "" or not _near_npc(id, at):
		return
	# paid once, because handing in is what clears the quest: come back and the
	# check above sees you are not on it any more
	var reward := QuestData.reward_gold(quest_id)
	if reward > 0:
		players[id]["gold"] = int(players[id].get("gold", 0)) + reward
	_set_quest(id, "") # sends the purse, so the gold rides along with it

func _server_take_gift(id: int, gift_id: String) -> void:
	if not GiftData.has(gift_id):
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
	for item_id: String in GiftData.items(gift_id):
		if ItemDb.has(item_id):
			NetRegistry.add_item(players[id], item_id)
		else:
			push_warning("Net: gift '%s' lists an unknown item '%s'" % [gift_id, item_id])
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
## that asks for kills.
##
## What the last kill does depends on whether anybody is waiting to hear about
## it. A counting quest with a `done_at` TURNS ROUND on the final kill — it
## stays on the HUD, the heading becomes its `done_name` and the star points
## back at whoever sent you — and is only cleared when you stand in front of
## them. One with no `done_at` has nobody to report back to, so it finishes
## itself where it stands.
func _credit_quest_kill(id: int) -> void:
	if not players.has(id):
		return
	var quest_id := str(players[id].get("quest", ""))
	var needed := QuestData.kills_needed(quest_id)
	if needed <= 0:
		return
	var done := int(players[id].get("quest_kills", 0)) + 1
	# capped, or a kill after the count is made keeps ticking a number the
	# heading has already stopped showing
	players[id]["quest_kills"] = mini(done, needed)
	if done < needed:
		_send_purse(id)
		return
	if QuestData.done_at(quest_id) != "":
		if done == needed:
			print("[Net] %s counted out '%s' (%d kills), reporting to '%s'" % [players[id]["name"],
					QuestData.label(quest_id), needed, QuestData.done_at(quest_id)])
		_send_purse(id) # the heading flips to the walk home
		return
	print("[Net] %s finished '%s' (%d kills)" % [players[id]["name"],
			QuestData.label(quest_id), needed])
	_set_quest(id, "")

# ---------------- shops ----------------
#
# Gold and the bag live in the registry, which only the server writes. Clients
# hold a read-only mirror in GameStats and ASK to trade; the server checks the
# shop stocks the item, that the price is its own price, that the player can
# afford it or actually holds it, and that they are standing at the counter.

func request_buy(shop_id: String, item_id: String) -> void:
	_ask("trade", [shop_id, item_id, true])

func request_sell(shop_id: String, item_id: String) -> void:
	_ask("trade", [shop_id, item_id, false])

func _server_trade(id: int, shop_id: String, item_id: String, buying: bool) -> void:
	if not ShopData.has(shop_id) or not ItemDb.has(item_id):
		_trade_reply(id, "There's nothing like that for sale here.", false)
		return
	if not _near_npc(id, shop_id):
		_trade_reply(id, "You're too far from the counter.", false)
		return
	var entry: Dictionary = players[id]
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
		NetRegistry.add_item(entry, item_id)
		_trade_reply(id, "Bought %s for %d gold." % [label, price], true)
	else:
		if not ShopData.buys(shop_id, item_id):
			_trade_reply(id, "He won't take that.", false)
			return
		if not NetRegistry.remove_item(entry, item_id):
			_trade_reply(id, "You have no %s to sell." % label, false)
			return
		var price := ItemDb.sell_price(item_id)
		entry["gold"] = gold + price
		_trade_reply(id, "Sold %s for %d gold." % [label, price], true)
	_bag_changed(id)

# ---------------- cheats (development only) ----------------
#
# The cheat menu is a testing tool, so it goes through the server like anything
# else that touches a bag — a client still cannot write its own items. Every
# "cheat_" request is refused by `_serve` unless the SERVER is an editor run, so
# an exported dedicated server ignores cheats no matter what a client sends.

## Would this build honour a cheat request? False in any exported build.
func cheats_allowed() -> bool:
	return OS.has_feature("editor")

func request_cheat_give(item_id: String) -> void:
	_ask("cheat_give", [item_id])

func request_cheat_quest(quest_id: String) -> void:
	_ask("cheat_quest", [quest_id])

func request_cheat_teleport(dest_id: String) -> void:
	_ask("cheat_teleport", [dest_id])

func request_cheat_tutorial() -> void:
	_ask("cheat_tutorial")

## Not only a place: from inside the tutorial this GRADUATES you — the same
## exit the last lesson uses, so the copy of the city is torn down, its bandits
## go with it and the follow-up quest is handed over. A plain teleport out would
## leave the lesson running behind you, with its bandits standing in an island
## nobody is in.
func request_cheat_starter_town() -> void:
	_ask("cheat_starter_town")

func _server_cheat_give(id: int, item_id: String) -> void:
	if not ItemDb.has(item_id):
		_trade_reply(id, "No such item.", false)
		return
	NetRegistry.add_item(players[id], item_id)
	_trade_reply(id, "Gave %s." % ItemDb.item_name(item_id), true)
	_bag_changed(id)

func _server_cheat_quest(id: int, quest_id: String) -> void:
	if quest_id != "" and not QuestData.has(quest_id):
		_trade_reply(id, "No such quest.", false)
		return
	_set_quest(id, quest_id)
	_trade_reply(id, "Quest cleared." if quest_id == ""
			else "Tracking %s." % QuestData.label(quest_id), true)

## The server moves its OWN copy of the pawn and then tells the owner where it
## now is. Doing it the other way round would be a client teleport, which the
## position validator exists to reject.
func _server_cheat_teleport(id: int, dest_id: String) -> void:
	if not TeleportData.has(dest_id):
		_trade_reply(id, "No such place.", false)
		return
	if TeleportData.anchor(get_tree(), dest_id) == null:
		_trade_reply(id, "%s has no anchor in this level yet." % TeleportData.label(dest_id), false)
		return
	if _standing_pawn(id) == null:
		return
	server_teleport_to(id, dest_id)
	_trade_reply(id, "Teleported to %s." % TeleportData.label(dest_id), true)

## A real restart on the server — a fresh copy of the city with its own
## bandits, not a client pretending to be at step one.
func _server_cheat_tutorial(id: int) -> void:
	if _standing_pawn(id) == null:
		return
	var pos := Tutorial.server_begin(id)
	if pos == Vector3.INF:
		_trade_reply(id, "No room for another copy of the city.", false)
		return
	_move_pawn(id, pos)
	# a restart has nobody to report in for it, so the lesson starts at once
	Tutorial.server_report_ready(id)
	_trade_reply(id, "Tutorial restarted.", true)

func _server_cheat_starter_town(id: int) -> void:
	if _standing_pawn(id) == null:
		return
	if Tutorial.server_running(id):
		Tutorial.server_end(id, true) # graduating already places you on the island
	else:
		server_place_on_island(id)
	_trade_reply(id, "Off to the starter town.", true)

## The pawn of a player who is in a state to be moved, or null (having said so).
func _standing_pawn(id: int) -> Node:
	var pawn := _pawn(id)
	if pawn == null or pawn.dead:
		_trade_reply(id, "Not while you are down.", false)
		return null
	return pawn

## SERVER: move a pawn and tell its owner where it landed.
func _move_pawn(id: int, pos: Vector3) -> void:
	var pawn := _pawn(id)
	if pawn == null:
		return
	pawn.net_teleport(pos)
	if id != multiplayer.get_unique_id():
		rpc_id(id, "cl_force_position", pos)

## Put a player on a named `TeleportData` destination. The server moves its OWN
## copy of the pawn and then tells the owner where it now is — doing it the
## other way round is a client teleport, which the position validator exists to
## reject. Shared by the cheat above and by `Portal`, so there is one place that
## knows how a pawn is moved across the level.
func server_teleport_to(id: int, dest_id: String) -> bool:
	if not multiplayer.is_server() or not players.has(id):
		return false
	var anchor := TeleportData.anchor(get_tree(), dest_id)
	var pawn := _pawn(id)
	if anchor == null or pawn == null or pawn.dead:
		return false
	_move_pawn(id, anchor.global_position)
	return true

# ---------------- hotbar, using and wearing (server-owned) ----------------

func request_hotbar_select(slot: int) -> void:
	_ask("hotbar_select", [slot])

func request_hotbar_assign(slot: int, item_id: String) -> void:
	_ask("hotbar_assign", [slot, item_id])

func request_use_item() -> void:
	_ask("use_item")

## The SPECIAL button (L2 / RMB) on whatever is in hand. Only reaches the server
## for an item that DECLARES a special — an empty hand and a sword just guard,
## and the guard is client-side and validated the way it always was.
func request_use_special() -> void:
	_ask("use_special")

func _server_hotbar_select(id: int, slot: int) -> void:
	if slot < 0 or slot >= HOTBAR_SLOTS:
		return
	players[id]["hot_slot"] = slot
	_hotbar_changed(id)

func _server_hotbar_assign(id: int, slot: int, item_id: String) -> void:
	if slot < 0 or slot >= HOTBAR_SLOTS:
		return
	if not NetRegistry.assign_hotbar(players[id], slot, item_id):
		# you can only put something on the bar that you are actually carrying
		_trade_reply(id, "You aren't carrying that.", false)
		_send_purse(id)
		return
	_hotbar_changed(id)

## The server decides what using an item does — never the client. Right now no
## item in the catalogue has an effect, so this only validates; give an item one
## by branching on item_id here, and remember to `_bag_changed(id)` if the bag
## changed.
##
## Replies carry an EMPTY message on purpose: `use_item` shares R2 with
## `attack`, so this runs on every swing, and a line on screen each time would
## be noise. Fill the message in when a use actually does something.
func _server_use_item(id: int) -> void:
	var item_id := _usable_item(id)
	if item_id != "" or _live_pawn(id):
		_use_reply(id, item_id, "")

## SERVER: run the held item's special. The request names NOTHING — not the
## item, not the action — so the worst a patched client can do is press a button
## it is already holding down. What happens comes off the server's own bar and
## the catalogue.
func _server_use_special(id: int) -> void:
	var item_id := _usable_item(id)
	if item_id == "":
		return
	match ItemDb.special_action(item_id):
		ItemDb.SPECIAL_EQUIP:
			_server_equip(id, item_id)
		_:
			pass # nothing declared: that button is the guard, and it is not ours

## What a living player is actually holding AND carrying, or "" — the shared
## front half of both button handlers.
func _usable_item(id: int) -> String:
	if not _live_pawn(id):
		return ""
	var entry: Dictionary = players[id]
	var item_id := NetRegistry.held_item(entry)
	return item_id if NetRegistry.carries(entry, item_id) else ""

func _live_pawn(id: int) -> bool:
	var pawn := _pawn(id)
	return pawn != null and not pawn.dead

## SERVER: put `item_id` on, or take it off if it is already worn. Everything it
## could be lied about is checked in NetRegistry.toggle_equipped — that the
## thing is armor, that the player is really carrying it, and which slot it
## belongs in (the ITEM says, never the request).
func _server_equip(id: int, item_id: String) -> void:
	var moved := NetRegistry.toggle_equipped(players[id], item_id)
	if str(moved[0]) == "":
		return
	# the owner gets the new set privately with the rest of their purse, and
	# EVERYONE gets the registry again, because what you are wearing is drawn on
	# your pawn for the whole server to see
	_send_purse(id)
	_sync_players()
	_use_reply(id, item_id, ("Took off %s" if bool(moved[1]) else "Equipped %s")
			% ItemDb.item_name(item_id))

## Anything that adds to or takes from a bag ends here: the bar is brought back
## in line with what is actually carried, armor you no longer own comes off, and
## then the owner is re-synced.
func _bag_changed(id: int) -> void:
	if players.has(id):
		NetRegistry.refill_hotbar(players[id])
		NetRegistry.drop_unowned_equipment(players[id])
	_hotbar_changed(id)

## The bar moved: the owner gets the new bar privately, and everyone gets the
## public registry again — it carries "held", which is what other players draw
## in this one's hand.
func _hotbar_changed(id: int) -> void:
	_send_purse(id)
	_sync_players()

func _near_npc(id: int, dialog_id: String) -> bool:
	return NetWorld.near_npc(get_tree(), _pawn(id), dialog_id, SHOP_RANGE_SLACK)

## Server -> one owner: here is your authoritative gold and bag. This is the
## ONLY thing that writes the GameStats mirror.
func _send_purse(id: int) -> void:
	var e: Dictionary = players.get(id, {})
	var args := [int(e.get("gold", 0)), e.get("items", {}),
			e.get("hotbar", NetRegistry.empty_hotbar()), int(e.get("hot_slot", 0)),
			str(e.get("quest", "")), int(e.get("quest_kills", 0)),
			e.get("gifts", {}), e.get("equipped", {})]
	if id == multiplayer.get_unique_id():
		callv("cl_purse", args)
	else:
		rpc_id(id, "cl_purse", args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7])

@rpc("authority", "call_remote", "reliable")
func cl_purse(gold: int, items: Dictionary, hotbar: Array, hot_slot: int,
		quest: String, quest_kills := 0, gifts := {}, equipped := {}) -> void:
	GameStats.coins = gold
	GameStats.items = items.duplicate(true) # never alias the server's dictionary
	GameStats.hotbar = hotbar.duplicate()
	GameStats.hot_slot = hot_slot
	GameStats.quest = quest
	GameStats.quest_kills = quest_kills
	GameStats.gifts = gifts.duplicate()
	GameStats.equipped = equipped.duplicate()
	GameStats.changed.emit()

# ---------------- state replication ----------------

func _physics_process(delta: float) -> void:
	if not active or not multiplayer.is_server() or _players_node() == null:
		return
	for tick: Array in _TICKS:
		var key: String = tick[1]
		var t := float(_accum.get(key, 0.0)) + delta
		if t >= float(tick[0]):
			t = 0.0
			call(key)
		_accum[key] = t
	_check_fell_off_world()

func _broadcast_player_states() -> void:
	var batch := []
	for pawn in _players_node().get_children():
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

func _send_vitals() -> void:
	var connected := multiplayer.get_peers()
	for pawn in _players_node().get_children():
		if pawn.peer_id != 1 and connected.has(pawn.peer_id):
			rpc_id(pawn.peer_id, "cl_vitals", pawn.stamina, pawn.health)

@rpc("authority", "call_remote", "unreliable")
func cl_vitals(server_stamina: float, server_health: float) -> void:
	var pawn := _pawn(multiplayer.get_unique_id())
	if pawn:
		pawn.stamina = server_stamina
		pawn.health = server_health

func _check_fell_off_world() -> void:
	for pawn in _players_node().get_children():
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
	if multiplayer.is_server():
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

func voice_accepts(from_id: int, packet: PackedByteArray) -> bool:
	return multiplayer.is_server() and NetVoice.accepts(_voice_spend, from_id, packet)

func voice_targets(from_id: int) -> Array[int]:
	var out: Array[int] = []
	return NetVoice.targets(get_tree(), players, from_id) if multiplayer.is_server() else out

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
	cl_player_damaged(id, health, result, knockback, stamina, attacker) # host's own fx

@rpc("authority", "call_remote", "reliable")
func cl_player_damaged(id: int, health: float, result: int, knockback: Vector3,
		stamina: float, attacker: int) -> void:
	var pawn := _pawn(id)
	if pawn:
		pawn.net_apply_damage(health, result, knockback, stamina, attacker)

## Parried or guard-broken: everyone plays the helpless pose for the same beat.
func server_broadcast_player_stagger(id: int, duration: float) -> void:
	rpc("cl_player_staggered", id, duration)
	cl_player_staggered(id, duration)

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
	cl_player_died(victim)

@rpc("authority", "call_remote", "reliable")
func cl_player_died(id: int) -> void:
	var pawn := _pawn(id)
	if pawn:
		pawn.net_die()

func server_respawn_player(id: int) -> void:
	if _players_node() == null:
		return
	# dying in the tutorial puts you back in the tutorial: the island is
	# somewhere you have not earned yet
	var pos := Tutorial.server_respawn_position(id)
	if pos == Vector3.INF:
		pos = spawn_position(randi() % 8)
	rpc("cl_player_respawn", id, pos)
	cl_player_respawn(id, pos)

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
			private.get_or_add(audience, []).append(e.net_visual_state())
	if not batch.is_empty():
		rpc("cl_enemy_states", batch)
	for peer: int in private:
		if peer != 1:
			rpc_id(peer, "cl_enemy_states", private[peer])

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_enemy_states(batch: Array) -> void:
	for row in batch:
		var e := _enemy(String(row[0]))
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
	cl_enemy_staggered(enemy_name, duration) # host plays the pose locally too

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
	var e := _enemy(enemy_name)
	if e:
		e.net_die()

func server_remove_enemy(enemy_name: String) -> void:
	rpc("cl_remove_enemy", enemy_name)

@rpc("authority", "call_remote", "reliable")
func cl_remove_enemy(enemy_name: String) -> void:
	var e := _enemy(enemy_name)
	if e:
		e.queue_free()

# ---------------- tutorial ----------------
#
# The tutorial gives each player a private copy of a city (see
# scripts/world/tutorial/). The rules are the usual ones: the SERVER owns the
# copy, its bandits and which step you are on; the client owns nothing but the
# screen. What is different is the AUDIENCE — a tutorial bandit is spawned and
# updated only for the one player it belongs to, because it is not in anyone
# else's world.

## SERVER: spawn one bandit into `id`'s copy of the city and tell only them.
func server_spawn_tutorial_bandit(id: int, pos: Vector3,
		hold: Enemy.Hold = Enemy.Hold.NONE) -> Node:
	var en := _enemies_node()
	if not multiplayer.is_server() or en == null:
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
	_move_pawn(id, spawn_position(0))

## SERVER -> one client: build your copy of the city / step / tear it down.
## The host is both ends at once, so it calls its own client half directly —
## `call_remote` RPCs never come back round to the peer that sent them.
func tutorial_enter(id: int, slot: int) -> void:
	_reply1(id, "cl_tutorial_enter", slot)

func tutorial_step(id: int, step_id: String) -> void:
	_reply1(id, "cl_tutorial_step", step_id)

func tutorial_leave(id: int) -> void:
	if id == multiplayer.get_unique_id():
		cl_tutorial_leave()
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
	_ask("tutorial_ready")

## CLIENT -> server: I did the thing this step asked for. Only the steps the
## server cannot watch for itself are taken on trust (see TutorialData), and the
## most a patched client wins by lying is skipping its own lesson.
func report_tutorial_pressed(step_id: String) -> void:
	_ask("tutorial_pressed", [step_id])

func _server_tutorial_ready(id: int) -> void:
	Tutorial.server_report_ready(id)

func _server_tutorial_pressed(id: int, step_id: String) -> void:
	Tutorial.server_report_pressed(id, step_id)

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
	var d: Node = dn.get_node_or_null(drop_name) if dn else null
	if d:
		d.queue_free()

## SERVER: award piles to the first living player standing on them.
func _check_gold_pickups() -> void:
	var dn := _drops_node()
	if dn == null:
		return
	for d in dn.get_children():
		var dpos: Vector3 = d.global_position
		for pawn in _players_node().get_children():
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
	cl_gold_picked(String(drop.name), drop.amount, drop.global_position)

@rpc("authority", "call_remote", "reliable")
func cl_gold_picked(drop_name: String, amount: int, pos: Vector3) -> void:
	var w := _world()
	if w == null:
		return
	GOLD_DROP_SCRIPT.spawn_pickup_text(w, pos, amount)
	cl_remove_gold(drop_name)

# ---------------- where things are (see NetWorld) ----------------

func spawn_position(i: int) -> Vector3:
	return NetWorld.spawn_position(get_tree(), i)

func _world() -> Node:
	return NetWorld.world(get_tree())

func _players_node() -> Node:
	return NetWorld.players_node(get_tree())

func _enemies_node() -> Node:
	return NetWorld.enemies_node(get_tree())

func _drops_node(create := false) -> Node:
	return NetWorld.drops_node(get_tree(), create)

func _pawn(id: int) -> Node:
	return NetWorld.pawn(get_tree(), id)

func _enemy(enemy_name: String) -> Node:
	return NetWorld.enemy(get_tree(), enemy_name)
