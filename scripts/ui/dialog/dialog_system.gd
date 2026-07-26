extends CanvasLayer
## Reusable NPC dialog box: semi-transparent black panel, typewriter text with
## a keyboard-clatter sound, and answer buttons the player picks with the
## mouse, WASD/arrows + E/Enter, or the gamepad stick + A.
## Autoload: DialogSystem. Conversation text lives in DialogData.
##
##     DialogSystem.start("blacksmith")

signal opened(dialog_id: String)
signal closed(dialog_id: String)
## Emitted when the player picks an answer carrying an "action" key.
signal action_triggered(dialog_id: String, action: String)

const TYPING_SFX := preload("res://Assets/Audio/SFX/UI/Typing/keyboard_typing.mp3")

const CHARS_PER_SEC := 42.0
const SENTENCE_PAUSE := 6.0   # extra "characters" of silence after . ! ?
const CLAUSE_PAUSE := 3.0     # ...and after , ; :
const TYPING_VOLUME_DB := -9.0
## Fallback pause for a line whose "auto" is not a number of seconds.
const AUTO_PAUSE := 1.5

var dialog_id := ""

var _root: Control
var _panel: PanelContainer
var _speaker: Label
var _body: Label
var _answers: VBoxContainer
var _hint: Label
var _sfx: AudioStreamPlayer

var _lines := {}
var _line_id := ""
var _full_text := ""
var _typing := false
var _type_accum := 0.0
var _auto_left := -1.0 # >= 0 while an "auto" line is counting down to its goto
## The current line split on "\n": each is typed on its own, in the same box.
var _pages: PackedStringArray = []
var _page := 0
## >= 0 while a finished page is being held before the next one is typed.
## -1 with pages left means it is waiting for a press instead.
var _page_left := -1.0
## Line ids already read in THIS conversation, so a loop back to one of them
## brings its choices back without saying it all again. Cleared by `start`.
var _read := {}
var _player: Node

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ui_panel") # the pawn frees the pointer for whatever is open
	_build()
	_root.visible = false
	set_process(false)

func is_open() -> bool:
	return dialog_id != ""

## Open `dialog_id` from DialogData. Returns false if there is no such entry.
##
## `speaker_node` is who is saying it, if anyone in the world is: the camera
## frames them and the cinematic bars come in for as long as the box is up.
## Leave it out for a line that comes from the player's own head — those are
## instructions, not scenes, and should not take the camera away.
func start(id: String, speaker_node: Node3D = null) -> bool:
	if not DialogData.has(id):
		push_warning("DialogSystem: no dialog named '%s'" % id)
		return false
	if is_instance_valid(speaker_node):
		Cinematic.focus(speaker_node)
	else:
		Cinematic.unfocus()
	var convo: Dictionary = DialogData.get_conversation(id)
	dialog_id = id
	_lines = convo.get("lines", {})
	_read = {} # a fresh conversation says everything again, including the opener
	_speaker.text = str(convo.get("speaker", ""))
	_speaker.visible = _speaker.text != ""
	_root.visible = true
	set_process(true)
	_player = _local_player()
	if is_instance_valid(_player):
		_player.set("ui_open", true)
	opened.emit(id)
	_show_line(str(convo.get("start", "")))
	return true

func close() -> void:
	if not is_open():
		return
	var was := dialog_id
	dialog_id = ""
	_typing = false
	_auto_left = -1.0
	_page_left = -1.0
	_pages = []
	_page = 0
	_sfx.stop()
	_root.visible = false
	set_process(false)
	_clear_answers()
	Cinematic.unfocus() # give the camera back; bars a cutscene is holding stay
	if is_instance_valid(_player):
		_player.set("ui_open", false)
	_player = null
	closed.emit(was)

# ---------------- conversation flow ----------------

