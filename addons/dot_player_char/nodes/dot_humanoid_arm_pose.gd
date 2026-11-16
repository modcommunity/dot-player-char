extends RefCounted

## The arms of a [DotHumanoidFigure] holding a blade or nothing, written over the clip: a knife throw's windup
## (the arm cocked back by the meter) and release, and a sprint's pumping arms. Drawn only; distances are in
## arm lengths so every body size and clip set gets the same pose.

const ARM_R: Array[String] = ["UpperArm.R", "LowerArm.R", "Middle1.R"]
const ARM_L: Array[String] = ["UpperArm.L", "LowerArm.L", "Middle1.L"]
const CHEST_BONE := "Torso"

## The hand fully cocked, from the right shoulder in arm lengths (figure frame: +X right, +Y up, -Z forward):
## beside the ear and behind it, the elbow out to the side and back.
const COCKED := Vector3(0.12, 0.42, 0.42)
const COCKED_POLE := Vector3(1.0, -0.1, 0.5)
## The share of the windup shown at a meter of 0: the arm has started back the moment the button is held.
const COCK_START := 0.25
## The chest turns the throwing shoulder back by this much at full windup, and through to the other side on release.
const TWIST_DEG := 22.0
const FOLLOW_TWIST_DEG := -18.0

## Seconds: the windup easing in, holding after the meter stops (the release usually lands then), and easing out.
const WIND_IN := 0.1
const WIND_HOLD := 0.15
const WIND_OUT := 0.2
const RELEASE_SECONDS := 0.42

## The release path from the right shoulder, in arm lengths: [fraction, hand, elbow pole].
const RELEASE_KEYS: Array = [
	[0.28, Vector3(0.02, 0.12, -0.92), Vector3(1.0, -0.6, 0.2)],
	[0.6, Vector3(-0.32, -0.5, -0.6), Vector3(1.0, -0.3, 0.4)],
]

## The sprint: the upper arm swings this far either side of hanging, the elbow is bent this much past
## straight, and the hands come in toward the middle by this share of an arm.
const RUN_SWING_DEG := 38.0
const RUN_ELBOW_DEG := 92.0
const RUN_INWARD := 0.12
const RUN_SECONDS := 0.2
## Metres a full stride (two steps) covers when the clip gives no stride phase.
const RUN_STRIDE := 2.4

## The throw meter as the game reports it, 0 to 1 while winding up, below 0 when not.
var charge := -1.0

## Shown: how far the windup is drawn (0 to 1) and the meter it is drawn at; the release's fraction (1 or more is
## none playing) and the windup it started from; the sprint arms' blend and their phase, 0 to 1 a stride.
var wind := 0.0
var cocked := 0.0
var release_at := 1.0
var release_from := 0.0
var run := 0.0
var run_phase := 0.0

var _hold_left := 0.0
var _keyed: Dictionary = {}


## Starts the release from wherever the windup is drawn.
func release() -> void:
	release_from = wind * _cock_share()
	release_at = 0.0
	wind = 0.0
	_hold_left = 0.0


