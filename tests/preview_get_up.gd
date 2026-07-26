extends Node3D
## Look-at aid, not a pass/fail test: the intro's getting-up, four frames across
## the clip, on the real player body.
##   godot --path . res://tests/preview_get_up.tscn
## Needs a real window — do NOT pass --headless. Shots land in
## user://get_up_preview.
##
## This is the only thing that can tell you whether the clip RETARGETS: it is a
## Mixamo take on a voxel character whose skeleton has been reproportioned and
## whose hips track has been rebased, and every one of those steps is invisible
## to an assertion about clip lengths. The character has to start flat on the
## floor and finish standing on it.

const OUT_DIR := "user://get_up_preview"
const PLAYER := preload("res://scenes/player.tscn")
## Fractions of the clip to photograph.
const AT := [0.0, 0.35, 0.65, 1.0]

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

	# the pawn's own camera is current; the preview wants a side-on view instead.
	# Aimed in code rather than by a transform in the scene — a hand-written
	# basis that misses the character photographs an empty field.
	var cam := $Camera3D as Camera3D
	cam.look_at_from_position(Vector3(2.8, 1.5, 3.4), Vector3(0.0, 0.7, 0.0))
	cam.current = true

	var visual: HumanoidVisual = pawn.body_visual
	var length: float = visual.play_scripted("get_up")
	print("PREVIEW get_up=%.2fs" % length)
	# SEEKED, not stepped. Counting frame-sized deltas by hand measures frames,
	# not time: a windowed run of an empty scene goes far faster than 60 fps, so
	# the clip was a third of the way through when the counter said it had
	# finished — which read as "the character never gets up".
	visual.anim_player.pause()
	for frac: float in AT:
		visual.anim_player.seek(length * frac, true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
				"%s/get_up_%02d.png" % [OUT_DIR, int(frac * 100.0)])

	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()
