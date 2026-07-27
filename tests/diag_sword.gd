extends Node
## Measuring aid for CUTTING SWING CLIPS out of the sword pack's takes — not a
## pass/fail test, and nothing depends on it. Prints, per frame of each attack
## FBX: where the sword hand is, how fast it is moving, and how far the hips
## have turned since the take began.
##   godot --headless --path . res://tests/diag_sword.tscn
##
## Those three numbers are the whole job of picking a slice. A strike is the
## speed peak; the slice wants the quiet frames either side of it (the lift in
## and the follow-through out), or the clip starts and ends mid-motion and the
## body snaps into it. And the yaw is why HumanoidClips.unspin exists: these
## takes are choreographed COMBOS that turn the fighter through a full circle,
## so the yaw at the strike says how far round they had got — which, before the
## unspin, was how far round the game played the swing.

const DIR := "res://Assets/Animations/Humanoid/Sword/Attack/"
const FPS := 30.0

func _ready() -> void:
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".fbx"):
			_measure(DIR + f)
	get_tree().quit()

func _measure(path: String) -> void:
	var scene: Node = (load(path) as PackedScene).instantiate()
	add_child(scene)
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var skel: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var take := ""
	for c in ap.get_animation_list():
		if c != "RESET":
			take = c
			break
	var anim := ap.get_animation(take)
	print("\n=== %s  take=%s  %.2fs" % [path.get_file(), take, anim.length])
	var hand := skel.find_bone("RightHand")
	var hips := skel.find_bone("Hips")
	ap.play(take)
	var prev := Vector3.ZERO
	var yaw0 := 0.0
	for i in int(anim.length * FPS) + 1:
		var t := float(i) / FPS
		ap.seek(t, true)
		var hp := skel.get_bone_global_pose(hand).origin
		var yaw := skel.get_bone_global_pose(hips).basis.get_euler().y
		if i == 0:
			prev = hp
			yaw0 = yaw
		var speed := (hp - prev).length() * FPS
		prev = hp
		print("  t=%.2f hand=(%5.2f,%5.2f,%5.2f) speed=%5.2f hips_yaw=%6.1f"
				% [t, hp.x, hp.y, hp.z, speed, rad_to_deg(wrapf(yaw - yaw0, -PI, PI))])
	scene.queue_free()
