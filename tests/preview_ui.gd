extends Control
## Look-at aid, not a pass/fail test: opens the REAL screens over a stand-in
## world and saves a PNG of each, so the palette, the paint behind it and the
## font can be judged without launching the game and walking to an NPC.
##   godot --path . res://tests/preview_ui.tscn
## It needs a real window — do NOT pass --headless, there is nothing to draw
## into. Shots land together in user://ui_preview (the path is printed).
##
## It renders the actual autoloads, not a mock-up: what comes out is what the
## shop and the dialog box really look like after a change to UiTheme.
##
## The root is a CONTROL and every screen is torn down after its shot, and both
## are load-bearing: a Control parented to a Node2D never gets a size, so
## full-rect children silently come out 0x0 (see CLAUDE.md on anchors), and a
## screen left open photobombs the next one.

const OUT_DIR := "user://ui_preview"
const TUTORIAL_OVERLAY := preload("res://scripts/ui/tutorial/tutorial_overlay.gd")
const INVENTORY := preload("res://scripts/ui/inventory_ui.gd")
const MENU := preload("res://scenes/ui/main_menu.tscn")
## Frames to let a screen settle before the shot — the dialog box types itself
## in, so a shot on frame one catches an empty panel.
const SETTLE := 45

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# something for the panels to sit over, so alpha and the backdrop read
	var world := ColorRect.new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.color = Color(0.29, 0.34, 0.30) # about the island's grass
	add_child(world)
	await get_tree().process_frame

	# Opened and torn down out here rather than through a callable: a lambda
	# captures by VALUE, so a node built inside one is not the node this scope
	# then tries to free.
	var swatches := _swatches()
	add_child(swatches)
	await _shot("palette")
	swatches.queue_free()

	ShopSystem.open("blacksmith")
	await _shot("shop")
	# And again after walking down the stock the way a pad walks it: the list is
	# longer than the six rows on screen, so this is the shot that shows the view
	# following the highlight (see tests/test_menu_scroll.tscn, which measures
	# it). A pad has no wheel and no scrollbar — if this shot is identical to the
	# one above, the list is stuck at the top.
	for _i in 9:
		var down := InputEventAction.new()
		down.action = "ui_down"
		down.pressed = true
		Input.parse_input_event(down)
		await get_tree().process_frame
	await _shot("shop_scrolled")
	ShopSystem.close()

	# Shot with its CHOICES up, not mid-sentence: that is the state the player
	# spends the conversation in, and the only one that shows the numbered rows
	# and the hint that says the number keys pick them. The typing is skipped the
	# way a player skips it, page by page.
	DialogSystem.start("blacksmith")
	await get_tree().process_frame
	for _i in 16:
		DialogSystem._finish_typing()
		if DialogSystem._page >= DialogSystem._pages.size() - 1:
			break
		DialogSystem._next_page()
	await _shot("dialog")
	DialogSystem.close()

	# The tutorial's control popup, POSED: it reads the live step off Tutorial and
	# there is no tutorial running here, so its own tick is stopped and one step
	# handed to it. This is the only way to judge "smaller, and further down".
	var tut: Control = TUTORIAL_OVERLAY.new()
	add_child(tut)
	await get_tree().process_frame
	tut.set_process(false)
	tut._update_gate({"kind": "gate", "action": "block", "popup":
			{"title": "GUARD", "body": "Hold it up and their punches cost you stamina instead of health."}})
	await _shot("tutorial_popup")
	tut.queue_free()

	# The quest corner, on the harder of its two shapes: a counting quest, which
	# is the longest line the panel ever has to hold. It reads the mirror, so
	# setting it here is the whole setup — nothing is claimed to the server.
	var tracker := QuestTracker.new()
	add_child(tracker)
	GameStats.quest = "kill_bandits"
	GameStats.quest_kills = 7
	GameStats.changed.emit()
	await _shot("quest_tracker")
	GameStats.quest = ""
	GameStats.quest_kills = 0
	GameStats.changed.emit()
	tracker.queue_free()

	# The inventory, with a bag to look at. It reads the GameStats mirror and
	# nothing else, so filling that in IS the setup — no server, and nothing is
	# claimed to one. Building it here is also the only check that the draggable
	# slots construct at all.
	var inv: CanvasLayer = INVENTORY.new()
	add_child(inv)
	# the chestplate is WORN and so is deliberately NOT in the bag: a piece on
	# your back has left it, and a preview that showed both would be a picture of
	# something the game cannot do
	GameStats.items = {"wooden_sword": 1, "copper_sword": 1, "iron_sword": 2,
			"flimsy_helmet": 1, "copper_helmet": 1}
	GameStats.hotbar = ["iron_sword", "", "flimsy_helmet", "", "", "", "", "", ""]
	GameStats.hot_slot = 0
	GameStats.coins = 240
	GameStats.equipped = {"helmet": "", "torso": "flimsy_chestplate", "pants": ""}
	GameStats.changed.emit()
	inv._toggle() # open it; there is no pawn here, which it copes with
	await _shot("inventory")

	# AND MID-DRAG, which is the half no assertion can see: the tile riding with
	# the cursor, the slot it came out of ghosted, the Helmet slot lit because
	# that is where a helmet goes, and everything it cannot go on stepped back.
	# `force_drag` is the real gesture — the same notification every slot answers.
	var picked_up := ""
	for slot: Button in inv.item_slots:
		if str(slot.item_id) == "flimsy_helmet":
			get_viewport().warp_mouse(slot.global_position + slot.size * 0.5
					+ Vector2(0, -60)) # off the slot, so the tile is not on top of it
			await get_tree().process_frame
			var data: Dictionary = slot.where()
			data["id"] = slot.item_id
			slot.dragging = true
			slot.force_drag(data, slot._preview())
			picked_up = str(slot.item_id)
			break
	if picked_up == "":
		print("PREVIEW no helmet in the bag to drag — inventory_drag is not a real shot")
	await _shot("inventory_drag")
	inv._toggle()
	inv.queue_free()

	# The menu, in BOTH of its states — the one thing a player sees before
	# anything else, and the one screen with a rule that only a picture proves:
	# signed out there must be no way into the world at all, not the main server
	# and not an address of your own.
	#
	# Posed, not driven: setting Net.last_error makes the menu treat this as a
	# return from a dropped connection, which is the one path through its _ready
	# that neither auto-joins nor hosts. Without it, opening the menu from the
	# editor starts a server.
	for signed_in: bool in [false, true]:
		var was := [Auth.access_token, Auth.user_id, Auth.username]
		if signed_in:
			Auth.access_token = "preview"
			Auth.user_id = "preview"
			Auth.username = "Ada"
		else:
			Auth.access_token = ""
			Auth.user_id = ""
		Net.last_error = "Connection to the host was lost."
		var menu: Control = MENU.instantiate()
		add_child(menu)
		await _shot("menu_signed_in" if signed_in else "menu_signed_out")
		menu.queue_free()
		Auth.access_token = was[0]
		Auth.user_id = was[1]
		Auth.username = was[2]
		Net.last_error = ""

	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()

func _shot(shot_name: String) -> void:
	for i in SETTLE:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])

## The three shades as they actually paint, with the font over them at the
## sizes the game uses — the two things a screenshot of a panel can't isolate.
func _swatches() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.add_child(UiTheme.backdrop(1.0))
	var col := VBoxContainer.new()
	col.position = Vector2(80, 60)
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)
	for pair in [["INK  #232323", UiTheme.INK], ["SLATE  #343434", UiTheme.SLATE],
			["STONE  #464646", UiTheme.STONE]]:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(420, 54)
		var style := StyleBoxFlat.new()
		style.bg_color = pair[1]
		chip.add_theme_stylebox_override("panel", style)
		var l := Label.new()
		l.text = str(pair[0])
		l.add_theme_font_size_override("font_size", 22)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(l)
		col.add_child(chip)
	for size in [13, 17, 22, 34, 52]:
		var l := Label.new()
		l.text = "EB Garamond %d — Bram's Forge, 100 gold" % size
		l.add_theme_font_size_override("font_size", size)
		col.add_child(l)
	return root
