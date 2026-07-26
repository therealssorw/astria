@tool
extends VBoxContainer
## One slot's row of controls in the NPC Builder: which model fills it, a swatch
## per palette colour in that model, and the offset/scale escape hatch for art
## that was not drawn quite where the rest of the set expects it.

signal changed

## Past this many palette entries a model is hand-shaded rather than flat-
## coloured (the zombie parts run to dozens of noise shades), and a wall of
## colour pickers helps nobody -- those get the tint alone.
const SWATCH_LIMIT := 8

var slot := ""
var part: NpcPart

var _picker: OptionButton
var _tint: ColorPickerButton
var _note: Label
var _swatches: HBoxContainer
var _tweaks: GridContainer
var _offset: Array[SpinBox] = []
var _scale: SpinBox

func setup(for_slot: String) -> void:
	slot = for_slot
	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = for_slot.capitalize()
	if NpcDefinition.is_armor(for_slot):
		title.tooltip_text = "Worn over the %s" % NpcDefinition.covers(for_slot)
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(_on_part_selected)
	add_child(_picker)

	var tint_row := HBoxContainer.new()
	tint_row.add_child(_label("Tint"))
	_tint = ColorPickerButton.new()
	_tint.custom_minimum_size = Vector2(58, 24)
	_tint.color = Color.WHITE
	_tint.tooltip_text = "Multiplied over every colour in this part"
	_tint.color_changed.connect(_on_tint_changed)
	tint_row.add_child(_tint)
	_note = Label.new()
	_note.modulate = Color(1, 1, 1, 0.55)
	tint_row.add_child(_note)
	add_child(tint_row)

	_swatches = HBoxContainer.new()
	add_child(_swatches)

	var fold := CheckButton.new()
	fold.text = "Adjust placement"
	fold.toggled.connect(func(on: bool) -> void: _tweaks.visible = on)
	add_child(fold)

	_tweaks = GridContainer.new()
	_tweaks.columns = 4
	_tweaks.visible = false
	add_child(_tweaks)
	for axis in ["Left", "Up", "Fwd"]:
		_tweaks.add_child(_label(axis))
		var box := _spin(-24.0, 24.0, 0.5)
		box.value_changed.connect(_on_offset_changed)
		_offset.append(box)
		_tweaks.add_child(box)
	_tweaks.add_child(_label("Scale"))
	_scale = _spin(0.2, 4.0, 0.05)
	_scale.value = 1.0
	_scale.value_changed.connect(_on_scale_changed)
	_tweaks.add_child(_scale)

	add_child(HSeparator.new())
	refresh_parts()

func _label(text: String) -> Label:
	var out := Label.new()
	out.text = text
	return out

func _spin(low: float, high: float, step: float) -> SpinBox:
	var out := SpinBox.new()
	out.min_value = low
	out.max_value = high
	out.step = step
	out.custom_minimum_size = Vector2(76, 0)
	return out

## Rescans the parts folder. Items are grouped under a separator per category,
## so "Undead" reads as its own section of the menu while still letting you
## put a skeleton head on an ordinary body.
func refresh_parts() -> void:
	var previous := part.model_path if part != null else ""
	_picker.clear()
	_picker.add_item("(none)")
	_picker.set_item_metadata(0, "")
	# An armor slot lists SUITS, a skin slot lists character sets — the two
	# libraries never mix, so a helmet can't be picked as a head.
	for category in NpcRig.categories_for(slot):
		var models := NpcRig.list_parts(slot, category)
		if models.is_empty():
			continue
		_picker.add_separator(category)
		for path in models:
			_picker.add_item(NpcRig.part_title(path))
			_picker.set_item_metadata(_picker.item_count - 1, path)
	_select_path(previous)

func bind(to_part: NpcPart) -> void:
	part = to_part
	_select_path(part.model_path if part != null else "")
	if part != null:
		for i in 3:
			_offset[i].set_value_no_signal(part.offset[i])
		_scale.set_value_no_signal(part.scale)
		_tint.color = part.tint
	_refresh_swatches()

func _select_path(path: String) -> void:
	for i in _picker.item_count:
		if _picker.get_item_metadata(i) == path:
			_picker.select(i)
			return
	_picker.select(0)

func _on_part_selected(index: int) -> void:
	if part == null:
		return
	var path: String = str(_picker.get_item_metadata(index))
	if path == part.model_path:
		return
	part.model_path = path
	# A different model means a different palette, so the old overrides are
	# meaningless -- start from the new model's own colours. The tint is a
	# property of the character, not the model, so it survives.
	part.colors = PackedColorArray()
	_refresh_swatches()
	changed.emit()

func _on_offset_changed(_value: float) -> void:
	if part == null:
		return
	part.offset = Vector3(_offset[0].value, _offset[1].value, _offset[2].value)
	changed.emit()

func _on_scale_changed(value: float) -> void:
	if part == null:
		return
	part.scale = value
	changed.emit()

func _refresh_swatches() -> void:
	for child in _swatches.get_children():
		_swatches.remove_child(child)
		child.free()
	if part == null or part.model_path.is_empty():
		_note.text = ""
		return
	var palette := NpcRig.palette_of(part.model_path)
	_fit_colors(palette)
	if palette.size() > SWATCH_LIMIT:
		_note.text = "%d shades — tint only" % palette.size()
		return
	_note.text = ""
	for i in palette.size():
		var button := ColorPickerButton.new()
		button.custom_minimum_size = Vector2(38, 24)
		button.color = part.colors[i]
		button.tooltip_text = "Colour %d — model default %s" % [i + 1, palette[i].to_html(false)]
		button.color_changed.connect(_on_colour_changed.bind(i))
		_swatches.add_child(button)
	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Back to the colours the model was drawn with"
	reset.pressed.connect(_on_reset_colours)
	_swatches.add_child(reset)

## Keeps the override array the same length as the model's palette, filling any
## new entries from the model itself.
func _fit_colors(palette: PackedColorArray) -> void:
	if part.colors.size() == palette.size():
		return
	var fitted := PackedColorArray()
	for i in palette.size():
		fitted.append(part.colors[i] if i < part.colors.size() else palette[i])
	part.colors = fitted

func _on_colour_changed(colour: Color, index: int) -> void:
	if part == null or index >= part.colors.size():
		return
	part.colors[index] = colour
	changed.emit()

func _on_tint_changed(colour: Color) -> void:
	if part == null:
		return
	part.tint = colour
	changed.emit()

func _on_reset_colours() -> void:
	if part == null:
		return
	part.colors = NpcRig.palette_of(part.model_path)
	part.tint = Color.WHITE
	_tint.color = Color.WHITE
	_refresh_swatches()
	changed.emit()
