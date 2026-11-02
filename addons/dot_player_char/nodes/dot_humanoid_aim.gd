class_name DotHumanoidAim
extends RefCounted

## The view pitch bent into a figure's waist and chest, and its arms when it holds a gun.


## Bends the waist and chest by [member pitch] about the figure's left-to-right axis, after the clip
## and overlays. Not while down, dead, swimming or climbing, and only on bones the clip keys: an
## unkeyed bone keeps last frame's pose and the bend would accumulate.
static func apply(skeleton: Skeleton3D, model: Node3D, animation: Animation, to_figure: Transform3D, arm: bool, pitch: float, sprint_blend: float) -> void:
	# Figure right in skeleton space. A collapsed basis (a figure popping in or out) has no inverse:
	# keep the clip's pose rather than hand Quaternion a zero or NaN axis.
	var axis := Vector3.ZERO
	if absf(to_figure.basis.determinant()) > 1e-9:
		axis = (to_figure.basis.inverse() * Vector3.RIGHT).normalized()
	if not axis.is_finite() or axis.length_squared() < 0.5:
		return
	var prefix := String(model.get_path_to(skeleton))
	# Parents are read before any bone turns; turns about one axis commute, so each share goes on
	# through the parent's unturned frame: local' = P^-1 * turn * P * local. Use local poses up the
	# chain, not get_bone_global_pose, which is last frame's (with last frame's bend in it).
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
