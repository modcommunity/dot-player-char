## Where a figure's legs point and where its feet land: the lower body turned toward the way it
## moves (the chest keeps facing the aim), a backward walk played in reverse, and feet set on the
## wall plane during a wall run. One per [DotHumanoidFigure]; it calls these around its clip.
class_name DotHumanoidLegs
extends RefCounted

## Most the hips turn from the facing, radians: a pure strafe past it slides a little sideways.
const MAX_TWIST := deg_to_rad(80.0)
## Past this angle from the facing the legs walk backward; under [constant BACK_EXIT] forward again.
const BACK_ENTER := deg_to_rad(105.0)
const BACK_EXIT := deg_to_rad(75.0)
## Below this ground speed the legs face forward again.
const MOVING := 0.4
## How fast the hips turn toward the wanted twist, radians a second.
const TURN_RATE := 9.0
## How much of a foot's clip height above the lowest foot is kept off the wall.
const WALL_LIFT := 0.6
const LEGS := [["UpperLeg.L", "LowerLeg.L", "Foot.L"], ["UpperLeg.R", "LowerLeg.R", "Foot.R"]]

## The lower body's turn from the facing now, radians (positive to the figure's left).
var twist: float = 0.0
## Whether the stride clip plays backward.
var backward: bool = false
## Ground speed along the legs' own direction, for the stride-matched rate.
var along_speed: float = 0.0
## How far the feet are drawn onto the wall, 0 to 1.
var wall_weight: float = 0.0

var _saved: Dictionary = {}


## Reads the ground [param velocity] (world) against [param facing] (the figure's world basis) and eases the twist.
func update(facing: Basis, velocity: Vector3, dt: float) -> void:
	var local := facing.inverse() * velocity if not is_zero_approx(facing.determinant()) else Vector3.ZERO
	var flat := Vector2(local.x, local.z)
	var speed := flat.length()
	var want := 0.0
	along_speed = speed
	if speed >= MOVING:
		var angle := atan2(-local.x, -local.z)
		backward = absf(angle) > (BACK_EXIT if backward else BACK_ENTER)
		var legs_dir := wrapf(angle - PI, -PI, PI) if backward else angle
		want = clampf(legs_dir, -MAX_TWIST, MAX_TWIST)
		along_speed = speed * maxf(cos(legs_dir - want), 0.0)
	else:
		backward = false
	twist = move_toward(twist, want, TURN_RATE * maxf(dt, 0.0))


## Puts back what [method apply] wrote, before the clip is advanced: a bone no track keys would keep it and add up.
func restore(skeleton: Skeleton3D) -> void:
	for bone: int in _saved:
		skeleton.set_bone_pose_rotation(bone, _saved[bone])
	_saved.clear()


## Turns the root by [member twist] about [param up] (skeleton space) and the hips back by as much.
func apply(skeleton: Skeleton3D, up: Vector3) -> void:
	if skeleton == null or is_zero_approx(twist):
		return
	var root := skeleton.find_bone("Root")
	var hips := skeleton.find_bone("Hips")
	if root < 0 or hips < 0:
		return
	_saved[root] = skeleton.get_bone_pose_rotation(root)
	_saved[hips] = skeleton.get_bone_pose_rotation(hips)
	var turn := Quaternion(up.normalized(), twist)
	var root_parent := DotHumanoidIk.chain_rotation(skeleton, skeleton.get_bone_parent(root))
	skeleton.set_bone_pose_rotation(root, (root_parent.inverse() * turn * root_parent * _saved[root]).normalized())
	var hips_parent := DotHumanoidIk.chain_rotation(skeleton, skeleton.get_bone_parent(hips))
	skeleton.set_bone_pose_rotation(hips, (hips_parent.inverse() * turn.inverse() * hips_parent * _saved[hips]).normalized())


## Sets each foot on [param wall] (a world plane facing the runner) by two-bone IK: planted while it carries
## the body, kept off by [constant WALL_LIFT] of its lift in the clip while it swings. [param up] is world up.
## A foot the leg cannot reach straight across is moved up the wall until it can.
func on_wall(skeleton: Skeleton3D, wall: Plane, up: Vector3, weight: float) -> void:
	wall_weight = clampf(weight, 0.0, 1.0)
	if skeleton == null or wall_weight <= 0.0 or wall.normal == Vector3.ZERO:
		return
	var to_skel := skeleton.global_transform.affine_inverse()
	var plane := to_skel * wall
	var up_s := (to_skel.basis * up).normalized()
	var heights: Array[float] = []
	var ankles: Array[Vector3] = []
	var ids: Array = []
	for names: Array in LEGS:
		var leg: Array[int] = [skeleton.find_bone(names[0]), skeleton.find_bone(names[1]), skeleton.find_bone(names[2])]
		if leg.has(-1):
			return
		var ankle := DotHumanoidIk.global_pose(skeleton, leg[2]).origin
		ids.append(leg)
		ankles.append(ankle)
		heights.append((ankle - skeleton.get_bone_global_rest(leg[2]).origin).dot(up_s))
	for k in 2:
		var leg: Array[int] = ids[k]
		var end_local := skeleton.get_bone_global_rest(leg[1]).affine_inverse() * skeleton.get_bone_global_rest(leg[2]).origin
		var hip := DotHumanoidIk.global_pose(skeleton, leg[0]).origin
		var knee := DotHumanoidIk.global_pose(skeleton, leg[1])
		var span := ((knee.origin - hip).length() + (knee.basis * end_local).length()) * 0.98
		var target := _within(plane, hip, plane.project(ankles[k]), span) + plane.normal * maxf(heights[k], 0.0) * WALL_LIFT
		var reached := DotHumanoidIk.two_bone_to(skeleton, leg[0], leg[1], end_local, ankles[k].lerp(target, wall_weight), plane.normal + up_s * 0.5, 1.0)
		var parent := skeleton.get_bone_parent(leg[2])
		skeleton.set_bone_pose_position(leg[2], reached if parent < 0 else DotHumanoidIk.global_pose(skeleton, parent).affine_inverse() * reached)


## [param target] on [param plane], or the nearest point to it on the plane within [param span] of [param hip].
static func _within(plane: Plane, hip: Vector3, target: Vector3, span: float) -> Vector3:
	var off := absf(plane.distance_to(hip))
	if hip.distance_to(target) <= span or off >= span:
		return target
	var foot := plane.project(hip)
	var along := target - foot
	return foot + along.normalized() * sqrt(span * span - off * off) if along.length() > 0.0001 else foot


## The feet's ankles in world space, for a check.
static func ankles(skeleton: Skeleton3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if skeleton == null:
		return out
	for names: Array in LEGS:
		var foot := skeleton.find_bone(names[2])
		if foot >= 0:
			out.append(skeleton.global_transform * DotHumanoidIk.global_pose(skeleton, foot).origin)
	return out


func describe() -> Dictionary:
	return {"twist_deg": rad_to_deg(twist), "backward": backward, "along_speed": along_speed, "wall": wall_weight}