func _show_line(line_id: String) -> void:
	if line_id == DialogData.END or not _lines.has(line_id):
		close()
		return
	_line_id = line_id
	var line: Dictionary = _lines[line_id]
	_clear_answers()
	# Coming BACK to a line already read — every "goto" that returns to the
	# question you branched off — keeps the answer you just finished reading on
	# screen and only brings the choices back. Retyping the same paragraph each
	# time round the loop reads as though the NPC forgot they had said it, and
	# it makes the reply you actually asked for disappear as you finish it.
	if _read.has(line_id):
		_typing = false
		_page_left = -1.0
		_build_answers(line)
		return
	_read[line_id] = true
	# A "\n" in a line is a PAGE BREAK, not a line break: the box clears and
	# types the next part in the same breath, the way the two halves of the
	# intro monologue read. Wrapping is the Label's job, not the writer's.
	_pages = []
	for part in str(line.get("text", "")).split("\n"):
		var trimmed := str(part).strip_edges()
		if trimmed != "":
			_pages.append(trimmed)
	if _pages.is_empty():
		_pages.append("")
	_page = 0
	_start_page()

## Begin typing the current page of the current line.
func _start_page() -> void:
	_full_text = _pages[_page]
	_body.text = _full_text
	_body.visible_characters = 0
	_type_accum = 0.0
	_auto_left = -1.0
	_page_left = -1.0
	_typing = true
	_hint.text = "%s — skip" % InputDevice.menu_accept_label()
	_hint.visible = true
	_start_typing_sfx()

func _finish_typing() -> void:
	_typing = false
	_body.visible_characters = -1
	_sfx.stop()
	var line: Dictionary = _lines.get(_line_id, {})
	# more of this line to say: hold the finished page for a beat (or for a
	# press) and then wipe it for the next one — the answers wait for the end
	if _page < _pages.size() - 1:
		var auto: Variant = line.get("auto")
		_page_left = (float(auto) if auto is float or auto is int else AUTO_PAUSE) \
				if auto != null else -1.0
		_hint.text = "%s — continue" % InputDevice.menu_accept_label()
		return
	_build_answers(line)

## Wipe the box and type the next page of the same line.
func _next_page() -> void:
	if _page >= _pages.size() - 1:
		return
	_page += 1
	_start_page()

## A line with no explicit answers still gets one button, so keyboard and
## gamepad advance the same way everywhere — unless it is an "auto" line, which
## is a monologue that advances itself after a beat (see DialogData's header).
func _build_answers(line: Dictionary) -> void:
	var auto: Variant = line.get("auto")
	if auto != null:
		_auto_left = float(auto) if auto is float or auto is int else AUTO_PAUSE
		_hint.text = "%s — skip" % InputDevice.interact_label()
		return
	var list: Array = line.get("answers", [])
	if list.is_empty():
		var goto := str(line.get("goto", DialogData.END))
		list = [{"text": "Goodbye." if goto == DialogData.END else "Continue", "goto": goto}]
	for i in list.size():
		var answer: Dictionary = list[i]
		var btn := _answer_button("%d.  %s" % [i + 1, str(answer.get("text", "..."))])
		btn.pressed.connect(_on_answer.bind(answer))
		_answers.add_child(btn)
	_answers.visible = true
	_hint.text = "%s — choose      %s — move" % [InputDevice.menu_accept_label(),
			"stick" if InputDevice.kind != InputDeviceTracker.Kind.KEYBOARD else "W S"]
	if _answers.get_child_count() > 0:
		(_answers.get_child(0) as Button).grab_focus()

func _on_answer(answer: Dictionary) -> void:
	# emit AFTER the line change: an answer that both ends the conversation and
	# fires an action (a shop, say) must not have close() undo what it opened
	var action := str(answer.get("action", ""))
	var id := dialog_id
	_show_line(str(answer.get("goto", DialogData.END)))
	if action != "":
		action_triggered.emit(id, action)

## Follow an "auto" line's goto, either because its beat ran out or because the
## player pressed interact to hurry it.
func _advance_auto() -> void:
	_auto_left = -1.0
	var line: Dictionary = _lines.get(_line_id, {})
	_show_line(str(line.get("goto", DialogData.END)))

