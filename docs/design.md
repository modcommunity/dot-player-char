# Design

Why dot-player-char is shaped the way it is, and why the obvious alternative is wrong in each case.

## One number for how tall somebody is

The collision capsule, the crouch test, the camera, the muzzle and the hitbox layout all have to agree. In most projects those are five numbers in five files that were the same on the day they were typed, and the bug they produce (a character visibly two metres tall that collides as if it were 1.8) is one nobody files, because it does not look like a bug. It looks like bad aim. `DotPlayerCharDef` holds the number.

## The look is validated from ids alone

dot-user-avatar's idea, restated smaller. If a change here ever needs a `load()` or a `ResourceLoader.exists()` to decide whether a look is legal, that is the thing to push back on.

### `validate` and `conform` are in different places on purpose

`validate` is for the trust boundary: a document arriving from a client, refused whole. `conform` is for the loading path: somebody's saved character after the hat they chose was retired, where refusing would lock them out of their own character. Dropping three things and keeping the rest is the correct answer there and the wrong one at the boundary. `DotPlayerChar.set_look` calls `conform`, and says so. The game calls `validate` where the document arrives.

### Planning never touches the filesystem

`DotPlayerModelBuilder.plan()` calls neither `load` nor `ResourceLoader.exists`. A dedicated server plans from ids and holds none of the content, so a plan that consulted the filesystem would produce a different answer on the server than on the client, and the difference shows up as a desync in something that is not the netcode.

`missing` therefore means *the definition names no path*, not *the file is absent*. Whether the scene is really there is `apply()`'s question and the placeholder is its answer. The suite asserts this explicitly, because it is the assertion somebody will otherwise "fix".

## The two seams

- `DotPlayerAnimSpriteSink` duck-types `set_row` / `set_frame`, because a game with its own sprite node, its own `AnimatedSprite2D` wrapper or a tilemap character gets the whole animation layer by offering two methods.
- `DotPlayerCharVisual` is abstract, with no implementation named by `DotPlayerChar`, because a game with its own art pipeline writes a third.

The 2D heading helper lives once, in `DotPlayerSpriteFacing.angle_of`; `DotPlayerAnimDriver` uses it rather than a copy.

## The signature is the whole performance story

`DotPlayerModelVisual` rebuilds when slot→scene changes and not otherwise. Colours are deliberately **excluded**, because a tint is applied to instances that already exist. Including them would put back the case the comparison is for: a player dragging a colour slider, calling `apply_char` several times a second, rebuilding forty parts a frame for a change that is not a change.

`_last_signature = ""` on a model change is load-bearing. A new rig has empty mounts, so a signature carried over would suppress the rebuild, and changing to a character wearing the same parts would show an empty body.

## A visual added later is still told what to draw

`DotPlayerChar` connects `child_entered_tree` and pushes the current character at any `DotPlayerCharVisual` that arrives. Without it, a game that instances its character and *then* attaches a first-person arms rig (the ordinary way round) sees an empty player and debugs it in the renderer. The push is deferred, because the child's own `_ready` has not run and a visual that builds its root node there would be told what to draw before it had anywhere to draw it.

## `_refresh` recurses exactly once, on purpose

`char_id`'s setter calls `_refresh`, and `_refresh` assigns `char_id` when it is empty. One level deep, terminating because a fallback id is never empty, and the `return` immediately after the assignment is what keeps it to one. It is the kind of thing a later reader "simplifies" into an infinite loop.

## A visual's drawn node hangs off the player, not off the visual

A visual is a plain `Node` (a behaviour, not a place), and **a `Node3D` whose parent is not a `Node3D` inherits nobody's transform**: it is placed in world space. So `DotPlayerCharVisual.seat()` moves the drawn node (`_drawn_node()`: the rig, the sprite root) onto the anchor: `anchor_ref` if set, else the nearest ancestor of `_anchor_class()` (`Node3D`, `Node2D`). The visual keeps its reference, so hiding, mounts, tints and rebuilds still reach it. Three details are load-bearing:

