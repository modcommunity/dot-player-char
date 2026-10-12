# People

Every model and animation here is from the **Zombie Apocalypse Kit** by **Quaternius** (https://quaternius.com/packs/zombieapocalypsekit.html), released under Creative Commons Zero (CC0 1.0, https://creativecommons.org/publicdomain/zero/1.0/).

| File | From the kit | What was changed |
| --- | --- | --- |
| `people_matt.glb` | `Characters/glTF/Characters_Matt.gltf`, plus the `Crawl` action of `Zombie_Basic.gltf` | weapons removed, one mesh decimated to 55%, clips renamed, the zombie's crawl added |
| `people_lis.glb` | `Characters_Lis.gltf` | weapons removed, decimated, no clips (they play matt's) |
| `people_sam.glb` | `Characters_Sam.gltf` | the same |
| `people_shaun.glb` | `Characters_Shaun.gltf` | the same |
| `atlas_people.png` | the survivors' embedded atlas | unchanged |

`tools/build_people.py` (at the repository root) rebuilds every file from the kit's `Characters/glTF` folder.
