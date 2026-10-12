# dot-player-char

Who a player looks like: the metrics, the customisation document, a 3D rig and a 2D sheet to draw it with, the locomotion animation layer, a body that comes apart on death, a dead body that falls as a ragdoll (with death reactions a server picks), and your own body in first person.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to characters.

**The distributable is `addons/dot_player_char/`.** It requires dot-core and dot-player (`DotPlayerChar` and `DotPlayerAnimDriver` extend `DotPlayerComponent`), both symlinked and in `.gitignore`.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: the one height, ids-only validation, the seams, the rebuild signature, seating a visual, breaking a body, the smaller traps, what is not here |
| [docs/ragdolls.md](docs/ragdolls.md) | dead bodies: the styles, the reaction rule, what travels with a kill, the cvars, the joint and fade traps |
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
| `nodes/dot_player_body_break.gd` | a body's meshes, copied into tumbling pieces that fade |
| `core/dot_player_death_reaction.gd`, `dot_player_death_reactions.gd` | one way a body goes down (pose, pushes, sounds, when it qualifies), and the set with the pure `pick()` |
| `core/dot_player_death.gd` | the server's decision for one kill (reaction, seed, direction, damage), `to_dict` / `from_dict` for a kill message |
| `core/dot_player_ragdoll_rules.gd` | style, lifetime, cap, force, weights; `bind_cvars` / `follow_cvars` for the `sv_ragdoll*` set |
| `core/dot_player_death_sounds.gd`, `death/sounds/` | the stock sound ids' files (Kenney CC0, credited in `death/sounds/CREDITS.md`) as data a game makes audio defs from |
| `nodes/dot_player_ragdoll.gd` | one dead body: parts by name, joints, the push, settle and freeze, the fade |
| `nodes/dot_player_ragdolls.gd` | where bodies lie: `spawn`, the cap, sounds out |
| `nodes/dot_player_first_person_body.gd` | your own body in first person: head shadow-only, body back |
| `examples/` | five suites: `char_selftest` (the main scene), `model_selftest`, `sprite_selftest`, `anim_selftest`, `ragdoll_selftest` |

Paths under `core/` and `nodes/` are in `addons/dot_player_char/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then **all five** suites: `char_selftest.tscn`, `model_selftest.tscn`, `sprite_selftest.tscn`, `anim_selftest.tscn`, `ragdoll_selftest.tscn` under `res://examples/`. The ragdoll suite runs real physics and takes about fifteen seconds; what a fall looks like is only seen in a rendered sequence ([docs/ragdolls.md](docs/ragdolls.md#looking-at-one)). The first is the main scene, and the one a careless check runs alone.

## Rules that bite

- One `DotPlayerCharDef` height feeds capsule, crouch, camera, muzzle and hitboxes; never a second copy of the number. [design](docs/design.md#one-number-for-how-tall-somebody-is)
- A look is validated from ids alone: no `load()` or `ResourceLoader.exists()` in a legality check, and `plan()` touches no file. [design](docs/design.md#planning-never-touches-the-filesystem)
- `validate` at the trust boundary (refuse whole), `conform` on load (drop what was retired); `set_look` conforms. [design](docs/design.md#validate-and-conform-are-in-different-places-on-purpose)
- Rebuild signature excludes colours; reset `_last_signature` on a model change. [design](docs/design.md#the-signature-is-the-whole-performance-story)
- A visual's drawn node is seated on the player with `reparent(anchor, false)`, deferred while the anchor readies, and follows the visual out. [design](docs/design.md#a-visuals-drawn-node-hangs-off-the-player-not-off-the-visual)
- A visual attached later is pushed the character (deferred) via `child_entered_tree`. [design](docs/design.md#a-visual-added-later-is-still-told-what-to-draw)
- `_refresh` recurses once through `char_id`'s setter; keep the `return` after the assignment. [design](docs/design.md#_refresh-recurses-exactly-once-on-purpose)
- Body breaking copies meshes, is seeded by the game (never `randf()` / `shuffle()`), sits on layer 0, and never runs on a server. [design](docs/design.md#a-body-coming-apart-is-presentation-seeded-from-the-death)
- The server picks a death's reaction and seed (`DotPlayerDeath.decide`) and sends them; a client never picks, and nothing in a ragdoll calls `randf()`. [ragdolls](docs/ragdolls.md#the-server-picks-every-client-falls)
- No tight joints: cone limits much under the stock ones fling the body across the map on a hard landing. A face plant is one rigid piece until it lands, then `_become_jointed`. [ragdolls](docs/ragdolls.md#a-plank-is-one-body-not-tight-joints)
- A ragdoll fades by shrinking about one floor point, not by `transparency` alone: the compatibility renderer (every web client) ignores it. [ragdolls](docs/ragdolls.md#the-fade)
- `capsule_3d()` returns a fresh shape and clamps to two radii; `eye_offset()` < 0 means "no opinion". [design](docs/design.md#smaller-traps)
- Run thresholds have a gap (`run_exit_speed`), events fire through `events_between`, and the reset is `forget_state`. [design](docs/design.md#smaller-traps)
- Entitlement is the game's: `requires_entitlement` is only an id. [design](docs/design.md#what-this-does-not-do)

Deliberately not here: network content loading (`content_paths()` lists it), blending, IK, aiming, entitlement decisions. [design](docs/design.md#what-this-does-not-do)
