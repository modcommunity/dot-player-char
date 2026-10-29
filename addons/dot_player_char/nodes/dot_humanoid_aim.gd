class_name DotHumanoidAim
extends RefCounted

## The view pitch bent into a figure's waist and chest, and its arms when it holds a gun.


## Bends the waist and chest by [member pitch] about the figure's own left-to-right axis,
## after the clip and the overlays, so whatever the arms are doing points up or down with the
## view. Not while down, dead, swimming or climbing (the body is not upright to bend), and only
## on a bone the playing clip keys: a bone no track writes keeps last frame's pose, and the bend
## would add up frame after frame.
static func apply(skeleton: Skeleton3D, model: Node3D, animation: Animation, to_figure: Transform3D, arm: bool, pitch: float, sprint_blend: float) -> void:
	# Figure right, in skeleton space: the axis a nod turns about.
	var axis := (to_figure.basis.inverse() * Vector3.RIGHT).normalized()
	var prefix := String(model.get_path_to(skeleton))
	# Every parent's pose is read before any bone is turned. Turns about one axis commute, so each
	# bone's share goes on through its parent's unturned frame: local' = P^-1 * turn * P * local.
	# Read from the local poses up the chain, not get_bone_global_pose: the skeleton updates its
	# global poses later in the frame, so that is last frame's (with last frame's bend in it).
	var shares: Dictionary = DotHumanoidClips.AIM_BONES
	if arm:
		shares = shares.merged(DotHumanoidClips.AIM_ARM)
	var parents := {}
	for bone: String in shares:
		var i := skeleton.find_bone(bone)
		if i >= 0:
			parents[i] = DotHumanoidIk.chain_rotation(skeleton, skeleton.get_bone_parent(i))
	for bone: String in shares:
		var i := skeleton.find_bone(bone)
		if i < 0 or animation.find_track(NodePath("%s:%s" % [prefix, bone]), Animation.TYPE_ROTATION_3D) < 0:
			continue
		var share: float = shares[bone]
		var p: Quaternion = parents[i]
		var drop := -DotHumanoidFigure.SPRINT_DROP * sprint_blend if DotHumanoidClips.AIM_ARM.has(bone) else 0.0
		var turn := Quaternion(axis, pitch * share + drop)
		skeleton.set_bone_pose_rotation(i, (p.inverse() * turn * p * skeleton.get_bone_pose_rotation(i)).normalized())
