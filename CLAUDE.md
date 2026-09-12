# dot-player-char

Who a player looks like — the metrics, the document, and the two ways of drawing one.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first — no autoloads, `DotNodeRef` instead of scene paths, `DotResult` for anything fallible, `Dot`-prefixed class names, layered configuration, `describe()` on anything stateful. This file is only what is specific to characters.

## The one idea

**Five systems have to agree about how tall somebody is, so there is one number.**

The collision capsule, the crouch test, the camera, the muzzle and the hitbox layout. In most projects those are five numbers in five files that were the same on the day they were typed, and the bug they produce — a character visibly two metres tall that collides as if it were 1.8 — is one nobody files, because it does not look like a bug. It looks like bad aim.

The second idea is dot-user-avatar's, restated smaller: **the customisation document is validated from ids alone.** If a change here ever needs a `load()` or a `ResourceLoader.exists()` to decide whether a look is legal, that is the thing to push back on.

## It was four addons

`dot-player-char-model`, `dot-player-char-sprite` and `dot-player-char-animations` were separate and were merged in. None of the three was ever pushed, so there is nothing to go and read: the reason is that none of them was useful without this one and none was useful beside another, so the split bought three repositories and bought nothing else — and two of the seams between them existed *only* to avoid a dependency.

Both of those seams stayed, with honest reasons:

- `DotPlayerAnimSpriteSink` still duck-types `set_row` / `set_frame`, because a game with its own sprite node, its own `AnimatedSprite2D` wrapper or a tilemap character gets the whole animation layer by offering two methods.
- `DotPlayerCharVisual` is still abstract with no implementation named by `DotPlayerChar`, because a game with its own art pipeline writes a third.

The one thing that did **not** stay was the duplicated 2D heading helper in `DotPlayerAnimDriver`. It was a duplicate to avoid a dependency a 3D game would not have installed; it is `DotPlayerSpriteFacing.angle_of` now.

## Layout

```
addons/dot_player_char/
  core/
    dot_player_char_def.gd          the metrics, the ids, the slots
    dot_player_char_look.gd         what a player chose, as a bounded document
    dot_player_char_catalogue.gd    the set, and three presets
    dot_player_model_def.gd         a 3D rig: mounts, parts, tints
    dot_player_model_catalogue.gd   the set, and the nine humanoid mount names
    dot_player_model_builder.gd     plan (pure) and apply (the only node work)
    dot_player_sprite_def.gd        a 2D sheet: the grid, the layers, the anchor
    dot_player_sprite_facing.gd     angle -> row offset and flip, static
    dot_player_sprite_catalogue.gd  the set, and two presets
    dot_player_anim_state.gd        the locomotion state machine, pure
    dot_player_anim_clip.gd         one clip, for a rig AND a sheet
    dot_player_anim_set.gd          the clip table, and the locomotion preset
  nodes/
    dot_player_char.gd              the component: metrics, stance, body, visuals
    dot_player_char_visual.gd       the abstract seam
    dot_player_model_rig.gd         a built rig: mount lookup, measured eye height
    dot_player_model_visual.gd      the 3D seam implementation
    dot_player_sprite_visual.gd     the 2D one
    dot_player_anim_sink.gd         where an animation decision goes (abstract)
    dot_player_anim_player_sink.gd  an AnimationPlayer
    dot_player_anim_sprite_sink.gd  a sprite, duck-typed
    dot_player_anim_driver.gd       the component that ties it together
```

Four self-tests, four scenes, one project: `char_selftest` (the default), `model_selftest`, `sprite_selftest`, `anim_selftest`. **Run all four.** The first is the main scene and is the one a careless check runs alone.

## `validate` and `conform` are in different places on purpose

`validate` is for the trust boundary: a document arriving from a client, refused whole. `conform` is for the loading path: somebody's saved character after the hat they chose was retired, where refusing would lock them out of their own character. Dropping three things and keeping the rest is the correct answer there and the wrong one at the boundary.

`DotPlayerChar.set_look` calls `conform`, and says so. The game calls `validate` where the document arrives.

## Planning never touches the filesystem

`DotPlayerModelBuilder.plan()` calls neither `load` nor `ResourceLoader.exists`. A dedicated server plans from ids and holds none of the content, so a plan that consulted the filesystem would produce a different answer on the server than on the client — and the difference shows up as a desync in something that is not the netcode.

`missing` therefore means *the definition names no path*, not *the file is absent*. Whether the scene is really there is `apply()`'s question and the placeholder is its answer. The suite asserts this explicitly, because it is the assertion somebody will otherwise "fix".

## The signature is the whole performance story

`DotPlayerModelVisual` rebuilds when slot→scene changes and not otherwise. Colours are deliberately **excluded**, because a tint is applied to instances that already exist — including them would put back the case the comparison is for: a player dragging a colour slider, calling `apply_char` several times a second, rebuilding forty parts a frame for a change that is not a change.

`_last_signature = ""` on a model change is load-bearing. A new rig has empty mounts, so a signature carried over would suppress the rebuild, and changing to a character wearing the same parts would show an empty body.

## Traps already paid for, in each half

**Shape aliasing.** A `Shape3D` handed to two bodies is shared by them, so `capsule_3d()` returns a fresh one — otherwise resizing one character resizes every player using the resource, which presents as everybody crouching at once. `to_physics_material` in dot-physics and the model builder's tints avoid the same family of bug.

**`capsule_3d` clamps to two radii.** A capsule shorter than that is silently a sphere, which stops climbing stairs in a way that reads as a movement bug.

**`eye_offset()` returns a negative number for "no opinion"**, not zero — zero would put a first-person camera in the floor. A rig with a real head bone answers properly and `DotPlayerChar` asks it before reading the resource.

**The mirror offset in `_set_region`.** Godot mirrors about the node's origin and the anchor is measured from the left, so a flipped sprite moves by its own width. Its absence presents as *the collision being offset*, not the sprite.

**Two thresholds, not one.** `DotPlayerAnimState` enters `run` at `run_speed` and leaves at `run_exit_speed`, and `validate()` refuses a configuration with no gap. `_land_time` is decremented *before* its test so a frame longer than the whole landing ends it in the same call — a suite stepping a second at a time is not hypothetical, it is this addon's own.

**Events are a window, never an instant.** `events_between(from, to)` is the only shape that fires an event exactly once; equality never fires and "past it" fires every tick afterwards.

**`forget_state`, not `reset`.** `docs/gdscript-hazards.md` records what `reset_state` cost when it silently bound to `Resource`'s.

## `_refresh` recurses exactly once, on purpose

`char_id`'s setter calls `_refresh`, and `_refresh` assigns `char_id` when it is empty. One level deep, terminating because a fallback id is never empty — and the `return` immediately after the assignment is what keeps it to one. Worth the comment in the file; it is the kind of thing a later reader "simplifies" into an infinite loop.

## A visual added later is still told what to draw

`DotPlayerChar` connects `child_entered_tree` and pushes the current character at any `DotPlayerCharVisual` that arrives. Without it, a game that instances its character and *then* attaches a first-person arms rig — the ordinary way round — sees an empty player and debugs it in the renderer. The push is deferred, because the child's own `_ready` has not run and a visual that builds its root node there would be told what to draw before it had anywhere to draw it.

## What this does not do

It does not load content over the network — `content_paths()` lists what a preloader or a dot-cloud manifest needs, and something else fetches it. It does not blend, do inverse kinematics or aim. It does not decide who may use which character: `allows()` answers about teams and classes, and `requires_entitlement` is an id the *game* checks, because an addon that decided entitlement is one a client could patch.
