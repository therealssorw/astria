#!/usr/bin/env python3
"""Convert a Goxel .gox file into the same flavour of glTF that Goxel's own
"Export as glTF" produces, so NPC part models are uniform no matter which
route they took into the project.

Goxel can already export glTF from the GUI; this exists for the parts that
were only ever saved as .gox (and for batch re-exports). The output matches
Goxel's conventions on purpose:

  * one culled mesh -- only voxel faces with an empty neighbour are emitted
  * a 64x64 palette texture of 4x4 tiles, tile i at grid cell (i + 1); every
    vertex's UV points at its tile's centre, so the mesh carries no gradients
    and a part can be recoloured by rewriting palette entries
  * a Z-up -> Y-up root node matrix, mesh node named "Layer.1"

Usage:  python tools/voxel/gox_to_gltf.py <in.gox> <out.gltf>
"""

import base64
import json
import struct
import sys
import zlib

BLOCK = 16          # goxel stores voxels in 16^3 blocks
TILE = 4            # palette tile size in texels
ATLAS = 64          # palette texture is 64x64
FACES = [
    # (normal, the four corner offsets of the quad, wound counter-clockwise)
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]


# --------------------------------------------------------------------------
# PNG (Goxel embeds every voxel block as a PNG, and we emit one for the atlas)
# --------------------------------------------------------------------------

