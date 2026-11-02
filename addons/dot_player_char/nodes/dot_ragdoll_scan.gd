class_name DotRagdollScan
extends RefCounted

## Reads a figure for [DotPlayerRagdoll]: which meshes it has and which body part each is.
## The public entry points are the static methods on [DotPlayerRagdoll].


## The visible skinned meshes under [param figure] that are drawn by one skeleton (the first one
## found), or none. A skinned figure falls by its bones: see [method _copy_skeleton].
static func skinned_meshes(figure: Node, hidden := false) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var skeleton: Skeleton3D = null
	for mesh in meshes_of(figure, hidden):
		if mesh.skin == null or mesh.skeleton.is_empty():
			continue
		var bones := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if bones == null or (skeleton != null and bones != skeleton):
			continue
		skeleton = bones
		out.append(mesh)
	return out


## Every visible mesh under [param figure], minus top_level subtrees (effects that do not move with it);
## [param hidden] keeps hidden ones too, for a first-person body hidden by set_drawn that still leaves a corpse.
static func meshes_of(figure: Node, hidden := false) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(figure, out, true, hidden)
	return out


static func _collect(node: Node, out: Array[MeshInstance3D], is_root: bool, hidden: bool) -> void:
	if not is_root and node is Node3D and ((not (node as Node3D).visible and not hidden) or (node as Node3D).top_level):
		return
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			out.append(mesh)
	for child in node.get_children():
		_collect(child, out, false, hidden)


## The role a mesh plays, from its own name and its ancestors' up to [param figure].
static func role_of(figure: Node, mesh: Node) -> int:
	var node: Node = mesh
	while node != null:
		var role := role_of_name(String(node.name))
		if role != DotPlayerRagdoll.Role.OTHER:
			return role
		if node == figure:
			break
		node = node.get_parent()
	return DotPlayerRagdoll.Role.OTHER


## The role one name says, or OTHER. Case and separators do not matter.
static func role_of_name(text: String) -> int:
	var t := text.to_lower().replace("_", "-").replace(" ", "-").replace(".", "-")
	var left := t.contains("left") or t.ends_with("-l") or t.begins_with("l-")
	var right := t.contains("right") or t.ends_with("-r") or t.begins_with("r-")
	if t.contains("head") or t.contains("skull"):
		return DotPlayerRagdoll.Role.HEAD
	if t.contains("arm") or t.contains("hand") or t.contains("shoulder") or t.contains("elbow"):
		if left != right:
			return DotPlayerRagdoll.Role.ARM_L if left else DotPlayerRagdoll.Role.ARM_R
	if t.contains("leg") or t.contains("foot") or t.contains("thigh") or t.contains("shin") or t.contains("knee"):
		if left != right:
			return DotPlayerRagdoll.Role.LEG_L if left else DotPlayerRagdoll.Role.LEG_R
	for word in ["torso", "chest", "spine", "pelvis", "hips", "trunk", "belly"]:
		if t.contains(word):
			return DotPlayerRagdoll.Role.TORSO
	return DotPlayerRagdoll.Role.OTHER


## Meshes by role. An OTHER mesh joins the role whose meshes' centre is nearest its own.
static func group_by_role(figure: Node, meshes: Array[MeshInstance3D]) -> Dictionary:
	return group(meshes, func(mesh: MeshInstance3D) -> int: return role_of(figure, mesh))


## Groups [param meshes] by the role [param role_fn] gives each; an OTHER mesh joins the nearest group.
static func group(meshes: Array[MeshInstance3D], role_fn: Callable) -> Dictionary:
	var groups := {}
	var others: Array[MeshInstance3D] = []
	for mesh in meshes:
		var role: int = role_fn.call(mesh)
		if role == DotPlayerRagdoll.Role.OTHER:
			others.append(mesh)
			continue
		if not groups.has(role):
			groups[role] = [] as Array[MeshInstance3D]
		(groups[role] as Array[MeshInstance3D]).append(mesh)

	for mesh in others:
		var at := _centre(mesh)
		var best := -1
		var best_d := INF
		for role: int in groups:
			for other: MeshInstance3D in groups[role]:
				var d := at.distance_squared_to(_centre(other))
				if d < best_d:
					best_d = d
					best = role
		if best < 0:
			best = DotPlayerRagdoll.Role.TORSO
			if not groups.has(best):
				groups[best] = [] as Array[MeshInstance3D]
		(groups[best] as Array[MeshInstance3D]).append(mesh)
	return groups


static func _centre(mesh: MeshInstance3D) -> Vector3:
	return mesh.global_transform * mesh.mesh.get_aabb().get_center()
