class_name DotPlayerRagdoll
extends Node3D

## One dead body: the figure's meshes copied onto rigid bodies joined at the hips, shoulders and
## neck, pushed the way the death says, settling, freezing, and fading after a while. Built by
## [DotPlayerRagdolls], which caps how many there are; see [DotPlayerRagdollRules] for the
## styles and [DotPlayerDeathReaction] for the falls.
##
## [b]Built from the drawn figure, whatever it is.[/b] The parts are found by name (a mesh or
## any ancestor up to the figure saying [code]head[/code], [code]torso[/code], [code]arm[/code]
## or [code]leg[/code] with [code]left[/code] or [code]right[/code]), which is what the block
## characters, the humanoid mounts and every game's figure here already call them. Meshes that
## are none of those (a crest, a gun in the hand) ride on the nearest part. A figure with no
## torso among its names (a capsule) becomes one rigid piece, which still falls over properly.
##
## [b]Copies, then hides the figure[/b], as [DotPlayerBodyBreak] does and for its reason: the
## figure is the player's, and a game frees or respawns it on its own schedule. The game shows
## its figure again on respawn.
##
## [b]Nothing collides with a body[/b] (layer 0): it lands on [member DotPlayerRagdollRules.collision_mask]
## and changes nothing in the game. [b]Its variations are seeded from the death[/b], never
## [code]randf()[/code], so every client builds the same fall.

const CHANNEL := "player.ragdoll"

## A body's sound: the reaction's start or land sound, where, and how hard (0 to 1).
signal sound(id: StringName, position: Vector3, strength: float)

## Every part has stopped and been frozen.
signal settled_now

enum Role { TORSO, HEAD, ARM_L, ARM_R, LEG_L, LEG_R, OTHER }

## Share of the body's mass each part carries; renormalised over the parts a figure has.
const MASS_SHARE := {
	Role.TORSO: 0.46, Role.HEAD: 0.08, Role.ARM_L: 0.055, Role.ARM_R: 0.055,
	Role.LEG_L: 0.175, Role.LEG_R: 0.175,
}

## How far each joint swings and twists, in degrees, before [member DotPlayerDeathReaction.looseness].
## A shoulder swings far and a neck does not; a hip in between. Cone limits are symmetric, so a
## knee-less leg folds as far back as forward, which a block figure cannot show anyway.
const SWING_DEG := {
	Role.HEAD: 40.0, Role.ARM_L: 95.0, Role.ARM_R: 95.0, Role.LEG_L: 60.0, Role.LEG_R: 60.0,
}
const TWIST_DEG := {
	Role.HEAD: 35.0, Role.ARM_L: 40.0, Role.ARM_R: 40.0, Role.LEG_L: 15.0, Role.LEG_R: 15.0,
}

## The part a body was built as: one rigid body (or, for TOPPLE, one node) and its role.
class Part:
	extends RefCounted
	var role: int = Role.OTHER
	var body: Node3D = null
	var joint: ConeTwistJoint3D = null
	var copies: Array[MeshInstance3D] = []
	## Each copy's transform as built, for the fade to shrink from.
	var copy_rest: Array[Transform3D] = []
	var size: Vector3 = Vector3.ZERO
	## The box's centre in the body's own space.
	var local_centre: Vector3 = Vector3.ZERO
	## The joint's frame in this part's own space, for rebuilding it where the part now is.
	var joint_local: Transform3D = Transform3D.IDENTITY
	## A skinned body's bones this part carries, and each one's transform in the part's frame.
	var bones: PackedInt32Array = PackedInt32Array()
	var bone_offsets: Array[Transform3D] = []
	## Where its joint goes, in world space when built; INF for "work it out from the box".
	var pivot: Vector3 = Vector3.INF

var rules: DotPlayerRagdollRules = null
var reaction: DotPlayerDeathReaction = null
var death: DotPlayerDeath = null

## What this body was built as; see [enum DotPlayerRagdollRules.Style].
var style: int = DotPlayerRagdollRules.Style.RAGDOLL

## Seconds since death.
var age: float = 0.0

## Every part stopped and frozen.
var settled: bool = false

## The land sound has played.
var landed: bool = false

## Fading out, early or on time.
var expiring: bool = false

var _parts: Array[Part] = []
var _fade_from: float = -1.0
var _fade_len: float = 1.0
var _still_for: float = 0.0
var _fastest: float = 0.0
var _fade_pivot: Vector3 = Vector3.ZERO
var _last_speed: Dictionary = {}
var _jointed_on_land: bool = false
var _source_roles: Dictionary = {}
var _topple_axis: Vector3 = Vector3.ZERO
var _topple_pivot: Vector3 = Vector3.ZERO
var _topple_angle: float = 0.0
var _topple_spin: float = 0.0
var _topple_start: Transform3D = Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()

# A skinned body: a copy of the figure's skeleton with copies of its skinned meshes on it, whose
# bones follow the parts (see [method _pose_bones]).
var _skel: Skeleton3D = null
var _skel_base: Transform3D = Transform3D.IDENTITY
var _skinned: Array[MeshInstance3D] = []
var _skinned_rest: Array[Transform3D] = []
var _bone_roles: PackedInt32Array = PackedInt32Array()
var _bone_order: PackedInt32Array = PackedInt32Array()


