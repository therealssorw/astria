class_name NpcPartLoader
## Turning a part MODEL into plain arrays, and working out what colours it was
## painted in. Split out of NpcRig because it is the only thing in the rig that
## touches a file: everything downstream works on the dictionary this returns.
##
## The flattened form is the part in its own voxel space (Y up, one unit per
## voxel — the Goxel exporter's Z-up -> Y-up root node is baked in here), with
## triangles UNWELDED, because rigid skinning picks a bone per voxel and a
## shared corner would have to choose one of them.

## Flattened part models, keyed by path. Loading one means instancing a scene
## and walking its surfaces, and the builder re-rigs constantly while you drag a
## colour around; `clear_cache()` drops it when the art changes on disk.
static var _cache := {}

static func clear_cache() -> void:
	_cache.clear()

## -> {"verts", "norms", "entry", "palette"}, or {} when there is nothing to
## load. `entry[i]` is which palette slot vertex i wears.
static func load_part(model_path: String) -> Dictionary:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return {}
	if _cache.has(model_path):
		return _cache[model_path]
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
	_cache[model_path] = {
		"verts": verts, "norms": norms,
		"entry": entry, "palette": palette["colors"],
	}
	return _cache[model_path]

## The model's own colours, in the order an NpcPart.colors override maps onto.
static func palette_of(model_path: String) -> PackedColorArray:
	return load_part(model_path).get("palette", PackedColorArray()) as PackedColorArray

## What colour a vertex actually comes out: the part's own override for that
## palette entry if it has one, the model's own colour otherwise, times the
## per-part tint. ONE place, shared by the rigged mesh and the icon preview, so
## a plate in the world and the same plate in the bag can never disagree.
static func colour(spec: NpcPart, palette: PackedColorArray, index: int) -> Color:
	var base := Color.WHITE
	if spec != null and index < spec.colors.size():
		base = spec.colors[index]
	elif index < palette.size():
		base = palette[index]
	return base * spec.tint if spec != null else base

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
	if img.is_compressed() and img.decompress() != OK:
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
