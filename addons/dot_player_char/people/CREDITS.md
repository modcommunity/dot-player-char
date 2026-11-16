# People

Every model and animation here is from the **Zombie Apocalypse Kit** by **Quaternius** (https://quaternius.com/packs/zombieapocalypsekit.html), released under Creative Commons Zero (CC0 1.0, https://creativecommons.org/publicdomain/zero/1.0/).

| File | From the kit | What was changed |
| --- | --- | --- |
| `people_matt.glb` | `Characters/glTF/Characters_Matt.gltf`, plus the `Crawl` action of `Zombie_Basic.gltf` | weapons removed, one mesh decimated to 42%, clips renamed, the zombie's crawl added |
| `people_lis.glb` | `Characters_Lis.gltf` | weapons removed, decimated, no clips (they play matt's) |
| `people_sam.glb` | `Characters_Sam.gltf` | the same |
| `people_shaun.glb` | `Characters_Shaun.gltf` | the same |
| `atlas_people.png` | the survivors' embedded atlas | unchanged |

`tools/build_people.py` (at the repository root) rebuilds every file from the kit's `Characters/glTF` folder.

## The seated idle

`people_ual.res` holds thirteen clips (`sit`, `drive`, and eleven `ual_*`: zombie idle, walk and scratch, knockback, lay-to-idle, slide, sprint, jog, crouch walk, hit chest and hit head, 163 KB) from the **Universal Animation Library** and **Universal Animation Library 2** (Standard, the free versions) by **Quaternius** (https://quaternius.com/packs/universalanimationlibrary.html, downloaded from https://quaternius.itch.io/universal-animation-library as `Universal Animation Library[Standard].zip`, file `Unreal-Godot/UAL1_Standard.glb`; the second from https://quaternius.itch.io/universal-animation-library-2, `UAL2_Standard.glb`, downloaded 2026-10-29), released under Creative Commons Zero (CC0 1.0, https://creativecommons.org/publicdomain/zero/1.0/; the zip's `License.txt` says the same). It was retargeted from the library's mannequin skeleton onto `people_matt.glb`'s and resampled at 15 keys a second. `tools/ual_retarget.gd -- --ual=<path to UAL1_Standard.glb>` rebuilds it.

## Kenney's animated characters

`kenney/` holds one body, eight skins and a clip library from **Animated Characters Protagonists** (https://kenney.nl/assets/animated-characters-protagonists) and **Animated Characters Retro** (https://kenney.nl/assets/animated-characters-retro) by **Kenney** (https://kenney.nl), both released under Creative Commons Zero (CC0 1.0, https://creativecommons.org/publicdomain/zero/1.0/; each zip's `License.txt` says the same). Downloaded 2026-11-16. The two packs carry a byte-identical body model and identical animations; only the skins differ, so there is one model file.

| File | From the packs | What was changed |
| --- | --- | --- |
| `kenney/kenney_character.glb` | `Model/characterMedium.fbx` and `Animations/{idle,run,jump}.fbx` (Protagonists; the Retro copies are identical) | converted to glTF by `tools/build_kenney_characters.py` (Blender), clips renamed `idle`, `run`, `jump`, the T-pose clip dropped, textures left out |
| `kenney/kenney_clips.res` | the three clips above, plus the Quaternius kit's clips (above) | the kit's walk, gun, crouch, fall, land, death and crawl clips carried onto this rig by `tools/kenney_retarget.gd` |
| `kenney/protagonists_{criminalMaleA,cyborgFemaleA,skaterFemaleA,skaterMaleA}.png` | Protagonists `Skins/` | unchanged |
| `kenney/retro_{humanFemaleA,humanMaleA,zombieFemaleA,zombieMaleA}.png` | Retro `Skins/` | unchanged |

Display names are "GS - <name>" (`DotKenneyCharacters`). The mapping is in `docs/kenney-characters.md`.
