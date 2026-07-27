extends Control
## The boss's health, across the top of the screen: its name, one long bar, and a
## notch at the phase threshold so the halfway point is something you can SEE
## coming rather than something that happens to you.
##
## Built from `UiTheme` like every other screen — the same INK body, STONE edge
## and sheet of paint — and it breaks the "panels are solid" rule on exactly the
## dial the quest corner does, and for the same reason: it is up while you are
## fighting, and an opaque slab across the top of the screen is a hole in the
## view during the one fight where you need to see everything.
##
## It reads the SERVER's copy of the boss's health, through the replicated
## `health` every peer already gets from `cl_enemy_damaged`. Nothing here is
## authoritative and nothing here is networked: it is the same number, drawn.

## Which boss it shows: the nearest living one within this of the local player.
## Comfortably past the arena, so the bar does not flicker at the door.
const SHOW_RANGE := 45.0
const WIDTH := 620.0
const HEIGHT := 22.0
## Down from the top of the screen.
const DROP := 26.0
## How fast the bar slides to a new value. A boss taking 40 damage should read as
## a chunk coming off, not as a number changing.
const DRAIN_SPEED := 0.45
## Same red as the player's own health, so a bar is a bar.
const FILL := Color(0.85, 0.2, 0.2)
## What is left of the phase you are past — the bar behind the notch.
const SPENT := Color(0.4, 0.12, 0.12)
const OPACITY := 0.82

var _frame: PanelContainer
var _name_label: Label
var _bar: Control
var _boss: Node3D
var _shown := 0.0     # health fraction actually drawn, chasing the real one

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	# a code-built Control has never been sized, so the preset alone leaves it
	# 0x0 with the anchors merely looking right — see CLAUDE.md
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = DROP + HEIGHT + 46.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_frame = UiTheme.panel()
	_frame.modulate.a = OPACITY
	_frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_frame.offset_left = -WIDTH * 0.5
	_frame.offset_right = WIDTH * 0.5
	_frame.offset_top = DROP
	_frame.offset_bottom = DROP + HEIGHT + 42.0
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.body(_frame).add_child(box)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_label)

	_bar = BarControl.new()
	_bar.custom_minimum_size = Vector2(0, HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_bar)

func _process(delta: float) -> void:
	_boss = _nearest_boss()
	_frame.visible = _boss != null
	if _boss == null:
		_shown = 0.0
		return
	var want := clampf(float(_boss.health) / maxf(float(_boss.max_health), 1.0), 0.0, 1.0)
	_shown = move_toward(_shown, want, DRAIN_SPEED * delta)
	_name_label.text = str(_boss.get("display_name"))
	var bar := _bar as BarControl
	bar.fraction = _shown
	bar.notch = clampf(float(_boss.get("phase_two_at")), 0.0, 1.0)
	bar.queue_redraw()

## The boss this screen is in a fight with: nearest living one in range of the
## local pawn. Group-driven, so a second boss anywhere else in the world is not
## this player's problem.
func _nearest_boss() -> Node3D:
	var pawn := get_tree().get_first_node_in_group("local_player")
	if pawn == null or not is_instance_valid(pawn):
		return null
	var best: Node3D = null
	var best_d := SHOW_RANGE
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b) or b.get("dead"):
			continue
		var d: float = (b as Node3D).global_position.distance_to((pawn as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


class BarControl:
	extends Control
	## The bar itself. Drawn rather than built out of ColorRects because of the
	## notch: it moves with the boss's own `phase_two_at`, so a threshold changed
	## in the inspector moves the mark on screen with it.

	var fraction := 1.0
	var notch := 0.5

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), UiTheme.tint(UiTheme.INK, 0.55))
		# what is left, and behind it the darker stripe up to the notch: the
		# second phase is a different colour of the same bar, so "how far to the
		# turn" is readable at a glance
		if fraction > 0.0:
			draw_rect(Rect2(Vector2(2, 2), Vector2((w - 4) * fraction, h - 4)),
					SPENT if fraction > notch else FILL)
		if fraction > notch:
			draw_rect(Rect2(Vector2(2, 2), Vector2((w - 4) * notch, h - 4)), FILL)
		var x := 2.0 + (w - 4.0) * notch
		draw_line(Vector2(x, 0), Vector2(x, h), UiTheme.STONE, 2.0)
