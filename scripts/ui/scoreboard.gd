extends Control
## Hold-P scoreboard. Every number here comes from the server's registry
## (Net.players, replicated read-only) — clients can't inflate their own
## stats because clients never write them.

var panel: PanelContainer
var rows_box: VBoxContainer
var _refresh_left := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = UiTheme.panel(UiTheme.INK, 0.92, Vector4i(20, 20, 20, 20))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)

	rows_box = VBoxContainer.new()
	rows_box.custom_minimum_size = Vector2(460, 0)
	rows_box.add_theme_constant_override("separation", 4)
	UiTheme.body(panel).add_child(rows_box)

func _process(delta: float) -> void:
	var show := Input.is_action_pressed("scoreboard")
	if show and not visible:
		_refresh_left = 0.0
	visible = show
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.5
		_refresh()

func _refresh() -> void:
	for c in rows_box.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = "SCOREBOARD"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows_box.add_child(title)

	rows_box.add_child(_line(_server_line(), Color(0.6, 0.6, 0.65), 11))

	# sort by kills desc, then name, off the server-replicated registry
	var entries := []
	for id in Net.players:
		var e: Dictionary = Net.players[id]
		entries.append({"id": id, "name": e["name"], "kills": int(e["kills"]), "deaths": int(e["deaths"])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["kills"] != b["kills"]:
			return a["kills"] > b["kills"]
		return String(a["name"]) < String(b["name"]))

	if entries.is_empty():
		rows_box.add_child(_line("Nobody here yet.", Color(0.6, 0.6, 0.65), 13))
		return

	var most_kills: Dictionary = entries[0]
	var most_deaths: Dictionary = entries[0]
	for e: Dictionary in entries:
		if e["deaths"] > most_deaths["deaths"]:
			most_deaths = e
	rows_box.add_child(_line("Most kills:  %s (%d)" % [most_kills["name"], most_kills["kills"]],
			Color(0.95, 0.8, 0.25), 14))
	rows_box.add_child(_line("Most deaths:  %s (%d)" % [most_deaths["name"], most_deaths["deaths"]],
			Color(0.85, 0.45, 0.35), 14))
	rows_box.add_child(_spacer(6))

	rows_box.add_child(_row("PLAYER", "KILLS", "DEATHS", Color(0.6, 0.6, 0.65), 12))
	var my_id := multiplayer.get_unique_id()
	for e: Dictionary in entries:
		var col := Color(0.95, 0.95, 0.6) if int(e["id"]) == my_id else Color.WHITE
		rows_box.add_child(_row(String(e["name"]), str(e["kills"]), str(e["deaths"]), col, 15))

func _server_line() -> String:
	if multiplayer.is_server():
		match Net.upnp_status:
			"ok":
				return "Hosting — friends join:  %s:%d" % [Net.public_ip, Net.host_port]
			"searching":
				return "Hosting — UPnP setting up port %d..." % Net.host_port
			_:
				return "Hosting — UPnP failed: LAN only, or forward UDP %d yourself" % Net.host_port
	return "%d player(s) online" % Net.players.size()

func _line(text_val: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text_val
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _row(name_v: String, kills_v: String, deaths_v: String, color: Color, size: int) -> Control:
	var row := HBoxContainer.new()
	var n := Label.new()
	n.text = name_v
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var k := Label.new()
	k.text = kills_v
	k.custom_minimum_size = Vector2(90, 0)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var d := Label.new()
	d.text = deaths_v
	d.custom_minimum_size = Vector2(90, 0)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for l: Label in [n, k, d]:
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
		row.add_child(l)
	return row

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
