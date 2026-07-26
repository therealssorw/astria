@tool
extends VBoxContainer
## The Items tab: where the things characters carry and wear are made.
##
## It opens on a menu of what can be made rather than on an editor, because
## "Items" is not one thing — armor is the first kind, and the next (a weapon,
## a shield) is another button on that menu and another editor pane beside this
## one. Nothing about the armor pane is the tab itself.
##
## ARMOR is made HERE and worn in the NPC Builder. The split is deliberate: a
## suit is authored once, named, and then put on any number of characters in one
## move, so recolouring the guards is one file instead of twenty NPCs.
##
## The part picker and the turntable are the NPC Builder's own widgets, reused
## rather than copied — a suit is made of the same NpcParts an NPC's armor layer
## holds, and two colour-swatch editors that drift apart would be worse than the
## dependency. Both plugins ship together and are enabled together.

const Preview := preload("res://addons/npc_builder/ui/npc_preview.gd")
const SlotEditor := preload("res://addons/npc_builder/ui/part_slot_editor.gd")

## Edits arrive faster than a rig can be rebuilt (dragging inside a colour wheel
## fires continuously), so they are coalesced onto this delay.
const PREVIEW_DELAY := 0.08

## The suit is previewed ON somebody — a suit hanging in the air tells you
## nothing about whether it fits, and the rig has no notion of a character made
## only of armor (the height stack is built from feet, body and head).
const MANNEQUIN_SET := "Base"

var _suit: ArmorDefinition
## The mannequin wearing it: a plain villager whose armor layer is the suit.
var _worn: NpcDefinition

var _menu: Control
var _editor: Control
var _preview: SubViewportContainer
var _name_field: LineEdit
var _suit_picker: OptionButton
var _status: Label
var _target: Label
var _slots := {}
var _repaint: Timer

func _ready() -> void:
	# The editor's main screen is a VBoxContainer: it lays children out by their
	# size flags and ignores anchors, so without EXPAND the tab opens collapsed.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_repaint = Timer.new()
	_repaint.one_shot = true
	_repaint.wait_time = PREVIEW_DELAY
	_repaint.timeout.connect(_apply_to_preview)
	add_child(_repaint)

	add_child(_build_toolbar())
	_menu = _build_menu()
	add_child(_menu)
	_editor = _build_editor()
	add_child(_editor)
	_show_menu()

# ---------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------

func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var create := Button.new()
	create.text = "Create armor"
	create.tooltip_text = "Start a new suit"
	create.pressed.connect(_on_create_armor)
	bar.add_child(create)
	bar.add_child(VSeparator.new())
	var load_btn := Button.new()
	load_btn.text = "Open…"
	load_btn.pressed.connect(_on_open)
	bar.add_child(load_btn)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_on_save)
	bar.add_child(save)
	var rescan := Button.new()
	rescan.text = "Rescan parts"
	rescan.tooltip_text = "Pick up armor models added to the Armor folder since this tab opened"
	rescan.pressed.connect(_on_rescan)
	bar.add_child(rescan)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status)
	return bar

## What the tab opens on: what can be made, and what has been made already.
func _build_menu() -> Control:
	var centre := CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	centre.add_child(column)

	var title := Label.new()
	title.text = "Items"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var blurb := Label.new()
	blurb.text = "Make the things characters carry and wear.\nA suit made here is worn in the NPC Builder."
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.modulate = Color(1, 1, 1, 0.6)
	column.add_child(blurb)

	var create := Button.new()
	create.text = "Create armor"
	create.custom_minimum_size = Vector2(260, 46)
	create.pressed.connect(_on_create_armor)
	column.add_child(create)

	var open_row := HBoxContainer.new()
	open_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_suit_picker = OptionButton.new()
	_suit_picker.custom_minimum_size = Vector2(180, 0)
	open_row.add_child(_suit_picker)
	var open_btn := Button.new()
	open_btn.text = "Edit"
	open_btn.pressed.connect(_on_open_selected)
	open_row.add_child(open_btn)
	column.add_child(open_row)
	return centre

func _build_editor() -> Control:
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview = Preview.new()
	left.add_child(_preview)
	var controls := HBoxContainer.new()
	for clip in Preview.CLIPS:
		var button := Button.new()
		button.text = String(clip).capitalize()
		button.pressed.connect(func() -> void: _preview.play_clip(clip))
		controls.add_child(button)
	controls.add_child(VSeparator.new())
	var spin := CheckButton.new()
	spin.text = "Turntable"
	spin.button_pressed = true
	spin.toggled.connect(func(on: bool) -> void: _preview.set_turntable(on))
	controls.add_child(spin)
	left.add_child(controls)
	var hint := Label.new()
	hint.text = "Shown on a %s villager — armor is only ever seen on somebody" % MANNEQUIN_SET
	hint.modulate = Color(1, 1, 1, 0.55)
	left.add_child(hint)
	split.add_child(left)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	var heading := Label.new()
	heading.text = "Armor"
	heading.add_theme_font_size_override("font_size", 17)
	column.add_child(heading)

	var form := GridContainer.new()
	form.columns = 2
	column.add_child(form)
	var label := Label.new()
	label.text = "Name"
	form.add_child(label)
	_name_field = LineEdit.new()
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.text_changed.connect(_on_name_changed)
	form.add_child(_name_field)

	var pieces := Label.new()
	pieces.text = "Pieces"
	pieces.add_theme_font_size_override("font_size", 17)
	column.add_child(pieces)
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var editor := SlotEditor.new()
		column.add_child(editor)
		editor.setup(slot)
		editor.changed.connect(_queue_preview)
		_slots[slot] = editor

	_target = Label.new()
	_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target.modulate = Color(1, 1, 1, 0.6)
	column.add_child(_target)
	split.add_child(scroll)
	return split

# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

func _show_menu() -> void:
	_menu.visible = true
	_editor.visible = false
	_refresh_suit_list()

func _show_editor() -> void:
	_menu.visible = false
	_editor.visible = true

func _refresh_suit_list() -> void:
	_suit_picker.clear()
	var paths := ArmorLibrary.paths()
	for path in paths:
		_suit_picker.add_item(ArmorLibrary.title_of(path))
		_suit_picker.set_item_metadata(_suit_picker.item_count - 1, path)
	if paths.is_empty():
		_suit_picker.add_item("(no suits saved yet)")
		_suit_picker.disabled = true
	else:
		_suit_picker.disabled = false
		_suit_picker.select(0)

## A new suit starts already wearing the first of everything, so the tab shows
## something to react to instead of an invisible pile of empty slots.
func _starter_suit() -> ArmorDefinition:
	var suit := ArmorDefinition.new()
	var suits := NpcRig.list_categories(true)
	if suits.is_empty():
		return suit
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var models := NpcRig.list_parts(slot, suits[0])
		if not models.is_empty():
			suit.get_piece(slot).model_path = models[0]
	return suit

func _set_suit(suit: ArmorDefinition) -> void:
	_suit = suit
	_worn = _mannequin()
	_name_field.text = suit.display_name
	_rebind_slots()
	_update_target_label()
	_apply_to_preview()

## The villager the suit is shown on. Rebuilt per suit rather than kept, so a
## part model swapped on disk shows up after a rescan.
func _mannequin() -> NpcDefinition:
	var def := NpcDefinition.new()
	for slot: String in NpcDefinition.SLOTS:
		var models := NpcRig.list_parts(slot, MANNEQUIN_SET)
		if not models.is_empty():
			def.get_part(slot).model_path = models[0]
	return def

## The slot editors edit the SUIT's pieces directly; the mannequin gets copies
## when the preview is built. Editing what is on the mannequin instead would
## leave the suit unchanged and the save empty.
func _rebind_slots() -> void:
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		_slots[slot].bind(_suit.get_piece(slot))

func _queue_preview() -> void:
	_repaint.start()

func _apply_to_preview() -> void:
	if _suit == null or _preview == null:
		return
	_suit.wear(_worn)
	_preview.apply(_worn)

func _update_target_label() -> void:
	_target.text = "Saves to %s" % ArmorLibrary.path_for(_suit.display_name)

# ---------------------------------------------------------------------------
# actions
# ---------------------------------------------------------------------------

func _on_create_armor() -> void:
	_set_suit(_starter_suit())
	_show_editor()
	_status.text = ""

func _on_name_changed(text: String) -> void:
	_suit.display_name = text
	_update_target_label()

func _on_open_selected() -> void:
	if _suit_picker.disabled or _suit_picker.selected < 0:
		return
	_open(str(_suit_picker.get_item_metadata(_suit_picker.selected)))

func _on_open() -> void:
	# From the editor pane there is no picker on screen, so Open goes back to the
	# menu where the list of saved suits lives.
	_show_menu()

func _open(path: String) -> void:
	var loaded := ArmorLibrary.load_suit(path)
	if loaded == null:
		_status.text = "%s is not an armor suit" % path.get_file()
		return
	# A copy, so editing here does not rewrite the file under every NPC already
	# wearing it until Save is actually pressed.
	_set_suit(loaded.copy())
	_show_editor()
	_status.text = "Opened %s" % path.get_file()

func _on_save() -> void:
	if _suit == null:
		_status.text = "Nothing open — press Create armor."
		return
	var result := ArmorLibrary.save(_suit)
	_status.text = result["message"]
	if result["ok"]:
		EditorInterface.get_resource_filesystem().scan()

## Armor models are read off disk, so a Goxel export saved while this tab was
## open is invisible until the cache is dropped and the menus rebuilt.
func _on_rescan() -> void:
	NpcRig.clear_cache()
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		_slots[slot].refresh_parts()
	_refresh_suit_list()
	if _suit != null:
		_rebind_slots()
		_apply_to_preview()
	_status.text = "Rescanned parts"
