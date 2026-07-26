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
##    reproportioned onto the art (`_reproportion`). Legs get stubby, the head
##    gets big, and the clips still play correctly.
##  * The parts are rigidly skinned -- every triangle of a voxel is bound whole
##    to one bone with weight 1 (`_nearest_bone`). That is what keeps the blocky
##    look: pieces rotate about the joints instead of bending like skin.
##
## Everything is derived from the models themselves (their bounding boxes,
## their symmetry, where their arms stick out), so a new part dropped into
## Assets/Models/Entity/Humanoid/VoxelNpc/Parts/<Slot>/ works with no metadata.

const PARTS_ROOT := "res://Assets/Models/Entity/Humanoid/VoxelNpc/Parts/"
## Armor lives in its OWN library rather than as another character set. A suit
## is not a family of villager: filed under Parts/ it would show up in the set
## picker, and "use whole set" would build a walking empty suit with no head,
## no hands and no one inside it.
const ARMOR_ROOT := "res://Assets/Models/Entity/Humanoid/VoxelNpc/Armor/"
const MODEL_EXTS := ["gltf", "glb", "obj", "res", "scn", "tscn"]

## Which bones each slot is allowed to bind to. Restricting per slot is what
## stops the arms model's centre section (which lives inside the torso) from
## grabbing an arm bone and flying off with it.
const BIND_SETS := {
	"feet": ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
			"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"],
	# No shoulders in the torso set: they swing with the arms, and letting them
	# claim the top of the chest would knead the whole body every stride.
	"body": ["Hips", "Spine", "Chest", "UpperChest", "Neck"],
	# No CLAVICLES either, and for the mirror of the reason above: a clavicle runs
	# from the spine out to the shoulder joint, so its segment lies along the
	# inner half of the sleeve and claims it -- and a clavicle barely rotates in
	# these clips while the upper arm swings the whole way. That splits one rigid
	# sleeve between a bone that moves and a bone that does not, and the voxels
	# tear apart into a sawtooth at the shoulder. A voxel arm swings whole,
	# shoulder cap included.
	"arms": ["UpperChest", "LeftUpperArm", "LeftLowerArm", "LeftHand",
			"RightUpperArm", "RightLowerArm", "RightHand"],
	# Head only, never Neck: Head is a child of Neck, so it already inherits the
	# neck's motion, and binding it whole keeps a voxel skull from shearing.
	"head": ["Head"],
}

## Goxel models are built facing +X; the game's characters face +Z.
const MODEL_YAW := -PI / 2.0

## Where the untouched bone rests are stashed on a skeleton we have reshaped.
const SOURCE_REST_META := "npc_rig_source_rest"

## Flattened part models, keyed by path. Loading one means instancing a scene
## and walking its surfaces, and the builder re-rigs constantly while you drag
## a colour around; `clear_cache()` drops it when the art changes on disk.
static var _part_cache := {}

static func clear_cache() -> void:
	_part_cache.clear()


# ---------------------------------------------------------------------------
# part library
# ---------------------------------------------------------------------------

## Part models are filed Parts/<Category>/<Slot>/, so a whole character family
## ("Base", "Undead", ...) is one folder and shows up in the builder as its own
## section. Slots can still be mixed across categories.
static func list_categories(armor := false) -> PackedStringArray:
	var out := PackedStringArray()
	var root := ARMOR_ROOT if armor else PARTS_ROOT
	if DirAccess.dir_exists_absolute(root):
		for d in DirAccess.get_directories_at(root):
			out.append(d)
	out.sort()
	return out

## The sets a given slot can be filled from: armor suits for an armor slot,
## character families for a skin one. Menus ask this instead of choosing a
## library themselves.
static func categories_for(slot: String) -> PackedStringArray:
	return list_categories(NpcDefinition.is_armor(slot))

## An armor slot's models sit in its OWN library under the folder of the slot
## they cover — Armor/<Suit>/Head/ holds what goes over Parts/<Set>/Head/.
static func slot_dir(category: String, slot: String) -> String:
	var root := ARMOR_ROOT if NpcDefinition.is_armor(slot) else PARTS_ROOT
	return "%s%s/%s/" % [root, category, NpcDefinition.covers(slot).capitalize()]

## Every model available for a slot, as res:// paths; all categories unless one
## is named. Editor-side only -- a built NPC stores the path it chose and loads
## that directly.
static func list_parts(slot: String, category := "") -> PackedStringArray:
	var out := PackedStringArray()
	var categories := PackedStringArray([category]) if category != "" else categories_for(slot)
	for cat in categories:
		var dir := slot_dir(cat, slot)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			var file := f.trim_suffix(".import").trim_suffix(".remap")
			if file.get_extension().to_lower() in MODEL_EXTS and not out.has(dir + file):
				out.append(dir + file)
	return out

