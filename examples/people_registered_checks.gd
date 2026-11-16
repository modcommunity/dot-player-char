extends RefCounted

## The suite's registered-body section ([method DotHumanoidAssets.register_body]): a game's own body on the kit rig,
## read from outside the project, swapping LOD0..LOD2 by distance and tinted by the look's top. The body here is a
## stock one re-exported with three detail meshes, so no private art is needed. Reports through the suite's `_check`.

const ID := &"selftest_avatar"
const PATH := "user://people_selftest_registered.glb"

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("a registered body")
	suite._check(not DotHumanoidAssets.register_body(ID, "user://nothing_here.glb") and not DotHumanoidAssets.register_body(&"matt", PATH),
		"a missing file or a stock id is refused")
	suite._check(_write_body(), "a stock body re-exported as LOD0..LOD2")
	suite._check(DotHumanoidAssets.register_body(ID, PATH) and DotHumanoidLook.is_body(ID), "registered from outside the project")
	var look := DotHumanoidLook.make(ID, Color("c58a62"), Color("3b2a20"), Color("2050c0"), Color("2f3a4f"))
	var kept := DotHumanoidLook.from_dict(look.to_dict())
	suite._check(look.body == ID and kept != null and kept.body == ID, "a look keeps it, through a dictionary too")

	var f := DotHumanoidFigure.new()
	suite.add_child(f)
	f.build(look, 1.8)
	var meshes := f.find_children("*", "MeshInstance3D", true, false)
	suite._check(f.from_art and f.skeleton() != null and meshes.size() == 1 and f.mesh().name == "LOD0",
		"one mesh instance, the LOD0 (%d instances)" % meshes.size())
	var material := f.mesh().material_override as ShaderMaterial
	suite._check(material != null and material.get_shader_parameter(&"albedo_tex") != null
		and material.get_shader_parameter(&"tint") == look.top and is_equal_approx(material.get_shader_parameter(&"amount"), DotHumanoidAssets.team_tint),
		"its own texture, tinted by the top")
	var cousin := DotHumanoidLook.make(ID, Color("f1d2b6"), Color("8c8c8c"), look.top, Color("2a2f38"))
	suite._check(DotHumanoidAssets.material_for(cousin) == material, "one material per top, whatever the other colours")
	suite._check(DotViewArmsMaterial.for_look(look) == material, "the first-person arms wear the same one")

	var near := f.mesh().mesh
	f._pick_detail(DotHumanoidAssets.lod_distances[0] + 1.0)
	var mid := f.mesh().mesh
	f._pick_detail(DotHumanoidAssets.lod_distances[1] + 1.0)
	var far := f.mesh().mesh
	f._pick_detail(1.0)
	suite._check(near != mid and mid != far and f.mesh().mesh == near, "the mesh steps down by distance and back")

	var skeleton := f.skeleton()
	var hand := skeleton.find_bone("LowerArm.L")
	var before := skeleton.get_bone_pose_rotation(hand)
	f.pose(Vector3.ZERO, 0.0, 4.0)
	for i in 20:
		f.animate(4.0, 1.0 / 30.0)
		await suite.get_tree().process_frame
	suite._check(f.clip == DotHumanoidClips.RUN or f.clip == DotHumanoidClips.WALK, "it plays the family clips (%s)" % f.clip)
	suite._check(not skeleton.get_bone_pose_rotation(hand).is_equal_approx(before), "and its bones move")
	f.queue_free()

	suite._check(DotHumanoidAssets.register_body(ID, "") and not DotHumanoidLook.is_body(ID)
		and DotHumanoidLook.make(ID, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE).body == DotHumanoidLook.BODIES[0],
		"forgotten again, a look of it draws the first body")
	DirAccess.remove_absolute(PATH)


# Matt's body with its mesh renamed LOD0 and two copies beside it, as a game's prepared avatar is laid out.
func _write_body() -> bool:
	var root := (load(DotHumanoidAssets.body_path(&"matt")) as PackedScene).instantiate()
	var mesh := root.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
	mesh.name = "LOD0"
	# Named as another exporter would: the figure must find the clips' path anyway.
	var skeleton := root.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	skeleton.get_parent().name = "Armature"
	# A prepared avatar carries no clips (and the stock ones' paths no longer resolve after the rename).
	for player in root.find_children("*", "AnimationPlayer", true, false):
		player.free()
	for i in range(1, 3):
		var copy := mesh.duplicate() as MeshInstance3D
		copy.name = "LOD%d" % i
		copy.mesh = mesh.mesh.duplicate()
		mesh.get_parent().add_child(copy)
		copy.owner = root
	# A prepared avatar carries its painted texture on the mesh, where the stock bodies use the shared atlas.
	var image := DotHumanoidAssets.load_texture(DotHumanoidAssets.directory().path_join("atlas_people.png")).get_image()
	if image.is_compressed():
		var _plain := image.decompress()
	var painted := StandardMaterial3D.new()
	painted.albedo_texture = ImageTexture.create_from_image(image)
	mesh.mesh.surface_set_material(0, painted)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var ok := doc.append_from_scene(root, state) == OK and doc.write_to_filesystem(state, PATH) == OK
	root.free()
	return ok and _restore_bone_names()


# The exporter writes "LowerArm.L" as "LowerArm_L" (a node name may not hold a dot); a prepared avatar keeps the
# dot, so the JSON chunk gets it back. Same length, so the chunk sizes stand.
func _restore_bone_names() -> bool:
	var bytes := FileAccess.get_file_as_bytes(PATH)
	var size := bytes.decode_u32(12)
	var json := bytes.slice(20, 20 + size).get_string_from_utf8().replace("_L\"", ".L\"").replace("_R\"", ".R\"").to_utf8_buffer()
	if json.size() != size:
		return false
	for i in size:
		bytes[20 + i] = json[i]
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	return file.get_error() == OK
