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
	("matt", "af6c1c", ("UpperLeg",), "bf7c2c"),
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


def unseam(body, data):
	"""A triangle with one corner moved to a split's pixel and another left on its old swatch
	samples every texel between the two across the atlas: the white page and its neighbours' dark
	edges, drawn as a jagged white shard at the hips (matt, shaun; avatar-polish judge round 1).
	Each such old corner gets a copy of its vertex on the new pixel for that triangle only, so a
	triangle samples one swatch. Run again it finds no mixed triangle and changes nothing."""
	jlen = struct.unpack("<I", data[12:16])[0]
	j = json.loads(data[20:20 + jlen])
	blen = struct.unpack("<I", data[20 + jlen:24 + jlen])[0]
	blob = bytearray(data[20 + jlen + 8:20 + jlen + 8 + blen])
	pixels = {}
	for k, (who, old, bones, _) in enumerate(SPLITS):
		if who == body:
			pixels[(X0 + k, Y)] = (old, bones)
	names_ = [j["nodes"][n]["name"] for n in j["skins"][0]["joints"]]
	split = 0
	for mesh in j["meshes"]:
		for prim in mesh["primitives"]:
			assert "targets" not in prim, "morph targets are not copied"
			names = sorted(prim["attributes"])
			cols = {}
			for name in names:
				start, stride, dt, n, count = view(j, blob, prim["attributes"][name])
				size = n * dt.itemsize
				rows = np.frombuffer(bytes(blob), dtype=np.uint8, count=stride * (count - 1) + size, offset=start)
				cols[name] = np.lib.stride_tricks.as_strided(rows, shape=(count, size), strides=(stride, 1)).copy()
			istart, _, idt, _, icount = view(j, blob, prim["indices"])
			tris = np.frombuffer(bytes(blob), dtype=idt, count=icount, offset=istart).astype(np.int64).reshape(-1, 3).copy()
			uv = cols["TEXCOORD_0"].view("<f4").reshape(-1, 2)
			px = np.minimum([W - 1, H - 1], (uv * [W, H]).astype(int))
			colour = ["%02x%02x%02x" % atlas.getpixel((int(x), int(y))) for x, y in px]
			bone = strongest(j, prim, cols, names_)
			extra = []  # (vertex copied, its uv in that triangle)
			for t in range(len(tris)):
				corners = [(int(px[v][0]), int(px[v][1])) for v in tris[t]]
				news = [c for c in corners if c in pixels]
				if not news:
					continue
				to = news[0]
				old, bones = pixels[to]
				olds = [c for c in range(3) if corners[c] != to and colour[int(tris[t][c])] == old]
				if not olds:
					continue
				if any(any(b in bone[int(tris[t][c])] for b in bones) for c in olds):
					# A part of the split (a leg): its old corners join the new pixel.
					uv_to, moving = ((to[0] + 0.5) / W, (to[1] + 0.5) / H), olds
				else:
					# A part that keeps the old swatch (a shoulder sharing the belt colour): the
					# split corners go back to it, so arms and hands stay on mapped swatches.
					uv_to = tuple(float(f) for f in uv[int(tris[t][olds[0]])])
					moving = [c for c in range(3) if corners[c] == to]
				for c in moving:
					extra.append((int(tris[t][c]), uv_to))
					tris[t][c] = len(uv) + len(extra) - 1
			if not extra:
				continue
			split += len(extra)
			# Vertices no triangle uses any more go, so a second run (which moves the shoulder
			# copies to the pixel again and copies them back) writes the same file.
			used = np.unique(tris)
			remap = np.full(len(uv) + len(extra), -1, dtype=np.int64)
			remap[used] = np.arange(len(used))
			tris = remap[tris]
			for name in names:
				dup = cols[name][[v for v, _ in extra]].copy()
				if name == "TEXCOORD_0":
					fl = dup.view("<f4").reshape(-1, 2)
					fl[:] = [u for _, u in extra]
				packed = np.concatenate([cols[name], dup])[used].tobytes()
				prim["attributes"][name] = add_accessor(j, blob, prim["attributes"][name], packed, len(used))
			out = tris.ravel().astype("<u4" if tris.max() > 65535 else "<u2")
			prim["indices"] = add_accessor(j, blob, prim["indices"], out.tobytes(), len(out), 5125 if out.dtype.itemsize == 4 else 5123)
	if split == 0:
		return data, 0
	# Drop the accessors and views nothing reads any more, so the file does not carry the replaced copies.
	refs = []  # (holder, key) pairs naming an accessor
	for mesh in j["meshes"]:
		for prim in mesh["primitives"]:
			refs += [(prim["attributes"], k) for k in prim["attributes"]]
			if "indices" in prim:
				refs.append((prim, "indices"))
	refs += [(s, "inverseBindMatrices") for s in j.get("skins", []) if "inverseBindMatrices" in s]
	for anim in j.get("animations", []):
		for s in anim["samplers"]:
			refs += [(s, "input"), (s, "output")]
	keep, accessors = {}, []
	for holder, key in refs:
		old = holder[key]
		if old not in keep:
			keep[old] = len(accessors)
			accessors.append(j["accessors"][old])
		holder[key] = keep[old]
	j["accessors"] = accessors
	users = [a for a in accessors if "bufferView" in a] + [i for i in j.get("images", []) if "bufferView" in i]
	packed, remap, views = bytearray(), {}, []
	for u in users:
		old = u["bufferView"]
		if old not in remap:
			bv = dict(j["bufferViews"][old])
			chunk = blob[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
			packed.extend(b"\0" * (-len(packed) % 4))
			bv["byteOffset"] = len(packed)
			packed.extend(chunk)
			remap[old] = len(views)
			views.append(bv)
		u["bufferView"] = remap[old]
	j["bufferViews"] = views
	blob = packed + b"\0" * (-len(packed) % 4)
	j["buffers"][0]["byteLength"] = len(blob)
	text = json.dumps(j, separators=(",", ":")).encode()
	text += b" " * (-len(text) % 4)
	total = 12 + 8 + len(text) + 8 + len(blob)
	head = struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(text), b"JSON")
	return bytearray(head + text + struct.pack("<I4s", len(blob), b"BIN\x00") + blob), split


def strongest(j, prim, cols, names):
	"""The name of each vertex's most weighted bone."""
	def decode(name):
		a = j["accessors"][prim["attributes"][name]]
		dt = {5126: "<f4", 5123: "<u2", 5121: "u1", 5125: "<u4"}[a["componentType"]]
		return cols[name].view(dt).reshape(len(cols[name]), -1)
	joints, weights = decode("JOINTS_0"), decode("WEIGHTS_0")
	return [names[int(joints[i][int(weights[i].argmax())])] for i in range(len(joints))]


def add_accessor(j, blob, old, payload, count, component=None):
	"""A copy of accessor [old] reading [payload], packed at the end of [blob]; returns its index."""
	blob.extend(b"\0" * (-len(blob) % 4))
	j["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(payload)})
	blob.extend(payload)
	blob.extend(b"\0" * (-len(blob) % 4))
	a = dict(j["accessors"][old])
	a.pop("byteOffset", None)
	a.pop("sparse", None)
	a["bufferView"] = len(j["bufferViews"]) - 1
	a["count"] = count
	if component is not None:
		a["componentType"] = component
		a.pop("min", None)
		a.pop("max", None)
	j["accessors"].append(a)
	return len(j["accessors"]) - 1


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
	data, seamed = unseam(body, data)
	open(path, "wb").write(data)
	print("split", body, "vertices moved", moved, "seam corners split", seamed)
