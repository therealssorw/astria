extends CanvasLayer
## Inventory screen (toggled with Tab, or D-pad up on a gamepad) +
## always-on hotbar.
## Tabs: Inventory (equipment slots + the bag, whose TOP ROW is the hotbar —
## framed in gold and labelled, with the general slots underneath it) and
## Stats (deaths / kills from the server registry). Gold is always visible at
## the bottom of the window; GameStats mirrors the server's gold, bag and bar.
##
## Everything in here is a REQUEST. The bag, the hotbar and which slot is in
## hand all live in the server registry — this screen draws the mirror and asks
## Net to change it, then redraws when `GameStats.changed` says the server
## answered. Equipment slots (Helmet / L Hand / Torso / R Hand / Pants) are
## still decoration: nothing equips yet.
##
## Driving it: the mouse clicks any slot, and a gamepad or the arrow keys move
## focus between them, with the bottom face button (PS5 Cross / Xbox A, i.e.
## `ui_accept`) to select.
##   - a bag slot -> puts that item in the hotbar slot you are holding
##   - a hotbar slot -> holds that slot; selecting the one you already hold
##     clears it back into the bag
## Out in the world R1/L1 (or ] and [) walk the selection and `use_item`
## (F / R2 — the same trigger as attack) uses whatever is in hand.

const SLOT_SIZE := 52
const HOTBAR_SLOTS := 9
const ITEM_COLS := HOTBAR_SLOTS # the bag sits directly under the bar: same width
const ITEM_ROWS := 4
## Padding inside the frame that highlights the hotbar row; the bag grid is
## inset by the same amount so the two line up column for column.
const HOTBAR_FRAME_PAD := 4

const GOLD := Color(0.95, 0.79, 0.42)
const USE_FLASH_TIME := 2.0

var panel_root: Control
var inv_content: Control
var stats_content: Control
var coins_label: Label
var deaths_label: Label
var kills_label: Label
var gold_label: Label
var _hint: Label
var _use_label: Label
var _use_flash := 0.0
var open := false
var player: Node
var item_slots: Array[Button] = []
var bar_slots: Array[Panel] = []        # the always-on bar along the bottom
var panel_bar_slots: Array[Button] = [] # the same nine slots inside the window

func _ready() -> void:
	layer = 5
	_build_hotbar()
	_build_panel()
	GameStats.changed.connect(_refresh_items)
	Net.item_used.connect(_on_item_used)
	_refresh_items()

## The server answered a use. An empty message means "nothing worth saying" —
## which is every use today, because use_item shares R2 with attack and a line
## per swing would be noise.
func _on_item_used(_item_id: String, message: String) -> void:
	if message == "":
		return
	_use_label.text = message
	_use_flash = USE_FLASH_TIME

func _input(_event: InputEvent) -> void:
	pass # toggling is polled in _process so it can't be swallowed by focus

func _toggle() -> void:
	open = not open
	panel_root.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if not is_instance_valid(player):
		var players := get_tree().get_nodes_in_group("local_player")
		player = players[0] if players.size() > 0 else null
	if is_instance_valid(player):
		player.set("ui_open", open)
	if open:
		_refresh_items()
		_focus_held_slot() # a gamepad needs somewhere to start without a mouse

func _process(delta: float) -> void:
	if _use_flash > 0.0:
		_use_flash -= delta
		_use_label.modulate.a = clampf(_use_flash, 0.0, 1.0)
	if Input.is_action_just_pressed("inventory") \
			and not DialogSystem.is_open() and not ShopSystem.is_open() \
			and not CheatMenu.is_open():
		_toggle()
	if open:
		gold_label.text = "Gold: %d" % GameStats.coins
	if open and stats_content.visible:
		# kills/deaths/gold come from the server's registry, not local counters
		var st: Dictionary = Net.my_stats()
		coins_label.text = "Gold: %d" % GameStats.coins
		deaths_label.text = "Deaths: %d" % int(st["deaths"])
		kills_label.text = "Kills: %d" % int(st["kills"])

