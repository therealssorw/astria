extends Node
## Headless check of the account/persistence layer. Run with:
##   godot --headless res://tests/test_accounts.tscn
## Prints ACCOUNTTEST RESULT=PASS/FAIL and sets the exit code.
##
## This deliberately does NOT talk to Supabase. What it guards is the stuff
## that goes quietly wrong and would only show up as a player losing their
## gold: the service key leaking into a client build, a private field riding
## along in the public registry broadcast, a stale save wedging a bag, and the
## save queue dropping a write when the API fails.

const AUTH := preload("res://scripts/core/account/auth.gd")

var _failures: Array[String] = []

func _ready() -> void:
	_test_service_key_is_server_only()
	_test_registry_never_broadcasts_private_fields()
	_test_every_progress_field_is_saved()
	_test_a_whole_player_survives_the_round_trip()
	_test_load_save_shape()
	_test_a_stale_save_cannot_wedge_a_player()
	_test_failed_write_is_requeued()
	_test_pkce_challenge_is_url_safe()

	if _failures.is_empty():
		print("ACCOUNTTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		print("ACCOUNTTEST RESULT=FAIL (%d)" % _failures.size())
		get_tree().quit(1)

func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)

# ---------------- the trust boundary ----------------

## The single worst mistake this feature could make. A client build that can
## read the service key can rewrite anybody's save.
func _test_service_key_is_server_only() -> void:
	var was := Net.is_dedicated
	Net.is_dedicated = false
	OS.set_environment(Supabase.ENV_SERVICE, "pretend-service-key")
	_check(Supabase.service_key().is_empty(),
		"service_key() handed out a key on a non-dedicated build")
	_check(not SaveStore.available(),
		"SaveStore thinks it can write from a client build")
	OS.set_environment(Supabase.ENV_SERVICE, "")
	Net.is_dedicated = was

## Gold, items and now the account id are private. The scoreboard broadcast is
## sent to every peer, so anything that ends up in it is public forever.
func _test_registry_never_broadcasts_private_fields() -> void:
	Net.players = {
		7: {"name": "Ada", "kills": 3, "deaths": 1, "gold": 999,
			"items": {"sword": 2}, "user_id": "0000-secret"},
	}
	var public: Dictionary = Net._public_players()
	var row: Dictionary = public[7]
	for private in ["gold", "items", "user_id"]:
		_check(not row.has(private),
			"_public_players leaked '%s' to every peer" % private)
	_check(row.get("name") == "Ada" and row.get("kills") == 3,
		"_public_players dropped a field the scoreboard needs")
	Net.players = {}

# ---------------- load / save round trip ----------------

## THE test that stops this quietly rotting. Every field of a live entry is
## either saved or on the short list of things that must not be — so adding a
## new piece of progress to `make_entry` and forgetting to persist it fails
## here, instead of failing as a player logging back in to find it gone.
func _test_every_progress_field_is_saved() -> void:
	# name comes from Discord on every login, user_id IS the account, and seen
	# is re-derived from the bag by apply_save.
	const NOT_SAVED := ["name", "user_id", "seen"]
	var entry: Dictionary = Net._make_entry("Ada")
	for key: String in entry:
		if NOT_SAVED.has(key):
			continue
		_check(NetRegistry.PERSISTED.has(key),
			"'%s' is part of a player but nothing saves it" % key)
	for key: String in NetRegistry.PERSISTED:
		_check(entry.has(key), "PERSISTED saves '%s', which is not part of a player" % key)
	print("  saved fields: %d of %d entry fields (%s not saved)"
		% [NetRegistry.PERSISTED.size(), entry.size(), ", ".join(NOT_SAVED)])

## A full round trip through the shape the database actually stores: play a
## little, write it out, parse it back, and come back as the same player. JSON
## in the middle is not decoration — jsonb is what the column is, and it is what
## turns an int into a float and an Array[String] into a plain Array.
func _test_a_whole_player_survives_the_round_trip() -> void:
	var before: Dictionary = Net._make_entry("Ada")
	before["gold"] = 340
	before["kills"] = 12
	before["deaths"] = 3
	NetRegistry.add_item(before, "flimsy_helmet", 1)
	NetRegistry.add_item(before, "copper_helmet", 2)
	NetRegistry.refill_hotbar(before)
	NetRegistry.assign_hotbar(before, 4, "copper_helmet")
	NetRegistry.equip(before, "flimsy_helmet")
	before["quest"] = "speak_to_king"
	before["quest_kills"] = 2
	before["gifts"] = {"blacksmith_armor": true}
	NetRegistry.record_boss_kill(before, "juggernaut")
	NetRegistry.record_boss_kill(before, "juggernaut")

	# out through jsonb and back, exactly as Supabase would hand it over
	var row: Variant = JSON.parse_string(JSON.stringify(NetRegistry.snapshot(before)))
	_check(row is Dictionary, "a snapshot did not survive being JSON")
	if not row is Dictionary:
		return
	var after: Dictionary = Net._make_entry("Ada")
	NetRegistry.apply_save(after, row)

	for key: String in NetRegistry.PERSISTED:
		_check(str(after[key]) == str(before[key]),
			"'%s' came back as %s, not %s" % [key, after[key], before[key]])
	# and the derived half: a bar slot only holds what the bag still has, and a
	# worn piece is on your back rather than in the sack
	_check(NetRegistry.held_item(after) == "copper_helmet",
		"the player came back holding '%s'" % NetRegistry.held_item(after))
	_check(str(after["equipped"].get("helmet", "")) == "flimsy_helmet",
		"the helmet did not come back on")
	_check(not NetRegistry.carries(after, "flimsy_helmet"),
		"the worn helmet came back in the bag as well as on the head")
	print("  round trip: %d gold, %d items, quest '%s', %d worn, bosses %s"
		% [after["gold"], (after["items"] as Dictionary).size(), after["quest"],
			(after["equipped"] as Dictionary).values().count("flimsy_helmet"),
			after["bosses"]])

