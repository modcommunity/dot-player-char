extends "dot_player_view_arms_state.gd"

## The build-time half of [DotPlayerViewArms]: stripping the figure's mesh down to arms and hands.


## Gear is skinned into the body mesh, so it goes by dropping its triangles from this figure's own copy of the mesh.
func _strip_gear(figure: DotHumanoidFigure) -> void:
	var instance := figure.mesh()
	var skeleton := figure.skeleton()

	if instance == null or skeleton == null or instance.mesh == null:
		return

	var old := instance.mesh
	var out := ArrayMesh.new()
	var one_arm := ArrayMesh.new()

	for s in old.get_surface_count():
		var arrays := old.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var per := bones.size() / maxi(verts.size(), 1)
		var gear := PackedByteArray()
		gear.resize(verts.size())

		for v in verts.size():
			if per < 1 or weights.size() < verts.size() * per:
				break

			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k

			var bone := StringName(skeleton.get_bone_name(bones[v * per + best]))
			gear[v] = 1 if _is_gear(bone, verts[v]) else 0

		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if index.is_empty():
			index.resize(verts.size())
			for i in verts.size():
				index[i] = i

		var kept := PackedInt32Array()
		for t in range(0, index.size() - 2, 3):
			if gear[index[t]] == 0 and gear[index[t + 1]] == 0 and gear[index[t + 2]] == 0:
				kept.append_array(index.slice(t, t + 3))

		arrays[Mesh.ARRAY_INDEX] = kept
		arrays[Mesh.ARRAY_CUSTOM0] = _rest_positions(verts)
		if mirror_support_forearm and instance.skin != null:
			_mirror_forearm(arrays, skeleton, instance.skin)
		# Shrunk to a point, a hidden bone still pulls every vertex that carries any of its weight: the collar and hip
		# triangles blended onto the head or a leg stretched into a skin wedge across the lower view (PLAYLOT).
		arrays[Mesh.ARRAY_INDEX] = _keep_off(arrays, skeleton, instance.skin, HIDDEN_BONES)
		out.add_surface_from_arrays(old.surface_get_primitive_type(s), arrays, [], {}, DotViewArmsMaterial.REST_FORMAT)
		out.surface_set_material(s, old.surface_get_material(s))
		var one := arrays.duplicate()
		one[Mesh.ARRAY_INDEX] = _keep_off(arrays, skeleton, instance.skin, LEFT_ARM_BONES)
		one_arm.add_surface_from_arrays(old.surface_get_primitive_type(s), one, [], {}, DotViewArmsMaterial.REST_FORMAT)
		one_arm.surface_set_material(s, old.surface_get_material(s))

	instance.mesh = out
	_two_arm_mesh = out
	_one_arm_mesh = one_arm


## [param arrays]' triangle indices less the triangles with a vertex carrying more than [constant TOUCH_WEIGHT] on a bone
## at or under one of [param roots].
func _keep_off(arrays: Array, skeleton: Skeleton3D, skin: Skin, roots: Array[String]) -> PackedInt32Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := verts.size()
	var per := bones.size() / maxi(n, 1)
	if per < 1 or weights.size() < n * per:
		return index
	var under := {}
	var touch := PackedByteArray()
	touch.resize(n)
	for v in n:
		for k in per:
			if weights[v * per + k] <= TOUCH_WEIGHT:
				continue
			var b := bones[v * per + k]
			if not under.has(b):
				under[b] = _under(skeleton, _bind_bone(skeleton, skin, b) if skin != null else b, roots)
			if under[b]:
				touch[v] = 1
				break
	var kept := PackedInt32Array()
	for t in range(0, index.size() - 2, 3):
		if touch[index[t]] == 0 and touch[index[t + 1]] == 0 and touch[index[t + 2]] == 0:
			kept.append_array(index.slice(t, t + 3))
	# A surface wholly on those bones keeps one empty triangle: an empty one fails to build, and the surfaces after it
	# would shift onto the wrong materials.
	if kept.is_empty() and n > 0:
		kept = PackedInt32Array([0, 0, 0])
	return kept


func _under(skeleton: Skeleton3D, bone: int, roots: Array[String]) -> bool:
	while bone >= 0:
		if skeleton.get_bone_name(bone) in roots:
			return true
		bone = skeleton.get_bone_parent(bone)
	return false


## The two real hands, coloured as the kit's own hand is drawn: the arms' material and its hand's spot on the atlas.
func _make_hands(figure: DotHumanoidFigure) -> void:
	var instance := figure.mesh()
	var material: Material = instance.material_override if instance.material_override != null else instance.get_active_material(0)
	for right in [true, false]:
		var hand := DotViewHand.new()
		hand.name = "HandR" if right else "HandL"
		hand.right = right
		hand.skin_uv = _hand_uv(instance, figure.skeleton(), ".R" if right else ".L")
		hand.material = material
		hand.build()
		hand.visible = false
		add_child(hand)
		_hands.append(hand)


