extends Node3D

## [DotPlayerRagdoll]'s constants, part record and state, split out to keep each file small.

const CHANNEL := "player.ragdoll"
const PLANK_MIN_SPIN := 1.6
const PLANK_PUSH_SECONDS := 1.0
## How long a face plant's plank may stand still on its feet before it goes limp where it is.
const PLANK_STALL_SECONDS := 0.15
## A plank still on its feet this long after death lets go whether or not it is still, so a jittering
## contact (a prop it shoves, a cushion edge) cannot hold it up until max_sim_time freezes it standing.
const PLANK_GIVE_UP_AGE := 2.5

## A body's sound: the reaction's start or land sound, where, and how hard (0 to 1).
signal sound(id: StringName, position: Vector3, strength: float)

## Every part has stopped and been frozen.
signal settled_now

enum Role { TORSO, HEAD, ARM_L, ARM_R, LEG_L, LEG_R, OTHER }

## Share of the body's mass each part carries; renormalised over the parts a figure has.
const MASS_SHARE := {
	Role.TORSO: 0.46, Role.HEAD: 0.08, Role.ARM_L: 0.055, Role.ARM_R: 0.055,
	Role.LEG_L: 0.175, Role.LEG_R: 0.175,
}

## How far each joint swings and twists, in degrees, before [member DotPlayerDeathReaction.looseness].
## A shoulder swings far and a neck does not; a hip in between. Cone limits are symmetric, so a
## knee-less leg folds as far back as forward, which a block figure cannot show anyway.
const SWING_DEG := {
	Role.HEAD: 40.0, Role.ARM_L: 95.0, Role.ARM_R: 95.0, Role.LEG_L: 60.0, Role.LEG_R: 60.0,
}
const TWIST_DEG := {
	Role.HEAD: 35.0, Role.ARM_L: 40.0, Role.ARM_R: 40.0, Role.LEG_L: 15.0, Role.LEG_R: 15.0,
}

## The part a body was built as: one rigid body (or, for TOPPLE, one node) and its role.
class Part:
	extends RefCounted
	var role: int = Role.OTHER
	var body: Node3D = null
	var joint: ConeTwistJoint3D = null
	var copies: Array[MeshInstance3D] = []
	## Each copy's transform as built, for the fade to shrink from.
	var copy_rest: Array[Transform3D] = []
	var size: Vector3 = Vector3.ZERO
	## The box's centre in the body's own space.
	var local_centre: Vector3 = Vector3.ZERO
	## The joint's frame in this part's own space, for rebuilding it where the part now is.
	var joint_local: Transform3D = Transform3D.IDENTITY
	## A skinned body's bones this part carries, and each one's transform in the part's frame.
	var bones: PackedInt32Array = PackedInt32Array()
	var bone_offsets: Array[Transform3D] = []
	## Where its joint goes, in world space when built; INF for "work it out from the box".
	var pivot: Vector3 = Vector3.INF

var rules: DotPlayerRagdollRules = null
var reaction: DotPlayerDeathReaction = null
var death: DotPlayerDeath = null

## What this body was built as; see [enum DotPlayerRagdollRules.Style].
var style: int = DotPlayerRagdollRules.Style.RAGDOLL

## Seconds since death.
var age: float = 0.0

## Every part stopped and frozen.
var settled: bool = false

## The land sound has played.
var landed: bool = false

## Fading out, early or on time.
var expiring: bool = false

var _parts: Array[Part] = []
var _fade_from: float = -1.0
var _fade_len: float = 1.0
var _still_for: float = 0.0
var _fastest: float = 0.0
var _fade_pivot: Vector3 = Vector3.ZERO
var _last_speed: Dictionary = {}
var _last_pos: Dictionary = {}
var _anchor: Vector3 = Vector3.ZERO
var _jointed_on_land: bool = false
## A face plant's push, kept up until the plank is past tipping: the axis it turns about (ZERO when
## not pushing), the toe edge it turns round, and how long it has been pushed.
var _plank_axis: Vector3 = Vector3.ZERO
var _plank_pivot: Vector3 = Vector3.ZERO
var _plank_time: float = 0.0
var _source_roles: Dictionary = {}
var _topple_axis: Vector3 = Vector3.ZERO
var _topple_pivot: Vector3 = Vector3.ZERO
var _topple_angle: float = 0.0
var _topple_spin: float = 0.0
var _topple_start: Transform3D = Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()
var _sim_from: float = 0.0

# A skinned body: a copy of the figure's skeleton with copies of its skinned meshes on it, whose
# bones follow the parts (see [method _pose_bones]).
var _skel: Skeleton3D = null
var _skel_base: Transform3D = Transform3D.IDENTITY
var _skinned: Array[MeshInstance3D] = []
var _skinned_rest: Array[Transform3D] = []
var _bone_roles: PackedInt32Array = PackedInt32Array()
var _bone_order: PackedInt32Array = PackedInt32Array()
# Reused by [method _pose_bones_script] and the native plan, so posing allocates nothing per frame.
var _wanted: Dictionary = {}
var _plan_bodies: Array[Node3D] = []
var _plan_offsets: Array[Transform3D] = []
