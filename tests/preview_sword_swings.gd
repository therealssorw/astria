extends Node3D
## Look-at aid, not a pass/fail test: every sword swing laid out as a CONTACT
## SHEET — eight frames of the clip in one image, left to right — with the blade
## actually in the hand.
##   godot --path . res://tests/preview_sword_swings.tscn
## Needs a real window — do NOT pass --headless. Sheets land in
## user://sword_preview, one per swing plus `all_swings.png`.
##
## What it is for: the swings are cut out of a mocap pack's combos and
## retargeted onto a reproportioned voxel skeleton, so whether a cut reads as a
## CUT is not something any assertion about clip lengths can tell you. One frame
## cannot tell you either, which is why this is a strip: a blade that is up at
## 30% and up again at 70% is a fighter waving a sword about, and that looked
## perfectly good as two separate stills.
##
## The strip is also the only way to see the SHAPE of a swing — where the blade
## starts, which way it travels, whether it finishes somewhere a player can see.

const OUT_DIR := "user://sword_preview"
const PLAYER := preload("res://scenes/player.tscn")
const ITEM := "iron_sword"
## Sword clip per swing, in the order the combo chains them.
const SWINGS := ["sword_light_0", "sword_light_1", "sword_light_2", "sword_heavy"]
## Frames per strip, evenly spaced across the clip.
const FRAMES := 8
## Each frame is shrunk to this wide for the sheet; a strip of full-size shots
## is 13000 pixels across and nothing will open it.
const CELL_W := 320

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

	var cam := $Camera3D as Camera3D
	# Close in on the fighter: a cell of the strip is 320 px wide, so a shot
	# framed for a full window leaves a character too small to read a blade on.
	cam.look_at_from_position(Vector3(1.5, 1.3, 1.9), Vector3(0.0, 0.95, 0.0))
	cam.current = true

	var visual: HumanoidVisual = pawn.body_visual
	visual.set_held_item(ITEM)
	await get_tree().process_frame

	var sheets: Array[Image] = []
	for key: String in SWINGS:
		var length := visual.play_scripted(key)
		print("PREVIEW %s=%.2fs" % [key, length])
		# SEEKED rather than stepped: counting frame-sized deltas measures frames,
		# not time, and a windowed run of an empty scene runs well past 60 fps.
		visual.anim_player.pause()
		var strip: Image = null
		for i in FRAMES:
			visual.anim_player.seek(length * float(i) / float(FRAMES - 1), true)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var shot := get_viewport().get_texture().get_image()
			var cell_h := int(shot.get_height() * CELL_W / float(shot.get_width()))
			shot.resize(CELL_W, cell_h, Image.INTERPOLATE_LANCZOS)
			if strip == null:
				strip = Image.create_empty(CELL_W * FRAMES, cell_h, false, shot.get_format())
			strip.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()),
					Vector2i(CELL_W * i, 0))
		strip.save_png("%s/%s.png" % [OUT_DIR, key])
		sheets.append(strip)
		visual.stop_scripted()

	# All four stacked, so the chain can be read as one picture.
	var cell_h := sheets[0].get_height()
	var all := Image.create_empty(sheets[0].get_width(), cell_h * sheets.size(),
			false, sheets[0].get_format())
	for i in sheets.size():
		all.blit_rect(sheets[i], Rect2i(Vector2i.ZERO, sheets[i].get_size()),
				Vector2i(0, cell_h * i))
	all.save_png("%s/all_swings.png" % OUT_DIR)

	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()
