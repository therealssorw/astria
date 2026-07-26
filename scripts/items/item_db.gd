class_name ItemDb
extends RefCounted
## The catalogue of every item in the game. Add an entry here and it can be
## carried, stocked by a shop and sold back — nothing else needs changing.
##
##   "item_id": {
##       "name": "Shown to the player",
##       "level": <rank — see below>,
##       "price": <buy cost in gold>,
##   }
##
## EVERY item carries a "level": it is the item's rank, and for anything you
## can swing it is also its damage. FISTS ARE LEVEL 0 (an empty hand is
## FIST_LEVEL, which is what an item with no level of its own falls back to),
## so the bare-handed numbers on player.gd are the baseline and each level is
## worth another CombatLevels.DAMAGE_PER_WEAPON_LEVEL of them. That is the
## whole ladder — see scripts/combat/combat_levels.gd, which owns the maths and
## is the only place allowed to.
##
## Optional per-item keys:
##   "sell"  — override the sell price instead of using SELL_RATIO
##   "desc"  — one-line flavour, shown as a tooltip
##   "hold"  — the model a character carries while this item is in hand:
##             {"model": <scene path>, "scale": float OR Vector3, "pos":
##              Vector3, "rot": Vector3 (degrees), "tint": Color,
##              "anim_set": String}. Everything but "model" is optional and
##             defaults to HOLD_DEFAULTS, which is where the grip is lined up
##             with the hand bone — tune the fit there once and every weapon
##             follows. A Vector3 scale fattens a blade's cross-section
##             without lengthening it; "anim_set" names a clip set in
##             HumanoidVisual.SWORD_CLIPS, so carrying it changes how the
##             character stands, walks and swings.
##   "suit"  — for armor: the ArmorDefinition the piece belongs to. It is where
##             the plate's model and its colours come from, so a suit
##             recoloured in the Items tab redresses the item with it.
##
## Selling pays SELL_RATIO of the buy price, rounded down.
##
## AN ITEM CARRIES NO ICON, because there is nothing to draw one from that is
## not already here: its picture is a photograph of its own art, taken at run
## time from the file above — the model a character is seen holding, or the
## piece of the suit it is. See `ItemIcons`. So an item is described in ONE
## place; a blade that gets fatter or a suit that gets repainted cannot leave a
## stale drawing of itself behind on the shop rows. An item with no art at all
## has no picture, and every screen falls back to drawing its name.

const SELL_RATIO := 0.5

## An empty hand. Everything is measured from here: the exported damage on
## player.gd is what a level 0 fist deals, and an item that forgets to declare
## a level is worth no more than punching.
const FIST_LEVEL := 0

const SWORD_MODEL := "res://Assets/Models/Items/Weapons/Swords/tony_sword.fbx"

## The suits the armor items below are pieces of, by tier. A tier's four items
## are that one file's four pieces, so what an iron helmet looks like is what
## iron_armor.tres says it looks like — in the game and in the bag alike.
const SUITS := {
	"flimsy": "res://Assets/Data/Armor/flimsy_armor.tres",
	"copper": "res://Assets/Data/Armor/copper_armor.tres",
	"iron": "res://Assets/Data/Armor/iron_armor.tres",
}

