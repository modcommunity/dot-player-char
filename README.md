# dot-player-char

What a player looks like. It has four parts in one addon:

| Part | What it gives you |
| --- | --- |
| Character | Body metrics (height, eye height, crouch height, radius, hitbox scale), a customisation document a server can validate without loading art, and a catalogue. |
| 3D model | A rig with named mounts and a plan of what goes in them. |
| 2D sprite | A sprite sheet with layered overlays on one grid, and facing. |
| Animation | A locomotion state machine that serves both 3D and 2D. |

It also includes ragdolls and death reactions, and a ready-made set of animated humanoid people. Neither drawing part loads anything until a catalogue points it at content.

## Install

1. Copy `addons/dot_player_char/`, `addons/dot_player/` and `addons/dot_core/` into your project.
2. Enable all three in *Project > Project Settings > Plugins*.

Needs Godot 4.7 or newer.

## Body metrics

One `DotPlayerCharDef` holds the numbers that must agree: height (collision capsule), eye height (camera and muzzle), crouch height and radius. `DotPlayerChar` sizes the body from it.

```gdscript
var ch := DotPlayerChar.new()
ch.catalogue = DotPlayerCharCatalogue.three_builds()
player.add_child(ch)

ch.set_char(&"heavy")     # the capsule resizes with the model
ch.set_crouched(true)
ch.eye_height()           # used by the camera, the muzzle and the trace
```

`validate()` rejects a crouch taller than standing and eyes above the head.

## Customisation

`DotPlayerCharLook` is slot choices plus tint colours. `look.validate(def)` checks that slots and options exist and that there are no more colours than channels, and it loads no art. Use it at the trust boundary. `conform()` instead drops illegal parts and keeps the rest, for loading a saved character after an item was retired. `fill_defaults()` completes a look.

## 3D model

```gdscript
var plan := DotPlayerModelBuilder.plan(model_def, look)
DotPlayerModelBuilder.apply(plan, rig, placeholder)
```

Planning works from ids only, so a dedicated server can plan without holding any content. `DotPlayerModelVisual` only rebuilds when the chosen scenes change, not on a tint or stance change. Tints are per-instance shader parameters, so two players wearing the same part do not recolour each other. `DotPlayerModelCatalogue.humanoid()` defines nine mount names: `head`, `face`, `chest`, `back`, `waist`, `left_hand`, `right_hand`, `left_foot`, `right_foot`.

## 2D sprite

A sheet is a grid: a row is a state, a direction offsets the row, a column is a frame. Overlays must be cut on the base's grid. `DotPlayerSpriteFacing.resolve(angle, count, mirror)` returns the row offset and whether to flip.

## Animation

```
DotPlayerAnimDriver           anim_set = DotPlayerAnimSet.locomotion()
  DotPlayerAnimPlayerSink     3D: drives an AnimationPlayer
  DotPlayerAnimSpriteSink     2D: calls set_row / set_frame
```

`DotPlayerAnimState.advance(motion, delta)` reads no node, clock or input, so a server can run the same state machine as a client. It uses two speed thresholds (hysteresis) so walk and run do not flicker, and a short air grace time so stairs do not trigger jump animations. Clip events come from the clip's own timeline, as fractions, so one clip serves a rig and a sheet.

## Ragdolls and deaths

```gdscript
var yard := DotPlayerRagdolls.new()     # one per world, on a client
yard.rules.follow_cvars(link)
world.add_child(yard)

# server, on a kill:
var death := DotPlayerDeath.decide(reactions, headshot, damage, direction, seed, weapon_def)
kill_message.merge(death.to_dict())

# every client, on that message:
yard.spawn(victim_figure, DotPlayerDeath.from_dict(kill_message), victim_velocity)
```

The server picks the reaction and sends it with the kill, so every screen shows the same fall. Stock reactions: plain fall, headshot throw, powerful-weapon carry (`params.death_reaction` or `params.death_power` in a weapon def), face plant and crumple. A game can add more.

| Server setting | Meaning |
| --- | --- |
| `sv_ragdoll` | Ragdolls on or off. |
| `sv_ragdoll_style` | Physics ragdoll, one stiff piece, scripted fall, or none. |
| `sv_ragdoll_time` | How long a ragdoll lasts before fading. |
| `sv_ragdoll_max` | How many ragdolls at once (default 8, 0 = unlimited; the oldest is removed first). Each machine also has its own cap: unlimited on desktop, 4 on mobile or without threads. |
| `sv_ragdoll_force`, `sv_ragdoll_torque` | How hard shots push bodies. |
| `sv_ragdoll_reactions` | Which reactions are allowed, with weights. |

See [docs/ragdolls.md](docs/ragdolls.md).

## People

```gdscript
var look := DotHumanoidLook.from_site(site_avatar)   # or DotHumanoidLook.stock(hash(player_id))
var person := DotHumanoidFigure.new()
world.add_child(person)
person.build(look.with_side(team_colour, 0.6), 1.8)

# every frame:
person.set_motion({"on_floor": on_floor, "vertical": velocity.y, "crouched": crouched})
person.set_hold(DotHumanoidFigure.Hold.GUN)
person.pose(drawn_position, yaw, ground_speed)
```

Four animated people on one rig, coloured by a look (body, skin, hair, top, bottom). The figure picks idle, walk, run, crouch, jump, fall, swim, climb, sit and death clips from how the player moves, holds a gun with aim, and plays gestures on the upper body. See [docs/people.md](docs/people.md).

## Credits

| Asset | Author / source | License |
| --- | --- | --- |
| The four survivors (Matt, Lis, Sam, Shaun) and their clips, plus the zombie crawl, in `addons/dot_player_char/people/` (rebuilt by `tools/build_people.py`) | [Zombie Apocalypse Kit](https://quaternius.com/packs/zombieapocalypsekit.html) by [Quaternius](https://quaternius.com) | CC0 1.0 |
| Seated idle (`Sitting_Idle_Loop`), sprint and slide clips in `people/people_ual.res` | [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) by Quaternius ([itch.io](https://quaternius.itch.io/universal-animation-library)) | CC0 1.0 |
| `wave` and `yes` gestures | Zombie Apocalypse Kit by Quaternius | CC0 1.0 |
| Death sounds in `addons/dot_player_char/death/sounds/` | [Kenney](https://www.kenney.nl) (Impact Sounds, Foley Sounds) | CC0 1.0 |

The other gestures are generated in code. Per-file details: `addons/dot_player_char/people/CREDITS.md` and `addons/dot_player_char/death/sounds/CREDITS.md`.

More: [docs/design.md](docs/design.md), [docs/history.md](docs/history.md).

## Status and licence

Part of the TMC **dot-\*** family of Godot addons. Written with Claude Code and maintained by `gamemann`. Every addon has headless tests, but little of this has been played by real users yet, so expect rough edges and please [open an issue](https://github.com/modcommunity/dot-player-char/issues) when you hit one.

MIT licence, see [LICENSE](LICENSE). The only closed part of the TMC platform is the web back end; you can use your own instead of TMC's.
