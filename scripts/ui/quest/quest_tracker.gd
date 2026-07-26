extends Control
class_name QuestTracker
## "Current Quest ★" heading, sitting under the health and stamina bars but
## over on the opposite side of the screen, so the top-left corner stays the
## vitals corner and quests get one of their own.
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
const SIZE := Vector2(240.0, 26.0)
## Space between the end of the text and the star.
const STAR_GAP := 10.0

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

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", GOLD)
	# a thin dark outline instead of a panel behind it: the heading has to stay
	# readable over bright sky and water without boxing in the corner
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_right = -(STAR_OUTER * 2.0 + STAR_GAP) # leave the star its room
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	GameStats.changed.connect(_refresh)
	_refresh()

## The purse sync is what carries the quest, so this rides GameStats.changed
## rather than polling every frame.
func _refresh() -> void:
	var quest := str(GameStats.quest)
	visible = quest != ""
	_label.text = QuestData.label(quest) if visible else ""
	queue_redraw()

func _draw() -> void:
	if str(GameStats.quest) == "":
		return
	var center := Vector2(size.x - STAR_OUTER, size.y * 0.5)
	draw_colored_polygon(_star_points(center, STAR_OUTER), GOLD)

func _star_points(center: Vector2, outer: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var inner := outer * (STAR_INNER / STAR_OUTER)
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
