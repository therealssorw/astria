class_name ItemDb
extends RefCounted
## The catalogue of every item in the game. Add an entry here and it can be
## carried, stocked by a shop and sold back — nothing else needs changing.
##
##   "item_id": {"name": "Shown to the player", "price": <buy cost in gold>}
##
## Optional per-item keys:
##   "sell"  — override the sell price instead of using SELL_RATIO
##   "desc"  — one-line flavour, shown in the shop row
##
## Selling pays SELL_RATIO of the buy price, rounded down.

const SELL_RATIO := 0.5

const ITEMS := {
	"wooden_sword": {
		"name": "Wooden Sword",
		"price": 20,
		"desc": "A splintered practice blade.",
	},
	"copper_sword": {
		"name": "Copper Sword",
		"price": 50,
		"desc": "Soft metal, but it holds an edge.",
	},
	"iron_sword": {
		"name": "Iron Sword",
		"price": 100,
		"desc": "Forge-work worth carrying.",
	},
}

static func has(id: String) -> bool:
	return ITEMS.has(id)

static func item_name(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))

static func description(id: String) -> String:
	return str(ITEMS.get(id, {}).get("desc", ""))

static func buy_price(id: String) -> int:
	return int(ITEMS.get(id, {}).get("price", 0))

static func sell_price(id: String) -> int:
	var entry: Dictionary = ITEMS.get(id, {})
	if entry.has("sell"):
		return int(entry["sell"])
	return int(floor(float(entry.get("price", 0)) * SELL_RATIO))
