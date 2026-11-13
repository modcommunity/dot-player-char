# History

Decisions and bugs worth recognising if they come back. The lessons that still apply are rules in [CLAUDE.md](../CLAUDE.md) and [design.md](design.md).

## It was four addons

`dot-player-char-model`, `dot-player-char-sprite` and `dot-player-char-animations` were separate and were merged in. None of the three was ever pushed. None was useful without this one and none was useful beside another, so the split bought three repositories and nothing else, and two of the seams between them existed *only* to avoid a dependency. Both seams stayed, for the reasons in [design.md](design.md#the-two-seams). The one thing that did not stay was a duplicated 2D heading helper in `DotPlayerAnimDriver`, kept only so a 3D game need not install the sprite addon; it is `DotPlayerSpriteFacing.angle_of` now.

## Every body stood at the world origin

`DotPlayerModelVisual` kept its rig as its own child, and a visual is a plain `Node`, so every body drawn through it stood at the world origin whatever its player did; `DotPlayerSpriteVisual`'s sheet stood at the canvas origin the same way. No suite could see it: every check asked what was built, none asked where it was. game-playlot, the one game drawing through it, drew every player at (0, 0, 0), hidden for months because its lobby spawn *is* the origin, and worked round it from the game until `seat()` existed ([design](design.md#a-visuals-drawn-node-hangs-off-the-player-not-off-the-visual)). A check that asks *what* was built says nothing about *where*; see [docs/testing.md](../../../docs/testing.md).

## A person's face plant stood back up

Game-zombie-zone's survivors, the first people to die holding guns, were rendered face-planting and stayed on their feet for good. The plank (the face plant's one rigid piece) was boxed round every bone's posed points plus each copied mesh's bounds; a skinned mesh's bounds are its rest pose, arms out, and a gun in the hand added another half metre in front, so the box was about as deep as it was wide. The 1.6 rad/s spin about the toes, damped at the floor-flapping rate of 1.5, ran out long before the top passed the toes, and the body rocked back upright and froze. The unarmed person in the suite fell, slowly, so nothing failed. The plank is now boxed round the head, body and legs alone and spins undamped until it lands; `ragdoll_selftest` face-plants a person holding a long gun out and fails on the old code.

The same evening mg-prop-hunt's hunters, killed with a gun in the hand, fell limp and stayed kneeling, torso 0.67 m up, for as long as they lay there: the arm's box was merged with the held gun's mesh bounds, and a rigid stick half a metre long under the body held it up. Held things are now drawn on their part and never collided.

## API levels

- Level 1: everything before this file existed (an absent file reads as 1).
- Level 2: dead bodies: DotPlayerRagdolls, DotPlayerRagdoll, DotPlayerRagdollRules, DotPlayerDeath, DotPlayerDeathReaction(s), DotPlayerDeathSounds and death/sounds/. A pack that draws a ragdoll needs a shell with this level, and says so in its requires.json.
- Level 3: people and skinned bodies: DotHumanoidLook, DotHumanoidClips, DotHumanoidFigure, people/, and DotPlayerRagdoll falling a skinned figure by its bones (skinned_meshes, skeleton_copy); the right-handed (mirrored) clips, DotHumanoidFigure.aim, seat_height, `seated`, the made sit and climb clips, the made swim stroke (DotHumanoidClips.SWIM, SWIM_CYCLE, DotHumanoidFigure.SWIM_LEAN) and the crown mount (head_top / crest / hat). All before any tag.
- Level 4: the `driving` motion key and DotHumanoidClips.DRIVE (a retargeted Driving_Loop in people_ual.res).
- Level 5: DotHumanoidActions and DotHumanoidFigure.play_action/stop_action: the 13 starter emotes, poses and gestures.
- Level 6: DotHumanoidFigure.add_action_scene, DotHumanoidActions.from_upload/humanoid_bone_map/profile_bone_of: uploaded clips.
- Level 7: DotPlayerViewArms: your own crawling arms in first person while downed (arms_factory to replace them).
- Level 8: DotPlayerViewArms.set_held and DotViewGrip: the arms posed on a weapon mesh the host supplies.
- Level 9: DotHumanoidFigure.sprint_speed and DotHumanoidClips.SPRINT: a runner above it plays the real sprint clip.
- Level 10: DotFootPlant (feet planted over a gait phase) and DotHumanoidIk.two_bone_to.
- Level 11: DotHumanoidFigure.frame_delta: the game-time step pose() animates by, for a figure that wraps it.
- Level 12: DotHumanoidFigure.pose_record / pose_apply: a drawn pose kept and put back (a killcam replay).
- Level 13: DotHumanoidLegs (legs.twist, backward walk, wall feet; the `velocity` and `wall` motion keys), DotHumanoidOwnView and DotHumanoidFigure.first_person (your own legs or body, shadow kept).
- Level 14: DotPlayerViewArms.debug_pose and DotViewArmsPoseDebug: sockets, hand targets and arm bone axes drawn over the view.
- Level 15: DotPlayerViewArms.hand_error(grip): how far the hands are from a grip, for a game's tests and tools.
- Level 16: DotPlayerHitboxes and DotPlayerHitboxPlan: optional config-driven hit zones (off by default).
- Level 17: DotOwnBodySetting (the client-only `cl_legs` setting) and DotHumanoidFigure.own_body_shown.
- Level 18: DotHumanoidFigure.own_look_down_back (DotHumanoidOwnView.look_down_back, back_for): in first person your own body trails behind the eye as the view tips past 40 degrees down, by default; a game that places the body itself sets it to 0.
- Level 19: first-person arms dressed and kept clear of the gun: DotViewArmsMaterial (skin and cloth detail over the palette swap), DotViewGrip.bounds/bounds_local, DotPlayerViewArms.set_look_override/own_look (a server-chosen arm set over the player's own), detailed, keep_arms_clear, arm_radius, arm_depth_right/left, and palm_offset defaulting to the side of the grip.
- Level 20: DotHumanoidAssets.prepare_libraries / poll_libraries: the shared clip set and body retargets built on a worker thread (or one per poll without threads), so no frame pays the 150 ms build. Models are instanced on the main thread and nothing waits on the worker: a node made off the main thread, or a main-thread wait on a worker that needs the main thread, deadlocked the first try; `library_for` during a build builds the set itself.
- Level 21: DotHumanoidFigure.floor_mask / floor_reach / floor_lift and DotHumanoidLegs.floor_lift: the drawn body stood on the floor under its origin (an origin interpolated across a step's riser no longer sinks it); `on_floor` takes the lift.
- Level 22: third-person gun carry: DotHumanoidCarry (per-class stances), DotHumanoidCarryPose as DotHumanoidFigure.carry (set_class, fired, raised / reloading / switching); DotHumanoidIk.two_bone_under. `sprint_blend` falls to 0 while the figure draws the carry, so a held weapon does not add its own sprint swing on top.
