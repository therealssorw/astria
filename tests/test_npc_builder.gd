extends Node
## Headless integration test for the NPC builder. Run:
##   godot --headless --path . res://tests/test_npc_builder.tscn
##
## Covers the whole pipeline: every part model in the library rigs onto the
## humanoid skeleton, the skeleton really is reproportioned to the voxel art,
## the Mixamo clips still drive it afterwards, colours reach the mesh, and a
## saved NPC reloads as a working scene. Also re-checks that Rouge (which now
## shares the same base class) still builds its own rig and full clip set.
## Prints NPCTEST RESULT=PASS/FAIL and exits with the matching code.

const Writer := preload("res://addons/npc_builder/io/npc_writer.gd")
const SlotEditor := preload("res://addons/npc_builder/ui/part_slot_editor.gd")
const TEST_NPC_NAME := "Zz Builder Test Npc"

var _failures: PackedStringArray = []
var _rigged := 0
var _checks := 0

func _ready() -> void:
	_check_library()
	for category in NpcRig.list_categories():
		_check_set(category)
	for category in NpcRig.list_categories():
		_check_no_coincident_surfaces(category)
	_check_armor_library()
	_check_armor_is_a_layer()
	_check_armor_fits_what_it_covers()
	_check_armor_recolours()
	_check_reproportioning()
	_check_rebuild_is_stable()
	_check_parts_line_up_in_depth()
	_check_build_is_once()
	_check_colours()
	_check_save_roundtrip()
	_check_definition_scripts_run_in_the_editor()
	_check_rouge_still_builds()

	# Reported so an assertion loop that silently found nothing to do cannot
	# pass by default.
	print("NPCTEST rigged %d NPCs over %d assertions" % [_rigged, _checks])
	if _expect(_rigged >= 3, "far too few NPCs were built to call this a test"):
		pass
	if _failures.is_empty():
		print("NPCTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("  - ", failure)
		print("NPCTEST RESULT=FAIL (%d problems)" % _failures.size())
		get_tree().quit(1)

func _expect(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(message)
	return condition

## Builds a live NPC and hands it back; caller frees it.
func _spawn(def: NpcDefinition) -> NpcVisual:
	var visual := NpcVisual.new()
	visual.definition = def
	add_child(visual)
	_rigged += 1
	return visual

func _drop(visual: NpcVisual) -> void:
	remove_child(visual)
	visual.free()

func _definition_for(category: String, index := 0) -> NpcDefinition:
	var def := NpcDefinition.new()
	def.display_name = "%s %d" % [category, index]
	for slot: String in NpcDefinition.SLOTS:
		var models := NpcRig.list_parts(slot, category)
		if not models.is_empty():
			def.get_part(slot).model_path = models[mini(index, models.size() - 1)]
	return def

# ---------------------------------------------------------------------------

func _check_library() -> void:
	var categories := NpcRig.list_categories()
	_expect(categories.has("Base"), "the Base part set is missing")
	_expect(categories.has("Undead"), "the Undead part set is missing")
	for category in categories:
		for slot: String in NpcDefinition.SLOTS:
			var models := NpcRig.list_parts(slot, category)
			_expect(not models.is_empty(), "%s has no %s models" % [category, slot])
			for path in models:
				_expect(NpcRig.category_of(path) == category,
						"%s is not filed under %s" % [path, category])
				_expect(not NpcRig.palette_of(path).is_empty(),
						"%s has no readable palette" % path)

## Every model in a set has to rig: a mesh per slot, skinned, and bound only to
## bones that slot is allowed to touch.
func _check_set(category: String) -> void:
	var depth := 0
	for slot: String in NpcDefinition.SLOTS:
		depth = maxi(depth, NpcRig.list_parts(slot, category).size())
	for index in depth:
		var def := _definition_for(category, index)
		var visual := _spawn(def)
		if not _expect(visual.skeleton != null, "%s #%d built no skeleton" % [category, index]):
			_drop(visual)
			continue
		var meshes := visual.skeleton.find_children("*", "MeshInstance3D", false, false)
		_expect(meshes.size() == NpcDefinition.SLOTS.size(),
				"%s #%d rigged %d parts, expected %d"
						% [category, index, meshes.size(), NpcDefinition.SLOTS.size()])
		for mi: MeshInstance3D in meshes:
			var slot := String(mi.name).to_lower()
			_expect(mi.skin != null, "%s #%d %s is not skinned" % [category, index, slot])
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			_expect(verts.size() > 0, "%s #%d %s is empty" % [category, index, slot])
			_expect(colours.size() == verts.size(),
					"%s #%d %s has no per-vertex colour" % [category, index, slot])
			var allowed: Array = NpcRig.BIND_SETS[NpcDefinition.covers(slot)]
			var stray := ""
			var bad_weight := false
			for i in verts.size():
				var bone := visual.skeleton.get_bone_name(bones[i * 4])
				if not allowed.has(bone):
					stray = bone
				if not is_equal_approx(weights[i * 4], 1.0):
					bad_weight = true
			_expect(stray.is_empty(),
					"%s #%d %s bound to %s, which is not in its bind set"
							% [category, index, slot, stray])
			_expect(not bad_weight,
					"%s #%d %s has vertices that are not rigidly bound"
							% [category, index, slot])
		_check_animation_drives(visual, "%s #%d" % [category, index])
		_drop(visual)

## The point of the whole exercise: the retargeted clips must still move the
## reproportioned bones.
func _check_animation_drives(visual: NpcVisual, label: String) -> void:
	if not _expect(visual.anim_player != null, "%s built no animation player" % label):
		return
	_expect(visual.anim_player.has_animation("lib/walk"), "%s has no walk clip" % label)
	var bone := visual.skeleton.find_bone("LeftHand")
	var rest := visual.skeleton.get_bone_global_rest(bone).origin
	visual.preview_clip("walk")
	visual.anim_player.advance(0.4)
	var posed := visual.skeleton.get_bone_global_pose(bone).origin
	_expect(rest.distance_to(posed) > 0.05,
			"%s: walking does not move the hand off its rest pose" % label)

## No two parts may draw the same voxel.
##
## Voxel models get drawn with their neighbours in view for reference and
## exported with them still in place -- the base arms shipped carrying a whole
## copy of the torso. Both meshes then render the same surface and the two
## z-fight, which reads as the NPC flickering inside out.
func _check_no_coincident_surfaces(category: String) -> void:
	var visual := _spawn(_definition_for(category))
	if not _expect(visual.skeleton != null, "%s overlap test built no skeleton" % category):
		_drop(visual)
		return
	var found := _coincident_voxels(visual)
	_expect(int(found["count"]) == 0,
			"%s has %d voxels drawn by two parts at once (%s) -- they will z-fight"
					% [category, found["count"], found["example"]])
	_drop(visual)

## How many voxels of a rigged NPC are painted by two parts at once, and one
## example of it. Shared so the armoured case is measured exactly the same way
## as the bare one.
func _coincident_voxels(visual: NpcVisual) -> Dictionary:
	var scale: float = visual.layout["voxel_scale"]
	var owner_of := {}
	var clashes := 0
	var example := ""
	for mi: MeshInstance3D in visual.skeleton.find_children("*", "MeshInstance3D", false, false):
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var cells := {}
		for t in range(0, verts.size() - 2, 3):
			var centre := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
			cells[Vector3i(((centre - norms[t] * scale * 0.5) / scale * 2.0).round())] = true
		for cell: Vector3i in cells:
			if owner_of.has(cell):
				clashes += 1
				example = "%s over %s" % [mi.name, owner_of[cell]]
			else:
				owner_of[cell] = mi.name
	return {"count": clashes, "example": example}

## Puts a whole suit on a definition, exactly as the builder's switch does.
func _wear(def: NpcDefinition, suit: String) -> void:
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var models := NpcRig.list_parts(slot, suit)
		if not models.is_empty():
			def.get_part(slot).model_path = models[0]

## Every armor mesh on a rigged NPC, keyed by its slot.
func _armor_meshes(visual: NpcVisual) -> Dictionary:
	var out := {}
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var mi := _mesh_named(visual, slot)
		if mi != null:
			out[slot] = mi
	return out

## A part by the slot it came from — the mesh is named for its slot, which is
## the only reason this can be asked at all.
func _mesh_named(visual: NpcVisual, slot: String) -> MeshInstance3D:
	return visual.skeleton.get_node_or_null(NpcRig.mesh_name(slot)) as MeshInstance3D

## Vertex colours come back out of an ArrayMesh quantised to 8 bits a channel,
## so a colour that did survive the trip is still a step or two off what went
## in. Anything inside half a step is the same colour.
func _same_colour(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 \
			and absf(a.b - b.b) < 0.004 and absf(a.a - b.a) < 0.004

## The armor library is its own thing, filed apart from the character sets so a
## suit can never turn up in the set picker as a family of villager.
func _check_armor_library() -> void:
	var suits := NpcRig.list_categories(true)
	_expect(suits.has("Armor1"), "the Armor1 suit is missing from the armor library")
	_expect(not NpcRig.list_categories().has("Armor1"),
			"Armor1 is showing up as a CHARACTER set — it would build an empty walking suit")
	for suit in suits:
		for slot: String in NpcDefinition.ARMOR_SLOTS:
			var models := NpcRig.list_parts(slot, suit)
			if not _expect(not models.is_empty(), "the %s suit has no %s models" % [suit, slot]):
				continue
			for path in models:
				var palette := NpcRig.palette_of(path)
				_expect(not palette.is_empty(), "%s has no readable palette" % path)
				# The point of the limit: at or under it the builder draws one
				# colour picker per palette entry, so the suit can be recoloured
				# piece by piece instead of only being tinted as a whole.
				_expect(palette.size() <= SlotEditor.SWATCH_LIMIT,
						"%s has %d palette entries, over the %d swatches the builder shows — it could only be tinted"
								% [path, palette.size(), SlotEditor.SWATCH_LIMIT])
		# a suit has to be complete, for the same reason a character set does
		_expect(NpcRig.list_parts("head_armor", suit).size() > 0
				and NpcRig.list_parts("body_armor", suit).size() > 0
				and NpcRig.list_parts("arms_armor", suit).size() > 0
				and NpcRig.list_parts("feet_armor", suit).size() > 0,
				"the %s suit is missing a piece" % suit)

## Armor is worn OVER a character, so putting a suit on must add meshes and
## change NOTHING about the character underneath. A helmet that makes an NPC
## two voxels taller is the failure this exists to catch: every part's height
## feeds the stack the skeleton is fitted to, and armor must stay out of it.
func _check_armor_is_a_layer() -> void:
	var bare := _spawn(_definition_for("Base"))
	var armoured_def := _definition_for("Base")
	_wear(armoured_def, "Armor1")
	var armoured := _spawn(armoured_def)
	if not _expect(bare.skeleton != null and armoured.skeleton != null,
			"the armor layer test built no skeleton"):
		_drop(bare)
		_drop(armoured)
		return

	_expect(armoured_def.wears_armor(), "a definition wearing a suit says it is unarmoured")
	var meshes := armoured.skeleton.find_children("*", "MeshInstance3D", false, false)
	_expect(meshes.size() == NpcDefinition.ALL_SLOTS.size(),
			"an armoured NPC rigged %d parts, expected %d"
					% [meshes.size(), NpcDefinition.ALL_SLOTS.size()])

	for key in ["crown", "hip_y", "neck_y", "arm_y", "voxel_scale"]:
		_expect(is_equal_approx(float(bare.layout[key]), float(armoured.layout[key])),
				"putting armor on moved %s from %.4f to %.4f — the suit is feeding the height stack"
						% [key, bare.layout[key], armoured.layout[key]])
	var drift := 0.0
	for i in bare.skeleton.get_bone_count():
		drift = maxf(drift, bare.skeleton.get_bone_global_rest(i).origin.distance_to(
				armoured.skeleton.get_bone_global_rest(i).origin))
	_expect(drift < 0.0001, "armor reproportioned the skeleton by %.4fm" % drift)

	# and it rides the bones of what it covers: a pauldron follows the arm
	var plates := _armor_meshes(armoured)
	_expect(plates.size() == NpcDefinition.ARMOR_SLOTS.size(),
			"only %d of %d armor pieces rigged" % [plates.size(), NpcDefinition.ARMOR_SLOTS.size()])
	for slot: String in plates:
		var mi: MeshInstance3D = plates[slot]
		var allowed: Array = NpcRig.BIND_SETS[NpcDefinition.covers(slot)]
		var arrays := mi.mesh.surface_get_arrays(0)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var stray := ""
		for i in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			var bone := armoured.skeleton.get_bone_name(bones[i * 4])
			if not allowed.has(bone):
				stray = bone
		_expect(stray.is_empty(), "%s is bound to %s, which is not in the %s bind set"
				% [slot, stray, NpcDefinition.covers(slot)])
	_check_animation_drives(armoured, "armoured Base")

	# A plate and the skin under it must not both paint the same voxel — armor is
	# the likeliest place for it, since a suit is drawn against the body it goes
	# over and can easily be exported with part of that body still in it.
	var found := _coincident_voxels(armoured)
	_expect(int(found["count"]) == 0,
			"an armoured NPC draws %d voxels twice (%s) -- they will z-fight"
					% [found["count"], found["example"]])

	# taking the suit off leaves the character exactly as it was
	armoured_def.clear_armor()
	_expect(not armoured_def.wears_armor(), "clear_armor left something on")
	armoured.rebuild(armoured_def)
	_expect(armoured.skeleton.find_children("*", "MeshInstance3D", false, false).size()
			== NpcDefinition.SLOTS.size(), "taking the armor off left its meshes behind")
	_drop(bare)
	_drop(armoured)

## A plate is drawn in place around the part it covers, so once rigged it has to
## still be AROUND it: concentric, and wrapping it left-to-right and
## front-to-back. This is what catches a helmet that has been re-centred onto
## its own bounding box and slid off the head.
func _check_armor_fits_what_it_covers() -> void:
	var def := _definition_for("Base")
	_wear(def, "Armor1")
	var visual := _spawn(def)
	if not _expect(visual.skeleton != null, "the armor fit test built no skeleton"):
		_drop(visual)
		return
	var voxel: float = visual.layout["voxel_scale"]
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var plate := _mesh_named(visual, slot)
		var skin := _mesh_named(visual, NpcDefinition.covers(slot))
		if not _expect(plate != null and skin != null, "%s or what it covers did not rig" % slot):
			continue
		var pa: AABB = plate.mesh.get_aabb()
		var sa: AABB = skin.mesh.get_aabb()
		var offset := (pa.get_center() - sa.get_center()).length() / voxel
		_expect(offset < 1.5,
				"%s sits %.1f voxels off the centre of the %s it is worn over"
						% [slot, offset, NpcDefinition.covers(slot)])
		# it wraps horizontally — a shell is wider than what is inside it
		_expect(pa.size.x >= sa.size.x - 0.001 and pa.size.z >= sa.size.z - 0.001,
				"%s (%.2f x %.2f) is narrower than the %s inside it (%.2f x %.2f)"
						% [slot, pa.size.x, pa.size.z, NpcDefinition.covers(slot),
								sa.size.x, sa.size.z])
		_expect(pa.intersects(sa), "%s does not overlap the %s at all — it is floating"
				% [slot, NpcDefinition.covers(slot)])
	_drop(visual)

## Recolouring the suit is the whole point of it being data: every armor slot
## carries its own palette overrides and its own tint, and neither may leak into
## the character wearing it.
func _check_armor_recolours() -> void:
	var def := _definition_for("Base")
	_wear(def, "Armor1")
	var plate_red := Color(0.85, 0.1, 0.12)
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var part := def.get_part(slot)
		var colours := PackedColorArray()
		for _i in NpcRig.palette_of(part.model_path).size():
			colours.append(plate_red)
		part.colors = colours
	var visual := _spawn(def)
	if not _expect(visual.skeleton != null, "the armor colour test built no skeleton"):
		_drop(visual)
		return
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var mi := _mesh_named(visual, slot)
		if not _expect(mi != null, "%s did not rig" % slot):
			continue
		var painted := true
		for c: Color in (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
			if not _same_colour(c, plate_red):
				painted = false
		_expect(painted, "%s ignored its colour overrides" % slot)
	# the character underneath kept its own colours
	var body := _mesh_named(visual, "body")
	var leaked := false
	for c: Color in (body.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
		if _same_colour(c, plate_red):
			leaked = true
	_expect(not leaked, "recolouring the armor also repainted the body under it")

	# ...and a tint on top of that reaches the mesh too, which is what a
	# hand-shaded suit would have to use
	def.get_part("body_armor").tint = Color(0.2, 0.4, 1.0)
	visual.rebuild(def)
	var tinted := _mesh_named(visual, "body_armor")
	var expected := plate_red * Color(0.2, 0.4, 1.0)
	var ok := true
	for c: Color in (tinted.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
		if not _same_colour(c, expected):
			ok = false
	_expect(ok, "the armor tint did not reach the mesh")
	_drop(visual)

## The skeleton must end up shaped like the voxel art, not like Rouge.
func _check_reproportioning() -> void:
	var def := _definition_for("Base")
	def.height = 1.6
	var visual := _spawn(def)
	if not _expect(visual.skeleton != null, "reproportioning test built no skeleton"):
		_drop(visual)
		return
	var layout := visual.layout
	_expect(is_equal_approx(float(layout["crown"]), 1.6),
			"crown is %s, expected the requested 1.6" % layout["crown"])

	var hips := visual.skeleton.get_bone_global_rest(visual.skeleton.find_bone("Hips")).origin.y
	_expect(is_equal_approx(hips, float(layout["hip_y"])),
			"Hips sits at %.3f but the legs end at %.3f" % [hips, layout["hip_y"]])
	# Rouge's pelvis is at 52%% of his height; stubby voxel legs must be lower,
	# which is the whole reason the rig is reshaped rather than the art.
	_expect(hips / 1.6 < 0.45,
			"Hips at %.0f%% of height -- the skeleton was not reproportioned"
					% [hips / 1.6 * 100.0])

	# The head is one voxel cube; it must be bound to the head bone as a unit.
	var top := 0.0
	for mi: MeshInstance3D in visual.skeleton.find_children("*", "MeshInstance3D", false, false):
		top = maxf(top, mi.mesh.get_aabb().end.y)
	_expect(absf(top - 1.6) < 0.02, "the assembled NPC is %.3f tall, expected 1.6" % top)
	_drop(visual)

## The builder's preview re-rigs the same skeleton on every edit, so rigging
## twice has to land in the same place as rigging once.
func _check_rebuild_is_stable() -> void:
	var def := _definition_for("Base")
	var visual := _spawn(def)
	if not _expect(visual.skeleton != null, "rebuild test built no skeleton"):
		_drop(visual)
		return
	var before: Array[Vector3] = []
	for i in visual.skeleton.get_bone_count():
		before.append(visual.skeleton.get_bone_global_rest(i).origin)
	visual.rebuild(def)
	var drift := 0.0
	for i in visual.skeleton.get_bone_count():
		drift = maxf(drift, before[i].distance_to(visual.skeleton.get_bone_global_rest(i).origin))
	_expect(drift < 0.0001, "re-rigging moved bones by %.4fm; it should be idempotent" % drift)
	_expect(visual.skeleton.find_children("*", "MeshInstance3D", false, false).size()
			== NpcDefinition.SLOTS.size(), "re-rigging left duplicate or missing part meshes")
	_drop(visual)

## Every part lines up front-to-back with the rest of ITS OWN set.
##
## Parts are modelled wherever was convenient in the Goxel grid, so the rig
## centres each one before stacking. Left-to-right it does that by fitting the
## art against its own mirror image, which is right: a character IS symmetric
## about that axis, and the fit ignores a stray voxel that would drag a
## bounding box sideways. Front-to-back nothing is symmetric -- a foot has toes
## at one end -- so the same scoring just picked whichever alignment happened to
## overlap most, and it stood the feet a whole voxel ahead of the torso.
##
## Same-set on purpose. Every arms model carries a copy of the torso it was
## drawn against (you cannot place a sleeve without seeing the shoulder it
## meets), and the rig drops the voxels the body already fills -- so pairing
## arms with a DIFFERENT set's body leaves whatever that other torso does not
## cover behind, sticking out of the chest. That is the reference copy showing,
## not a rig fault, and the sets are authored to be worn whole.
func _check_parts_line_up_in_depth() -> void:
	for category in NpcRig.list_categories():
		for slot: String in NpcDefinition.SLOTS:
			for model in NpcRig.list_parts(slot, category):
				var def := _definition_for(category)
				def.get_part(slot).model_path = model
				var visual := _spawn(def)
				if not _expect(visual.skeleton != null,
						"%s built no skeleton" % model.get_file()):
					_drop(visual)
					continue
				for mi: MeshInstance3D in visual.skeleton.find_children("*", "MeshInstance3D", false, false):
					var depth: float = (mi.mesh.get_aabb() as AABB).get_center().z
					_expect(absf(depth) < 0.001,
							"with %s in the %s slot, %s sits %.3fm off the centre line front-to-back"
									% [model.get_file(), slot, mi.name, depth])
				_drop(visual)

## However many times a visual is asked to build, it builds once.
##
## Entering the tree builds it -- in the editor too, because tool code that
## says NpcVisual.new() gets a live instance whose notifications fire like any
## other node's. The builder preview and NpcCharacter used to call build()
## again on top of that, which parented a second model, a second skeleton and a
## second set of part meshes in exactly the same place. Every voxel surface was
## drawn twice and the two copies z-fought over every pixel, which is what "the
## meshes overlap" looked like on screen.
func _check_build_is_once() -> void:
	var visual := _spawn(_definition_for("Base"))
	visual.build()
	visual.build(false)
	var skeletons := visual.find_children("*", "Skeleton3D", true, false).size()
	var meshes := visual.find_children("*", "MeshInstance3D", true, false).size()
	var players := visual.find_children("*", "AnimationPlayer", true, false).size()
	_expect(skeletons == 1, "building twice left %d skeletons, expected 1" % skeletons)
	_expect(meshes == NpcDefinition.SLOTS.size(),
			"building twice left %d part meshes, expected %d -- coincident copies z-fight"
					% [meshes, NpcDefinition.SLOTS.size()])
	_expect(players == 1, "building twice left %d animation players, expected 1" % players)
	_drop(visual)

## Palette overrides and the tint both have to reach the baked vertex colours.
func _check_colours() -> void:
	var def := _definition_for("Base")
	var body := def.body
	body.colors = PackedColorArray([Color(1.0, 0.0, 0.0)])
	body.tint = Color(1.0, 0.5, 0.5)
	var visual := _spawn(def)
	if not _expect(visual.skeleton != null, "colour test built no skeleton"):
		_drop(visual)
		return
	var mesh := visual.skeleton.get_node_or_null("Body") as MeshInstance3D
	if _expect(mesh != null, "colour test found no body mesh"):
		var colours: PackedColorArray = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var want := Color(1.0, 0.0, 0.0) * Color(1.0, 0.5, 0.5)
		var mismatched := 0
		for c in colours:
			if not c.is_equal_approx(want):
				mismatched += 1
		_expect(mismatched == 0,
				"%d of %d body vertices ignored the colour override"
						% [mismatched, colours.size()])
	_drop(visual)

## Saving has to produce a scene that loads back into a working, talkable NPC.
func _check_save_roundtrip() -> void:
	var def := _definition_for("Undead")
	def.display_name = TEST_NPC_NAME
	def.dialog_id = "blacksmith"
	def.height = 1.9
	var result := Writer.save(def)
	if not _expect(result["ok"], "save failed: %s" % result["message"]):
		return

	var res_path := Writer.definition_path(TEST_NPC_NAME)
	var scene_path := Writer.scene_path(TEST_NPC_NAME)
	var reloaded := load(res_path) as NpcDefinition
	if _expect(reloaded != null, "%s did not reload as an NpcDefinition" % res_path):
		_expect(reloaded.dialog_id == "blacksmith", "dialog_id did not survive the save")
		_expect(is_equal_approx(reloaded.height, 1.9), "height did not survive the save")
		_expect(reloaded.head.model_path == def.head.model_path,
				"the head part did not survive the save")

	var packed := load(scene_path) as PackedScene
	if _expect(packed != null, "%s did not reload as a scene" % scene_path):
		var npc := packed.instantiate() as NpcCharacter
		add_child(npc)
		_expect(npc.visual != null and npc.visual.skeleton != null,
				"the saved NPC scene did not rig itself on load")
		# A skeleton is not a character. Rigging succeeds and leaves a correctly
		# proportioned set of BONES whenever the parts fail to load, and from
		# outside that is indistinguishable from the save having eaten the mesh
		# -- so every slot the definition names has to come back with geometry
		# on it, not just a rig to hang it from.
		if npc.visual != null and npc.visual.skeleton != null:
			var drawn := {}
			for mi: MeshInstance3D in npc.visual.skeleton.find_children(
					"*", "MeshInstance3D", false, false):
				var verts := 0
				if mi.mesh != null:
					for s in mi.mesh.get_surface_count():
						verts += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
				if verts > 0:
					drawn[String(mi.name).to_lower()] = verts
			for slot: String in NpcDefinition.SLOTS:
				if def.get_part(slot).model_path.is_empty():
					continue
				_expect(drawn.has(slot),
						"the saved NPC came back with no %s mesh (drawn: %s)" % [slot, drawn])
		_expect(npc.interactable != null and npc.interactable.dialog_id == "blacksmith",
				"the saved NPC scene is not talkable")
		remove_child(npc)
		npc.free()

	for path in [res_path, scene_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## The one thing about a built NPC that a headless run cannot see for itself.
##
## An NpcDefinition placed in a level is LOADED FROM DISK, and the editor gives
## a loaded resource whose script is not a tool script a PLACEHOLDER instance:
## the exported properties are all there, but every method call dies with
## "Attempt to call a method on a placeholder instance". NpcRig reaches its
## parts through `get_part()`, so a placed NPC collected nothing and came out
## as a correctly proportioned skeleton with no body -- while the builder's own
## preview, whose definition is a live `NpcDefinition.new()`, looked perfect.
##
## Nothing in a --headless run is a placeholder, so this is checked as the
## invariant it is rather than by rigging something.
func _check_definition_scripts_run_in_the_editor() -> void:
	for path in ["res://scripts/entities/npc/npc_definition.gd",
			"res://scripts/entities/npc/npc_part.gd"]:
		var script := load(path) as Script
		if _expect(script != null, "%s did not load as a script" % path):
			_expect(script.is_tool(),
					"%s is not @tool — the editor will hand placed NPCs a placeholder "
					% path + "definition and they will rig as bare skeletons")

## The refactor that gave NPCs their rig also rewrote Rouge's base class.
func _check_rouge_still_builds() -> void:
	var rouge := RougeVisual.new()
	add_child(rouge)
	_expect(rouge.skeleton != null, "RougeVisual no longer builds a skeleton")
	_expect(rouge.model.find_children("*", "MeshInstance3D", true, false).size() > 0,
			"RougeVisual no longer has any meshes")
	# CLIPS plus the guard-movement variants, which are grafted together at
	# build time rather than listed as clips of their own
	var expected: int = HumanoidVisual.CLIPS.size() + HumanoidVisual.BLOCK_MOVE.size()
	_expect(rouge.clip_lengths.size() == expected,
			"RougeVisual built %d clips, expected %d"
					% [rouge.clip_lengths.size(), expected])
	var info := rouge.get_attack_info(false, 0)
	_expect(float(info["duration"]) > 0.0, "RougeVisual reports no attack duration")
	_check_sword_clips(rouge)
	_check_long_idle(rouge)
	remove_child(rouge)
	rouge.free()

## Standing still for IDLE_LONG_AFTER drops the character into the second idle
## pose, and ANY movement puts them back to the first. Driven through tick()
## with the deltas a frame would bring, because the clock lives inside it —
## reading the constant back would test nothing.
func _check_long_idle(vis: HumanoidVisual) -> void:
	var wait: float = HumanoidVisual.IDLE_LONG_AFTER
	_expect(vis.clip_lengths.has("idle_long"), "the long idle clip was never built")

	# 1. it is the short idle right up to the moment, not before it
	vis.tick(0.0, "idle")
	_expect(vis._current_key == "idle", "standing still should start on 'idle'")
	_tick_for(vis, "idle", wait - 1.0)
	_expect(vis._current_key == "idle",
			"'idle_long' came up after %.0fs, before the %.0fs it waits for"
					% [wait - 1.0, wait])

	# 2. and the long one once the wait is up
	_tick_for(vis, "idle", 1.5)
	_expect(vis._current_key == "idle_long",
			"still on '%s' after %.0fs stood still" % [vis._current_key, wait + 0.5])

	# 3. one step resets it — the clock is time spent doing nothing, not time
	# since the character last idled
	vis.tick(0.1, "run", 0.0, 1.0)
	_tick_for(vis, "idle", 1.0)
	_expect(vis._current_key == "idle",
			"moving did not put the character back on the short idle")

	# 4. with a blade in hand there is one standing pose, so the swap is
	# invisible rather than yanking the sword idle away
	vis.set_held_item("iron_sword")
	_tick_for(vis, "idle", wait + 1.5)
	_expect(vis._current_key == "sword_idle",
			"a sword in hand should stay on 'sword_idle', got '%s'" % vis._current_key)
	vis.set_held_item("")

	# 5. and a character built without the clip (a villager: idle/walk/run) just
	# keeps standing there instead of erroring on a clip it never loaded
	_expect(not HumanoidVisual.CLIPS.keys().is_empty(), "the clip table is empty")
	_expect(not NpcVisual.NPC_CLIPS.has("idle_long"),
			"villagers now load the fighting idle — they have no business in it")

	vis.tick(0.1, "run", 0.0, 1.0) # leave it as it was found

func _tick_for(vis: HumanoidVisual, anim: String, seconds: float) -> void:
	var step := 1.0 / 60.0
	var left := seconds
	while left > 0.0:
		vis.tick(minf(step, left), anim)
		left -= step

## A sword in hand swaps the clip set. The sliced swings come out of one long
## combo take, so a bad slice shows up as a zero-length clip rather than an
## error — check they all carry real time, and that empty hands are unaffected.
func _check_sword_clips(vis: HumanoidVisual) -> void:
	_expect(vis._clip_for("idle") == "idle", "empty hands already swap clips")
	var bare := [vis.get_attack_info(false, 0), vis.get_attack_info(false, 2),
			vis.get_attack_info(true, 0)]
	vis.set_held_item("iron_sword")
	# a weapon must not change how fast you fight: same window, armed or not
	var armed := [vis.get_attack_info(false, 0), vis.get_attack_info(false, 2),
			vis.get_attack_info(true, 0)]
	for i in bare.size():
		_expect(is_equal_approx(float(bare[i]["duration"]), float(armed[i]["duration"])),
				"holding a sword changed swing %d: %.3fs vs %.3fs"
						% [i, float(bare[i]["duration"]), float(armed[i]["duration"])])
	_expect(float(armed[2]["duration"]) > float(armed[0]["duration"]),
			"the heavy is not slower than a light swing")
	_expect(vis.held_id == "iron_sword", "the sword never reached the hand")
	_expect(vis.skeleton.find_children("HeldItem", "BoneAttachment3D", true, false).size() == 1,
			"the sword is not attached to a bone")
	for key: String in HumanoidVisual.SWORD_CLIPS:
		var swapped: String = HumanoidVisual.SWORD_CLIPS[key]
		_expect(vis._clip_for(key) == swapped,
				"holding a sword did not swap '%s' for '%s'" % [key, swapped])
		_expect(float(vis.clip_lengths.get(swapped, 0.0)) > 0.05,
				"sword clip '%s' is empty — check its slice" % swapped)
	_expect(float(vis.get_attack_info(false, 0)["duration"]) > 0.0,
			"no swing timing with a sword out")
	vis.set_held_item("")
	_expect(vis._clip_for("idle") == "idle", "dropping the sword kept its clips")
	_expect(vis.skeleton.find_children("HeldItem", "BoneAttachment3D", true, false).is_empty(),
			"the sword stayed in the hand after dropping it")
