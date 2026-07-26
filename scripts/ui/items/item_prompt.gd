extends Control
## The two buttons for whatever is in your hand, bottom-right of the screen:
##
##     [F]  Swing
##        [Right Mouse]  Block
##
## USE on top, SPECIAL indented under it — the indent is the whole of saying
## "this one is the other thing", without a heading or a box to draw. See
## ItemDb's header for what the pair means; this only reports it.
##
## The button names come from `InputDevice`, so they follow the last device
## that was actually touched: F / Right Mouse on a keyboard, RT / LT on an Xbox
## pad, R2 / L2 on a PlayStation one. Nothing here knows a binding.
##
## Purely local and purely cosmetic. What is in the hand comes from the server
## (`Net.held_of`), and pressing either button is a request like any other —
## this cannot make anything happen.

## In from the bottom-right corner, and how far the special is pushed right of
## the use line.
const MARGIN := Vector2(24.0, 24.0)
const INDENT := 22.0
const ROW_GAP := 4.0
const KEY_SIZE := 15
const VERB_SIZE := 17
## Gold is the game's "pay attention" accent and a prompt that is up the whole
## time is not that, so the button name gets it and the verb stays plain.
const KEY_COLOR := Color(0.95, 0.79, 0.42)
const VERB_COLOR := Color(0.88, 0.88, 0.92, 0.92)

var _rows: VBoxContainer
var _use_key: Label
var _use_verb: Label
var _special_key: Label
var _special_verb: Label
var _shown := ""     # last thing drawn, so the labels are only rebuilt on a change

func _ready() -> void:
	name = "ItemPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored to the bottom-right, and sized by hand: a code-built Control has
	# never been laid out, so a preset alone would leave this 0x0 with the
	# anchors merely looking right (see CLAUDE.md).
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN

	# LEFT-aligned inside the block, even though the block itself sits in the
	# right-hand corner. That is what makes the indent visible at all: with the
	# rows flushed right, pushing the special line over only makes its row wider
	# and both lines still end on the same column.
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", int(ROW_GAP))
	_rows.alignment = BoxContainer.ALIGNMENT_BEGIN
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)

	var use_row := _row(0.0)
	_use_key = use_row[0]
	_use_verb = use_row[1]
	var special_row := _row(INDENT)
	_special_key = special_row[0]
	_special_verb = special_row[1]

	# Rebuilt when the device changes (the button names move with it) and when
	# the hotbar does (a different thing is in hand).
	InputDevice.kind_changed.connect(func(_k: int) -> void: _refresh())
	Net.player_list_changed.connect(_refresh)
	GameStats.changed.connect(_refresh)
	_refresh()

## One line: the button in gold, then what it does. Returns [key, verb].
func _row(indent: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if indent > 0.0:
		var pad := Control.new()
		pad.custom_minimum_size.x = indent
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pad)

	var key := Label.new()
	key.add_theme_font_size_override("font_size", KEY_SIZE)
	key.add_theme_color_override("font_color", KEY_COLOR)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key)

	var verb := Label.new()
	verb.add_theme_font_size_override("font_size", VERB_SIZE)
	verb.add_theme_color_override("font_color", VERB_COLOR)
	verb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(verb)

	_rows.add_child(row)
	return [key, verb]

func _refresh() -> void:
	var held := _held_id()
	var use := ItemDb.use_label(held)
	var special := _special_label(held)
	# Only touch the labels when something really changed: this is wired to
	# every registry sync, and the bar re-syncs on each hotbar press.
	var state := "%s|%s|%s|%s" % [held, use, special, InputDevice.kind]
	if state == _shown:
		return
	_shown = state

	_use_key.text = "[%s]" % InputDevice.action_label("use_item")
	_use_verb.text = use
	# A use that does nothing says nothing rather than saying "nothing" — the
	# line simply is not there, which is also true of most of the catalogue.
	_use_key.get_parent().visible = use != ""

	_special_key.text = "[%s]" % InputDevice.action_label("block")
	_special_verb.text = special
	_rows.reset_size()
	# Sized to its content and then pushed in from the corner by hand, for the
	# anchoring reason in _ready.
	custom_minimum_size = _rows.get_combined_minimum_size()
	size = custom_minimum_size
	offset_left = -size.x - MARGIN.x
	offset_top = -size.y - MARGIN.y
	offset_right = -MARGIN.x
	offset_bottom = -MARGIN.y

## What the special reads as right now. Armor is the one that changes with the
## state of the thing rather than being fixed: the button that puts a helmet on
## is the same button that takes it off again, and a prompt that always said
## "Equip" would be lying half the time.
func _special_label(held: String) -> String:
	if ItemDb.special_action(held) == ItemDb.SPECIAL_EQUIP \
			and GameStats.is_equipped(held):
		return "Take off"
	return ItemDb.special_label(held)

## The hotbar slot in hand, off the local mirror. Falls back to "" — bare
## hands — before the first purse sync, which is the honest answer then.
func _held_id() -> String:
	return GameStats.held_id()
