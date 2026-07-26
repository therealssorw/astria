extends Node
## Headless test for armor SUITS — the things the Items tab makes. Run:
##   godot --headless --path . res://tests/test_armor_suits.tscn
## Prints ARMORTEST RESULT=PASS/FAIL and exits with the matching code.
##
## A suit is armor lifted out of a character: pieces chosen, coloured, named and
## saved, so twenty guards share one file. The three things that has to mean —
## it survives the trip to disk with its colours, wearing it copies rather than
## links, and the Items tab can actually build one — are what this checks.

const Screen := preload("res://addons/item_builder/ui/item_builder_screen.gd")
const NpcScreen := preload("res://addons/npc_builder/ui/npc_builder_screen.gd")
const TEST_SUIT_NAME := "Zz Suit Test"
## A second suit, saved while an NPC Builder tab is already open — see
## `_check_a_suit_made_next_door_turns_up`.
const LATE_SUIT_NAME := "Zz Suit Test Late"

var _failures: PackedStringArray = []
var _checks := 0

func _ready() -> void:
	_check_scripts_run_in_the_editor()
	_check_build_and_save()
	_check_wearing_copies()
	_check_library_is_picky()
	_check_items_tab_builds()
	_check_npc_builder_wears_a_saved_suit()
	_check_a_suit_made_next_door_turns_up()
	_cleanup()

	print("ARMORTEST ran %d assertions" % _checks)
	if _failures.is_empty():
		print("ARMORTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("  - ", failure)
		print("ARMORTEST RESULT=FAIL (%d problems)" % _failures.size())
		get_tree().quit(1)

func _expect(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition

func _suit_path() -> String:
	return ArmorLibrary.path_for(TEST_SUIT_NAME)

func _cleanup() -> void:
	for name in [TEST_SUIT_NAME, LATE_SUIT_NAME]:
		var path := ArmorLibrary.path_for(name)
		if ResourceLoader.exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## A suit made of the first armor set, every piece painted one colour.
func _painted_suit(colour: Color) -> ArmorDefinition:
	var suit := ArmorDefinition.new()
	suit.display_name = TEST_SUIT_NAME
	var sets := NpcRig.list_categories(true)
	if sets.is_empty():
		return suit
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var models := NpcRig.list_parts(slot, sets[0])
		if models.is_empty():
			continue
		var piece := suit.get_piece(slot)
		piece.model_path = models[0]
		var colours := PackedColorArray()
		for _i in NpcRig.palette_of(models[0]).size():
			colours.append(colour)
		piece.colors = colours
	return suit

## Same load-bearing reason as NpcDefinition: a Resource whose methods are
## called from tool code must be a @tool script, or the editor hands back a
## placeholder and `wear()` dies on a suit loaded off disk.
func _check_scripts_run_in_the_editor() -> void:
	_expect((ArmorDefinition.new().get_script() as Script).is_tool(),
			"ArmorDefinition is not a @tool script — a loaded suit would be a placeholder")

func _check_build_and_save() -> void:
	var empty := ArmorDefinition.new()
	_expect(not empty.has_pieces(), "a suit with no models says it has pieces")
	var refused: Dictionary = ArmorLibrary.save(empty)
	_expect(not bool(refused["ok"]), "an empty suit was saved anyway")

	var suit := _painted_suit(Color(0.2, 0.45, 0.9))
	_expect(suit.has_pieces(), "a dressed suit says it is empty")
	var result: Dictionary = ArmorLibrary.save(suit)
	if not _expect(bool(result["ok"]), "saving a suit failed: %s" % result["message"]):
		return
	_expect(ArmorLibrary.paths().has(_suit_path()),
			"the saved suit is not in the library listing")
	_expect(ArmorLibrary.title_of(_suit_path()) == TEST_SUIT_NAME,
			"the suit is listed as '%s'" % ArmorLibrary.title_of(_suit_path()))

	var loaded := ArmorLibrary.load_suit(_suit_path())
	if not _expect(loaded != null, "the saved suit did not load back"):
		return
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var before := suit.get_piece(slot)
		var after := loaded.get_piece(slot)
		_expect(after.model_path == before.model_path,
				"%s came back as %s" % [slot, after.model_path])
		# the colours ARE the suit — a suit that reloads in the art's own colours
		# is just the model set again
		_expect(after.colors == before.colors,
				"%s lost its colours on the way to disk" % slot)

## Wearing a suit hands the character COPIES. If it handed references,
## recolouring one guard in the NPC Builder would rewrite the suit file and
## every other guard wearing it.
func _check_wearing_copies() -> void:
	var suit := _painted_suit(Color(0.2, 0.45, 0.9))
	var def := NpcDefinition.new()
	for slot: String in NpcDefinition.SLOTS:
		var models := NpcRig.list_parts(slot, "Base")
		if not models.is_empty():
			def.get_part(slot).model_path = models[0]
	suit.wear(def)
	_expect(def.wears_armor(), "wearing a suit left the NPC unarmoured")

	var worn := def.get_part("body_armor")
	_expect(worn != suit.get_piece("body_armor"),
			"the NPC is holding the suit's own piece, not a copy")
	worn.tint = Color(1.0, 0.0, 0.0)
	_expect(suit.get_piece("body_armor").tint == Color.WHITE,
			"recolouring the NPC also recoloured the suit")

	# and it really rigs: a suit is only worth saving if it comes out as armor
	var visual := NpcVisual.new()
	visual.definition = def
	add_child(visual)
	var meshes := visual.skeleton.find_children("*", "MeshInstance3D", false, false)
	_expect(meshes.size() == NpcDefinition.ALL_SLOTS.size(),
			"an NPC in a saved suit rigged %d parts, expected %d"
					% [meshes.size(), NpcDefinition.ALL_SLOTS.size()])
	var plate := visual.skeleton.get_node_or_null(NpcRig.mesh_name("head_armor")) as MeshInstance3D
	if _expect(plate != null, "the suit's helmet did not rig"):
		var painted := true
		for c: Color in (plate.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
			if absf(c.r - 0.2) > 0.01 or absf(c.g - 0.45) > 0.01 or absf(c.b - 0.9) > 0.01:
				painted = false
		_expect(painted, "the suit's colours did not reach the rigged helmet")

	# reading a suit back off a character is the other direction of the same trip
	var taken := ArmorDefinition.new()
	taken.take_from(def)
	_expect(taken.get_piece("body_armor").tint == Color(1.0, 0.0, 0.0),
			"taking a suit off a character did not pick up what it was wearing")
	remove_child(visual)
	visual.free()

## The suits folder sits next to the NPC definitions and things get dragged
## around, so "a .tres in that folder" is never enough.
func _check_library_is_picky() -> void:
	_expect(ArmorLibrary.load_suit("res://Assets/Data/Armor/nothing_here.tres") == null,
			"a missing suit loaded as something")
	var npc_files := DirAccess.get_files_at("res://Assets/Data/Npcs/")
	for f in npc_files:
		var file := String(f).trim_suffix(".import").trim_suffix(".remap")
		if file.get_extension().to_lower() != "tres":
			continue
		_expect(ArmorLibrary.load_suit("res://Assets/Data/Npcs/" + file) == null,
				"the NPC definition %s loaded as an armor suit" % file)
		break

## The Items tab itself: it has to build, and its Create armor button has to
## produce a suit with something on it. An editor tab is otherwise only testable
## by opening the editor and looking.
func _check_items_tab_builds() -> void:
	var screen: Control = Screen.new()
	add_child(screen)
	_expect(screen.get_child_count() > 0, "the Items tab built nothing")
	screen._on_create_armor()
	var made: ArmorDefinition = screen._suit
	if _expect(made != null, "Create armor produced no suit"):
		_expect(made.has_pieces(),
				"Create armor produced an empty suit — the tab opens on nothing to react to")
	# the preview stands it on somebody: a suit alone has no height to rig by
	_expect(screen._worn != null and not screen._worn.get_part("body").model_path.is_empty(),
			"the Items tab has no mannequin to show the suit on")
	remove_child(screen)
	screen.free()

## The other half of the split: a suit is MADE in the Items tab and WORN in the
## NPC Builder, so the saved file has to turn up in that picker and arrive with
## the colours it was authored in. A raw armor set in the same menu must still
## come through as the art was drawn.
func _check_npc_builder_wears_a_saved_suit() -> void:
	var screen: Control = NpcScreen.new()
	add_child(screen)
	var picker: OptionButton = screen._suit_picker
	var saved_at := -1
	var raw_at := -1
	for i in picker.item_count:
		if picker.is_item_separator(i):
			continue
		if str(picker.get_item_metadata(i)) == _suit_path():
			saved_at = i
		elif not str(picker.get_item_metadata(i)).begins_with("res://"):
			raw_at = i
	if _expect(saved_at >= 0, "the saved suit is not offered in the NPC Builder"):
		picker.select(saved_at)
		screen._on_apply_suit()
		var def: NpcDefinition = screen._definition
		_expect(def.wears_armor(), "applying a saved suit left the NPC unarmoured")
		var worn: PackedColorArray = def.get_part("body_armor").colors
		_expect(worn.size() > 0 and worn[0].is_equal_approx(Color(0.2, 0.45, 0.9)),
				"a saved suit arrived in %s, not the colour it was authored in"
						% ("nothing" if worn.is_empty() else worn[0].to_html(false)))
	if _expect(raw_at >= 0, "the raw armor sets are not offered in the NPC Builder"):
		picker.select(raw_at)
		screen._on_apply_suit()
		var def: NpcDefinition = screen._definition
		_expect(def.wears_armor(), "applying an armor set left the NPC unarmoured")
		# The art AS DRAWN. (Not "no overrides": binding a slot editor fills the
		# override array from the model's own palette so it has swatches to show,
		# which is why this asks what colour arrived rather than whether the array
		# is empty.)
		var plate: NpcPart = def.get_part("body_armor")
		var drawn := NpcRig.palette_of(plate.model_path)
		_expect(plate.colors.is_empty() or (drawn.size() > 0 and plate.colors[0].is_equal_approx(drawn[0])),
				"a raw armor set arrived pre-coloured — it should be the art as drawn")
	screen._on_armor_toggled(false)
	_expect(not (screen._definition as NpcDefinition).wears_armor(),
			"the armor switch did not take the suit off")
	remove_child(screen)
	screen.free()

## The half of "made next door, worn here" that a test building the screen AFTER
## the save can never see: an NPC Builder tab is built ONCE, when the plugin
## loads, so its list of suits used to be a snapshot of the folder as it stood at
## editor startup. Everything the user made afterwards was simply absent, and the
## only way in was knowing that "Rescan parts" rescans suits too.
##
## So: open the tab FIRST, save a suit, then show the tab — the way switching
## from Items back to NPC Builder does — and it has to be wearable. The picked
## suit has to survive that rebuild as well, or coming back to the tab would swap
## the suit under the character you left half-dressed.
func _check_a_suit_made_next_door_turns_up() -> void:
	var screen: Control = NpcScreen.new()
	add_child(screen)
	screen.visible = false
	var picker: OptionButton = screen._suit_picker
	var late_path := ArmorLibrary.path_for(LATE_SUIT_NAME)
	_expect(_offered_at(picker, late_path) < 0,
			"a suit that does not exist yet is already in the menu")

	# what pressing Save in the Items tab does
	var late := _painted_suit(Color(0.9, 0.3, 0.1))
	late.display_name = LATE_SUIT_NAME
	var saved: Dictionary = ArmorLibrary.save(late)
	if not _expect(bool(saved["ok"]), "saving the late suit failed: %s" % saved["message"]):
		remove_child(screen)
		screen.free()
		return

	# ...and what switching back to the NPC Builder tab does
	var kept := _offered_at(picker, _suit_path())
	if kept >= 0:
		picker.select(kept)
	screen.visible = true
	var at := _offered_at(picker, late_path)
	if _expect(at >= 0, "a suit saved while the tab was open never turns up in it"):
		if kept >= 0:
			_expect(str(picker.get_item_metadata(picker.selected)) == _suit_path(),
					"reopening the tab changed which suit was picked")
		picker.select(at)
		screen._on_apply_suit()
		var worn: PackedColorArray = (screen._definition as NpcDefinition).get_part("body_armor").colors
		_expect(worn.size() > 0 and worn[0].is_equal_approx(Color(0.9, 0.3, 0.1)),
				"the late suit went on in the wrong colours")
	remove_child(screen)
	screen.free()

## Where a suit sits in the picker, by the path/set name in its metadata, or -1.
func _offered_at(picker: OptionButton, path: String) -> int:
	for i in picker.item_count:
		if not picker.is_item_separator(i) and str(picker.get_item_metadata(i)) == path:
			return i
	return -1
