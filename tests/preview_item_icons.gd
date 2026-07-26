extends Control
## Eyeballing aid, not a pass/fail test: takes the REAL item icons — the same
## `ItemIcons` the bag and the shop ask — lays every one of them out on a sheet
## with its name under it, and saves a PNG.
##   godot --path . res://tests/preview_item_icons.tscn
## It needs a real window: an icon is a render, and --headless has nothing to
## render into (which is exactly what test_item_icons.tscn checks).
##
## This is the only place the pictures themselves are ever looked at. Framing,
## the three-quarter angle, whether a boot is recognisable at 64 pixels and
## whether the three swords read as three different metals are all invisible
## from a headless run.

const OUT := "user://item_icons_preview.png"
const COLS := 5
const CELL := Vector2(120, 132)
const PAD := Vector2(16, 16)

func _ready() -> void:
	var ids := ItemDb.ITEMS.keys()
	var rows := int(ceil(float(ids.size()) / COLS))
	var size := Vector2(COLS, rows) * CELL + PAD * 2.0
	get_window().size = Vector2i(size)
	custom_minimum_size = size

	var bg := ColorRect.new()
	bg.color = UiTheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	for i in ids.size():
		var id: String = ids[i]
		var at := PAD + Vector2(i % COLS, i / COLS) * CELL

		var slot := ColorRect.new()
		slot.color = UiTheme.SLATE
		slot.position = at
		slot.size = Vector2(CELL.x - 16, CELL.x - 16)
		add_child(slot)

		var pic := TextureRect.new()
		pic.texture = ItemDb.icon(id)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.position = at
		pic.size = slot.size
		add_child(pic)

		var label := Label.new()
		label.text = "%s\n%s" % [ItemDb.item_name(id), ItemDb.level_label(id)]
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = at + Vector2(0, CELL.x - 14)
		label.size = Vector2(CELL.x - 16, 32)
		add_child(label)

	# The icons are taken one a frame, so wait for the whole queue before the
	# sheet is photographed — otherwise the last rows are still empty.
	for _i in ids.size() + 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT)
	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT))
	_report_colours()
	get_tree().quit()

## Does the picture come out the colour the item was PAINTED? Printed rather
## than eyeballed because a wash is hard to see and easy to measure: the studio
## used to over-light everything, and a grey suit photographed as white.
##
## Only armor, and only its plate: a suit says in so many words what colour it
## is, where a sword's colour is buried in an imported FBX texture.
func _report_colours() -> void:
	print("COLOUR (a plate against the colour its suit paints it)")
	for id: String in ItemDb.ITEMS:
		var piece := ItemDb.armor_piece(id)
		if piece == null or piece.colors.is_empty():
			continue
		var shot := ItemDb.icon(id) as ImageTexture
		if shot == null:
			continue
		var got := _average(shot.get_image())
		var want: Color = piece.colors[0] * piece.tint
		var off := maxf(maxf(absf(got.r - want.r), absf(got.g - want.g)),
				absf(got.b - want.b))
		# A piece painted in several colours averages to a blend of them, so the
		# bar is loose; it is a wash detector, not a colour picker.
		print("  %-18s shot %.3f,%.3f,%.3f  painted %.3f,%.3f,%.3f  off %.3f  %s" % [
				id, got.r, got.g, got.b, want.r, want.g, want.b, off,
				"ok" if off <= 0.12 else "WASHED"])

func _average(img: Image) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			# Only the solid middle of a face: the edge pixels are part sky after
			# the shot is shrunk, and they drag every average towards nothing.
			if px.a > 0.9:
				sum += px
				n += 1
	return sum / maxf(n, 1)
