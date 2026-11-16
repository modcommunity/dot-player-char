# Kenney's animated characters

`DotKenneyCharacters` draws Kenney's **Animated Characters Protagonists** and **Animated Characters Retro** (both CC0, kenney.nl) beside the Quaternius people ([people.md](people.md)). Licence and file manifest: `addons/dot_player_char/people/CREDITS.md`.

## What the packs are

Both packs ship the same body (`characterMedium.fbx`, a 58-bone Mixamo-style humanoid: hips, spine, chest, upper chest, neck, head, shoulders, arms, fingers, legs, toes, plus `HipsCtrl`, foot and knee controls) and the same three clips (`idle`, `run`, `jump`). They differ only in skins: four PNG textures each. So there is one model file, and the packs are groups of skins:

| Pack | Skins ("GS - <name>") |
| --- | --- |
| Protagonists | Criminal, Cyborg, Skater Girl, Skater Boy |
| Retro | Human Woman, Human Man, Zombie Woman, Zombie Man |

The rig is humanoid-compatible with the family's: both rest in a T-pose facing +Z with straight legs and spine, so a bone's turn from rest carries across.

## Clip mapping

| Family clip | Source | Treatment |
| --- | --- | --- |
| `idle`, `run`, `jump` | Kenney's own | kept; `idle` and `run` loop |
| `walk`, `walk_gun`, `idle_gun`, `crouch`, `crouch_walk`, `land` | the Quaternius kit's clip, mirrored (gun in the right hand) and made as the game makes it | turns carried bone by bone; the lower foot held on the floor each frame |
| `run_gun` | the kit's | as above, moved once so the loop's lowest foot is on the floor (keeps the flight) |
| `fall` | the kit's | the kit's body travel, scaled by leg length |
| `death`, `crawl` | the kit's | moved once so the lowest bone of the clip rests just above the floor |

`jump` is Kenney's own and is nearly a still pose; the family's `fall` and `land` carry the air. `tools/kenney_retarget.gd` bakes them (30 keys a second, 145 KB for ten clips); a rebuilt body needs it run again. `DotKenneyCharacters.REQUIRED` (idle, walk, run, jump, fall, land, death) must all exist or `build` returns null with an error; `OPTIONAL` is the gun, crouch and crawl set.

## Using one

`DotKenneyCharacters.build(&"retro", &"zombieMaleA")` returns a `Node3D` named "GS - Zombie Man", scaled to 1.8 m (`SCALE`: the glTF exporter drops the armature's own scale, so the wrapper carries it), holding the model with its skin and an `AnimationPlayer` with every clip. It does not use `DotHumanoidFigure`: no aim, overlays or ragdoll yet (left on the nightly board).

## Rebuilding

`blender -b --factory-startup --python tools/build_kenney_characters.py -- <pack dir> <out dir>` writes `kenney_character.glb` (needs numpy for Blender's FBX importer; `KENNEY_NUMPY` names a directory with it). Then `godot --headless --path . --import`, then `godot --headless --path . --script tools/kenney_retarget.gd`.

Checked by `examples/kenney_selftest.tscn`: every family clip on both packs resolves its tracks, moves the pose and stays above the floor.
