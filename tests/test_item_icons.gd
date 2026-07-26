extends Node
## Headless test for item pictures. Run:
##   godot --headless --path . res://tests/test_item_icons.tscn
## Prints ICONTEST RESULT=PASS/FAIL and exits with the matching code.
##
## An icon is a photograph of the item's own art file, so what a headless run
## can check is everything up to the shutter: that every item HAS art, that the
## art is the right art (a helmet is its suit's head piece, in that suit's
## colours), and that a model comes out of it with geometry in it. The picture
## itself needs a screen — see tests/preview_item_icons.tscn.

var _failures: PackedStringArray = []
var _checks := 0

func _ready() -> void:
	_check_every_item_has_art()
	_check_armor_points_at_its_own_suit()
	_check_a_model_is_built()
	_check_a_suit_paints_its_piece()
	_check_a_tint_reaches_the_blade()
	_check_headless_takes_no_pictures()

	print("ICONTEST ran %d assertions" % _checks)
	if _failures.is_empty():
		print("ICONTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("  - ", failure)
		print("ICONTEST RESULT=FAIL (%d problems)" % _failures.size())
		get_tree().quit(1)

func _expect(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition

## The regression guard the old hand-drawn icons never had: an item added
## without art used to be a silent nameplate in the bag, and it is now a
## failing test instead.
func _check_every_item_has_art() -> void:
	for id: String in ItemDb.ITEMS:
		var source := ItemDb.art_source(id)
		_expect(source != "", "'%s' has no art to photograph" % id)
		_expect(source == "" or ResourceLoader.exists(source),
				"'%s' names art that is not there — %s" % [id, source])

## A piece of armor is a piece of ITS suit: the copper helmet is what the head
## slot of copper_armor.tres holds, and not the chestplate and not the flimsy
## one. Mixing those up is invisible until you look at a bag.
func _check_armor_points_at_its_own_suit() -> void:
	for id: String in ItemDb.ITEMS:
		if not ItemDb.is_armor(id):
			continue
		var suit := ItemDb.suit_of(id)
		if not _expect(suit != null, "armor '%s' has no suit" % id):
			continue
		var piece := ItemDb.armor_piece(id)
		if not _expect(piece != null and not piece.model_path.is_empty(),
				"'%s' has no piece in %s" % [id, suit.display_name]):
			continue
		# The model of a head piece lives in the suit's Head folder, which is
		# what says the item and the plate agree about what it covers.
		var slot_folder := "/%s/" % ItemDb.armor_slot(id).capitalize()
		_expect(piece.model_path.contains(slot_folder),
				"'%s' covers %s but its model is %s" % [id, ItemDb.armor_slot(id),
						piece.model_path])
		_expect(piece == suit.get_piece(ItemDb.armor_slot(id)),
				"'%s' is not the %s piece of its own suit" % [id, ItemDb.armor_slot(id)])

## Every item builds into something with triangles in it. A model that loads
## and comes out empty photographs as a blank square.
func _check_a_model_is_built() -> void:
	for id: String in ItemDb.ITEMS:
		var model := ItemDb.build_model(id)
		if not _expect(model != null, "'%s' built no model" % id):
			continue
		var faces := 0
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				faces += mi.mesh.get_faces().size()
		if model is MeshInstance3D and (model as MeshInstance3D).mesh != null:
			faces += (model as MeshInstance3D).mesh.get_faces().size()
		_expect(faces > 0, "'%s' built a model with nothing in it" % id)
		model.free()

## The plate wears the colours the SUIT paints it, not the colours it was drawn
## in — otherwise all three tiers are one grey helmet three times.
func _check_a_suit_paints_its_piece() -> void:
	var flimsy := _first_colour("flimsy_helmet")
	var copper := _first_colour("copper_helmet")
	var iron := _first_colour("iron_helmet")
	_expect(flimsy != Color.TRANSPARENT, "the flimsy helmet has no vertex colours")
	_expect(flimsy != copper, "the flimsy and copper helmets photograph the same colour")
	_expect(copper != iron, "the copper and iron helmets photograph the same colour")
	var piece := ItemDb.armor_piece("copper_helmet")
	_expect(piece != null and piece.colors.size() > 0
			and copper.is_equal_approx(piece.colors[0]),
			"the copper helmet is not painted its suit's first colour")

## Three swords share one model and are told apart by a tint, so the tint has
## to survive into what is photographed.
func _check_a_tint_reaches_the_blade() -> void:
	var wooden := _first_albedo("wooden_sword")
	var copper := _first_albedo("copper_sword")
	_expect(wooden != Color.TRANSPARENT,
			"the wooden sword's tint never reached a material")
	_expect(wooden != copper, "the wooden and copper swords photograph the same colour")
	# An untinted item is left strictly alone rather than multiplied by white,
	# so the iron sword keeps whatever its own art says.
	_expect(_first_albedo("iron_sword") == Color.TRANSPARENT,
			"the iron sword was repainted despite carrying no tint")
	var tint: Color = ItemDb.hold_config("wooden_sword")["tint"]
	_expect(wooden.r <= tint.r + 0.001 and wooden.g <= tint.g + 0.001
			and wooden.b <= tint.b + 0.001,
			"the wooden sword came out lighter than the tint it was painted with")

## Nothing is rendered where there is no display: a dedicated server and every
## test in this folder run headless, and a viewport that cannot draw would
## either warn on every item or hand back a black square.
func _check_headless_takes_no_pictures() -> void:
	if not _expect(DisplayServer.get_name() == "headless",
			"this test is meant to be run with --headless"):
		return
	_expect(ItemIcons.icon("iron_sword") == null,
			"a headless run tried to photograph the iron sword")
	_expect(ItemDb.icon("iron_sword") == null,
			"ItemDb.icon disagrees with ItemIcons about a headless run")

func _first_colour(id: String) -> Color:
	var mi := ItemDb.build_model(id) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return Color.TRANSPARENT
	var cols: PackedColorArray = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var out := cols[0] if cols.size() > 0 else Color.TRANSPARENT
	mi.free()
	return out

func _first_albedo(id: String) -> Color:
	var model := ItemDb.build_model(id)
	if model == null:
		return Color.TRANSPARENT
	var out := Color.TRANSPARENT
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(i) as BaseMaterial3D
			if mat != null:
				out = mat.albedo_color
				break
		if out != Color.TRANSPARENT:
			break
	model.free()
	return out
