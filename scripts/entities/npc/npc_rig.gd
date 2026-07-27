class_name NpcRig
extends RefCounted
## Auto-rigs a set of voxel part models onto the humanoid skeleton the Rouge
## character uses, so a built NPC animates off exactly the same Mixamo clips as
## the player and the bandits.
##
## Two things make that possible:
##
##  * The retargeted clips are rotation-only -- every bone except Hips has just
##    a rotation track. Bone REST positions therefore define the silhouette and
##    nothing in the animation fights them, so instead of stretching the voxel
##    art onto human proportions we do the opposite: the skeleton is
##    reproportioned onto the art. Legs get stubby, the head gets big, and the
##    clips still play correctly.
##  * The parts are rigidly skinned -- every triangle of a voxel is bound whole
##    to one bone with weight 1. That is what keeps the blocky look: pieces
##    rotate about the joints instead of bending like skin.
##
## Everything is derived from the models themselves (their bounding boxes, their
## symmetry, where their arms stick out), so a new part dropped into the library
## works with no metadata.
##
## THIS FILE IS THE ORCHESTRATOR AND THE FRONT DOOR. Each stage lives in
## scripts/entities/npc/rig/ and can be read on its own:
##
##   NpcPartLibrary    where the art is filed, and what is on offer
##   NpcPartLoader     a model -> flat arrays + its palette
##   NpcLayout         where each part sits, and the landmarks to fit to
##   NpcReproportion   moving the bone rests onto those landmarks
##   NpcSkinner        bones per voxel, who owns a shared cell, and the seam caps
##
## The `NpcRig.*` names below stay because forty call sites across the builder
## tabs, the item icons and the tests already use them, and "the rig" is the
## right thing for them to be asking.

const PARTS_ROOT := NpcPartLibrary.PARTS_ROOT
const ARMOR_ROOT := NpcPartLibrary.ARMOR_ROOT
const BIND_SETS := NpcSkinner.BIND_SETS
const MODEL_YAW := NpcLayout.MODEL_YAW
const SOURCE_REST_META := NpcReproportion.SOURCE_REST_META

# ---------------------------------------------------------------------------
# the part library (see NpcPartLibrary)
# ---------------------------------------------------------------------------

static func clear_cache() -> void:
	NpcPartLoader.clear_cache()

static func list_categories(armor := false) -> PackedStringArray:
	return NpcPartLibrary.list_categories(armor)

static func categories_for(slot: String) -> PackedStringArray:
	return NpcPartLibrary.categories_for(slot)

static func slot_dir(category: String, slot: String) -> String:
	return NpcPartLibrary.slot_dir(category, slot)

static func list_parts(slot: String, category := "") -> PackedStringArray:
	return NpcPartLibrary.list_parts(slot, category)

static func category_of(model_path: String) -> String:
	return NpcPartLibrary.category_of(model_path)

static func mesh_name(slot: String) -> String:
	return NpcPartLibrary.mesh_name(slot)

static func part_title(model_path: String) -> String:
	return NpcPartLibrary.part_title(model_path)

static func palette_of(model_path: String) -> PackedColorArray:
	return NpcPartLoader.palette_of(model_path)

# ---------------------------------------------------------------------------
# rigging
# ---------------------------------------------------------------------------