## Builds a body from [param figure] under [param world], or null when the style is HIDE or the
## figure has no meshes. [param velocity] is how the player was moving, carried into the fall.
##
## The figure is hidden; a game shows it again when the player respawns.
static func build(
	figure: Node3D,
	world: Node,
	p_rules: DotPlayerRagdollRules,
	p_reaction: DotPlayerDeathReaction,
	p_death: DotPlayerDeath,
	velocity: Vector3 = Vector3.ZERO
) -> DotPlayerRagdoll:
	if figure == null or world == null or p_rules == null or not figure.is_inside_tree():
		return null

	var chosen_style := p_rules.effective_style()
	if chosen_style == DotPlayerRagdollRules.Style.HIDE:
		figure.visible = false
		return null

	var meshes := meshes_of(figure)
	if meshes.is_empty():
		return null

	var made := DotPlayerRagdoll.new()
	made.name = "Ragdoll"
	made.rules = p_rules
	made.reaction = p_reaction if p_reaction != null else DotPlayerDeathReactions.stock().find(DotPlayerDeathReactions.LIMP)
	made.death = p_death if p_death != null else DotPlayerDeath.new()
	made._rng.seed = made.death.roll_seed
	world.add_child(made)

	# A skinned figure: its skeleton is copied, and the parts carry bones rather than meshes. What
	# else it holds (a gun on a hand bone) is copied as meshes and rides on the nearest part.
	var skinned := skinned_meshes(figure)
	if not skinned.is_empty():
		made._copy_skeleton(skinned)
		meshes = meshes.filter(func(m: MeshInstance3D) -> bool: return not skinned.has(m))

	for mesh in meshes:
		made._source_roles[mesh] = role_of(figure, mesh)
	var groups := group_by_role(figure, meshes)
	var named_torso := made._skel != null or meshes.any(func(m: MeshInstance3D) -> bool: return role_of(figure, m) == Role.TORSO)
	if chosen_style == DotPlayerRagdollRules.Style.RAGDOLL and not named_torso:
		# Nothing to hang limbs off: one piece is the honest body.
		chosen_style = DotPlayerRagdollRules.Style.STIFF
	made.style = chosen_style

	var forward := -figure.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

	match chosen_style:
		DotPlayerRagdollRules.Style.RAGDOLL:
			if made.reaction.pose == DotPlayerDeathReaction.Pose.FACE_PLANT:
				# A plank is one rigid body until the face lands, then the jointed body. Tight
				# joints are not a plank: on impact, five cone limits a few degrees wide threw
				# the test figure a hundred metres (docs/ragdolls.md).
				made._build_one(meshes, figure, true)
				made._jointed_on_land = true
			else:
				made._build_jointed(groups)
			made._drive(forward, velocity)
		DotPlayerRagdollRules.Style.STIFF:
			made._build_one(meshes, figure, true)
			made._drive(forward, velocity)
		_:
			made._build_one(meshes, figure, false)
			made._start_topple(figure, forward)

	figure.visible = false
	made._pose_bones()

	if made.reaction.start_sound != &"":
		# Deferred: whoever built this connects to [signal sound] after build returns.
		made.sound.emit.call_deferred(made.reaction.start_sound, figure.global_position + Vector3.UP, 1.0)

	DotLog.debug(CHANNEL, "body down", {
		"style": DotPlayerRagdollRules.style_name(chosen_style),
		"reaction": String(made.reaction.id),
		"parts": made._parts.size(),
	})
	return made


