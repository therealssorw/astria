extends CanvasLayer
## Developer cheat menu, opened with Z (or the PS5 Options / Xbox Menu button).
## Autoload: CheatMenu.
##
## EDITOR ONLY, on both ends. The menu refuses to build itself in an exported
## game, and the server refuses every cheat request unless it too is running
## from the editor (`Net.cheats_allowed`), so a shipped build has no cheats
## even if someone rebuilds the client. Nothing here writes game state
## locally — "Give item" asks the server exactly like a shop purchase does.
##
## Adding a cheat is one entry in `_build_root`: a button that calls a
## `Net.request_cheat_*`. The lists inside the pages come from the game's own
## data — ItemDb for "Give item", TeleportData for "Teleport" — so a new sword
## or a new destination shows up here the moment it is in the catalogue.


const GOLD := Color(0.95, 0.79, 0.42)
const DIM := Color(0.78, 0.79, 0.84)
const BAD := Color(0.9, 0.42, 0.36)
const ROW_H := 40
const PANEL_W := 460
const FLASH_TIME := 2.5

var _root: Control
var _title: Label
var _rows: VBoxContainer
var _hint: Label
var _open := false
var _page := "root" # "root" or "give"
var _flash_left := 0.0
var _player: Node

func _ready() -> void:
	if not OS.has_feature("editor"):
		set_process(false) # shipped builds never even build the menu
		set_process_input(false)
		return
	layer = 30 # above the shop and the dialog box
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ui_panel") # the pawn frees the pointer for whatever is open
	_build()
	_root.visible = false
	Net.trade_result.connect(_on_result)
	GameStats.changed.connect(_on_purse_changed)

func is_open() -> bool:
	return _open

func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_set_hint(_default_hint(), Color(1, 1, 1, 0.38))
	if Input.is_action_just_pressed("cheat_menu"):
		if _open:
			close()
		elif not ShopSystem.is_open():
			open()

## A conversation does NOT keep the menu shut: half of what these cheats are
## for is getting out of something that is talking to you — an NPC, or a gate you cannot find the button for. The box is closed on the
## way in so the two are never both listening for the same press.
func open() -> void:
	if _open:
		return
	_player = _local_player()
	if _player == null:
		return # not in the world yet (main menu) — nothing to cheat at
	if DialogSystem.is_open():
		DialogSystem.close()
	_open = true
	_page = "root"
	_root.visible = true
	if is_instance_valid(_player):
		_player.set("ui_open", true)
	_refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if is_instance_valid(_player):
		_player.set("ui_open", false)
	_player = null

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _page == "root":
			close()
		else:
			_page = "root"
			_refresh()
	elif InputDevice.is_menu_accept(event) or event.is_action_pressed("interact"):
		# swallow interact even when it no longer picks (pad Y), matching the
		# dialog box and the shop
		get_viewport().set_input_as_handled()
		if InputDevice.is_menu_accept(event):
			var focused := get_viewport().gui_get_focus_owner()
			if focused is Button:
				(focused as Button).pressed.emit()

# ---------------- pages ----------------

func _refresh() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if _page == "give":
		_build_give()
	elif _page == "teleport":
		_build_teleport()
	elif _page == "quest":
		_build_quest()
	else:
		_build_root()
	_set_hint(_default_hint(), Color(1, 1, 1, 0.38))
	var first := _first_button()
	if first:
		first.grab_focus()

func _build_root() -> void:
	_title.text = "Cheats"
	_add_row("Give item…", "", func() -> void:
		_page = "give"
		_refresh())
	_add_row("Teleport…", "", func() -> void:
		_page = "teleport"
		_refresh())
	_add_row("Quest…", "", func() -> void:
		_page = "quest"
		_refresh())
	# closes the menu first so you actually see the thing you asked for
	_add_row("Start tutorial", "island raid", func() -> void:
		close()
		Net.request_cheat_tutorial())

