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
##
## Selling pays SELL_RATIO of the buy price, rounded down.
##
## The icon is what the inventory grid and the shop rows draw — give an item
## one here and it shows up everywhere, no UI changes needed. Anything without
## a usable icon falls back to drawing its name, so a missing file is a cosmetic
## problem and never a crash. Icons live under Assets/Textures/Items/, grouped
## like the models are; square art reads best (the shipped ones are 64x64).

const SELL_RATIO := 0.5

const ITEMS := {
	"wooden_sword": {
		"name": "Wooden Sword",
		"price": 20,
		"desc": "A splintered practice blade.",
		"icon": "res://Assets/Textures/Items/Weapons/wooden_sword.png",
	},
	"copper_sword": {
		"name": "Copper Sword",
		"price": 50,
		"desc": "Soft metal, but it holds an edge.",
		"icon": "res://Assets/Textures/Items/Weapons/copper_sword.png",
	},
	"iron_sword": {
		"name": "Iron Sword",
		"price": 100,
		"desc": "Forge-work worth carrying.",
		"icon": "res://Assets/Textures/Items/Weapons/iron_sword.png",
	},
}

## Loaded icons, kept so the grid doesn't hit the disk every redraw.
static var _icons := {}

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
