extends Node
## Autoload "Net": all multiplayer plumbing — hosting/joining (ENet), UPnP
## port mapping so hosts don't need manual port forwarding, the server-
## authoritative player registry (usernames + kills/deaths) and the whole
## RPC protocol. The server never trusts clients: it validates movement,
## simulates all combat itself and is the only writer of health and stats;
## everything a client sends is treated as a request or a cosmetic claim.

const DEFAULT_PORT := 27032
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

## peer_id -> {"name", "kills", "deaths", "gold", "items"}. Server-owned.
## "gold"/"items" are private to their owner: they are stripped before the
## registry is broadcast, and each owner gets theirs alone through cl_purse.
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
			if not e.dead:
				rpc_id(id, "cl_spawn_enemy", String(e.name), e.global_position)
	var dn := _drops_node()
	if dn:
		for d in dn.get_children():
			rpc_id(id, "cl_spawn_gold", String(d.name), d.global_position, d.amount)
	rpc_id(id, "cl_sync_players", players)
	# then their own pawn, broadcast to everyone (including them)
	_server_spawn_player(id)

func _server_spawn_player(id: int) -> void:
	var pn := _players_node()
	if pn == null or pn.has_node(str(id)):
		return
	var pos := spawn_position(pn.get_child_count())
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
		out[id] = {"name": e["name"], "kills": e["kills"], "deaths": e["deaths"]}
	return out

func _make_entry(username: String) -> Dictionary:
	return {"name": username, "kills": 0, "deaths": 0, "gold": 0, "items": {}}

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

# ---------------- purse and bag (server-owned) ----------------
#
# Gold and carried items live in the registry above, which only the server
# writes. Clients hold a read-only mirror in GameStats and ASK to trade; the
# server checks the shop stocks the item, that the price is its own price,
# that the player can afford it or actually holds it, and that they are
# standing at the counter. A client that lies gets a refusal and a re-sync.

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
	if not _at_counter(id, shop_id):
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

	_send_purse(id)

## Is this player actually standing at that NPC? The server owns every pawn's
## position (speed-validated in sv_player_state), so this can't be spoofed.
func _at_counter(id: int, shop_id: String) -> bool:
	var pawn := _pawn(id)
	if pawn == null:
		return false
	for npc in get_tree().get_nodes_in_group("npc_interactable"):
		if not is_instance_valid(npc) or npc.dialog_id != shop_id:
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
	if id == multiplayer.get_unique_id():
		cl_purse(gold, items)
	else:
		rpc_id(id, "cl_purse", gold, items)

@rpc("authority", "call_remote", "reliable")
func cl_purse(gold: int, items: Dictionary) -> void:
	GameStats.coins = gold
	GameStats.items = items.duplicate(true) # never alias the server's dictionary
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
			pawn.net_apply_state(row[1], row[2], row[3], row[4], row[5], row[6])

## Client owner -> server: position + cosmetic state claim, ~20 Hz.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func sv_player_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, blocking: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var pawn := _pawn(id)
	if pawn == null or pawn.is_local:
		return
	if not pawn.net_report_state(pos, yaw, anim, anim_t, ratio, blocking):
		# rejected (teleport / speedhack): snap the client back
		rpc_id(id, "cl_force_position", pawn.net_pos)

@rpc("authority", "call_remote", "reliable")
func cl_force_position(pos: Vector3) -> void:
	var pawn := _pawn(multiplayer.get_unique_id())
	if pawn:
		pawn.global_position = pos
		pawn.velocity = Vector3.ZERO

func send_player_state(pos: Vector3, yaw: float, anim: String, anim_t: float,
		ratio: float, blocking: bool) -> void:
	if active and not multiplayer.is_server():
		rpc_id(1, "sv_player_state", pos, yaw, anim, anim_t, ratio, blocking)

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

# ---------------- combat protocol ----------------

## Client owner -> server: "I pressed attack" (+ claimed lock-on target,
## which the server re-validates by range). Everything else is server-side.
@rpc("any_peer", "call_remote", "reliable")
func sv_request_attack(heavy: bool, lock_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var pawn := _pawn(multiplayer.get_remote_sender_id())
	if pawn and not pawn.is_local:
		pawn.server_handle_attack_request(heavy, lock_path)

func request_attack(heavy: bool, lock_path: NodePath) -> void:
	rpc_id(1, "sv_request_attack", heavy, lock_path)

## Server: tell everyone (but the swinging owner predicted it already).
func server_broadcast_swing(id: int, heavy: bool, section: int) -> void:
	rpc("cl_play_swing", id, heavy, section)

@rpc("authority", "call_remote", "reliable")
func cl_play_swing(id: int, heavy: bool, section: int) -> void:
	var pawn := _pawn(id)
	if pawn and not pawn.is_local:
		pawn.puppet_play_swing(heavy, section)

func server_broadcast_player_damage(id: int, health: float, blocked: bool,
		knockback: Vector3) -> void:
	rpc("cl_player_damaged", id, health, blocked, knockback)
	var pawn := _pawn(id)  # host applies its own fx locally too
	if pawn:
		pawn.net_apply_damage(health, blocked, knockback)

@rpc("authority", "call_remote", "reliable")
func cl_player_damaged(id: int, health: float, blocked: bool, knockback: Vector3) -> void:
	var pawn := _pawn(id)
	if pawn:
		pawn.net_apply_damage(health, blocked, knockback)

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
	var pos := spawn_position(randi() % 8)
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
	for e in en.get_children():
		if not e.dead:
			batch.append(e.net_visual_state())
	if not batch.is_empty():
		rpc("cl_enemy_states", batch)

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

func server_broadcast_enemy_damage(enemy_name: String, health: float, blocked: bool) -> void:
	rpc("cl_enemy_damaged", enemy_name, health, blocked)

@rpc("authority", "call_remote", "reliable")
func cl_enemy_damaged(enemy_name: String, health: float, blocked: bool) -> void:
	var en := _enemies_node()
	if en == null:
		return
	var e := en.get_node_or_null(enemy_name)
	if e:
		e.net_apply_damage(health, blocked)

func server_record_enemy_kill(enemy_name: String, attacker: int) -> void:
	if attacker > 0 and players.has(attacker):
		print("[Net] %s slew %s" % [players[attacker]["name"], enemy_name])
		players[attacker]["kills"] += 1
		_sync_players()
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