static func category_of(model_path: String) -> String:
	for root in [PARTS_ROOT, ARMOR_ROOT]:
		if model_path.begins_with(root):
			return model_path.trim_prefix(root).get_slice("/", 0)
	return ""

## What a slot's mesh is called under the skeleton: "feet" -> "Feet",
## "feet_armor" -> "FeetArmor". NOT String.capitalize(), which turns the second
## one into "Feet Armor" — a name with a space in it no longer says which slot
## it came from, and finding a part by its slot is how everything downstream
## (the tests, anything reaching for a piece) does it.
static func mesh_name(slot: String) -> String:
	var out := ""
	for chunk in slot.split("_", false):
		out += chunk.substr(0, 1).to_upper() + chunk.substr(1)
	return out

## "skeleton_head.gltf" -> "Skeleton Head", for menus.
static func part_title(model_path: String) -> String:
	return model_path.get_file().get_basename().replace("_", " ").capitalize()

## The model's own colours, in the order the NpcPart.colors overrides map onto.
static func palette_of(model_path: String) -> PackedColorArray:
	var part := _load_part(model_path)
	return part.get("palette", PackedColorArray()) as PackedColorArray


# ---------------------------------------------------------------------------
# rigging
# ---------------------------------------------------------------------------

## Reproportions `skeleton` to fit `def`'s parts and parents a skinned
## MeshInstance3D per part under it. Returns the layout metrics (crown height,
## hip height, ...) so callers can size collision shapes and prompt offsets.
static func rig(def: NpcDefinition, skeleton: Skeleton3D) -> Dictionary:
	var parts := {}
	var asked := 0
	for slot: String in NpcDefinition.ALL_SLOTS:
		var spec: NpcPart = def.get_part(slot)
		var path := spec.model_path if spec else ""
		if not path.is_empty():
			asked += 1
		var data := _load_part(path)
		if not data.is_empty():
			parts[slot] = data
		elif not path.is_empty():
			# A part that will not load is the whole slot gone, and the only sign
			# of it used to be a gap in the character. Say so: an NPC that comes
			# out as a bare skeleton is nearly always four of these in a row.
			push_error("NpcRig: the %s model %s could not be loaded — that slot will be empty"
					% [slot, path])
	# Nothing to hang on the bones at all. Worth its own line: the caller gets a
	# rigged, correctly proportioned, completely invisible character otherwise,
	# which reads as "the mesh was lost" rather than "no part model loaded".
	if parts.is_empty():
		push_error("NpcRig: '%s' rigged with no parts at all — %s" % [
				def.display_name,
				"its definition names no models" if asked == 0
						else "none of the %d models it names could be loaded" % asked])

	var layout := _layout(def, parts)
	_reproportion(skeleton, layout)

	var skin := skeleton.create_skin_from_rest_transforms()
	var segments := _segments(skeleton)
	# Who owns each voxel, worked out for EVERY part before any mesh is built.
	# Two reasons it is a pass of its own rather than something each part does on
	# its way past:
	#  * Voxels an earlier part already fills are dropped. Models are routinely
	#    drawn with their neighbours in view for reference and exported with them
	#    still there -- the base arms carry a whole copy of the torso -- and two
	#    parts painting the same cell means two coincident surfaces fighting over
	#    every pixel. Slot order decides who wins: the torso beats the arms laid
	#    over it.
	#  * The seam caps below need to know which bone the voxel NEXT DOOR binds
	#    to, and next door is often the next part along -- the join under the
	#    chin is the head meeting the body. A part built before its neighbour
	#    exists cannot ask.
	var occupied := {}
	var cells := {}
	for slot: String in NpcDefinition.ALL_SLOTS:
		if not parts.has(slot):
			continue
		cells[slot] = _claim_cells(slot, parts[slot], def.get_part(slot),
				layout["part_xf"][slot], skeleton, segments,
				layout["voxel_scale"], occupied)
	for slot: String in NpcDefinition.ALL_SLOTS:
		if not parts.has(slot):
			continue
		var mi := _build_mesh(parts[slot], def.get_part(slot),
				layout["part_xf"][slot], cells[slot], occupied,
				layout["voxel_scale"])
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


# ---------------------------------------------------------------------------
# loading part models
# ---------------------------------------------------------------------------