const ITEMS := {
	"wooden_sword": {
		"name": "Wooden Sword",
		"level": 1,
		"price": 20,
		"desc": "A splintered practice blade.",
		"hold": {"model": SWORD_MODEL, "scale": Vector3(2.6, 1.0, 2.4),
				"tint": Color(0.52, 0.36, 0.19), "anim_set": "sword"},
	},
	"copper_sword": {
		"name": "Copper Sword",
		"level": 2,
		"price": 125,
		"desc": "Soft metal, but it holds an edge.",
		"hold": {"model": SWORD_MODEL, "scale": Vector3(2.9, 1.08, 2.7),
				"tint": Color(0.85, 0.52, 0.28), "anim_set": "sword"},
	},
	"iron_sword": {
		"name": "Iron Sword",
		"level": 3,
		"price": 250,
		"desc": "Forge-work worth carrying.",
		"hold": {"model": SWORD_MODEL, "scale": Vector3(3.2, 1.15, 3.0),
				"anim_set": "sword"},
	},
	# --- armor ---
	#
	# The three suits in Assets/Data/Armor/, a piece at a time. An armor item
	# carries "armor": the slot it covers, which is what makes four pieces a SET
	# rather than four items — you cannot wear two helmets, so only the best
	# piece per slot counts (see Net.armor_levels).
	#
	# Its "level" is the same ladder as a sword's, and matched to the blade of
	# the same name: flimsy sits with the wooden sword at 1, copper at 2, iron at
	# 3. On a weapon a level is damage dealt; on armor it is damage NOT taken.
	# Priced to match its blade too, per piece — so a full suit costs four
	# swords.
	"flimsy_helmet": {
		"name": "Flimsy Helmet", "armor": "head", "level": 1, "price": 20,
		"suit": SUITS["flimsy"],
		"desc": "Dented, and a size too big.",
	},
	"flimsy_chestplate": {
		"name": "Flimsy Chestplate", "armor": "body", "level": 1, "price": 20,
		"suit": SUITS["flimsy"],
		"desc": "The straps have been replaced more than once.",
	},
	"flimsy_gauntlets": {
		"name": "Flimsy Gauntlets", "armor": "arms", "level": 1, "price": 20,
		"suit": SUITS["flimsy"],
		"desc": "Thin plate over older leather.",
	},
	"flimsy_boots": {
		"name": "Flimsy Boots", "armor": "feet", "level": 1, "price": 20,
		"suit": SUITS["flimsy"],
		"desc": "Scuffed through to the metal at the toe.",
	},
	"copper_helmet": {
		"name": "Copper Helmet", "armor": "head", "level": 2, "price": 125,
		"suit": SUITS["copper"],
		"desc": "Soft, but it turns an edge once.",
	},
	"copper_chestplate": {
		"name": "Copper Chestplate", "armor": "body", "level": 2, "price": 125,
		"suit": SUITS["copper"],
		"desc": "Beaten from one sheet, and heavy for it.",
	},
	"copper_gauntlets": {
		"name": "Copper Gauntlets", "armor": "arms", "level": 2, "price": 125,
		"suit": SUITS["copper"],
		"desc": "Green at the knuckles already.",
	},
	"copper_boots": {
		"name": "Copper Boots", "armor": "feet", "level": 2, "price": 125,
		"suit": SUITS["copper"],
		"desc": "Loud on stone, but they hold.",
	},
	"iron_helmet": {
		"name": "Iron Helmet", "armor": "head", "level": 3, "price": 250,
		"suit": SUITS["iron"],
		"desc": "Forge-work worth wearing.",
	},
	"iron_chestplate": {
		"name": "Iron Chestplate", "armor": "body", "level": 3, "price": 250,
		"suit": SUITS["iron"],
		"desc": "Plate thick enough to argue with a sword.",
	},
	"iron_gauntlets": {
		"name": "Iron Gauntlets", "armor": "arms", "level": 3, "price": 250,
		"suit": SUITS["iron"],
		"desc": "Articulated, and barely worn in.",
	},
	"iron_boots": {
		"name": "Iron Boots", "armor": "feet", "level": 3, "price": 250,
		"suit": SUITS["iron"],
		"desc": "You feel every step, and so does the ground.",
	},
}

## The armor slots, in the order a suit is worn from the ground up. The same
## four an NpcDefinition's armor layer holds, because they are the same pieces.
const ARMOR_SLOTS := ["feet", "body", "arms", "head"]

## A full suit, by tier. Kept here rather than written out wherever a set is
## handed over or stocked, so "a full set" cannot come to mean four different
## things in three files.
const ARMOR_SETS := {
	"flimsy": ["flimsy_boots", "flimsy_chestplate", "flimsy_gauntlets", "flimsy_helmet"],
	"copper": ["copper_boots", "copper_chestplate", "copper_gauntlets", "copper_helmet"],
	"iron": ["iron_boots", "iron_chestplate", "iron_gauntlets", "iron_helmet"],
}

## Which armor slot an item covers, or "" when it is not armor.
static func armor_slot(id: String) -> String:
	return str(ITEMS.get(id, {}).get("armor", ""))

static func is_armor(id: String) -> bool:
	return armor_slot(id) != ""

## How a held model sits in the hand bone before per-item tweaks. The sword
## art runs up its own +Y with the grip at the origin, and a humanoid-profile
## hand bone has the fingers along +Y too, so the blade needs turning to run
## along the palm rather than out of the wrist.
const HOLD_DEFAULTS := {
	"scale": 1.0,
	"pos": Vector3(0.0, 0.06, 0.0),
	"rot": Vector3(35.0, 0.0, 0.0),
	"tint": Color(1, 1, 1),
}

