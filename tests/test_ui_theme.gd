extends Node
## Headless test for the shared UI look. Run:
##   godot --headless --path . res://tests/test_ui_theme.tscn
## Prints UITEST RESULT=PASS/FAIL and exits with the matching code.
##
## Two things it is guarding, both of which are invisible in a diff:
##   1. The palette and the sheet of paint are REALLY on the screens. A texture
##      path that stops resolving, or a font that fails to import, does not
##      error — the UI just quietly goes back to Godot's defaults.
##   2. No screen has drifted back to black. It walks every live UI and fails on
##      any panel, row or rectangle painted a pure black, which is what the
##      whole palette exists to replace.

var fails := 0

func _ready() -> void:
	call_deferred("_run")

func ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		print("  PASS  %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL  %s %s" % [label, detail])

func _run() -> void:
	await get_tree().process_frame
	print("=== palette ===")
	_test_palette()
	print("=== font ===")
	await _test_font()
	print("=== panel ===")
	_test_panel()
	print("=== no black left ===")
	await _test_no_black()
	print("UITEST RESULT=%s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _hex(c: Color) -> String:
	return c.to_html(false)

func _test_palette() -> void:
	ok(_hex(UiTheme.INK) == "232323", "INK is 232323", _hex(UiTheme.INK))
	ok(_hex(UiTheme.SLATE) == "343434", "SLATE is 343434", _hex(UiTheme.SLATE))
	ok(_hex(UiTheme.STONE) == "464646", "STONE is 464646", _hex(UiTheme.STONE))
	ok(UiTheme.INK.v < UiTheme.SLATE.v and UiTheme.SLATE.v < UiTheme.STONE.v,
			"the three shades are a depth order, darkest first")
	var sheet := UiTheme.sheet_texture()
	ok(sheet != null, "the sheet of paint is really there", UiTheme.TEXTURE_PATH)
	ok(sheet != null and sheet.get_width() > 256 and sheet.get_height() > 256,
			"...and is big enough to stretch over a screen",
			"%dx%d" % [sheet.get_width() if sheet else 0, sheet.get_height() if sheet else 0])
	# a row has to be visibly lighter than the panel under it, or the list is a
	# flat wall of grey with no rows in it
	ok(UiTheme.row_fill(true).v > UiTheme.row_fill().v,
			"a row lights up when it is the one under the pointer")

## The font is set for the WHOLE game through the project's default theme, so
## the check is the one a Control actually makes — not that the file exists.
func _test_font() -> void:
	var probe := Label.new()
	add_child(probe)
	await get_tree().process_frame
	var font := probe.get_theme_default_font()
	var font_name := font.get_font_name() if font else "<none>"
	ok(font != null, "every Control has a default font")
	ok("Garamond" in font_name, "and it is EB Garamond", font_name)
	# drawn overlays (the quest star's distance, the NPC bubble) ask for exactly
	# this font, so one check covers the panels and the vector HUD both
	ok(str(ProjectSettings.get_setting("gui/theme/custom_font", "")).ends_with(".ttf"),
			"the project, not one screen, is what sets it")
	probe.free()

func _test_panel() -> void:
	var frame := UiTheme.panel()
	add_child(frame)
	var style: StyleBoxFlat = frame.get_theme_stylebox("panel")
	ok(style != null and _hex(style.bg_color) == "232323",
			"a panel's body is INK", _hex(style.bg_color) if style else "<none>")
	ok(style != null and _hex(style.border_color) == "464646",
			"...with a STONE edge")
	ok(frame.get_child_count() == 2 and frame.get_child(0) is TextureRect,
			"the paint is behind the content, not beside it")
	ok(UiTheme.body(frame) is MarginContainer,
			"and content goes into the body, which is what carries the padding")
	# the padding must NOT be in the stylebox, or the sheet is inset with it and
	# every screen gets an untextured border ring
	ok(style != null and style.content_margin_left <= 0.0,
			"the padding is not in the stylebox")
	frame.free()

## Walks every screen that is actually live and fails on anything still painted
## black. Two exceptions, and both for the same reason — they are the shot
## rather than a surface with UI on it: Cinematic's letterbox bars, and the
## intro cutscene's rect, which IS the black the world fades up out of.
func _test_no_black() -> void:
	var board: Control = (load("res://scripts/ui/scoreboard.gd") as Script).new()
	add_child(board)
	board.set_process(false)
	await get_tree().process_frame

	var offenders: Array[String] = []
	var panels := 0
	for node in _walk(get_tree().root):
		if Cinematic != null and Cinematic.is_ancestor_of(node):
			continue
		if IntroCutscene != null and IntroCutscene.is_ancestor_of(node):
			continue
		if node is ColorRect:
			panels += 1
			if _is_black((node as ColorRect).color):
				offenders.append("%s.color" % node.get_path())
		if node is Control:
			for slot in ["panel", "normal", "hover", "focus", "pressed"]:
				if not (node as Control).has_theme_stylebox_override(slot):
					continue
				var box := (node as Control).get_theme_stylebox(slot)
				if box is StyleBoxFlat:
					panels += 1
					if _is_black((box as StyleBoxFlat).bg_color):
						offenders.append("%s[%s]" % [node.get_path(), slot])
	ok(panels > 10, "found the live screens to check", "%d surfaces" % panels)
	ok(offenders.is_empty(), "nothing is painted black any more",
			"" if offenders.is_empty() else str(offenders))
	board.free()

## Black enough to be a leftover: near-zero on every channel, and actually
## drawn. A fully transparent black is just "no fill" and is fine.
func _is_black(c: Color) -> bool:
	return c.a > 0.02 and c.r < 0.02 and c.g < 0.02 and c.b < 0.02

func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
