"""Slims a rigged humanoid GLB (Mixamo-named skeleton) into web-ready, 64-player-budget avatars.

    blender -b --factory-startup --python tools/avatar_prep/prep_avatar.py -- <config.json> <source.glb> <out dir>

The source asset is private and never committed: this script and the configs beside it are the
whole recipe (docs/avatar-prep.md has the numbers and the reasons). Per LOD in the config:

- Drops what FC does not draw (hand-held weapon, eyebrows, eyelashes: tiny alpha-blended meshes
  that would cost a second pass), by material name.
- Renames every bone to the canonical Mixamo name (no `mixamorig:` prefix, no exporter `_N` suffix),
  so every Mixamo-rigged avatar shares one bone map (`mixamo_bone_map.json`).
- Scales to `height` metres, feet on y=0, hips on the origin axis. Source clips are dropped:
  FC retargets its own set; Mixamo-derived clips stay in the private folder.
- Trims the skeleton per LOD (`fingers` drops ring finger and tip joints, `core` drops all fingers),
  moving each dropped bone's skin weight to its nearest kept parent.
- Cuts skin faces hidden under clothing (`covered`), so a decimated clothing shell cannot show the body.
- Decimates meshes to the LOD triangle budget (meshes under `small` triangles are kept whole;
  `shares` gives a material a fixed fraction of the budget).
- Bakes `dye` into the vertex colour by material: red is how far the team tint may dye it, green
  1 keeps the runtime's warm-is-skin test (a tan vest would read as skin and stay undyed).
  Unlisted materials get white: dyed, skin test on, as on a body with no vertex colour.
- Packs every material's base-colour image into ONE atlas and joins the meshes: one material per
  LOD, so a team's 64 bodies batch. UVs must lie in 0..1.
- Exports `<name>_<lod>.glb` (JPEG atlas) and `.webp.glb`, plus first-person arms for LODs with `arms`.
- Writes `report_<name>.json` (triangles, bones, sizes, gib-cut straddle share).
"""
import bpy, sys, os, json, mathutils, collections
from array import array

argv = sys.argv[sys.argv.index("--") + 1:]
cfg = json.load(open(argv[0]))
src, out = argv[1], argv[2]
os.makedirs(out, exist_ok=True)


def canon(name):
	"""'mixamorig:Hips_63' and 'Hips_64' both become 'Hips'."""
	n = name.split(":")[-1]
	parts = n.rsplit("_", 1)
	if len(parts) == 2 and parts[1].isdigit():
		n = parts[0]
	return n


def role_of(bone):
	"""Gib role of a canonical Mixamo bone name (docs/gibbable-avatars.md)."""
	for side in ("Left", "Right"):
		if bone.startswith(side):
			if bone[len(side):].startswith(("Shoulder", "Arm", "ForeArm", "Hand")):
				return "arm_" + side[0].lower()
			return "leg_" + side[0].lower()
	if bone in ("Head", "HeadTop_End"):
		return "head"
	return "torso"


def is_finger(bone):
	return "Hand" in bone and bone not in ("LeftHand", "RightHand")


def drops(bone, mode):
	if bone in ("GLTF_created_0_rootJoint", "HeadTop_End") or bone.endswith("Toe_End"):
		return True
	if is_finger(bone):
		return mode == "core" or bone.endswith("4") or "Ring" in bone
	return False


def clean_import():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=src)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	arm.animation_data_clear()
	arm.data.pose_position = "REST"
	for a in list(bpy.data.actions):
		bpy.data.actions.remove(a)
	meshes = []
	for o in list(bpy.data.objects):
		if o.type != "MESH":
			continue
		mats = [m.name for m in o.data.materials]
		if len(o.vertex_groups) == 0 or any(m in cfg["drop_materials"] for m in mats):
			bpy.data.objects.remove(o, do_unlink=True)
		else:
			meshes.append(o)
	return arm, meshes


