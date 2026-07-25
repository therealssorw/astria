extends CanvasLayer
## The wake-up that opens the game: the screen is already black when the island
## loads, your own head complains at you, the world slowly fades up around you,
## and then you ask where you are. Autoload: IntroCutscene.
##
## The words live in DialogData ("intro_wake" / "intro_where") like every other
## line in the game — this file only owns the black rect and the timing.
##
## Purely local (see "Server authority" in CLAUDE.md): a cutscene changes
## nothing but this player's screen, so none of it is networked. The server
## spawns the pawn exactly as it always does; the black rect is just drawn over
## the top until the player has had their moment.
##
## Hooks: world.gd arms it as the island enters the tree (so the black is up
## before a frame of the world is drawn), player.gd starts it once the local
## pawn exists, and main_menu.gd aborts it if we end up back at the menu.

const DARK_DIALOG := "intro_wake"    # spoken over the black
const LIGHT_DIALOG := "intro_where"  # spoken once the world is visible

## How long the world takes to appear once the first line is done.
const FADE_TIME := 4.5
## Beat between the world being visible and the second line starting.
const AFTER_FADE_PAUSE := 0.8

var _rect: ColorRect
var _armed := false
var _playing := false
var _tween: Tween

func _ready() -> void:
	# above the HUD, below the dialog box (layer 20): the words are meant to be
	# read against the black, not covered by it
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)
	DialogSystem.closed.connect(_on_dialog_closed)

## Black out now, and wait for the local pawn. Called by world.gd from _ready,
## which is before the world has been drawn once.
func arm() -> void:
	if Net.is_dedicated or _playing:
		return
	_armed = true
	_rect.color = Color.BLACK
	_rect.visible = true

## The local pawn exists — start talking. Called by player.gd. Does nothing if
## we were never armed, so a respawn mid-session never replays the intro.
func on_local_pawn_ready() -> void:
	if not _armed:
		return
	_armed = false
	_playing = true
	_freeze(true)
	_begin.call_deferred() # let the pawn finish entering the tree first

## Drop everything and give the screen back — used when the world goes away
## under us (a disconnect back to the menu) rather than at the end of the scene.
func abort() -> void:
	if not _playing and not _armed:
		return
	if DialogSystem.is_open():
		DialogSystem.close()
	_finish()

func is_playing() -> bool:
	return _playing

## How black the screen is: 1 while the world is hidden, 0 once it is fully up.
func darkness() -> float:
	return _rect.color.a if _rect.visible else 0.0

# ---------------- the scene itself ----------------

func _begin() -> void:
	# a missing dialog must never leave a player staring at a black screen
	if not DialogSystem.start(DARK_DIALOG):
		_finish()

func _on_dialog_closed(id: String) -> void:
	if not _playing:
		return
	if id == DARK_DIALOG:
		_fade_up()
	elif id == LIGHT_DIALOG:
		_finish()

func _fade_up() -> void:
	# the box let go of the player when it closed, but the fade is still
	# cutscene — hold onto them, and keep the cursor free so a stray mouse
	# nudge cannot spin the camera while the island appears
	_freeze(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(AFTER_FADE_PAUSE)
	_tween.tween_callback(_speak_awake)

func _speak_awake() -> void:
	_rect.visible = false
	if not DialogSystem.start(LIGHT_DIALOG):
		_finish()

func _finish() -> void:
	_armed = false
	_playing = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
	_rect.visible = false
	_rect.color = Color.BLACK # reset for the next time we load in
	_freeze(false)
	if get_tree().get_first_node_in_group("local_player") != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _freeze(on: bool) -> void:
	var pawn := get_tree().get_first_node_in_group("local_player")
	if is_instance_valid(pawn):
		pawn.set("ui_open", on)