## Flattens a part model to plain arrays in its own voxel space (Y up, 1 unit
## per voxel -- the Goxel exporter's Z-up->Y-up root node is baked in here).
static func _load_part(model_path: String) -> Dictionary:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return {}
	if _part_cache.has(model_path):
		return _part_cache[model_path]
	var scene := load(model_path) as PackedScene
	if scene == null:
		return {}
	var root := scene.instantiate()

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var image: Image = null
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := _relative_transform(mi, root)
		for s in mi.mesh.get_surface_count():
			if image == null:
				image = _palette_image(mi, s)
			var arrays := mi.mesh.surface_get_arrays(s)
			var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var sn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var su: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var si: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if si.is_empty():
				si.resize(sv.size())
				for i in sv.size():
					si[i] = i
			# Unwelded on purpose: rigid skinning decides a bone per triangle,
			# and shared corners would have to pick one of them.
			for i in si:
				verts.append(xf * sv[i])
				norms.append((xf.basis * (sn[i] if i < sn.size() else Vector3.UP)).normalized())
				uvs.append(su[i] if i < su.size() else Vector2.ZERO)
	root.free()

	var palette := _canonical_palette(uvs, image)
	var entry := PackedInt32Array()
	entry.resize(uvs.size())
	for i in uvs.size():
		entry[i] = palette["index_of"].get(_uv_key(uvs[i]), 0)
	_part_cache[model_path] = {
		"verts": verts,
		"norms": norms,
		"entry": entry,
		"palette": palette["colors"],
	}
	return _part_cache[model_path]

static func _relative_transform(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf

static func _palette_image(mi: MeshInstance3D, surface: int) -> Image:
	var mat := mi.mesh.surface_get_material(surface)
	if mat == null:
		mat = mi.get_active_material(surface)
	var std := mat as StandardMaterial3D
	if std == null or std.albedo_texture == null:
		return null
	var img := std.albedo_texture.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	return img

## Goxel writes one flat tile per colour and points every vertex at its tile's
## centre, so the distinct UVs ARE the palette. Sorting them gives a stable
## entry order that NpcPart.colors can index into.
static func _canonical_palette(uvs: PackedVector2Array, image: Image) -> Dictionary:
	var keys := {}
	for uv in uvs:
		keys[_uv_key(uv)] = uv
	var sorted: Array = keys.keys()
	sorted.sort()
	var colors := PackedColorArray()
	var index_of := {}
	for key: String in sorted:
		index_of[key] = colors.size()
		colors.append(_sample(image, keys[key]))
	return {"colors": colors, "index_of": index_of}

static func _uv_key(uv: Vector2) -> String:
	return "%.5f|%.5f" % [uv.y, uv.x]

static func _sample(image: Image, uv: Vector2) -> Color:
	if image == null:
		return Color.WHITE
	var x := clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1)
	var y := clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


# ---------------------------------------------------------------------------
# layout: where each part sits, and the landmarks the skeleton is fitted to
# ---------------------------------------------------------------------------

