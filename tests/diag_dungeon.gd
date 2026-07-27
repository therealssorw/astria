extends Node3D

const DUNGEON := "res://scenes/starterDungeon.tscn"
const CELL := 2.0

func _ready() -> void:
    var d: Node3D = (load(DUNGEON) as PackedScene).instantiate()
    add_child(d)
    await get_tree().physics_frame
    await get_tree().physics_frame
    var mi := _find_mesh(d.get_node("dungeon1"))
    var ab: AABB = mi.mesh.get_aabb()
    var g: Transform3D = mi.global_transform
    var lo: Vector3 = g * ab.position
    var hi: Vector3 = g * ab.end
    var walls: Array[RID] = []
    for n in _all(d.get_node("dungeon1/Walls")):
        if n is CollisionObject3D:
            walls.append((n as CollisionObject3D).get_rid())
    var space := get_world_3d().direct_space_state
    var nx := int((hi.x - lo.x) / CELL) + 1
    var nz := int((hi.z - lo.z) / CELL) + 1
    # visual surface height from the triangles themselves, facing ignored
    var tris := _tris(mi)
    var vis := {}
    for t in tris:
        var a: Vector3 = t[0]
        var b: Vector3 = t[1]
        var c: Vector3 = t[2]
        var x0 := mini(nx - 1, maxi(0, int((minf(a.x, minf(b.x, c.x)) - lo.x) / CELL)))
        var x1 := mini(nx - 1, maxi(0, int((maxf(a.x, maxf(b.x, c.x)) - lo.x) / CELL)))
        var z0 := mini(nz - 1, maxi(0, int((minf(a.z, minf(b.z, c.z)) - lo.z) / CELL)))
        var z1 := mini(nz - 1, maxi(0, int((maxf(a.z, maxf(b.z, c.z)) - lo.z) / CELL)))
        for i in range(x0, x1 + 1):
            for j in range(z0, z1 + 1):
                var p := Vector2(lo.x + (float(i) + 0.5) * CELL, lo.z + (float(j) + 0.5) * CELL)
                var y = _height_at(a, b, c, p)
                if y == null:
                    continue
                var k := Vector2i(i, j)
                if not vis.has(k) or y > vis[k]:
                    vis[k] = y
    var front := {}
    var back := {}
    for i in nx:
        for j in nz:
            var x: float = lo.x + (float(i) + 0.5) * CELL
            var z: float = lo.z + (float(j) + 0.5) * CELL
            var from := Vector3(x, hi.y + 2.0, z)
            var to := Vector3(x, lo.y - 2.0, z)
            var qf := PhysicsRayQueryParameters3D.create(from, to)
            qf.exclude = walls
            qf.hit_back_faces = false
            var hf := space.intersect_ray(qf)
            if not hf.is_empty():
                front[Vector2i(i, j)] = hf.position.y
            var qb := PhysicsRayQueryParameters3D.create(from, to)
            qb.exclude = walls
            qb.hit_back_faces = true
            var hb := space.intersect_ray(qb)
            if not hb.is_empty():
                back[Vector2i(i, j)] = hb.position.y
    var only_back := 0
    var sink := 0
    var worst := 0.0
    var no_solid := 0
    for k in vis:
        if not back.has(k) and not front.has(k):
            no_solid += 1
            continue
        if not front.has(k):
            only_back += 1
            continue
        var drop: float = vis[k] - front[k]
        if drop > 0.25:
            sink += 1
            worst = maxf(worst, drop)
    print("DIAG cells with visible floor=%d" % vis.size())
    print("DIAG   nothing solid at all=%d" % no_solid)
    print("DIAG   solid only from BELOW (inverted face, you see it and fall through)=%d" % only_back)
    print("DIAG   you stand LOWER than what you see (sink) =%d worst=%.2f m" % [sink, worst])
    print("DIAG map: '#'=stand on what you see  'v'=sink  'B'=inverted  'X'=no collision  '.'=no floor")
    for j in nz:
        var line := ""
        for i in nx:
            var k := Vector2i(i, j)
            if not vis.has(k):
                line += "."
            elif not front.has(k) and not back.has(k):
                line += "X"
            elif not front.has(k):
                line += "B"
            elif vis[k] - front[k] > 0.25:
                line += "v"
            else:
                line += "#"
        print("DIAG |" + line)
    print("DIAG done")
    get_tree().quit()

func _height_at(a: Vector3, b: Vector3, c: Vector3, p: Vector2):
    var a2 := Vector2(a.x, a.z)
    var b2 := Vector2(b.x, b.z)
    var c2 := Vector2(c.x, c.z)
    var den := (b2.y - c2.y) * (a2.x - c2.x) + (c2.x - b2.x) * (a2.y - c2.y)
    if absf(den) < 1e-9:
        return null
    var w1 := ((b2.y - c2.y) * (p.x - c2.x) + (c2.x - b2.x) * (p.y - c2.y)) / den
    var w2 := ((c2.y - a2.y) * (p.x - c2.x) + (a2.x - c2.x) * (p.y - c2.y)) / den
    var w3 := 1.0 - w1 - w2
    if w1 < -0.001 or w2 < -0.001 or w3 < -0.001:
        return null
    return a.y * w1 + b.y * w2 + c.y * w3

func _tris(mi: MeshInstance3D) -> Array:
    var out: Array = []
    var arr := mi.mesh.surface_get_arrays(0)
    var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
    var g: Transform3D = mi.global_transform
    for t in idx.size() / 3:
        out.append([g * v[idx[t * 3]], g * v[idx[t * 3 + 1]], g * v[idx[t * 3 + 2]]])
    return out

func _all(n: Node) -> Array:
    var out: Array = [n]
    for c in n.get_children():
        out.append_array(_all(c))
    return out

func _find_mesh(n: Node) -> MeshInstance3D:
    if n is MeshInstance3D and (n as MeshInstance3D).mesh:
        return n as MeshInstance3D
    for c in n.get_children():
        var r := _find_mesh(c)
        if r != null:
            return r
    return null