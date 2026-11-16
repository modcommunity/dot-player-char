"""Re-rigs prepped Mixamo-named LODs onto the people kit skeleton, as one GLB with all LOD meshes.

    blender -b --factory-startup --python tools/avatar_prep/kit_rig.py -- <kit body.glb> <out dir> <name> [prep config.json]

Reads `<out dir>/<name>_lod0..2.glb` (from prep_avatar.py) and writes `<name>_kit.glb` and
`<name>_kit.webp.glb`: one skeleton with the kit's bone names, hierarchy, rest directions and
rolls, and meshes `LOD0`, `LOD1`, `LOD2` under it. Every people clip, the aim/crouch/leg code, the
own view and the gib roles then work on the avatar unchanged (docs/avatar-prep.md, "Kit rig").

- Scales so the leg (hip joint to ankle) is as long as the kit's: the clips' Body and Foot
  position keys are kit-sized, so equal legs keep the feet on the ground.
- Poses thighs, shins, upper arms and forearms along the kit's rest directions (the military
  A-pose arms go up to the kit T-pose) and bakes that pose into the meshes; feet keep their
  world orientation so the soles stay flat. Spine, shoulders and hands are not bent: the kit's
  bone directions there do not follow its mesh.
- With the prep config's `forearm` (forearm over upper-arm length; absent or 0 keeps the arm as
  modelled), slides each hand and the far part of its forearm along the forearm to that ratio. SWAT's
  wrist joint sits at its long gloves' cuffs, so its forearm was 0.87 of the upper arm (kit 1.39,
  military 1.34): the first-person arm worked near full stretch, where the elbow pops between frames.
- Puts each kit bone at the matching joint with the kit bone's orientation, and remaps the vertex
  groups (MIX_TO_KIT). An unmapped group is an error, not a silent drop.
"""
import bpy, sys, os, json, mathutils, collections

argv = sys.argv[sys.argv.index("--") + 1:]
kit_path, out, name = argv[0], argv[1], argv[2]
CFG = json.load(open(argv[3])) if len(argv) > 3 else {}
FOREARM = float(CFG.get("forearm", 0.0))
if FOREARM < 0.0:
	raise RuntimeError("forearm ratio %s is negative" % FOREARM)
LODS = ("lod0", "lod1", "lod2")
SIDES = (("Left", "L"), ("Right", "R"))
# Kit bone -> Mixamo joint whose head it sits on (None: placed from the kit, never skinned).
KIT_JOINT = {"Root": None, "Body": "Hips", "Hips": "Hips", "Abdomen": "Spine", "Torso": "Spine1",
	"Neck": "Neck", "Head": "Head"}
MIX_TO_KIT = {"Hips": "Hips", "Spine": "Abdomen", "Spine1": "Torso", "Spine2": "Torso", "Neck": "Neck",
	"Head": "Head", "HeadTop_End": "Head"}