## The visible skinned meshes under [param figure] that are drawn by one skeleton (the first one
## found), or none. A skinned figure falls by its bones: see [method _copy_skeleton].
static func skinned_meshes(figure: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var skeleton: Skeleton3D = null
	for mesh in meshes_of(figure):
		if mesh.skin == null or mesh.skeleton.is_empty():
			continue
		var bones := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if bones == null or (skeleton != null and bones != skeleton):
			continue
		skeleton = bones
		out.append(mesh)
	return out


## Every visible mesh under [param figure], the figure itself counted visible: a game may have
## hidden its dead player's figure already, and the copy is still wanted.
static func meshes_of(figure: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(figure, out, true)
	return out


static func _collect(node: Node, out: Array[MeshInstance3D], is_root: bool) -> void:
	if not is_root and node is Node3D and not (node as Node3D).visible:
		return
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			out.append(mesh)
	for child in node.get_children():
		_collect(child, out, false)


## The role a mesh plays, from its own name and its ancestors' up to [param figure].
static func role_of(figure: Node, mesh: Node) -> int:
	var node: Node = mesh
	while node != null:
		var role := role_of_name(String(node.name))
		if role != Role.OTHER:
			return role
		if node == figure:
			break
		node = node.get_parent()
	return Role.OTHER


## The role one name says, or OTHER. Case and separators do not matter.
static func role_of_name(text: String) -> int:
	var t := text.to_lower().replace("_", "-").replace(" ", "-").replace(".", "-")
	var left := t.contains("left") or t.ends_with("-l") or t.begins_with("l-")
	var right := t.contains("right") or t.ends_with("-r") or t.begins_with("r-")
	if t.contains("head") or t.contains("skull"):
		return Role.HEAD
	if t.contains("arm") or t.contains("hand") or t.contains("shoulder") or t.contains("elbow"):
		if left != right:
			return Role.ARM_L if left else Role.ARM_R
	if t.contains("leg") or t.contains("foot") or t.contains("thigh") or t.contains("shin") or t.contains("knee"):
		if left != right:
			return Role.LEG_L if left else Role.LEG_R
	for word in ["torso", "chest", "spine", "pelvis", "hips", "trunk", "belly"]:
		if t.contains(word):
			return Role.TORSO
	return Role.OTHER


## Meshes by role. An OTHER mesh joins the role whose meshes' centre is nearest its own.
static func group_by_role(figure: Node, meshes: Array[MeshInstance3D]) -> Dictionary:
	return _group(meshes, func(mesh: MeshInstance3D) -> int: return role_of(figure, mesh))


static func _group(meshes: Array[MeshInstance3D], role_fn: Callable) -> Dictionary:
	var groups := {}
	var others: Array[MeshInstance3D] = []
	for mesh in meshes:
		var role: int = role_fn.call(mesh)
		if role == Role.OTHER:
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
			best = Role.TORSO
			if not groups.has(best):
				groups[best] = [] as Array[MeshInstance3D]
		(groups[best] as Array[MeshInstance3D]).append(mesh)
	return groups


static func _centre(mesh: MeshInstance3D) -> Vector3:
	return mesh.global_transform * mesh.mesh.get_aabb().get_center()


# --- Building --------------------------------------------------------------

func _build_jointed(groups: Dictionary) -> void:
	if _skel != null:
		_build_jointed_skeletal(groups)
		return

	var share_total := 0.0
	for role: int in groups:
		share_total += float(MASS_SHARE.get(role, 0.05))

	var torso: Part = null
	for role: int in [Role.TORSO, Role.HEAD, Role.ARM_L, Role.ARM_R, Role.LEG_L, Role.LEG_R]:
		if not groups.has(role):
			continue
		var list: Array[MeshInstance3D] = groups[role]
		var frame := Transform3D(list[0].global_basis.orthonormalized(), list[0].global_position)
		var part := _make_body(role, list, frame, rules.mass * float(MASS_SHARE.get(role, 0.05)) / share_total)
		if role == Role.TORSO:
			torso = part
	_finish_joints(torso)


## The parts joined to [param torso], and kept from colliding with each other.
func _finish_joints(torso: Part) -> void:
	if torso == null:
		return

	var torso_centre := _part_centre(torso)
	for part in _parts:
		if part != torso:
			_join(torso, part, torso_centre)

	# No part of one body collides with another: blocks that overlap at a shoulder would
	# otherwise push apart on the first step, which is the exploding-ragdoll bug.
	for i in range(_parts.size()):
		for j in range(i + 1, _parts.size()):
			(_parts[i].body as RigidBody3D).add_collision_exception_with(_parts[j].body)


## One piece holding every mesh: STIFF as a rigid body, TOPPLE as a plain node.
func _build_one(meshes: Array[MeshInstance3D], figure: Node3D, physical: bool) -> void:
	var frame := Transform3D(figure.global_basis.orthonormalized(), figure.global_position)
	if physical:
		var made := _make_body(Role.TORSO, meshes, frame, rules.mass)
		if _skel != null:
			_carry_bones(made, range(_skel.get_bone_count()), _skeletal_points(), true, true)
		return
	var part := Part.new()
	part.role = Role.TORSO
	var holder := Node3D.new()
	holder.name = "Body"
	add_child(holder)
	holder.global_transform = frame
	part.body = holder
	var bounds := _copy_meshes(part, meshes, frame)
	part.size = bounds.size
	part.local_centre = bounds.get_center()
	_parts.append(part)
	if _skel != null:
		_carry_bones(part, range(_skel.get_bone_count()), _skeletal_points(), false)


func _make_body(role: int, meshes: Array[MeshInstance3D], frame: Transform3D, part_mass: float) -> Part:
	var part := _new_body(role, frame, part_mass)
	var bounds := _copy_meshes(part, meshes, frame) if not meshes.is_empty() else AABB(Vector3.ZERO, Vector3.ONE * 0.08)
	_give_box(part, bounds)
	return part


## A rigid body for one part, placed at [param frame], with no shape yet.
func _new_body(role: int, frame: Transform3D, part_mass: float) -> Part:
	var part := Part.new()
	part.role = role

	var body := RigidBody3D.new()
	body.name = String(Role.keys()[role]).to_pascal_case()
	body.collision_layer = 0
	body.collision_mask = rules.collision_mask
	body.mass = maxf(part_mass, 0.5)
	body.linear_damp = rules.linear_damp
	body.angular_damp = rules.angular_damp
	# A launched head moves a metre in a frame: without this it is through the floor.
	body.continuous_cd = true
	body.can_sleep = true
	var material := PhysicsMaterial.new()
	material.friction = 0.9
	material.bounce = 0.05
	body.physics_material_override = material
	add_child(body)
	body.global_transform = frame
	part.body = body

	if role == Role.TORSO or role == Role.HEAD:
		body.contact_monitor = true
		body.max_contacts_reported = 2
		var _c := body.body_entered.connect(_on_contact.bind(part))

	_parts.append(part)
	return part


## Gives [param part]'s body its box: [param bounds] in its own frame.
func _give_box(part: Part, bounds: AABB) -> void:
	var body := part.body
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Never thinner than 8 cm: a flat shape tunnels into a floor even with CCD on.
	box.size = Vector3(maxf(bounds.size.x, 0.08), maxf(bounds.size.y, 0.08), maxf(bounds.size.z, 0.08))
	shape.shape = box
	shape.position = bounds.get_center()
	body.add_child(shape)
	part.size = box.size
	part.local_centre = shape.position


## Copies [param meshes] under [param part]'s node where they are now, and returns their
## bounds in [param frame]'s space.
func _copy_meshes(part: Part, meshes: Array[MeshInstance3D], frame: Transform3D) -> AABB:
	var holder := part.body
	var inverse := frame.affine_inverse()
	var bounds := AABB()
	var seeded := false

	for source in meshes:
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		copy.name = source.name
		copy.set_meta(&"dot_role", int(_source_roles.get(source, source.get_meta(&"dot_role", Role.OTHER))))
		copy.material_override = source.material_override
		copy.cast_shadow = source.cast_shadow
		for i in range(source.get_surface_override_material_count()):
			copy.set_surface_override_material(i, source.get_surface_override_material(i))
		holder.add_child(copy)
		# Instance uniforms are how a figure is tinted per player (game-arena's team colour);
		# a copy without them is everybody in the stock colour.
		for prop in source.get_property_list():
			var prop_name := String(prop["name"])
			if prop_name.begins_with("instance_shader_parameters/"):
				copy.set(prop_name, source.get(prop_name))
		# The scale lives on the copy: a RigidBody3D's own scale is reset by the physics server.
		copy.transform = inverse * source.global_transform
		var local := copy.transform * source.mesh.get_aabb()
		bounds = local if not seeded else bounds.merge(local)
		seeded = true
		part.copies.append(copy)
		part.copy_rest.append(copy.transform)
	return bounds


## The point a limb hangs from: the end of its long axis nearest [param torso_centre], or for a
## block (a head) the face nearest it.
func _pivot_of(part: Part, torso_centre: Vector3) -> Vector3:
	var body := part.body
	var half := part.size * 0.5
	var centre := body.global_transform * part.local_centre
	var axes := [body.global_basis.x, body.global_basis.y, body.global_basis.z]
	var longest := 0
	for i in range(1, 3):
		if half[i] > half[longest]:
			longest = i
	var sorted := [half.x, half.y, half.z]
	sorted.sort()
	var elongated: bool = float(sorted[2]) > float(sorted[1]) * 1.4

	if elongated:
		var a: Vector3 = centre + axes[longest] * half[longest]
		var b: Vector3 = centre - axes[longest] * half[longest]
		return a if a.distance_squared_to(torso_centre) < b.distance_squared_to(torso_centre) else b

	var toward := (torso_centre - centre)
	var best := 0
	var best_dot := -INF
	for i in range(3):
		var d := absf(toward.dot(axes[i])) / maxf(half[i], 0.01)
		if d > best_dot:
			best_dot = d
			best = i
	var sign_of := signf(toward.dot(axes[best]))
	return centre + axes[best] * half[best] * (sign_of if sign_of != 0.0 else -1.0)


func _part_centre(part: Part) -> Vector3:
	return part.body.global_transform * part.local_centre


func _join(torso: Part, part: Part, torso_centre: Vector3) -> void:
	var pivot := _pivot_of(part, torso_centre) if part.pivot == Vector3.INF else part.pivot
	var along := (_part_centre(part) - pivot)
	along = along.normalized() if along.length_squared() > 0.0001 else Vector3.DOWN

	# The twist axis is the joint's X: down the limb, away from the torso.
	var up_hint := Vector3.UP if absf(along.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var z := along.cross(up_hint).normalized()
	var y := z.cross(along).normalized()

	part.joint_local = part.body.global_transform.affine_inverse() * Transform3D(Basis(along, y, z), pivot)
	_make_joint(torso, part, reaction.looseness)


## Builds [param part]'s joint to the torso where the part is now, at [param looseness], placed
## from the part's own frame ([member Part.joint_local]) so a rebuilt joint is where the limb is.
func _make_joint(torso: Part, part: Part, looseness: float) -> void:
	if part.joint != null:
		# Freed now, not queued: two joints on one pair for a frame would both be solved.
		remove_child(part.joint)
		part.joint.free()
		part.joint = null
	var joint := ConeTwistJoint3D.new()
	joint.name = "Joint%s" % String(Role.keys()[part.role]).to_pascal_case()
	add_child(joint)
	joint.global_transform = part.body.global_transform * part.joint_local
	_set_looseness_of(joint, part.role, looseness)
	joint.node_a = joint.get_path_to(torso.body)
	joint.node_b = joint.get_path_to(part.body)
	part.joint = joint


static func _set_looseness_of(joint: ConeTwistJoint3D, role: int, looseness: float) -> void:
	var swing := deg_to_rad(float(SWING_DEG.get(role, 45.0)) * looseness)
	var twist := deg_to_rad(float(TWIST_DEG.get(role, 20.0)) * looseness)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, maxf(swing, 0.01))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, maxf(twist, 0.01))
	joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.9)
	joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)


