# Gibbable avatars

What an avatar must supply so Fatal Contact (FC) can take its limbs off like it does for the family's own people, and how to make that automatic so any rigged humanoid is gibbable without per-model work. Survey of 2026-11-16. Candidate packs are in the research note linked from the nightly item `fc-auto-gib-1`.

## How gibbing works today

Two implementations exist and neither is complete for imported avatars.

| | Player body (`nodes/dot_player_body_break.gd`) | NPC limbs (dot-npc `view/dot_npc_gibs.gd`, `runtime/dot_npc_limbs.gd`) |
| --- | --- | --- |
| Who decides | the game's `DotPlayerBreakRules` (cvars `break_mode`, `break_limbs`, `break_criticals_only`), seeded from victim and tick | the server's `DotNpcLimbs` (per-limb health, `sever`, replicated mask); config yml names each limb's bones |
| Limb = | every bone of one role (head, arm L/R, leg L/R) plus all bones below, role from bone **name** (`DotRagdollScan.role_of_name`) | the bones listed in the limb definition |
| Cut | each triangle goes to the limb that owns its strongest-weighted vertex bone (`bake_bones`), baked as posed into a plain mesh and thrown as a `RigidBody3D` | same idea (`DotNpcGibs`, cut by vertex weight, cached per mesh) |
| What is left | the top bones scaled to 0.001; **no cap**, so the torso shows an open hole and the piece is a hollow shell | bone collapsed, a drawn **stump** (flesh collar, muscle ring, bone disc, marrow dot), drip and wound marks, floor pools |
| Blood and gore level | none | `DotNpcGore` level, with gib and wound caps (cvars, not hard numbers) |
| Undo | `DotHumanoidFigure.mend()` on respawn | `DotNpcGibs.restore` |

Everything else a body needs on death already exists and works on any skinned figure: `DotPlayerRagdoll` builds six jointed parts from the skeleton's roles (skinned or rigid), with reactions and a fade (docs/ragdolls.md). The decal art (`dot-fx` `gibs.png`, `blood_splatter.png`) is shared.

## What an avatar must supply

