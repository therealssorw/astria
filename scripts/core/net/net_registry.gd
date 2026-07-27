class_name NetRegistry
## What a player IS, as a plain dictionary, and every rule for reading and
## reshaping one. Split out of Net because none of it needs the network: an
## entry is a bag, a purse, a bar and a record of progress, and the RPC layer
## only ever hands one of these functions the entry it just looked up.
##
## Everything here is STATIC and takes the entry it works on. That is what
## makes it testable without a server, and what stops a second copy of "what
## does the hotbar do when the bag changes" growing somewhere else.

## Quick-use bar: how many slots a player has. Server-owned like the bag —
## what you are holding decides what "use" does, so it is gameplay, not a
## screen decoration.
const HOTBAR_SLOTS := 9
## Longest a username may be after cleaning.
const NAME_LIMIT := 20

# ---------------- making one ----------------

static func make_entry(username: String, starting_items: Dictionary) -> Dictionary:
	var entry := {
		"name": username,
		"kills": 0, "deaths": 0,
		"gold": 0,
		"items": starting_items,
		"hotbar": empty_hotbar(), "hot_slot": 0,
		"quest": "",       # id of the quest being tracked, "" for none
		"quest_kills": 0,  # kills counted towards it, when it asks for kills
		"gifts": {},       # GiftData ids already handed over, so none is given twice
		"equipped": empty_equipment(), # armor slot -> item id worn there
		"seen": {},        # items already offered a hotbar slot (server-side only)
	}
	refill_hotbar(entry) # --dev-items handouts land on the bar like anything else
	return entry

static func empty_hotbar() -> Array:
	var bar := []
	bar.resize(HOTBAR_SLOTS)
	bar.fill("")
	return bar

static func empty_equipment() -> Dictionary:
	var worn := {}
	for slot: String in ItemDb.EQUIP_SLOTS:
		worn[slot] = ""
	return worn

## Clean a username and make it unique against the names already registered.
static func sanitize_name(raw: String, taken: Array) -> String:
	var cleaned := ""
	for ch in raw.strip_edges():
		if ch >= " " and cleaned.length() < NAME_LIMIT:
			cleaned += ch
	if cleaned.is_empty():
		cleaned = "Player"
	var candidate := cleaned
	var n := 2
	while taken.has(candidate):
		candidate = "%s(%d)" % [cleaned, n]
		n += 1
	return candidate

# ---------------- reading one ----------------

## The item in an entry's selected hotbar slot, or "".
static func held_item(entry: Dictionary) -> String:
	var bar: Array = entry.get("hotbar", [])
	var slot := int(entry.get("hot_slot", 0))
	return str(bar[slot]) if slot >= 0 and slot < bar.size() else ""

static func carries(entry: Dictionary, item_id: String) -> bool:
	return int((entry.get("items", {}) as Dictionary).get(item_id, 0)) > 0

## Total armor level worn: the best piece in each of the three equipment slots,
## added up. One slot holds one piece, so a bag full of helmets is worth exactly
## one helmet — and only when it is on your head.
static func armor_levels(entry: Dictionary) -> int:
	var total := 0
	var worn: Dictionary = entry.get("equipped", {})
	for slot: String in ItemDb.EQUIP_SLOTS:
		total += ItemDb.level_of(str(worn.get(slot, "")))
	return total

## What everyone is allowed to see. No one needs another player's purse or bag,
## so those never leave the server except to the peer they belong to. "held" and
## "equipped" ARE public: one is in your hand and the other is on your back, so
## every other pawn has to draw them.
static func public_slice(players: Dictionary) -> Dictionary:
	var out := {}
	for id in players:
		var e: Dictionary = players[id]
		out[id] = {
			"name": e["name"], "kills": e["kills"], "deaths": e["deaths"],
			"held": held_item(e),
			"equipped": (e.get("equipped", {}) as Dictionary).duplicate(),
		}
	return out

static func names(players: Dictionary) -> Array:
	var out: Array = []
	for id in players:
		out.append(str(players[id].get("name", "")))
	return out