func _clear_answers() -> void:
	for c in _answers.get_children():
		_answers.remove_child(c) # detach now so the next line's buttons index from 0
		c.queue_free()
	_answers.visible = false

# ---------------- per-frame ----------------

func _process(delta: float) -> void:
	# the pawn can die or despawn mid-conversation
	if not _typing and not is_instance_valid(_player):
		_player = _local_player()
	if _page_left >= 0.0:
		_page_left -= delta
		if _page_left < 0.0:
			_next_page()
		return
	if _auto_left >= 0.0:
		_auto_left -= delta
		if _auto_left < 0.0:
			_advance_auto()
		return
	if not _typing:
		return
	_type_accum += delta * CHARS_PER_SEC
	while _type_accum >= 1.0 and _body.visible_characters < _full_text.length():
		_body.visible_characters += 1
		_type_accum -= 1.0
		var ch := _full_text[_body.visible_characters - 1]
		if ".!?".contains(ch):
			_type_accum -= SENTENCE_PAUSE
		elif ",;:".contains(ch):
			_type_accum -= CLAUSE_PAUSE
	if _body.visible_characters >= _full_text.length():
		_finish_typing()

func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	var accept := InputDevice.is_menu_accept(event)
	if not accept and not event.is_action_pressed("interact"):
		return
	# an interact press is swallowed even when it no longer chooses (pad Y):
	# left unhandled it reaches the NPC and reopens the conversation we are in
	get_viewport().set_input_as_handled()
	if not accept:
		return
	if _typing:
		_finish_typing()
	elif _page < _pages.size() - 1:
		_next_page() # more of this line to say before there is anything to pick
	elif _auto_left >= 0.0:
		_advance_auto() # a cutscene line: hurry it along instead of choosing
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button and focused.get_parent() == _answers:
			(focused as Button).pressed.emit()
		elif _answers.get_child_count() > 0:
			(_answers.get_child(0) as Button).grab_focus()

# ---------------- audio ----------------

func _start_typing_sfx() -> void:
	if _full_text.strip_edges() == "":
		return
	# start somewhere random in the loop so every line doesn't sound identical
	var length := _sfx.stream.get_length()
	_sfx.play(randf() * maxf(length - 1.0, 0.0))

# ---------------- construction ----------------

func _local_player() -> Node:
	var found := get_tree().get_nodes_in_group("local_player")
	return found[0] if found.size() > 0 else null

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.16
	_panel.anchor_right = 0.84
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -44
	_panel.offset_bottom = -44
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.68)
	style.border_color = Color(1, 1, 1, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 21)
	_speaker.add_theme_color_override("font_color", Color(0.95, 0.79, 0.42))
	vbox.add_child(_speaker)

	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 19)
	_body.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	_body.add_theme_constant_override("line_spacing", 5)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.y = 78
	vbox.add_child(_body)

	_answers = VBoxContainer.new()
	_answers.add_theme_constant_override("separation", 2)
	_answers.visible = false
	vbox.add_child(_answers)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(_hint)

	_sfx = AudioStreamPlayer.new()
	var stream: AudioStreamMP3 = TYPING_SFX.duplicate()
	stream.loop = true # one long clatter clip, looped for as long as text types
	_sfx.stream = stream
	_sfx.volume_db = TYPING_VOLUME_DB
	add_child(_sfx)

func _answer_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(0.78, 0.79, 0.84))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _answer_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	var hot := _answer_style(Color(1, 1, 1, 0.09), Color(0.95, 0.79, 0.42, 0.95))
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", hot)
	b.add_theme_stylebox_override("pressed", _answer_style(Color(1, 1, 1, 0.16), Color(0.95, 0.79, 0.42, 1)))
	return b

## Flat row with a gold bar down the left edge when it is hovered/focused.
func _answer_style(bg: Color, accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = accent
	s.border_width_left = 3
	s.set_corner_radius_all(3)
	s.content_margin_left = 12
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s
