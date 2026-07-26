extends Node
## Headless test for the dialog box's line flow. Run:
##   godot --headless --path . res://tests/test_dialog.tscn
## Prints DIALOGTEST RESULT=PASS/FAIL and exits with the matching code.
##
## Needs no server: a conversation is purely local (see "NPC dialog" in
## CLAUDE.md), so this drives the autoload directly.
##
## What it is really guarding: a `goto` that LOOPS BACK to a line you have
## already read must not say it again. Every branching conversation in the game
## ends its side-branches by returning to the question they came from, so
## getting this wrong retypes the same paragraph on every answer — and wipes the
## reply you actually asked for off the screen as you finish reading it.

func _ready() -> void:
	_run()

var _failed := false

func _fail(msg: String) -> void:
	_failed = true
	print("DIALOGTEST RESULT=FAIL (%s)" % msg)
	get_tree().quit(1)

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

## The King is the branching conversation: his three questions all loop back to
## "hideout", so he is what the rule above is walked on. (The blacksmith used to
## be, until his conversation was cut down to "buy" and "goodbye" — a
## conversation with no branch in it cannot test a branch.) None of the answers
## on the way fires anything that needs a server: the one that carries
## `finish_quest` is dropped by QuestSystem because this player is on no quest.
const CONV := "king"

func _run() -> void:
	await get_tree().process_frame
	var lines: Dictionary = DialogData.get_conversation(CONV).get("lines", {})
	var greeting := _last_page(str(lines["greeting"]["text"]))
	var rumors := _last_page(str(lines["rumors"]["text"]))

	if not _check(DialogSystem.start(CONV), "the King has no conversation"):
		return
	_skip_typing()
	if not _check(_body() == greeting, "the opener should be the greeting, got '%s'" % _body()):
		return

	# down to the line the branches hang off
	if not _check(_pick("defeated the bandits"), "the greeting has no way on"):
		return
	_skip_typing()
	if not _check(_pick("want to help"), "the caravan line has no way on"):
		return
	_skip_typing()
	var hideout := _body()

	# down a branch: its own text, typed fresh
	if not _check(_pick("Where do I find them"), "the hideout has no rumors answer"):
		return
	_skip_typing()
	if not _check(_body() == rumors, "the branch should say its own line, got '%s'" % _body()):
		return

	# ...and back out of it. "rumors" is a plain goto back to "hideout", which
	# has been read, so the box must KEEP the rumors text and just offer the
	# hideout's choices again
	if not _check(_pick("Continue"), "a plain goto should offer one Continue button"):
		return
	if not _check(_body() == rumors,
			"looping back retyped the line instead of keeping the reply: '%s'" % _body()):
		return
	if not _check(_body() != hideout, "looping back should not have retyped the question"):
		return
	if not _check(_answer_count() >= 2,
			"looping back should bring the hideout's choices back, got %d" % _answer_count()):
		return
	# and they really are the hideout's, not the branch's
	if not _check(_has_answer("I'll do it now"), "the choices are not the hideout's"):
		return

	# a FRESH conversation says everything again, opener included
	DialogSystem.close()
	if not _check(DialogSystem.start(CONV), "could not reopen the conversation"):
		return
	_skip_typing()
	if not _check(_body() == greeting,
			"reopening should type the greeting again, got '%s'" % _body()):
		return
	DialogSystem.close()

	if not _blacksmith():
		return

	print("DIALOGTEST RESULT=PASS")
	get_tree().quit(0)

## The shopkeeper's own conversation is two lines long, so it gets a smoke test
## rather than a walk: it opens, and the answer that ends it really does close
## the box. (That the "buy" answer reaches a SHOP is test_shop's job.)
func _blacksmith() -> bool:
	if not _check(DialogSystem.start("blacksmith"), "the blacksmith has no conversation"):
		return false
	_skip_typing()
	# He opens on his GIFT while the armor is still outstanding — which is what a
	# fresh player meets, and what this test sees, because "outstanding" is the
	# server's record and there is no server here. Taking it comes back to the
	# greeting, so the way out is one line further in than it used to be.
	if _pick("Thank you"):
		_skip_typing()
	if not _check(_pick("leave now"), "the blacksmith has no way out of the conversation"):
		return false
	_skip_typing()
	# a line that ends the conversation gets one button, and it says "Goodbye."
	if not _check(_pick("Goodbye"), "the farewell should offer one closing button"):
		return false
	if not _check(not DialogSystem.is_open(),
			"walking off the last line should have closed the box"):
		return false
	return true

## The box types over several frames; every test here is about which line is on
## screen rather than the typing, so each one is skipped the way a player would.
## A line broken into PAGES with "\n" is skipped page by page to its end, which
## is where its answers appear — so what is on screen afterwards is its LAST
## page, not the whole text.
func _skip_typing() -> void:
	for _i in 16:
		DialogSystem._finish_typing()
		if DialogSystem._page >= DialogSystem._pages.size() - 1:
			return
		DialogSystem._next_page()

## The part of a line that is still on screen once it has finished saying it.
func _last_page(text: String) -> String:
	var pages := PackedStringArray()
	for part in text.split("\n"):
		var trimmed := str(part).strip_edges()
		if trimmed != "":
			pages.append(trimmed)
	return pages[pages.size() - 1] if pages.size() > 0 else ""

func _body() -> String:
	return str(DialogSystem._body.text)

func _answer_count() -> int:
	return DialogSystem._answers.get_child_count()

func _has_answer(fragment: String) -> bool:
	for b in DialogSystem._answers.get_children():
		if b is Button and str((b as Button).text).contains(fragment):
			return true
	return false

## Press the answer whose label contains `fragment`.
func _pick(fragment: String) -> bool:
	for b in DialogSystem._answers.get_children():
		if b is Button and str((b as Button).text).contains(fragment):
			(b as Button).pressed.emit()
			return true
	return false