BENT = ("UpLeg", "Leg", "Arm", "ForeArm")
for mix, kit in SIDES:
	KIT_JOINT.update({"Shoulder." + kit: mix + "Shoulder", "UpperArm." + kit: mix + "Arm",
		"LowerArm." + kit: mix + "ForeArm", "UpperLeg." + kit: mix + "UpLeg", "LowerLeg." + kit: mix + "Leg",
		"Foot." + kit: mix + "Foot", "PoleTarget." + kit: None,
		"Middle1." + kit: mix + "Hand", "Index1." + kit: mix + "Hand", "Pinky1." + kit: mix + "Hand",
		"Middle2." + kit: mix + "HandMiddle1", "Middle3." + kit: mix + "HandMiddle2",
		"Index2." + kit: mix + "HandIndex1", "Index3." + kit: mix + "HandIndex2",
		"Pinky2." + kit: mix + "HandPinky1", "Pinky3." + kit: mix + "HandPinky2",
		"Thumb1." + kit: mix + "HandThumb1", "Thumb2." + kit: mix + "HandThumb2"})
	MIX_TO_KIT.update({mix + "Shoulder": "Shoulder." + kit, mix + "Arm": "UpperArm." + kit,
		mix + "ForeArm": "LowerArm." + kit, mix + "Hand": "Middle1." + kit, mix + "UpLeg": "UpperLeg." + kit,
		mix + "Leg": "LowerLeg." + kit, mix + "Foot": "Foot." + kit, mix + "ToeBase": "Foot." + kit,
		mix + "Toe_End": "Foot." + kit})
	for finger, first, rest in (("Middle", "Middle2", "Middle3"), ("Index", "Index2", "Index3"),
			("Pinky", "Pinky2", "Pinky3"), ("Ring", "Pinky2", "Pinky3"), ("Thumb", "Thumb1", "Thumb2")):
		MIX_TO_KIT[mix + "Hand" + finger + "1"] = first + "." + kit
		for i in (2, 3, 4):
			MIX_TO_KIT[mix + "Hand" + finger + str(i)] = rest + "." + kit


def read_kit():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=kit_path)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	bones = []
	for b in arm.data.bones:
		m = arm.matrix_world.to_3x3() @ b.matrix_local.to_3x3()
		bones.append({"name": b.name, "parent": b.parent.name if b.parent else None,
			"head": arm.matrix_world @ b.head_local, "y": m.col[1].normalized(), "z": m.col[2].normalized(), "length": b.length})
	return bones


def import_lod(lod):
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=os.path.join(out, "%s_%s.glb" % (name, lod)))
	new = [o for o in bpy.data.objects if o not in before]
	arm = next(o for o in new if o.type == "ARMATURE")
	meshes = [o for o in new if o.type == "MESH" and len(o.vertex_groups) > 0]
	for o in new:
		if o.type == "MESH" and o not in meshes:
			bpy.data.objects.remove(o, do_unlink=True)
	if len(meshes) != 1:
		raise RuntimeError("%s: expected one skinned mesh, got %d" % (lod, len(meshes)))
	return arm, meshes[0]


def bend_to_kit(arm, kit_dir):
	"""Rotates the BENT bones so each segment points the kit's way; returns posed joint heads."""
	pose = arm.pose
	feet = {}
	for mix, _kit in SIDES:
		pb = pose.bones.get(mix + "Foot")
		if pb:
			feet[pb.name] = pb.matrix.to_3x3().copy()
	for mix, kit in SIDES:
		for part, child, kit_bone in (("UpLeg", "Leg", "UpperLeg"), ("Leg", "Foot", "LowerLeg"),
				("Arm", "ForeArm", "UpperArm"), ("ForeArm", "Hand", "LowerArm")):
			bpy.context.view_layer.update()
			pb = pose.bones[mix + part]
			seg = pose.bones[mix + child].head - pb.head
			turn = seg.rotation_difference(kit_dir[kit_bone + "." + kit]).to_matrix().to_4x4()
			h = pb.head.copy()
			pb.matrix = mathutils.Matrix.Translation(h) @ turn @ mathutils.Matrix.Translation(-h) @ pb.matrix
	bpy.context.view_layer.update()
	for n, rot in feet.items():
		pb = pose.bones[n]
		pb.matrix = mathutils.Matrix.Translation(pb.head.copy()) @ rot.to_4x4()
	bpy.context.view_layer.update()
	return {pb.name: pb.head.copy() for pb in pose.bones}


def bake(arm, mesh):
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = mesh
	mesh.select_set(True)
	mod = next(m for m in mesh.modifiers if m.type == "ARMATURE")
	mod.object = arm
	bpy.ops.object.modifier_apply(modifier=mod.name)
	mesh.data.transform(mesh.matrix_world)
	mesh.parent = None
	mesh.matrix_world = mathutils.Matrix.Identity(4)


