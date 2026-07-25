class_name ShopData
extends RefCounted
## Who sells what. Keyed by the NPC's `dialog_id`, so giving an NPC a shop is
## two steps: add an entry here, and give one of its dialog answers
## `"action": "open_shop"` (see DialogData).
##
##   "npc_dialog_id": {
##       "title": "Sign over the counter",
##       "stock": ["item_id", ...],   # what it sells, in listed order
##       "buys":  ["item_id", ...],   # optional — omit to buy anything
##   }
##
## Prices come from ItemDb, so two shops can't disagree about what a sword
## is worth.

const SHOPS := {
	"blacksmith": {
		"title": "Bram's Forge",
		"stock": ["wooden_sword", "copper_sword", "iron_sword"],
	},
}

static func has(shop_id: String) -> bool:
	return SHOPS.has(shop_id)

static func get_shop(shop_id: String) -> Dictionary:
	return SHOPS.get(shop_id, {})

static func stock(shop_id: String) -> Array:
	return SHOPS.get(shop_id, {}).get("stock", [])

## True when this shop is willing to take `id` off the player's hands.
static func buys(shop_id: String, id: String) -> bool:
	var shop: Dictionary = SHOPS.get(shop_id, {})
	if not shop.has("buys"):
		return true
	return (shop["buys"] as Array).has(id)