# --- A skinned body -----------------------------------------------------------
#
# The same parts, the same joints, pushes, settling and fade as a body of rigid meshes: the only
# difference is what a part carries. Here it carries bones, and the copied skeleton's bones are
# put where their parts are after every step ([method _pose_bones]). One path for both kinds of
# figure, so every reaction tuned on the block figures (the plank that becomes jointed on landing,
# the crumple, the launches) falls the same way skinned; a PhysicalBoneSimulator3D would have been
# a second ragdoll with its own joints and its own tuning. docs/ragdolls.md has the reasoning.

## Copies the skeleton [param skinned] is drawn by, posed as it is now, with copies of the meshes
## on it, under this body. Each bone gets the role of its name, or its parent's.
func _copy_skeleton(skinned: Array[MeshInstance3D]) -> void:
	var source := skinned[0].get_node(skinned[0].skeleton) as Skeleton3D
	_skel = Skeleton3D.new()
	_skel.name = "Skeleton"
	for i in source.get_bone_count():
		var _b := _skel.add_bone(source.get_bone_name(i))
	for i in source.get_bone_count():
		_skel.set_bone_parent(i, source.get_bone_parent(i))
		_skel.set_bone_rest(i, source.get_bone_rest(i))
		_skel.set_bone_pose_position(i, source.get_bone_pose_position(i))
		_skel.set_bone_pose_rotation(i, source.get_bone_pose_rotation(i))
		_skel.set_bone_pose_scale(i, source.get_bone_pose_scale(i))
	add_child(_skel)
	_skel_base = source.global_transform
	_skel.global_transform = _skel_base

	for mesh in skinned:
		var copy := MeshInstance3D.new()
		copy.name = mesh.name
		copy.mesh = mesh.mesh
		copy.skin = mesh.skin
		copy.material_override = mesh.material_override
		copy.cast_shadow = mesh.cast_shadow
		for i in range(mesh.get_surface_override_material_count()):
			copy.set_surface_override_material(i, mesh.get_surface_override_material(i))
		for prop in mesh.get_property_list():
			var prop_name := String(prop["name"])
			if prop_name.begins_with("instance_shader_parameters/"):
				copy.set(prop_name, mesh.get(prop_name))
		_skel.add_child(copy)
		copy.transform = source.global_transform.affine_inverse() * mesh.global_transform
		copy.skeleton = NodePath("..")
		_skinned.append(copy)
		_skinned_rest.append(copy.transform)

	_bone_roles.resize(_skel.get_bone_count())
	var depth := {}
	for i in _skel.get_bone_count():
		var role := role_of_name(_skel.get_bone_name(i))
		var parent := _skel.get_bone_parent(i)
		if role == Role.OTHER:
			role = _bone_roles[parent] if parent >= 0 and parent < i else Role.TORSO
		_bone_roles[i] = role
		var d := 0
		var p := parent
		while p >= 0:
			d += 1
			p = _skel.get_bone_parent(p)
		depth[i] = d
	# A bone whose parent comes later in the list: resolve roles again in depth order.
	var order := range(_skel.get_bone_count())
	order.sort_custom(func(a: int, b: int) -> bool: return int(depth[a]) < int(depth[b]))
	for i: int in order:
		if role_of_name(_skel.get_bone_name(i)) == Role.OTHER:
			var parent := _skel.get_bone_parent(i)
			_bone_roles[i] = _bone_roles[parent] if parent >= 0 else Role.TORSO
	_bone_order = PackedInt32Array(order)


