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
	_test_save_entry_shape_matches_registry()
	_test_stale_items_are_cleaned()
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

## A loaded save is dropped straight into Net.players, so it has to carry every
## key the registry expects — a missing one is a crash the first time that
## player buys something.
func _test_save_entry_shape_matches_registry() -> void:
	var blank: Dictionary = Net._make_entry("Ada")
	var loaded: Dictionary = await SaveStore.load_save("nobody", "Ada")
	var entry: Dictionary = loaded["entry"]
	for key in blank.keys():
		if key == "user_id":
			continue  # attached by _server_register, not by the store
		_check(entry.has(key), "a loaded save is missing '%s'" % key)
	_check(not loaded["ok"], "load_save claimed success with no database")

## The catalogue changes between builds. A row still holding an item that no
## longer exists must not travel into a live bag.
func _test_stale_items_are_cleaned() -> void:
	var real := ""
	for id in ItemDb.ITEMS:
		real = id
		break
	var cleaned: Dictionary = SaveStore._clean_items({
		"definitely_not_an_item": 4,
		real: 2,
		"negative": -1,
	})
	_check(not cleaned.has("definitely_not_an_item"),
		"_clean_items kept an item ItemDb no longer knows")
	_check(not cleaned.has("negative"), "_clean_items kept a non-positive count")
	if not real.is_empty():
		_check(cleaned.get(real) == 2, "_clean_items dropped a valid item")

## An API blip must not eat somebody's afternoon. A write that fails goes back
## on the queue rather than vanishing.
func _test_failed_write_is_requeued() -> void:
	var entry := {"name": "Ada", "kills": 0, "deaths": 0, "gold": 50, "items": {}}
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