## Every place in TeleportData, whether or not it has been built yet — a
## destination with no anchor in the level answers with that, which is more
## use while building one than quietly hiding it from the list.
func _build_teleport() -> void:
	_title.text = "Cheats  ›  Teleport"
	for id: String in TeleportData.ids():
		var placed := TeleportData.anchor(get_tree(), id) != null
		_add_row(TeleportData.label(id), "" if placed else "not in this level",
				func() -> void: Net.request_cheat_teleport(id))
	# Not a TeleportData destination, because it is not only a place: from
	# inside the tutorial it graduates you out of it (see
	# `Net._server_cheat_starter_town`) rather than dropping you through a wall
	# of the city and leaving the lesson running.
	_add_row("Enter starter town", "leaves the tutorial", func() -> void:
		Net.request_cheat_starter_town())
	_add_row("‹ Back", "", func() -> void:
		_page = "root"
		_refresh())

## Every quest in the catalogue, plus a way off the one you are on. A quest
## whose target is not in this level says so, exactly as teleports do — that is
## the useful answer while the place it points at is still being built.
func _build_quest() -> void:
	_title.text = "Cheats  ›  Quest"
	for id: String in QuestData.ids():
		var placed := QuestData.target_pos(get_tree(), id) != null
		var note := "" if placed else "target not in this level"
		if str(GameStats.quest) == id:
			note = "tracking" if placed else "tracking, no target here"
		_add_row(QuestData.label(id), note,
				func() -> void: Net.request_cheat_quest(id))
	_add_row("Clear quest", "", func() -> void: Net.request_cheat_quest(""))
	_add_row("‹ Back", "", func() -> void:
		_page = "root"
		_refresh())

func _build_give() -> void:
	_title.text = "Cheats  ›  Give item"
	for id: String in ItemDb.ITEMS:
		var held := GameStats.item_count(id)
		_add_row(ItemDb.item_name(id), "carrying %d" % held,
				func() -> void: Net.request_cheat_give(id), ItemDb.icon(id),
				ItemDb.description(id))
	_add_row("‹ Back", "", func() -> void:
		_page = "root"
		_refresh())

## The bag changed under us (the server answered a give) — redraw the counts.
func _on_purse_changed() -> void:
	if _open and _page == "give":
		_refresh.call_deferred() # can land inside a row button's own signal

func _on_result(message: String, ok: bool) -> void:
	if not _open:
		return
	# a teleport that worked gets out of the way, so you see where you landed;
	# one that was refused stays up with the reason on the hint line
	if ok and _page == "teleport":
		close()
		return
	_set_hint(message, GOLD if ok else BAD)
	_flash_left = FLASH_TIME

# ---------------- construction ----------------

func _local_player() -> Node:
	var found := get_tree().get_nodes_in_group("local_player")
	return found[0] if found.size() > 0 else null

func _first_button() -> Button:
	for c in _rows.get_children():
		if c is Button:
			return c
	return null

func _set_hint(text: String, color: Color) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", color)

func _default_hint() -> String:
	if not Net.cheats_allowed():
		return "This server has cheats off."
	return "%s — pick      Esc — %s" % [InputDevice.menu_accept_label(),
			"back" if _page != "root" else "close"]

## One row = a focusable button, styled like the shop's so the two read the same.
func _add_row(text: String, right_text: String, on_press: Callable,
		icon: Texture2D = null, tooltip := "") -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = ROW_H
	b.tooltip_text = tooltip
	b.icon = icon
	b.expand_icon = true
	b.add_theme_constant_override("h_separation", 10)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", DIM)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _row_style(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0)))
	var hot := _row_style(Color(1, 1, 1, 0.10), Color(0.95, 0.79, 0.42, 0.95))
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", hot)
	b.add_theme_stylebox_override("pressed", _row_style(Color(1, 1, 1, 0.16), GOLD))
	b.pressed.connect(on_press)

	if right_text != "":
		var right := Label.new()
		right.text = right_text
		right.add_theme_font_size_override("font_size", 15)
		right.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		right.set_anchors_preset(Control.PRESET_FULL_RECT)
		right.offset_right = -14
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(right)

	_rows.add_child(b)

func _row_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.border_color = Color(0.95, 0.79, 0.42, 0.5) # gold edge: this isn't a normal screen
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_child(vbox)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", GOLD)
	vbox.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W, ROW_H * 6)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
	vbox.add_child(_hint)
