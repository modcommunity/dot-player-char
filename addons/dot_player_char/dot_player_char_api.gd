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
const LEVEL := 5
const OLDEST := 1
