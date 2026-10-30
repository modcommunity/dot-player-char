class_name DotHumanoidBlend
extends RefCounted

## Pose blending on a figure's skeleton: the ease out of a stride-clip cut, and the weighted turn
## an overlay writes.

const SECONDS := 0.15

var rotations: Dictionary = {}
var positions: Dictionary = {}
var left: float = 0.0


## Remembers the pose on screen now for [param bones] (name to index), the hips and [param extra], to ease from.
func begin(skeleton: Skeleton3D, bones: Dictionary, extra: String) -> void:
	rotations.clear()
	for bone: String in bones:
		rotations[bones[bone]] = skeleton.get_bone_pose_rotation(bones[bone])
	for bone: String in ["Body", "Hips", extra]:
		var b := skeleton.find_bone(bone)
		if b >= 0:
			rotations[b] = skeleton.get_bone_pose_rotation(b)
			positions[b] = skeleton.get_bone_pose_position(b)
	left = SECONDS


func clear() -> void:
	rotations.clear()
	positions.clear()
	left = 0.0


## Eases the upper body from the pose a stride cut left into the new clip's, so a hand-held weapon turns smoothly.
func step(skeleton: Skeleton3D, dt: float) -> void:
	if left <= 0.0:
		return
	left = maxf(0.0, left - dt)
	var w := 1.0 - left / SECONDS
	for index: int in rotations:
		var from: Quaternion = rotations[index]
		skeleton.set_bone_pose_rotation(index, from.slerp(skeleton.get_bone_pose_rotation(index), w))
	for index: int in positions:
		var at: Vector3 = positions[index]
		skeleton.set_bone_pose_position(index, at.lerp(skeleton.get_bone_pose_position(index), w))
	if left <= 0.0:
		rotations.clear()
		positions.clear()


## [param from] turned [param weight] of the way to [param to], the angle then multiplied by [param gain]; a slerp past 1 flips the long way round and pops.
static func toward(from: Quaternion, to: Quaternion, weight: float, gain: float) -> Quaternion:
	if gain == 1.0:
		return from.slerp(to, weight)
	var d := (from.inverse() * to).normalized()
	if d.w < 0.0:
		d = -d
	var angle := d.get_angle()
	if angle < 0.0001:
		return from
	return from * Quaternion(d.get_axis().normalized(), angle * weight * gain)
