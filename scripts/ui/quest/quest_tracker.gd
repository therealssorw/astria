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

## Gold accent, shared with the wind-up star and the NPC speech bubble.
const GOLD := Color(0.95, 0.79, 0.42)
const STAR_OUTER := 9.0
const STAR_INNER := 4.0
## Distance in from the right edge, and down from the top (clear of the bars,
## which end at y = 72).
const MARGIN := Vector2(24.0, 84.0)
const SIZE := Vector2(240.0, 50.0)
## The heading's share of that height. The objective takes the rest, and the
## star rides on the heading row — which is where the star has always been, so
## growing the block downwards leaves the corner looking the same.
const HEADING_H := 22.0
## Space between the end of the heading and the star.
const STAR_GAP := 10.0

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

	_heading = _row(15)
	_heading.text = "Current Quest:"
	_heading.offset_right = -(STAR_OUTER * 2.0 + STAR_GAP) # leave the star its room
	_heading.offset_bottom = -(SIZE.y - HEADING_H)

	# the objective gets the full width: it is the longer of the two, and the
	# star is not sitting on this row to take any of it
	_label = _row(18)
	_label.offset_top = HEADING_H

	GameStats.changed.connect(_refresh)
	_refresh()

## One right-aligned gold row of the block, full-rect within it until the caller
## says otherwise. A thin dark outline instead of a panel behind it: the corner
## has to stay readable over bright sky and water without being boxed in.
func _row(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	return label

## The purse sync is what carries the quest, so this rides GameStats.changed
## rather than polling every frame.
func _refresh() -> void:
	var quest := str(GameStats.quest)
	visible = quest != ""
	# a counting quest reads "Kill the bandits  7/25"; the rest just their name
	_label.text = QuestData.progress_label(quest, GameStats.quest_kills) if visible else ""
	queue_redraw()

func _draw() -> void:
	if str(GameStats.quest) == "":
		return
	# on the heading's row, not the block's middle: the star belongs beside
	# "Current Quest:" exactly where the one-row version put it
	var center := Vector2(size.x - STAR_OUTER, HEADING_H * 0.5)
	draw_colored_polygon(_star_points(center, STAR_OUTER), GOLD)

func _star_points(center: Vector2, outer: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var inner := outer * (STAR_INNER / STAR_OUTER)
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
