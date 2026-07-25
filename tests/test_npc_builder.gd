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
	_check_reproportioning()
	_check_rebuild_is_stable()
	_check_colours()
	_check_save_roundtrip()
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
			var allowed: Array = NpcRig.BIND_SETS[slot]
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
	_expect(clashes == 0,
			"%s has %d voxels drawn by two parts at once (%s) -- they will z-fight"
					% [category, clashes, example])
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
		_expect(npc.interactable != null and npc.interactable.dialog_id == "blacksmith",
				"the saved NPC scene is not talkable")
		remove_child(npc)
		npc.free()

	for path in [res_path, scene_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

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
	remove_child(rouge)
	rouge.free()
