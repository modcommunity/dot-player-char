class_name DotHumanoidTurnLimit
extends RefCounted

## Caps how fast a figure's limbs turn on screen, after everything that poses them (the clip, a blend, the overlays,
## the floor IK). A stride clip played well past its own pace, a cut between clips or a foot let go by the floor IK can
## swing a knee or an arm through 100 degrees in a frame or two; drawn, that is a pop. Each limb bone turns at most
## [code]rate * dt[/code] from where it was last drawn. Drawing only: nothing a game simulates reads these bones.

const BONES: Array[String] = ["UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R",
	"UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R"]

var _of: int = 0
var _count: int = 0
var _bones: PackedInt32Array = PackedInt32Array()
## Per bone in [member _bones], the rotation last drawn; empty until a step has drawn one.
var _drawn: Array[Quaternion] = []
## Bone to the rotation the pose had before [method step] turned it back, for [method restore].
var _saved: Dictionary = {}


## Turns each limb bone of [param skeleton] no further than [param rate] (radians a second) times [param dt] from its
## last drawn rotation. [param rate] 0 or less draws the pose as it is (and forgets the last one).
func step(skeleton: Skeleton3D, rate: float, dt: float) -> void:
	if skeleton == null or rate <= 0.0:
		_drawn.clear()
		return
	if _of != skeleton.get_instance_id() or _count != skeleton.get_bone_count():
		_of = skeleton.get_instance_id()
		_count = skeleton.get_bone_count()
		_bones.clear()
		for name in BONES:
			var bone := skeleton.find_bone(name)
			if bone >= 0:
				_bones.append(bone)
		_drawn.clear()
	var first := _drawn.size() != _bones.size()
	if first:
		_drawn.resize(_bones.size())
	var most := rate * maxf(dt, 0.0)
	for n in _bones.size():
		var bone := _bones[n]
		var now := skeleton.get_bone_pose_rotation(bone)
		if not first:
			var last := _drawn[n]
			var angle := last.angle_to(now)
			if angle > most:
				_saved[bone] = now
				now = last.slerp(now, most / angle)
				skeleton.set_bone_pose_rotation(bone, now)
		_drawn[n] = now


## Puts back what [method step] turned, before the clip is advanced: a bone no track keys would keep it.
func restore(skeleton: Skeleton3D) -> void:
	if skeleton != null:
		for bone: int in _saved:
			skeleton.set_bone_pose_rotation(bone, _saved[bone])
	_saved.clear()


## Whether the last [method step] held a bone back (until [method restore]).
func turned() -> bool:
	return not _saved.is_empty()


## Forgets the last drawn pose: the next [method step] draws the pose as it is (a figure rebuilt, respawned or put back in view).
func clear() -> void:
	_drawn.clear()
	_saved.clear()