## A bone's transform in the world, from the copied skeleton's pose.
func _bone_world(bone: int) -> Transform3D:
	return _skel_base * _skel.get_bone_global_pose(bone)


## Where the body is, per role: world points of the skinned meshes' vertices (each by the bone
## that moves it most; every third, which is plenty for a box), and per role the bone that moves
## the most of them. Falls back to the bones' own joints when the mesh's arrays are not readable.
func _skeletal_points() -> Dictionary:
	var points := {}
	var counts := {}
	for mesh in _skinned:
		var skin := mesh.skin
		if mesh.mesh == null or skin == null:
			continue
		var bind_bones := PackedInt32Array()
		for b in skin.get_bind_count():
			var bone := skin.get_bind_bone(b)
			if bone < 0:
				bone = _skel.find_bone(skin.get_bind_name(b))
			bind_bones.append(bone)
		var poses := {}
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_WEIGHTS or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_BONES] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones.is_empty():
				continue
			var per := bones.size() / verts.size()
			for v in range(0, verts.size(), 3):
				var best := 0
				for k in per:
					if weights[v * per + k] > weights[v * per + best]:
						best = k
				var bind := bones[v * per + best]
				if bind < 0 or bind >= bind_bones.size() or bind_bones[bind] < 0:
					continue
				var bone := bind_bones[bind]
				if not poses.has(bind):
					poses[bind] = _skel_base * _skel.get_bone_global_pose(bone) * skin.get_bind_pose(bind)
				var at: Vector3 = (poses[bind] as Transform3D) * verts[v]
				var role := _bone_roles[bone]
				if not points.has(role):
					# An Array, not a PackedVector3Array: a packed array is a value, and appending
					# to one read out of a Dictionary appends to a copy (every box came out empty).
					points[role] = []
					counts[role] = {}
				(points[role] as Array).append(at)
				counts[role][bone] = int(counts[role].get(bone, 0)) + 1

	if points.is_empty():
		# Nothing readable: the joints, each bone to each of its children.
		for i in _skel.get_bone_count():
			var role := _bone_roles[i]
			if not points.has(role):
				points[role] = []
				counts[role] = {}
			(points[role] as Array).append(_bone_world(i).origin)
			counts[role][i] = int(counts[role].get(i, 0)) + 1

	var anchors := {}
	for role: int in counts:
		var best := -1
		for bone: int in counts[role]:
			if best < 0 or int(counts[role][bone]) > int(counts[role][best]):
				best = bone
		anchors[role] = best
	return {"points": points, "anchors": anchors}


## The jointed body of a skinned figure: one part per role, its box laid along the limb (from
## where it joins the torso to the middle of its vertices), joined there.
func _build_jointed_skeletal(mesh_groups: Dictionary) -> void:
	var found := _skeletal_points()
	var points: Dictionary = found["points"]
	var share_total := 0.0
	for role: int in points:
		share_total += float(MASS_SHARE.get(role, 0.05))
	var torso_at := _mean(points.get(Role.TORSO, []), global_position)
	var forward := -_skel_base.basis.z.normalized()

	var torso: Part = null
	for role: int in [Role.TORSO, Role.HEAD, Role.ARM_L, Role.ARM_R, Role.LEG_L, Role.LEG_R]:
		if not points.has(role):
			continue
		var bones: Array = []
		for i in _skel.get_bone_count():
			if _bone_roles[i] == role:
				bones.append(i)
		var centre := _mean(points[role], torso_at)
		var frame: Transform3D
		if role == Role.TORSO:
			var anchor: int = found["anchors"][role]
			frame = Transform3D(_bone_world(anchor).basis.orthonormalized(), centre)
		else:
			var top := _top_of(bones, torso_at)
			frame = Transform3D(_basis_along(centre - top, forward), top)
		var part := _new_body(role, frame, rules.mass * float(MASS_SHARE.get(role, 0.05)) / maxf(share_total, 0.01))
		if mesh_groups.has(role):
			var _b := _copy_meshes(part, mesh_groups[role], frame)
		_carry_bones(part, bones, found, true)
		if role != Role.TORSO:
			part.pivot = frame.origin
		if role == Role.TORSO:
			torso = part
	# Meshes riding on roles the skeleton has no part for go on the torso.
	for role: int in mesh_groups:
		if not points.has(role) and torso != null:
			var _c := _copy_meshes(torso, mesh_groups[role], torso.body.global_transform)
	_finish_joints(torso)


static func _mean(list: Array, fallback: Vector3) -> Vector3:
	if list.is_empty():
		return fallback
	var sum := Vector3.ZERO
	for p: Vector3 in list:
		sum += p
	return sum / float(list.size())


