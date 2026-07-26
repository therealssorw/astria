extends Node3D
## Look-at aid, not a pass/fail test: each sword swing at its midpoint, with the
## blade actually in the hand.
##   godot --path . res://tests/preview_sword_swings.tscn
## Needs a real window — do NOT pass --headless. Shots land in
## user://sword_preview.
##
## What it is for: the swings come off a UE-mannequin pack and are retargeted
## onto a reproportioned voxel skeleton, so whether the cut reads as a cut — and
## whether the sword is still in the hand while it does — is not something any
## assertion about clip lengths can tell you.

const OUT_DIR := "user://sword_preview"
const PLAYER := preload("res://scenes/player.tscn")
const ITEM := "iron_sword"
## Sword clip per swing, in the order the combo chains them.
const SWINGS := ["sword_light_0", "sword_light_1", "sword_light_2", "sword_heavy"]
## Fractions of each clip to photograph: into it, the strike, and out of it.
const AT := [0.25, 0.55, 0.85]

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
	cam.look_at_from_position(Vector3(2.6, 1.5, 3.0), Vector3(0.0, 1.0, 0.0))
	cam.current = true

	var visual: HumanoidVisual = pawn.body_visual
	visual.set_held_item(ITEM)
	await get_tree().process_frame

	for key: String in SWINGS:
		var length := visual.play_scripted(key)
		print("PREVIEW %s=%.2fs" % [key, length])
		# SEEKED rather than stepped: counting frame-sized deltas measures frames,
		# not time, and a windowed run of an empty scene runs well past 60 fps.
		visual.anim_player.pause()
		for frac: float in AT:
			visual.anim_player.seek(length * frac, true)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					"%s/%s_%02d.png" % [OUT_DIR, key, int(frac * 100.0)])
		visual.stop_scripted()

	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()