## Reproportions `skeleton` to fit `def`'s parts and parents a skinned
## MeshInstance3D per part under it. Returns the layout metrics (crown height,
## hip height, ...) so callers can size collision shapes and prompt offsets.
static func rig(def: NpcDefinition, skeleton: Skeleton3D) -> Dictionary:
	var parts := _load_parts(def)
	var layout := NpcLayout.build(def, parts)
	NpcReproportion.apply(skeleton, layout)

	var skin := skeleton.create_skin_from_rest_transforms()
	var segments := NpcSkinner.segments(skeleton)
	# Who owns each voxel, worked out for EVERY part before any mesh is built.
	# Two reasons it is a pass of its own rather than something each part does on
	# its way past:
	#  * Voxels an earlier part already fills are dropped. Models are routinely
	#    drawn with their neighbours in view for reference and exported with them
	#    still there -- the base arms carry a whole copy of the torso -- and two
	#    parts painting the same cell means two coincident surfaces fighting over
	#    every pixel. Slot order decides who wins: the torso beats the arms laid
	#    over it.
	#  * The seam caps need to know which bone the voxel NEXT DOOR binds to, and
	#    next door is often the next part along -- the join under the chin is the
	#    head meeting the body. A part built before its neighbour exists cannot
	#    ask.
	var occupied := {}
	var cells := {}
	for slot: String in NpcDefinition.ALL_SLOTS:
		if parts.has(slot):
			cells[slot] = NpcSkinner.claim_cells(slot, parts[slot], def.get_part(slot),
					layout["part_xf"][slot], skeleton, segments,
					layout["voxel_scale"], occupied)
	for slot: String in NpcDefinition.ALL_SLOTS:
		if not parts.has(slot):
			continue
		var mi := NpcSkinner.build_mesh(parts[slot], def.get_part(slot),
				layout["part_xf"][slot], cells[slot], occupied, layout["voxel_scale"])
		if mi == null:
			continue
		mi.name = mesh_name(slot)
		mi.skin = skin
		skeleton.add_child(mi)
		# A skin on its own animates nothing: the mesh also has to POINT at the
		# skeleton, and a code-made MeshInstance3D starts with that path empty --
		# being a child of the Skeleton3D is not enough. Without it every part
		# draws at its bind pose while the bones underneath animate perfectly,
		# which reads as a character frozen mid T-pose rather than as one missing
		# NodePath.
		mi.skeleton = NodePath("..")
	return layout

## Every part model a definition names, flattened — and a LOUD complaint about
## any that would not load. A slot that fails to load is the whole slot gone,
## and the only sign of it used to be a gap in the character.
static func _load_parts(def: NpcDefinition) -> Dictionary:
	var parts := {}
	var asked := 0
	for slot: String in NpcDefinition.ALL_SLOTS:
		var spec: NpcPart = def.get_part(slot)
		var path := spec.model_path if spec else ""
		if not path.is_empty():
			asked += 1
		var data := NpcPartLoader.load_part(path)
		if not data.is_empty():
			parts[slot] = data
		elif not path.is_empty():
			push_error("NpcRig: the %s model %s could not be loaded — that slot will be empty"
					% [slot, path])
	# Nothing to hang on the bones at all. Worth its own line: the caller gets a
	# rigged, correctly proportioned, completely invisible character otherwise,
	# which reads as "the mesh was lost" rather than "no part model loaded".
	if parts.is_empty():
		push_error("NpcRig: '%s' rigged with no parts at all — %s" % [def.display_name,
				"its definition names no models" if asked == 0
						else "none of the %d models it names could be loaded" % asked])
	return parts

## The part ON ITS OWN: the art as drawn, in this NpcPart's colours, turned to
## face +Z, and bound to nothing. It is for LOOKING at a piece with no character
## under it — an item icon of a helmet — which is why it skips everything the
## rigged path does for the sake of MOVEMENT: no bones, no cell claiming (there
## is no neighbouring part to lose voxels to) and no seam caps (nothing here can
## come apart, because nothing here can move). The part's `offset` and `scale`
## are skipped for the same reason: both are nudges for fitting it onto a body.
static func preview_mesh(spec: NpcPart) -> MeshInstance3D:
	if spec == null:
		return null
	var data := NpcPartLoader.load_part(spec.model_path)
	if data.is_empty():
		return null
	var verts: PackedVector3Array = data["verts"]
	if verts.is_empty():
		return null
	var entry: PackedInt32Array = data["entry"]
	var palette: PackedColorArray = data["palette"]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for i in verts.size():
		cols[i] = NpcPartLoader.colour(spec, palette, entry[i])

	var mi := MeshInstance3D.new()
	# sRGB decode, unlike the rigged path: a part's colours come out of a Goxel
	# palette PNG or a Godot colour picker, both display values, so without it
	# every one of them renders about a tenth too bright — an authored 0.73 grey
	# photographs at 0.82 and the copper suit washes out to pink. This is what
	# makes an item's icon the item's OWN colour.
	mi.mesh = NpcSkinner.surface({
		Mesh.ARRAY_VERTEX: verts, Mesh.ARRAY_NORMAL: data["norms"], Mesh.ARRAY_COLOR: cols,
	}, true)
	# Goxel models are built facing +X; turned here so a piece looked at from the
	# front is looked at from ITS front, the same way a rigged character is.
	mi.rotate_y(MODEL_YAW)
	return mi
