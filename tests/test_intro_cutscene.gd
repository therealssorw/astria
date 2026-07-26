extends Node
## Headless integration test for the intro cutscene. Run:
##   godot --headless --path . res://tests/test_intro_cutscene.tscn
## Walks the whole sequence with a stand-in for the local pawn: black the
## instant the world arms it, the first line spoken over that black, the world
## fading up by itself afterwards, the second line once it is up, the player
## frozen the entire way and handed back at the end — and a later pawn (a
## respawn) not replaying any of it.
## Prints INTROTEST RESULT=PASS/FAIL and exits with the matching code.

## Wall-clock ceiling for any single step. The scene itself is sped up by
## TIME_SCALE, so this is only ever hit when something is actually stuck.
const STEP_TIMEOUT := 15.0
const TIME_SCALE := 8.0

var _fails: PackedStringArray = []

class FakePawn:
	extends Node
	var ui_open := false # the one thing the cutscene and the dialog box touch

func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	_run()

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)

func _done() -> void:
	Engine.time_scale = 1.0
	if _fails.is_empty():
		print("INTROTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		print("INTROTEST RESULT=FAIL (%s)" % ", ".join(_fails))
		get_tree().quit(1)

## Spin frames until `cond` holds, or give up. Wall clock, so a stalled step
## fails instead of hanging the run.
func _until(cond: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return false

func _run() -> void:
	var pawn := FakePawn.new()
	pawn.add_to_group("local_player")
	add_child(pawn)
	await get_tree().process_frame

	# the world scene arms it before it has drawn a frame
	IntroCutscene.arm()
	_check(IntroCutscene.darkness() == 1.0, "screen not black when the world armed it")
	# a cutscene is framed like one: bars top and bottom for the whole thing
	_check(Cinematic.is_framing(), "the cutscene did not put the bars up")
	var ok_bars := await _until(func() -> bool: return Cinematic.bar_amount() > 0.9)
	_check(ok_bars, "the cinematic bars never slid in")

	IntroCutscene.on_local_pawn_ready()
	var ok := await _until(func() -> bool: return DialogSystem.dialog_id == IntroCutscene.DARK_DIALOG)
	_check(ok, "first line never opened")
	_check(IntroCutscene.darkness() == 1.0, "screen not black while the first line plays")
	_check(pawn.ui_open, "player not frozen during the first line")

	# it types and advances itself — nothing presses a button here. The "\n" in
	# the line is a PAGE BREAK: the box types "Ugh.", wipes, and types the rest
	# in the same box, so the two halves are never on screen together and a
	# newline is never typed as one.
	var pages: Array = []
	var frames := 0
	while DialogSystem.dialog_id == IntroCutscene.DARK_DIALOG and frames < 4000:
		var shown: String = DialogSystem._body.text
		if shown != "" and not pages.has(shown):
			pages.append(shown)
		await get_tree().process_frame
		frames += 1
	_check(DialogSystem.dialog_id == "", "first line never advanced on its own")
	_check(pages.size() == 2, "the first line did not page on its \\n (saw %s)" % [pages])
	for shown: String in pages:
		_check(not shown.contains("\n"), "a page break was typed as a line break")

	ok = await _until(func() -> bool:
		return IntroCutscene.darkness() < 0.99 and IntroCutscene.darkness() > 0.0)
	_check(ok, "world never started fading in")
	_check(pawn.ui_open, "player let go mid-fade")

	ok = await _until(func() -> bool: return DialogSystem.dialog_id == IntroCutscene.LIGHT_DIALOG)
	_check(ok, "second line never opened")
	_check(IntroCutscene.darkness() == 0.0, "second line spoken before the world was up")
	_check(pawn.ui_open, "player not frozen during the second line")

	ok = await _until(func() -> bool: return not IntroCutscene.is_playing())
	_check(ok, "cutscene never ended")
	_check(IntroCutscene.darkness() == 0.0, "screen left dark after the cutscene")
	_check(not pawn.ui_open, "player left frozen after the cutscene")
	_check(not Cinematic.is_framing(), "the cutscene kept the bars after it ended")
	ok = await _until(func() -> bool: return Cinematic.bar_amount() == 0.0)
	_check(ok, "the cinematic bars never slid back out")

	# a pawn that shows up later (a respawn) must not replay the intro
	IntroCutscene.on_local_pawn_ready()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not IntroCutscene.is_playing(), "intro replayed for a later pawn")
	_check(IntroCutscene.darkness() == 0.0, "screen went black again for a later pawn")
	_check(DialogSystem.dialog_id == "", "dialog reopened for a later pawn")

	# ...but the cheat menu's "Start cutscene" runs the whole thing again
	IntroCutscene.replay()
	_check(IntroCutscene.darkness() == 1.0, "replay did not black the screen out again")
	ok = await _until(func() -> bool: return DialogSystem.dialog_id == IntroCutscene.DARK_DIALOG)
	_check(ok, "replay never reopened the first line")
	ok = await _until(func() -> bool: return not IntroCutscene.is_playing())
	_check(ok, "replay never ended")
	_check(IntroCutscene.darkness() == 0.0, "screen left dark after the replay")
	_check(not pawn.ui_open, "player left frozen after the replay")

	_done()
