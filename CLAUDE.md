# dot-player-char

Who a player looks like: the metrics, the customisation document, a 3D rig and a 2D sheet to draw it with, the locomotion animation layer, the family's animated people (skinned, one rig, one clip set, coloured by a look or a site avatar), a body that comes apart on death, a dead body that falls as a ragdoll (rigid meshes or a skeleton, with death reactions a server picks), and your own body in first person.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to characters.

**The distributable is `addons/dot_player_char/`.** It requires dot-core and dot-player (`DotPlayerChar` and `DotPlayerAnimDriver` extend `DotPlayerComponent`), both symlinked and in `.gitignore`.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: the one height, ids-only validation, the seams, the rebuild signature, seating a visual, breaking a body, the smaller traps, what is not here |
| [docs/people.md](docs/people.md) | drawing a player, bot or NPC as a person: why this kit, colour looks, the site avatar, retargeting and the made clips, overlays, the mirrored (right) gun hand, aiming, sitting and climbing, the crown mount, cost |
| [docs/ragdolls.md](docs/ragdolls.md) | dead bodies: the styles, the reaction rule, what travels with a kill, the cvars, the joint and fade traps, the skinned path |
| [docs/history.md](docs/history.md) | the four-addon merge, and the bodies that all stood at the origin |

## Layout

| Path | What |
| --- | --- |
| `core/dot_player_char_def.gd` | the metrics, the ids, the slots; `capsule_3d()`, `allows()` |
| `core/dot_player_char_look.gd` | what a player chose, as a bounded document; `validate`, `conform` |
| `core/dot_player_char_catalogue.gd` | the set, and its presets |
| `core/dot_player_model_def.gd`, `dot_player_model_catalogue.gd` | a 3D rig (mounts, parts, tints), and the set with the humanoid mount names |
| `core/dot_player_model_builder.gd` | `plan` (pure) and `apply` (the only node work) |
| `core/dot_player_sprite_def.gd`, `dot_player_sprite_catalogue.gd` | a 2D sheet (grid, layers, anchor), and the set with its presets |
| `core/dot_player_sprite_facing.gd` | angle to row offset and flip, static |
| `core/dot_player_anim_state.gd`, `dot_player_anim_clip.gd`, `dot_player_anim_set.gd` | the locomotion state machine (pure), one clip for a rig and a sheet, the clip table |
| `core/dot_player_break_rules.gd` | how a body comes apart on death: none, limbs, explode |
| `nodes/dot_player_char.gd` | the component: metrics, stance, body, visuals |
| `nodes/dot_player_char_visual.gd` | the abstract seam; `seat()` |
| `nodes/dot_player_model_rig.gd`, `dot_player_model_visual.gd` | a built rig (mount lookup, measured eye height), and the 3D visual |
| `nodes/dot_player_sprite_visual.gd` | the 2D visual |
| `nodes/dot_player_anim_sink.gd`, `dot_player_anim_player_sink.gd`, `dot_player_anim_sprite_sink.gd` | where an animation decision goes: abstract, an `AnimationPlayer`, a duck-typed sprite |
| `nodes/dot_player_anim_driver.gd` | the component that ties animation together |
| `nodes/dot_player_body_break.gd` | a body's meshes, copied into tumbling pieces that fade; a skinned body's limbs baked out of the skin |
| `core/dot_player_death_reaction.gd`, `dot_player_death_reactions.gd` | one way a body goes down (pose, pushes, sounds, when it qualifies), and the set with the pure `pick()` |
| `core/dot_player_death.gd` | the server's decision for one kill (reaction, seed, direction, damage); `write_to` / `read_from` (a dot-net writer, duck-typed) or `to_dict` / `from_dict` for a kill message |
| `core/dot_player_ragdoll_rules.gd` | style, lifetime, cap, force, weights; `bind_cvars` / `follow_cvars` for the `sv_ragdoll*` set |
| `core/dot_player_death_sounds.gd`, `death/sounds/` | the stock sound ids' files (Kenney CC0, credited in `death/sounds/CREDITS.md`) as data a game makes audio defs from |
| `nodes/dot_player_ragdoll.gd` | one dead body: parts by name, joints, the push, settle and freeze, the fade |
| `nodes/dot_player_ragdolls.gd` | where bodies lie: `spawn`, the cap, sounds out |
| `nodes/dot_player_first_person_body.gd` | your own body in first person: head shadow-only, body back |
| `core/dot_view_grip.gd` | where the hands go on a first-person weapon: anchor, grip, support |
| `nodes/dot_player_view_arms.gd` | your own crawling arms in first person while downed, under the yaw pivot; `arms_factory` swaps them and `set_held` poses them on a weapon (`DotViewGrip`); no game mounts it yet |
| `core/dot_humanoid_look.gd` | a person as data: body and four colours; `stock(seed)`, `from_site(avatar)`, `with_side` |
| `core/dot_humanoid_clips.gd` | the family clip names, `retarget`, the made crouch and grounded air clips, `adopt` (real clips over made ones) |
| `core/dot_humanoid_actions.gd` | the 13 starter emotes, poses and gestures as clips (made, CC0 wave/nod/sit), and `rename_humanoid` for an uploaded clip |
| `core/dot_foot_plant.gd` | feet held still on the ground over a gait phase, swung in an arc to the next step; bend the leg to it with `DotHumanoidIk.two_bone_to` |
| `nodes/dot_humanoid_figure.gd` | a person drawn: palette material per look, clip from motion, overlays, the hand, LOD stepping |
| `people/` | the four bodies (Quaternius, CC0; `CREDITS.md`) and their atlas, built by `tools/build_people.py`; `people_ual.res`, the real sit (Universal Animation Library, CC0) |
| `tools/` | `build_people.py` (Blender), `ual_retarget.gd` (library clips onto the rig: `people_ual.res`), `people_palette.gd`, `kenney_site_colours.py`, `people_sheet.gd` (contact sheets; `--aim`, `--swim`, `--compare`), `survivor_compare.gd` (made vs real clip strips), `crowd_bench.tscn` (a browser crowd measurement) |
| `dot_player_char_api.gd` | the API level (`DotAddonApi`): 11 since `frame_delta` (10: `DotFootPlant`) (9: `sprint_speed`) (8: `DotViewGrip`) (7: `DotPlayerViewArms`) (5: `play_action`) (4: the `driving` motion; 3: the people and the skinned ragdoll) |
| `examples/` | six suites: `char_selftest` (the main scene), `model_selftest`, `sprite_selftest`, `anim_selftest`, `ragdoll_selftest`, `people_selftest` |

