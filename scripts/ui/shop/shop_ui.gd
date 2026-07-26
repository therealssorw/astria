extends CanvasLayer
## Reusable NPC shop, styled to match the dialog box. Buy and Sell tabs, one
## focusable row per item so it drives from mouse, keyboard or gamepad.
## Autoload: ShopSystem. Stock lives in ShopData, prices in ItemDb.
##
## It opens itself: any dialog answer carrying `"action": "open_shop"` opens
## the shop registered under that NPC's dialog_id. Nothing else to wire up.

signal opened(shop_id: String)
signal closed(shop_id: String)

const OPEN_ACTION := "open_shop"
const FLASH_TIME := 2.0
const ROW_H := 44 # tall enough that the item icon reads at a glance
const PANEL_W := 620

const GOLD := Color(0.95, 0.79, 0.42)
const DIM := Color(0.78, 0.79, 0.84)
const BAD := Color(0.9, 0.42, 0.36)

var shop_id := ""

var _root: Control
var _title: Label
var _purse: Label
var _buy_tab: Button
var _sell_tab: Button
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _hint: Label
var _selling := false
var _flash_left := 0.0
var _focus_row := 0
var _player: Node

func _ready() -> void:
	layer = 21 # above the dialog box
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ui_panel") # the pawn frees the pointer for whatever is open
	_build()
	_root.visible = false
	set_process(false)
	DialogSystem.action_triggered.connect(_on_dialog_action)
	GameStats.changed.connect(_on_purse_changed)
	Net.trade_result.connect(_on_trade_result)

func is_open() -> bool:
	return shop_id != ""

## Open the shop registered under `id`. Returns false if there is no such shop.
func open(id: String) -> bool:
	if not ShopData.has(id):
		push_warning("ShopSystem: no shop named '%s'" % id)
		return false
	shop_id = id
	_selling = false
	_focus_row = 0
	_title.text = str(ShopData.get_shop(id).get("title", id))
	_root.visible = true
	set_process(true)
	_player = _local_player()
	if is_instance_valid(_player):
		_player.set("ui_open", true)
	_hint.text = _default_hint()
	_flash_left = 0.0
	_refresh()
	opened.emit(id)
	return true

func close() -> void:
	if not is_open():
		return
	var was := shop_id
	shop_id = ""
	_root.visible = false
	set_process(false)
	if is_instance_valid(_player):
		_player.set("ui_open", false)
	_player = null
	closed.emit(was)

func _on_dialog_action(dialog_id: String, action: String) -> void:
	if action == OPEN_ACTION:
		open(dialog_id)

func _on_purse_changed() -> void:
	# deferred: this can land inside a row button's own `pressed` signal (the
	# host trades synchronously), and the refresh frees that button
	if is_open():
		_refresh.call_deferred()

func _on_trade_result(message: String, ok: bool) -> void:
	if is_open():
		_flash(message, GOLD if ok else BAD)

# ---------------- transactions ----------------
#
# The UI never moves coins or items itself — it asks, and redraws when the
# server sends the new purse back. So a client that patches this file can only
# make its own screen lie to it.

func _buy(id: String) -> void:
	Net.request_buy(shop_id, id)

func _sell(id: String) -> void:
	Net.request_sell(shop_id, id)

func _flash(text: String, color: Color) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", color)
	_flash_left = FLASH_TIME

# ---------------- per-frame ----------------

func _process(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		_hint.text = _default_hint()
		_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))

func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif InputDevice.is_menu_accept(event) or event.is_action_pressed("interact"):
		# swallow interact even when it no longer picks (pad Y), so it cannot
		# reach the shopkeeper standing behind the panel
		get_viewport().set_input_as_handled()
		if InputDevice.is_menu_accept(event):
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button:
				(focused as Button).pressed.emit()

# ---------------- list ----------------

func _refresh() -> void:
	_purse.text = "%d gold" % GameStats.coins
	_buy_tab.button_pressed = not _selling
	_sell_tab.button_pressed = _selling
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if _selling:
		_fill_sell_rows()
	else:
		_fill_buy_rows()
	_restore_focus()

func _fill_buy_rows() -> void:
	for id: String in ShopData.stock(shop_id):
		if not ItemDb.has(id):
			push_warning("ShopSystem: '%s' stocks unknown item '%s'" % [shop_id, id])
			continue
		var price := ItemDb.buy_price(id)
		var owned := GameStats.item_count(id)
		var label := "%s   %s" % [ItemDb.item_name(id), ItemDb.level_label(id)]
		if owned > 0:
			label += "   (carrying %d)" % owned
		_add_row(id, label, "%d gold" % price,
				GOLD if price <= GameStats.coins else BAD, _buy.bind(id))

func _fill_sell_rows() -> void:
	var any := false
	for id: String in GameStats.owned_ids():
		if not ShopData.buys(shop_id, id):
			continue
		any = true
		var count := GameStats.item_count(id)
		var label := "%s   %s" % [ItemDb.item_name(id), ItemDb.level_label(id)]
		if count > 1:
			label += "   x%d" % count
		_add_row(id, label, "%d gold" % ItemDb.sell_price(id), GOLD, _sell.bind(id))
	if not any:
		var empty := Label.new()
		empty.text = "Nothing here he'll take off your hands."
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = ROW_H * 2
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_rows.add_child(empty)