func _focus_held_slot() -> void:
	var i := clampi(GameStats.hot_slot, 0, panel_bar_slots.size() - 1)
	if i >= 0 and i < panel_bar_slots.size():
		panel_bar_slots[i].grab_focus()

# ---------------- requests ----------------
#
# Neither of these touches GameStats: they ask, and the redraw happens when the
# server's answer lands in the mirror.

## A bag slot was chosen — put that item in the slot currently in hand.
func _on_item_pressed(id: String) -> void:
	if id != "":
		Net.request_hotbar_assign(GameStats.hot_slot, id)

## A hotbar slot was chosen — hold it, or clear it if it is already held.
func _on_bar_pressed(slot: int) -> void:
	if slot == GameStats.hot_slot and GameStats.hotbar_id(slot) != "":
		Net.request_hotbar_assign(slot, "")
	else:
		Net.request_hotbar_select(slot)

# ---------------- construction ----------------

func _slot_style(selected := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.15, 0.92)
	style.border_color = GOLD if selected else Color(0.45, 0.45, 0.5)
	style.set_border_width_all(3 if selected else 2)
	style.set_corner_radius_all(3)
	return style

func _slot(label_text := "") -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	p.add_theme_stylebox_override("panel", _slot_style())
	if label_text != "":
		var l := Label.new()
		l.text = label_text
		l.add_theme_font_size_override("font_size", 9)
		l.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
	return p

## What every item slot carries: the icon, the item's name as a fallback for
## art that doesn't exist yet, and the stack count in the corner.
func _add_item_labels(host: Control) -> void:
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -4
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(icon)

	var name_label := Label.new()
	name_label.name = "ItemName"
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.offset_left = 3
	name_label.offset_right = -3
	name_label.offset_bottom = -7 # leave the bottom strip for the stack count
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(name_label)

	# full-rect and aligned into the corner, so the badge can never spill out
	var count := Label.new()
	count.name = "ItemCount"
	count.add_theme_font_size_override("font_size", 10)
	count.add_theme_color_override("font_color", GOLD)
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.offset_right = -4
	count.offset_bottom = -2
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(count)

## An in-panel slot: a Button, so the mouse can click it and a gamepad can walk
## the grid with focus, styled to look exactly like the plain Panel slots.
func _slot_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	b.focus_mode = Control.FOCUS_ALL
	_add_item_labels(b)
	_paint_slot(b, false)
	return b

## Repaint one slot's border: gold and thicker when it is the one in hand,
## bright when it merely has focus or the pointer.
func _paint_slot(b: Button, selected: bool) -> void:
	b.add_theme_stylebox_override("normal", _slot_style(selected))
	b.add_theme_stylebox_override("pressed", _slot_style(selected))
	var hot := _slot_style(selected)
	hot.border_color = GOLD if selected else Color(0.85, 0.85, 0.9)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", hot)

## Fill a slot's icon/name/count from an item id ("" empties it).
func _draw_item(host: Control, id: String, count_text := "") -> void:
	var icon := host.get_node("ItemIcon") as TextureRect
	var name_label := host.get_node("ItemName") as Label
	var count := host.get_node("ItemCount") as Label
	if id == "":
		icon.texture = null
		name_label.text = ""
		count.text = ""
		host.tooltip_text = ""
		return
	icon.texture = ItemDb.icon(id)
	# the name only stands in for missing art; the tooltip always names it
	name_label.text = "" if icon.texture else ItemDb.item_name(id)
	count.text = count_text
	host.tooltip_text = "%s\n%s" % [ItemDb.item_name(id), ItemDb.description(id)]

func _refresh_items() -> void:
	var ids := GameStats.owned_ids()
	for i in item_slots.size():
		var slot := item_slots[i]
		var id: String = ids[i] if i < ids.size() else ""
		var n := GameStats.item_count(id) if id != "" else 0
		_draw_item(slot, id, "x%d" % n if n > 1 else "")
		# a gold edge in the bag means "this one is on the bar somewhere"
		_paint_slot(slot, id != "" and GameStats.hotbar.has(id))
	_refresh_hotbar()

