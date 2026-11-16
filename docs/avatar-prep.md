# Preparing app-specific avatars for 64 players

FC aims at 64 players on screen, web build included. The two app-specific avatars (the S.W.A.T. Operator by SpatialNeglect and "Game Ready Military Character" by jayb3e, both CC BY 4.0 from Sketchfab) arrive as 67k-72k triangle, 10-12 texture, 65-66 bone downloads. `tools/avatar_prep/prep_avatar.py` turns each into a LOD chain that fits 64. The raw files are private (`private-assets/`, never in a public repo); the script, the per-model configs and this page are the recipe.

    blender -b --factory-startup --python tools/avatar_prep/prep_avatar.py -- tools/avatar_prep/<model>.json <source.glb> <out dir>

Blender needs its bundled numpy for the glTF importer; run it as the work user (`gamedev`) on the build box.

## What the script does

- Drops the hand-held weapon (SWAT: 24 KSVR meshes, 14k triangles) and the alpha-blended eyebrows/eyelashes (a second pass per person).
- Renames bones to canonical Mixamo names (`mixamorig:Hips_63` becomes `Hips`) so `DotHumanoidActions.profile_bone_of` and one shared map cover every Mixamo-rigged avatar (`mixamo_bone_map.json`: canonical bone to UAL bone and FC kit bone, from `tools/ual_retarget.gd` MAP; it is the avatars-3 clip-mapping table, not a fork).
- Scales both to 1.8 m, feet on y=0, hips on the origin axis (measured: bounds 0.0..1.80 m), Y-up as glTF has it. The source A-pose (military) and T-pose (SWAT) are kept; rough retarget of a T-pose source is the known gap in docs/people.md.
- Trims the skeleton and moves the dropped bones' weights to the nearest kept parent. Source 66 / 65 bones; LOD0 46 / 45 (no ring finger, no finger tips, no toe/head ends); LOD1-2 22 / 21 (no fingers).
- Decimates to the LOD budget, packs all materials into one 1024-wide atlas (military 1024x1024, SWAT 1024x512; 512 px per big material) and joins to one mesh with one material, so a team's 64 bodies share one material and one surface.

## Numbers (before and after)

| | source | LOD0 | LOD1 | LOD2 | LOD0 arms only |
|---|---|---|---|---|---|
| military tris | 66,768 | 9,995 | 2,996 | 800 | 1,456 |
| military bones | 66 | 46 | 22 | 22 | 36 |
| military GLB (JPEG atlas) | 9.83 MB | 582 KB | 288 KB | 180 KB | 189 KB |
| SWAT tris | 71.8k (57k body + 14k gun) | 9,997 | 2,999 | 799 | 276 |
| SWAT bones | 65 | 45 | 21 | 21 | 35 |
| SWAT GLB (JPEG atlas) | 15.3 MB | 730 KB | 303 KB | 154 KB | 89 KB |

WEBP-atlas variants are 5-25 percent smaller (`*.webp.glb`). Compression to ktx2/basis happens at Godot import or web export; no CLI for it is installed on the build boxes (no toktx, basisu), so the GLBs carry JPEG and the importer compresses. The far tier past LOD2 (about 40 m) is a capsule or impostor, not built here (see Left).

## Measured: 64 of each, windowed, RTX 2070 (staging02)