## One row = a focusable button (icon + name) with the price pinned right.
func _add_row(id: String, name_text: String, price_text: String,
		price_color: Color, on_press: Callable) -> void:
	var b := Button.new()
	b.text = name_text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = ROW_H
	b.tooltip_text = ItemDb.description(id)
	b.icon = ItemDb.icon(id)
	b.expand_icon = true
	b.add_theme_constant_override("h_separation", 10)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", DIM)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _row_style(UiTheme.row_fill(), Color(0, 0, 0, 0)))
	var hot := _row_style(UiTheme.row_fill(true), Color(0.95, 0.79, 0.42, 0.95))
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", hot)
	b.add_theme_stylebox_override("pressed", _row_style(UiTheme.tint(UiTheme.STONE, 1.0), GOLD))
	b.pressed.connect(on_press)
	b.focus_entered.connect(func() -> void: _focus_row = b.get_index())

	var price := Label.new()
	price.text = price_text
	price.add_theme_font_size_override("font_size", 17)
	price.add_theme_color_override("font_color", price_color)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.set_anchors_preset(Control.PRESET_FULL_RECT)
	price.offset_right = -14
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(price)

	_rows.add_child(b)

## Rows are rebuilt after every purchase, so put the highlight back where it was.
func _restore_focus() -> void:
	var buttons: Array[Button] = []
	for c in _rows.get_children():
		if c is Button:
			buttons.append(c)
	if buttons.is_empty():
		return
	var row := buttons[clampi(_focus_row, 0, buttons.size() - 1)]
	row.grab_focus()
	# `follow_focus` scrolls the instant focus lands, and these rows were built
	# this same frame — the container has not sorted them yet, so every one of
	# them still says it is at the top and the view scrolls home while the
	# highlight sits on row twelve. Ask again once they know where they are.
	await get_tree().process_frame
	if is_open() and is_instance_valid(row) and row.has_focus():
		_scroll.ensure_control_visible(row)

func _set_selling(on: bool) -> void:
	if _selling == on:
		return
	_selling = on
	_focus_row = 0
	_refresh()

func _default_hint() -> String:
	return "%s — trade      %s — leave" % [InputDevice.menu_accept_label(),
			"Circle" if InputDevice.kind == InputDeviceTracker.Kind.PLAYSTATION
			else ("B" if InputDevice.kind == InputDeviceTracker.Kind.XBOX else "Esc")]

# ---------------- construction ----------------

func _local_player() -> Node:
	var found := get_tree().get_nodes_in_group("local_player")
	return found[0] if found.size() > 0 else null

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_root.add_child(UiTheme.backdrop())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := UiTheme.panel(UiTheme.INK, 0.82)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(PANEL_W, 0)
	UiTheme.body(panel).add_child(vbox)

	var header := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", 18)
	_purse.add_theme_color_override("font_color", GOLD)
	header.add_child(_purse)
	vbox.add_child(header)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_buy_tab = _tab_button("Buy")
	_sell_tab = _tab_button("Sell")
	_buy_tab.pressed.connect(_set_selling.bind(false))
	_sell_tab.pressed.connect(_set_selling.bind(true))
	tabs.add_child(_buy_tab)
	tabs.add_child(_sell_tab)
	vbox.add_child(tabs)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(PANEL_W, ROW_H * 6)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# THE LIST FOLLOWS THE HIGHLIGHT. Six rows are on screen and the stock is
	# longer than that, and a gamepad has no scroll wheel and no scrollbar to
	# drag: walking down past the sixth row moved the focus onto something the
	# player could not see, so the shop simply ran out at row six for anyone on a
	# controller.
	_scroll.follow_focus = true
	vbox.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)

	var footer := HBoxContainer.new()
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_hint)
	var leave := Button.new()
	leave.text = "Leave"
	leave.add_theme_font_size_override("font_size", 15)
	leave.pressed.connect(close)
	footer.add_child(leave)
	vbox.add_child(footer)

## Tabs read as underlined headings — the default toggle look is too subtle to
## tell Buy from Sell at a glance.
func _tab_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(96, 0)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	for state in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, GOLD)
	var idle := _tab_style(UiTheme.row_fill(), Color(0, 0, 0, 0))
	var active := _tab_style(UiTheme.row_fill(true), GOLD)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", _tab_style(UiTheme.row_fill(true), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("focus", _tab_style(UiTheme.row_fill(true), UiTheme.STONE))
	b.add_theme_stylebox_override("pressed", active)
	b.add_theme_stylebox_override("hover_pressed", active)
	return b

func _tab_style(bg: Color, underline: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = underline
	s.border_width_bottom = 3
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.content_margin_top = 6
	s.content_margin_bottom = 5
	return s

func _row_style(bg: Color, accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = accent
	s.border_width_left = 3
	s.set_corner_radius_all(3)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s
