"""Builds addons/dot_player_char/people/kenney/kenney_character.glb from Kenney's Animated Characters packs (CC0 1.0).

    blender -b --factory-startup --python tools/build_kenney_characters.py -- <extracted pack dir> addons/dot_player_char/people/kenney

The pack dir is either of kenney.nl/assets/animated-characters-protagonists and -retro (one zip each:
`Model/characterMedium.fbx`, `Animations/{idle,run,jump}.fbx`, `Skins/*.png`). The two packs' model and
animation files are byte-identical (checked by md5 when this was written): the packs differ only in their
skins, so one body is built and the packs are two groups of skins on it.
The FBX importer needs numpy: Blender's own python does not ship it here, so put one on
`KENNEY_NUMPY` (a directory holding the numpy package) when the import complains.

What this does:
- Keeps the one skinned mesh and the whole 58-bone skeleton (the foot and hip control bones carry the
  clips' body and foot movement, so they stay).
- Takes the three clips (one pose track set each) and names them `idle`, `run`, `jump`, the family's
  names; the "Targeting Pose" action each animation file carries is dropped.
- Leaves the body at the FBX's size (3.77 units tall: the glTF exporter drops an armature's object scale, and a
  scaled-in-place skeleton would invalidate the clips' translations). `DotKenneyCharacters.SCALE` takes it to 1.8 m.
- Exports without images: the skins are separate PNGs a game puts on the one material
  (`DotKenneyCharacters.build`), so one body serves four skins.
"""
import sys, os
sys.path.insert(0, os.environ.get("KENNEY_NUMPY", "/tmp/kn-np"))
import bpy

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
os.makedirs(out, exist_ok=True)

CLIPS = {"Idle": "idle", "Run": "run", "Jump": "jump"}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(src, "Model", "characterMedium.fbx"))
armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
for a in list(bpy.data.actions):
	bpy.data.actions.remove(a)

for file in CLIPS.values():
	before = set(bpy.data.objects)
	bpy.ops.import_scene.fbx(filepath=os.path.join(src, "Animations", file + ".fbx"))
	for o in set(bpy.data.objects) - before:
		bpy.data.objects.remove(o, do_unlink=True)

for a in list(bpy.data.actions):
	name = a.name.split("|")[-1]
	if name in CLIPS:
		a.name = CLIPS[name]
		a.use_fake_user = True
	else:
		bpy.data.actions.remove(a)
found = sorted(a.name for a in bpy.data.actions)
if found != sorted(CLIPS.values()):
	raise SystemExit("expected clips %s, found %s" % (sorted(CLIPS.values()), found))

top = max(v.co.z for v in mesh.data.vertices)
# The glTF exporter's ACTIONS mode only takes actions the armature uses: one NLA track per clip.
ad = armature.animation_data_create()
for a in sorted(bpy.data.actions, key=lambda x: x.name):
	track = ad.nla_tracks.new()
	track.name = a.name
	track.strips.new(a.name, int(a.frame_range[0]), a)
mesh.name = "body"
armature.name = "KenneyCharacter"  # the same root in both packs: one baked clip library (kenney_clips.res) serves both

bpy.ops.object.select_all(action="DESELECT")
armature.select_set(True)
mesh.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "kenney_character.glb"), export_format="GLB",
	use_selection=True, export_image_format="NONE", export_animation_mode="ACTIONS",
	export_force_sampling=True, export_optimize_animation_size=True, export_apply=False, export_yup=True)
print("BUILT height", top)
