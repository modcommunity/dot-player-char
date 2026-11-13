class_name DotHumanoidCarryPose
extends RefCounted

## The gun arm of a [DotHumanoidFigure] as others see it: puts the gun hand where a [DotHumanoidCarry] stance
## says, eased between ready, sprint, aim, reload and swap, swaying with the gait, and gives the other hand the
## foregrip. Written over the clip after the legs; drawn only, so hit zones and the shot never follow it.

const CHANNEL := "player.humanoid"

## The gun arm (upper, lower, hand) and the bone the stance rides on.
const ARM_BONES: Array[String] = ["UpperArm.R", "LowerArm.R", "Middle1.R"]
const CHEST_BONE := "Torso"

## Where the gun arm's elbow points, in the figure's frame: right, down, a little back.
const POLE := Vector3(0.5, -1.0, 0.25)

## The share of the view's pitch the waist and chest already bend ([constant DotHumanoidAim.AIM_BONES]).
const CHEST_PITCH := 0.22

## Seconds to ease the whole carry in or out, a stance (sprint aside, which the figure eases), and the aim.
const EASE := 0.2
const STANCE_EASE := 0.2
const AIM_IN := 0.08
const AIM_OUT := 0.3

## Seconds the gun stays shouldered after a shot.
const AIM_HOLD := 1.2

## Seconds of the other hand's reload path: off the foregrip to the magazine well, down to the belt, back to the
## well, back to the foregrip. A longer reload holds at the foregrip with the gun still rolled.
const RELOAD_PATH := 1.1

## Where the other hand takes a magazine: the left hip, from the chest, metres on a 1.8 m figure; and the
## magazine well, in the gun's frame.
const BELT := Vector3(-0.12, -0.26, -0.06)
const WELL := Vector3(0.0, -0.10, -0.08)

## Seconds for a shot's kick to settle.
const KICK_SECONDS := 0.1

## The style drawn, or null for none; until [method set_class] is called a gun is carried as a rifle.
var style: DotHumanoidCarry = null
## Whether a game chose the style: only then does the other hand take the foregrip on its own.
var explicit := false

## How far the carry is drawn (0 to 1), and how far each stance is blended in.
var weight := 0.0
var aim := 0.0
var reload := 0.0
var swap := 0.0

## Held raised (aiming down sights), reloading and changing weapon, as the game says.
var raised := false
var reloading := false
var switching := false

## Where the other hand goes this frame, in skeleton space; INF for nowhere.
var support_grip := Vector3.INF

var _fire_hold := 0.0
var _kick := 0.0
var _reload_time := 0.0
var _turns: Array[Quaternion] = []
var _bones: Dictionary = {}
var _chest := -1
var _shoulder := -1
var _hand_frame := Transform3D.IDENTITY
var _hand_frame_inv := Transform3D.IDENTITY
var _chest_ref := Transform3D.IDENTITY
var _skeleton_id := 0


## How the gun is carried: a class ([constant DotHumanoidCarry.CLASSES]: &"rifle", &"pistol", &"sniper", ...), a
## [DotHumanoidCarry], or null for the clip's arms alone.
func set_class(kind: Variant) -> void:
	explicit = true
	if kind is StringName or kind is String:
		_set_style(DotHumanoidCarry.for_class(StringName(kind)))
	else:
		_set_style(kind as DotHumanoidCarry)


func _set_style(p_style: DotHumanoidCarry) -> void:
	style = p_style
	_turns.clear()
	if style == null:
		return
	var turns: Array[Vector3] = [style.ready_turn, style.sprint_turn, style.aim_turn, style.reload_turn, style.swap_turn]
	for turn in turns:
		_turns.append(Quaternion.from_euler(turn * (PI / 180.0)))


## A shot: the gun goes to the shoulder, kicks, and stays up for [constant AIM_HOLD] seconds.
func fired() -> void:
	_fire_hold = AIM_HOLD
	_kick = 1.0