## The atlas spot of the kit hand on [param side] (".R"): the UV of a vertex bound mostly to a finger root, so a gloved
## outfit's hands stay gloved. Vector2.ZERO when the mesh has none.
func _hand_uv(instance: MeshInstance3D, skeleton: Skeleton3D, side: String) -> Vector2:
	var mesh := instance.mesh
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var n := uvs.size()
		var per := bones.size() / maxi(n, 1)
		if n == 0 or per < 1 or weights.size() < n * per:
			continue
		for v in n:
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			if weights[v * per + best] < 0.9:
				continue
			var b := bones[v * per + best]
			var bone := _bind_bone(skeleton, instance.skin, b) if instance.skin != null else b
			if bone >= 0 and skeleton.get_bone_name(bone).trim_suffix(side) in FINGER_ROOTS and skeleton.get_bone_name(bone).ends_with(side):
				return uvs[v]
	return Vector2.ZERO


## Each vertex's rest position for [DotViewArmsMaterial]'s pattern, four floats a vertex.
func _rest_positions(verts: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(verts.size() * 4)
	for v in verts.size():
		out[v * 4] = verts[v].x
		out[v * 4 + 1] = verts[v].y
		out[v * 4 + 2] = verts[v].z
		out[v * 4 + 3] = 1.0
	return out


## Replaces the support forearm and hand with the firing ones mirrored across the body (x = the forearms' midpoint).
## A body's one-sided forearm gear (a bandage's loose wraps) otherwise crosses the view as torn-looking strips.
func _mirror_forearm(arrays: Array, skeleton: Skeleton3D, skin: Skin) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var n := verts.size()
	var per := bones.size() / maxi(n, 1)
	var bind_of := {}
	var at := {}
	for b in skin.get_bind_count():
		var bone := _bind_bone(skeleton, skin, b)
		if bone >= 0:
			bind_of[skeleton.get_bone_name(bone)] = b
			at[skeleton.get_bone_name(bone)] = skin.get_bind_pose(b).affine_inverse().origin
	if per < 1 or weights.size() < n * per or not at.has("LowerArm.L") or not at.has("LowerArm.R"):
		return
	var l: Vector3 = at["LowerArm.L"]
	var r: Vector3 = at["LowerArm.R"]
	if absf(l.y - r.y) > 0.01 or absf(l.z - r.z) > 0.01:
		return
	var mid := (l.x + r.x) * 0.5
	var side := PackedByteArray()
	side.resize(n)
	for v in n:
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		side[v] = _forearm_side(skeleton, skin, bones[v * per + best])
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	var copied := {}
	var added := PackedInt32Array()
	for t in range(0, index.size() - 2, 3):
		var tri := [index[t], index[t + 1], index[t + 2]]
		if side[tri[0]] == 1 and side[tri[1]] == 1 and side[tri[2]] == 1:
			continue
		kept.append_array(index.slice(t, t + 3))
		if side[tri[0]] == 2 and side[tri[1]] == 2 and side[tri[2]] == 2:
			for c in [0, 2, 1]:
				if not copied.has(tri[c]):
					copied[tri[c]] = n + copied.size()
					added.append(tri[c])
				kept.append(copied[tri[c]])
	for a in arrays.size():
		var src = arrays[a]
		if a == Mesh.ARRAY_INDEX or not (src is PackedVector3Array or src is PackedFloat32Array or src is PackedVector2Array or src is PackedInt32Array or src is PackedColorArray):
			continue
		var w: int = src.size() / n
		for v in added:
			for k in w:
				var value = src[v * w + k]
				if a == Mesh.ARRAY_VERTEX:
					value = Vector3(2.0 * mid - value.x, value.y, value.z)
				elif a == Mesh.ARRAY_NORMAL:
					value = Vector3(-value.x, value.y, value.z)
				elif a == Mesh.ARRAY_TANGENT and (k == 0 or k == 3):
					value = -value
				elif a == Mesh.ARRAY_BONES:
					value = bind_of.get(String(skeleton.get_bone_name(_bind_bone(skeleton, skin, value))).trim_suffix(".R") + ".L", value)
				src.append(value)
		arrays[a] = src
	arrays[Mesh.ARRAY_INDEX] = kept


## 1 for a bind on the support forearm or hand (LowerArm.L and below), 2 on the firing one, else 0.
func _forearm_side(skeleton: Skeleton3D, skin: Skin, bind: int) -> int:
	var bone := _bind_bone(skeleton, skin, bind)
	while bone >= 0:
		var bone_name := skeleton.get_bone_name(bone)
		if bone_name == "LowerArm.L":
			return 1
		if bone_name == "LowerArm.R":
			return 2
		bone = skeleton.get_bone_parent(bone)
	return 0


func _bind_bone(skeleton: Skeleton3D, skin: Skin, bind: int) -> int:
	return skeleton.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)


func _is_gear(bone: StringName, rest: Vector3) -> bool:
	if hide_vertex_fn.is_valid():
		return bool(hide_vertex_fn.call(bone, rest))

	return bone == PACK_BONE and rest.z < PACK_BEHIND
