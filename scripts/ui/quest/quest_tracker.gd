extends Control
class_name QuestTracker
## The quest corner: a "Current Quest: ★" heading with what you are actually on
## underneath it. It sits under the health and stamina bars but over on the
## opposite side of the screen, so the top-left corner stays the vitals corner
## and quests get one of their own.
##
## Two rows rather than one, because the objective alone read as a label of
## itself — "Kill the bandits" in the corner says nothing about why it is there.
## The heading keeps the place (and the star) the single row used to have, and
## the objective moved down under it.
##
## The star is DRAWN, not typed: Godot's default font (Open Sans) has no U+2605,
## so a ★ in a Label comes out as tofu. It is the same polygon as the enemy
## wind-up star in `hud.gd`, in the same gold — the HUD's "pay attention"
## colour — which keeps the two reading as one language.
##
## It shows the quest you are actually on, and nothing at all when you are on
## none: the heading used to read "Current Quest ★" whether or not there was
## one. The name comes from `GameStats.quest`, the read-only mirror of the
## server's copy, so this never decides anything — it reports.
## `quest_marker_overlay.gd` draws the same star out in the world.
##
## It sits on a REAL panel, `UiTheme.panel()` — the same frame, edge and sheet
## of cracked paint every screen in the game is built from, so the corner is
## part of the same UI rather than two gold labels floating over the water. It
## used to be bare text with a heavy outline, which held up over sky and lost
## the objective completely against a pale beach or a lit fire.
##
## The one thing it does not take from `UiTheme` is the panel's opacity: a
## screen is SOLID because it is opened over a paused-feeling world, whereas
## this is up the entire time you are playing and a solid slab in the corner is
## a hole in the view. `PANEL_ALPHA` here is that trade — the world moving
## behind it is the point, and there is nothing on it worth cheating for.
##
## Fixed WIDTH on purpose. A panel that hugged its text would change size every
## time a counting quest ticked over, so the corner would breathe as you fought;
## a box that stays put is furniture, which is what the HUD wants.

## Gold accent, shared with the wind-up star and the NPC speech bubble.
const GOLD := Color(0.95, 0.79, 0.42)
const STAR_OUTER := 9.0
const STAR_INNER := 4.0
## Distance in from the right edge, and down from the top (clear of the bars,
## which end at y = 72).
const MARGIN := Vector2(24.0, 84.0)
const SIZE := Vector2(248.0, 64.0)
## The heading's share of the panel's inside. The objective takes the rest, and
## the star rides on the heading row — which is where the star has always been.
const HEADING_H := 22.0
## Space between the end of the heading and the star.
const STAR_GAP := 10.0
## Inside the frame: left, right, top, bottom. Tighter than a screen's padding
## because this is a corner label, not a page.
const PAD := Vector4i(14, 14, 6, 6)
## How much of the world it hides. See the note above — a HUD panel is the one
## place `UiTheme.PANEL_ALPHA` (solid) is the wrong answer.
const PANEL_ALPHA := 0.66

var _heading: Label
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# offsets, not `position`: with the anchors pinned to the top-right corner
	# these are measured from that corner, whereas `position` is parent-relative
	# and would put the heading off the left of the screen
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -MARGIN.x - SIZE.x
	offset_right = -MARGIN.x
	offset_top = MARGIN.y
	offset_bottom = MARGIN.y + SIZE.y

	# the shared frame: INK body, STONE edge, the sheet of paint over it. The
	# content goes in `body()`, never on the frame — that is where the padding
	# lives and what keeps the paint behind the text instead of beside it.
	var frame := UiTheme.panel(UiTheme.INK, PANEL_ALPHA, PAD, UiTheme.STONE)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.body(frame).add_child(rows)

	# the heading shares its row with the star, so the two live in a box of
	# their own; the objective gets the full width underneath
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", int(STAR_GAP))
	head_row.custom_minimum_size.y = HEADING_H
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(head_row)

	_heading = _row(head_row, 15)
	_heading.text = "Current Quest:"
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var star := StarBox.new()
	star.custom_minimum_size = Vector2(STAR_OUTER * 2.0, STAR_OUTER * 2.0)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(star)

	_label = _row(rows, 18)
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	GameStats.changed.connect(_refresh)
	_refresh()

## One right-aligned gold row of the block. The dark outline stays even now that
## there is a panel under it: the panel is deliberately see-through, so a bright
## sky still comes through behind the letters.
func _row(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true # a long name shortens rather than widening the panel
	parent.add_child(label)
	return label

## The purse sync is what carries the quest, so this rides GameStats.changed
## rather than polling every frame.
func _refresh() -> void:
	var quest := str(GameStats.quest)
	visible = quest != ""
	# a counting quest reads "Kill the bandits  7/25"; the rest just their name
	_label.text = QuestData.progress_label(quest, GameStats.quest_kills) if visible else ""

## The star, in a box of its own on the heading's row. It has to be a NODE now
## rather than the tracker's own `_draw`: a Control paints itself BEFORE its
## children, so a star drawn by the tracker would be behind the panel.
class StarBox:
	extends Control

	func _draw() -> void:
		# through the outer class by name: one star, one gold, one set of radii,
		# rather than an inner copy that can drift from the block around it
		draw_colored_polygon(_star_points(size * 0.5, QuestTracker.STAR_OUTER),
				QuestTracker.GOLD)

	static func _star_points(center: Vector2, outer: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var inner := outer * (QuestTracker.STAR_INNER / QuestTracker.STAR_OUTER)
		for i in 10:
			var r := outer if i % 2 == 0 else inner
			var a := -PI / 2.0 + TAU * i / 10.0
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		return pts
