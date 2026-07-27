extends Node
## Autoload `SaveStore`: the SERVER half of accounts. Turns "this peer handed
## me a token" into "this peer owns 340 gold and two swords", and writes that
## back when it changes.
##
## Everything here runs on the dedicated server ONLY. It holds the service key,
## which bypasses row-level security, so a client that somehow got this code to
## run would still get nothing — `Supabase.service_key()` is empty off the
## server, and every call below bails without it.
##
## Server authority, restated for persistence: the client's token proves WHO it
## is and nothing else. It never sends its gold, its bag or its kill count, and
## the server never reads those from anything but the database. A patched
## client can lie about its identity only as far as it can forge a Supabase
## JWT, which it cannot.
##
## Writes are debounced. A player picking up gold every few seconds should not
## be a database round trip every few seconds, and a crash losing the last few
## seconds of coins is a far smaller problem than hammering the API. Anything
## that must not be lost — a disconnect — flushes immediately.

## A save finished writing. Mostly for the tests.
signal save_flushed(user_id: String)

const FLUSH_INTERVAL := 10.0

var _dirty := {}      # user_id -> entry Dictionary (a reference into Net.players)
var _in_flight := {}  # user_id -> true while a write is out, so we don't overlap
var _accum := 0.0

func available() -> bool:
	return Supabase.configured() and not Supabase.service_key().is_empty()

func _process(delta: float) -> void:
	if _dirty.is_empty():
		return
	_accum += delta
	if _accum < FLUSH_INTERVAL:
		return
	_accum = 0.0
	for user_id in _dirty.keys():
		_flush(user_id)

# ---------------- identity ----------------

## Ask Supabase who this token belongs to. Returns
## { ok, user_id, username, avatar_url, discord_id, error }.
##
## This is the whole trust boundary. We deliberately do NOT decode the JWT
## ourselves: verifying a signature by hand is exactly the kind of thing that
## is subtly wrong for years. Supabase can answer "is this real" definitively,
## so ask it.
func verify(token: String) -> Dictionary:
	if token.strip_edges().is_empty():
		return {"ok": false, "error": "No account token was sent."}
	if not Supabase.configured():
		return {"ok": false, "error": "This server has no account service configured."}

	var res: Dictionary = await Supabase.get_json("/auth/v1/user", Supabase.auth_headers(token))
	if not res["ok"]:
		return {"ok": false, "error": "Your sign-in is no longer valid — log in again."}
	var user: Dictionary = res["data"] if res["data"] is Dictionary else {}
	var id := str(user.get("id", ""))
	if id.is_empty():
		return {"ok": false, "error": "The account service returned no user."}

	var meta: Dictionary = user.get("user_metadata", {}) if user.get("user_metadata") is Dictionary else {}
	var name := ""
	for key in ["full_name", "name", "preferred_username"]:
		var v: Variant = meta.get(key)
		if v is String and not (v as String).is_empty():
			name = v
			break
	return {
		"ok": true,
		"error": "",
		"user_id": id,
		"username": name,
		"avatar_url": str(meta.get("avatar_url", "")),
		"discord_id": str(meta.get("provider_id", meta.get("sub", ""))),
	}

# ---------------- loading ----------------

## Everything this account had when it last logged out, keyed the way an entry
## is: `{ ok, error, save, new_account }`, with `save` ready for
## `NetRegistry.apply_save`. A brand-new account comes back as an empty save
## rather than an error — signing up for the first time is not a failure.
##
## The cleaning is NetRegistry's job, not this file's: what a saved bag or a
## saved hotbar may contain is a fact about a player, and there is exactly one
## owner of that.
func load_save(user_id: String) -> Dictionary:
	if not available():
		return {"ok": false, "error": "This server cannot reach the save database.", "save": {}}

	var res: Dictionary = await Supabase.get_json(
		"/rest/v1/player_saves?select=%s&user_id=eq.%s" % [",".join(_columns()), user_id],
		Supabase.service_headers())
	if not res["ok"]:
		return {"ok": false, "error": "Could not load your save — try again shortly.", "save": {}}

	var rows: Array = res["data"] if res["data"] is Array else []
	if rows.is_empty():
		return {"ok": true, "error": "", "save": {}, "new_account": true}

	var row: Dictionary = rows[0]
	var save := {}
	for key: String in NetRegistry.PERSISTED:
		var column := _column(key)
		if row.has(column) and row[column] != null:
			save[key] = row[column]
	return {"ok": true, "error": "", "save": save}

## Entry field -> its column. They match apart from gold, which is `coins` in
## the database because that is what the site and the leaderboard call it.
const COLUMNS := {"gold": "coins"}

func _column(key: String) -> String:
	return str(COLUMNS.get(key, key))

func _columns() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in NetRegistry.PERSISTED:
		out.append(_column(key))
	return out

# ---------------- writing ----------------

## Record the player's profile so the site/dashboard has something human to
## look at, and so a name change on Discord follows them here.
func upsert_profile(user_id: String, username: String, discord_id: String, avatar_url: String) -> void:
	if not available():
		return
	var res: Dictionary = await Supabase.post_json(
		"/rest/v1/profiles",
		Supabase.service_headers(PackedStringArray(["Prefer: resolution=merge-duplicates,return=minimal"])),
		{
			"user_id": user_id,
			"username": username,
			"discord_id": discord_id,
			"avatar_url": avatar_url,
			"updated_at": Time.get_datetime_string_from_system(true, true) + "Z",
		})
	if not res["ok"]:
		push_warning("[SaveStore] profile write failed: %s" % res["error"])

## Queue this entry to be written. Cheap — call it from anywhere that changes
## gold, items, kills or deaths.
func mark_dirty(user_id: String, entry: Dictionary) -> void:
	if user_id.is_empty() or not available():
		return
	_dirty[user_id] = entry

## Write now and wait for it. Used on disconnect, where "later" never comes.
func flush_now(user_id: String) -> void:
	if not _dirty.has(user_id):
		return
	await _flush(user_id)

func _flush(user_id: String) -> void:
	if _in_flight.get(user_id, false):
		return  # a write is already out; the next tick will pick up the newer state
	# No service key means this build cannot write a save at all. Leave it on
	# the queue rather than spending a round trip to be told 401 — and, since
	# the anon key now ships in the client, this is also what stops a client
	# build (or a test) from reaching out to the real API by accident.
	if not available():
		return
	var entry: Dictionary = _dirty.get(user_id, {})
	if entry.is_empty():
		_dirty.erase(user_id)
		return
	_dirty.erase(user_id)
	_in_flight[user_id] = true

	var row := {"user_id": user_id,
			"updated_at": Time.get_datetime_string_from_system(true, true) + "Z"}
	var save := NetRegistry.snapshot(entry)
	for key: Variant in save:
		row[_column(str(key))] = save[key]

	var res: Dictionary = await Supabase.post_json(
		"/rest/v1/player_saves",
		Supabase.service_headers(PackedStringArray(["Prefer: resolution=merge-duplicates,return=minimal"])),
		row)
	_in_flight.erase(user_id)
	if not res["ok"]:
		# Put it back: losing a save because the API blipped would be the one
		# bug players actually notice.
		push_warning("[SaveStore] save write failed for %s: %s" % [user_id, res["error"]])
		if not _dirty.has(user_id):
			_dirty[user_id] = entry
		return
	save_flushed.emit(user_id)
