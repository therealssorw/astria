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

func _run() -> void:
	await get_tree().process_frame
	var lines: Dictionary = DialogData.get_conversation("blacksmith").get("lines", {})
	var greeting := str(lines["greeting"]["text"])
	var repair := str(lines["repair"]["text"])

	if not _check(DialogSystem.start("blacksmith"), "the blacksmith has no conversation"):
		return
	_skip_typing()
	if not _check(_body() == greeting, "the opener should be the greeting, got '%s'" % _body()):
		return

	# down a branch: its own text, typed fresh
	if not _check(_pick("repair my gear"), "the greeting has no repair answer"):
		return
	_skip_typing()
	if not _check(_body() == repair, "the branch should say its own line, got '%s'" % _body()):
		return

	# ...and back out of it. "repair" is a plain goto back to "greeting", which
	# has been read, so the box must KEEP the repair text and just offer the
	# greeting's choices again
	if not _check(_pick("Continue"), "a plain goto should offer one Continue button"):
		return
	if not _check(_body() == repair,
			"looping back retyped the line instead of keeping the reply: '%s'" % _body()):
		return
	if not _check(_answer_count() >= 2,
			"looping back should bring the greeting's choices back, got %d" % _answer_count()):
		return
	# and they really are the greeting's, not the branch's
	if not _check(_has_answer("for sale"), "the choices are not the greeting's"):
		return

	# a FRESH conversation says everything again, opener included
	DialogSystem.close()
	if not _check(DialogSystem.start("blacksmith"), "could not reopen the conversation"):
		return
	_skip_typing()
	if not _check(_body() == greeting,
			"reopening should type the greeting again, got '%s'" % _body()):
		return
	DialogSystem.close()

	print("DIALOGTEST RESULT=PASS")
	get_tree().quit(0)

## The box types over several frames; every test here is about which line is on
## screen rather than the typing, so each one is skipped the way a player would.
func _skip_typing() -> void:
	DialogSystem._finish_typing()

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
