extends RefCounted

## dot-player-char's API level. The rule for bumping it is on [DotAddonApi] (dot-core's
## docs/addon-api.md): LEVEL rises by one for anything a game could call that did not exist
## before; OLDEST is raised to LEVEL when something a game could have called is removed or
## changes meaning.

# 1: everything before this file existed (an absent file reads as 1).
# 2: dead bodies: DotPlayerRagdolls, DotPlayerRagdoll, DotPlayerRagdollRules, DotPlayerDeath,
#    DotPlayerDeathReaction(s), DotPlayerDeathSounds and death/sounds/. A pack that draws a
#    ragdoll needs a shell with this level, and says so in its requires.json.
const LEVEL := 2
const OLDEST := 1
