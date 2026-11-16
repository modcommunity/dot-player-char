extends RefCounted

## The suite's far stand-in section ([member DotHumanoidFigure.stand_in_range]), split out to keep people_selftest
## under the file-size gate. Reports through the suite's `_section` and `_check`.

const DT := 1.0 / 60.0

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("a far figure is drawn as its stand-in")
	var cam := Camera3D.new()
	suite.add_child(cam)
	cam.position = Vector3(0, 1.6, 60.0)
	cam.make_current()
	var g := DotHumanoidFigure.new()
	suite.add_child(g)
	g.build(DotHumanoidLook.stock(9), 1.8)
	var skin := g.mesh()
	var own_mesh := skin.mesh
	var own_skeleton := skin.skeleton
	g.set_hold(DotHumanoidFigure.Hold.GUN)
	_run(g, 30)
	var off := not g.standing_in() and skin.mesh == own_mesh

	DotHumanoidFigure.stand_in_range = 40.0
	# Every step here is in one engine frame: let each bake in at once.
	DotHumanoidFigure.stand_in_bakes_per_frame = 0
	DotHumanoidStandIn.clear()
	_run(g, 240)
	var baked := skin.mesh
	var levels_own: Array = RenderingServer.mesh_get_surface(own_mesh.get_rid(), 0).get("lods", [])
	var levels_baked: Array = RenderingServer.mesh_get_surface(baked.get_rid(), 0).get("lods", []) if baked != null else []
	suite._check(off and g.standing_in() and baked != own_mesh and skin.skeleton.is_empty() and skin.visible
			and levels_baked.size() == levels_own.size() and DotHumanoidStandIn.count() >= 2,
		"stand_in_range 40 at 60 m: off by default; then the skin draws a shared baked pose (%d baked, %d of %d detail levels kept)"
			% [DotHumanoidStandIn.count(), levels_baked.size(), levels_own.size()])

	# Every pose of the run baked: from here on the skeleton is not written at all, and the pose drawn goes round.
	var bone := g.skeleton().find_bone("UpperLeg.L")
	bone = bone if bone >= 0 else 1
	var before := g.skeleton().get_bone_pose(bone)
	var drawn := {}
	for i in 120:
		g.animate(4.0, DT)
		drawn[skin.mesh] = true
	var still := g.skeleton().get_bone_pose(bone) == before
	suite._check(still and drawn.size() >= 4 and g.standing_in(),
		"a walking stand-in writes no bone (%s) and steps through %d shared poses" % [still, drawn.size()])

	var other := DotHumanoidFigure.new()
	suite.add_child(other)
	other.build(DotHumanoidLook.stock(9), 1.8)
	other.set_hold(DotHumanoidFigure.Hold.GUN)
	var count := DotHumanoidStandIn.count()
	_run(other, 120)
	suite._check(other.standing_in() and DotHumanoidStandIn.count() == count,
		"a second figure of the same body shares the poses already baked (%d, was %d)" % [DotHumanoidStandIn.count(), count])

	cam.position = Vector3(0, 1.6, 35.0)
	g.animate(0.0, DT)
	var near_back := not g.standing_in() and skin.mesh == own_mesh and skin.skeleton == own_skeleton
	cam.position = Vector3(0, 1.6, 60.0)
	_run(other, 8)
	var meshes := DotPlayerRagdoll.meshes_of(other)
	suite._check(near_back and not other.standing_in() and meshes.size() == 1 and meshes[0].skeleton == own_skeleton,
		"nearer than the range less a tenth the skin is back; a ragdoll reads the skin, not the stand-in")

	DotHumanoidFigure.stand_in_range = 0.0
	DotHumanoidFigure.stand_in_bakes_per_frame = 1
	DotHumanoidStandIn.clear()
	g.queue_free()
	other.queue_free()
	cam.queue_free()
	await suite.get_tree().process_frame


func _run(g: DotHumanoidFigure, frames: int) -> void:
	for i in frames:
		g.animate(4.0, DT)
