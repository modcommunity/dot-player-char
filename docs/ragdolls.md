# Dead bodies

Why a dead player falls the way it does here, and why the obvious alternative is wrong in each case. The classes are `DotPlayerRagdolls` (where bodies lie), `DotPlayerRagdoll` (one body), `DotPlayerRagdollRules` (the server's settings), `DotPlayerDeathReactions` / `DotPlayerDeathReaction` (the ways to go down) and `DotPlayerDeath` (one kill's decision).

## What it replaced

Before this, every game here drew a death one of two ways, and both looked wrong. In game-arena the dead stood where they died until they respawned, upright, a statue; a critical took one limb off as a tumbling box and left the rest standing on one leg. In every other game (zombie-zone, the prop and hide-and-seek games, the minigames) the figure vanished the instant the death arrived. Neither is a body falling down.

## The styles

`DotPlayerRagdollRules.style`, the cvar `sv_ragdoll_style`:

- **ragdoll** (the default): one `RigidBody3D` per part, joined to the torso with `ConeTwistJoint3D`s at the hips, shoulders and neck. Parts are found by name: a mesh or any ancestor up to the figure saying `head`, `torso`/`chest`/`spine`/`hips`, or `arm`/`hand`/`leg`/`foot` with a side (`left`, `right`, `-l`, `-r`). The block characters and the humanoid mounts both match. A mesh that is none of those (a crest, the gun in the hand) rides on the nearest part.
- **stiff**: the whole figure as one rigid body. It still falls over properly, and it is what a figure with no named torso gets (a capsule), because there is nothing to hang limbs off.
- **topple**: no physics at all; a short scripted fall about the edge of the footprint, so it lands lying on the floor rather than half in it. This is the fallback `sv_ragdoll 0` gives: the cheapest body that still lies down, and one that works with no physics world.
- **hide**: the figure disappears, as everything did before.

## The server picks, every client falls

`DotPlayerDeath.decide(reactions, headshot, damage, direction, seed, weapon_def)` runs on the server and gives the reaction id and a seed; the game sends `to_dict()`'s keys with its kill message and every client calls `DotPlayerRagdolls.spawn(figure, DotPlayerDeath.from_dict(info))`. A client never picks.

- **Picking on each client would show different deaths on different screens**: one viewer sees a launch and the next a face plant. The pick is cheap and pure, so the server makes it once.
- **Nothing in a body calls `randf()`.** Its tumble and which way a crumple tips come from the death's seed, so two clients build the same fall. Physics is not bit-exact across machines, and does not need to be: the reaction, the direction and the strength agree, and where a hand ends up differs by centimetres nobody can see.
- **No pose travels.** A client already draws the victim where it is, and the ragdoll is copied from that drawn figure. Sending a pose would cost a snapshot's worth of bytes per death to correct a difference of a few centimetres.

## The reaction rule

`DotPlayerDeathReactions.pick(headshot, power, damage, weapon_named, seed)`:

1. A reaction the weapon names (its def's `params.death_reaction`) wins outright, if the server has not turned it off.
2. Otherwise every reaction with weight above zero whose conditions the kill meets (`needs_headshot`, `needs_power` against `min_power`, `min_damage`) goes into a weighted draw from the seed.
3. Nothing qualifying is `limp`, which always exists.

The stock set: `limp` (4), `headshot_launch` (6, headshots only), `power_launch` (8, weapons with `params.death_power` at least 0.5), `face_plant` (1.5), `crumple` (2.5). So a headshot launches about six times in fourteen and an ordinary kill never launches. A game adds its own with `add()`; a weapon picks by naming one or by its power. The suite asserts the shares by counting a thousand seeded picks, because a draw that is wrong by a factor of two still picks something every time.

**Weight zero is "off".** `sv_ragdoll_reactions face_plant=0,crumple=0` removes those from the draw, and a weapon naming one falls through to the draw rather than forcing what the server turned off.

## The cvars

`DotPlayerRagdollRules.bind_cvars(add_cvar, FLAG_REPLICATED)` on the server, `follow_cvars(link)` on each client, the same duck-typed shape as dot-combat's: a client draws the bodies, so the client is the one that needs the server's lifetime, cap and style.

| Cvar | Default | What |
| --- | --- | --- |
| `sv_ragdoll` | 1 | 0: no physics, the topple fallback |
| `sv_ragdoll_style` | ragdoll | ragdoll, stiff, topple, hide |
| `sv_ragdoll_time` | 10 | seconds a body lies there before the fade |
| `sv_ragdoll_max` | 8 | most bodies at once |
| `sv_ragdoll_force` | 1 | multiplies every push and launch; 0 drops bodies where they stood |
| `sv_ragdoll_reactions` | (stock) | `id=weight,...`; 0 turns one off |

## The cap

The server's `max_count` and the machine's `local_cap` (`default_local_cap()`: four on a machine without threads or a phone, so a browser tab, which simulates on its one thread), the lower. **The oldest body fades out quickly to make room, rather than the new one not appearing**, because the new one is the death somebody is looking at. Bodies that are fading do not count.

A settled body is frozen (`freeze_mode = STATIC`), which is what makes eight bodies on a floor cost nothing; one still moving after `max_sim_time` (wedged, jittering against a wall) is frozen anyway.

## Not through the floor

- **Continuous collision on every part**: a launched head moves a metre in a frame.
- **No box thinner than 8 cm**: a flat shape tunnels into a floor even with CCD.
- **No part of one body collides with another.** Blocks that overlap at a shoulder push apart on the first step, which is the exploding-ragdoll bug; the joints' limits keep limbs out of the torso instead.
- **Nothing collides with a body** (layer 0, mask the world's): no player trips on a corpse and no shot stops in one, so a body cannot change a match.

## A plank is one body, not tight joints

The face plant has to go over straight, stiff, and only go limp when the face hits the floor. The obvious way is to build the jointed body with joints a few degrees wide and widen them on landing. **On a hard landing five cone limits that tight threw the test figure a hundred metres**, with or without the widening. So the face plant is built as one rigid piece, rotated about the point under its toes, and `_become_jointed()` swaps in the jointed body where it lies, moving as it moved, when it lands. The same reason keeps `looseness` near 1 for every stock reaction.

A one-piece body has "landed" only when it is lying down (its up axis well off vertical): it starts standing on its own feet, and a contact report from its toes is not the face hitting the ground.

## Sounds

A reaction names a `start_sound` (the launches' whoosh) and a `land_sound` (a thud, the face plant's smack, a crumple's slump), played once, where and when the head or torso first hits something at `land_speed` or more. The bodies emit them; `DotPlayerRagdolls.sound_fn` (dot-audio's `play_at` fits) or its `sound` signal hand them to the game. The files are Kenney's CC0 impact and foley sounds in `addons/dot_player_char/death/sounds/` (credited in its `CREDITS.md`), described by `DotPlayerDeathSounds.rows()` as plain data, because this addon does not depend on dot-audio. The start sound is emitted deferred, since whoever built the body connects after `build` returns.

## The fade

After `sv_ragdoll_time` a body shrinks about one point on the floor under it and frees itself. **Not `GeometryInstance3D.transparency` alone**: the compatibility renderer, which every web client uses, ignores it, and a body that stays solid until it vanishes is exactly the pop the fade is for. It is set as well, for the renderers that honour it. One point for every part, so the parts close in together rather than each shrinking about its own middle and drifting apart, which is what the first version did.

## Looking at one

No assertion says whether a fall looks right. A frame sequence does: build a figure, `spawn` it with each reaction, and save frames at 0, 0.1, 0.2, 0.35, 0.5, 0.75, 1, 1.5, 2.5 and 4 seconds under `xvfb-run` (not `--headless`, which renders nothing), then look at them as a contact sheet. Every tuning number in the stock reactions came from doing that.

## What it does not do

No knees or elbows: a part is one body, so a block figure with one mesh per limb bends at the hip and shoulder only. A rig with separate upper and lower segments has them welded together. No skeletal (`PhysicalBone3D`) path: nothing here is skinned yet. No get-up, no blending from the ragdoll back into animation; a body is dead until it fades.