static func _layout(def: NpcDefinition, parts: Dictionary) -> Dictionary:
	var yaw := Basis(Vector3.UP, MODEL_YAW)
	var metrics := {}
	for slot: String in parts:
		var spec: NpcPart = def.get_part(slot)
		var verts: PackedVector3Array = parts[slot]["verts"]
		var zs := PackedFloat32Array()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for v in verts:
			zs.append(v.z)
			lo = lo.min(v)
			hi = hi.max(v)
		# Model Z is the character's LEFT-RIGHT axis (the parts are yawed a
		# quarter turn below), and that is the one a character is symmetric
		# about, so it gets the mirror fit. Model X is front-to-back, where
		# nothing is symmetric -- a foot has toes at one end -- and scoring it
		# for symmetry just picks whichever alignment happens to overlap most:
		# it put the feet a whole voxel ahead of the torso. Depth is the plain
		# bounding-box middle.
		metrics[slot] = {
			"centre": Vector3((lo.x + hi.x) * 0.5, lo.y, _symmetry_centre(zs)),
			"size": (hi - lo) * spec.scale,
		}
	# Arms are modelled in the TORSO's vertical frame, not their own: the base
	# set draws a T-bar spanning the whole body, the undead set draws bare arms
	# up at shoulder height. Anchoring them to the body's floor instead of their
	# own keeps both where the artist put them.
	if metrics.has("arms") and metrics.has("body"):
		var arms_centre: Vector3 = metrics["arms"]["centre"]
		arms_centre.y = (metrics["body"]["centre"] as Vector3).y
		metrics["arms"]["centre"] = arms_centre
	# Armor is the same idea taken all the way: a plate is drawn IN PLACE over
	# the part it covers -- same Goxel grid, a voxel out on each side -- so it
	# takes that part's centre wholesale instead of being re-centred on its own
	# bounding box, which would slide a breastplate off the chest it was drawn
	# around. The fit is then exactly what the artist drew, not something the rig
	# has second-guessed. Arms armor inherits the torso rebase above with it.
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var under := NpcDefinition.covers(slot)
		if metrics.has(slot) and metrics.has(under):
			metrics[slot]["centre"] = metrics[under]["centre"]

	var feet_h: float = metrics["feet"]["size"].y if metrics.has("feet") else 0.0
	var body_h: float = metrics["body"]["size"].y if metrics.has("body") else 0.0
	var head_h: float = metrics["head"]["size"].y if metrics.has("head") else 0.0
	var total: float = maxf(feet_h + body_h + head_h, 0.001)
	var voxel_scale: float = def.height / total
	# Arms share the body's base: the T-bar model overlaps the torso instead of
	# stacking on it.
	var stack := {"feet": 0.0, "body": feet_h, "arms": feet_h, "head": feet_h + body_h}
	# Armor stands on the same step as what it covers -- and note that NOTHING
	# on the armor layer reached feet_h/body_h/head_h above, which is what keeps
	# a helmet from making the character two voxels taller.
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		stack[slot] = stack[NpcDefinition.covers(slot)]

	var part_xf := {}
	for slot: String in parts:
		var spec: NpcPart = def.get_part(slot)
		var m: Dictionary = metrics[slot]
		# An armor piece's own scale is RELATIVE to the part it covers, so
		# scaling a body carries its plate with it instead of leaving the suit
		# behind at its original size.
		var part_scale := spec.scale
		if NpcDefinition.is_armor(slot):
			var under: NpcPart = def.get_part(NpcDefinition.covers(slot))
			if under != null:
				part_scale *= under.scale
		var xf := Transform3D(Basis.IDENTITY, -(m["centre"] as Vector3))
		xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * part_scale), Vector3.ZERO) * xf
		xf = Transform3D(yaw, Vector3.ZERO) * xf
		xf = Transform3D(Basis.IDENTITY, spec.offset + Vector3.UP * stack[slot]) * xf
		part_xf[slot] = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * voxel_scale), Vector3.ZERO) * xf

	var hip_y := feet_h * voxel_scale
	var neck_y := (feet_h + body_h) * voxel_scale
	var layout := {
		"voxel_scale": voxel_scale,
		"part_xf": part_xf,
		"crown": def.height,
		"hip_y": hip_y,
		"neck_y": neck_y,
		"head_y": neck_y + head_h * voxel_scale * 0.25,
		"arm_y": lerpf(hip_y, neck_y, 0.75),
		"hand_x": def.height * 0.28,
		"arm_thick": def.height * 0.08,
		"leg_x": def.height * 0.06,
		"shoulder_x": def.height * 0.09,
	}
	_measure_arms(layout, parts, part_xf)
	_measure_legs(layout, parts, part_xf)
	# Where the arm hangs FROM. Half the arm's own thickness outside the torso's
	# edge, because that is the pivot an arm can be rotated down to the
	# character's side about and land flush against the body rather than inside
	# it: swung a quarter turn, a bar pivoted at `p` sweeps out the slab
	# [p - thickness/2, p + thickness/2].
	#
	# Getting this from the ART rather than from the human rig's proportions is
	# the whole point. A voxel character is a third as wide as it is tall and the
	# human it borrows its skeleton from is not, so a shoulder placed at the
	# human's shoulder-to-hand ratio lands INSIDE the chest -- and an arm pivoting
	# in the middle of the chest spends every clip ploughing through it.
	var torso_x: float = layout["hand_x"] * 0.35
	if parts.has("body"):
		var torso := _mirrored_points(parts["body"]["verts"], part_xf["body"])
		torso_x = maxf(_half_width(torso), 0.01)
		layout["shoulder_x"] = maxf(torso_x * 0.5, 0.01)
	# Never past the hand: a character with stubby arms on a broad body would
	# otherwise put the shoulder outboard of its own fist and turn the arm inside
	# out.
	layout["arm_root_x"] = minf(torso_x + layout["arm_thick"] * 0.5,
			layout["hand_x"] * 0.75)
	# The Y landmarks feed a piecewise remap, which needs them strictly rising.
	var floor_y := 0.0
	for key in ["hip_y", "arm_y", "neck_y", "head_y", "crown"]:
		floor_y = maxf(floor_y + 0.01, layout[key])
		layout[key] = floor_y
	return layout

## Arm height, reach and thickness, read off the outer quarter of the arms model
## -- the part that actually sticks out past the torso.
##
## Only the outer quarter, and that matters for the thickness: an arms model
## carries a reference copy of the torso through its middle (see the occlusion
## pass in `rig`), so measured whole it is as thick as a chest.
static func _measure_arms(layout: Dictionary, parts: Dictionary, part_xf: Dictionary) -> void:
	if not parts.has("arms"):
		return
	var points := _mirrored_points(parts["arms"]["verts"], part_xf["arms"])
	var reach := _half_width(points)
	if reach <= 0.0:
		return
	var sum := 0.0
	var count := 0
	var lo := INF
	var hi := -INF
	for p in points:
		if absf(p.x) >= reach * 0.75:
			sum += p.y
			count += 1
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	# The bone wants to sit inside the hand rather than on its outer face.
	layout["hand_x"] = reach * 0.85
	if count > 0:
		layout["arm_y"] = sum / count
		layout["arm_thick"] = maxf(hi - lo, 0.01)