`tools/avatar_bench.tscn`, procedural bone poses, 300 frames per row. Forward+/Vulkan, then gl_compatibility/OpenGL (the browser shell's renderer). The distance-plan row ran with the first LOD2 (1,328 / 1,009 triangles); the shipped LOD2 is smaller.

| 64 people | Vulkan ms | GL compat ms | draw calls | primitives |
|---|---|---|---|---|
| military, source | 4.52 | 3.85 | 1161 | 13.1M |
| military, all LOD0 | 1.29 | 2.06 | 197 | 1.92M |
| military, distance plan | 0.61 | 0.80 | 197 | 0.58M |
| SWAT, source | 4.40 | 4.06 | 999 (6364 compat) | 13.7M |
| SWAT, all LOD0 | 1.21 | 2.23 | 197 | 1.92M |
| SWAT, distance plan | 0.58 | 0.81 | 197 | 0.55M |

Distance plan: 1/8 LOD0, 3/8 LOD1, 1/2 LOD2. Skinned meshes are not instanced by Godot; "batching" here means one surface and one material per person (3 draws each with the shadow pass), which is what 197 calls shows, against 1,000+ for the downloads.

## Verdict

Both fit 64 players with the chain. The unprocessed downloads do not on a weaker card: 13M primitives and 1,000-6,400 draw calls. On a 2070 LOD0 for all 64 is 1.2-2.2 ms; the weak-GPU and web cost is in primitives, so keep LOD0 to the nearest 8-10 players. Quality: SWAT holds at LOD1 (helmet and vest read), military keeps a good LOD0 but at LOD1/LOD2 the pants shell, a separate mesh over the body, collapses and shows skin through (render: `military_tex.png`). Acceptable past 15 m; if the owner wants it better, a pants-only second atlas or a manual LOD1 is the fix. Fallback if a worse budget is set: Modern Army Soldier (Sketchfab m152027350, 1,164 triangles, 23 clips) or the Quaternius set.

## Gib cut (docs/gibbable-avatars.md)

Roles come from bone names (`LeftArm`..., `Head`, rest torso) via each vertex's strongest weight, the cut `DotGibMesh` would make. After this prep the share of triangles whose three vertices disagree on role (those get split at death): military LOD0 3.4 percent, LOD1 6.0, LOD2 13; SWAT LOD0 1.2, LOD1 2.2, LOD2 4.4. The exploded-role render (`*_gib.png`: head yellow, torso blue, arms red/green, legs magenta/cyan) shows clean seams at shoulders, hips and neck. Note SWAT's helmet/mask mesh is skinned to the head, so the head piece is 76 percent of its triangles; cap it or cut the helmet off as its own piece. Gib pieces are not stored: they are built lazily from the LOD0 mesh at the moment of death and cached per mesh, so a living player carries none.

## First-person arms

`<name>_lod0_fp_arms.glb`: the triangles whose three vertices are arm-dominant (shoulder to hand), on a 36 / 35 bone skeleton (spine plus both arms, 4 finger chains kept). Military 1,456 triangles, SWAT 276 (SWAT's sleeves are mostly part of the torso mesh weight, so its arms are the bare hands and forearms; a proper fp-arms mesh needs a sleeve cut by hand).

## Kit rig

`kit_rig.py` (Blender, after `prep_avatar.py`) puts the three LODs on the people kit's 43-bone skeleton with the kit's bone names and rest directions, as one `<name>_kit.glb` holding meshes `LOD0`, `LOD1`, `LOD2`, one skin and one material (`team_atlas`, the packed atlas as its base colour). On that rig every people clip, the aim, crouch and leg code, the own view and the gib roles work unchanged, so the `mixamo_bone_map.json` route is only needed for clips that are not the family's.

| | LOD0 | LOD1 | LOD2 | `_kit.glb` |
|---|---|---|---|---|
| SWAT tris | 9,999 | 3,000 | 1,200 | 1.13 MB |
| military tris | 9,998 | 2,997 | 784 | 976 KB (with the `dye` vertex colour) |

Two config keys came out of the LOD1/2 check: `covered` cuts the skin faces a clothing shell hides before decimation (the military pants and SWAT suit no longer show the legs through at LOD1/2), and `shares` gives a material a fixed part of the budget (SWAT's 38k-triangle helmet took three quarters of LOD2 and left the limbs as slivers; LOD2 is now 1,200).

A game registers the result at run time with `DotHumanoidAssets.register_body(id, path)` (docs/people.md, "A game's own body"); the GLB stays in the game's private assets and is read from outside the project.

## Team colours

A registered body draws with `DotHumanoidAssets.TEAM_SHADER`: its own texture, with everything but warm skin turned toward the look's top colour at the same brightness, by `DotHumanoidAssets.team_tint` (0 = untouched). One material per body and top colour, so a team's players batch.

The warm-is-skin guess fails on tan or brown cloth: the military vest and camo pants stayed brown under a red team. A config's `dye` map (material name to 0..1) makes `prep_avatar.py` bake the answer into the vertex colour, and the shader multiplies the tint by its red and applies the skin test only where green is 1. Unlisted materials, and a body with no vertex colour at all, read as white and keep the guess. The military config dyes vest, pants and hat fully and never dyes `player_soldier` (the bare skin); SWAT needs none (black and navy cloth, skin that the guess finds).

## Animation LOD plan

DotHumanoidFigure already steps the clip rate down at 22 m and 45 m, and a registered body swaps LOD0..LOD2 at `DotHumanoidAssets.lod_distances` (the same distances by default) on its one mesh instance. The bench used: LOD0 posed every frame, LOD1 every 3rd, LOD2 every 6th, nothing past the far tier. 64 people cost 56-277 us of script a frame in the bench.

## Left (nightly fc-military-avatar-1)

The far impostor/capsule tier, ktx2/basis at import, a hand-cut fp-arms mesh (the registered body's first-person arms are its LOD0 stripped by bone, which for SWAT is mostly hands and forearms), the game side (team config, credits, a team's look naming the body), and the owner's question whether the Mixamo-derived characters may be redistributed: until it is answered the prepared GLBs stay private.