def normalise(arm, meshes):
	"""Canonical names, world-space geometry, scale to height, feet on 0, centred on the hips."""
	bpy.context.view_layer.update()
	for o in meshes:
		mw = o.matrix_world.copy()
		o.parent = None
		o.matrix_world = mw
	lo = [1e9] * 3
	hi = [-1e9] * 3
	for o in meshes:
		for v in o.data.vertices:
			w = o.matrix_world @ v.co
			for i in range(3):
				lo[i] = min(lo[i], w[i])
				hi[i] = max(hi[i], w[i])
	s = cfg["height"] / (hi[2] - lo[2])
	hips = next(b for b in arm.data.bones if canon(b.name) == "Hips")
	hc = arm.matrix_world @ hips.head_local
	m = mathutils.Matrix.Scale(s, 4) @ mathutils.Matrix.Translation((-hc.x, -hc.y, -lo[2]))
	for o in meshes:
		o.data.transform(m @ o.matrix_world)
		o.matrix_world = mathutils.Matrix.Identity(4)
		for vg in o.vertex_groups:
			vg.name = canon(vg.name)
	bpy.context.view_layer.objects.active = arm
	arm.select_set(True)
	bpy.ops.object.mode_set(mode="EDIT")
	aw = arm.matrix_world
	for eb in arm.data.edit_bones:
		h = m @ (aw @ eb.head)
		t = m @ (aw @ eb.tail)
		eb.head, eb.tail = h, t
	bpy.ops.object.mode_set(mode="OBJECT")
	arm.matrix_world = mathutils.Matrix.Identity(4)
	for b in arm.data.bones:
		b.name = canon(b.name)
	for o in meshes:
		o.parent = arm
		o.matrix_parent_inverse = mathutils.Matrix.Identity(4)
		for mod in list(o.modifiers):
			o.modifiers.remove(mod)
		mod = o.modifiers.new("Armature", "ARMATURE")
		mod.object = arm
	return s


def trim_skeleton(arm, meshes, mode):
	names = [b.name for b in arm.data.bones]
	if mode == "arms":
		keep = {"Hips", "Spine", "Spine1", "Spine2"} | {n for n in names if role_of(n).startswith("arm") and not drops(n, "fingers")}
		gone = {n for n in names if n not in keep}
	else:
		gone = {n for n in names if drops(n, mode)}
	kept_parent = {}
	for n in gone:
		p = arm.data.bones[n].parent
		while p is not None and p.name in gone:
			p = p.parent
		kept_parent[n] = p.name if p else "Hips"
	for o in meshes:
		idx = {vg.index: vg.name for vg in o.vertex_groups}
		for v in o.data.vertices:
			acc = collections.defaultdict(float)
			touched = False
			for g in v.groups:
				n = idx[g.group]
				if n in gone:
					acc[kept_parent[n]] += g.weight
					touched = True
				else:
					acc[n] += g.weight
			if touched:
				for n in {idx[g.group] for g in v.groups}:
					o.vertex_groups[n].remove([v.index])
				for n, w in acc.items():
					o.vertex_groups[n].add([v.index], w, "REPLACE")
		for n in gone:
			if n in o.vertex_groups:
				o.vertex_groups.remove(o.vertex_groups[n])
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	for n in gone:
		eb = arm.data.edit_bones.get(n)
		if eb:
			arm.data.edit_bones.remove(eb)
	bpy.ops.object.mode_set(mode="OBJECT")


def cull_covered(meshes):
	"""Deletes skin faces that clothing covers (config `covered`), before decimation.

	A collapsed clothing shell at LOD1/2 otherwise shows the full body underneath. A face goes when
	a ray out along each of its vertex normals meets a covering mesh within `reach` metres."""
	import bmesh
	from mathutils.bvhtree import BVHTree
	rule = cfg.get("covered")
	if not rule:
		return 0
	under = [o for o in meshes if any(m.name in rule["under"] for m in o.data.materials)]
	cover = [o for o in meshes if o not in under]
	trees = [BVHTree.FromPolygons([v.co.copy() for v in o.data.vertices], [tuple(p.vertices) for p in o.data.polygons]) for o in cover]
	reach = rule["reach"]
	gone = 0
	for o in under:
		hidden = []
		for v in o.data.vertices:
			n = v.normal
			start = v.co + n * 0.002
			hidden.append(any(t.ray_cast(start, n, reach)[0] is not None for t in trees))
		bm = bmesh.new()
		bm.from_mesh(o.data)
		dead = [f for f in bm.faces if all(hidden[v.index] for v in f.verts)]
		gone += len(dead)
		bmesh.ops.delete(bm, geom=dead, context="FACES")
		bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
		bm.to_mesh(o.data)
		bm.free()
	return gone


