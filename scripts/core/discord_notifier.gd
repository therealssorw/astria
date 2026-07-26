extends Node
## Autoload: Discord. Posts "so-and-so just joined" to a Discord webhook, so
## people can see there is somebody on and come and play with them.
##
## SERVER ONLY, and silent unless a webhook is configured. A client never posts
## anything: it would be telling Discord about its own screen, and it would put
## the webhook URL in every player's copy of the game.
##
## THE URL IS A SECRET AND IS NOT IN THIS REPO. Anyone holding it can post to
## the channel as the server, and this repository is public — so it is read at
## runtime, in this order:
##
##   1. the `ASTRIA_DISCORD_WEBHOOK` environment variable
##   2. `discord_webhook.txt` beside the server executable (or in the project
##      folder when running from the editor), which .gitignore keeps out of git
##
## Neither present means no webhook, which is not an error: the tests, every
## player's client and anybody's local dev server all run that way and post
## nothing. Rotate the URL in Discord if it ever does get committed.

const ENV_VAR := "ASTRIA_DISCORD_WEBHOOK"
const FILE_NAME := "discord_webhook.txt"
## Discord's own limit is generous, but a join loop (a client reconnecting in a
## crash cycle) must not turn into a flood: posts wait their turn behind this.
const MIN_GAP := 2.0
## Dropped rather than queued past this — if that many joins are backed up, the
## channel does not need every one of them.
const MAX_QUEUED := 20
## Discord's own blurple, so the embed's stripe reads as part of the client
## rather than as something shouting from a bot.
const EMBED_COLOR := 0x5865F2

var _url := ""
var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _cooldown := 0.0
var _busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_url = _read_url()
	if _url == "":
		return
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	set_process(true)

## Is there anywhere to post? False on every client and on any server that was
## never given a URL — callers do not have to check, this is for tests and logs.
func is_configured() -> bool:
	return _url != ""

## A player just joined. Called by Net; posts only from the DEDICATED server —
## the one everybody actually plays on.
##
## That last condition is not fussiness. A listen server is somebody's own
## machine: playing from the editor, a LAN game, and every headless integration
## test in `tests/` all host one and register a player, and without this the
## channel would fill up with joins nobody can act on — and a test run would post
## to a real Discord channel every time it was run.
func post_join(username: String, online: Array) -> void:
	if _url == "" or not multiplayer.is_server() or not Net.is_dedicated:
		return
	if _queue.size() >= MAX_QUEUED:
		return
	_queue.append(build_join_payload(username, online,
			Time.get_unix_time_from_system()))

## The message itself, kept separate from the sending so it can be checked
## without a network — see tests/test_discord.tscn.
##
## `<t:unix:F>` and `<t:unix:R>` are Discord's own timestamp markup: every
## reader sees the join time in THEIR timezone, and the relative one keeps
## counting ("3 minutes ago") without the message being edited. A UTC string
## baked in here would be right for nobody but the server.
static func build_join_payload(username: String, online: Array,
		unix_time: float) -> Dictionary:
	var stamp := int(unix_time)
	var names: Array[String] = []
	for n in online:
		var text := str(n).strip_edges()
		if text != "":
			names.append(text)
	var count := names.size()
	# no peer id: it is a number off the wire that means nothing to somebody
	# reading the channel deciding whether to come and play
	var fields := [
		{"name": "Joined", "value": "<t:%d:F>\n<t:%d:R>" % [stamp, stamp], "inline": false},
		{"name": "Players online", "value": str(count), "inline": true},
	]
	if count > 0:
		# who is actually on, which is the whole point: somebody deciding whether
		# to join wants to know who they would be joining
		fields.append({"name": "Who's on", "value": ", ".join(names), "inline": false})
	return {
		"username": "Astria",
		"embeds": [{
			"title": "%s joined the server" % username,
			"description": "There's someone playing — hop in.",
			"color": EMBED_COLOR,
			"fields": fields,
			"timestamp": Time.get_datetime_string_from_unix_time(stamp, true) + "Z",
		}],
	}

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _busy or _cooldown > 0.0 or _queue.is_empty():
		return
	_send(_queue.pop_front())

func _send(payload: Dictionary) -> void:
	var err := _http.request(_url, ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		push_warning("Discord: could not start the request (%d)" % err)
		return
	_busy = true
	_cooldown = MIN_GAP

## A webhook that fails is a webhook that fails: it is a notification, not game
## state, so it is logged and forgotten rather than retried into a loop.
func _on_request_completed(result: int, code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		push_warning("Discord: webhook post failed (result %d, HTTP %d)" % [result, code])

func _read_url() -> String:
	var from_env := OS.get_environment(ENV_VAR).strip_edges()
	if from_env != "":
		return from_env
	for dir: String in [OS.get_executable_path().get_base_dir(),
			ProjectSettings.globalize_path("res://")]:
		var path := dir.path_join(FILE_NAME)
		if FileAccess.file_exists(path):
			var text := FileAccess.get_file_as_string(path).strip_edges()
			if text != "":
				return text
	return ""