def forearm_shift(joints):
	"""Per side: the move that puts the wrist FOREARM x the upper arm from the elbow, the elbow, the forearm."""
	shift = {}
	for mix, _kit in SIDES:
		shoulder, elbow, wrist = joints[mix + "Arm"], joints[mix + "ForeArm"], joints[mix + "Hand"]
		fore = wrist - elbow
		shift[mix] = (fore.normalized() * (FOREARM * (elbow - shoulder).length - fore.length), elbow, fore)
	return shift


def stretch_forearms(mesh, shift):
	"""Moves hand-bound weight by the side's shift and forearm-bound weight by its share along the forearm."""
	idx = {vg.index: vg.name for vg in mesh.vertex_groups}
	for v in mesh.data.vertices:
		total = sum(g.weight for g in v.groups)
		if total <= 0.0:
			continue
		move = mathutils.Vector()
		for g in v.groups:
			n = idx[g.group]
			for mix, (d, elbow, fore) in shift.items():
				if n.startswith(mix + "Hand"):
					move += d * g.weight
				elif n == mix + "ForeArm":
					t = min(max((v.co - elbow).dot(fore) / fore.length_squared, 0.0), 1.0)
					move += d * (g.weight * t)
		v.co += move / total


def remap_groups(mesh):
	idx = {vg.index: vg.name for vg in mesh.vertex_groups}
	unknown = sorted(n for n in idx.values() if n not in MIX_TO_KIT)
	if unknown:
		raise RuntimeError("no kit bone for vertex groups %s" % unknown)
	weights = []
	for v in mesh.data.vertices:
		acc = collections.defaultdict(float)
		for g in v.groups:
			acc[MIX_TO_KIT[idx[g.group]]] += g.weight
		weights.append(acc)
	for vg in list(mesh.vertex_groups):
		mesh.vertex_groups.remove(vg)
	groups = {}
	for i, acc in enumerate(weights):
		for n, w in acc.items():
			if n not in groups:
				groups[n] = mesh.vertex_groups.new(name=n)
			groups[n].add([i], w, "REPLACE")


def build_skeleton(kit, joints, s):
	data = bpy.data.armatures.new("Armature")
	arm = bpy.data.objects.new("Armature", data)
	bpy.context.scene.collection.objects.link(arm)
	bpy.ops.object.select_all(action="DESELECT")
	bpy.context.view_layer.objects.active = arm
	arm.select_set(True)
	bpy.ops.object.mode_set(mode="EDIT")
	kit_by = {b["name"]: b for b in kit}
	knee_offset = {}
	for b in kit:
		if b["name"].startswith("PoleTarget."):
			knee_offset[b["name"]] = b["head"] - kit_by["LowerLeg." + b["name"][-1]]["head"]
	heads = {}
	for b in kit:
		n = b["name"]
		if n not in KIT_JOINT:
			raise RuntimeError("kit bone %s has no joint rule" % n)
		j = KIT_JOINT[n]
		if n == "Root":
			heads[n] = mathutils.Vector((0, 0, 0))
		elif n.startswith("PoleTarget."):
			heads[n] = None
		elif j in joints:
			heads[n] = joints[j] * s
		else:
			heads[n] = None
	for b in kit:
		n = b["name"]
		if heads[n] is None:
			if n.startswith("PoleTarget."):
				heads[n] = heads["LowerLeg." + n[-1]] + knee_offset[n]
			else:
				# A trimmed joint (no fingers on a lower LOD source): keep the kit's offset from the parent.
				p = b["parent"]
				heads[n] = heads[p] + (b["head"] - kit_by[p]["head"])
	for b in kit:
		eb = data.edit_bones.new(b["name"])
		eb.head = heads[b["name"]]
		eb.tail = eb.head + b["y"] * b["length"]
		eb.align_roll(b["z"])
		eb.use_deform = True
	for b in kit:
		if b["parent"]:
			data.edit_bones[b["name"]].parent = data.edit_bones[b["parent"]]
	bpy.ops.object.mode_set(mode="OBJECT")
	return arm