- **It defers when the anchor is still readying its children.** A whole player added at once runs the visual's `_ready` while the body is mid-setup, and Godot refuses `add_child` on a node in that state with an error rather than a result. Deferred, it lands before the frame is drawn; added to a body already in the world, it is immediate.
- **`reparent(anchor, false)`, not keeping the global transform.** Under a plain `Node` the local transform *was* the global one, so keeping it would carry the world origin over as an offset from the player: the bug, one level down.
- **The drawn node goes where the visual goes.** Taken off its player, the visual takes its rig back (deferred, since a node leaving the tree cannot rearrange its parent's children); freed, it frees it. Otherwise a visual removed from a player leaves a body standing in the world for a player who is gone.

With no anchor at all (a character screen with no spatial parent) the drawn node stays the visual's own child. `model_selftest`'s *where the rig is drawn* and `sprite_selftest`'s *where the sheet is drawn* are armed against the seat and the unseat.

## A body coming apart is presentation, seeded from the death

`DotPlayerBodyBreak.break_apart(body, world, rules, origin, direction, seed, lethal, critical)` copies the chosen meshes into `RigidBody3D` pieces under `world`, hides the originals, and frees itself after `lifetime` + `fade`. `DotPlayerBreakRules` (a `DotConfig`, so a server owner sets it per mode) picks NONE, LIMBS (`limbs` of the meshes whose name or an ancestor's matches `limb_names`; the humanoid mounts all do) or EXPLODE, and by default only a lethal **critical** breaks anything (`criticals_only`), because a body that comes apart on every death stops meaning anything.

- **Copies, not the originals reparented.** The body is the player's, which a game frees or respawns on its own schedule; a piece that was still its child would vanish mid-flight or come back on respawn.
- **Seeded from the death, never `randf()` or `Array.shuffle()`**, both of which use the global generator: the game passes a seed made of the victim and the tick, so every viewer sees the same arm come off.
- **Pieces collide with the world (`collision_mask`) and sit on layer 0**: nothing collides with them, so a piece cannot change the game. A server never calls it.

**Your own body in first person** is the same kind of helper (`DotPlayerFirstPersonBody`): the head's meshes go `SHADOWS_ONLY` rather than invisible (the camera is inside the head, and a shadow with no head on it is a stranger) and the body is pulled `back_offset` behind the eye so looking down shows the torso rather than its inside. `restore()` undoes both. A game's setting, local player only.

## Smaller traps

- **Shape aliasing.** A `Shape3D` handed to two bodies is shared by them, so `capsule_3d()` returns a fresh one; otherwise resizing one character resizes every player using the resource, which presents as everybody crouching at once. dot-physics' `to_physics_material` and the model builder's tints avoid the same family of bug.
- **`capsule_3d` clamps to two radii.** A capsule shorter than that is silently a sphere, which stops climbing stairs in a way that reads as a movement bug.
- **`eye_offset()` returns a negative number for "no opinion"**, not zero: zero would put a first-person camera in the floor. A rig with a real head bone answers properly and `DotPlayerChar` asks it before reading the resource.
- **The mirror offset in `_set_region`.** Godot mirrors about the node's origin and the anchor is measured from the left, so a flipped sprite moves by its own width. Its absence presents as *the collision being offset*, not the sprite.
- **Two thresholds, not one.** `DotPlayerAnimState` enters `run` at `run_speed` and leaves at `run_exit_speed`, and `validate()` refuses a configuration with no gap. `_land_time` is decremented *before* its test so a frame longer than the whole landing ends it in the same call; a suite stepping a second at a time is this addon's own.
- **Events are a window, never an instant.** `events_between(from, to)` is the only shape that fires an event exactly once; equality never fires and "past it" fires every tick afterwards.
- **`forget_state`, not `reset`.** [gdscript-hazards.md](../../../docs/gdscript-hazards.md) records what `reset_state` cost when it silently bound to `Resource`'s.

## What this does not do

It does not load content over the network: `content_paths()` lists what a preloader or a dot-cloud manifest needs, and something else fetches it. It does not blend, do inverse kinematics or aim. It does not decide who may use which character: `allows()` answers about teams and classes, and `requires_entitlement` is an id the *game* checks, because an addon that decided entitlement is one a client could patch.
