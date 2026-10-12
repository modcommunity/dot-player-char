# People

Why the family's players, bots and NPCs are drawn the way `DotHumanoidFigure` draws them, and why the obvious alternative is wrong in each case. The classes are `DotHumanoidLook` (what somebody looks like, as data), `DotHumanoidClips` (the clip set, retargeting, the made clips) and `DotHumanoidFigure` (the drawn person). The files are in `addons/dot_player_char/people/`, built by `tools/build_people.py`.

## One style for everybody, from one rig

Before this, each game drew its people its own way, and most drew Kenney's Blocky Characters: one 2.7 m body with eighteen painted skins, its animation node transforms on six rigid parts. game-zombie-zone then adopted animated skinned zombies, and its survivors (still blocks) stopped matching the zombies chasing them in every frame. That is the play test's complaint, and the family's answer is one rig for everybody.

The people are the four survivors of Quaternius' [Zombie Apocalypse Kit](https://quaternius.com/packs/zombieapocalypsekit.html) (CC0 1.0): `matt`, `lis`, `sam`, `shaun`. The reasons for this kit over the alternatives:

- **The zombies are already on it.** game-zombie-zone's zombies are the same kit's zombies, on the same rig with the same bone names, so a survivor and the thing chasing them are one style, and one ragdoll and one clip set serve both.
- **It is animated, and the clips are the family's list.** Idle, walk, run, the three again holding a gun, jump, fall, land, slash, stab, punch, a hit, a death, a dodge, a wave, yes and no. The zombie's crawl is the same rig, so a downed player crawls with it.
- **Kenney's kits are not.** Blocky Characters is rigid parts and Mini Characters has no skeleton; neither can bend a knee, which is what a crouch and a crawl are.
- Quaternius' Ultimate Animated Character Pack (also CC0, also downloaded and compared) has more costumes but thinner, smaller-headed bodies on a 23-bone rig: beside the kit's zombies it reads as a second art style, which is the problem being fixed.

Kenney's assets stay first everywhere else; for animated people there is no Kenney kit that does the job.

## Variety is colour, not texture

The four bodies share one atlas of flat swatches. A look is a body and four colours (skin, hair, top, bottom), and the figure's palette shader swaps each body's own swatches for the look's (`WEARS`, measured by `tools/people_palette.gd`). Four bodies times any colours is enough for a server of strangers to look different, a side's colour goes on the top (`with_side`), and a member's site avatar becomes colours too.

- **One material per look, no per-instance uniforms.** A look's material is built once and shared by everybody who wears it (`material_for`, keyed by `key()`), the choice game-zombie-zone's palette shader made for the compatibility renderer (every browser); a crowd of forty is a handful of materials.
- **The swap is matched in both colour spaces**, and answered in the one it matched: what a `source_color` sampler hands back differs by renderer, and game-zombie-zone's first palette shader, converting by hand, drew every zombie near black on one of them.
- **Colour arrays are `vec4`**: a `vec3` array is padded on the GPU, and a packed `Vector3` array set into one is read skewed.

## The site's avatar

The site's built-in avatar is Kenney's blocky kit: three slots (face, top, legs), each one of the eighteen skins `skin-a` to `skin-r`. `DotHumanoidLook.from_site` turns one into a person: the face's letter picks the body and gives the skin and hair colour, the top's and the legs' give the clothes. `SITE_SKINS` is the colour under the most area of each part of each skin, measured by `tools/kenney_site_colours.py`. A member who dressed as the robot is grey and red here; the person is recognisable without the block body.

It is duck-typed (`schema_id`, `part_in`), so this addon does not depend on dot-user-avatar, and it reads the site's `<slot>.<option>` part ids as well as bare ones: checking only the bare form once refused every real site avatar in six games.

## One clip set, carried to every body

Only `people_matt.glb` carries clips; the others are a quarter of the size without them. `DotHumanoidClips.retarget` carries the set onto each other body once and every figure of that body shares it.

