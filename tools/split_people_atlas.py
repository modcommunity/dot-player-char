"""Gives parts that share an atlas swatch with another role their own swatch pixel.

    python3 -I tools/split_people_atlas.py addons/dot_player_char/people

`DotHumanoidAssets.WEARS` tints by colour, but a few swatches are painted on two parts (sam's
b2b2b2 is his top and his shoes). Run after `build_people.py`: for each SPLITS entry the vertices
whose strongest bone matches move their UV to a pixel in the unused bottom edge of the atlas,
painted `new`. List `new` in WEARS to tint it, leave it out to keep the painted colour. It must be
more than ~0.05 away from every WEARS colour of that body, or the shader matches it too. Idempotent.
Pure Python (Pillow, numpy) so it needs neither Blender nor the Quaternius kit.
"""
import json, os, struct, sys
import numpy as np
from PIL import Image

# (body, swatch, bones whose strongest-weight vertices move, new swatch)
SPLITS = [
	("sam", "b2b2b2", ("Foot", "LowerLeg", "UpperLeg"), "a2a2a2"),
	("shaun", "5f4009", ("Foot", "LowerLeg", "UpperLeg"), "6f4f19"),
	("shaun", "4e694b", ("Foot", "LowerLeg", "UpperLeg", "Hips"), "5a8a5a"),
	("shaun", "a58a3b", ("Foot", "LowerLeg", "UpperLeg", "Hips"), "b59a4b"),
]
X0, Y = 480, 509  # the pixel row, top-origin; no body's UVs reach below row 50

directory = sys.argv[1]
atlas_path = os.path.join(directory, "atlas_people.png")
atlas = Image.open(atlas_path).convert("RGB")
W, H = atlas.size
for k, (_, _, _, new) in enumerate(SPLITS):
	atlas.putpixel((X0 + k, Y), tuple(int(new[i:i + 2], 16) for i in (0, 2, 4)))
atlas.save(atlas_path)


def view(j, blob, index):
	a = j["accessors"][index]
	bv = j["bufferViews"][a["bufferView"]]
	n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
	dt = np.dtype({5126: "<f4", 5123: "<u2", 5121: "u1", 5125: "<u4"}[a["componentType"]])
	stride = bv.get("byteStride", n * dt.itemsize)
	start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
	raw = np.frombuffer(blob, dtype=np.uint8, count=stride * (a["count"] - 1) + n * dt.itemsize, offset=start)
	out = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], n * dt.itemsize), strides=(stride, 1))
	return start, stride, dt, n, a["count"]


for body in ("matt", "lis", "sam", "shaun"):
	path = os.path.join(directory, "people_%s.glb" % body)
	data = bytearray(open(path, "rb").read())
	jlen = struct.unpack("<I", data[12:16])[0]
	j = json.loads(data[20:20 + jlen])
	blob_at = 20 + jlen + 8
	names = [j["nodes"][n]["name"] for n in j["skins"][0]["joints"]]
	moved = 0
	for mesh in j["meshes"]:
		for prim in mesh["primitives"]:
			at = prim["attributes"]
			uv0, uvs, _, _, count = view(j, data, at["TEXCOORD_0"])
			j0, js, jdt, jn, _ = view(j, data, at["JOINTS_0"])
			w0, ws, wdt, wn, _ = view(j, data, at["WEIGHTS_0"])
			for i in range(count):
				uo = blob_at + uv0 + i * uvs
				u, v = struct.unpack_from("<ff", data, uo)
				jo = blob_at + j0 + i * js
				wo = blob_at + w0 + i * ws
				joints = np.frombuffer(data, dtype=jdt, count=jn, offset=jo)
				weights = np.frombuffer(data, dtype=wdt, count=wn, offset=wo)
				bone = names[joints[int(weights.argmax())]]
				x, y = min(W - 1, int(u * W)), min(H - 1, int(v * H))
				here = "%02x%02x%02x" % atlas.getpixel((x, y))
				for k, (who, old, bones, _) in enumerate(SPLITS):
					if who == body and here == old and any(b in bone for b in bones):
						struct.pack_into("<ff", data, uo, (X0 + k + 0.5) / W, (Y + 0.5) / H)
						moved += 1
						break
	open(path, "wb").write(data)
	print("split", body, "vertices moved", moved)