## Both copies of the bar — the one on screen and the one in the panel — draw
## from the same mirror, so they can never disagree.
func _refresh_hotbar() -> void:
	for i in HOTBAR_SLOTS:
		var id := GameStats.hotbar_id(i)
		var n := GameStats.item_count(id) if id != "" else 0
		var count_text := "x%d" % n if n > 1 else ""
		var selected := i == GameStats.hot_slot
		if i < bar_slots.size():
			var p := bar_slots[i]
			_draw_item(p, id, count_text)
			p.add_theme_stylebox_override("panel", _slot_style(selected))
		if i < panel_bar_slots.size():
			var b := panel_bar_slots[i]
			_draw_item(b, id, count_text)
			_paint_slot(b, selected)

func _spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	return c

func _build_hotbar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y = -8
	bar.add_theme_constant_override("separation", 4)
	bar_slots.clear()
	for i in HOTBAR_SLOTS:
		var p := _slot()
		_add_item_labels(p)
		bar_slots.append(p)
		bar.add_child(p)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 10)

	# what the server said about the last "use" — sits just above the bar and
	# fades, so nothing about it needs a place in the HUD proper
	_use_label = Label.new()
	_use_label.add_theme_font_size_override("font_size", 15)
	_use_label.add_theme_color_override("font_color", GOLD)
	_use_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_use_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_use_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_use_label.modulate.a = 0.0
	add_child(_use_label)
	_use_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM,
			Control.PRESET_MODE_MINSIZE, SLOT_SIZE + 22)

func _build_panel() -> void:
	panel_root = Control.new()
	panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.visible = false
	add_child(panel_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.add_child(center)

	var window := PanelContainer.new()
	var wstyle := StyleBoxFlat.new()
	wstyle.bg_color = Color(0.09, 0.09, 0.11, 0.97)
	wstyle.border_color = Color(0.35, 0.35, 0.4)
	wstyle.set_border_width_all(2)
	wstyle.set_corner_radius_all(6)
	wstyle.content_margin_left = 18
	wstyle.content_margin_right = 18
	wstyle.content_margin_top = 12
	wstyle.content_margin_bottom = 18
	window.add_theme_stylebox_override("panel", wstyle)
	center.add_child(window)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	window.add_child(vbox)

	# tab buttons above the content
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	var inv_btn := Button.new()
	inv_btn.text = "Inventory"
	var stats_btn := Button.new()
	stats_btn.text = "Stats"
	tabs.add_child(inv_btn)
	tabs.add_child(stats_btn)
	vbox.add_child(tabs)

	inv_content = _build_inventory_tab()
	stats_content = _build_stats_tab()
	vbox.add_child(inv_content)
	vbox.add_child(stats_content)
	stats_content.visible = false

	# gold readout, visible on every tab (vector coin, no glyph textures)
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 7)
	var coin := Panel.new()
	coin.custom_minimum_size = Vector2(15, 15)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.95, 0.78, 0.2)
	cstyle.border_color = Color(0.62, 0.47, 0.1)
	cstyle.set_border_width_all(2)
	cstyle.set_corner_radius_all(8)
	coin.add_theme_stylebox_override("panel", cstyle)
	gold_row.add_child(coin)
	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 18)
	gold_label.add_theme_color_override("font_color", Color(0.98, 0.85, 0.3))
	gold_row.add_child(gold_label)
	vbox.add_child(gold_row)

	inv_btn.pressed.connect(func() -> void:
		inv_content.visible = true
		stats_content.visible = false)
	stats_btn.pressed.connect(func() -> void:
		inv_content.visible = false
		stats_content.visible = true)