## Where the legs stand, so the leg bones land inside them rather than on the
## model's centre line.
static func _measure_legs(layout: Dictionary, parts: Dictionary, part_xf: Dictionary) -> void:
	if not parts.has("feet"):
		return
	var points := _mirrored_points(parts["feet"]["verts"], part_xf["feet"])
	var span := _half_width(points)
	if span <= 0.0:
		return
	var sum := 0.0
	var count := 0
	for p in points:
		if absf(p.x) >= span * 0.25:
			sum += absf(p.x)
			count += 1
	if count > 0:
		layout["leg_x"] = sum / count

## The part's vertices in character space, keeping only those with a mirror
## twin across the centre line.
##
## Characters are built symmetric, so anything unpaired is either decoration or
## a mistake -- the template feet model carries a stray 1x1 column beside the
## legs. Either way it must not drag a limb bone sideways, and dropping it here
## is cheaper than asking every part to be spotless.
static func _mirrored_points(verts: PackedVector3Array, xf: Transform3D) -> PackedVector3Array:
	var present := {}
	var points := PackedVector3Array()
	for v in verts:
		var p: Vector3 = xf * v
		points.append(p)
		present[_mirror_key(p.x)] = true
	var out := PackedVector3Array()
	for p in points:
		if present.has(-_mirror_key(p.x)):
			out.append(p)
	return out if not out.is_empty() else points

static func _mirror_key(x: float) -> int:
	return roundi(x * 200.0)     # 5 mm buckets

static func _half_width(points: PackedVector3Array) -> float:
	var out := 0.0
	for p in points:
		out = maxf(out, absf(p.x))
	return out

## The offset that makes a coordinate set most mirror-symmetric.
##
## Parts are modelled wherever it was convenient in the Goxel grid, so they have
## to be centred before stacking. A bounding-box centre is thrown off by any
## stray voxel (the template feet model has a loose 1x1 column beside the
## legs); matching the art against its own mirror image is not.
static func _symmetry_centre(coords: PackedFloat32Array) -> float:
	if coords.is_empty():
		return 0.0
	var lo := coords[0]
	var hi := coords[0]
	var counts := {}
	for c in coords:
		lo = minf(lo, c)
		hi = maxf(hi, c)
		var key := roundi(c * 2.0)
		counts[key] = int(counts.get(key, 0)) + 1
	var middle := (lo + hi) * 0.5
	var search := (hi - lo) * 0.25
	var best := middle
	var best_score := -1.0
	# Candidates step by half a voxel, which is where a symmetry plane can fall.
	for step in range(-int(search * 2.0), int(search * 2.0) + 1):
		var candidate := middle + step * 0.5
		# Score by how much GEOMETRY pairs up, not how many distinct slices do:
		# a stray column has as many slices as a whole leg but a fraction of the
		# vertices, and only the weighted score tells the two apart.
		var mirror := roundi(candidate * 4.0)
		var score := 0.0
		for key: int in counts:
			score += minf(counts[key], counts.get(mirror - key, 0))
		# Ties go to the candidate nearest the bounding-box centre, so genuinely
		# asymmetric art still lands somewhere sensible.
		score -= absf(candidate - middle) * 0.001
		if score > best_score:
			best_score = score
			best = candidate
	return best


# ---------------------------------------------------------------------------
# skeleton reproportioning
# ---------------------------------------------------------------------------

