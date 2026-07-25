@tool
class_name CloudScrub
extends RefCounted
## Core cloud-removal image processing, separate from the editor plugin so it
## can also be run headless/scripted.

const MAX_WIDTH := 2048  # cap panorama size so processing stays fast

## Returns a copy of the panorama with clouds blended into the sky gradient.
## Clouds are detected as bright, low-saturation pixels; each one is replaced
## with its image row's baseline color (the average of the row's saturated,
## non-cloud pixels), which preserves the vertical sky/sea gradient.
static func remove_clouds(src: Image) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	if img.get_width() > MAX_WIDTH:
		var scale := float(MAX_WIDTH) / img.get_width()
		img.resize(MAX_WIDTH, int(img.get_height() * scale), Image.INTERPOLATE_LANCZOS)

	var w := img.get_width()
	var h := img.get_height()

	# pass 1: per-row baseline color from clearly-colored (non-cloud) pixels
	var row_color: Array[Color] = []
	var row_valid: Array[bool] = []
	for y in h:
		var sum := Vector3.ZERO
		var count := 0
		for x in w:
			var c := img.get_pixel(x, y)
			if c.s >= 0.28 and c.v >= 0.15:
				sum += Vector3(c.r, c.g, c.b)
				count += 1
		if count > w / 50:
			sum /= count
			row_color.append(Color(sum.x, sum.y, sum.z))
			row_valid.append(true)
		else:
			row_color.append(Color.BLACK)
			row_valid.append(false)

	_fill_missing_rows(row_color, row_valid)
	_smooth_rows(row_color)

	# pass 2 (x2): blend cloudy pixels toward the row baseline; the second
	# iteration catches half-blended haze left by the first
	for pass_i in 2:
		for y in h:
			var base := row_color[y]
			for x in w:
				var c := img.get_pixel(x, y)
				var brightness: float = clampf((c.v - 0.4) / 0.2, 0.0, 1.0)
				var desaturation: float = 1.0 - clampf(c.s / 0.4, 0.0, 1.0)
				var cloudiness: float = clampf(brightness * desaturation * 1.6, 0.0, 1.0)
				if cloudiness > 0.01:
					img.set_pixel(x, y, c.lerp(base, cloudiness))

	# pass 3: flatten leftover ghost shapes — anything still far from its
	# row's baseline (cloud shadows, blue-tinted remnants) gets pulled in
	for y in h:
		var base := row_color[y]
		for x in w:
			var c := img.get_pixel(x, y)
			var dist := Vector3(c.r - base.r, c.g - base.g, c.b - base.b).length()
			var f: float = clampf((dist - 0.05) * 6.0, 0.0, 0.8)
			if f > 0.01:
				img.set_pixel(x, y, c.lerp(base, f))
	return img

## Rows that were fully covered by cloud borrow the nearest clear rows.
static func _fill_missing_rows(colors: Array[Color], valid: Array[bool]) -> void:
	var h := colors.size()
	var prev := -1
	for y in h:
		if valid[y]:
			if prev == -1:
				for k in y:
					colors[k] = colors[y]
			elif prev < y - 1:
				for k in range(prev + 1, y):
					colors[k] = colors[prev].lerp(colors[y], float(k - prev) / float(y - prev))
			prev = y
	if prev == -1:
		return  # nothing valid at all; leave as-is
	for k in range(prev + 1, h):
		colors[k] = colors[prev]

static func _smooth_rows(colors: Array[Color]) -> void:
	var h := colors.size()
	var smoothed := colors.duplicate()
	var radius := maxi(2, h / 100)
	for y in h:
		var sum := Vector3.ZERO
		var n := 0
		for k in range(maxi(0, y - radius), mini(h, y + radius + 1)):
			sum += Vector3(colors[k].r, colors[k].g, colors[k].b)
			n += 1
		sum /= n
		smoothed[y] = Color(sum.x, sum.y, sum.z)
	for y in h:
		colors[y] = smoothed[y]
