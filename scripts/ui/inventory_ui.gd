extends CanvasLayer
## Inventory screen (toggled with Tab, or D-pad left on a gamepad) +
## always-on hotbar.
## Tabs: Inventory (equipment slots + 32-slot item grid) and Stats
## (coins / deaths / kills, from the GameStats autoload).

const SLOT_SIZE := 52
const HOTBAR_SLOTS := 9
const ITEM_COLS := 8
const ITEM_ROWS := 4

var panel_root: Control
var inv_content: Control
var stats_content: Control
var coins_label: Label
var deaths_label: Label
var kills_label: Label
var open := false
var player: Node
var item_slots: Array[Panel] = []

func _ready() -> void:
	layer = 5
	_build_hotbar()
	_build_panel()
	GameStats.changed.connect(_refresh_items)
	_refresh_items()

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

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory") \
			and not DialogSystem.is_open() and not ShopSystem.is_open():
		_toggle()
	if open and stats_content.visible:
		# kills/deaths come from the server's registry, not local counters
		var st: Dictionary = Net.my_stats()
		coins_label.text = "Coins: %d" % GameStats.coins
		deaths_label.text = "Deaths: %d" % int(st["deaths"])
		kills_label.text = "Kills: %d" % int(st["kills"])

# ---------------- construction ----------------

func _slot(label_text := "") -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.15, 0.92)
	style.border_color = Color(0.45, 0.45, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", style)
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

## A bag slot: item name across the middle, stack count in the corner. There
## is no item art yet, so the name is the icon.
func _item_slot() -> Panel:
	var p := _slot()
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
	p.add_child(name_label)

	# full-rect and aligned into the corner, so the badge can never spill out
	var count := Label.new()
	count.name = "ItemCount"
	count.add_theme_font_size_override("font_size", 10)
	count.add_theme_color_override("font_color", Color(0.95, 0.79, 0.42))
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.offset_right = -4
	count.offset_bottom = -2
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	p.add_child(count)
	return p

func _refresh_items() -> void:
	var ids := GameStats.owned_ids()
	for i in item_slots.size():
		var slot := item_slots[i]
		var name_label := slot.get_node("ItemName") as Label
		var count := slot.get_node("ItemCount") as Label
		if i >= ids.size():
			name_label.text = ""
			count.text = ""
			continue
		var id: String = ids[i]
		var n := GameStats.item_count(id)
		name_label.text = ItemDb.item_name(id)
		count.text = "x%d" % n if n > 1 else ""

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
	for i in HOTBAR_SLOTS:
		bar.add_child(_slot())
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 10)

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

	inv_btn.pressed.connect(func() -> void:
		inv_content.visible = true
		stats_content.visible = false)
	stats_btn.pressed.connect(func() -> void:
		inv_content.visible = false
		stats_content.visible = true)

func _build_inventory_tab() -> Control:
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

	# 32 general item slots
	var grid := GridContainer.new()
	grid.columns = ITEM_COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	item_slots.clear()
	for i in ITEM_COLS * ITEM_ROWS:
		var slot := _item_slot()
		item_slots.append(slot)
		grid.add_child(slot)
	row.add_child(grid)
	return row

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