## Moves every bone's rest position onto the voxel model's proportions, keeping
## each bone's rest ORIENTATION untouched so the clips' local rotations still
## mean what they meant on Rouge.
static func _reproportion(skeleton: Skeleton3D, layout: Dictionary) -> void:
	# Always fit from the ORIGINAL rig, never from the last fit, so re-rigging
	# the same skeleton (which the builder's preview does on every keystroke)
	# converges instead of compounding.
	var src: Dictionary = skeleton.get_meta(SOURCE_REST_META, {})
	if src.is_empty():
		for i in skeleton.get_bone_count():
			src[i] = skeleton.get_bone_global_rest(i)
		skeleton.set_meta(SOURCE_REST_META, src)

	var ref := _reference_landmarks(skeleton, src)
	# Kept so NpcVisual can rebase the clips' Hips position track: it was
	# authored around a pelvis at this height, and ours has just moved.
	layout["ref_hip_y"] = ref["hip_y"]
	# Height is remapped through the shared landmarks; width is a per-chain
	# factor, because arms, legs and torso widen by different amounts.
	var y_from: Array[float] = [0.0, ref["hip_y"], ref["arm_y"], ref["neck_y"], ref["head_y"], ref["crown"]]
	var y_to: Array[float] = [0.0, layout["hip_y"], layout["arm_y"], layout["neck_y"],
			layout["head_y"], layout["crown"]]
	var k := {
		"leg": _ratio(layout["leg_x"], ref["leg_x"]),
		"body": _ratio(layout["shoulder_x"], ref["shoulder_x"]),
	}
	# The arm is fitted at TWO points -- the shoulder and the hand -- where the
	# other chains get away with one scale. One factor can only ever put the hand
	# in the right place OR the shoulder, and the human rig it is scaled from has
	# its shoulders a quarter of the way out to its hands; a voxel character,
	# being nearly as wide as its arms are long, needs them most of the way out.
	# Scaled to land the hands, its shoulders end up buried in its chest.
	var arm_from: Array[float] = [0.0, ref["upper_arm_x"], ref["hand_x"]]
	var arm_to: Array[float] = [0.0, layout["arm_root_x"], layout["hand_x"]]
	var depth: float = _ratio(layout["crown"], ref["crown"])

	var fitted := {}
	for i in skeleton.get_bone_count():
		var g: Transform3D = src[i]
		var chain: String = _chain_of(skeleton, i)
		# Sign carries the side: the ladder is measured on the left and mirrored.
		var x: float = signf(g.origin.x) * _remap(absf(g.origin.x), arm_from, arm_to) \
				if chain == "arm" else g.origin.x * k[chain]
		fitted[i] = Transform3D(g.basis, Vector3(
				x,
				_remap(g.origin.y, y_from, y_to),
				g.origin.z * depth))
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		var local: Transform3D = fitted[i]
		if parent >= 0:
			local = (fitted[parent] as Transform3D).affine_inverse() * local
		skeleton.set_bone_rest(i, local)
	skeleton.reset_bone_poses()

static func _reference_landmarks(skeleton: Skeleton3D, src: Dictionary) -> Dictionary:
	var crown := 0.0
	for i in skeleton.get_bone_count():
		crown = maxf(crown, (src[i] as Transform3D).origin.y)
	return {
		"hip_y": _bone_y(skeleton, src, "Hips", 0.96),
		"arm_y": _bone_y(skeleton, src, "LeftUpperArm", 1.44),
		"neck_y": _bone_y(skeleton, src, "Neck", 1.53),
		"head_y": _bone_y(skeleton, src, "Head", 1.63),
		# The topmost bone is the skull base, not the crown; the mesh carries on
		# above it, so allow for that when scaling depth and total height.
		"crown": crown * 1.07,
		"hand_x": _bone_x(skeleton, src, "LeftHand", 0.74),
		"upper_arm_x": _bone_x(skeleton, src, "LeftUpperArm", 0.19),
		"leg_x": _bone_x(skeleton, src, "LeftUpperLeg", 0.10),
		"shoulder_x": _bone_x(skeleton, src, "LeftShoulder", 0.015),
	}

static func _bone_y(skeleton: Skeleton3D, src: Dictionary, bone: String, fallback: float) -> float:
	var i := skeleton.find_bone(bone)
	return (src[i] as Transform3D).origin.y if i >= 0 else fallback

static func _bone_x(skeleton: Skeleton3D, src: Dictionary, bone: String, fallback: float) -> float:
	var i := skeleton.find_bone(bone)
	return absf((src[i] as Transform3D).origin.x) if i >= 0 else fallback

static func _ratio(target: float, reference: float) -> float:
	return target / reference if absf(reference) > 0.0001 else 1.0

static func _remap(y: float, from: Array[float], to: Array[float]) -> float:
	for i in range(1, from.size()):
		if y <= from[i] or i == from.size() - 1:
			var span := from[i] - from[i - 1]
			var t := 0.0 if absf(span) < 0.0001 else (y - from[i - 1]) / span
			return to[i - 1] + (to[i] - to[i - 1]) * t
	return y

## Which limb a bone belongs to, so it widens with that limb. Covers the rig's
## non-humanoid extras too (UE Manny's twist and IK bones), which have no
## animation tracks but still have to end up somewhere sane.
static func _chain_of(skeleton: Skeleton3D, bone: int) -> String:
	var name := skeleton.get_bone_name(bone)
	if name.begins_with("ik_hand"):
		return "arm"
	if name.begins_with("ik_foot"):
		return "leg"
	var at := bone
	while at >= 0:
		var n := skeleton.get_bone_name(at)
		if n == "LeftShoulder" or n == "RightShoulder":
			return "arm"
		if n == "LeftUpperLeg" or n == "RightUpperLeg":
			return "leg"
		at = skeleton.get_bone_parent(at)
	return "body"


# ---------------------------------------------------------------------------
# skinning
# ---------------------------------------------------------------------------

