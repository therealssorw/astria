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
	get_tree().quit()
