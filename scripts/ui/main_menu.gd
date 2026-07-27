extends Control
## Start menu (also the boot scene). Players do not run servers: the game lives
## on one dedicated box (Net.DEFAULT_SERVER), so a signed-in player launches
## straight into it and never sees this screen.
##
## Accounts are Discord, through Supabase (see scripts/core/account/). The
## screen therefore has exactly one state machine:
##
##   no saved session   -> "LOG IN WITH DISCORD"
##   saved session      -> silently refresh it, then join. No screen at all.
##   signed in, failed  -> the reason, and a PLAY button to try again
##
## There is no guest path and no address box: your gold and your bag live in
## the database under your account, so playing without one would mean playing
## with nothing to save into — and there is one world to play in, so a player
## has nowhere else to point. Signing in is the only door, and PLAY is the only
## button behind it. LAN and localhost testing moved to --join, below, which
## pairs with a server started --allow-guests.
##
## The name field is what a player wants to be CALLED, which is not the same as
## who they are. The server still takes the name from Discord — this is kept for
## next time and sent on join, ready for the server half that honours it.
##
## Running from the editor hosts locally instead of joining that box, so a test
## run never disturbs the live world (and works with the server down).
##
## A dedicated server build (feature tag "server", or the --server flag) skips
## the UI entirely and hosts headlessly from here.
##
## CLI conveniences (work on any build, and each one suppresses the auto-join):
##   --username=NAME   the name to play under (a guest server's only one)
##   --host            host locally instead (LAN and development)
##   --join=IP[:PORT]  join some other address, e.g. 127.0.0.1 for a local test

const SETTINGS_PATH := "user://settings.cfg"
## Most of the window height the panel may take before it starts scrolling
## inside itself instead of growing off the bottom. Signed in is taller than
## signed out (there is a name to set), and someone's window is smaller than
## both — so the panel MEASURES its content every frame rather than being told
## a height that only suits one of the three.
const PANEL_MAX_SCREEN := 0.88

var name_edit: LineEdit
## The name field, which only means anything once there is an account behind
## it. Held as a container so `_refresh_account_ui` shows or hides it in ONE
## place, the same way it does the buttons.
var name_box: VBoxContainer
var scroll: ScrollContainer
var panel_box: VBoxContainer
var bar_gap: MarginContainer
var status_label: Label
var account_label: Label
var login_btn: Button
var play_btn: Button
var logout_btn: Button
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
	# we may have come back here mid-intro or mid-tutorial (a drop); don't
	# leave the black screen up, or a stale step on the way back in
	IntroCutscene.abort()
	Tutorial.client_leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_load_settings()
	Net.join_failed.connect(_on_join_failed)
	Auth.login_finished.connect(_on_login_finished)
	Auth.login_status.connect(func(m: String) -> void: status_label.text = m)
	Auth.logged_out.connect(_refresh_account_ui)
	_refresh_account_ui()

	# Arriving with an error means we just came BACK from a failed or dropped
	# connection. Showing the menu is the point then -- auto-joining would walk
	# straight into the same wall, forever.
	var returned_with_error := Net.last_error != ""
	if returned_with_error:
		status_label.text = Net.last_error
		Net.last_error = ""
	if _handle_cli_args() or returned_with_error:
		return
	# Playing from the editor is development, not playing the live game: host
	# locally so a test run never touches the dedicated box (and works offline).
	# A local listen server registers its own host entry, so this path needs no
	# Discord round trip.
	if OS.has_feature("editor"):
		_on_host_pressed()
		return

	# The returning-player path: a stored refresh token becomes a live session
	# without anything on screen, and then straight into the world.
	if Auth.has_saved_session():
		if await Auth.restore_session():
			_refresh_account_ui()
			_on_play_pressed()
			return
		status_label.text = "Your sign-in expired — log in again."
		_refresh_account_ui()

func _process(delta: float) -> void:
	_fit_panel()
	if _join_timeout > 0.0:
		_join_timeout -= delta
		if _join_timeout <= 0.0:
			Net.return_to_menu("Connection timed out.")

