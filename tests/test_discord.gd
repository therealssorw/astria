extends Node
## Headless test for the Discord join notification. Run:
##   godot --headless --path . res://tests/test_discord.tscn
## Prints DISCORDTEST RESULT=PASS/FAIL and exits with the matching code.
##
## POSTS NOTHING. It checks the message that WOULD be sent and the rule about
## when one is sent at all — a test that actually hit the webhook would put a
## line in a real Discord channel every time anybody ran the suite.
##
## The second half is the one that matters: a listen server (the editor, a LAN
## game, every other test in this folder) must never post. Only the dedicated
## server everybody plays on does.

const NOTIFIER := preload("res://scripts/core/discord_notifier.gd")
## A fixed moment, so the timestamp markup can be checked exactly.
const WHEN := 1750000000.0

func _ready() -> void:
	_run()

func _fail(msg: String) -> void:
	print("DISCORDTEST RESULT=FAIL (%s)" % msg)
	get_tree().quit(1)

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

func _run() -> void:
	await get_tree().process_frame
	if not _payload():
		return
	if not _never_from_a_listen_server():
		return
	print("DISCORDTEST RESULT=PASS")
	get_tree().quit(0)

func _payload() -> bool:
	var roster := ["Marth", "Bram", "Wanderer"]
	var payload := NOTIFIER.build_join_payload("Marth", roster, WHEN)

	# it has to survive being sent: Discord gets JSON, not a Dictionary
	var json := JSON.stringify(payload)
	if not _check(JSON.parse_string(json) != null, "the payload is not valid JSON"):
		return false

	var embeds: Array = payload.get("embeds", [])
	if not _check(embeds.size() == 1, "expected one embed, got %d" % embeds.size()):
		return false
	var embed: Dictionary = embeds[0]
	if not _check(str(embed.get("title", "")).contains("Marth"),
			"the title should name who joined, got '%s'" % embed.get("title", "")):
		return false

	var fields := _fields(embed)
	# Discord's own timestamp markup, so every reader sees their OWN timezone
	# and the relative one keeps counting without the message being edited
	var joined := str(fields.get("Joined", ""))
	if not _check(joined.contains("<t:%d:F>" % int(WHEN)),
			"no absolute timestamp in '%s'" % joined):
		return false
	if not _check(joined.contains("<t:%d:R>" % int(WHEN)),
			"no relative timestamp in '%s'" % joined):
		return false

	if not _check(str(fields.get("Players online", "")) == "3",
			"expected 3 online, got '%s'" % fields.get("Players online", "")):
		return false
	# who is on is the point of the message: someone deciding whether to join
	# wants to know who they would be joining
	for who in roster:
		if not _check(str(fields.get("Who's on", "")).contains(who),
				"the roster left out %s" % who):
			return false
	# a peer id is a number off the wire; the channel does not want it
	if not _check(not fields.has("Peer"), "the peer id is back in the message"):
		return false
	if not _check(int(embed.get("color", 0)) == NOTIFIER.EMBED_COLOR,
			"the embed lost its colour"):
		return false

	# an empty server (nobody registered yet) must not produce an empty roster
	# field — Discord rejects a field with a blank value outright
	var alone := NOTIFIER.build_join_payload("Marth", [], WHEN)
	var alone_fields := _fields(alone["embeds"][0])
	if not _check(not alone_fields.has("Who's on"),
			"an empty roster should leave the field out, not send it blank"):
		return false
	for name: String in alone_fields:
		if not _check(str(alone_fields[name]).strip_edges() != "",
				"field '%s' would be sent empty" % name):
			return false
	return true

## Nothing is queued unless this is the dedicated server. The test runs as a
## plain client (no server at all), which is the same "not the dedicated box"
## case as the editor and every other test in this folder.
func _never_from_a_listen_server() -> bool:
	if not _check(Discord._queue.is_empty(), "something was queued before the test began"):
		return false
	Discord.post_join("Marth", ["Marth"])
	if not _check(Discord._queue.is_empty(),
			"a non-dedicated run queued a webhook post — a test run would " \
			+ "have posted to a real Discord channel"):
		return false
	# and the same when a URL is definitely present, so this is not passing
	# merely because nothing was configured on this machine
	var was := Discord._url
	Discord._url = "https://example.invalid/webhook"
	Discord.post_join("Marth", ["Marth"])
	var stayed_empty := Discord._queue.is_empty()
	Discord._url = was
	return _check(stayed_empty,
			"with a URL set, a non-dedicated run still queued a post")

## The embed's fields as name -> value, which is how the checks above read.
func _fields(embed: Dictionary) -> Dictionary:
	var out := {}
	for f: Dictionary in embed.get("fields", []):
		out[str(f.get("name", ""))] = str(f.get("value", ""))
	return out
