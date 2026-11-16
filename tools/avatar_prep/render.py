"""Renders LOD0/1/2 side by side (textured, then gib-role colours) and prints measured heights.
blender -b --python render.py -- <out dir> <name> <png prefix>"""
import bpy, sys, os, mathutils, math
out, name, prefix = sys.argv[sys.argv.index("--") + 1:][:3]
COL = {"head": (1, .9, .1), "torso": (.2, .4, 1), "arm_l": (1, .2, .2), "arm_r": (.2, 1, .2), "leg_l": (1, .2, 1), "leg_r": (.1, 1, 1)}
def role(b):
	for side in ("Left", "Right"):
		if b.startswith(side):
			return ("arm_" if b[len(side):].startswith(("Shoulder", "Arm", "ForeArm", "Hand")) else "leg_") + side[0].lower()
	return "head" if b == "Head" else "torso"
def build(colour):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bodies = []
	for i, lod in enumerate(("lod0", "lod1", "lod2")):
		before = set(bpy.data.objects)
		bpy.ops.import_scene.gltf(filepath=os.path.join(out, "%s_%s.glb" % (name, lod)))
		new = [o for o in bpy.data.objects if o not in before]
		for o in new:
			if o.type == "ARMATURE":
				o.location.x += (i - 1) * 1.2
			if o.type == "MESH":
				bodies.append(o)
				zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
		print("HEIGHT", name, lod, round(max(zs) - min(zs), 3), "min z", round(min(zs), 3), flush=True)
	if colour:
		for o in bodies:
			idx = {vg.index: vg.name for vg in o.vertex_groups}
			attr = o.data.color_attributes.new("r", "FLOAT_COLOR", "POINT")
			for v in o.data.vertices:
				g = max(v.groups, key=lambda g: g.weight) if v.groups else None
				attr.data[v.index].color = COL[role(idx[g.group]) if g else "torso"] + (1,)
	cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); bpy.context.scene.collection.objects.link(cam)
	cam.location = (0, -6.5, 0.9); cam.rotation_euler = (math.pi / 2, 0, 0); cam.data.lens = 40
	bpy.context.scene.camera = cam
	s = bpy.context.scene; s.render.engine = "BLENDER_WORKBENCH"; s.render.resolution_x = 1500; s.render.resolution_y = 800
	sh = s.display.shading; sh.light = "STUDIO"; sh.color_type = "VERTEX" if colour else "TEXTURE"
	s.render.filepath = prefix + ("_gib.png" if colour else "_tex.png")
	bpy.ops.render.render(write_still=True)
build(False); build(True)
