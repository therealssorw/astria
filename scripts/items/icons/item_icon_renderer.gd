extends Node
## The pictures of items the bag, the hotbar, the shop rows and the cheat menu
## draw. Autoload `ItemIcons`; everything asks for one through `ItemDb.icon()`.
##
## AN ICON IS A PHOTOGRAPH OF THE ITEM'S OWN FILE, taken when the game starts.
## The iron sword's picture is tony_sword.fbx at the size and tint that item
## wears; the copper helmet's is Armor1's head model in the colours
## copper_armor.tres paints it. Nothing is drawn by hand, so an item is
## described in exactly one place — repaint a suit in the Items tab, fatten a
## blade in ItemDb, and every screen showing it follows on the next run instead
## of quietly keeping a picture of what it used to look like.
##
## The shot: an ORTHOGONAL camera (a picture of a thing, not a scene it stands
## in — perspective on a 64-pixel icon only skews it), from three quarters on
## and slightly above, framed on the art's own bounding box so a boot and a
## greatsword both fill the frame. Anything much taller than it is wide is laid
## over diagonally, which is the difference between a sword icon and a thin
## vertical line with air either side of it. The background is transparent: the
## slot's own frame is behind it.
##
## It renders one item per frame into a single small viewport and keeps the
## result, so the cost is one 256px render each, once. Every catalogue item is
## queued at startup so the first bag opened already has its pictures; anything
## asked for early gets its (blank) texture straight away and the art appears in
## it a frame or two later — the texture object never changes, so whatever is
## already showing it redraws itself.
##
## Headless runs have nothing to draw into and nothing to look at it, so it
## renders nothing at all there and every screen falls back to item names.
## `ItemDb.art_source()` is what a test asks instead — it says whether an item
## HAS a picture without needing one taken.

## What the viewport draws at, and what gets kept. Rendered large and shrunk
## with a filter rather than rendered at 64: it is much cheaper than MSAA and
## the voxel edges come out cleaner for it.
const SHOT_SIZE := 256
const ICON_SIZE := 64

## Three quarters on and a little above, the way something set down on a table
## is looked at. Flat on, a plate reads as a coloured rectangle.
const VIEW_YAW_DEG := -35.0
const VIEW_PITCH_DEG := -22.0

## Air around the art, so nothing touches the edge of its slot.
const MARGIN := 1.1

## How much taller than wide a thing has to be before it is laid over
## diagonally, and how far it is laid.
const LEAN_RATIO := 1.6
const LEAN_DEG := 38.0

var _icons := {}
var _queue: PackedStringArray = []
var _running := false

var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D

func _ready() -> void:
	if _no_display():
		return
	_build_studio()
	# Every item, up front: a bag opened in the first second of play should have
	# its pictures in it, not fill itself in while being looked at.
	for id: String in ItemDb.ITEMS:
		icon(id)

## The item's picture, or null when it has no art — callers draw the item's
## name instead, so an item without a model is never a blank slot.
func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	if ItemDb.art_source(id) == "":
		return null
	if _no_display():
		return null
	# Handed back empty and filled in when its turn comes. It is the SAME
	# texture either way, so a slot drawn before the shot was taken picks the
	# art up by itself.
	var tex := ImageTexture.create_from_image(
			Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	_icons[id] = tex
	_queue.append(id)
	_pump()
	return tex

func _no_display() -> bool:
	return DisplayServer.get_name() == "headless"


# ---------------------------------------------------------------------------
# the studio
# ---------------------------------------------------------------------------

func _build_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SHOT_SIZE, SHOT_SIZE)
	# Its own world, or every icon would be taken inside the island — the game's
	# sky, its fog and whatever happens to be standing behind the camera.
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_viewport)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	# CLEAR_COLOR and not a background of its own: it is what leaves the
	# transparency alone, so an icon is the item and nothing else.
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.72)
	e.ambient_light_energy = 1.0
	env.environment = e
	_viewport.add_child(env)

	# Over the camera's left shoulder: the lit face is the one being looked at,
	# and the shadowed sides are what make a voxel block read as a solid.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, VIEW_YAW_DEG + 25.0, 0.0)
	key.light_energy = 1.5
	_viewport.add_child(key)

	_stage = Node3D.new()
	_viewport.add_child(_stage)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_viewport.add_child(_camera)

func _pump() -> void:
	if _running:
		return
	_running = true
	_run()

func _run() -> void:
	while not _queue.is_empty():
		var id := _queue[0]
		_queue.remove_at(0)
		await _shoot(id)
	# Nothing left standing in the studio between runs: the last item shot would
	# otherwise sit there for the rest of the session.
	_clear_stage()
	_running = false

func _shoot(id: String) -> void:
	var model := ItemDb.build_model(id)
	if model == null:
		return
	_clear_stage()
	_stage.add_child(model)
	_frame()

	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	if img == null or img.is_empty():
		push_warning("ItemIcons: nothing came back from the viewport for '%s'" % id)
		return
	img.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	(_icons[id] as ImageTexture).set_image(img)

## free() and not queue_free(): a queued free happens at the END of this frame,
## which is the frame the next item is photographed in — the one just shot would
## be standing in the picture behind it.
func _clear_stage() -> void:
	for old in _stage.get_children():
		_stage.remove_child(old)
		old.free()

## Point the camera at whatever is on the stage and open it just wide enough to
## hold it. Everything is measured off the art's own bounding box, so nothing
## has to be told how big it is: the same code frames a boot and a greatsword.
func _frame() -> void:
	# Stand it up first. The stage is reused for every shot, and measuring the
	# next item while the last one's lean is still on it decides the lean off the
	# wrong shape — which is how two of three identical swords came out at
	# different angles.
	_stage.rotation = Vector3.ZERO
	var box := _bounds()
	if box.size.length() <= 0.0:
		return
	# Long thin things are laid over so they run corner to corner. A sword stood
	# upright in a square icon is a line with two empty margins beside it, and
	# framing it to fill the height makes it too thin to recognise.
	var flat := Vector2(box.size.x, box.size.z).length()
	if flat > 0.0 and box.size.y / flat >= LEAN_RATIO:
		_stage.rotation.z = deg_to_rad(LEAN_DEG)
		box = _bounds()

	var aim := Basis.from_euler(Vector3(
			deg_to_rad(VIEW_PITCH_DEG), deg_to_rad(VIEW_YAW_DEG), 0.0))
	var radius := box.size.length() * 0.5
	# Ortho, so the distance changes nothing about the picture — it only has to
	# clear the art, and the near/far planes have to hold all of it.
	_camera.transform = Transform3D(aim, box.get_center() + aim.z * radius * 2.0)
	_camera.near = maxf(radius * 0.01, 0.001)
	_camera.far = radius * 4.0 + 1.0

	# Tight to the corners as the camera sees them, not to the box's own size:
	# turned three quarters on, a wide flat thing presents its diagonal.
	var into_camera := _camera.transform.affine_inverse()
	var half := Vector2.ZERO
	for i in 8:
		var corner := into_camera * box.get_endpoint(i)
		half = half.max(Vector2(absf(corner.x), absf(corner.y)))
	_camera.size = maxf(half.x, half.y) * 2.0 * MARGIN

## What is on the stage, in the stage's own space. Read off the drawn meshes
## rather than any node's transform: a model's root is often nowhere near it.
func _bounds() -> AABB:
	var out := AABB()
	var first := true
	for node in _stage.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var box := vi.global_transform * vi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