## A basis whose Y runs along [param along], with Z as near [param forward] as that allows.
static func _basis_along(along: Vector3, forward: Vector3) -> Basis:
	var y := along.normalized() if along.length_squared() > 0.0001 else Vector3.DOWN
	var z := forward - y * forward.dot(y)
	if z.length_squared() < 0.0001:
		z = Vector3.RIGHT.cross(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## The top of a part's chain: the one of [param bones] whose parent is not among them, nearest
## [param torso_at] (an arm's shoulder, a leg's hip; not the foot, which hangs off the root here).
func _top_of(bones: Array, torso_at: Vector3) -> Vector3:
	var best := Vector3.INF
	for bone: int in bones:
		var parent := _skel.get_bone_parent(bone)
		if parent >= 0 and bones.has(parent):
			continue
		var at := _bone_world(bone).origin
		if best == Vector3.INF or at.distance_squared_to(torso_at) < best.distance_squared_to(torso_at):
			best = at
	return best if best != Vector3.INF else torso_at


## Gives [param part] [param bones] (their offsets from where the part is now) and, when
## [param reshape], a box round the middle nine tenths of their points along each axis and its
## copies: a spike of hair or a shoulder pad is not what the body lands on.
##
## [param column] (the one-piece body): the box is the head, torso and legs alone. Arms held out
## and a gun in the hand made a person's plank a block as deep as it was wide, which a face
## plant's spin could not tip past its toes, so it stood back up (zz's survivors, 2026-10-12).
func _carry_bones(part: Part, bones: Array, found: Dictionary, reshape: bool, column: bool = false) -> void:
	var frame := part.body.global_transform
	var inverse := frame.affine_inverse()
	for bone: int in bones:
		part.bones.append(bone)
		part.bone_offsets.append(inverse * _bone_world(bone))

	var points: Dictionary = found["points"]
	var roles := {}
	for bone: int in bones:
		roles[_bone_roles[bone]] = true
	var xs: Array[float] = []
	var ys: Array[float] = []
	var zs: Array[float] = []
	if column:
		for arm: int in [Role.ARM_L, Role.ARM_R]:
			var _gone := roles.erase(arm)
	for role: int in roles:
		for p: Vector3 in (points.get(role, []) as Array):
			var local := inverse * p
			xs.append(local.x)
			ys.append(local.y)
			zs.append(local.z)
	var bounds := AABB()
	if not xs.is_empty():
		var lo := Vector3(_quantile(xs, 0.05), _quantile(ys, 0.03), _quantile(zs, 0.05))
		var hi := Vector3(_quantile(xs, 0.95), _quantile(ys, 0.97), _quantile(zs, 0.95))
		bounds = AABB(lo, hi - lo)
	for copy in part.copies:
		# A skinned copy's mesh bounds are its rest pose (arms out), not how it stands: the
		# points above already are the posed skin. A column leaves out what the hands hold too.
		if (copy.skin != null or column) and not xs.is_empty():
			continue
		var b := copy.transform * copy.mesh.get_aabb()
		bounds = b if xs.is_empty() else bounds.merge(b)

	if reshape and part.body is RigidBody3D:
		for child in part.body.get_children():
			if child is CollisionShape3D:
				part.body.remove_child(child)
				child.free()
		_give_box(part, bounds)
	elif not (part.body is RigidBody3D):
		part.size = bounds.size
		part.local_centre = bounds.get_center()


static func _quantile(values: Array[float], q: float) -> float:
	values.sort()
	return values[clampi(int(q * float(values.size() - 1)), 0, values.size() - 1)]


## Puts every carried bone where its part now is. Bones are written parents first, because a
## bone's global pose is stored as a local one under its parent's.
func _pose_bones() -> void:
	if _skel == null:
		return
	var base_inverse := _skel_base.affine_inverse()
	var wanted := {}
	for part in _parts:
		var at := part.body.global_transform
		for i in part.bones.size():
			wanted[part.bones[i]] = base_inverse * at * part.bone_offsets[i]
	for bone in _bone_order:
		if wanted.has(bone):
			_skel.set_bone_global_pose(bone, wanted[bone])


# --- Driving the fall --------------------------------------------------------

func _drive(forward: Vector3, velocity: Vector3) -> void:
	var k := rules.force_scale
	# Along the ground, mostly: a trap that kills "downward" or a shot from a roof pushes a body
	# into the floor, which reads as nothing. With no sideways part at all there is no push.
	var dir := death.direction
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.1:
		dir = Vector3.ZERO
	else:
		dir = (flat.normalized() + Vector3.UP * clampf(dir.y, -0.3, 0.3)).normalized()
	var strength := clampf(death.damage, 0.0, 300.0) / 100.0

	var base := velocity
	base += dir * reaction.push * strength * k
	base += dir * reaction.launch_along * k
	base += Vector3.UP * reaction.launch_up * k

	var torso := _part(Role.TORSO)
	var hit := _part(Role.HEAD) if death.headshot and _part(Role.HEAD) != null else torso

	match reaction.pose:
		DotPlayerDeathReaction.Pose.FACE_PLANT:
			# A plank falling about its feet: every part moves as one rigid rotation round the
			# point under the toes, so it goes over straight rather than folding.
			var axis := Vector3.UP.cross(forward).normalized()
			var feet := _feet_point(forward)
			var omega := axis * 1.6
			for part in _parts:
				var body := part.body as RigidBody3D
				# Undamped until it lands: the damping is for a body flapping on the floor, and
				# on a plank going over it ate the spin before the top passed the toes. A person
				# holding a gun out is a deep box, and stood back up (zz's survivors, 2026-10-12).
				body.angular_damp = 0.0
				body.angular_velocity = omega
				body.linear_velocity = velocity + omega.cross(_part_centre(part) - feet)
			return
		DotPlayerDeathReaction.Pose.CRUMPLE:
			# The legs fold forward under the body, which drops and tips back or forward by
			# the seed: a body sitting down hard and going over.
			var axis := Vector3.UP.cross(forward).normalized()
			var back := 1.0 if _rng.randf() < 0.5 else -1.0
			for part in _parts:
				var body := part.body as RigidBody3D
				body.linear_velocity = base + Vector3.DOWN * 1.2
				if part.role == Role.LEG_L or part.role == Role.LEG_R:
					body.angular_velocity = -axis * _rng.randf_range(4.0, 6.5)
					body.linear_velocity += forward * 1.4
				elif part.role == Role.TORSO:
					body.angular_velocity = axis * back * _rng.randf_range(0.8, 1.6)
		_:
			for part in _parts:
				(part.body as RigidBody3D).linear_velocity = base

	if hit != null and dir != Vector3.ZERO:
		(hit.body as RigidBody3D).linear_velocity += dir * reaction.hit_push * k

	if torso != null:
		var body := torso.body as RigidBody3D
		# Tipped the way the shot went (or backward from the facing with no shot), so nobody
		# balances upright on their feet, plus the reaction's seeded tumble.
		var fall_dir := dir if dir != Vector3.ZERO else -forward
		var tip := Vector3.UP.cross(fall_dir).normalized() * (1.2 + strength * 0.4)
		var tumble := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * reaction.spin * 0.35
		var flip := Vector3.UP.cross(fall_dir).normalized() * reaction.spin * k
		body.angular_velocity += tip + tumble + flip


## The ground point under the toes, for a fall forward.
func _feet_point(forward: Vector3) -> Vector3:
	var lowest := INF
	var front := -INF
	for part in _parts:
		var c := _part_centre(part)
		lowest = minf(lowest, c.y - part.size.y * 0.5)
		front = maxf(front, c.dot(forward) + part.size.z * 0.5)
	var torso := _part(Role.TORSO)
	var at := _part_centre(torso) if torso != null else global_position
	var along := at.dot(forward)
	return Vector3(at.x, lowest, at.z) + forward * (front - along)


func _part(role: int) -> Part:
	for part in _parts:
		if part.role == role:
			return part
	return null


# --- Topple: the no-physics fall --------------------------------------------

func _start_topple(figure: Node3D, forward: Vector3) -> void:
	var dir := death.direction
	dir.y = 0.0
	var fall := dir.normalized() if dir.length_squared() > 0.0001 else (forward if reaction.pose == DotPlayerDeathReaction.Pose.FACE_PLANT else -forward)
	if reaction.pose == DotPlayerDeathReaction.Pose.FACE_PLANT:
		fall = forward
	var holder := _parts[0].body
	# Pivot about the edge of the footprint on the side it falls to, so it lands lying ON the
	# floor rather than half through it.
	var bounds := AABB()
	var seeded := false
	for copy in _parts[0].copies:
		var b := holder.global_transform * copy.transform * copy.mesh.get_aabb()
		bounds = b if not seeded else bounds.merge(b)
		seeded = true
	if _skel != null:
		var box := holder.global_transform * AABB(_parts[0].local_centre - _parts[0].size * 0.5, _parts[0].size)
		bounds = box if not seeded else bounds.merge(box)
	var reach := absf(fall.x) * bounds.size.x * 0.5 + absf(fall.z) * bounds.size.z * 0.5
	var centre := bounds.get_center()
	_topple_pivot = Vector3(centre.x, bounds.position.y, centre.z) + fall * reach
	_topple_axis = Vector3.UP.cross(fall).normalized()
	_topple_start = holder.global_transform
	_topple_angle = 0.0
	_topple_spin = 0.0
	if _topple_axis == Vector3.ZERO:
		_topple_axis = Vector3.RIGHT


func _advance_topple(delta: float) -> void:
	if settled or _parts.is_empty():
		return
	# Gravity on a stick, roughly: the angular speed grows with how far over it is.
	_topple_spin += (2.0 + 9.0 * sin(_topple_angle)) * delta
	_topple_angle = minf(_topple_angle + _topple_spin * delta, PI * 0.5)
	var turn := Transform3D(Basis(_topple_axis, _topple_angle), Vector3.ZERO)
	var about := Transform3D(Basis.IDENTITY, _topple_pivot) * turn * Transform3D(Basis.IDENTITY, -_topple_pivot)
	_parts[0].body.global_transform = about * _topple_start
	if _topple_angle >= PI * 0.5:
		_land(_topple_pivot, 1.0)
		settled = true
		settled_now.emit()


# --- Life --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	advance(delta)


## Ages the body by [param delta]: the topple, the land check, settling and the fade. Public so
## a suite can step it.
func advance(delta: float) -> void:
	age += delta

	var was_settled := settled
	if style == DotPlayerRagdollRules.Style.TOPPLE:
		_advance_topple(delta)
	elif not settled:
		_watch_motion(delta)
	if not was_settled:
		_pose_bones()

	if not expiring and rules != null and age >= rules.lifetime:
		expire(rules.fade)

	if expiring:
		var left := 1.0 - clampf((age - _fade_from) / maxf(_fade_len, 0.01), 0.0, 1.0)
		# Shrunk into the floor as well as faded: the compatibility renderer (every web client)
		# ignores [member GeometryInstance3D.transparency], and a body that stays solid until
		# it vanishes is the pop this fade exists to avoid.
		# One shrink about one point on the floor under the body, so the parts close in together
		# rather than each shrinking about its own middle and drifting apart.
		var squeeze := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(left, 0.01)), Vector3.ZERO)
		var about := Transform3D(Basis.IDENTITY, _fade_pivot) * squeeze * Transform3D(Basis.IDENTITY, -_fade_pivot)
		for part in _parts:
			var to_local := part.body.global_transform.affine_inverse()
			for i in range(part.copies.size()):
				var copy := part.copies[i]
				copy.transparency = 1.0 - left
				if i < part.copy_rest.size():
					copy.transform = to_local * about * part.body.global_transform * part.copy_rest[i]
		if _skel != null:
			# The bones are posed in the skeleton's own space, so shrinking the skeleton's node
			# about the point shrinks the skinned body with everything else.
			_skel.global_transform = about * _skel_base
			for copy in _skinned:
				copy.transparency = 1.0 - left
		if left <= 0.0:
			queue_free()


