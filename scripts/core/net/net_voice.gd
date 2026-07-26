class_name NetVoice
## The two decisions the server makes about speech: whether it will carry a
## packet at all, and who is close enough to hear it. Split out of Net because
## it is policy, not plumbing — the RPC hop either side of it is three lines.
##
## Voice ITSELF cannot be validated: there is no way to tell speech from noise,
## and it does not matter, because nothing in the game changes when somebody
## talks. What CAN be abused is the RELAY — one patched client sending at ten
## times the rate would cost the server bandwidth for every listener near it.

## How far a voice carries. The server relays a packet only to peers whose pawns
## are inside this of the speaker's — measured on its OWN copies of both — and
## the listener's audio fades to nothing at exactly the same distance, so the
## cut-off is never audible as a pop.
const RANGE := 24.0

## Would the relay carry this packet? Size first, then a budget per talker per
## second. Overspend COUNTS even though it is dropped, so a flooder stays cut
## off for the rest of its second instead of getting a free packet whenever the
## window turns.
##
## `spend` is the server's bookkeeping, peer -> [window start msec, bytes], and
## is written in place.
static func accepts(spend: Dictionary, from_id: int, packet: PackedByteArray) -> bool:
	var n := packet.size()
	if n == 0 or n > VoiceCodec.MAX_PACKET:
		return false
	var now := Time.get_ticks_msec()
	var row: Array = spend.get(from_id, [now, 0])
	if now - int(row[0]) >= 1000:
		row = [now, 0]
	var spent := int(row[1]) + n
	spend[from_id] = [row[0], spent]
	return spent <= VoiceCodec.MAX_BYTES_PER_SECOND

## Who is near enough to hear `from_id` right now.
##
## Read off the SERVER's own copy of every pawn (`server_body_pos` — the last
## position it accepted, already speed-validated), never off anything a client
## claims: who can hear you is not the speaker's decision to make, and a client
## that could name its own audience could listen in across the island. Players
## inside the tutorial need no special case — their copy of the city is
## kilometres away, so the distance rules them out by itself.
static func targets(tree: SceneTree, players: Dictionary, from_id: int) -> Array[int]:
	var out: Array[int] = []
	var speaker := NetWorld.pawn(tree, from_id)
	if speaker == null:
		return out
	var origin: Vector3 = speaker.server_body_pos()
	var reach := RANGE * RANGE
	for id: int in players:
		if id == from_id:
			continue # you never hear yourself
		var pawn := NetWorld.pawn(tree, id)
		if pawn and origin.distance_squared_to(pawn.server_body_pos()) <= reach:
			out.append(id)
	return out
