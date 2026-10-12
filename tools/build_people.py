"""Builds addons/dot_player_char/people/ from Quaternius' Zombie Apocalypse Kit (CC0 1.0).

    blender -b --factory-startup --python tools/build_people.py -- <kit glTF dir> addons/dot_player_char/people

The kit is not vendored: download its `Characters/glTF` folder from
https://quaternius.com/packs/zombieapocalypsekit.html (CC0 1.0, by Quaternius) and point the first
argument at it. It is the family's people because its zombies are game-zombie-zone's, on the same
rig: a survivor and the zombie chasing them are one style, and one ragdoll and one clip set serve
both (docs/people.md). What this does, and why:

- Keeps each survivor's one skinned mesh and drops the eleven weapons on its finger bone (a game
  hangs its own weapon on the hand) and the importer's hidden bone-display icosphere.
- Decimates to 55% (three to five thousand triangles): a person is seen closer than a zombie in
  a crowd, so more is kept than game-zombie-zone's 35%, and Godot's generated LODs take it down
  with distance.
- Keeps the clips on `matt` only, renamed to the family's names, plus the zombie's crawl (same
  bone names, so the action binds as it is) for a downed player. Every other body plays matt's
  clips through `DotHumanoidClips.retarget`, so four bodies carry one clip set.
- Writes the atlas the survivors share once, as `atlas_people.png`, and exports without images:
  `DotHumanoidPalette` draws every body through one shader that swaps the atlas colours for a
  look's colours.
"""
import bpy, sys, os

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
os.makedirs(out, exist_ok=True)

CLIPS = {"Death": "death", "Duck": "duck", "HitReact": "hit", "Idle": "idle", "Idle_Gun": "idle_gun",
	"Jump": "jump", "Jump_Idle": "fall", "Jump_Land": "land", "No": "no", "Punch": "punch", "Run": "run",
	"Run_Gun": "run_gun", "Run_Slash": "run_slash", "Run_Stab": "run_stab", "Slash": "slash", "Stab": "stab",
	"Walk": "walk", "Walk_Gun": "walk_gun", "Wave": "wave", "Yes": "yes", "Crawl": "crawl"}

BODIES = [("matt", "Characters_Matt", True), ("lis", "Characters_Lis", False),
	("sam", "Characters_Sam", False), ("shaun", "Characters_Shaun", False)]

RATIO = 0.55


def base_name(action):
	for suffix in ("_CharacterArmature", "_ZombieArmature", "_Armature"):
		if action.name.endswith(suffix):
			return action.name[: -len(suffix)]
	return action.name


for name, file, own_anims in BODIES:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	crawl = None
	if own_anims:
		# The zombie's crawl, taken before the survivor is imported: a downed player crawls.
		bpy.ops.import_scene.gltf(filepath=os.path.join(src, "Zombie_Basic.gltf"))
		for a in bpy.data.actions:
			if base_name(a) == "Crawl":
				crawl = a
				crawl.name = "crawl"
				crawl.use_fake_user = True
		for o in list(bpy.data.objects):
			bpy.data.objects.remove(o, do_unlink=True)
		for a in list(bpy.data.actions):
			if a != crawl:
				bpy.data.actions.remove(a)

	bpy.ops.import_scene.gltf(filepath=os.path.join(src, file + ".gltf"))
	arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]

	if name == "matt":
		for img in bpy.data.images:
			if img.size[0] > 0:
				img.filepath_raw = os.path.join(out, "atlas_people.png")
				img.file_format = "PNG"
				img.save()
				break

	for o in list(bpy.data.objects):
		if o.type == "MESH" and (not o.visible_get() or o.parent_type == "BONE"
				or not any(m.type == "ARMATURE" for m in o.modifiers)):
			bpy.data.objects.remove(o, do_unlink=True)

	meshes = [o for o in bpy.data.objects if o.type == "MESH"]
	bpy.ops.object.select_all(action="DESELECT")
	for m in meshes:
		m.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	body = bpy.context.view_layer.objects.active
	body.name = "Mesh"
	for old in list(body.data.color_attributes):
		body.data.color_attributes.remove(old)
	decimate = body.modifiers.new("Decimate", "DECIMATE")
	decimate.ratio = RATIO
	decimate.use_collapse_triangulate = True
	while body.modifiers[0].name != "Decimate":
		bpy.ops.object.modifier_move_up(modifier="Decimate")
	bpy.ops.object.modifier_apply(modifier="Decimate")

	for a in list(bpy.data.actions):
		if a == crawl:
			continue
		base = base_name(a)
		if not own_anims or base not in CLIPS:
			bpy.data.actions.remove(a)
		else:
			a.name = CLIPS[base]

	if arm.animation_data:
		arm.animation_data.action = None
		for t in list(arm.animation_data.nla_tracks):
			arm.animation_data.nla_tracks.remove(t)
	if own_anims:
		if arm.animation_data is None:
			arm.animation_data_create()
		for a in bpy.data.actions:
			track = arm.animation_data.nla_tracks.new()
			track.name = a.name
			track.strips.new(a.name, int(a.frame_range[0]), a)

	tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
	print("BODY", name, "tris", tris, "anims", sorted(a.name for a in bpy.data.actions))
	bpy.ops.export_scene.gltf(filepath=os.path.join(out, "people_%s.glb" % name), export_format="GLB",
		export_yup=True, export_texcoords=True, export_normals=True, export_vertex_color="NONE",
		export_materials="EXPORT", export_animations=own_anims, export_animation_mode="NLA_TRACKS",
		export_skins=True, export_morph=False, export_def_bones=False, export_image_format="NONE")
