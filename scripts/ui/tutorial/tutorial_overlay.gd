extends Control
## The tutorial's two pieces of screen furniture, added by hud.gd:
##
##   - the CONTROL POPUP, centre screen: what the control is called, the button
##     it is on, and a line saying what it does. This is how the tutorial
##     teaches — it does not talk, and nothing here takes the controls off the
##     player or has to be dismissed. It goes away the instant they do it.
##   - the BANNER, under the quest heading: a line of nudging during the parts
##     that are just a fight.
##
## Both read `Tutorial.client_step_data()` and nothing else, so the tutorial
## script decides what is on screen and this file only knows how to draw it.
##
## The button NAME comes from InputDevice, so a pad player is never told to
## press a key that isn't on their pad. Styling follows the dialog box and the
## cheat menu (black panel, gold accent) — a popup is not a new language.

const GOLD := Color(0.95, 0.79, 0.42)
const PULSE_SPEED := 3.0

var _gate: PanelContainer
var _title: Label
var _button: Label
var _hint: Label
var _banner: Label
var _t := 0.0

func _ready() -> void:
	# Full rect BY HAND. `set_anchors_preset()` keeps the control's current
	# rect by baking offsets to match it, and a code-built Control has never
	# been sized — so the preset leaves it 0x0 with the anchors merely looking
	# right. The HUD's drawing overlays get away with it (a _draw() call is not
	# clipped to the rect), but anything that LAYS OUT CHILDREN does not: the
	# popup was centring itself inside nothing, half off the left edge, and the
	# banner was anchored to a right edge sitting at x=0.
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_gate.visible = false
	_banner.visible = false

## Is the control popup actually on screen? Read by the test — the popup IS
## the tutorial's teaching now, so "the step had one" is not the same claim as
## "the player was shown one".
func showing_popup() -> bool:
	return _gate.visible

## ...and WHOLLY on screen. It was centring inside a zero-sized parent and
## hanging half off the left edge, which every flag-level check called a pass.
func popup_fully_visible() -> bool:
	if not _gate.visible:
		return false
	var rect := _gate.get_global_rect()
	var view := get_viewport().get_visible_rect().size
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 \
			and rect.end.x <= view.x and rect.end.y <= view.y

func _process(delta: float) -> void:
	_t += delta
	var step: Dictionary = Tutorial.client_step_data()
	_update_gate(step)
	_update_banner(step)

## A popup stands down while something else is talking to the player — an NPC,
## or the intro — so two boxes are never up at once.
func _update_gate(step: Dictionary) -> void:
	var popup: Dictionary = step.get("popup", {})
	var show_gate := str(step.get("kind", "")) == "gate" and not popup.is_empty() \
			and not DialogSystem.is_open()
	_gate.visible = show_gate
	if not show_gate:
		return
	var action := str(step.get("action", ""))
	var button := InputDevice.action_label(TutorialData.gate_action_binding(action)).to_upper()
	_title.text = str(popup.get("title", "")).to_upper()
	# "HOLD X" rather than "X": a heavy swing and a jab are the same button, and
	# a player who taps it gets a jab and no idea why nothing happened
	_button.text = ("HOLD  " + button) if TutorialData.gate_is_hold(action) else button
	_hint.text = str(popup.get("body", ""))
	_gate.modulate.a = 0.82 + 0.18 * sin(_t * PULSE_SPEED)

func _update_banner(step: Dictionary) -> void:
	var text := str(step.get("banner", ""))
	_banner.visible = text != "" and not DialogSystem.is_open()
	_banner.text = text

func _build() -> void:
	# gold edge, like the cheat menu: a lesson is not an ordinary panel
	_gate = UiTheme.panel(UiTheme.INK, 0.72, Vector4i(26, 26, 12, 12),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.75))
	# Anchored to the middle of the screen BY HAND, and every offset set: the
	# PRESET_CENTER helper bakes absolute offsets out of whatever size the
	# control happens to have when it is called (zero, here), which pinned the
	# panel's centre to the top-left corner and hung half of it off the screen.
	# Anchors 0.5 with zero offsets and GROW_BOTH means "grow out from the
	# middle", which is what centring a self-sizing panel actually needs.
	_gate.anchor_left = 0.5
	_gate.anchor_right = 0.5
	_gate.anchor_top = 0.5
	_gate.anchor_bottom = 0.5
	_gate.offset_left = 0
	_gate.offset_right = 0
	_gate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gate.grow_vertical = Control.GROW_DIRECTION_BOTH
	_gate.offset_top = 90 # below the reticle, out of the fight's way
	_gate.offset_bottom = 90
	_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gate)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.custom_minimum_size.x = 460 # room for a sentence without it going thin
	UiTheme.body(_gate).add_child(vbox)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	_button = Label.new()
	_button.add_theme_font_size_override("font_size", 34)
	_button.add_theme_color_override("font_color", GOLD)
	_button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_button)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 460
	vbox.add_child(_hint)

	# same corner and colour as the quest heading, one line below it
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_banner.offset_left = -324
	_banner.offset_right = -24
	_banner.offset_top = 114
	_banner.offset_bottom = 138
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_banner.add_theme_font_size_override("font_size", 16)
	_banner.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_banner.add_theme_constant_override("outline_size", 4)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