def png_decode(data):
    """Minimal PNG reader -- enough for the 8-bit images Goxel writes."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, plte, trns = 8, b"", None, None
    width = height = depth = color = 0
    while pos < len(data):
        length, kind = struct.unpack_from(">I4s", data, pos)
        chunk = data[pos + 8:pos + 8 + length]
        pos += length + 12
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack_from(">IIBB", chunk, 0)
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"PLTE":
            plte = chunk
        elif kind == b"tRNS":
            trns = chunk
        elif kind == b"IEND":
            break
    assert depth == 8, "only 8-bit PNGs are supported (got %d)" % depth
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    raw = zlib.decompress(idat)
    stride = width * channels
    prev = bytearray(stride)
    rows = []
    at = 0
    for _ in range(height):
        filt = raw[at]
        at += 1
        line = bytearray(raw[at:at + stride])
        at += stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pick = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pick) & 0xFF
        rows.append(line)
        prev = line
    out = []
    for line in rows:
        row = []
        for x in range(width):
            o = x * channels
            if color == 6:
                row.append(tuple(line[o:o + 4]))
            elif color == 2:
                row.append(tuple(line[o:o + 3]) + (255,))
            elif color == 3:
                i = line[o]
                alpha = trns[i] if trns and i < len(trns) else 255
                row.append(tuple(plte[i * 3:i * 3 + 3]) + (alpha,))
            elif color == 0:
                row.append((line[o],) * 3 + (255,))
            else:
                row.append((line[o],) * 3 + (line[o + 1],))
        out.append(row)
    return width, height, out


def png_encode(width, height, pixels):
    """RGBA8 PNG writer (no filtering -- the atlas is 4 KiB of flat colour)."""
    raw = b"".join(b"\x00" + bytes(b for px in row for b in px) for row in pixels)

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


# --------------------------------------------------------------------------
# .gox
# --------------------------------------------------------------------------

def _read_dict(data, pos):
    """Goxel's key/value blob: <int32 len> key <int32 len> value, repeated.

    A zero-length key terminates it, but the last dict in a chunk is simply
    cut off by the chunk end, so stop on either.
    """
    out = {}
    while pos + 4 <= len(data):
        (n,) = struct.unpack_from("<i", data, pos)
        pos += 4
        if n == 0:
            break
        key = data[pos:pos + n].decode("utf8", "replace")
        pos += n
        (m,) = struct.unpack_from("<i", data, pos)
        pos += 4
        out[key] = data[pos:pos + m]
        pos += m
    return out


def read_voxels(path):
    """{(x, y, z): (r, g, b, a)} for every visible voxel in the file."""
    data = open(path, "rb").read()
    assert data[:4] == b"GOX ", "not a .gox file"
    pos = 8
    blocks, layers = [], []
    while pos + 8 <= len(data):
        kind = data[pos:pos + 4]
        (length,) = struct.unpack_from("<i", data, pos + 4)
        body = data[pos + 8:pos + 8 + length]
        pos += length + 12          # 4 type + 4 length + body + 4 crc
        if kind == b"BL16":
            blocks.append(png_decode(body))
        elif kind == b"LAYR":
            (count,) = struct.unpack_from("<i", body, 0)
            at = 4
            entries = []
            for _ in range(count):
                index, bx, by, bz, _pad = struct.unpack_from("<5i", body, at)
                at += 20
                entries.append((index, bx, by, bz))
            layers.append((entries, _read_dict(body, at)))

    voxels = {}
    for entries, meta in layers:
        visible = meta.get("visible")
        if visible is not None and not any(visible):
            continue
        for index, bx, by, bz in entries:
            _w, _h, pixels = blocks[index]
            # A block is 16*16*16 RGBA bytes reinterpreted as a 64x64 image,
            # indexed [z][y][x].
            for i in range(BLOCK ** 3):
                color = pixels[i // ATLAS][i % ATLAS]
                if color[3] == 0:
                    continue
                z, y, x = i // (BLOCK * BLOCK), (i // BLOCK) % BLOCK, i % BLOCK
                voxels[(bx + x, by + y, bz + z)] = color
    return voxels


# --------------------------------------------------------------------------
# meshing
# --------------------------------------------------------------------------

def build_mesh(voxels):
    """Culled surface mesh + the palette it indexes into."""
    palette = []
    tile_of = {}
    for color in voxels.values():
        if color not in tile_of:
            tile_of[color] = len(palette)
            palette.append(color)
    if len(palette) > (ATLAS // TILE) ** 2 - 1:
        raise SystemExit("more than %d distinct colours"
                         % ((ATLAS // TILE) ** 2 - 1))

    positions, normals, uvs, indices = [], [], [], []
    for (x, y, z), color in sorted(voxels.items()):
        tile = tile_of[color] + 1        # tile 0 stays empty, as Goxel leaves it
        u = ((tile % (ATLAS // TILE)) * TILE + TILE / 2.0) / ATLAS
        v = ((tile // (ATLAS // TILE)) * TILE + TILE / 2.0) / ATLAS
        for normal, corners in FACES:
            neighbour = (x + normal[0], y + normal[1], z + normal[2])
            if neighbour in voxels:
                continue
            base = len(positions)
            for dx, dy, dz in corners:
                positions.append((x + dx, y + dy, z + dz))
                normals.append(normal)
                uvs.append((u, v))
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]

    atlas = [[(0, 0, 0, 255)] * ATLAS for _ in range(ATLAS)]
    for i, color in enumerate(palette):
        tile = i + 1
        tx = (tile % (ATLAS // TILE)) * TILE
        ty = (tile // (ATLAS // TILE)) * TILE
        for py in range(ty, ty + TILE):
            for px in range(tx, tx + TILE):
                atlas[py][px] = color
    return positions, normals, uvs, indices, atlas


def write_gltf(path, positions, normals, uvs, indices, atlas):
    def data_uri(blob):
        return "data:application/octet-stream;base64," + base64.b64encode(blob).decode()

    pos_blob = b"".join(struct.pack("<3f", *p) for p in positions)
    nrm_blob = b"".join(struct.pack("<3f", *n) for n in normals)
    uv_blob = b"".join(struct.pack("<2f", *t) for t in uvs)
    idx_blob = b"".join(struct.pack("<I", i) for i in indices)
    png_blob = png_encode(ATLAS, ATLAS, atlas)

    doc = {
        "asset": {"generator": "astria gox_to_gltf", "version": "2.0"},
        "buffers": [
            {"uri": data_uri(png_blob), "byteLength": len(png_blob)},
            {"uri": data_uri(pos_blob + nrm_blob + uv_blob), "byteLength":
                len(pos_blob) + len(nrm_blob) + len(uv_blob)},
            {"uri": data_uri(idx_blob), "byteLength": len(idx_blob)},
        ],
        "bufferViews": [
            {"buffer": 0, "byteLength": len(png_blob)},
            {"buffer": 1, "byteLength": len(pos_blob)},
            {"buffer": 1, "byteOffset": len(pos_blob), "byteLength": len(nrm_blob)},
            {"buffer": 1, "byteOffset": len(pos_blob) + len(nrm_blob),
             "byteLength": len(uv_blob)},
            {"buffer": 2, "byteLength": len(idx_blob)},
        ],
        "accessors": [
            {"bufferView": 1, "componentType": 5126, "type": "VEC3",
             "count": len(positions),
             "min": [min(p[i] for p in positions) for i in range(3)],
             "max": [max(p[i] for p in positions) for i in range(3)]},
            {"bufferView": 2, "componentType": 5126, "type": "VEC3",
             "count": len(normals)},
            {"bufferView": 3, "componentType": 5126, "type": "VEC2",
             "count": len(uvs)},
            {"bufferView": 4, "componentType": 5125, "type": "SCALAR",
             "count": len(indices)},
        ],
        "images": [{"bufferView": 0, "mimeType": "image/png"}],
        "textures": [{"source": 0}],
        "materials": [{
            "name": "Material.1",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicFactor": 0.2,
                "roughnessFactor": 0.5,
            },
        }],
        "meshes": [{"primitives": [{
            "indices": 3,
            "material": 0,
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
        }]}],
        # Goxel models are Z-up; this is the same root matrix its exporter writes.
        "nodes": [
            {"children": [1], "matrix": [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1]},
            {"mesh": 0, "name": "Layer.1"},
        ],
        "scenes": [{"nodes": [0]}],
        "scene": 0,
    }
    with open(path, "w", encoding="utf8") as f:
        json.dump(doc, f, indent=2)


def main(argv):
    if len(argv) != 3:
        raise SystemExit(__doc__.strip().splitlines()[-1])
    voxels = read_voxels(argv[1])
    if not voxels:
        raise SystemExit("%s has no visible voxels" % argv[1])
    positions, normals, uvs, indices, atlas = build_mesh(voxels)
    write_gltf(argv[2], positions, normals, uvs, indices, atlas)
    lo = [min(v[i] for v in voxels) for i in range(3)]
    hi = [max(v[i] for v in voxels) for i in range(3)]
    print("%s -> %s : %d voxels, %d tris, bounds %s..%s"
          % (argv[1], argv[2], len(voxels), len(indices) // 3, lo, hi))


if __name__ == "__main__":
    main(sys.argv)