## Grow the panel to whatever is on it, up to PANEL_MAX_SCREEN of the window,
## and let it scroll past that. A ScrollContainer reports no minimum height on
## the axis it scrolls, so the height has to be handed to it — and it changes
## with the state, since signing in adds a name field and an address row.
func _fit_panel() -> void:
	if scroll == null or panel_box == null:
		return
	var cap := get_viewport_rect().size.y * PANEL_MAX_SCREEN
	scroll.custom_minimum_size.y = minf(bar_gap.get_combined_minimum_size().y, cap)
	# Inset the content by the scrollbar only while there IS one, so the short
	# signed-out panel is not left with a stripe of nothing down its side.
	var bar := scroll.get_v_scroll_bar()
	bar_gap.add_theme_constant_override("margin_right",
			int(bar.size.x) if bar.visible else 0)

# ---------------- account ----------------

func _on_login_pressed() -> void:
	login_btn.disabled = true
	status_label.text = "Opening Discord..."
	Auth.login_with_discord()

func _on_login_finished(ok: bool, message: String) -> void:
	login_btn.disabled = false
	status_label.text = message
	_refresh_account_ui()
	if ok:
		# Just created an account, or just signed back in — either way the
		# player asked to play, so do not make them press a second button.
		_on_play_pressed()

func _on_logout_pressed() -> void:
	Auth.log_out()
	status_label.text = "Signed out."

## One place decides what is on screen, so the signed-in and signed-out layouts
## can never drift apart.
func _refresh_account_ui() -> void:
	var signed_in := Auth.logged_in()
	account_label.text = "Signed in as %s" % Auth.username if signed_in else ""
	account_label.visible = signed_in
	login_btn.visible = not signed_in
	play_btn.visible = signed_in
	logout_btn.visible = signed_in
	# Signed out there is no way into the world at all, and nothing to be
	# called. Discord is the only door.
	name_box.visible = signed_in
	# First sign-in fills the box with the Discord name, so the field shows what
	# the player is ALREADY called rather than an empty box that means "Player".
	if signed_in and name_edit.text.strip_edges().is_empty():
		name_edit.text = Auth.username

# ---------------- actions ----------------

## What this player would like to be called: their own choice if they have made
## one, and the name Discord knows them by otherwise.
func _username() -> String:
	var chosen := name_edit.text.strip_edges()
	if not chosen.is_empty():
		return chosen
	return Auth.username if Auth.logged_in() else "Player"

func _on_host_pressed() -> void:
	_save_settings()
	status_label.text = "Starting server..."
	if Net.host_game(_username()) != OK:
		status_label.text = Net.last_error

## The normal way in: the one server everybody plays on.
func _on_play_pressed() -> void:
	_connect_to(Net.DEFAULT_SERVER)

func _connect_to(address: String) -> void:
	_save_settings()
	var addr := address
	var port := Net.DEFAULT_PORT
	if ":" in addr:
		port = maxi(1, addr.get_slice(":", 1).to_int())
		addr = addr.get_slice(":", 0)
	# Renew first if the access token is close to expiring: the server checks
	# it with Supabase, and a token that dies mid-handshake reads to the player
	# as a mysterious refusal.
	var token := ""
	if Auth.logged_in():
		token = await Auth.fresh_token()
	status_label.text = "Connecting to %s..." % addr
	play_btn.disabled = true
	if Net.join_game(addr, _username(), port, token) == OK:
		_join_timeout = 12.0
	else:
		_on_join_failed(Net.last_error)

func _on_join_failed(reason: String) -> void:
	_join_timeout = 0.0
	status_label.text = reason
	play_btn.disabled = false

## True if any flag took over, so the caller knows not to auto-join as well.
func _handle_cli_args() -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--username="):
			name_edit.text = a.get_slice("=", 1)
	for a in args:
		if a == "--host":
			_on_host_pressed()
			return true
		if a.begins_with("--join="):
			# The only way to reach an address other than the main server. There
			# is no box for it any more: a player has exactly one world, and a
			# test run says so on the command line.
			_connect_to(a.get_slice("=", 1))
			return true
	return false

# ---------------- settings ----------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		name_edit.text = cfg.get_value("net", "username", "")

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	# load first: Voice keeps its mode in this same file, and saving a fresh
	# ConfigFile over the top would quietly wipe whatever else is in it
	cfg.load(SETTINGS_PATH)
	cfg.set_value("net", "username", name_edit.text.strip_edges())
	cfg.save(SETTINGS_PATH)

