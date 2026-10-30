class_name DotViewArmsPoseDebug
extends MeshInstance3D
## Draws what the held arms solve for, over everything: each grip socket (yellow), the hand target the IK aims at
## (cyan), a line from target to the hand that reached for it (red when off by more than [member tolerance]), and
## each arm bone's axes (x red, y green, z blue). Added by [member DotPlayerViewArms.debug_pose].

const ARM_BONES: Array[String] = ["UpperArm.R", "LowerArm.R", "Middle1.R", "UpperArm.L", "LowerArm.L", "Middle1.L"]

## Metres a hand may sit from its target before its line turns red.
var tolerance: float = 0.03
## Length of the drawn bone axes and socket crosses, metres.
var size: float = 0.03

var _mesh := ImmediateMesh.new()


func _init() -> void:
	name = "PoseDebug"
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.render_priority = 127
	material_override = material


## Redraws for this frame. [param pairs] holds [socket, target, hand bone] per hand, in world space.
func draw(skeleton: Skeleton3D, pairs: Array) -> void:
	global_transform = Transform3D.IDENTITY
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair: Array in pairs:
		_cross(pair[0], Color.YELLOW)
		_cross(pair[1], Color.CYAN)
		var hand := _bone(skeleton, pair[2]).origin
		_line(pair[1], hand, Color.RED if hand.distance_to(pair[1]) > tolerance else Color.GREEN)
	for bone in ARM_BONES:
		if skeleton.find_bone(bone) < 0:
			continue
		var at := _bone(skeleton, bone)
		_line(at.origin, at.origin + at.basis.x.normalized() * size, Color.RED)
		_line(at.origin, at.origin + at.basis.y.normalized() * size, Color.GREEN)
		_line(at.origin, at.origin + at.basis.z.normalized() * size, Color.BLUE)
	_mesh.surface_end()


func _bone(skeleton: Skeleton3D, bone: String) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))


func _cross(at: Vector3, color: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(at - axis * size * 0.5, at + axis * size * 0.5, color)


func _line(from: Vector3, to: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(from)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(to)
