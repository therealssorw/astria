extends Node
## Autoload: run-wide local stats that survive scene changes. Kills and
## deaths moved to the server-authoritative registry in Net (multiplayer);
## currency and the carried bag live here.
##
## Purely local, like the dialog and the shop — nothing here is replicated.

## Coins or carried items changed; the inventory and shop screens redraw on it.
signal changed

## Placeholder purse so the shop is usable — set to 0 once coins can be earned.
const STARTING_COINS := 150

var coins := STARTING_COINS

## item id (see ItemDb) -> how many are carried. Insertion-ordered, which is
## the order the inventory grid and the shop's sell list use.
var items := {}

# ---------------- coins ----------------

func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)
	changed.emit()

## Deducts `amount` only if it is affordable; returns whether it went through.
func spend_coins(amount: int) -> bool:
	if amount > coins:
		return false
	coins -= amount
	changed.emit()
	return true

# ---------------- carried items ----------------

func add_item(id: String, count := 1) -> void:
	if count <= 0:
		return
	items[id] = item_count(id) + count
	changed.emit()

## Removes up to `count`; returns false (and changes nothing) if too few held.
func remove_item(id: String, count := 1) -> bool:
	if count <= 0 or item_count(id) < count:
		return false
	var left: int = items[id] - count
	if left > 0:
		items[id] = left
	else:
		items.erase(id)
	changed.emit()
	return true

func item_count(id: String) -> int:
	return int(items.get(id, 0))

## Carried item ids, in the order they were first picked up.
func owned_ids() -> Array:
	return items.keys()