# ---------------- construction ----------------

func _build_ui() -> void:
	# there is no world behind this one, so the sheet is the whole screen
	add_child(UiTheme.backdrop(1.0))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UiTheme.panel(UiTheme.INK, 0.96, Vector4i(28, 28, 28, 28))
	center.add_child(panel)

	# Everything below sits inside a scroller, so the menu cannot run off the
	# bottom of a short window — see PANEL_MAX_SCREEN and _fit_panel.
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UiTheme.body(panel).add_child(scroll)

	# The bar is drawn INSIDE the scroller, over its right edge, so the content
	# is inset by exactly its width when it appears — otherwise it sits on top
	# of the JOIN button. _fit_panel keeps the inset honest.
	bar_gap = MarginContainer.new()
	scroll.add_child(bar_gap)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	bar_gap.add_child(box)
	panel_box = box

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

	box.add_child(_spacer(12))

	account_label = Label.new()
	account_label.add_theme_font_size_override("font_size", 13)
	account_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
	account_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(account_label)

	# Discord blurple, so the button reads as "the Discord one" at a glance.
	login_btn = Button.new()
	login_btn.text = "LOG IN WITH DISCORD"
	login_btn.custom_minimum_size = Vector2(0, 46)
	var blurple := StyleBoxFlat.new()
	blurple.bg_color = Color(0.345, 0.396, 0.949)
	blurple.set_corner_radius_all(6)
	login_btn.add_theme_stylebox_override("normal", blurple)
	var blurple_hover := blurple.duplicate() as StyleBoxFlat
	blurple_hover.bg_color = Color(0.42, 0.46, 0.98)
	login_btn.add_theme_stylebox_override("hover", blurple_hover)
	login_btn.add_theme_color_override("font_color", Color.WHITE)
	login_btn.pressed.connect(_on_login_pressed)
	box.add_child(login_btn)

	play_btn = Button.new()
	play_btn.text = "PLAY"
	play_btn.custom_minimum_size = Vector2(0, 46)
	play_btn.pressed.connect(_on_play_pressed)
	box.add_child(play_btn)

	var hint := _small_label("Your gold, bag and score are saved to your account.\nYou will join automatically next time you launch.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	logout_btn = Button.new()
	logout_btn.text = "log out"
	logout_btn.flat = true
	logout_btn.pressed.connect(_on_logout_pressed)
	box.add_child(logout_btn)

	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.25))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	# The name you play under. Your account is your Discord account, but the
	# thing above everyone else's head does not have to be your Discord name.
	name_box = VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 4)
	box.add_child(name_box)
	name_box.add_child(_spacer(6))
	name_box.add_child(_small_label("DISPLAY NAME"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "your Discord name"
	name_edit.max_length = NetRegistry.NAME_LIMIT
	name_edit.text_submitted.connect(func(_t: String) -> void: _on_play_pressed())
	name_box.add_child(name_edit)
	# Said out loud rather than left to be discovered: the server still takes
	# the name from Discord, so until it accepts this one, changing it here
	# changes nothing anybody else can see.
	name_box.add_child(_small_label(
		"Kept for next time. Other players still see your Discord name\nuntil the server accepts the change."))

	box.add_child(_spacer(10))
	box.add_child(_small_label("VOICE CHAT"))
	# the one setting the menu owns besides the name, because it is also the one
	# a player wants to decide BEFORE walking into a world with an open mic
	var open_mic := CheckButton.new()
	open_mic.text = "Open mic (talks when you do)"
	open_mic.button_pressed = Voice.is_open_mic()
	open_mic.toggled.connect(func(on: bool) -> void:
		Voice.set_mode(Voice.Mode.OPEN_MIC if on else Voice.Mode.PUSH_TO_TALK))
	box.add_child(open_mic)
	box.add_child(_small_label("Off: hold V (L3 on a pad) to talk. M switches in game.\nOnly players standing near you can hear it."))

	box.add_child(_spacer(8))
	var controls := _small_label("WASD move  •  LMB punch (hold = heavy)  •  RMB block  •  MMB lock-on\nSPACE jump  •  CTRL slide (in air: dive)  •  TAB inventory  •  hold P scoreboard\nhold V talk  •  M mic mode")
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