func _watch_motion(delta: float) -> void:
	var fastest := 0.0
	for part in _parts:
		var body := part.body as RigidBody3D
		if body == null:
			continue
		var speed := body.linear_velocity.length()
		# One piece that stood on the floor it falls onto never reports touching it again (its
		# toes never left), so a plank lying down on it has landed: on zz's streets the face plant
		# never went limp and never smacked.
		if not landed and _parts.size() == 1 and age >= 0.25 and body.get_contact_count() > 0 \
				and absf(body.global_basis.y.dot(Vector3.UP)) <= 0.3:
			var was := float(_last_speed.get(part, speed))
			if was >= reaction.land_speed:
				_land(body.global_position, clampf(was / 4.0, 0.3, 1.0))
		_last_speed[part] = speed
		fastest = maxf(fastest, maxf(speed, body.angular_velocity.length() * 0.2))

	_fastest = fastest
	_still_for = _still_for + delta if fastest < rules.settle_speed else 0.0

	if _still_for >= rules.settle_time or age >= rules.max_sim_time:
		freeze_all()


## Stops every part where it lies. Frozen bodies cost nothing to keep.
func freeze_all() -> void:
	for part in _parts:
		var body := part.body as RigidBody3D
		if body != null:
			body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			body.freeze = true
	settled = true
	settled_now.emit()


