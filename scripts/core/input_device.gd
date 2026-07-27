class_name InputDeviceTracker
extends Node
## Tracks which device the local player last used, so on-screen prompts can
## show the matching glyph (keyboard "E" / Xbox "Y" / PlayStation triangle).
## Autoload: InputDevice (the class name differs so it doesn't shadow it).

enum Kind { KEYBOARD, XBOX, PLAYSTATION }

signal kind_changed(kind: Kind)

var kind: Kind = Kind.KEYBOARD

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	var next := kind
	if event is InputEventKey or event is InputEventMouseButton:
		next = Kind.KEYBOARD
	elif event is InputEventJoypadButton:
		next = _pad_kind(event.device)
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		next = _pad_kind(event.device)
	if next != kind:
		kind = next
		kind_changed.emit(kind)

## Sony pads get the triangle glyph; everything else falls back to the Xbox
## face-button naming (which is also what generic XInput pads report).
func _pad_kind(device: int) -> Kind:
	var name := Input.get_joy_name(device).to_lower()
	for token in ["playstation", "dualshock", "dualsense", "sony", "ps3", "ps4", "ps5"]:
		if name.contains(token):
			return Kind.PLAYSTATION
	return Kind.XBOX

## True when the current device draws its "interact" button as a shape rather
## than a letter (prompt widgets draw that shape themselves).
func uses_shape_glyph() -> bool:
	return kind == Kind.PLAYSTATION

## Letter shown on the interact button for the current device.
func interact_letter() -> String:
	match kind:
		Kind.XBOX: return "Y"
		Kind.PLAYSTATION: return ""
		_: return "E"

## Spelled-out button name, for hint text where a drawn glyph isn't available.
func interact_label() -> String:
	match kind:
		Kind.XBOX: return "Y"
		Kind.PLAYSTATION: return "Triangle"
		_: return "E"

## Name of the button that confirms a menu choice on the current device.
func accept_label() -> String:
	match kind:
		Kind.XBOX: return "A"
		Kind.PLAYSTATION: return "Cross"
		_: return "Enter"

## Everything that picks a menu entry on the current device — on a keyboard E
## works alongside Enter, on a pad it is the bottom face button ONLY.
func menu_accept_label() -> String:
	if kind == Kind.KEYBOARD:
		return "E / Enter"
	return accept_label()

## THE NUMBER ROW, and it belongs to whoever is on top. 1-9 pick a hotbar slot
## out in the world and an answer in the dialog box, which are the same gesture
## in two places — "the thing labelled 3" — so they are ONE set of bindings read
## through one function rather than a set per screen that could drift apart.
## Nine actions rather than reading a keycode: a number key is still a control a
## player presses, so it lives in the input map like every other one.
##
## Keyboard only, deliberately. There is no pad equivalent of nine buttons, and
## everything they reach has a pad way already (R1/L1 walk the bar, the stick
## walks a menu).
const NUMBER_ACTIONS := ["number_1", "number_2", "number_3", "number_4",
		"number_5", "number_6", "number_7", "number_8", "number_9"]

## Which number this event just pressed, 1-9, or 0 for anything else. The caller
## decides what its Nth thing is; nothing here knows about hotbars or answers.
func number_pressed(event: InputEvent) -> int:
	for i in NUMBER_ACTIONS.size():
		if event.is_action_pressed(NUMBER_ACTIONS[i]):
			return i + 1
	return 0

## True when this event picks the focused menu entry. On a pad that is strictly
## the bottom face button (PS5 Cross / Xbox A — the same physical place), never
## the interact button: Y / triangle is the world's "press at a thing" and
## letting it double as a menu confirm made the two blur together.
func is_menu_accept(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept"):
		return true
	return event.is_action_pressed("interact") and not (event is InputEventJoypadButton)

## Spelled-out name of whatever button an action is on for the device in use —
## what the tutorial's prompts show. These mirror the bindings in
## project.godot's input map; a rebinding has to be reflected here by hand,
## because Godot's own event names ("Joypad Button 5") are not what a player
## calls the button.
func action_label(action: String) -> String:
	match action:
		"attack":
			match kind:
				Kind.XBOX: return "RT"
				Kind.PLAYSTATION: return "R2"
				_: return "Left Mouse"
		"block":
			match kind:
				Kind.XBOX: return "LT"
				Kind.PLAYSTATION: return "L2"
				_: return "Right Mouse"
		"lock_on":
			match kind:
				Kind.KEYBOARD: return "Middle Mouse"
				_: return "R3"
		"jump", "slide":
			match kind:
				Kind.XBOX: return "A"
				Kind.PLAYSTATION: return "Cross"
				_: return "Space"
		"interact":
			return interact_label()
		"inventory":
			match kind:
				Kind.KEYBOARD: return "Tab"
				_: return "D-pad Up"
		"use_item":
			match kind:
				Kind.XBOX: return "RT"
				Kind.PLAYSTATION: return "R2"
				_: return "F"
		"voice_talk":
			match kind:
				Kind.XBOX: return "LS"
				Kind.PLAYSTATION: return "L3"
				_: return "V"
		"voice_mode":
			return "M" # keyboard only for now, like sprint
	return action
