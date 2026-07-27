extends Node
## Autoload `Supabase`: the thin HTTP layer everything else in `account/` sits on.
## It knows the project URL and the two keys, and nothing about the game.
##
## THE TWO KEYS ARE NOT INTERCHANGEABLE.
##   - ANON key is public by design. It is compiled into every build, and can
##     only ever do what row-level security lets an anonymous caller do (which,
##     for our tables, is "read your own row"). The client uses it to log in.
##   - SERVICE key bypasses RLS entirely — it is a master password for the
##     database. It must NEVER reach a player's machine. It is read from the
##     environment (ASTRIA_SUPABASE_SERVICE_KEY) on the dedicated server only,
##     and `service_key()` refuses to return it on a client build.
##
## Both can be overridden by environment variables, which is how a test or a
## staging box points at a different project without a rebuild.

const PROJECT_URL := "https://byckhykwklzjbfratzds.supabase.co"

## Public, ships in the client. Safe to commit — RLS is what actually guards
## the data. Override with ASTRIA_SUPABASE_ANON_KEY.
const ANON_KEY := ""

const ENV_URL := "ASTRIA_SUPABASE_URL"
const ENV_ANON := "ASTRIA_SUPABASE_ANON_KEY"
const ENV_SERVICE := "ASTRIA_SUPABASE_SERVICE_KEY"

const TIMEOUT := 15.0

func url() -> String:
	var u := OS.get_environment(ENV_URL)
	return u.rstrip("/") if not u.is_empty() else PROJECT_URL

func anon_key() -> String:
	var k := OS.get_environment(ENV_ANON)
	return k if not k.is_empty() else ANON_KEY

## The server's key, or "" on any build that is not the dedicated server.
## Guarded twice on purpose: a client build should not be able to read this
## even if someone sets the variable on their own machine, because the server
## is the only thing that is ever supposed to write a save.
func service_key() -> String:
	if not Net.should_run_dedicated() and not Net.is_dedicated:
		return ""
	return OS.get_environment(ENV_SERVICE)

func configured() -> bool:
	return not anon_key().is_empty()

# ---------------- requests ----------------
#
# Every call is a coroutine returning the same shape, so callers never have to
# think about HTTPRequest lifetimes or distinguish "the network died" from
# "the server said no":
#   { ok: bool, code: int, data: Variant, error: String }

## Authenticate as a logged-in user (or anonymously, with token = "").
func auth_headers(token := "") -> PackedStringArray:
	var h := PackedStringArray([
		"apikey: " + anon_key(),
		"Content-Type: application/json",
	])
	h.append("Authorization: Bearer " + (token if not token.is_empty() else anon_key()))
	return h

## Authenticate as the server. Empty on a client build — callers must check.
func service_headers(extra := PackedStringArray()) -> PackedStringArray:
	var key := service_key()
	var h := PackedStringArray([
		"apikey: " + key,
		"Authorization: Bearer " + key,
		"Content-Type: application/json",
	])
	h.append_array(extra)
	return h

func get_json(path: String, headers: PackedStringArray) -> Dictionary:
	return await request(path, headers, HTTPClient.METHOD_GET, "")

func post_json(path: String, headers: PackedStringArray, body: Variant) -> Dictionary:
	return await request(path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func patch_json(path: String, headers: PackedStringArray, body: Variant) -> Dictionary:
	return await request(path, headers, HTTPClient.METHOD_PATCH, JSON.stringify(body))

## `path` is appended to the project URL, e.g. "/auth/v1/user".
func request(path: String, headers: PackedStringArray, method: int, body: String) -> Dictionary:
	if not configured():
		return _fail("Supabase is not configured (no anon key).")

	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var err := http.request(url() + path, headers, method, body)
	if err != OK:
		http.queue_free()
		return _fail("Could not reach the account service.")

	var res: Array = await http.request_completed
	http.queue_free()

	var result := int(res[0])
	var code := int(res[1])
	var raw := (res[3] as PackedByteArray).get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail("Could not reach the account service (%d)." % result)

	var data: Variant = null
	if not raw.strip_edges().is_empty():
		data = JSON.parse_string(raw)
		if data == null:
			data = raw
	if code < 200 or code >= 300:
		return {"ok": false, "code": code, "data": data, "error": _message(data, code)}
	return {"ok": true, "code": code, "data": data, "error": ""}

## Supabase reports errors in a few different shapes depending on which
## sub-service answered; pull out whichever one is present so the menu can show
## a real sentence instead of a status code.
func _message(data: Variant, code: int) -> String:
	if data is Dictionary:
		for key in ["error_description", "msg", "message", "error", "hint"]:
			var v: Variant = data.get(key)
			if v is String and not (v as String).is_empty():
				return v
	return "The account service refused the request (%d)." % code

func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": 0, "data": null, "error": message}