**A clip stores where each bone is, not how far it moved.** Two bodies on one rig still differ in rest pose (here, at the shoulder and the head), and a clip played as it is on another body bends it. Each key is taken off the clip body's rest and put on the target's: rotation `to * from^-1 * key`, a position by the same turn about the new rest.

### The made clips

- **The crouch and the crouch walk are made, not drawn.** The kit has no crouch. Its duck is a dodge with both arms over the head; held at its lowest it reads as cowering. `synthesise` adds the duck's bend at its lowest frame (as a change from the idle pose, on the body and legs) to the idle and to the walk, so the idle's breathing and the walk's stride stay. A crouched player who stands up to walk reads as not crouching, which is the one thing a crouch has to say.
- **The jump, the fall and the landing are grounded.** The kit's are in-place jumps that lift the body (and the feet, which hang off the root in this rig) in the clip. A player in the air is already lifted by the game, so drawn as it is a falling player hung half a metre above their own capsule. The rise is taken out at every key; the landing's squat is kept.

### Not in the kit

- **Swimming** is a slow run with the whole body leaned forward 70 degrees about the hips (`_apply_swim`). There is no CC0 swim clip on this rig; this is a stand-in, and a real stroke is a queue item.
- **Climbing** plays the crawl.
- **Aiming up and down** is not drawn: the gun clips hold a gun level.

## Legs from the clip, arms from an overlay

A swing, a flinch and a gesture are one-shots that would stop the legs if played as the clip. The figure advances its `AnimationPlayer` by hand (`ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`) and then writes the upper body (`UPPER_BONES`) from the overlay, blended in and out, so a player swinging while running keeps running. Holding a gun in a clip that has no gun version (a crouch, the air) writes the held-gun arms the same way. Left to the engine, the clip and the overlay run in an order nothing controls, and an arm written before the clip is an arm the clip puts back.

**The gun hand is the left.** The kit's people hold a gun in the left hand and its gun clips are made that way. `attachment("right_hand")` (the family's mount name for "where a weapon goes", which `ZeeWorldModel` asks for) means that hand. The attachment's frame is worked out from the held-gun pose: forward is the figure's forward and up is up there, at metre scale whatever the body's, so a weapon model made pointing down -Z points where the clips aim.

## What a crowd costs

- One surface and one material per look; the bodies are decimated to 42% at build (2.6 to 3.7 thousand triangles; 55% was tried first and cost a fifth more for no difference anybody could see in the looks sheet) and Godot's generated LODs take them down with distance (`lod_bias` 0.4); nothing drawn past 140 m.
- **No shadow past 28 m** (`SHADOW_RANGE`). The shadow pass drew every person at full detail and was more than half of a crowd's triangles: thirty people measured 267 thousand primitives with every shadow and 110 thousand with none.
- The clip advanced every frame within 22 m of the camera, every second frame to 45 m, every fourth beyond, with the skipped time carried.
- Measured with `tools/people_sheet.gd --crowd=30` (thirty people running 6 to 30 m from the camera, each a different look) on the dev VM's software renderer (llvmpipe, a worst case, not a browser): 64 draw calls, 174 thousand primitives, about 50 ms a frame at 1280x720 in both renderers, 15 to 18 µs of script per person per frame; sixty people: 124 draw calls. A real browser on a real GPU is not measured.
- Animation is client side only; a server never builds a figure.

## The ragdoll, and a critical

A dead person falls by its bones through dot-player-char's own ragdoll, not a second one: see [ragdolls.md](ragdolls.md#a-skinned-body). A critical that takes a limb off bakes the limb out of the skin and shrinks its bones to the stump ([design.md](design.md#a-body-coming-apart-is-presentation-seeded-from-the-death)); `mend()` on respawn. `hide_head` shrinks the head bone for your own body in first person, where the camera is inside it.

## Looking at them

`tools/people_sheet.gd` (under `xvfb-run`, not `--headless`) renders every clip of every body at six moments (default), a sheet of stock and site looks (`--looks`), a skinned body falling with each reaction (`--ragdoll`) and a critical taking a limb and everything off (`--break`); add `--rendering-method gl_compatibility` to see what a browser sees. Every made clip and every number above came from looking at those.
