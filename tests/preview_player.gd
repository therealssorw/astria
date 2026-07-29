extends Node3D
## Look-at aid for the player's body: EVERY frame of the idle clip as a contact
## sheet, from two angles, plus a per-frame hole count printed beside it.
##   godot --path . res://tests/preview_player.tscn
## Needs a real window — do NOT pass --headless. Sheets land in
## user://player_preview, one row per angle plus `idle_all.png`.
##
## A strip rather than a still, and that is the whole point: every wrong-looking
## body in this project's history looked FINE in the one frame that got
## screenshotted. A shoulder that opens up only at the top of the arm swing, a
## bridge that juts out at full extension, a hand that separates halfway through
## -- each is invisible in a still and obvious in a row. Judge the rig here.
##
## Angles are chosen for the joints that actually come apart: three-quarter front
## shows the shoulder tops and the chest seam, side shows the elbow and the hip.

const OUT_DIR := "user://player_preview"
const PLAYER := preload("res://scenes/player.tscn")
## Frames rendered across the idle loop. The numeric sweep below walks the clip
## far more finely than this -- these are the ones a human looks at.
const FRAMES := 8
## Steps in the numeric sweep: EVERY frame of the clip at 30fps, so a joint that
## only opens for a moment between two rendered cells is still caught.
const SWEEP := 30.0
## Each frame shrunk to this wide -- a strip of full-size shots is unopenable.
const CELL_W := 420
## [label, direction the camera looks FROM, point it centres on, ortho height].
## Orthographic and sized in METRES, not a hand-placed perspective camera: the
## joint being judged is 20 cm of a 1.85 m character, and every guessed camera
## position in this file's history framed a lot of ground and a tiny person.
const ANGLES := [
	["shoulders", Vector3(0.75, 0.35, 1.0), Vector3(0.0, 1.05, 0.0), 0.85],
	# Straight down onto ONE shoulder: the only angle that shows the TOPS of the
	# arms, zoomed to the joint itself because a whole-body overhead is 400 px of
	# mostly head.
	["overhead", Vector3(0.10, 1.0, 0.10), Vector3(0.33, 1.10, 0.0), 0.45],
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Net.players[1] = {"name": "Tester", "kills": 0, "deaths": 0}

	var pawn: Node3D = PLAYER.instantiate()
	pawn.name = "1"
	pawn.peer_id = 1
	pawn.username = "Tester"
	$Players.add_child(pawn)
	pawn.global_position = Vector3.ZERO
	pawn.set_physics_process(false)
	for _i in 6:
		await get_tree().process_frame

	var visual: HumanoidVisual = pawn.body_visual
	var cam := $Camera3D as Camera3D
	cam.current = true

	# A LOUD background and no ground under the character, so a hole is a patch of
	# magenta and cannot be mistaken for shadow. Every "is that a gap or just dark
	# shading?" round trip in this file came from judging holes against scenery.
	$Ground.visible = false
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(1.0, 0.0, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.4
	env.environment = e
	add_child(env)

	# Drive the idle exactly as the pawn does, then freeze and SEEK: counting
	# frame-sized deltas measures frames, not time, and an empty windowed scene
	# runs well past 60 fps.
	visual.tick(1.0 / 60.0, "idle", 0.0, 0.0)
	await get_tree().process_frame
	var length: float = visual.clip_lengths.get("idle", 1.0)
	visual.anim_player.pause()
	print("PREVIEW idle=%.2fs over %d frames" % [length, FRAMES])

	var rows: Array[Image] = []
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	for angle in ANGLES:
		cam.size = angle[3]
		cam.look_at_from_position((angle[2] as Vector3) + (angle[1] as Vector3).normalized() * 3.0,
				angle[2], Vector3.UP)
		var strip: Image = null
		for i in FRAMES:
			var t := length * float(i) / float(FRAMES)
			visual.anim_player.seek(t, true)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var shot := get_viewport().get_texture().get_image()
			var cell_h := int(shot.get_height() * CELL_W / float(shot.get_width()))
			shot.resize(CELL_W, cell_h, Image.INTERPOLATE_LANCZOS)
			if strip == null:
				strip = Image.create_empty(CELL_W * FRAMES, cell_h, false, shot.get_format())
			strip.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(CELL_W * i, 0))
			print("  %-10s frame %d/%d t=%.2fs  shoulder opening=%.4fm"
					% [angle[0], i + 1, FRAMES, t, _shoulder_gap(visual)])
		strip.save_png("%s/idle_%s.png" % [OUT_DIR, String(angle[0]).replace("-", "_")])
		rows.append(strip)

	var cell_h := rows[0].get_height()
	var all := Image.create_empty(rows[0].get_width(), cell_h * rows.size(), false,
			rows[0].get_format())
	for i in rows.size():
		all.blit_rect(rows[i], Rect2i(Vector2i.ZERO, rows[i].get_size()), Vector2i(0, cell_h * i))
	all.save_png("%s/idle_all.png" % OUT_DIR)

	# EVERY frame, not just the eight that got drawn: the worst moment of a clip
	# rarely lands on a cell boundary, and a shoulder that only opens between two
	# rendered frames is exactly the bug a contact sheet misses.
	var worst := 0.0
	var worst_t := 0.0
	var steps := int(length * SWEEP)
	for i in steps + 1:
		var t := length * float(i) / float(steps)
		visual.anim_player.seek(t, true)
		await get_tree().process_frame
		var gap := _shoulder_gap(visual)
		if gap > worst:
			worst = gap
			worst_t = t
	print("SWEEP %d frames of idle: worst shoulder opening=%.4fm at t=%.2fs"
			% [steps + 1, worst, worst_t])
	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()

## The actual HOLE at the shoulder this frame, in metres: how far the nearest bit
## of arm has pulled away from the nearest bit of torso.
##
## Measured between the two posed meshes rather than off the joint, because how
## far a bone travels is not the question -- an arm can swing a long way and stay
## flush against the body, and it is the daylight between the two surfaces that a
## player sees. 0 means they still touch.
func _shoulder_gap(visual: HumanoidVisual) -> float:
	var skel := visual.skeleton
	var arms := _posed(skel, "Arms", ["LeftUpperArm"])
	var body := _posed(skel, "Body", ["Chest", "Hips"])
	if arms.is_empty() or body.is_empty():
		return 0.0
	var best := INF
	for a in arms:
		for b in body:
			best = minf(best, a.distance_squared_to(b))
	return sqrt(best)

## Posed positions of one mesh's vertices, keeping only those riding `bones`.
## Thinned to every 6th vertex: this runs on hundreds of frames and the nearest
## approach of two voxel slabs does not need every corner to be found.
func _posed(skel: Skeleton3D, mesh_name: String, bones: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi := skel.get_node_or_null(NodePath(mesh_name)) as MeshInstance3D
	if mi == null:
		return out
	var wanted := {}
	for n: String in bones:
		var i := skel.find_bone(n)
		if i >= 0:
			wanted[i] = true
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var vbones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	for i in range(0, verts.size(), 6):
		var b := vbones[i * 4]
		if wanted.has(b):
			out.append(skel.get_bone_global_pose(b)
					* (skel.get_bone_global_rest(b).affine_inverse() * verts[i]))
	return out