## Eases the blends by [param delta]; [param active] says whether the carry is drawn at all. Every frame, LOD or not.
func step(delta: float, active: bool) -> void:
	if active and style == null and not explicit:
		_set_style(DotHumanoidCarry.for_class(&"rifle"))
	weight = move_toward(weight, 1.0 if active and style != null else 0.0, delta / EASE)
	_fire_hold = maxf(_fire_hold - delta, 0.0)
	var up := raised or _fire_hold > 0.0
	aim = move_toward(aim, 1.0 if up else 0.0, delta / (AIM_IN if up else AIM_OUT))
	reload = move_toward(reload, 1.0 if reloading else 0.0, delta / STANCE_EASE)
	swap = move_toward(swap, 1.0 if switching else 0.0, delta / STANCE_EASE)
	_reload_time = _reload_time + delta if reloading else 0.0
	_kick = move_toward(_kick, 0.0, delta / KICK_SECONDS)


## Writes the gun arm over the pose. [param to_figure] is the skeleton's frame in the figure's; [param animation]
## the clip playing; [param phase] how far through its stride (0 to 1, or negative for none); [param pitch] the
## view's, radians; [param size] the figure's height over 1.8; [param sprint] the sprint blend; [param speed] m/s;
## [param under] how much an overlay (a swing, a flinch, a gesture) holds the arms instead.
func apply(skeleton: Skeleton3D, model: Node3D, anim: AnimationPlayer, to_figure: Transform3D, animation: Animation,
		phase: float, pitch: float, size: float, sprint: float, speed: float, under: float) -> void:
	support_grip = Vector3.INF
	var w := weight * (1.0 - clampf(under, 0.0, 1.0))
	if w <= 0.001 or style == null or _turns.is_empty() or animation == null:
		return
	if skeleton.get_instance_id() != _skeleton_id:
		_measure(skeleton, model, anim, to_figure)
	if not _bones.has(animation):
		_bones[animation] = DotHumanoidIk.keyed_bones(skeleton, model, animation, ARM_BONES)
	var bones: Array[int] = _bones[animation]
	if bones.is_empty() or _chest < 0:
		return
	var s := style
	# The stance, blended: sprint over ready, the aim over both, reload and swap over all.
	var grip := s.ready_grip.lerp(s.sprint_grip, sprint)
	var turn := _turns[0].slerp(_turns[1], sprint)
	grip = grip.lerp(s.aim_grip, aim)
	turn = turn.slerp(_turns[2], aim)
	grip = grip.lerp(s.reload_grip, reload)
	turn = turn.slerp(_turns[3], reload)
	grip = grip.lerp(s.swap_grip, swap)
	turn = turn.slerp(_turns[4], swap)
	# Ride the chest as the clip moves it: all of its travel, part of its turn (less when aiming).
	# One walk from the root: the arm hangs off the chest (Torso, Shoulder, UpperArm, LowerArm, hand).
	var chest_global := DotHumanoidIk.global_pose(skeleton, _chest)
	var shoulder_global := chest_global * skeleton.get_bone_pose(_shoulder)
	var chest := to_figure * chest_global
	var chest_ref := to_figure * _chest_ref
	var lean := chest.basis.get_rotation_quaternion() * chest_ref.basis.get_rotation_quaternion().inverse()
	var follow := Quaternion.IDENTITY.slerp(lean, lerpf(s.follow, 0.25, aim))
	grip = chest.origin + follow * (grip * size - chest_ref.origin)
	turn = follow * turn
	# Gait sway: a bob twice a stride, side sway and a turn once, less at an aim or a reload.
	if phase >= 0.0:
		var amount := clampf(speed / 1.2, 0.0, 1.0) * (1.0 - 0.75 * aim) * (1.0 - 0.5 * reload)
		var amp := s.walk_sway.lerp(s.run_sway, clampf((speed - 2.0) / 3.0, 0.0, 1.0)) * amount
		var a := TAU * phase
		grip += Vector3(amp.y * sin(a), amp.x * sin(2.0 * a), 0.0) * size
		var deg := amp.z * (PI / 180.0)
		turn = Quaternion.from_euler(Vector3(0.4 * deg * sin(2.0 * a), deg * sin(a), -0.6 * deg * sin(a))) * turn
	# The view's pitch, about the shoulder: in full when aiming, half at the ready, little at a sprint.
	var shoulder := to_figure * (shoulder_global * skeleton.get_bone_pose(bones[0])).origin
	var share := lerpf(0.5, 1.0, aim) * (1.0 - 0.7 * sprint * (1.0 - aim)) - CHEST_PITCH * lerpf(s.follow, 0.25, aim)
	var tilt := Quaternion(Vector3.RIGHT, pitch * share)
	grip = shoulder + tilt * (grip - shoulder)
	turn = tilt * turn
	# The kick: back along the barrel and the muzzle up.
	if _kick > 0.0:
		grip += turn * Vector3(0.0, 0.0, s.kick * _kick * size)
		turn = turn * Quaternion(Vector3.RIGHT, deg_to_rad(s.kick_climb) * _kick)
	# The hand bone that puts the gun's frame there, in skeleton space.
	var hand := to_figure.affine_inverse() * Transform3D(Basis(turn), grip) * _hand_frame_inv
	DotHumanoidIk.two_bone_under(skeleton, bones, shoulder_global, hand.origin, to_figure.basis.inverse() * POLE, w)
	var upper_global := shoulder_global * skeleton.get_bone_pose(bones[0])
	var lower_global := upper_global * skeleton.get_bone_pose(bones[1])
	var lower := lower_global.basis.get_rotation_quaternion()
	var wanted := (lower.inverse() * hand.basis.get_rotation_quaternion()).normalized()
	skeleton.set_bone_pose_rotation(bones[2], skeleton.get_bone_pose_rotation(bones[2]).slerp(wanted, w))
	if s.two_handed and explicit and swap < 0.5:
		support_grip = _support(lower_global * skeleton.get_bone_pose(bones[2]), to_figure, chest.origin, size)


