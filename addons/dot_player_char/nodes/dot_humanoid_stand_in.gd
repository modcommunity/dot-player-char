class_name DotHumanoidStandIn
extends RefCounted

## A far figure's stand-in ([member DotHumanoidFigure.stand_in_range]): its skinned body baked once in one pose of one
## clip into a plain mesh, shared by every figure of that body and kept until [method clear]. Drawn in place of the
## skin, it costs no clip, no bones and no skinning, and the figure's material (its colours) still paints it. The
## skin's own detail levels are kept, so a far stand-in draws as few triangles as the skin did.

## Baked meshes by [method key].
static var _baked: Dictionary = {}
## Each source mesh surface's detail levels as [method ArrayMesh.add_surface_from_arrays] takes them, by mesh and surface.
static var _levels: Dictionary = {}
static var _bake_frame := -1
static var _bakes := 0


## The name a pose is shared under: the skin's mesh, the clip, the pose's place in its lap and how the hands hold.
static func key(skin: Mesh, clip: StringName, phase: int, hold: int) -> String:
	return "%d|%s|%d|%d" % [skin.get_instance_id(), clip, phase, hold]


static func find(name: String) -> Mesh:
	return _baked.get(name) as Mesh


## Whether another bake fits in this frame ([member DotHumanoidFigure.stand_in_bakes_per_frame]).
static func may_bake() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _bake_frame:
		_bake_frame = frame
		_bakes = 0
	var most := DotHumanoidFigure.stand_in_bakes_per_frame
	return most <= 0 or _bakes < most


## Bakes [param skin] as [param skeleton] is posed now and keeps it under [param name]; null when the skin cannot be
## baked (no skin binds, or a surface that is not skinned triangles). Skinned here on the CPU from the bones' global
## poses, as the engine skins it: [method MeshInstance3D.bake_mesh_from_current_skeleton_pose] reads the rendering
## server's copy of the bones, which lags a pose set this frame and is empty with no renderer.
static func bake(skin: MeshInstance3D, skeleton: Skeleton3D, name: String) -> Mesh:
	_bakes += 1
	var source := skin.mesh
	var binds := skin.skin
	if source == null or binds == null or binds.get_bind_count() == 0:
		return null
	var poses: Array[Transform3D] = []
	for j in binds.get_bind_count():
		var bone := binds.get_bind_bone(j)
		if bone < 0:
			bone = skeleton.find_bone(binds.get_bind_name(j))
		poses.append((skeleton.get_bone_global_pose(bone) if bone >= 0 else Transform3D()) * binds.get_bind_pose(j))
	var out := ArrayMesh.new()
	for i in source.get_surface_count():
		if source.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return null
		var arrays := source.surface_get_arrays(i)
		if not _skin_arrays(arrays, poses, source.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS != 0):
			return null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], _levels_of(source, i))
		out.surface_set_material(i, source.surface_get_material(i))
	_baked[name] = out
	return out


# Moves [param arrays]' vertices, normals and tangents by their weighted [param poses] and drops the bones and weights,
# leaving a plain mesh. False when the surface carries no bones.
static func _skin_arrays(arrays: Array, poses: Array[Transform3D], eight: bool) -> bool:
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var per := 8 if eight else 4
	if bones.size() < points.size() * per or weights.size() < points.size() * per:
		return false
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var has_normals := normals.size() == points.size()
	var has_tangents := tangents.size() == points.size() * 4
	for v in points.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var t := Vector3.ZERO
		var at := v * per
		var tangent := Vector3(tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2]) if has_tangents else Vector3.ZERO
		for k in per:
			var w := weights[at + k]
			if w == 0.0:
				continue
			var pose := poses[bones[at + k]]
			p += pose * points[v] * w
			if has_normals:
				n += pose.basis * normals[v] * w
			if has_tangents:
				t += pose.basis * tangent * w
		points[v] = p
		if has_normals:
			normals[v] = n.normalized()
		if has_tangents:
			t = t.normalized()
			tangents[v * 4] = t.x
			tangents[v * 4 + 1] = t.y
			tangents[v * 4 + 2] = t.z
	arrays[Mesh.ARRAY_VERTEX] = points
	if has_normals:
		arrays[Mesh.ARRAY_NORMAL] = normals
	if has_tangents:
		arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_BONES] = null
	arrays[Mesh.ARRAY_WEIGHTS] = null
	return true


## How many poses are baked.
static func count() -> int:
	return _baked.size()


## Drops every baked pose (a body's scene freed, or the process exiting).
static func clear() -> void:
	_baked.clear()
	_levels.clear()


# The detail levels of [param mesh]'s surface [param surface]: the same vertices, fewer indices, so a baked copy of the
# surface takes them as they are.
static func _levels_of(mesh: Mesh, surface: int) -> Dictionary:
	var name := "%d|%d" % [mesh.get_instance_id(), surface]
	if _levels.has(name):
		return _levels[name]
	var levels := {}
	var data := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	var wide := int(data.get("vertex_count", 0)) > 65535
	for level: Dictionary in data.get("lods", []):
		var bytes: PackedByteArray = level.get("index_data", PackedByteArray())
		var indices := PackedInt32Array()
		if wide:
			indices = bytes.to_int32_array()
		else:
			indices.resize(bytes.size() / 2)
			for j in indices.size():
				indices[j] = bytes.decode_u16(j * 2)
		if not indices.is_empty():
			levels[float(level.get("edge_length", 0.0))] = indices
	_levels[name] = levels
	return levels
