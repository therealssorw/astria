class_name NetWorld
## Where things ARE. Every "reach into the world scene for the Players
## container / a pawn / an enemy" lookup in the network layer, in one place
## instead of scattered through it.
##
## Static and stateless on purpose: these are questions about the scene tree,
## which is a global, so nothing here needs an instance to own it. Net keeps
## thin `_pawn` / `_players_node` wrappers over these because the tests and the
## rest of the game already say `Net.pawn_of(id)`.

## Fallback used when the level has no `spawn_point` marker in it at all — a
## level being built, or a test scene with no island under it.
const FALLBACK_SPAWN := Vector3(241.0, 95.0, -204.0)
## Extra players are dealt around the marker by golden angle at this radius, so
## two joining in the same frame do not land inside each other.
const SPAWN_RING := 1.6

static func world(tree: SceneTree) -> Node:
	return tree.current_scene

static func container(tree: SceneTree, node_name: String) -> Node:
	var w := world(tree)
	return w.get_node_or_null(node_name) if w else null

static func players_node(tree: SceneTree) -> Node:
	return container(tree, "Players")

static func enemies_node(tree: SceneTree) -> Node:
	return container(tree, "Enemies")

## Runtime-only container for gold piles, created on demand on each peer.
static func drops_node(tree: SceneTree, create := false) -> Node:
	var dn := container(tree, "Drops")
	if dn == null and create:
		var w := world(tree)
		if w == null:
			return null
		dn = Node3D.new()
		dn.name = "Drops"
		w.add_child(dn)
	return dn

static func pawn(tree: SceneTree, id: int) -> Node:
	var pn := players_node(tree)
	return pn.get_node_or_null(str(id)) if pn else null

static func enemy(tree: SceneTree, enemy_name: String) -> Node:
	var en := enemies_node(tree)
	return en.get_node_or_null(enemy_name) if en else null

## Where the i'th player entering the island starts. A NAME, never a
## coordinate: the marker is whatever wears the `spawn_point` group, so moving
## it in the editor moves every spawn with it.
static func spawn_position(tree: SceneTree, i: int) -> Vector3:
	var markers := tree.get_nodes_in_group("spawn_point")
	var base := (markers[0] as Node3D).global_position if markers.size() > 0 else FALLBACK_SPAWN
	if i <= 0:
		return base
	var a := float(i) * 2.3999632 # golden angle, so the ring never repeats a spot
	return base + Vector3(cos(a), 0, sin(a)) * SPAWN_RING

## Is this pawn actually standing at that NPC? Used by the shop counter, the
## quest giver and the gift giver alike — a conversation is LOCAL, so being in
## reach of the NPC is the only part of one the server can verify at all. The
## position is the server's own copy, which is already speed-validated, so this
## cannot be spoofed.
static func near_npc(tree: SceneTree, pawn_node: Node, dialog_id: String, slack: float) -> bool:
	if pawn_node == null:
		return false
	for npc in tree.get_nodes_in_group("npc_interactable"):
		if not is_instance_valid(npc) or npc.dialog_id != dialog_id:
			continue
		if pawn_node.global_position.distance_to(npc.global_position) <= float(npc.interact_range) + slack:
			return true
	return false