## Starts fading now, over [param seconds]. The cap's way to make room.
func expire(seconds: float) -> void:
	if expiring:
		return
	expiring = true
	_fade_from = age
	_fade_len = seconds
	var sum := Vector3.ZERO
	for part in _parts:
		sum += _part_centre(part)
	_fade_pivot = sum / maxf(float(_parts.size()), 1.0)
	_fade_pivot.y = lowest_point()


func _on_contact(_other: Node, part: Part) -> void:
	if landed or age < 0.25:
		return
	var body := part.body as RigidBody3D
	# One rigid piece stands on its own feet from the start and scrapes them as it tips: it has
	# landed when it is lying down, not when its toes touch.
	if _parts.size() == 1 and absf(body.global_basis.y.dot(Vector3.UP)) > 0.55:
		return
	var speed := float(_last_speed.get(part, body.linear_velocity.length()))
	if speed < reaction.land_speed:
		return
	_land(body.global_position, clampf(speed / 4.0, 0.3, 1.0))


func _land(at: Vector3, strength: float) -> void:
	if landed:
		return
	landed = true
	for part in _parts:
		if part.body is RigidBody3D:
			(part.body as RigidBody3D).angular_damp = rules.angular_damp
	if _jointed_on_land:
		# The plank lets go when the face meets the floor: limp from here. Deferred, because
		# this runs inside the physics server's contact report, and bodies added there are
		# added mid-step.
		_jointed_on_land = false
		_become_jointed.call_deferred()
	if reaction.land_sound != &"":
		sound.emit(reaction.land_sound, at, strength)


## Turns the one rigid piece into the jointed body where it lies, moving as it moved.
func _become_jointed() -> void:
	if _parts.size() != 1 or not is_inside_tree():
		return
	var old := _parts[0]
	var old_body := old.body as RigidBody3D
	var v := old_body.linear_velocity
	var w := old_body.angular_velocity
	var com := old_body.global_transform * old_body.center_of_mass
	var groups := _group(old.copies, func(copy: MeshInstance3D) -> int: return int(copy.get_meta(&"dot_role", Role.OTHER)))
	if not groups.has(Role.TORSO) and _skel == null:
		return
	_parts.clear()
	_build_jointed(groups)
	for part in _parts:
		var body := part.body as RigidBody3D
		body.linear_velocity = v + w.cross(_part_centre(part) - com)
		body.angular_velocity = w
	remove_child(old_body)
	old_body.free()


## The parts, for a suite or a game that wants to look: each a [Node3D] (a [RigidBody3D] unless
## the style is TOPPLE).
func part_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for part in _parts:
		out.append(part.body)
	return out


## The copied skeleton a skinned body is drawn with, or null for a body of rigid meshes.
func skeleton_copy() -> Skeleton3D:
	return _skel


func part_count() -> int:
	return _parts.size()


func joint_count() -> int:
	var n := 0
	for part in _parts:
		if part.joint != null:
			n += 1
	return n


## The lowest point of any part's box, in world space: a suite's "is it through the floor".
func lowest_point() -> float:
	var lowest := INF
	for part in _parts:
		var body := part.body
		for child in body.get_children():
			if child is CollisionShape3D:
				var box := (child as CollisionShape3D).shape as BoxShape3D
				var half := box.size * 0.5
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						for sz in [-1.0, 1.0]:
							var p := body.global_transform * ((child as CollisionShape3D).position + Vector3(sx * half.x, sy * half.y, sz * half.z))
							lowest = minf(lowest, p.y)
	if lowest == INF and _skel != null:
		for part in _parts:
			var box := part.body.global_transform * AABB(part.local_centre - part.size * 0.5, part.size)
			lowest = minf(lowest, box.position.y)
	if lowest == INF:
		for part in _parts:
			for copy in part.copies:
				var b := copy.global_transform * copy.mesh.get_aabb()
				lowest = minf(lowest, b.position.y)
	return lowest


## Where the body's middle is now.
func centre() -> Vector3:
	var torso := _part(Role.TORSO)
	if torso == null:
		return global_position
	return _part_centre(torso)


func describe() -> Dictionary:
	return {
		"style": DotPlayerRagdollRules.style_name(style),
		"reaction": String(reaction.id) if reaction != null else "",
		"parts": _parts.size(),
		"joints": joint_count(),
		"age": snappedf(age, 0.01),
		"settled": settled,
		"moving": snappedf(_fastest, 0.01),
		"landed": landed,
		"expiring": expiring,
		"skinned": _skel != null,
	}