# ---------------- changing one ----------------

## Put NEWLY carried items on the first free slot, and take gone ones off.
## Only the first copy of an item does this, and only once: "seen" remembers
## what has already been offered a slot, so clearing a slot by hand stays
## cleared instead of filling itself back in the next time anything changes. A
## full bar keeps what it has, and dropping an item entirely forgets it — buy it
## again and it comes back.
static func refill_hotbar(entry: Dictionary) -> void:
	var bar: Array = entry["hotbar"]
	var items: Dictionary = entry["items"]
	var seen: Dictionary = entry["seen"]
	# an item that is gone from the bag can't stay in a slot, or be remembered
	for i in bar.size():
		if bar[i] != "" and int(items.get(bar[i], 0)) <= 0:
			bar[i] = ""
	for known: String in seen.keys():
		if int(items.get(known, 0)) <= 0:
			seen.erase(known)
	for item_id: String in items:
		if seen.has(item_id):
			continue
		seen[item_id] = true
		if bar.has(item_id):
			continue
		var free := bar.find("")
		if free >= 0:
			bar[free] = item_id # else the bar is full and this one waits in the bag

static func add_item(entry: Dictionary, item_id: String, n := 1) -> void:
	var items: Dictionary = entry["items"]
	items[item_id] = int(items.get(item_id, 0)) + n

## Take one away, erasing the key when the last one goes. Returns false when
## there was nothing to take.
static func remove_item(entry: Dictionary, item_id: String) -> bool:
	var items: Dictionary = entry["items"]
	var held := int(items.get(item_id, 0))
	if held < 1:
		return false
	if held > 1:
		items[item_id] = held - 1
	else:
		items.erase(item_id)
	return true

## Put a slot in hand / into a slot. Assigning something already on the bar
## SWAPS rather than duplicating it. Returns false when the player is not
## carrying what it was asked to place.
static func assign_hotbar(entry: Dictionary, slot: int, item_id: String) -> bool:
	var bar: Array = entry["hotbar"]
	if item_id == "":
		bar[slot] = ""
		return true
	if not carries(entry, item_id):
		return false
	var already: int = bar.find(item_id)
	if already >= 0:
		bar[already] = bar[slot]
	bar[slot] = item_id
	entry["hot_slot"] = slot
	return true

## Put `item_id` ON, MOVING it out of the bag. A piece you are wearing is on your
## back and not in your sack, so it occupies an equipment slot INSTEAD of a bag
## slot — which is also what stops you selling the breastplate you have on, and
## why nothing has to take armor off when the bag shrinks. Whatever that slot was
## already wearing goes back into the bag in exchange.
##
## Returns the slot it went into, or "" when the item is not armor, is not
## carried, or is the piece already worn there. The SLOT comes from the ITEM,
## never from a request.
static func equip(entry: Dictionary, item_id: String) -> String:
	var slot := ItemDb.armor_slot(item_id)
	if slot == "" or not carries(entry, item_id):
		return ""
	var worn: Dictionary = entry.get("equipped", empty_equipment())
	var replaced := str(worn.get(slot, ""))
	if replaced == item_id:
		return "" # already on: taking it off is unequip's job, not a second meaning
	remove_item(entry, item_id)
	if replaced != "":
		add_item(entry, replaced)
	worn[slot] = item_id
	entry["equipped"] = worn
	return slot

## Take whatever is worn in `slot` off, back into the bag. Returns the item that
## came off, or "" when the slot is not an equipment slot or is already empty.
## The slot is the only thing a request names here, and there is nothing to lie
## about in it: an unknown one is refused and an empty one does nothing.
static func unequip(entry: Dictionary, slot: String) -> String:
	if not ItemDb.EQUIP_SLOTS.has(slot):
		return ""
	var worn: Dictionary = entry.get("equipped", empty_equipment())
	var item_id := str(worn.get(slot, ""))
	if item_id == "":
		return ""
	worn[slot] = ""
	entry["equipped"] = worn
	add_item(entry, item_id)
	return item_id
