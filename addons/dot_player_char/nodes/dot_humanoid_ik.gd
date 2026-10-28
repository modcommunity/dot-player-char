## Pose maths for [DotHumanoidFigure]: a two-bone IK and skeleton-space bone transforms.
class_name DotHumanoidIk
extends RefCounted


## Two-bone IK turning [param bones] (upper, lower, end) to reach [param target] (skeleton space) with the elbow toward [param pole_dir], blended by [param weight].
static func two_bone(skeleton: Skeleton3D, bones: Array[int], target: Vector3, pole_dir: Vector3, weight: float) -> void:
	var upper := global_pose(skeleton, bones[0])
	var lower := global_pose(skeleton, bones[1])
	var wrist := global_pose(skeleton, bones[2])
	var a := lower.origin - upper.origin
	var b := wrist.origin - lower.origin
	var la := a.length()
	var lb := b.length()
	var to_target := target - upper.origin
	if la < 0.0001 or lb < 0.0001 or to_target.length() < 0.0001:
		return
	var reach := clampf(to_target.length(), absf(la - lb) + 0.001, la + lb - 0.001)
	var dir := to_target.normalized()
	var along := (la * la - lb * lb + reach * reach) / (2.0 * reach)
	var height := sqrt(maxf(la * la - along * along, 0.0))
	var pole := pole_dir
	var side := pole - dir * pole.dot(dir)
	side = side.normalized() if side.length_squared() > 0.000001 else Vector3.UP
	var elbow := upper.origin + dir * along + side * height
	var hand_goal := upper.origin + dir * reach
	var q1 := Quaternion(a.normalized(), (elbow - upper.origin).normalized())
	var q2 := Quaternion((q1 * b).normalized(), (hand_goal - elbow).normalized())
	var upper_rot := (q1 * upper.basis.get_rotation_quaternion()).normalized()
	var lower_rot := (q2 * q1 * lower.basis.get_rotation_quaternion()).normalized()
	var upper_parent := global_pose(skeleton, skeleton.get_bone_parent(bones[0])).basis.get_rotation_quaternion()
	var upper_local := (upper_parent.inverse() * upper_rot).normalized()
	var lower_local := (upper_rot.inverse() * lower_rot).normalized()
	var w := clampf(weight, 0.0, 1.0)
	skeleton.set_bone_pose_rotation(bones[0], skeleton.get_bone_pose_rotation(bones[0]).slerp(upper_local, w))
	skeleton.set_bone_pose_rotation(bones[1], skeleton.get_bone_pose_rotation(bones[1]).slerp(lower_local, w))


## Bone [param bone]'s transform in skeleton space from the local poses as they are now (the skeleton's own
## global poses are last frame's).
static func global_pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var chain: Array[int] = []
	while bone >= 0:
		chain.push_front(bone)
		bone = skeleton.get_bone_parent(bone)
	var out := Transform3D.IDENTITY
	for b in chain:
		out = out * skeleton.get_bone_pose(b)
	return out


## Bone [param bone]'s rotation in skeleton space from the local poses as they are now.
static func chain_rotation(skeleton: Skeleton3D, bone: int) -> Quaternion:
	var q := Quaternion.IDENTITY
	while bone >= 0:
		q = skeleton.get_bone_pose_rotation(bone) * q
		bone = skeleton.get_bone_parent(bone)
	return q


## The indices of [param names] in [param skeleton], or empty when one is missing or (all but the last) is not rotated by a track of [param animation].
static func keyed_bones(skeleton: Skeleton3D, model: Node, animation: Animation, names: Array[String]) -> Array[int]:
	var bones: Array[int] = []
	if animation == null:
		return bones
	var prefix := String(model.get_path_to(skeleton))
	for name in names:
		var i := skeleton.find_bone(name)
		if i < 0 or (name != names[names.size() - 1] and animation.find_track(NodePath("%s:%s" % [prefix, name]), Animation.TYPE_ROTATION_3D) < 0):
			bones.clear()
			return bones
		bones.append(i)
	return bones