## Bone index -> the [start, end] line segment a vertex measures its distance
## to. A bone's segment runs to its bindable children; a tip bone (hand, head,
## toes) gets a stub carrying on the way its parent pointed.
static func _segments(skeleton: Skeleton3D) -> Dictionary:
	var bindable := {}
	for set_name: String in BIND_SETS:
		for bone: String in BIND_SETS[set_name]:
			var i := skeleton.find_bone(bone)
			if i >= 0:
				bindable[i] = true

	var origin := {}
	for i: int in bindable:
		origin[i] = skeleton.get_bone_global_rest(i).origin

	var kids := {}
	for i: int in bindable:
		var at := skeleton.get_bone_parent(i)
		while at >= 0 and not bindable.has(at):
			at = skeleton.get_bone_parent(at)
		if at >= 0:
			if not kids.has(at):
				kids[at] = []
			kids[at].append(i)

	var out := {}
	for i: int in bindable:
		var a: Vector3 = origin[i]
		var b := a
		if kids.has(i):
			var sum := Vector3.ZERO
			for c: int in kids[i]:
				sum += origin[c] as Vector3
			b = sum / float(kids[i].size())
		else:
			var at := skeleton.get_bone_parent(i)
			while at >= 0 and not bindable.has(at):
				at = skeleton.get_bone_parent(at)
			var dir := (a - (origin[at] as Vector3)) if at >= 0 else Vector3.UP
			b = a + (dir.normalized() if dir.length() > 0.0001 else Vector3.UP) * 0.08
		out[i] = [a, b]
	return out

## Which voxels this part gets, on the grid every part shares: the bone each one
## binds to, where its centre sits, and what colour it is. Nothing is drawn here
## -- see `rig()` for why ownership has to be settled for the whole character
## before the first mesh is built.
static func _claim_cells(slot: String, data: Dictionary, spec: NpcPart, xf: Transform3D,
		skeleton: Skeleton3D, segments: Dictionary, voxel_scale: float,
		occupied: Dictionary) -> Dictionary:
	var candidates: Array[int] = []
	# Armor binds to the bones of the part it covers: a pauldron rides the arm
	# it is strapped to, and there is no such thing as an armor bone.
	for bone: String in BIND_SETS[NpcDefinition.covers(slot)]:
		var i := skeleton.find_bone(bone)
		if i >= 0 and segments.has(i):
			candidates.append(i)
	if candidates.is_empty():
		candidates.append(0)

	var src_verts: PackedVector3Array = data["verts"]
	var src_norms: PackedVector3Array = data["norms"]
	var entry: PackedInt32Array = data["entry"]
	var palette: PackedColorArray = data["palette"]

	var mine := {}
	for t in range(0, src_verts.size() - 2, 3):
		# One bone for the whole voxel, chosen from its centre rather than from
		# each face -- picking per vertex would tear voxels in half at the joints.
		var cell := xf * (_face_centre(src_verts, t) - src_norms[t] * 0.5)
		var key := _cell_key(cell, voxel_scale)
		if occupied.has(key) or mine.has(key):
			continue
		mine[key] = {
			"bone": _nearest_bone(cell, candidates, segments),
			"centre": cell,
			"colour": _colour(spec, palette, entry[t]),
		}
	for key: Vector3i in mine:
		occupied[key] = int((mine[key] as Dictionary)["bone"])
	return mine

static func _build_mesh(data: Dictionary, spec: NpcPart, xf: Transform3D,
		mine: Dictionary, occupied: Dictionary, voxel_scale: float) -> MeshInstance3D:
	var src_verts: PackedVector3Array = data["verts"]
	var src_norms: PackedVector3Array = data["norms"]
	var entry: PackedInt32Array = data["entry"]
	var palette: PackedColorArray = data["palette"]

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()

	for t in range(0, src_verts.size() - 2, 3):
		var key := _cell_key(xf * (_face_centre(src_verts, t) - src_norms[t] * 0.5),
				voxel_scale)
		if not mine.has(key):
			continue
		var bone := int((mine[key] as Dictionary)["bone"])
		for c in 3:
			var src := t + c
			verts.append(xf * src_verts[src])
			norms.append((xf.basis * src_norms[src]).normalized())
			cols.append(_colour(spec, palette, entry[src]))
			_bind(bones, weights, bone)

	_add_seam_caps(mine, occupied, xf.basis.get_scale().x, voxel_scale,
			_winding_sign(data), verts, norms, cols, bones, weights)
	if verts.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.metallic = 0.0
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi

## The centre of the square face a triangle is half of.
##
## NOT the triangle's own centroid, which sits a sixth of a voxel off it: a
## voxel face is two triangles and each one leans towards its own three corners.
## That was close enough to identify which voxel a face belongs to (the cell
## grid is far coarser than a sixth) and nowhere near close enough to BUILD on,
## which is what the seam caps do -- they were landing a sixth of a voxel proud
## of the model and pushing its bounding box out with them. Taking the corners'
## own min and max recovers the square exactly, because either triangle of a
## square still spans the whole of it.
static func _face_centre(verts: PackedVector3Array, t: int) -> Vector3:
	var lo := verts[t].min(verts[t + 1]).min(verts[t + 2])
	var hi := verts[t].max(verts[t + 1]).max(verts[t + 2])
	return (lo + hi) * 0.5

