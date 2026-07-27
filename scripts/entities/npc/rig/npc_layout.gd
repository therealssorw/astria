class_name NpcLayout
## WHERE EACH PART SITS, and the landmarks the skeleton is then fitted to. Split
## out of NpcRig because it is pure measurement: it reads the art's own bounding
## boxes and symmetry and answers with transforms and heights, without touching
## a bone or building a triangle.
##
## Nothing here is hand-placed or configured. A part is centred by matching it
## against its own mirror image, the parts stack feet-body-head, the arms are
## anchored to the TORSO's frame, and armor takes the centre of whatever it
## covers. That is why a new model dropped into the library needs no metadata.

## Goxel models are built facing +X; the game's characters face +Z.
const MODEL_YAW := -PI / 2.0

static func build(def: NpcDefinition, parts: Dictionary) -> Dictionary:
	var metrics := _metrics(def, parts)
	var feet_h: float = metrics["feet"]["size"].y if metrics.has("feet") else 0.0
	var body_h: float = metrics["body"]["size"].y if metrics.has("body") else 0.0
	var head_h: float = metrics["head"]["size"].y if metrics.has("head") else 0.0
	var voxel_scale: float = def.height / maxf(feet_h + body_h + head_h, 0.001)

	var layout := {
		"voxel_scale": voxel_scale,
		"part_xf": _part_transforms(def, parts, metrics, voxel_scale, feet_h, body_h),
		"crown": def.height,
		"hip_y": feet_h * voxel_scale,
		"neck_y": (feet_h + body_h) * voxel_scale,
		"head_y": (feet_h + body_h) * voxel_scale + head_h * voxel_scale * 0.25,
		"arm_y": lerpf(feet_h * voxel_scale, (feet_h + body_h) * voxel_scale, 0.75),
		"hand_x": def.height * 0.28,
		"arm_thick": def.height * 0.08,
		"leg_x": def.height * 0.06,
		"shoulder_x": def.height * 0.09,
	}
	var part_xf: Dictionary = layout["part_xf"]
	_measure_arms(layout, parts, part_xf)
	_measure_legs(layout, parts, part_xf)
	_measure_shoulder(layout, parts, part_xf)
	# The Y landmarks feed a piecewise remap, which needs them strictly rising.
	var floor_y := 0.0
	for key in ["hip_y", "arm_y", "neck_y", "head_y", "crown"]:
		floor_y = maxf(floor_y + 0.01, layout[key])
		layout[key] = floor_y
	return layout

## Each part's own centre and scaled size, before anything is stacked.
static func _metrics(def: NpcDefinition, parts: Dictionary) -> Dictionary:
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
			"centre": Vector3((lo.x + hi.x) * 0.5, lo.y, symmetry_centre(zs)),
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
	return metrics

static func _part_transforms(def: NpcDefinition, parts: Dictionary, metrics: Dictionary,
		voxel_scale: float, feet_h: float, body_h: float) -> Dictionary:
	var yaw := Basis(Vector3.UP, MODEL_YAW)
	# Arms share the body's base: the T-bar model overlaps the torso instead of
	# stacking on it. Armor stands on the same step as what it covers -- and note
	# that NOTHING on the armor layer fed feet_h/body_h/head_h, which is what
	# keeps a helmet from making the character two voxels taller.
	var stack := {"feet": 0.0, "body": feet_h, "arms": feet_h, "head": feet_h + body_h}
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		stack[slot] = stack[NpcDefinition.covers(slot)]

	var part_xf := {}
	for slot: String in parts:
		var spec: NpcPart = def.get_part(slot)
		# An armor piece's own scale is RELATIVE to the part it covers, so
		# scaling a body carries its plate with it instead of leaving the suit
		# behind at its original size.
		var part_scale := spec.scale
		if NpcDefinition.is_armor(slot):
			var under: NpcPart = def.get_part(NpcDefinition.covers(slot))
			if under != null:
				part_scale *= under.scale
		var xf := Transform3D(Basis.IDENTITY, -(metrics[slot]["centre"] as Vector3))
		xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * part_scale), Vector3.ZERO) * xf
		xf = Transform3D(yaw, Vector3.ZERO) * xf
		xf = Transform3D(Basis.IDENTITY, spec.offset + Vector3.UP * stack[slot]) * xf
		part_xf[slot] = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * voxel_scale), Vector3.ZERO) * xf
	return part_xf

## Arm height, reach and thickness, read off the outer quarter of the arms model
## -- the part that actually sticks out past the torso.
##
## Only the outer quarter, and that matters for the thickness: an arms model
## carries a reference copy of the torso through its middle, so measured whole
## it is as thick as a chest.
static func _measure_arms(layout: Dictionary, parts: Dictionary, part_xf: Dictionary) -> void:
	if not parts.has("arms"):
		return
	var points := mirrored_points(parts["arms"]["verts"], part_xf["arms"])
	var reach := half_width(points)
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
	var points := mirrored_points(parts["feet"]["verts"], part_xf["feet"])
	var span := half_width(points)
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

## Where the arm hangs FROM: half the arm's own thickness outside the torso's
## edge, because that is the pivot an arm can be rotated down to the character's
## side about and land flush against the body rather than inside it — swung a
## quarter turn, a bar pivoted at `p` sweeps out [p - thickness/2, p +
## thickness/2].
##
## Getting this from the ART rather than from the human rig's proportions is the
## whole point. A voxel character is a third as wide as it is tall and the human
## it borrows its skeleton from is not, so a shoulder placed at the human's
## shoulder-to-hand ratio lands INSIDE the chest — and an arm pivoting in the
## middle of the chest spends every clip ploughing through it.
static func _measure_shoulder(layout: Dictionary, parts: Dictionary, part_xf: Dictionary) -> void:
	var torso_x: float = layout["hand_x"] * 0.35
	if parts.has("body"):
		torso_x = maxf(half_width(mirrored_points(parts["body"]["verts"], part_xf["body"])), 0.01)
		layout["shoulder_x"] = maxf(torso_x * 0.5, 0.01)
	# Never past the hand: a character with stubby arms on a broad body would
	# otherwise put the shoulder outboard of its own fist and turn the arm inside
	# out.
	layout["arm_root_x"] = minf(torso_x + layout["arm_thick"] * 0.5, layout["hand_x"] * 0.75)

## The part's vertices in character space, keeping only those with a mirror twin
## across the centre line.
##
## Characters are built symmetric, so anything unpaired is either decoration or
## a mistake -- the template feet model carries a stray 1x1 column beside the
## legs. Either way it must not drag a limb bone sideways, and dropping it here
## is cheaper than asking every part to be spotless.
static func mirrored_points(verts: PackedVector3Array, xf: Transform3D) -> PackedVector3Array:
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

static func half_width(points: PackedVector3Array) -> float:
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
static func symmetry_centre(coords: PackedFloat32Array) -> float:
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
