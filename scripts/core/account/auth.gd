extends Node
## Autoload `Auth`: the CLIENT half of accounts. Signing in with Discord, and
## keeping the resulting session alive across launches.
##
## Godot has no embedded browser, so this is the standard native-app dance
## (OAuth 2.0 authorization code + PKCE, RFC 7636):
##
##   1. Make a random `verifier`, and its SHA-256 `challenge`.
##   2. Listen on 127.0.0.1:REDIRECT_PORT.
##   3. Open the system browser at Supabase's /authorize with provider=discord
##      and the challenge, asking it to redirect back to that loopback port.
##   4. Discord authenticates the player; Supabase redirects the browser to
##      http://127.0.0.1:PORT/?code=... — which lands in our listener.
##   5. Trade the code + verifier for an access token and a refresh token.
##
## The challenge/verifier split is the point: the code arrives over plain
## loopback HTTP, but it is worthless without the verifier, which never left
## this process. Another program on the machine that races us to the port still
## cannot spend the code.
##
## The refresh token is stored in `user://` so the next launch signs in
## silently and auto-joins — the "you're logged in, so you just play" path.
## The ACCESS token is what gets handed to the game server; it is short-lived
## and the server verifies it with Supabase rather than believing it.
##
## Nothing here is trusted by the game server. This file only obtains proof of
## identity; `save_store.gd` on the server decides what that identity owns.

## A sign-in attempt finished. `ok` false means `message` explains why.
signal login_finished(ok: bool, message: String)
## Progress text while the browser is open, for the menu's status line.
signal login_status(message: String)
## The session ended (sign out, or a refresh token that no longer works).
signal logged_out

const SESSION_PATH := "user://account.cfg"

## Fixed, because Supabase only redirects to URLs on the project's allow-list
## and a random port could not be listed there. Must be registered in the
## dashboard as http://127.0.0.1:27045 (see docs/accounts.md).
const REDIRECT_PORT := 27045
const REDIRECT_URI := "http://127.0.0.1:27045"

const LOGIN_TIMEOUT := 180.0   # how long we hold the port waiting for a browser
const REFRESH_MARGIN := 120.0  # renew this long before the token actually dies

var user_id := ""        # Supabase auth.users uuid — the account's real name
var username := ""       # what Discord calls them; the server re-reads this
var avatar_url := ""
var access_token := ""

var _refresh_token := ""
var _expires_at := 0.0   # unix seconds
var _busy := false

func _ready() -> void:
	_load_session()

func logged_in() -> bool:
	return not access_token.is_empty() and not user_id.is_empty()

## True when a previous launch left us a refresh token, so the menu knows to
## try a silent sign-in before drawing a "Log in" button.
func has_saved_session() -> bool:
	return not _refresh_token.is_empty()

# ---------------- interactive sign-in ----------------

## Opens the browser and waits for the redirect. Emits `login_finished`.
func login_with_discord() -> void:
	if _busy:
		return
	if not Supabase.configured():
		login_finished.emit(false, "This build has no account service configured.")
		return
	_busy = true

	var verifier := _make_verifier()
	var listener := TCPServer.new()
	if listener.listen(REDIRECT_PORT, "127.0.0.1") != OK:
		_busy = false
		login_finished.emit(false, "Port %d is in use — is the game already open?" % REDIRECT_PORT)
		return

	var authorize := "%s/auth/v1/authorize?provider=discord&redirect_to=%s&code_challenge=%s&code_challenge_method=s256" % [
		Supabase.url(),
		REDIRECT_URI.uri_encode(),
		_challenge_for(verifier),
	]
	login_status.emit("Waiting for Discord in your browser...")
	OS.shell_open(authorize)

	var code := await _await_redirect(listener)
	listener.stop()
	if code.is_empty():
		_busy = false
		login_finished.emit(false, "Sign-in was cancelled or timed out.")
		return

	login_status.emit("Signing in...")
	var res: Dictionary = await Supabase.post_json(
		"/auth/v1/token?grant_type=pkce",
		Supabase.auth_headers(),
		{"auth_code": code, "code_verifier": verifier})
	_busy = false
	if not res["ok"]:
		login_finished.emit(false, res["error"])
		return
	_apply_session(res["data"])
	login_finished.emit(true, "Signed in as %s." % username)

## Reuse the stored refresh token. This is what makes a returning player go
## straight into the world without seeing a login screen at all.
func restore_session() -> bool:
	if _refresh_token.is_empty() or _busy:
		return false
	_busy = true
	login_status.emit("Signing in...")
	var res: Dictionary = await Supabase.post_json(
		"/auth/v1/token?grant_type=refresh_token",
		Supabase.auth_headers(),
		{"refresh_token": _refresh_token})
	_busy = false
	if not res["ok"]:
		# A refresh token that Supabase no longer honours is dead for good —
		# keeping it would retry-and-fail on every single launch.
		_clear_session()
		return false
	_apply_session(res["data"])
	return true

