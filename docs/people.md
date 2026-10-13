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
- **Sitting is a real clip, with a made one under it** ([below](#real-clips-from-the-universal-animation-library)). The made sit (`_sat`, from the idle's first frame: the thighs laid forward level, the shins hanging straight down, the feet flat under the knees, the body dropped until they are on the floor) is what a figure plays when `people_ual.res` is missing. A figure with `seated` in its motion plays the sit whatever speed it is carried at, and `seat_height()` (about 0.28 m at 1.8 m: these are short cartoon legs) is how far under the seat a game puts the figure's origin. A rider drawn crouching, the stand-in before both, was somebody squatting over the cushion.
- **Climbing is made from the idle too** (`_climbing`): one knee lifted to the next rung while the other leg straightens, the hands over the head with the one on the straight leg's side higher, one second a cycle and played as fast as the player climbs. The body is pushed up until the lower foot is where the feet stood (the idle stands on bent knees, and a straight leg would put its foot through the origin), which is also the pull-up. The crawl it played before was somebody lying on their front, drawn upright on a ladder.
- **Swimming is a made front crawl** (`_swimming`), drawn upright and laid forward about the hips by the figure (`SWIM_LEAN`, about 80 degrees), so in the clip "up" is ahead of the swimmer, "front" is down into the water and "back" is up out of it. Each arm goes round the body's side half a turn from the other: the reach, a bent-elbow pull under the chest, the finish at the thigh, and a recovery swung wide and low with the hand hanging towards the water. The first try was a windmill in the body's plane, and a recovering arm stood straight up like a mast. The body rolls towards the pulling arm, the head turns to breathe on the right once a stroke, and the legs flutter three kicks to a stroke with the toes pointed. One stroke is `SWIM_CYCLE` (1.6 s), played faster with speed. A swimmer holding a gun does not get the held-gun arms: the stroke is the arms. The stand-in before was the run, slowed and leaned 70 degrees. Looked at in `people_sheet.gd --swim` (side, ahead and above, behind and above, with a water surface at the hips).
- **The feet hang off the root on this rig** (for the kit's own leg IK, which nothing here runs), not off the shins. A made pose that moves a leg moves its foot to where the shin now ends, and measures the shin before it moves the body: the first sit took it after the drop, so the shin was a quarter shorter and the feet floated.
- **The jump, the fall and the landing are grounded.** The kit's are in-place jumps that lift the body (and the feet, which hang off the root in this rig) in the clip. A player in the air is already lifted by the game, so drawn as it is a falling player hung half a metre above their own capsule. The rise is taken out at every key; the landing's squat is kept.

### Not in the kit

- **A figure something else carries** (an NPC on a physics body) sets `auto_animate`: it measures how far it moved each frame and animates from that.
- **A real ladder climb** would be better than the made one above; no free CC0 clip has one (see the next section). Nor does any have a seat with the arms on armrests: the real sit has the hands in the lap.

## Real clips from the Universal Animation Library

Quaternius' [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) (CC0 1.0) is the same artist's clip library, on a different skeleton: a 65-bone mannequin about 1.8 tall, with a hand bone, three-joint fingers and the feet under the shins, where the kit has 43 bones, is about 1.1 tall, and hangs its feet off the root. `tools/ual_retarget.gd` carries a clip across and saves it into `people/people_ual.res`, and `DotHumanoidClips.adopt` puts each clip in that file over the made one of the same name, after the mirror and the made clips (the library is right-handed already).

- **Turned in skeleton space, not copied locally.** Both rigs rest in a T pose facing +Z, so each kit bone gets how far its mapped bone turned from rest in the skeleton's space (`turn = ual_global * ual_rest_global^-1`, then `turn * kit_rest_global`). Local rotations cannot be copied: the bones' own axes differ. Bone lengths stay the kit's; the hips' travel is scaled by the ratio of hip heights; a foot is put where its shin now ends (as the made clips do); a grounded clip is then moved until its lower foot is where the rest pose's feet are.
- **The bone map** (`MAP`): `Body` is the pelvis and `Hips`, `Abdomen`, `Torso` the three spine bones; the kit's `Middle1`, `Index1` and `Pinky1` all start at the wrist and are the palm, so they follow the hand, and their second and third joints follow the first two finger joints.
- **The free version has no ladder climb.** Standard (free, 43 clips) has sitting, crouching, swimming, driving and pistol aims; climbing is only in the paid Pro and Source versions, so it is not used. The second library's free Standard has `ClimbUp_1m`, a mantle onto a ledge, which is not a ladder.
- **What was compared and kept**, each rendered beside the made clip with `people_sheet.gd --compare` (the file's clips, made and real, three-quarter and side) and looked at:
  - `sit` from `Sitting_Idle_Loop`: **kept.** Upright, hands resting on the thighs, breathing; the made sit held both arms out over the knees as if reaching for something.
  - `crouch` from `Crouch_Idle_Loop` and `crouch_walk` from `Crouch_Fwd_Loop`: **not kept.** A deep squat with the head down and the knuckles on the floor: it reads as hiding, not as a player crouched and looking ahead, and the hands on the floor fight the held-gun arms. The made crouch stays.
  - `swim` from `Swim_Fwd_Loop` (stood up about the hips with `^`, since the figure lays the swim down itself): **not kept.** A head-up stroke whose arms swing out level to the sides at one point of the cycle; not clearly better than the made crawl, which was tuned frame by frame.
  - `Driving_Loop` (hands on a wheel) and `Sitting_Talking_Loop` read well but have no made clip to replace and no motion that asks for them; a driver pose would need a `driving` motion from the games (queue item `people-drive-clip-1`).
- **Cost:** `people_ual.res` is 16 KB (one clip, 1.67 s at 15 keys a second, still tracks kept to one key, compressed); the six candidates together were 110 KB.

## Aiming up and down

`aim(pitch_radians)` (up positive; a first-person controller's `state.pitch` is degrees) bends the upper body after the clip and the overlays: the waist and chest a little under a quarter of the pitch, the neck a quarter more so the head reads as looking there, and the weapon arm the rest at the shoulder when the hand holds something, so the gun points the whole way (`AIM_BONES`, `AIM_ARM`). The other arm hangs as the clip has it. Held to about 66 degrees; nothing while down, dead, swimming or climbing. Looked at in `people_sheet.gd --aim` (standing, front, crouched and seated, from straight down to straight up).

- **Most of the pitch goes to the arm, not the spine.** The first try put it all in the waist and chest: on a cartoon-proportioned body a player looking down was bowing and one looking up was falling over backwards.
- **The parents' poses come from the local poses up the chain**, not `get_bone_global_pose`, which is last frame's until the skeleton updates (with last frame's bend in it). Each bone's share goes on as `P^-1 * turn * P * local` with every `P` read before anything turns: turns about one axis commute.
- **Only on a bone the playing clip keys.** A bone no track writes keeps last frame's pose, and a bend put on it would add up frame after frame.
- A game passes it as `"aim"` in `set_motion` (left out, it stays). A remote player is drawn aiming only if the game sends the pitch; the games' snapshots already carry it for the view.

## Legs from the clip, arms from an overlay

A swing, a flinch and a gesture are one-shots that would stop the legs if played as the clip. The figure advances its `AnimationPlayer` by hand (`ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`) and then writes the upper body (`UPPER_BONES`) from the overlay, blended in and out, so a player swinging while running keeps running. Holding a gun in a clip that has no gun version (a crouch, the air) writes the held-gun arms the same way. Left to the engine, the clip and the overlay run in an order nothing controls, and an arm written before the clip is an arm the clip puts back.

**The gun hand is the right, because the clips are mirrored.** The kit's people are left-handed: every weapon in it hangs off `Middle1.L`, and its gun and melee clips hold them there. The family's first-person view models are right-handed, so everybody else saw a player hold the gun in the other hand from the one they saw it in. `DotHumanoidClips.mirror` turns the whole set left for right once, when it is loaded (before the made clips and the retarget): each `.L` track becomes the `.R` bone's and every key is reflected across the middle (a rotation's y and z negated, a position's x). That is exact because the rig is symmetric (each `.R` rest is the `.L` rest reflected, measured to the thousandth). The whole set rather than the gun clips alone, so a swing, a punch and a wave are the same hand as the gun. `attachment("right_hand")` (the family's mount name for "where a weapon goes", which `ZeeWorldModel` asks for) is `Middle1.R`. The attachment's frame is worked out from the held-gun pose: forward is the figure's forward and up is up there, at metre scale whatever the body's, so a weapon model made pointing down -Z points where the clips aim.

**A hat or a crest goes on the crown.** `attachment("head_top")`, `"crest"` or `"hat"` is one mount on the head bone at the top of the mesh, upright and at metre scale, so it nods with the head and shrinks with it in first person (`hide_head`).

## What a crowd costs

- One surface and one material per look; the bodies are decimated to 42% at build (2.6 to 3.7 thousand triangles; 55% was tried first and cost a fifth more for no difference anybody could see in the looks sheet) and Godot's generated LODs take them down with distance (`lod_bias` 0.4); nothing drawn past 140 m.
- **No shadow past 28 m** (`SHADOW_RANGE`). The shadow pass drew every person at full detail and was more than half of a crowd's triangles: thirty people measured 267 thousand primitives with every shadow and 110 thousand with none.
- The clip advanced every frame within 22 m of the camera, every second frame to 45 m, every fourth beyond, with the skipped time carried.
- Measured with `tools/people_sheet.gd --crowd=30` (thirty people running 6 to 30 m from the camera, each a different look) on the dev VM's software renderer (llvmpipe, a worst case, not a browser): 64 draw calls, 174 thousand primitives, about 50 ms a frame at 1280x720 in both renderers, 15 to 18 µs of script per person per frame; sixty people: 124 draw calls.
- **In a browser** (2026-10-12): `tools/crowd_bench.tscn` as the main scene of a scratch web export (no threads, compatibility renderer), in headless Chromium 150 with WebGL2 on SwiftShader (the VM has no GPU, so this is software rendering again, a worst case): thirty people at 1280x720, 76 draw calls, 190 thousand primitives, about 220 ms a frame, 42 µs of script per person per frame (the WebAssembly build is between two and three times the native one); with four of them fallen as skeletal ragdolls, 68 draw calls, 169 thousand primitives, 174 ms. The draw calls and primitives are what a GPU would get; the frame time is not. **A browser on a real GPU is still not measured** (queue item `people-browser-measure-1`).
- Animation is client side only; a server never builds a figure.

## The ragdoll, and a critical

A dead person falls by its bones through dot-player-char's own ragdoll, not a second one: see [ragdolls.md](ragdolls.md#a-skinned-body). A critical that takes a limb off bakes the limb out of the skin and shrinks its bones to the stump ([design.md](design.md#a-body-coming-apart-is-presentation-seeded-from-the-death)); `mend()` on respawn. `hide_head` shrinks the head bone for your own body in first person, where the camera is inside it.

## Looking at them

`tools/people_sheet.gd` (under `xvfb-run`, not `--headless`) renders every clip of every body at six moments (default), a sheet of stock and site looks (`--looks`), a skinned body falling with each reaction (`--ragdoll`) and a critical taking a limb and everything off (`--break`); add `--rendering-method gl_compatibility` to see what a browser sees. Every made clip and every number above came from looking at those.

**A game newly linking this addon re-imports before rendering.** mg-look-at-me's first `--import` after the link registered the classes but left `people/` unimported: the figure fell back to its capsule (with a `player.humanoid` warning) and every suite passed. A second `--import` imported the bodies.
