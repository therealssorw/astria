class_name ItemDb
extends RefCounted
## The catalogue of every item in the game. Add an entry here and it can be
## carried, stocked by a shop and sold back — nothing else needs changing.
##
##   "item_id": {
##       "name": "Shown to the player",
##       "price": <buy cost in gold>,
##       "icon": "res://Assets/Textures/Items/<group>/<file>.png",
##   }
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
##
## Selling pays SELL_RATIO of the buy price, rounded down.
##
## The icon is what the inventory grid and the shop rows draw — give an item
## one here and it shows up everywhere, no UI changes needed. Anything without
## a usable icon falls back to drawing its name, so a missing file is a cosmetic
## problem and never a crash. Icons live under Assets/Textures/Items/, grouped
## like the models are; square art reads best (the shipped ones are 64x64).

const SELL_RATIO := 0.5

const SWORD_MODEL := "res://Assets/Models/Items/Weapons/Swords/tony_sword.fbx"

const ITEMS := {
	"wooden_sword": {
		"name": "Wooden Sword",
		"price": 20,
		"desc": "A splintered practice blade.",
		"icon": "res://Assets/Textures/Items/Weapons/wooden_sword.png",
		"hold": {"model": SWORD_MODEL, "scale": Vector3(2.6, 1.0, 2.4),
				"tint": Color(0.52, 0.36, 0.19), "anim_set": "sword"},
	},
	"copper_sword": {
		"name": "Copper Sword",
		"price": 50,
		"desc": "Soft metal, but it holds an edge.",
		"icon": "res://Assets/Textures/Items/Weapons/copper_sword.png",
		"hold": {"model": SWORD_MODEL, "scale": Vector3(2.9, 1.08, 2.7),
				"tint": Color(0.85, 0.52, 0.28), "anim_set": "sword"},
	},
	"iron_sword": {
		"name": "Iron Sword",
		"price": 100,
		"desc": "Forge-work worth carrying.",
		"icon": "res://Assets/Textures/Items/Weapons/iron_sword.png",
		"hold": {"model": SWORD_MODEL, "scale": Vector3(3.2, 1.15, 3.0),
				"anim_set": "sword"},
	},
}

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

## Loaded icons, kept so the grid doesn't hit the disk every redraw.
static var _icons := {}

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

## The item's art, or null when it has none / the file is missing — callers
## fall back to the item's name so a bad path never breaks a screen.
static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var path := str(ITEMS.get(id, {}).get("icon", ""))
	var tex: Texture2D = null
	if path == "":
		pass
	elif ResourceLoader.exists(path):
		tex = load(path)
	else:
		push_warning("ItemDb: '%s' has no icon at %s" % [id, path])
	_icons[id] = tex
	return tex

static func buy_price(id: String) -> int:
	return int(ITEMS.get(id, {}).get("price", 0))

static func sell_price(id: String) -> int:
	var entry: Dictionary = ITEMS.get(id, {})
	if entry.has("sell"):
		return int(entry["sell"])
	return int(floor(float(entry.get("price", 0)) * SELL_RATIO))