## Called before handing the token to the game server: a token that expires
## mid-handshake would be rejected for no reason the player could understand.
func fresh_token() -> String:
	if not logged_in():
		return ""
	if Time.get_unix_time_from_system() < _expires_at - REFRESH_MARGIN:
		return access_token
	if await restore_session():
		return access_token
	return ""

func log_out() -> void:
	if logged_in():
		# Best-effort: revoking server-side is polite, but a failure here must
		# not stop us forgetting the session locally.
		Supabase.post_json("/auth/v1/logout", Supabase.auth_headers(access_token), {})
	_clear_session()
	logged_out.emit()

# ---------------- the loopback redirect ----------------

## Accept exactly one browser connection and pull `code` out of its request
## line. Returns "" on timeout, on a user who closed the tab, or on Supabase
## redirecting back with an error instead of a code.
func _await_redirect(listener: TCPServer) -> String:
	var deadline := Time.get_ticks_msec() + int(LOGIN_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not listener.is_connection_available():
			await get_tree().process_frame
			continue
		var conn := listener.take_connection()
		var request := await _read_request_line(conn)
		var code := _query_value(request, "code")
		var body := "You're signed in. You can close this tab and go back to Astria." \
			if not code.is_empty() else "Sign-in failed. Close this tab and try again in Astria."
		_reply(conn, body)
		if not code.is_empty():
			return code
		# Browsers routinely also ask for /favicon.ico on the same port; that is
		# not the redirect, so keep waiting rather than calling it a failure.
	return ""

func _read_request_line(conn: StreamPeerTCP) -> String:
	var deadline := Time.get_ticks_msec() + 3000
	var buf := ""
	while Time.get_ticks_msec() < deadline:
		conn.poll()
		if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var available := conn.get_available_bytes()
		if available > 0:
			buf += conn.get_utf8_string(available)
			if "\r\n" in buf:
				return buf.get_slice("\r\n", 0)
		await get_tree().process_frame
	return buf

func _reply(conn: StreamPeerTCP, message: String) -> void:
	var html := "<!doctype html><meta charset=utf-8><title>Astria</title>" \
		+ "<body style=\"background:#12131a;color:#e6e6ee;font:16px system-ui;" \
		+ "display:flex;align-items:center;justify-content:center;height:100vh\">" \
		+ "<p>" + message + "</p>"
	var payload := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" \
		+ "Content-Length: %d\r\nConnection: close\r\n\r\n%s" % [html.to_utf8_buffer().size(), html]
	conn.put_data(payload.to_utf8_buffer())
	conn.poll()
	conn.disconnect_from_host()

## Pull one parameter out of a raw "GET /?a=1&b=2 HTTP/1.1" request line.
func _query_value(request_line: String, key: String) -> String:
	var path := request_line.get_slice(" ", 1)
	if not "?" in path:
		return ""
	for pair in path.substr(path.find("?") + 1).split("&"):
		if pair.begins_with(key + "="):
			return pair.substr(key.length() + 1).uri_decode()
	return ""

# ---------------- PKCE ----------------

func _make_verifier() -> String:
	return _b64url(Crypto.new().generate_random_bytes(64))

func _challenge_for(verifier: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verifier.to_utf8_buffer())
	return _b64url(ctx.finish())

## base64url without padding — what RFC 7636 asks for, and what Supabase
## compares against. Plain base64 would fail the comparison AND corrupt the
## query string, since "+" means a space in a URL.
func _b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

# ---------------- session storage ----------------

func _apply_session(data: Variant) -> void:
	if not data is Dictionary:
		return
	var d: Dictionary = data
	access_token = str(d.get("access_token", ""))
	_refresh_token = str(d.get("refresh_token", _refresh_token))
	_expires_at = Time.get_unix_time_from_system() + float(d.get("expires_in", 3600))
	var user: Dictionary = d.get("user", {}) if d.get("user") is Dictionary else {}
	user_id = str(user.get("id", user_id))
	var meta: Dictionary = user.get("user_metadata", {}) if user.get("user_metadata") is Dictionary else {}
	# Discord's display name first, then the handle; `full_name` is what
	# Supabase fills from Discord's global_name.
	for key in ["full_name", "name", "custom_claims", "preferred_username"]:
		var v: Variant = meta.get(key)
		if v is String and not (v as String).is_empty():
			username = v
			break
	avatar_url = str(meta.get("avatar_url", ""))
	_save_session()

func _load_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	_refresh_token = cfg.get_value("account", "refresh_token", "")
	user_id = cfg.get_value("account", "user_id", "")
	username = cfg.get_value("account", "username", "")

func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("account", "refresh_token", _refresh_token)
	cfg.set_value("account", "user_id", user_id)
	cfg.set_value("account", "username", username)
	cfg.save(SESSION_PATH)

func _clear_session() -> void:
	access_token = ""
	_refresh_token = ""
	user_id = ""
	username = ""
	avatar_url = ""
	_expires_at = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	var cfg := ConfigFile.new()
	cfg.save(SESSION_PATH)
