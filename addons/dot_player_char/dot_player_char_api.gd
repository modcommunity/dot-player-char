extends RefCounted

## dot-player-char's API level. The rule for bumping it is on [DotAddonApi] (dot-core's
## docs/addon-api.md): LEVEL rises by one for anything a game could call that did not exist
## before; OLDEST is raised to LEVEL when something a game could have called is removed or
## changes meaning.

# 1: everything before this file existed (an absent file reads as 1).
# 2: dead bodies: DotPlayerRagdolls, DotPlayerRagdoll, DotPlayerRagdollRules, DotPlayerDeath,
#    DotPlayerDeathReaction(s), DotPlayerDeathSounds and death/sounds/. A pack that draws a
#    ragdoll needs a shell with this level, and says so in its requires.json.
# 3: people and skinned bodies: DotHumanoidLook, DotHumanoidClips, DotHumanoidFigure, people/,
#    and DotPlayerRagdoll falling a skinned figure by its bones (skinned_meshes, skeleton_copy);
#    the right-handed (mirrored) clips, DotHumanoidFigure.aim, seat_height, `seated`, the made
#    sit and climb clips, the made swim stroke (DotHumanoidClips.SWIM, SWIM_CYCLE,
#    DotHumanoidFigure.SWIM_LEAN) and the crown mount (head_top / crest / hat). All before any tag.
# 4: the `driving` motion key and DotHumanoidClips.DRIVE (a retargeted Driving_Loop in people_ual.res).
# 5: DotHumanoidActions and DotHumanoidFigure.play_action/stop_action: the 13 starter emotes, poses and gestures.
# 6: DotHumanoidFigure.add_action_scene, DotHumanoidActions.from_upload/humanoid_bone_map/profile_bone_of: uploaded clips.
# 7: DotPlayerViewArms: your own crawling arms in first person while downed (arms_factory to replace them).
# 8: DotPlayerViewArms.set_held and DotViewGrip: the arms posed on a weapon mesh the host supplies.
# 9: DotHumanoidFigure.sprint_speed and DotHumanoidClips.SPRINT: a runner above it plays the real sprint clip.
# 10: DotFootPlant (feet planted over a gait phase) and DotHumanoidIk.two_bone_to.
# 11: DotHumanoidFigure.frame_delta: the game-time step pose() animates by, for a figure that wraps it.
# 12: DotHumanoidFigure.pose_record / pose_apply: a drawn pose kept and put back (a killcam replay).
const LEVEL := 12
const OLDEST := 1