1. **One skinned humanoid model** (glTF/GLB): a single `Skeleton3D`, meshes skinned to it with per-vertex weights, at most the usual 4 influences. Separate meshes per limb are NOT needed and are not used: cutting is by weight.
2. **Bone names the role finder understands**, or a `BoneMap`. Today: any name containing head/skull, arm/hand/shoulder/elbow, leg/foot/thigh/shin/knee with a left/right marker (`_l`, `.R`, `Left...`). Verified by reading the code for the three rigs of interest: Mixamo (`mixamorig:LeftArm`, `LeftUpLeg`, `LeftFoot`; toes and fingers hang under their parent so are carried), Quaternius Universal (`upperarm_l`, `thigh_l`, `calf_l` under thigh, `hand_l`), Quaternius kit (the people). Gaps: `calf`, `clavicle` and `toe` match nothing (carried by the subtree rule, but a rig whose first leg bone is called `calf` or whose root bone is a pelvis-less `root` would give an empty role). Auto-gib must not depend on names alone (see below).
3. **Water-tight enough skinning**: each limb's triangles must be mostly weighted to that limb's bones. Smooth weights at a joint make a ragged cut edge; the cap hides it.
4. **Materials**: a normal PBR material set. The cap and stump need none from the avatar: they use the shared flesh, muscle and bone materials. Cut pieces keep the avatar's own surfaces so a gib looks like the person (uniform colour included).
5. **Team colour**: expressed as a tint on a named material or a swappable albedo, never as a baked mesh, so gibs inherit it (they copy the surface material).
6. **Animations** (the avatar may ship none; FC retargets its own set to the avatar's skeleton, as `tools/ual_retarget.gd` does for the UAL via a bone map): idle, walk, run, strafe (8 directions), crouch idle and walk, jump, fall, land, aim and fire with the weapon held (rifle and pistol grips), reload, hit (chest, head), death, ragdoll (no clip: physics from the skeleton). The family list in docs/people.md covers idle, walk, run, the gun variants, jump, fall, land, crouch, crawl, hit, death, slide and sit; strafe, fire and reload are not in it today and are the real animation gap.
7. **Scale and tris**: about 1.6 to 1.9 m tall, rest pose T or A facing +Z, at most 20k tris for LOD0 (web), a LOD1 near 6k. The cut works on the LOD0 arrays; cost is linear in triangles, so it is cached per mesh and avatar.
8. **Licence record**: source URL, author, licence, credit text, in the asset manifest and FC credits (CC-BY needs the credit shown).

## Can any rigged mesh be gibbed automatically? Yes, with these additions

Splitting by bone weight needs only a skeleton and skin weights, which every animated humanoid has. What is missing is not the split, it is the cap, the blood, a role finder that does not trust names, and one shared implementation.

**Auto-gib pipeline (run once per avatar at load, cached by mesh id):**

1. **Role map.** Resolve each bone to HEAD, ARM_L/R, LEG_L/R, TORSO by (a) a `BoneMap` or Godot's `SkeletonProfileHumanoid` when the avatar carries one (`DotHumanoidActions.profile_bone_of` already guesses a humanoid map from names), then (b) the existing name rule, then (c) geometry as the last resort: the five largest subtrees by hanging off the pelvis/spine, classified by rest position (up = head, left/right of the spine axis = arm if above the hip height else leg). A rig that cannot be classified is a loud error naming the bones, never a silent "no gibs".
2. **Cut levels.** Per role, a list of cut joints (head at neck; arm at shoulder, elbow, wrist; leg at hip, knee, ankle), all from data, so a game chooses a clean limb or a segment. Hand-held items and wearables ride the bone and go with the piece.
3. **Weighted split.** Triangles assigned by dominant bone among the piece's bones (as `bake_bones`); a triangle straddling the cut is cut at the joint plane (clip and re-triangulate) instead of assigned whole, so the edge is straight and the cap can close it. Cached triangle-to-bone arrays per surface avoid re-reading weights per death.
4. **Cap, generated.** Walk the boundary edges between the kept and cut triangles to get the cut loop, fill it with a fan around its centroid, with an inner muscle ring and a bone disc (the look `DotNpcGibs` already builds for stumps), UV-free flat materials. The same loop closes both the piece and the stump left on the body, so neither is hollow. For the body, hide the cut triangles with the collapsed bone as now (no stretched slivers) but draw the cap on the parent bone.
5. **Effects.** Blood burst, wound marks and floor pool through the existing `DotNpcGore` levels and `dot-fx` decals; gib pieces fade with `DotPlayerBreakRules`. Gore off or headless: nothing is built.
6. **Server and net.** Nothing new on the wire: the server already sends the death and the seed; the cut is presentation, identical for every viewer by the seed.

**One implementation, not two.** `DotNpcGibs` and `DotPlayerBodyBreak._break_skinned` are the same algorithm with different decoration. Do not write a third: put the cut and the cap in one class both call (the implementer checks the dependency direction between dot-npc and dot-player-char; dot-player-char requires only dot-core and dot-player), and let the NPC path keep its limb-health rules on top.

## Cost and limits

No hard caps: piece counts, cut joints, gore level and lifetime are cvars (0 means unlimited where a count). The cut is a one-shot per death (not per frame); measure it on a 20k-tri avatar and record the time in the item. A 70k-tri model is not a gib problem, it is a web-budget problem; slim it first (fc-swat-avatar-1).

## Acceptance (see `fc-auto-gib-1`)

An avatar that supplies only a skinned rig, with no gib-specific data, can lose any limb in FC with a closed cap on both the piece and the body, blood, and the same result for every viewer, verified on the Quaternius people, the UAL mannequin and a Mixamo-rigged SWAT operator.