## One frame: [param running] is a sprint with nothing in the hands that needs both of them.
func step(delta: float, running: bool, speed: float, stride: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var winding := is_finite(charge) and charge >= 0.0
	if winding:
		wind = move_toward(wind, 1.0, delta / WIND_IN)
		cocked = lerpf(cocked, clampf(charge, 0.0, 1.0), 1.0 - exp(-18.0 * delta))
		_hold_left = WIND_HOLD
	elif _hold_left > 0.0:
		_hold_left -= delta
	else:
		wind = move_toward(wind, 0.0, delta / WIND_OUT)
		if wind <= 0.0:
			cocked = 0.0
	if release_at < 1.0:
		release_at = minf(1.0, release_at + delta / RELEASE_SECONDS)
	run = move_toward(run, 1.0 if running else 0.0, delta / RUN_SECONDS)
	if stride >= 0.0:
		run_phase = stride
	else:
		run_phase = fposmod(run_phase + delta * maxf(speed, 0.0) / RUN_STRIDE, 1.0)


## Whether anything is drawn this frame.
func active() -> bool:
	return wind > 0.0 or release_at < 1.0 or run > 0.0


## Writes the arms over the clip. [param to_figure] is skeleton space to the figure's frame.
func apply(skeleton: Skeleton3D, model: Node, animation: Animation, to_figure: Transform3D) -> void:
	if skeleton == null or animation == null or not active():
		return
	var right := _bones(skeleton, model, animation, ARM_R)
	var left := _bones(skeleton, model, animation, ARM_L)
	var chest := _bones(skeleton, model, animation, [CHEST_BONE, ARM_R[0]] as Array[String])
	var throw_w := 0.0
	var twist := 0.0
	var hand := Vector3.ZERO
	var pole := Vector3.ZERO
	var share := wind * _cock_share()
	if release_at < 1.0:
		var r := _release_pose(release_at)
		hand = r[0]
		pole = r[1]
		twist = r[2]
		throw_w = r[3]
	elif share > 0.0:
		hand = COCKED
		pole = COCKED_POLE
		twist = TWIST_DEG * share
		throw_w = share
	twist *= 1.0 - run * 0.5
	if not chest.is_empty() and absf(twist) > 0.01:
		_turn_chest(skeleton, chest[0], to_figure, -deg_to_rad(twist))
	var swing := sin(TAU * run_phase) * deg_to_rad(RUN_SWING_DEG)
	if not right.is_empty():
		if run > 0.0:
			_run_arm(skeleton, right, to_figure, swing, 1.0, run * (1.0 - throw_w))
		if throw_w > 0.0:
			_reach(skeleton, right, to_figure, hand, pole, throw_w)
	if not left.is_empty():
		if run > 0.0:
			_run_arm(skeleton, left, to_figure, -swing, -1.0, run)
		if throw_w > 0.0 and run < 1.0:
			# The free arm comes up and forward to aim the throw.
			_reach(skeleton, left, to_figure, Vector3(0.1, 0.05, -0.75), Vector3(-1.0, -0.6, 0.1), throw_w * 0.7 * (1.0 - run))


func describe() -> Dictionary:
	return {
		"charge": snappedf(charge, 0.01),
		"wind": snappedf(wind, 0.01),
		"cocked": snappedf(cocked, 0.01),
		"release": snappedf(release_at, 0.01),
		"run": snappedf(run, 0.01),
	}


func _cock_share() -> float:
	var f := clampf(cocked, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(COCK_START, 1.0, f)


## [hand, pole, twist degrees, weight] [param t] through the release.
func _release_pose(t: float) -> Array:
	var from := release_from
	var k0: Array = RELEASE_KEYS[0]
	var k1: Array = RELEASE_KEYS[1]
	var a := float(k0[0])
	var b := float(k1[0])
	if t < a:
		var u := _smooth(t / a)
		return [COCKED.lerp(k0[1], u), COCKED_POLE.lerp(k0[2], u), lerpf(TWIST_DEG * from, 0.0, u), maxf(from, u)]
	if t < b:
		var u := _smooth((t - a) / (b - a))
		return [(k0[1] as Vector3).lerp(k1[1], u), (k0[2] as Vector3).lerp(k1[2], u), FOLLOW_TWIST_DEG * u, 1.0]
	var u := _smooth((t - b) / (1.0 - b))
	return [k1[1], k1[2], FOLLOW_TWIST_DEG * (1.0 - u), 1.0 - u]


static func _smooth(x: float) -> float:
	var f := clampf(x, 0.0, 1.0)
	return f * f * (3.0 - 2.0 * f)


## Bones of [param names] when the clip keys them, else empty (a bone no track writes keeps last frame's pose,
## and a pose written over it every frame would compound).
func _bones(skeleton: Skeleton3D, model: Node, animation: Animation, names: Array[String]) -> Array[int]:
	var key := "%d:%s" % [animation.get_instance_id(), names[0]]
	if not _keyed.has(key):
		_keyed[key] = DotHumanoidIk.keyed_bones(skeleton, model, animation, names)
	return _keyed[key]


func _turn_chest(skeleton: Skeleton3D, bone: int, to_figure: Transform3D, angle: float) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var to_fig := to_figure.basis.get_rotation_quaternion()
	var turn := to_fig.inverse() * Quaternion(Vector3.UP, angle) * to_fig
	var parent_q := DotHumanoidIk.chain_rotation(skeleton, parent) if parent >= 0 else Quaternion.IDENTITY
	var global_q := parent_q * skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, (parent_q.inverse() * turn * global_q).normalized())


## The arm's shoulder (figure frame) and its two lengths.
func _measure(skeleton: Skeleton3D, bones: Array[int], to_figure: Transform3D) -> Array:
	var upper := to_figure * DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var lower := to_figure * DotHumanoidIk.global_pose(skeleton, bones[1]).origin
	var end := to_figure * DotHumanoidIk.global_pose(skeleton, bones[2]).origin
	return [upper, upper.distance_to(lower), lower.distance_to(end)]


## The hand to [param offset] arm lengths from its shoulder, the elbow toward [param pole] (figure frame).
func _reach(skeleton: Skeleton3D, bones: Array[int], to_figure: Transform3D, offset: Vector3, pole: Vector3, w: float) -> void:
	var m := _measure(skeleton, bones, to_figure)
	var length: float = float(m[1]) + float(m[2])
	var target: Vector3 = (m[0] as Vector3) + offset * length
	var inverse := to_figure.affine_inverse()
	DotHumanoidIk.two_bone(skeleton, bones, inverse * target, to_figure.basis.inverse() * pole, w)


## A sprinting arm: the upper arm [param swing] radians forward of hanging, the elbow bent [constant RUN_ELBOW_DEG]
## and the hand in toward the middle. [param side] is 1 for the right arm and -1 for the left.
func _run_arm(skeleton: Skeleton3D, bones: Array[int], to_figure: Transform3D, swing: float, side: float, w: float) -> void:
	var m := _measure(skeleton, bones, to_figure)
	var shoulder: Vector3 = m[0]
	var la: float = m[1]
	var lb: float = m[2]
	var upper := Basis(Vector3.RIGHT, swing) * Vector3.DOWN
	var elbow := shoulder + upper * la
	var fore := Basis(Vector3.RIGHT, swing + deg_to_rad(RUN_ELBOW_DEG)) * Vector3.DOWN
	fore = (fore + Vector3(-side * RUN_INWARD * 2.0, 0.0, 0.0)).normalized()
	var hand := elbow + fore * lb
	var pole := elbow - (shoulder + hand) * 0.5
	var inverse := to_figure.affine_inverse()
	DotHumanoidIk.two_bone(skeleton, bones, inverse * hand, to_figure.basis.inverse() * pole, w)
