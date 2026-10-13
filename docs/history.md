# History

Decisions and bugs worth recognising if they come back. The lessons that still apply are rules in [CLAUDE.md](../CLAUDE.md) and [design.md](design.md).

## It was four addons

`dot-player-char-model`, `dot-player-char-sprite` and `dot-player-char-animations` were separate and were merged in. None of the three was ever pushed. None was useful without this one and none was useful beside another, so the split bought three repositories and nothing else, and two of the seams between them existed *only* to avoid a dependency. Both seams stayed, for the reasons in [design.md](design.md#the-two-seams). The one thing that did not stay was a duplicated 2D heading helper in `DotPlayerAnimDriver`, kept only so a 3D game need not install the sprite addon; it is `DotPlayerSpriteFacing.angle_of` now.

## Every body stood at the world origin

`DotPlayerModelVisual` kept its rig as its own child, and a visual is a plain `Node`, so every body drawn through it stood at the world origin whatever its player did; `DotPlayerSpriteVisual`'s sheet stood at the canvas origin the same way. No suite could see it: every check asked what was built, none asked where it was. game-playground, the one game drawing through it, drew every player at (0, 0, 0), hidden for months because its lobby spawn *is* the origin, and worked round it from the game until `seat()` existed ([design](design.md#a-visuals-drawn-node-hangs-off-the-player-not-off-the-visual)). A check that asks *what* was built says nothing about *where*; see [game-dev/docs/testing.md](../../../docs/testing.md).

## A person's face plant stood back up

Game-zombie-zone's survivors, the first people to die holding guns, were rendered face-planting and stayed on their feet for good. The plank (the face plant's one rigid piece) was boxed round every bone's posed points plus each copied mesh's bounds; a skinned mesh's bounds are its rest pose, arms out, and a gun in the hand added another half metre in front, so the box was about as deep as it was wide. The 1.6 rad/s spin about the toes, damped at the floor-flapping rate of 1.5, ran out long before the top passed the toes, and the body rocked back upright and froze. The unarmed person in the suite fell, slowly, so nothing failed. The plank is now boxed round the head, body and legs alone and spins undamped until it lands; `ragdoll_selftest` face-plants a person holding a long gun out and fails on the old code.