## One vertex bound whole to one bone. Rigid on purpose -- it is what keeps the
## blocky look, pieces rotating about the joints instead of bending like skin.
static func _bind(bones: PackedInt32Array, weights: PackedFloat32Array, bone: int) -> void:
	bones.append(bone)
	weights.append(1.0)
	for _i in 3:
		bones.append(0)
		weights.append(0.0)

## Which way round Godot wants a front face, read off the art rather than
## assumed: the exporter already wound its own triangles correctly, so whether
## (v1-v0)x(v2-v0) runs with the face normal or against it is a fact to look up
## rather than a convention this file can get wrong. The caps below are the only
## geometry the rig invents, and a cap wound backwards is invisible -- which
## looks exactly like not having written it.
static func _winding_sign(data: Dictionary) -> float:
	var verts: PackedVector3Array = data["verts"]
	var norms: PackedVector3Array = data["norms"]
	for t in range(0, verts.size() - 2, 3):
		var facing := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).dot(norms[t])
		if absf(facing) > 0.0001:
			return signf(facing)
	return 1.0

## Puts back the faces voxel art does not carry.
##
## Goxel exports only the OUTSIDE of a model: where two voxels touch there is no
## geometry at all, and nothing needs any while the pair cannot move apart.
## Rigid skinning moves them apart. A voxel bound to Chest and the one beside it
## bound to Hips separate the moment the spine bends, and with no face on either
## side of the join you are looking straight through the character -- that is
## the row of dark wedges that opened across the chest and down the arms of
## every built NPC as soon as anything animated, and it is worse in armor, which
## sits a voxel further out from the bone and so swings further.
##
## So every join between two voxels on DIFFERENT bones gets its missing face
## back, one square per side, each bound to its own voxel's bone. At rest the
## pair sits back to back on the same plane facing opposite ways, so each is the
## other's backface and neither is drawn; the moment the joint opens, both sides
## show solid colour instead of the inside of the model.
##
## Joins WITHIN a bone are left alone -- those two voxels can never part, and
## capping them would be geometry that is never seen. Neighbours across a PART
## boundary count, which is what closes the seam under the chin.
static func _add_seam_caps(mine: Dictionary, occupied: Dictionary, voxel: float,
		voxel_scale: float, winding: float, verts: PackedVector3Array,
		norms: PackedVector3Array, cols: PackedColorArray, bones: PackedInt32Array,
		weights: PackedFloat32Array) -> void:
	if voxel <= 0.0:
		return
	var half := voxel * 0.5
	for key: Vector3i in mine:
		var cell: Dictionary = mine[key]
		var at: Vector3 = cell["centre"]
		var bone := int(cell["bone"])
		for axis in 3:
			for step in [-1.0, 1.0]:
				var dir := Vector3.ZERO
				dir[axis] = step
				var beside := _cell_key(at + dir * voxel, voxel_scale)
				if not occupied.has(beside) or int(occupied[beside]) == bone:
					continue
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = half
				var w := Vector3.ZERO
				w[(axis + 2) % 3] = half
				var face := at + dir * half
				var quad: Array[Vector3] = [
						face - u - w, face + u - w, face + u + w, face - u + w]
				# u x w is +axis, so that order runs anticlockwise seen from the
				# +axis side; flip it to face `dir`, then again if the art says
				# Godot wants the other winding.
				if (step > 0.0) != (winding < 0.0):
					quad.reverse()
				for corner in [0, 1, 2, 0, 2, 3]:
					verts.append(quad[corner])
					norms.append(dir)
					cols.append(cell["colour"])
					_bind(bones, weights, bone)

static func _colour(spec: NpcPart, palette: PackedColorArray, index: int) -> Color:
	var base := Color.WHITE
	if spec != null and index < spec.colors.size():
		base = spec.colors[index]
	elif index < palette.size():
		base = palette[index]
	return base * spec.tint if spec != null else base

## Identifies the voxel a point sits in, on a grid shared by every part. Half a
## voxel of resolution, so a part deliberately offset by half a step is treated
## as its own geometry rather than a duplicate.
static func _cell_key(point: Vector3, voxel_scale: float) -> Vector3i:
	if voxel_scale <= 0.0:
		return Vector3i.ZERO
	return Vector3i((point / voxel_scale * 2.0).round())

static func _nearest_bone(point: Vector3, candidates: Array[int], segments: Dictionary) -> int:
	var best := candidates[0]
	var best_d := INF
	for i in candidates:
		var seg: Array = segments[i]
		var d := point.distance_squared_to(Geometry3D.get_closest_point_to_segment(
				point, seg[0], seg[1]))
		if d < best_d:
			best_d = d
			best = i
	return best