Paths under `core/`, `nodes/` and `people/` are in `addons/dot_player_char/`; `tools/` is at the repository root and does not ship.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then **all six** suites: `char_selftest.tscn`, `model_selftest.tscn`, `sprite_selftest.tscn`, `anim_selftest.tscn`, `ragdoll_selftest.tscn`, `people_selftest.tscn` under `res://examples/`. What people look like and how they fall is only seen in `xvfb-run -a godot --path . --script tools/people_sheet.gd -- [--looks|--ragdoll]` ([docs/people.md](docs/people.md#looking-at-them)). The ragdoll suite runs real physics and takes about fifteen seconds; what a fall looks like is only seen in a rendered sequence ([docs/ragdolls.md](docs/ragdolls.md#looking-at-one)). The first is the main scene, and the one a careless check runs alone.

## Rules that bite

- One `DotPlayerCharDef` height feeds capsule, crouch, camera, muzzle and hitboxes; never a second copy of the number. [design](docs/design.md#one-number-for-how-tall-somebody-is)
- A look is validated from ids alone: no `load()` or `ResourceLoader.exists()` in a legality check, and `plan()` touches no file. [design](docs/design.md#planning-never-touches-the-filesystem)
- `validate` at the trust boundary (refuse whole), `conform` on load (drop what was retired); `set_look` conforms. [design](docs/design.md#validate-and-conform-are-in-different-places-on-purpose)
- Rebuild signature excludes colours; reset `_last_signature` on a model change. [design](docs/design.md#the-signature-is-the-whole-performance-story)
- A visual's drawn node is seated on the player with `reparent(anchor, false)`, deferred while the anchor readies, and follows the visual out. [design](docs/design.md#a-visuals-drawn-node-hangs-off-the-player-not-off-the-visual)
- A visual attached later is pushed the character (deferred) via `child_entered_tree`. [design](docs/design.md#a-visual-added-later-is-still-told-what-to-draw)
- `_refresh` recurses once through `char_id`'s setter; keep the `return` after the assignment. [design](docs/design.md#_refresh-recurses-exactly-once-on-purpose)
- Every mesh copy (a ragdoll, a broken body, a dropped weapon) skips `top_level` subtrees: shot effects, marks and casings hung under a gun are drawn in world space, and a copy of them hangs in the air for the prop's life (and its collider grew to 20 m).
- Body breaking copies meshes (a skinned body's limbs are baked from the skin, never copied: a copy draws the bind pose), is seeded by the game (never `randf()` / `shuffle()`), sits on layer 0, and never runs on a server. [design](docs/design.md#a-body-coming-apart-is-presentation-seeded-from-the-death)
- The server picks a death's reaction and seed (`DotPlayerDeath.decide`) and sends them; a client never picks, and nothing in a ragdoll calls `randf()`. [ragdolls](docs/ragdolls.md#the-server-picks-every-client-falls)
- No tight joints: cone limits much under the stock ones fling the body across the map on a hard landing. A face plant is one rigid piece until it lands, then `_become_jointed`. [ragdolls](docs/ragdolls.md#a-plank-is-one-body-not-tight-joints)
- A ragdoll fades by shrinking about one floor point, not by `transparency` alone: the compatibility renderer (every web client) ignores it. [ragdolls](docs/ragdolls.md#the-fade)
- `capsule_3d()` returns a fresh shape and clamps to two radii; `eye_offset()` < 0 means "no opinion". [design](docs/design.md#smaller-traps)
- Run thresholds have a gap (`run_exit_speed`), events fire through `events_between`, and the reset is `forget_state`. [design](docs/design.md#smaller-traps)
- People: only `people_matt.glb` carries clips; every other body plays them through `DotHumanoidClips.retarget` (played raw they bend). [people](docs/people.md#one-clip-set-carried-to-every-body)
- The air clips are grounded and the crouch is made (`synthesise`); a rebuilt kit needs both again. [people](docs/people.md#the-made-clips)
- The sit is the Universal Animation Library's, baked onto matt's skeleton by `tools/ual_retarget.gd` and adopted after the mirror (it is right-handed already); a rebuilt kit re-bakes it. Compare a candidate with `people_sheet.gd --compare=FILE` before adding it. [people](docs/people.md#real-clips-from-the-universal-animation-library)
- A person's material is one per look, shared by everybody wearing it, with no per-instance uniforms (game-zombie-zone's palette shader made the same choice for the compatibility renderer). [people](docs/people.md#variety-is-colour-not-texture)
- A game newly linking `dot_player_char`: run `--import` again before trusting a render. mg-look-at-me's first import after linking left `people/` unimported, the figure drew its capsule, and every suite still passed. [people](docs/people.md#looking-at-them)
- The kit is left-handed; `DotHumanoidClips.mirror` makes every clip right-handed at load, before the made clips and the retarget. A rebuilt kit is mirrored the same way, never in the glb. [people](docs/people.md#legs-from-the-clip-arms-from-an-overlay)
- The swim clip is drawn upright and the figure lays it flat (`SWIM_LEAN`); no held-gun arms while swimming. Look at it with `people_sheet.gd --swim`. [people](docs/people.md#the-made-clips)
- `DotDownedRules` (`sv_downed_*` cvars, pure functions of the rules) picks the downed weapon kind, who may crawl, the pose and the holster; the figure lies propped on its back (`set_motion` key `propped`, `PROP_LEAN`) or crawls, clips behind `downed_clips`.
- The walk, run and crouch walk play at the rate that keeps the planted foot still (`_matched_rate`, from a per-clip distance table); a constant rate skates it. [people](docs/people.md#legs-from-the-clip-arms-from-an-overlay)
- The rig's feet hang off the root, not the shins: a made pose moves the foot to the shin's end, measuring the shin before moving the body. [people](docs/people.md#the-made-clips)
- `aim()` bends only bones the playing clip keys, from parents read off the local poses (`get_bone_global_pose` is last frame's). [people](docs/people.md#aiming-up-and-down)
- A skinned body falls by the same parts with bones riding on them, not a `PhysicalBoneSimulator3D`; a packed array read out of a Dictionary is a copy. [ragdolls](docs/ragdolls.md#a-skinned-body)
- Entitlement is the game's: `requires_entitlement` is only an id. [design](docs/design.md#what-this-does-not-do)

Deliberately not here: network content loading (`content_paths()` lists it), blending, full-body IK (only the two-bone limb and `DotFootPlant`), entitlement decisions. Aiming is only the people's upper-body pitch (`DotHumanoidFigure.aim`). [design](docs/design.md#what-this-does-not-do)