func _build_inventory_tab() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)

	# equipment cross: helmet / (left hand, torso, right hand) / pants
	var eq := GridContainer.new()
	eq.columns = 3
	eq.add_theme_constant_override("h_separation", 6)
	eq.add_theme_constant_override("v_separation", 6)
	eq.add_child(_spacer());          eq.add_child(_slot("Helmet"));  eq.add_child(_spacer())
	eq.add_child(_slot("L Hand"));    eq.add_child(_slot("Torso"));   eq.add_child(_slot("R Hand"))
	eq.add_child(_spacer());          eq.add_child(_slot("Pants"));   eq.add_child(_spacer())
	row.add_child(eq)

	# The bag: the hotbar IS its top row (labelled and framed so it reads as
	# special), with the general slots filling the rows underneath. Two columns
	# — the labels and the rows they name — so the grid lines up under the bar
	# on its own instead of being nudged by however wide "Hotbar" renders.
	var bag := HBoxContainer.new()
	bag.add_theme_constant_override("separation", 8)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 6)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)

	var bar_title := Label.new()
	bar_title.text = "Hotbar"
	bar_title.add_theme_font_size_override("font_size", 16)
	bar_title.add_theme_color_override("font_color", GOLD)
	bar_title.custom_minimum_size.y = SLOT_SIZE + HOTBAR_FRAME_PAD * 2
	bar_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	titles.add_child(bar_title)

	# the frame is the highlight — a gold wash behind the row, so the top row
	# never reads as just more bag
	var bar_frame := PanelContainer.new()
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.13)
	fstyle.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.65)
	fstyle.set_border_width_all(2)
	fstyle.set_corner_radius_all(5)
	fstyle.set_content_margin_all(HOTBAR_FRAME_PAD)
	bar_frame.add_theme_stylebox_override("panel", fstyle)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	panel_bar_slots.clear()
	for i in HOTBAR_SLOTS:
		var b := _slot_button()
		b.pressed.connect(_on_bar_pressed.bind(i))
		panel_bar_slots.append(b)
		bar.add_child(b)
	bar_frame.add_child(bar)
	rows.add_child(bar_frame)

	# the general slots, inset by the frame's padding so their columns line up
	# with the hotbar slots directly above them
	var grid_margin := MarginContainer.new()
	grid_margin.add_theme_constant_override("margin_left", HOTBAR_FRAME_PAD)
	grid_margin.add_theme_constant_override("margin_right", HOTBAR_FRAME_PAD)
	var grid := GridContainer.new()
	grid.columns = ITEM_COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	item_slots.clear()
	for i in ITEM_COLS * ITEM_ROWS:
		var slot := _slot_button()
		# read the id at press time: the bag reorders as things come and go
		slot.pressed.connect(func() -> void:
			var ids := GameStats.owned_ids()
			_on_item_pressed(str(ids[i]) if i < ids.size() else ""))
		item_slots.append(slot)
		grid.add_child(slot)
	grid_margin.add_child(grid)
	rows.add_child(grid_margin)
	# an empty title cell keeps the bag rows aligned with the labelled bar
	var bag_title := Control.new()
	bag_title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	titles.add_child(bag_title)
	bag.add_child(titles)
	bag.add_child(rows)
	row.add_child(bag)
	col.add_child(row)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
	_update_hint()
	InputDevice.kind_changed.connect(func(_k: int) -> void: _update_hint())
	col.add_child(_hint)
	return col

## The accept button is named after whatever device was last used, exactly as
## the dialog box and the shop do it.
func _update_hint() -> void:
	if _hint:
		_hint.text = "%s an item to put it in the held hotbar slot · the held slot again to clear it · R1 / L1 in the world" \
				% InputDevice.accept_label()

func _build_stats_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(420, 220)
	coins_label = Label.new()
	deaths_label = Label.new()
	kills_label = Label.new()
	for l: Label in [coins_label, deaths_label, kills_label]:
		l.add_theme_font_size_override("font_size", 20)
		vbox.add_child(l)
	return vbox