## What this item looks like in a character's hand, with the defaults filled
## in. Empty when the item isn't something you can be seen holding.
static func hold_config(id: String) -> Dictionary:
	var raw: Dictionary = ITEMS.get(id, {}).get("hold", {})
	if raw.is_empty() or not raw.has("model"):
		return {}
	var cfg := HOLD_DEFAULTS.duplicate()
	cfg.merge(raw, true)
	return cfg

## Is this item drawn in the hand at all?
static func is_holdable(id: String) -> bool:
	return not hold_config(id).is_empty()

static func has(id: String) -> bool:
	return ITEMS.has(id)

static func item_name(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))

static func description(id: String) -> String:
	return str(ITEMS.get(id, {}).get("desc", ""))

## This item's rank. An empty hand, an unknown id and an item that never
## declared one all come out as FIST_LEVEL — punching — so a missing level is
## never a free upgrade.
static func level_of(id: String) -> int:
	return int(ITEMS.get(id, {}).get("level", FIST_LEVEL))

## How a level reads on screen — one wording, so the bag, the shop and anything
## added later can never label the same rank two different ways.
static func level_label(id: String) -> String:
	return "Lv %d" % level_of(id)

## The suit an armor item is a piece of, or null for anything else. Loaded
## rather than copied: nothing here writes to it.
static func suit_of(id: String) -> ArmorDefinition:
	var path := str(ITEMS.get(id, {}).get("suit", ""))
	if path.is_empty():
		return null
	var suit := ArmorLibrary.load_suit(path)
	if suit == null:
		push_warning("ItemDb: '%s' names a suit that will not load — %s" % [id, path])
	return suit

## Which piece of that suit it is — the plate itself, with its model and the
## colours the suit paints it.
static func armor_piece(id: String) -> NpcPart:
	var suit := suit_of(id)
	if suit == null:
		return null
	return suit.get_piece(armor_slot(id))

## The FILE an item's picture is a photograph of, or "" when it has no art at
## all. Held items are their held model; armor is the plate of its suit.
static func art_source(id: String) -> String:
	var cfg := hold_config(id)
	if not cfg.is_empty():
		var model := str(cfg["model"])
		return model if ResourceLoader.exists(model) else ""
	var piece := armor_piece(id)
	if piece == null or not ResourceLoader.exists(piece.model_path):
		return ""
	return piece.model_path

## The item as an OBJECT: its own art, in its own colours, facing +Z like
## everything else in the game, with nothing about a hand or a body applied.
## Null when the item has no art. This is what gets photographed for the icon,
## and it is the thing to instance if an item is ever dropped on the ground.
static func build_model(id: String) -> Node3D:
	if art_source(id) == "":
		return null
	var cfg := hold_config(id)
	if not cfg.is_empty():
		var scene := load(str(cfg["model"])) as PackedScene
		if scene == null:
			return null
		var inst := scene.instantiate() as Node3D
		# The hand's pos/rot are deliberately NOT applied: they line the grip up
		# with a bone, and there is no bone here. The scale IS, because that is
		# how big the item is — a wooden sword really is the shorter one.
		var s: Variant = cfg["scale"]
		inst.scale = s if s is Vector3 else Vector3.ONE * float(s)
		tint_model(inst, cfg["tint"])
		return inst
	return NpcRig.preview_mesh(armor_piece(id))

## One model serves several items, so a tint stands in for different metals
## until each has art of its own. White leaves the material alone. Shared with
## the copy in a character's hand, so an item's icon and the thing being swung
## can never be different colours.
static func tint_model(root: Node, tint: Color) -> void:
	if tint == Color(1, 1, 1):
		return
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		for i in mesh_inst.get_surface_override_material_count():
			var mat := mesh_inst.mesh.surface_get_material(i)
			var over := (mat.duplicate() if mat else StandardMaterial3D.new()) as BaseMaterial3D
			over.albedo_color = over.albedo_color * tint
			mesh_inst.set_surface_override_material(i, over)

## The item's picture: a render of the art above, or null when it has none —
## callers fall back to the item's name, so a missing model is a cosmetic
## problem and never a crash. See `ItemIcons`, which takes the photograph.
static func icon(id: String) -> Texture2D:
	return ItemIcons.icon(id)

static func buy_price(id: String) -> int:
	return int(ITEMS.get(id, {}).get("price", 0))

static func sell_price(id: String) -> int:
	var entry: Dictionary = ITEMS.get(id, {})
	if entry.has("sell"):
		return int(entry["sell"])
	return int(floor(float(entry.get("price", 0)) * SELL_RATIO))
