extends Node
## Measuring aid for CUTTING SWING CLIPS out of the sword pack's takes — not a
## pass/fail test, and nothing depends on it.
##   godot --headless --path . res://tests/diag_sword.tscn
##
## The pack ships choreographed COMBOS: spins, flourishes and two-handed
## acrobatics, several strikes to a take. What the game wants out of them is the
## plain ones — a slash that stays in front of the fighter and crosses their
## body. So this slides a window over every take and scores each one on the
## things that make a cut ordinary — measured AS THE GAME WILL SHOW IT, which is
## the only measurement worth having here. That means the hand relative to the
## hips with the hips' YAW divided out and their travel dropped, because that is
## exactly what the clip pipeline does to it (HumanoidClips.unspin, and the
## de-root in repath).
##
## Measuring it any other way picks unplayable slices, and both mistakes were
## made before landing on this: in WORLD terms a spin makes a stationary blade
## look like a fast cut, and in the CHEST's frame the strike of combo 6 scores
## as the fastest hand in the file — while on screen, unspun, it is a fighter
## waving a sword over their head, because the cut WAS the spin and the spin is
## what got taken out.
##
##   speed  the fastest the sword hand travels — a window with no strike in it
##          is not a swing, whatever else it scores
##   at     where in the window that peak falls. A window ENDING on the strike
##          is all wind-up and no cut: it scores beautifully and, played, the
##          blade never arrives. Wanted somewhere near the middle
##   turn   how far the hips rotate across the window. THE HEADLINE NUMBER: a
##          plain slash is nearly 0, a spin is a hundred and up, and unspinning
##          one afterwards (HumanoidClips.unspin) straightens the body but not
##          the arm, which still sweeps in whatever plane the spin left it
##   front  how far ahead of the fighter the hand stays. Negative is a cut
##          thrown behind them
##   cross  how far the hand travels sideways across the body, tip to tail
##   drop   how far it falls: a downward cut is positive, an uppercut negative
##   blade  how far the hand ROTATES, in degrees. A hand that travels without
##          turning carries the blade broadside, so what you get is a fighter
##          waving a sword about rather than cutting with it — that is combo
##          6's strike, which every other number here rates highly

const DIR := "res://Assets/Animations/Humanoid/Sword/Attack/"
const FPS := 30.0
## Swing windows to try, in seconds — about as long as a strike with its
## wind-up and follow-through either side.
const LENGTHS := [0.40, 0.50, 0.60]
## Windows printed per take, best first.
const SHOW := 6

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
	var hand := skel.find_bone("RightHand")
	var hips := skel.find_bone("Hips")
	ap.play(take)

	# Sample the whole take once: the hand in the character's own frame, and
	# the hips' heading.
	var local: Array[Vector3] = []
	var grip: Array[Basis] = []
	var yaw: Array[float] = []
	for i in int(anim.length * FPS) + 1:
		ap.seek(float(i) / FPS, true)
		var pelvis := skel.get_bone_global_pose(hips)
		var heading := pelvis.basis.get_euler().y
		var flat := Basis(Vector3.UP, -heading)
		local.append(flat * (skel.get_bone_global_pose(hand).origin - pelvis.origin))
		grip.append(flat * skel.get_bone_global_pose(hand).basis.orthonormalized())
		yaw.append(heading)

	var scored: Array = []
	for length: float in LENGTHS:
		var span := int(length * FPS)
		for a in range(0, local.size() - span):
			scored.append(_score(local, grip, yaw, a, a + span))
	scored.sort_custom(func(x, y): return x["score"] > y["score"])
	print("\n=== %s  take=%s  %.2fs" % [path.get_file(), take, anim.length])
	for i in mini(SHOW, scored.size()):
		var w: Dictionary = scored[i]
		print("  slice [%.2f, %.2f]  speed=%5.2f at=%3.0f%% blade=%4.0f turn=%6.1f front=%5.2f cross=%5.2f drop=%5.2f"
				% [w.from, w.to, w.speed, w.at * 100.0, w.blade, w.turn, w.front, w.cross, w.drop])
	scene.queue_free()

func _score(local: Array[Vector3], grip: Array[Basis], yaw: Array[float],
		a: int, b: int) -> Dictionary:
	var speed := 0.0
	var peak := a
	var front := 0.0
	var turn_lo := 0.0
	var turn_hi := 0.0
	for i in range(a, b + 1):
		front += local[i].z
		if i > a:
			var step := (local[i] - local[i - 1]).length() * FPS
			if step > speed:
				speed = step
				peak = i
			var d := rad_to_deg(wrapf(yaw[i] - yaw[a], -PI, PI))
			turn_lo = minf(turn_lo, d)
			turn_hi = maxf(turn_hi, d)
	front /= float(b - a + 1)
	var turn := turn_hi - turn_lo
	var w := {
		"from": float(a) / FPS, "to": float(b) / FPS,
		"speed": speed, "at": float(peak - a) / float(b - a), "turn": turn, "front": front,
		"cross": local[b].x - local[a].x, "drop": local[a].y - local[b].y,
		"blade": rad_to_deg((grip[a].inverse() * grip[b]).get_rotation_quaternion().get_angle()),
	}
	# A swing worth having is a fast hand kept in front of the fighter. A strike
	# that lands outside the middle of the window is not a swing at all — see
	# "at". "turn" is printed rather than scored: it says how much of the take's
	# choreography the unspin is about to remove, which is a thing to look at
	# before trusting a slice, not a thing to rank by.
	w["score"] = w.speed + 4.0 * front + 0.03 * w.blade
	if w.at < 0.3 or w.at > 0.65:
		w["score"] -= 100.0
	return w
