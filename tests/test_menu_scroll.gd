extends Node
## Headless test for long menus following the highlight. Run:
##   godot --headless --path . res://tests/test_menu_scroll.tscn
## Prints SCROLLTEST RESULT=PASS/FAIL and exits with the matching code.
##
## Six rows fit on screen and both of these lists are longer than that. With a
## mouse there is a wheel and a scrollbar; ON A GAMEPAD THERE IS NEITHER, so the
## only way down is the focus walking there — and if the view does not follow it,
## the list simply ends at row six for anyone on a controller, with the highlight
## on something they cannot see.
##
## Driven with REAL input events (`ui_down`, which is the pad's d-pad and left
## stick), not by calling grab_focus() down the list: what is being tested is
## that walking the menu the way a player walks it keeps the row on screen.
##
## Needs no server — a shop panel and the cheat menu are both local.

const WALK := 9

var _failures: PackedStringArray = []
var _checks := 0

func _ready() -> void:
	await _check_shop()
	await _check_cheat_menu()

	print("SCROLLTEST ran %d assertions" % _checks)
	if _failures.is_empty():
		print("SCROLLTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("  - ", failure)
		print("SCROLLTEST RESULT=FAIL (%d problems)" % _failures.size())
		get_tree().quit(1)

func _expect(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition

func _check_shop() -> void:
	if not _expect(ShopSystem.open("blacksmith"), "the blacksmith's shop would not open"):
		return
	await _settle()
	var scroll := _scroll_of(ShopSystem)
	if not _expect(scroll != null, "the shop has no scrolling list"):
		return
	await _walk_and_check(scroll, "shop")
	ShopSystem.close()
	await _settle()

## The cheat menu's "Give item" page is the whole catalogue and has exactly the
## same problem, but it will not OPEN without a pawn to cheat at (see its
## `open()`), and hosting a world to walk a menu is not worth the minute it
## costs. So this half only asserts the property, where the shop's is walked:
## weaker on purpose, and still enough to catch the line being dropped.
func _check_cheat_menu() -> void:
	# Editor-only by design (see CLAUDE.md "Development cheats"), so it may not
	# have built at all — say so rather than failing on a deliberate absence.
	if not OS.has_feature("editor"):
		print("SCROLLTEST skipped the cheat menu — not an editor run")
		return
	var scroll := _scroll_of(CheatMenu)
	if not _expect(scroll != null, "the cheat menu has no scrolling list"):
		return
	_expect(scroll.follow_focus,
			"the cheat menu's list does not follow the highlight — a pad walking "
			+ "down 'Give item' would lose sight of the row it is on")

## Walk down with the d-pad and check the highlighted row is still on screen at
## every step. Checked EVERY step and not only at the bottom: a list that jumps
## the view a page at a time passes an end-state check while flickering the row
## you are on off the top.
func _walk_and_check(scroll: ScrollContainer, what: String) -> void:
	var rows := _rows_of(scroll)
	if not _expect(rows.size() > 6,
			"%s only has %d rows — that is not long enough to have to scroll"
					% [what, rows.size()]):
		return
	var focused := _focused_row(rows)
	if not _expect(focused >= 0, "%s: nothing is highlighted to start with" % what):
		return

	var walked := 0
	for _step in mini(WALK, rows.size() - 1):
		_press("ui_down")
		await _settle()
		var now := _focused_row(rows)
		if not _expect(now == focused + 1,
				"%s: pressing down at row %d went to row %d" % [what, focused, now]):
			return
		focused = now
		walked += 1
		if not _expect(_is_visible_in(scroll, rows[focused]),
				"%s: row %d is highlighted but sits outside the visible list (%s)"
						% [what, focused, _placement(scroll, rows[focused])]):
			return
	_expect(walked >= 6, "%s: only walked %d rows, so nothing had to scroll"
			% [what, walked])
	# And the view really did move — a list tall enough to show everything at
	# once would pass every check above without scrolling at all.
	_expect(scroll.scroll_vertical > 0,
			"%s: walked past the bottom row and the list never scrolled" % what)

## Is the row inside the window the scroll container shows? Measured in the
## content's own space: a row's y is where it sits in the whole list, and the
## window is [scroll_vertical, scroll_vertical + height].
func _is_visible_in(scroll: ScrollContainer, row: Control) -> bool:
	var top := row.position.y
	var bottom := top + row.size.y
	var view_top := float(scroll.scroll_vertical)
	var view_bottom := view_top + scroll.size.y
	return top >= view_top - 1.0 and bottom <= view_bottom + 1.0

func _placement(scroll: ScrollContainer, row: Control) -> String:
	return "row %.0f..%.0f, window %.0f..%.0f" % [row.position.y,
			row.position.y + row.size.y, scroll.scroll_vertical,
			scroll.scroll_vertical + scroll.size.y]

func _press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)

func _scroll_of(panel: Node) -> ScrollContainer:
	for node in panel.find_children("*", "ScrollContainer", true, false):
		return node as ScrollContainer
	return null

func _rows_of(scroll: ScrollContainer) -> Array[Control]:
	var out: Array[Control] = []
	for content in scroll.get_children():
		if content is Control and not (content is ScrollBar):
			for row in (content as Control).get_children():
				if row is Button:
					out.append(row as Control)
	return out

func _focused_row(rows: Array[Control]) -> int:
	var owner := get_viewport().gui_get_focus_owner()
	return rows.find(owner)

## Input is handled next frame and the containers sort themselves the frame
## after, so a check on the frame the key went down measures the layout it had
## before the press.
func _settle() -> void:
	for _i in 4:
		await get_tree().process_frame
