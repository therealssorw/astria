@tool
extends VBoxContainer
## The NPC Builder main screen: turntable on the left, everything that defines
## an NPC on the right, and a Save that drops a ready-to-place scene into
## scenes/entities/npc/built/.

const Preview := preload("res://addons/npc_builder/ui/npc_preview.gd")
const SlotEditor := preload("res://addons/npc_builder/ui/part_slot_editor.gd")
const Writer := preload("res://addons/npc_builder/io/npc_writer.gd")

## Edits arrive faster than a rig can be rebuilt (dragging inside a colour
## wheel fires continuously), so they are coalesced onto this delay.
const PREVIEW_DELAY := 0.08

var _definition: NpcDefinition

var _preview: SubViewportContainer
var _name_field: LineEdit
var _dialog_field: LineEdit
var _height: SpinBox
var _range: SpinBox
var _set_picker: OptionButton
var _suit_picker: OptionButton
var _armor_switch: CheckButton
var _armor_box: VBoxContainer
var _status: Label
var _target: Label
var _slots := {}
var _repaint: Timer
var _file_dialog: FileDialog

func _ready() -> void:
	# The editor's main screen is a VBoxContainer, so it lays its children out
	# by their size flags and ignores anchors entirely. Without EXPAND the tab
	# opens collapsed to nothing.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_repaint = Timer.new()
	_repaint.one_shot = true
	_repaint.wait_time = PREVIEW_DELAY
	_repaint.timeout.connect(_apply_to_preview)
	add_child(_repaint)

	add_child(_build_toolbar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(_build_preview_pane())
	split.add_child(_build_side_pane())

	_set_definition(_starter_definition())

## A suit is MADE in the Items tab and WORN here, which means the two halves of
## that workflow are two screens in ONE editor session -- and this one is built
## once, when the plugin loads. So the list of saved suits was a snapshot of the
## folder as it stood at editor startup: every suit made after that was invisible
## here, and the only way to see your own armor was to know that a button called
## "Rescan parts" also rescans suits. Rebuilding the list on the way into the tab
## is what closes that: save in Items, switch to NPC Builder, wear it.
##
## Cheap enough to do unconditionally -- it is a directory listing and a load of
## each suit's header, both of which the editor has cached.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and _suit_picker != null:
		_refresh_suits()

# ---------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------

func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	for entry in [["New", _on_new], ["Load…", _on_load], ["Save", _on_save]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		bar.add_child(button)
	bar.add_child(VSeparator.new())
	var shuffle := Button.new()
	shuffle.text = "Randomise"
	shuffle.tooltip_text = "Random parts and colours from the selected set"
	shuffle.pressed.connect(_on_randomise)
	bar.add_child(shuffle)
	var rescan := Button.new()
	rescan.text = "Rescan parts"
	rescan.tooltip_text = "Pick up part models added to the Parts folder since this tab opened"
	rescan.pressed.connect(_on_rescan)
	bar.add_child(rescan)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status)
	return bar

func _build_preview_pane() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview = Preview.new()
	column.add_child(_preview)

	var controls := HBoxContainer.new()
	for clip in Preview.CLIPS:
		var button := Button.new()
		button.text = clip.capitalize()
		button.pressed.connect(func() -> void: _preview.play_clip(clip))
		controls.add_child(button)
	controls.add_child(VSeparator.new())
	var spin := CheckButton.new()
	spin.text = "Turntable"
	spin.button_pressed = true
	spin.toggled.connect(func(on: bool) -> void: _preview.set_turntable(on))
	controls.add_child(spin)
	var reframe := Button.new()
	reframe.text = "Reframe"
	reframe.pressed.connect(func() -> void: _preview.frame_character())
	controls.add_child(reframe)
	column.add_child(controls)

	var hint := Label.new()
	hint.text = "Drag to orbit · wheel to zoom"
	hint.modulate = Color(1, 1, 1, 0.55)
	column.add_child(hint)
	return column

func _build_side_pane() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	column.add_child(_heading("Identity"))
	var form := GridContainer.new()
	form.columns = 2
	column.add_child(form)

	_name_field = LineEdit.new()
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.text_changed.connect(_on_name_changed)
	_add_field(form, "Name", _name_field)

	_dialog_field = LineEdit.new()
	_dialog_field.placeholder_text = "key in DialogData.DIALOGS"
	_dialog_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_field.text_changed.connect(func(text: String) -> void: _definition.dialog_id = text)
	_add_field(form, "Dialog id", _dialog_field)

	_height = SpinBox.new()
	_height.min_value = 0.6
	_height.max_value = 3.0
	_height.step = 0.01
	_height.suffix = "m"
	_height.value_changed.connect(func(value: float) -> void:
		_definition.height = value
		_queue_preview())
	_add_field(form, "Height", _height)

	_range = SpinBox.new()
	_range.min_value = 0.5
	_range.max_value = 12.0
	_range.step = 0.1
	_range.suffix = "m"
	_range.value_changed.connect(func(value: float) -> void: _definition.interact_range = value)
	_add_field(form, "Talk range", _range)

	column.add_child(_heading("Character set"))
	var set_row := HBoxContainer.new()
	_set_picker = OptionButton.new()
	_set_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_row.add_child(_set_picker)
	var apply_set := Button.new()
	apply_set.text = "Use whole set"
	apply_set.tooltip_text = "Fill every slot from this set"
	apply_set.pressed.connect(_on_apply_set)
	set_row.add_child(apply_set)
	column.add_child(set_row)
	_refresh_sets()

	column.add_child(_heading("Parts"))
	for slot: String in NpcDefinition.SLOTS:
		var editor := SlotEditor.new()
		column.add_child(editor)
		editor.setup(slot)
		editor.changed.connect(_queue_preview)
		_slots[slot] = editor

	column.add_child(_heading("Armor"))
	_armor_switch = CheckButton.new()
	_armor_switch.text = "Wears armor"
	_armor_switch.tooltip_text = "A suit worn OVER the parts above — the character keeps its own head, hands and height"
	_armor_switch.toggled.connect(_on_armor_toggled)
	column.add_child(_armor_switch)

	# Everything armor lives under the switch, so an unarmoured villager is not
	# scrolling past four slots it will never fill.
	_armor_box = VBoxContainer.new()
	_armor_box.add_theme_constant_override("separation", 8)
	_armor_box.visible = false
	column.add_child(_armor_box)

	var suit_row := HBoxContainer.new()
	_suit_picker = OptionButton.new()
	_suit_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	suit_row.add_child(_suit_picker)
	var apply_suit := Button.new()
	apply_suit.text = "Wear whole suit"
	apply_suit.tooltip_text = "Fill every armor slot from this suit"
	apply_suit.pressed.connect(_on_apply_suit)
	suit_row.add_child(apply_suit)
	_armor_box.add_child(suit_row)

	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var editor := SlotEditor.new()
		_armor_box.add_child(editor)
		editor.setup(slot)
		editor.changed.connect(_queue_preview)
		_slots[slot] = editor
	_refresh_suits()

	_target = Label.new()
	_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target.modulate = Color(1, 1, 1, 0.6)
	column.add_child(_target)
	return scroll

func _heading(text: String) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_size_override("font_size", 17)
	return out

func _add_field(form: GridContainer, label: String, control: Control) -> void:
	var text := Label.new()
	text.text = label
	form.add_child(text)
	form.add_child(control)

# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

## A new NPC starts as a complete character rather than an invisible pile of
## empty slots, so the first thing the tab shows is something to react to.
func _starter_definition() -> NpcDefinition:
	var def := NpcDefinition.new()
	var categories := NpcRig.list_categories()
	if not categories.is_empty():
		_fill_from_set(def, categories[0])
	return def

func _fill_from_set(def: NpcDefinition, category: String, shuffle := false) -> void:
	for slot: String in NpcDefinition.SLOTS:
		var models := NpcRig.list_parts(slot, category)
		var part := def.get_part(slot)
		if models.is_empty():
			part.model_path = ""
		else:
			part.model_path = models[randi() % models.size()] if shuffle else models[0]
		part.colors = PackedColorArray()
		part.tint = Color.WHITE

func _set_definition(def: NpcDefinition) -> void:
	_definition = def
	_name_field.text = def.display_name
	_dialog_field.text = def.dialog_id
	_height.set_value_no_signal(def.height)
	_range.set_value_no_signal(def.interact_range)
	_rebind_slots()
	# A loaded NPC arrives already wearing (or not wearing) a suit, so the switch
	# follows the definition rather than the other way round.
	_armor_switch.set_pressed_no_signal(def.wears_armor())
	_armor_box.visible = def.wears_armor()
	_update_target_label()
	_apply_to_preview()

func _rebind_slots() -> void:
	for slot: String in NpcDefinition.ALL_SLOTS:
		_slots[slot].bind(_definition.get_part(slot))

func _refresh_sets() -> void:
	_set_picker.clear()
	for category in NpcRig.list_categories():
		_set_picker.add_item(category)
	if _set_picker.item_count > 0:
		_set_picker.select(0)

## Two kinds of thing can be worn, and the menu says which is which. A SAVED
## suit (made in the Items tab) arrives named and already coloured; a raw model
## SET is the art as drawn, for dressing a character without making a suit
## first. Metadata carries the path or the set name, so applying one does not
## have to guess from the label.
##
## Whatever was picked stays picked across a rebuild. The list is rebuilt every
## time this tab is opened (see `_notification`), and a menu that snapped back
## to its first entry on the way in would quietly swap the suit under the NPC
## you came back to dress.
func _refresh_suits() -> void:
	var previous := _selected_suit()
	_suit_picker.clear()
	var saved := ArmorLibrary.paths()
	if not saved.is_empty():
		_suit_picker.add_separator("Saved suits")
		for path in saved:
			_suit_picker.add_item(ArmorLibrary.title_of(path))
			_suit_picker.set_item_metadata(_suit_picker.item_count - 1, path)
	var sets := NpcRig.list_categories(true)
	if not sets.is_empty():
		_suit_picker.add_separator("Armor sets")
		for suit in sets:
			_suit_picker.add_item(suit)
			_suit_picker.set_item_metadata(_suit_picker.item_count - 1, suit)
	if _suit_picker.item_count == 0:
		_suit_picker.add_item("(nothing made yet — the Items tab makes suits)")
		_suit_picker.disabled = true
		return
	_suit_picker.disabled = false
	for i in _suit_picker.item_count:
		if _suit_picker.is_item_separator(i):
			continue
		if str(_suit_picker.get_item_metadata(i)) == previous:
			_suit_picker.select(i)
			return
	for i in _suit_picker.item_count:
		if not _suit_picker.is_item_separator(i):
			_suit_picker.select(i)
			return

func _selected_set() -> String:
	if _set_picker.selected < 0:
		return ""
	return _set_picker.get_item_text(_set_picker.selected)

## Either a res:// path to a saved suit or the name of a raw armor set.
func _selected_suit() -> String:
	if _suit_picker.disabled or _suit_picker.selected < 0:
		return ""
	return str(_suit_picker.get_item_metadata(_suit_picker.selected))

func _queue_preview() -> void:
	_repaint.start()

func _apply_to_preview() -> void:
	if _definition != null and _preview != null:
		_preview.apply(_definition)

func _update_target_label() -> void:
	_target.text = "Saves to %s and %s" % [
		Writer.definition_path(_definition.display_name),
		Writer.scene_path(_definition.display_name)]

# ---------------------------------------------------------------------------
# actions
# ---------------------------------------------------------------------------

func _on_name_changed(text: String) -> void:
	_definition.display_name = text
	_update_target_label()

func _on_new() -> void:
	_set_definition(_starter_definition())
	_status.text = ""

func _on_apply_set() -> void:
	var category := _selected_set()
	if category.is_empty():
		return
	_fill_from_set(_definition, category)
	_rebind_slots()
	_apply_to_preview()

## Turning armor ON puts the first suit on straight away rather than showing
## four empty slots: the switch is meant to answer "what does he look like in
## armor", and nothing happening reads as a broken checkbox.
func _on_armor_toggled(on: bool) -> void:
	_armor_box.visible = on
	if on:
		if not _definition.wears_armor():
			_fill_armor(_definition, _selected_suit())
	else:
		_definition.clear_armor()
	_rebind_slots()
	_apply_to_preview()

func _on_apply_suit() -> void:
	var suit := _selected_suit()
	if suit.is_empty():
		return
	_fill_armor(_definition, suit)
	_rebind_slots()
	_apply_to_preview()

## Puts on whatever the picker is showing. A SAVED suit comes with the colours
## it was authored in (that is the point of having saved it); a raw armor SET is
## the art as drawn, so its overrides start empty. An empty name strips the
## layer, which is what the switch going off means.
func _fill_armor(def: NpcDefinition, suit: String) -> void:
	if suit.begins_with("res://"):
		var saved := ArmorLibrary.load_suit(suit)
		if saved != null:
			saved.wear(def)
			return
		_status.text = "%s could not be loaded" % suit.get_file()
		return
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var part := def.get_part(slot)
		var models := NpcRig.list_parts(slot, suit) if not suit.is_empty() else PackedStringArray()
		part.model_path = models[0] if not models.is_empty() else ""
		part.colors = PackedColorArray()
		part.tint = Color.WHITE

func _on_randomise() -> void:
	var category := _selected_set()
	_fill_from_set(_definition, category, true)
	# Armor is left ON or OFF as it was — the dice pick a character, not whether
	# he is a soldier — but a suit he IS wearing gets recoloured with the rest.
	for slot: String in NpcDefinition.ALL_SLOTS:
		var part := _definition.get_part(slot)
		if part.model_path.is_empty():
			continue
		var palette := NpcRig.palette_of(part.model_path)
		if palette.size() > SlotEditor.SWATCH_LIMIT:
			# Hand-shaded art already has its own colour scheme; rolling every
			# noise shade separately would just turn it to confetti.
			part.tint = Color.from_hsv(randf(), randf_range(0.0, 0.3), randf_range(0.75, 1.0))
			continue
		var colors := PackedColorArray()
		for _i in palette.size():
			colors.append(Color.from_hsv(randf(), randf_range(0.15, 0.6), randf_range(0.45, 0.9)))
		part.colors = colors
	_rebind_slots()
	_apply_to_preview()

## Part models are read off disk, so a Goxel export saved while this tab was
## open is invisible until the cache is dropped and the menus rebuilt.
func _on_rescan() -> void:
	NpcRig.clear_cache()
	_refresh_sets()
	_refresh_suits()
	for slot: String in NpcDefinition.ALL_SLOTS:
		_slots[slot].refresh_parts()
	_rebind_slots()
	_apply_to_preview()
	_status.text = "Rescanned parts"

func _on_load() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_RESOURCES
		_file_dialog.add_filter("*.tres", "NPC definition")
		_file_dialog.current_dir = Writer.DEFINITION_DIR
		_file_dialog.file_selected.connect(_on_file_chosen)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)

func _on_file_chosen(path: String) -> void:
	var loaded := load(path) as NpcDefinition
	if loaded == null:
		_status.text = "%s is not an NPC definition" % path.get_file()
		return
	# A copy, so editing here does not quietly rewrite the cached resource that
	# every placed NPC in the open scene is pointing at.
	_set_definition(loaded.copy())
	_status.text = "Loaded %s" % path.get_file()

func _on_save() -> void:
	var result := Writer.save(_definition)
	_status.text = result["message"]
	if result["ok"]:
		EditorInterface.get_resource_filesystem().scan()