## The store asks for the columns the game knows about and applies the keys the
## row came back with — nothing more, so a schema behind or ahead of the build
## is a partial load rather than a broken one.
func _test_load_save_shape() -> void:
	var loaded: Dictionary = await SaveStore.load_save("nobody")
	_check(not loaded["ok"], "load_save claimed success with no database")
	_check(loaded.get("save") is Dictionary, "load_save returned no save at all")
	var columns: PackedStringArray = SaveStore._columns()
	_check(columns.has("coins"), "the store stopped asking for the coins column")
	_check(columns.size() == NetRegistry.PERSISTED.size(),
		"%d columns for %d saved fields" % [columns.size(), NetRegistry.PERSISTED.size()])
	# a save is applied by key, so a row that is missing one leaves the default
	var entry: Dictionary = Net._make_entry("Ada")
	NetRegistry.apply_save(entry, {"gold": 7})
	_check(int(entry["gold"]) == 7 and entry.has("hotbar") and entry.has("bosses"),
		"a partial save did not leave the rest of the player intact")

## The catalogue changes between builds, and a row can be hand-edited by anyone
## with database access. Nothing in one may travel into a live player.
func _test_a_stale_save_cannot_wedge_a_player() -> void:
	var entry: Dictionary = Net._make_entry("Ada")
	NetRegistry.apply_save(entry, {
		"gold": -500,
		"items": {"definitely_not_an_item": 4, "copper_helmet": 2, "negative": -1},
		"hotbar": ["definitely_not_an_item", "copper_helmet"],
		"hot_slot": 99,
		"quest": "a_quest_that_was_renamed",
		"quest_kills": -3,
		"gifts": {"not_a_gift": true},
		"equipped": {"helmet": "copper_chestplate"}, # right item, wrong slot
		"bosses": {"juggernaut": "lots"},
	})
	_check(int(entry["gold"]) == 0, "a negative save became negative gold")
	_check(not (entry["items"] as Dictionary).has("definitely_not_an_item"),
		"an item ItemDb no longer knows travelled into a live bag")
	_check(not (entry["items"] as Dictionary).has("negative"), "a non-positive count survived")
	_check(int((entry["items"] as Dictionary).get("copper_helmet", 0)) == 2,
		"a valid item was dropped along with the bad ones")
	_check(not (entry["hotbar"] as Array).has("definitely_not_an_item"),
		"the bar came back pointing at an item that does not exist")
	_check(int(entry["hot_slot"]) < NetRegistry.HOTBAR_SLOTS, "hot_slot came back off the end of the bar")
	_check(str(entry["quest"]) == "", "a quest this build does not have survived")
	_check(int(entry["quest_kills"]) == 0, "negative quest progress survived")
	_check((entry["gifts"] as Dictionary).is_empty(), "an unknown gift id survived")
	_check(str((entry["equipped"] as Dictionary).get("helmet", "")) == "",
		"a chestplate was worn as a helmet")
	_check((entry["bosses"] as Dictionary).is_empty(), "a non-numeric boss count survived")

## An API blip must not eat somebody's afternoon. A write that fails goes back
## on the queue rather than vanishing.
func _test_failed_write_is_requeued() -> void:
	var entry: Dictionary = Net._make_entry("Ada")
	entry["gold"] = 50
	SaveStore._dirty["u1"] = entry
	# No service key here, so the POST inside _flush fails at the first check.
	await SaveStore._flush("u1")
	_check(SaveStore._dirty.has("u1"), "a failed save write was dropped, not requeued")
	SaveStore._dirty.clear()
	SaveStore._in_flight.clear()

# ---------------- PKCE ----------------

## base64url, not base64: a "+" in a query string means a space, so a plain
## base64 challenge would arrive at Supabase corrupted and every login would
## fail with an unhelpful message.
func _test_pkce_challenge_is_url_safe() -> void:
	var auth = AUTH.new()
	var verifier: String = auth._make_verifier()
	var challenge: String = auth._challenge_for(verifier)
	for s in [verifier, challenge]:
		for bad in ["+", "/", "="]:
			_check(not bad in s, "PKCE value contains '%s' — not base64url" % bad)
	_check(verifier.length() >= 43 and verifier.length() <= 128,
		"PKCE verifier is outside RFC 7636's 43-128 characters")
	_check(auth._challenge_for(verifier) == challenge,
		"PKCE challenge is not deterministic for one verifier")
	_check(auth._make_verifier() != verifier, "PKCE verifier is not random")
	# Parsing the redirect back off the wire is the other half that has to work.
	_check(auth._query_value("GET /?code=abc%2Fd&state=1 HTTP/1.1", "code") == "abc/d",
		"the loopback redirect parser mangles the auth code")
	_check(auth._query_value("GET /favicon.ico HTTP/1.1", "code").is_empty(),
		"the loopback redirect parser invents a code from an unrelated request")
	auth.free()
