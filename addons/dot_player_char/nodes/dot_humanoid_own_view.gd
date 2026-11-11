## Which of a figure's bones are shrunk away so its own player can look down at it from inside the
## head, and a shadow-only copy that keeps the whole person's shadow while they are gone.
## One per [DotHumanoidFigure]: [member DotHumanoidFigure.hide_head] and [member DotHumanoidFigure.first_person].
class_name DotHumanoidOwnView
extends RefCounted

## Drawn whole (the head only if [member hide_head] is off).
const THIRD := 0
## First person, legs and hips only: everything from the belly up is gone.
const LEGS := 1
## First person, the whole body but the head, neck and arms (the view model draws the arms).
const BODY := 2

const HIDDEN_BONES := {LEGS: ["Abdomen"], BODY: ["Neck", "Shoulder.L", "Shoulder.R"]}
const GONE := Vector3.ONE * 0.001
## Degrees down where the body starts trailing back; the full trail clears the hips from a 100-degree view at 80 degrees down.
const LOOK_DOWN_FROM := 40.0
const LOOK_DOWN_FULL := 85.0

var mode: int = THIRD
## False (the `cl_legs` setting off): in first person nothing of the body is drawn, only its shadow, with no shrunk bones, cap or shadow copy.
var shown: bool = true
var hide_head: bool = false
## Metres (at 1.8 m tall) the body trails behind the eye as the view tips from [constant LOOK_DOWN_FROM] to 85 degrees down ([method back_for]): over the cut waist, the hip cap fills the screen and reads as a face. 0 for a game that places the body itself.
var look_down_back: float = 1.0
## Colour of the disc that closes the cut waist in LEGS mode (the look's top: the hem left at the waist); set before [method apply].
var cap_colour := Color("2f3a4f")
var _shrunk: Array[int] = []
var _cap: MeshInstance3D = null
var _shadow: Skeleton3D = null


## The bones shrunk this frame, after the clip: a clip may key a scale, so this is written every frame while hidden.
func apply(skeleton: Skeleton3D, mesh: MeshInstance3D) -> void:
	if skeleton == null:
		return
	var want: Array[int] = []
	var live := effective()
	# Every other person on the screen is drawn whole: nothing to look up.
	if hide_head or live != THIRD:
		var names: Array = HIDDEN_BONES.get(live, []).duplicate()
		names.append("Head")
		for bone_name: String in names:
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				want.append(bone)
	# Put back only what this class shrank: a head a critical took off stays off until mend.
	for bone in _shrunk:
		if not bone in want:
			skeleton.set_bone_pose_scale(bone, Vector3.ONE)
	for bone in want:
		skeleton.set_bone_pose_scale(bone, GONE)
	_shrunk = want
	_sync_cap(skeleton)
	_sync_shadow(skeleton, mesh)
	if mesh != null and mode != THIRD and not shown:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## Every bone at its own size again, for a respawn, then what this view hides.
func mend(skeleton: Skeleton3D, mesh: MeshInstance3D) -> void:
	if skeleton == null:
		return
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_scale(i, Vector3.ONE)
	_shrunk.clear()
	apply(skeleton, mesh)


## The mode that is drawn: [member mode], or [constant THIRD] while [member shown] is off.
func effective() -> int:
	return mode if shown else THIRD


## How far behind its origin the body is drawn for a view [param pitch_radians] (down negative): 0 outside first person.
func back_for(pitch_radians: float) -> float:
	if effective() == THIRD or not is_finite(pitch_radians):
		return 0.0
	var down := clampf(-rad_to_deg(pitch_radians), 0.0, 90.0)
	return look_down_back * clampf((down - LOOK_DOWN_FROM) / (LOOK_DOWN_FULL - LOOK_DOWN_FROM), 0.0, 1.0)


## The shadow copy's skeleton, or null outside first person.
func shadow() -> Skeleton3D:
	return _shadow if is_instance_valid(_shadow) else null


## Without the belly the hips are an open tube seen from above: a flat disc on the hips bone, as wide as the stance, closes it.
func _sync_cap(skeleton: Skeleton3D) -> void:
	if effective() != LEGS and _cap == null:
		return
	var hips := skeleton.find_bone("Hips")
	var abdomen := skeleton.find_bone("Abdomen")
	var left := skeleton.find_bone("UpperLeg.L")
	var right := skeleton.find_bone("UpperLeg.R")
	if effective() != LEGS or hips < 0 or abdomen < 0 or left < 0 or right < 0:
		if is_instance_valid(_cap):
			_cap.get_parent().queue_free()
		_cap = null
		return
	if not is_instance_valid(_cap):
		var attach := BoneAttachment3D.new()
		attach.name = "OwnHipCap"
		attach.bone_name = "Hips"
		skeleton.add_child(attach)
		var disc := CylinderMesh.new()
		disc.height = 0.02
		disc.radial_segments = 16
		disc.rings = 1
		_cap = MeshInstance3D.new()
		_cap.mesh = disc
		_cap.material_override = StandardMaterial3D.new()
		_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attach.add_child(_cap)
		var hips_rest := skeleton.get_bone_global_rest(hips)
		var width := (skeleton.get_bone_global_rest(left).origin - skeleton.get_bone_global_rest(right).origin).length()
		var radius := width * 0.6
		disc.top_radius = radius
		disc.bottom_radius = radius
		_cap.position = hips_rest.affine_inverse() * skeleton.get_bone_global_rest(abdomen).origin
	var material := _cap.material_override as StandardMaterial3D
	material.albedo_color = cap_colour
	material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _sync_shadow(skeleton: Skeleton3D, mesh: MeshInstance3D) -> void:
	var wanted := effective() != THIRD and mesh != null
	if mesh != null:
		var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if wanted else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh.cast_shadow != cast:
			mesh.cast_shadow = cast
	if not wanted:
		if is_instance_valid(_shadow):
			_shadow.queue_free()
		_shadow = null
		return
	if not is_instance_valid(_shadow):
		_shadow = _shadow_of(skeleton, mesh)
	for i in skeleton.get_bone_count():
		_shadow.set_bone_pose_position(i, skeleton.get_bone_pose_position(i))
		_shadow.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i))
		_shadow.set_bone_pose_scale(i, Vector3.ONE if i in _shrunk else skeleton.get_bone_pose_scale(i))


static func _shadow_of(skeleton: Skeleton3D, mesh: MeshInstance3D) -> Skeleton3D:
	var copy := Skeleton3D.new()
	copy.name = "OwnShadow"
	for i in skeleton.get_bone_count():
		copy.add_bone(skeleton.get_bone_name(i))
		copy.set_bone_parent(i, skeleton.get_bone_parent(i))
		copy.set_bone_rest(i, skeleton.get_bone_rest(i))
	copy.transform = skeleton.transform
	var body := MeshInstance3D.new()
	body.mesh = mesh.mesh
	body.skin = mesh.skin
	body.material_override = mesh.material_override
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	body.layers = mesh.layers
	copy.add_child(body)
	body.transform = mesh.transform if mesh.get_parent() == skeleton else Transform3D.IDENTITY
	body.skeleton = NodePath("..")
	skeleton.get_parent().add_child(copy)
	return copy


func describe() -> Dictionary:
	return {"mode": mode, "shown": shown, "hide_head": hide_head, "shrunk": _shrunk.size(), "shadow": shadow() != null, "look_down_back": look_down_back}
