This is the **player character** asset for TMC's **Dot** collection. It is who a player looks like — the body metrics five other systems have to agree about, a customisation document a server can check without loading any art, and the two ways of actually drawing one.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Four halves, one addon

| | |
| --- | --- |
| **The character** | Metrics, the customisation document, the catalogue, and the abstract visual seam. |
| **The model** | A 3D rig with named mounts, and a plan of what goes in them. |
| **The sprite** | A 2D sheet with layered overlays cut on one grid, and a facing. |
| **The animations** | A locomotion state machine with hysteresis, a clip table that serves both, and a sink. |

They were four addons and are one, because there was no combination anybody installed that did not include this one — and two of the seams between them only existed to avoid a dependency that no longer exists. Shipping both drawing halves costs a handful of unused scripts and no content: neither loads anything until a catalogue points it at something.

## The metrics are the point

A character's height decides the collision capsule. The eye height decides where the camera and the muzzle are. The crouch height decides whether it fits under a vent. The radius decides whether it fits through a door. The hitbox scale decides how hard it is to shoot.

In most projects those are five numbers in five files that were the same on the day they were typed. Here they are one `DotPlayerCharDef`, and `DotPlayerChar` sizes the body from it:

```gdscript
var ch := DotPlayerChar.new()
ch.catalogue = DotPlayerCharCatalogue.three_builds()
player.add_child(ch)

ch.set_char(&"heavy")     # the capsule resizes with the model
ch.set_crouched(true)     # so does the crouched one
ch.eye_height()           # asked by the camera, the muzzle and the trace
```

`validate()` refuses the three configurations that have no obvious symptom: crouching taller than standing (you get stuck coming out of every gap you crouched into), eyes above the head (you see over walls you are standing behind), and the crouched pair of the same.

## Install

Copy `addons/dot_player_char/`, `addons/dot_player/` and `addons/dot_core/` into your project and enable all three in *Project → Project Settings → Plugins*.

Requires Godot 4.7 or newer.

## A customisation document a server can check

`DotPlayerCharLook` is slot choices plus tint colours, and **nothing in validating one loads any art**:

```gdscript
var res := look.validate(def)   # does the slot exist, is the option real,
                                # are there no more colours than channels
```

That is dot-user-avatar's rule restated for the character itself, and for the same reason: a server running a match should not have to hold every cosmetic anybody owns.

`conform()` is the other half and lives in a different place. `validate` is for the trust boundary, where a bad document should be refused. `conform` is for **loading somebody's saved character after the hat they chose was retired** — where refusing would lock them out of their own character. It drops what is illegal and keeps the rest. `fill_defaults()` then completes it, so a player who never opened the customisation screen has a valid look rather than a half-built one a renderer has to have an opinion about.

## Drawing it: 3D

```
DotPlayerChar
  DotPlayerModelVisual       catalogue = a DotPlayerModelCatalogue
    Rig                      built from the definition's rig_scene
```

A plan is worked out from ids, then built:

```gdscript
var plan := DotPlayerModelBuilder.plan(model_def, look)
DotPlayerModelBuilder.apply(plan, rig, placeholder)
```

**Planning never touches the filesystem.** `missing` means *the definition names no path for this part*, not *the file is absent* — a dedicated server plans from ids and holds none of the content, so a plan that consulted `ResourceLoader.exists` would answer differently on the server and the client.

`DotPlayerModelVisual` keeps a **signature** of slot→scene, so a colour change does not rebuild (a tint is written to instances that already exist) and neither does a stance change. Getting this wrong is expensive in both directions: too eager and a player who crouches re-instantiates their whole wardrobe, too lazy and a hat changed in a menu does not appear until the next respawn.

Tints are **per-instance shader parameters**, never a material swap, because two players wearing the same part must not recolour each other.

`DotPlayerModelCatalogue.humanoid()` ships nine mount names — `head`, `face`, `chest`, `back`, `waist`, `left_hand`, `right_hand`, `left_foot`, `right_foot` — and no scene paths. **The names are the point**: a family that agrees on one spelling is a family where a weapon written for one game attaches in another.

## Drawing it: 2D

```
DotPlayerChar
  DotPlayerSpriteVisual      catalogue = a DotPlayerSpriteCatalogue
    Sprite                   one Sprite2D per layer, all sharing one region
```

A sheet is a grid: a **row** is a state, a **direction** offsets that row, a **column** is a frame. `def.frame_index(row, direction, frame)` is the four lines every project writes once per layer with the rows and columns swapped in one of them, and the constraint that makes one number serve every layer is that **overlays are cut on the base's grid**.

`DotPlayerSpriteFacing.resolve(angle, count, mirror)` returns the row offset **and the flip**, because a mirrored eight-way sheet is five drawn rows and three derived, and a caller working the flip out itself has to know which three.

## Animating it

```gdscript
DotPlayerAnimDriver           anim_set = DotPlayerAnimSet.locomotion()
  DotPlayerAnimPlayerSink     3D: drives an AnimationPlayer
  DotPlayerAnimSpriteSink     2D: calls set_row / set_frame
```

The decision is **pure**: `DotPlayerAnimState.advance(motion, delta)` reads no node, no clock and no input device, so a server can run the same state machine as a client and check what the client claims to be doing.

**Hysteresis, not a smaller epsilon.** `speed > run_speed ? "run" : "walk"` flickers for a player holding a stick at the threshold; the fix is two thresholds. The suite jitters a speed either side for forty ticks and checks the state changes *twice*. `air_grace` is the same idea in time — a stair step leaves the floor for a tick, and a character that started a jump animation each time twitches its way upstairs.

Events come out of the **clip's own timeline**, not a `Timer`: a footstep on a wall clock drifts out of step the moment the frame rate changes. One clip serves a rig and a sheet, with event positions as fractions so `0.25` means the same place in both.

## Licence

MIT. See [LICENSE](LICENSE).