## The other hand's point in skeleton space: the foregrip of the gun as drawn, or along the reload path.
func _support(hand_global: Transform3D, to_figure: Transform3D, chest: Vector3, size: float) -> Vector3:
	var gun := hand_global * _hand_frame
	var fore := gun * (style.support * size)
	if reload <= 0.0:
		return fore
	var well := gun * (WELL * size)
	var belt := to_figure.affine_inverse() * (chest + BELT * size)
	var t := _reload_time / RELOAD_PATH
	var path := fore
	if t < 0.15:
		path = fore.lerp(well, smoothstep(0.0, 0.15, t))
	elif t < 0.4:
		path = well.lerp(belt, smoothstep(0.15, 0.4, t))
	elif t < 0.7:
		path = belt.lerp(well, smoothstep(0.4, 0.7, t))
	elif t < 0.85:
		path = well
	elif t < 1.0:
		path = well.lerp(fore, smoothstep(0.85, 1.0, t))
	return fore.lerp(path, reload)


## The chest and shoulder bones, and the hand's and chest's frames at the held-gun pose, once per body. A body
## whose gun arm does not hang off its chest by one shoulder bone gets no carry.
func _measure(skeleton: Skeleton3D, model: Node3D, anim: AnimationPlayer, to_figure: Transform3D) -> void:
	_skeleton_id = skeleton.get_instance_id()
	_bones.clear()
	_chest = skeleton.find_bone(CHEST_BONE)
	var upper := skeleton.find_bone(ARM_BONES[0])
	_shoulder = skeleton.get_bone_parent(upper) if upper >= 0 else -1
	var lower := skeleton.find_bone(ARM_BONES[1])
	var hand := skeleton.find_bone(ARM_BONES[2])
	if _chest < 0 or _shoulder < 0 or skeleton.get_bone_parent(_shoulder) != _chest or lower < 0 or hand < 0 \
			or skeleton.get_bone_parent(lower) != upper or skeleton.get_bone_parent(hand) != lower:
		_chest = -1
		return
	_hand_frame = DotHumanoidFrames.hand_frame(skeleton, anim, model, to_figure)
	_hand_frame_inv = _hand_frame.affine_inverse()
	_chest_ref = DotHumanoidFrames.held_pose(skeleton, anim, model, _chest)


func describe() -> Dictionary:
	return {
		"style": String(style.id) if style != null else "",
		"weight": snappedf(weight, 0.01),
		"aim": snappedf(aim, 0.01),
		"reload": snappedf(reload, 0.01),
		"swap": snappedf(swap, 0.01),
		"support": support_grip.is_finite(),
	}