def same_image(a, b):
	ia = [n.image for n in a.node_tree.nodes if n.type == "TEX_IMAGE"]
	ib = [n.image for n in b.node_tree.nodes if n.type == "TEX_IMAGE"]
	if len(ia) != 1 or len(ib) != 1 or tuple(ia[0].size) != tuple(ib[0].size):
		return False
	pa, pb = ia[0].pixels[:], ib[0].pixels[:]
	return max(abs(x - y) for x, y in zip(pa[::97], pb[::97])) < 0.08


kit = read_kit()
kit_dir = {b["name"]: b["y"] for b in kit}
kit_by = {b["name"]: b for b in kit}
bpy.ops.wm.read_factory_settings(use_empty=True)
meshes = []
joints = None
report = {"name": name, "lods": {}}
for lod in LODS:
	arm, mesh = import_lod(lod)
	arm.data.pose_position = "POSE"
	posed = bend_to_kit(arm, kit_dir)
	if joints is None:
		joints = posed
		shift = forearm_shift(joints) if FOREARM > 0.0 else {}
	else:
		drift = max((posed[n] - joints[n]).length for n in posed if n in joints)
		if drift > 0.005:
			raise RuntimeError("%s joints differ from lod0 by %.4f m" % (lod, drift))
	bake(arm, mesh)
	bpy.data.objects.remove(arm, do_unlink=True)
	stretch_forearms(mesh, shift)
	remap_groups(mesh)
	mesh.name = mesh.data.name = lod.upper()
	meshes.append(mesh)

for mix, (d, _elbow, _fore) in shift.items():
	for n in list(joints):
		if n.startswith(mix + "Hand"):
			joints[n] = joints[n] + d
	report["forearm_" + mix.lower()] = round((joints[mix + "Hand"] - joints[mix + "ForeArm"]).length
		/ (joints[mix + "ForeArm"] - joints[mix + "Arm"]).length, 3)
kit_leg = (kit_by["UpperLeg.L"]["head"] - kit_by["Foot.L"]["head"]).length
leg = (joints["LeftUpLeg"] - joints["LeftFoot"]).length
s = kit_leg / leg
for m in meshes:
	m.data.transform(mathutils.Matrix.Scale(s, 4))
arm = build_skeleton(kit, joints, s)
shared = meshes[0].data.materials[0]
for m in meshes:
	own = m.data.materials[0]
	if own != shared and same_image(own, shared):
		m.data.materials[0] = shared
	m.parent = arm
	mod = m.modifiers.new("Armature", "ARMATURE")
	mod.object = arm
	report["lods"][m.name] = {"tris": len(m.data.polygons), "material_shared": m.data.materials[0] == shared}
lo = min((v.co.z for v in meshes[0].data.vertices))
hi = max((v.co.z for v in meshes[0].data.vertices))
report.update({"scale": round(s, 5), "height": round(hi - lo, 4), "kit_leg": round(kit_leg, 4), "bones": len(arm.data.bones)})
bpy.ops.object.select_all(action="DESELECT")
for o in [arm] + meshes:
	o.select_set(True)
for fmt, ext in (("JPEG", "glb"), ("WEBP", "webp.glb")):
	p = os.path.join(out, "%s_kit.%s" % (name, ext))
	bpy.ops.export_scene.gltf(filepath=p, export_format="GLB", use_selection=True, export_image_format=fmt,
		export_jpeg_quality=85, export_animations=False, export_skins=True, export_apply=False,
		export_yup=True, export_materials="EXPORT", export_vertex_color="ACTIVE")
	report["size_" + ext] = os.path.getsize(p)
json.dump(report, open(os.path.join(out, "report_%s_kit.json" % name), "w"), indent=1)
print("KIT", json.dumps(report))