def decimate(meshes, target):
	"""Meshes at or under `small` triangles stay whole; the rest share what is left.

	`shares` gives a material's meshes a fixed fraction of the budget (a 38k-triangle helmet would
	otherwise take three quarters of every LOD and leave the limbs as slivers)."""
	tris = {o: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes}
	small = {o for o in meshes if tris[o] <= cfg["small"]}
	left = target - sum(tris[o] for o in small)
	big = sum(tris[o] for o in meshes if o not in small)
	if left < 0.25 * big:
		small = set()
		left, big = target, sum(tris.values())
	shares = cfg.get("shares", {})
	share_of = {o: next((shares[m.name] for m in o.data.materials if m.name in shares), None) for o in meshes}
	fixed = {}
	for o in meshes:
		if o not in small and share_of[o] is not None:
			fixed[o] = share_of[o] * target
	rest_tris = sum(tris[o] for o in meshes if o not in small and o not in fixed)
	rest_left = left - sum(fixed.values())
	for o in meshes:
		if o in small:
			continue
		ratio = fixed[o] / tris[o] if o in fixed else (rest_left / rest_tris if rest_tris > 0 else 1.0)
		ratio = max(0.02, min(1.0, ratio))
		if ratio >= 0.999:
			continue
		bpy.context.view_layer.objects.active = o
		mod = o.modifiers.new("Decimate", "DECIMATE")
		mod.ratio = ratio
		mod.use_collapse_triangulate = True
		bpy.ops.object.modifier_move_to_index(modifier="Decimate", index=0)
		bpy.ops.object.modifier_apply(modifier="Decimate")


def bake_dye(meshes):
	dye = cfg.get("dye")
	if not dye:
		return
	for o in meshes:
		name = o.data.materials[0].name
		col = (dye[name], 0.0, 0.0, 1.0) if name in dye else (1.0, 1.0, 1.0, 1.0)
		attr = o.data.color_attributes.new("Color", "BYTE_COLOR", "CORNER")
		for d in attr.data:
			d.color = col
		o.data.color_attributes.active_color = attr


def base_image(mat):
	for nd in mat.node_tree.nodes:
		if nd.type == "TEX_IMAGE" and nd.image and any(l.to_socket.name == "Base Color" for oo in nd.outputs for l in oo.links):
			return nd.image
	return None


def build_atlas(meshes, size):
	"""One atlas of every material's base-colour image; each mesh's UVs moved into its cell."""
	cells = cfg["atlas_cells"]
	mats = {o.data.materials[0].name: o.data.materials[0] for o in meshes}
	order = sorted(mats, key=lambda n: -cells.get(n, 256))
	x = y = row = 0
	place = {}
	for n in order:
		c = cells.get(n, 256) * size // 1024
		if x + c > size:
			x, y, row = 0, y + row, 0
		place[n] = (x, y, c)
		x += c
		row = max(row, c)
	h2 = 1
	while h2 < y + row:
		h2 *= 2
	buf = array("f", [0.5, 0.5, 0.5, 1.0]) * (size * h2)
	for n, (px, py, c) in place.items():
		tex = base_image(mats[n])
		if tex is None:
			continue
		im = tex.copy()
		im.scale(c, c)
		a = array("f", [0.0]) * (c * c * 4)
		im.pixels.foreach_get(a)
		for r in range(c):
			o = ((py + r) * size + px) * 4
			buf[o:o + c * 4] = a[r * c * 4:(r + 1) * c * 4]
			for k in range(3, c * 4, 4):
				buf[o + k] = 1.0
		bpy.data.images.remove(im)
	img = bpy.data.images.new("team_atlas", size, h2, alpha=False)
	img.pixels.foreach_set(buf)
	img.pack()
	mat = bpy.data.materials.new("team_atlas")
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	t = mat.node_tree.nodes.new("ShaderNodeTexImage")
	t.image = img
	mat.node_tree.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.85
	for o in meshes:
		px, py, c = place[o.data.materials[0].name]
		uvl = o.data.uv_layers[0]
		for l in o.data.loops:
			u, v = uvl.data[l.index].uv
			u = min(max(u, 0.0), 1.0)
			v = min(max(v, 0.0), 1.0)
			uvl.data[l.index].uv = ((px + u * c) / size, (py + v * c) / h2)
		while len(o.data.uv_layers) > 1:
			o.data.uv_layers.remove(o.data.uv_layers[1])
		o.data.materials.clear()
		o.data.materials.append(mat)
	return (size, h2)


