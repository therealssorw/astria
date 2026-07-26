extends Control
## The tutorial's two pieces of screen furniture, added by hud.gd:
##
##   - the GATE PROMPT, centre screen: the button the fight is waiting on, big,
##     with one line saying what it is for. It is up only while the fight is
##     frozen, and it goes away the instant the player does the thing.
##   - the BANNER, under the quest heading: a line of nudging during the parts
##     that are just a fight. No box, no pause, nothing to dismiss.
##
## Both read `Tutorial.client_step_data()` and nothing else, so the tutorial
## script decides what is on screen and this file only knows how to draw it.
##
## The button NAME comes from InputDevice, so a pad player is never told to
## press a key that isn't on their pad. Styling follows the dialog box and the
## cheat menu (black panel, gold accent) — a prompt is not a new language.

const GOLD := Color(0.95, 0.79, 0.42)
const PULSE_SPEED := 3.0

var _gate: PanelContainer
var _button: Label
var _hint: Label
var _banner: Label
var _t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_gate.visible = false
	_banner.visible = false

func _process(delta: float) -> void:
	_t += delta
	var step: Dictionary = Tutorial.client_step_data()
	_update_gate(step)
	_update_banner(step)

## The prompt waits for the box: a line is being spoken, and asking someone to
## swing while they cannot move would be asking them to fail.
func _update_gate(step: Dictionary) -> void:
	var show_gate := str(step.get("kind", "")) == "gate" and not DialogSystem.is_open()
	_gate.visible = show_gate
	if not show_gate:
		return
	var action := str(step.get("action", ""))
	var button := InputDevice.action_label(TutorialData.gate_action_binding(action)).to_upper()
	# "HOLD X" rather than "X": a heavy swing and a jab are the same button, and
	# a player who taps it gets a jab and no idea why the gate did not open
	_button.text = ("HOLD  " + button) if TutorialData.gate_is_hold(action) else button
	_hint.text = TutorialData.gate_hint(str(step.get("id", "")))
	_gate.modulate.a = 0.82 + 0.18 * sin(_t * PULSE_SPEED)

func _update_banner(step: Dictionary) -> void:
	var text := str(step.get("banner", ""))
	_banner.visible = text != "" and not DialogSystem.is_open()
	_banner.text = text

func _build() -> void:
	_gate = PanelContainer.new()
	_gate.set_anchors_preset(Control.PRESET_CENTER)
	_gate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gate.grow_vertical = Control.GROW_DIRECTION_BOTH
	_gate.offset_top = 90 # below the reticle, out of the fight's way
	_gate.offset_bottom = 90
	_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_gate.add_theme_stylebox_override("panel", style)
	add_child(_gate)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_gate.add_child(vbox)

	_button = Label.new()
	_button.add_theme_font_size_override("font_size", 34)
	_button.add_theme_color_override("font_color", GOLD)
	_button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_button)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
