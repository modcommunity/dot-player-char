class_name DotPeopleViewChecks
extends RefCounted

## The suite's view-arms section, split out to keep people_selftest under the file-size gate.
## Reports through the suite's own `_section` and `_check`, so the totals stay one set.

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("your own arms while downed")
	var arms := DotPlayerViewArms.new()
	suite.add_child(arms)
	arms.build(DotHumanoidLook.stock(3), 1.8)
	suite._check(arms.arms() is DotHumanoidFigure and not arms.arms().visible, "built hidden, as a figure")
	suite._check(arms.describe()["hidden_bones"] == 4, "head, neck and both legs are shrunk away")
	arms.set_downed(true)
	for i in 4:
		arms.tick(1.0, 1.0 / 30.0)
		await suite.get_tree().process_frame
	suite._check(arms.arms().visible, "shown while downed")
	var sk: Skeleton3D = (arms.arms() as DotHumanoidFigure).skeleton()
	suite._check(sk.get_bone_pose_scale(sk.find_bone("Head")).x < 0.01 and sk.get_bone_pose_scale(sk.find_bone("LowerArm.L")).x > 0.5, "the head is gone and the arms are not")
	var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin
	var hand := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Middle1.L"))).origin
	suite._check(hand.z < head.z - 0.2 and hand.y < head.y, "the hand reaches ahead of the eye (-Z) and below it")
	var pack := _gear_triangles(arms.arms() as DotHumanoidFigure)
	suite._check(pack == 0, "the view figure has no backpack surface (%d triangles)" % pack)
	var bare := DotPlayerViewArms.new()
	suite.add_child(bare)
	bare.hide_vertex_fn = func(_b, _p): return false
	bare.build(DotHumanoidLook.stock(7), 1.8)
	suite._check(_gear_triangles(bare.arms() as DotHumanoidFigure) > 0, "without the hide the stock figure does carry a pack (the check can fail)")
	bare.queue_free()
	var wrapped := DotHumanoidLook.stock(7)
	wrapped.body = &"shaun"
	var sides := []
	for mirror in [true, false]:
		var held := DotPlayerViewArms.new()
		suite.add_child(held)
		held.mirror_support_forearm = mirror
		held.build(wrapped, 1.8)
		sides.append(_forearm_triangles(held.arms() as DotHumanoidFigure))
		held.queue_free()
	suite._check(sides[0][0] == sides[0][1] and sides[1][0] != sides[1][1], "the support forearm is the firing one mirrored, so a one-sided bandage is not drawn (%s, unmirrored %s)" % [sides[0], sides[1]])
	arms.set_downed(false)
	suite._check(not arms.arms().visible, "hidden once up")
	var custom := DotPlayerViewArms.new()
	suite.add_child(custom)
	custom.arms_factory = func(_l, _h): return Node3D.new()
	custom.build()
	suite._check(custom.describe()["custom"] and custom.arms().get_class() == "Node3D", "a game supplies its own arms")
	arms.queue_free()
	custom.queue_free()


## Triangles with a vertex on the hips more than 0.3 behind the body: the stock kit's backpack.
func _gear_triangles(figure: DotHumanoidFigure) -> int:
	var sk := figure.skeleton()
	var arrays := figure.mesh().mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per := bones.size() / verts.size()
	var n := 0
	for t in range(0, index.size() - 2, 3):
		for c in 3:
			var v := index[t + c]
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			if sk.get_bone_name(bones[v * per + best]) == "Hips" and verts[v].z < -0.3:
				n += 1
				break
	return n


## Triangles wholly on each forearm and hand (support, firing), bones read through the skin's binds.
func _forearm_triangles(figure: DotHumanoidFigure) -> Array:
	var sk := figure.skeleton()
	var skin := figure.mesh().skin
	var arrays := figure.mesh().mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per := bones.size() / (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var counts := [0, 0]
	for t in range(0, index.size() - 2, 3):
		var sides := {}
		for c in 3:
			var v := index[t + c]
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			var bone := sk.find_bone(skin.get_bind_name(bones[v * per + best]))
			var side := ""
			while bone >= 0 and side == "":
				side = sk.get_bone_name(bone).trim_prefix("LowerArm") if sk.get_bone_name(bone).begins_with("LowerArm") else ""
				bone = sk.get_bone_parent(bone)
			sides[side] = true
		if sides.size() == 1 and sides.has(".L"):
			counts[0] += 1
		elif sides.size() == 1 and sides.has(".R"):
			counts[1] += 1
	return counts
