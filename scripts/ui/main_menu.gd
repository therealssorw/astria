extends Control
## Start menu (also the boot scene): pick a username, then host a server or
## join one by IP. A dedicated server build (feature tag "server", or the
## --server flag) skips the UI entirely and hosts headlessly from here.
##
## CLI conveniences (work on any build):
##   --username=NAME   prefill the username
##   --host            host immediately
##   --join=IP[:PORT]  join immediately

const SETTINGS_PATH := "user://settings.cfg"

var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label
var host_btn: Button
var join_btn: Button
var _join_timeout := 0.0

func _ready() -> void:
	if Net.should_run_dedicated():
		var port := Net.DEFAULT_PORT
		for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			if a.begins_with("--port="):
				port = maxi(1, a.get_slice("=", 1).to_int())
		print("[Server] Dedicated mode — hosting on port %d" % port)
		Net.host_game("", true, port)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_load_settings()
	Net.join_failed.connect(_on_join_failed)
	if Net.last_error != "":
		status_label.text = Net.last_error
		Net.last_error = ""
	_handle_cli_args()

func _process(delta: float) -> void:
	if _join_timeout > 0.0:
		_join_timeout -= delta
		if _join_timeout <= 0.0:
			Net.return_to_menu("Connection timed out.")

# ---------------- actions ----------------

func _username() -> String:
	var n := name_edit.text.strip_edges()
	return n if not n.is_empty() else "Player"

func _on_host_pressed() -> void:
	_save_settings()
	status_label.text = "Starting server..."
	if Net.host_game(_username()) != OK:
		status_label.text = Net.last_error

func _on_join_pressed() -> void:
	_save_settings()
	var addr := ip_edit.text.strip_edges()
	if addr.is_empty():
		status_label.text = "Enter the host's IP address."
		return
	var port := Net.DEFAULT_PORT
	if ":" in addr:
		port = maxi(1, addr.get_slice(":", 1).to_int())
		addr = addr.get_slice(":", 0)
	status_label.text = "Connecting to %s..." % addr
	host_btn.disabled = true
	join_btn.disabled = true
	if Net.join_game(addr, _username(), port) == OK:
		_join_timeout = 12.0
	else:
		_on_join_failed(Net.last_error)

func _on_join_failed(reason: String) -> void:
	_join_timeout = 0.0
	status_label.text = reason
	host_btn.disabled = false
	join_btn.disabled = false

func _handle_cli_args() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--username="):
			name_edit.text = a.get_slice("=", 1)
	for a in args:
		if a == "--host":
			_on_host_pressed()
			return
		if a.begins_with("--join="):
			ip_edit.text = a.get_slice("=", 1)
			_on_join_pressed()
			return

# ---------------- settings ----------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		name_edit.text = cfg.get_value("net", "username", "")
		ip_edit.text = cfg.get_value("net", "last_ip", "")

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "username", name_edit.text.strip_edges())
	cfg.set_value("net", "last_ip", ip_edit.text.strip_edges())
	cfg.save(SETTINGS_PATH)

# ---------------- construction ----------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.08, 0.1)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.15, 0.96)
	style.border_color = Color(0.45, 0.45, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "ASTRIA"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "online island brawl"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(_spacer(10))
	box.add_child(_small_label("USERNAME"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Player"
	name_edit.max_length = 20
	box.add_child(name_edit)

	box.add_child(_spacer(6))
	host_btn = Button.new()
	host_btn.text = "HOST GAME"
	host_btn.custom_minimum_size = Vector2(0, 42)
	host_btn.pressed.connect(_on_host_pressed)
	box.add_child(host_btn)

	var hint := _small_label("Hosting tries UPnP automatically — no port forwarding needed\non most routers. Friends join with your public IP.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	box.add_child(_spacer(10))
	box.add_child(_small_label("JOIN A SERVER"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "host ip (e.g. 203.0.113.7)"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	row.add_child(ip_edit)
	join_btn = Button.new()
	join_btn.text = "JOIN"
	join_btn.custom_minimum_size = Vector2(84, 0)
	join_btn.pressed.connect(_on_join_pressed)
	row.add_child(join_btn)

	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.25))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	box.add_child(_spacer(8))
	var controls := _small_label("WASD move  •  LMB punch (hold = heavy)  •  RMB block\nSPACE jump  •  CTRL slide (in air: dive)  •  TAB lock-on  •  hold P scoreboard")
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(controls)

	var quit := Button.new()
	quit.text = "QUIT"
	quit.flat = true
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

func _small_label(text_val: String) -> Label:
	var l := Label.new()
	l.text = text_val
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	return l

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