def join(meshes, arm):
	bpy.ops.object.select_all(action="DESELECT")
	for o in meshes:
		o.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	bpy.ops.object.join()
	body = bpy.context.view_layer.objects.active
	body.name = "Body"
	body.data.name = "Body"
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.mesh.quads_convert_to_tris()
	bpy.ops.object.mode_set(mode="OBJECT")
	arm.name = "Armature"
	return body


def dominant_roles(body):
	idx = {vg.index: vg.name for vg in body.vertex_groups}
	dom = []
	for v in body.data.vertices:
		best = max(v.groups, key=lambda g: g.weight) if v.groups else None
		dom.append(role_of(idx[best.group]) if best else "torso")
	return dom


def keep_arm_triangles(body):
	import bmesh
	dom = dominant_roles(body)
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bm.faces.ensure_lookup_table()
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if not all(dom[v.index].startswith("arm") for v in f.verts)], context="FACES")
	loose = [v for v in bm.verts if not v.link_faces]
	bmesh.ops.delete(bm, geom=loose, context="VERTS")
	bm.to_mesh(body.data)
	bm.free()


def gib_report(body):
	"""Share of triangles whose vertices disagree on gib role (a straddling triangle is cut open)."""
	dom = dominant_roles(body)
	counts = collections.Counter()
	mixed = 0
	for p in body.data.polygons:
		rs = collections.Counter(dom[i] for i in p.vertices)
		if len(rs) > 1:
			mixed += 1
		counts[rs.most_common(1)[0][0]] += 1
	n = max(1, len(body.data.polygons))
	return {"tris_by_role": dict(counts), "straddling_tris": mixed, "straddle_share": round(mixed / n, 4)}


def export(path, objs, fmt):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_image_format=fmt,
		export_jpeg_quality=cfg.get("jpeg_quality", 85), export_animations=False, export_skins=True,
		export_apply=False, export_yup=True, export_materials="EXPORT", export_vertex_color="ACTIVE")


report = {"name": cfg["name"], "lods": {}}
for lod in cfg["lods"]:
	arm, meshes = clean_import()
	s = normalise(arm, meshes)
	trim_skeleton(arm, meshes, lod["skeleton"])
	culled = cull_covered(meshes)
	decimate(meshes, lod["tris"])
	bake_dye(meshes)
	size = build_atlas(meshes, lod["atlas"])
	body = join(meshes, arm)
	over = len(body.data.polygons)
	if over > lod["tris"] * 1.1:
		# Per-mesh collapse stalls on shells that must stay closed; one more pass over the joined mesh reaches the budget.
		bpy.context.view_layer.objects.active = body
		mod = body.modifiers.new("Decimate", "DECIMATE")
		mod.ratio = lod["tris"] / over
		mod.use_collapse_triangulate = True
		bpy.ops.object.modifier_move_to_index(modifier="Decimate", index=0)
		bpy.ops.object.modifier_apply(modifier="Decimate")
	entry = {"scale_applied": round(s, 5), "covered_faces_cut": culled, "tris": len(body.data.polygons), "verts": len(body.data.vertices),
		"bones": len(arm.data.bones), "atlas": list(size), "gib": gib_report(body)}
	for fmt, ext in (("JPEG", "glb"), ("WEBP", "webp.glb")):
		p = os.path.join(out, "%s_%s.%s" % (cfg["name"], lod["name"], ext))
		export(p, [arm, body], fmt)
		entry["size_" + ext] = os.path.getsize(p)
	if lod.get("arms"):
		bpy.context.view_layer.objects.active = body
		keep_arm_triangles(body)
		trim_skeleton(arm, [body], "arms")
		entry["arms_tris"] = len(body.data.polygons)
		entry["arms_bones"] = len(arm.data.bones)
		p = os.path.join(out, "%s_%s_fp_arms.glb" % (cfg["name"], lod["name"]))
		export(p, [arm, body], "JPEG")
		entry["arms_size"] = os.path.getsize(p)
	report["lods"][lod["name"]] = entry
	print("LOD", cfg["name"], lod["name"], entry)
json.dump(report, open(os.path.join(out, "report_%s.json" % cfg["name"]), "w"), indent=1)
