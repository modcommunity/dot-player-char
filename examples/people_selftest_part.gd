extends Node

## [code]people_selftest.gd[/code]'s counters, report lines, and its upload, break and action sections, split out to keep
## each file small.

var _passed := 0
var _failed := 0
var _section_count := 0


## A critical on a skinned person: a limb is baked out of the skin as a piece of its own, and its
## bones shrink to the stump; a respawn mends it.
func _test_break() -> void:
	_section("a skinned body comes apart")
	var world := Node3D.new()
	add_child(world)
	var f := DotHumanoidFigure.new()
	world.add_child(f)
	f.build(DotHumanoidLook.stock(77), 1.8)
	f.animate(0.0, 0.1)
	var rules := DotPlayerBreakRules.new()
	rules.mode = DotPlayerBreakRules.Mode.LIMBS
	rules.limbs = 1
	var skel := f.skeleton()
	var whole := _small_bones(skel)
	var broke := DotPlayerBodyBreak.break_apart(f, world, rules, f.global_position, Vector3.FORWARD, 42, true, true)
	_check(broke != null and broke.piece_count() == 1, "a limb comes off as one piece (%d)" % (broke.piece_count() if broke != null else -1))
	var piece_mesh: Mesh = null
	if broke != null and broke.piece_count() > 0:
		for child in broke.get_child(0).get_children():
			if child is MeshInstance3D:
				piece_mesh = (child as MeshInstance3D).mesh
	_check(piece_mesh != null and piece_mesh.get_faces().size() > 30 and piece_mesh.get_aabb().size.length() < 1.5,
		"baked from the skin: a mesh of its own, limb-sized, not the whole body")
	_check(_small_bones(skel) > whole, "and the limb's bones shrank to the stump")
	var again := DotPlayerBodyBreak.break_apart(f, world, rules, f.global_position, Vector3.FORWARD, 42, true, true)
	_check(again != null, "the same seed takes a limb again")
	f.mend()
	_check(_small_bones(skel) == whole, "a respawn puts every bone back")
	rules.mode = DotPlayerBreakRules.Mode.EXPLODE
	var all := DotPlayerBodyBreak.break_apart(f, world, rules, f.global_position, Vector3.FORWARD, 7, true, true)
	_check(all != null and all.piece_count() == 5, "explode: both arms, both legs and the head (%d)" % (all.piece_count() if all != null else -1))
	world.queue_free()
	await get_tree().process_frame


static func _small_bones(skel: Skeleton3D) -> int:
	var n := 0
	for i in skel.get_bone_count():
		if skel.get_bone_pose_scale(i).x < 0.01:
			n += 1
	return n


func _library_of(id: StringName) -> AnimationLibrary:
	var f := DotHumanoidFigure.new()
	add_child(f)
	f.build(DotHumanoidLook.make(id, Color.WHITE, Color.BLACK, Color.RED, Color.BLUE), 1.8)
	var out := (f.body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer).get_animation_library(&"")
	f.free()
	return out


static func _body_y(animation: Animation, time: float) -> float:
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_POSITION_3D \
				and String(animation.track_get_path(t).get_concatenated_subnames()) == "Body":
			return animation.position_track_interpolate(t, time).y
	return INF


func _test_actions() -> void:
	_section("avatar actions")
	var ids := ["wave", "point", "thumbs_up", "nod", "shrug", "cheer", "dance", "clap", "bow", "sit", "salute", "arms_crossed", "hands_on_hips"]
	for body in [&"matt", &"lis"]:
		var f := DotHumanoidFigure.new()
		add_child(f)
		f.build(DotHumanoidLook.make(body, Color.WHITE, Color.BLACK, Color.RED, Color.BLUE), 1.8)
		var all := true
		for id in ids:
			all = all and f.play_action(StringName(id), true)
			f.animate(0.0, 0.1)
		_check(all, "%s plays all %d starter actions" % [body, ids.size()])
		f.free()
	var f := DotHumanoidFigure.new()
	add_child(f)
	f.build(DotHumanoidLook.stock(3), 1.8)
	_check(not f.play_action(&"no_such_thing"), "an id with no clip plays nothing")
	var rest := f.skeleton().get_bone_pose_rotation(f.skeleton().find_bone("UpperArm.R"))
	f.play_action(&"cheer", true)
	for i in 8:
		f.animate(0.0, 0.1)
	var raised := f.skeleton().get_bone_pose_rotation(f.skeleton().find_bone("UpperArm.R"))
	_check(f.action == &"cheer" and rest.angle_to(raised) > 0.5, "a looping gesture holds and moves the arm (%.2f rad)" % rest.angle_to(raised))
	f.animate(2.0, 0.1)
	f.animate(2.0, 0.1)
	_check(f.action == &"cheer", "walking does not end a gesture")
	f.set_motion({"swimming": true})
	f.animate(2.0, 0.1)
	_check(f.action == &"", "swimming ends it")
	f.set_motion({})
	f.play_action(&"dance", true)
	f.animate(0.0, 0.1)
	_check(f.clip == DotHumanoidActions.clip_name(&"dance"), "dance takes the legs while standing")
	f.animate(4.0, 0.1)
	_check(f.action == &"" and f.clip != DotHumanoidActions.clip_name(&"dance"), "and gives them back on the move")
	f.play_action(&"bow", false, 99.0)
	_check(f.action == &"", "a one-shot that began long ago is already over")
	f.swing()
	f.play_action(&"wave", false)
	_check(f.overlay == DotHumanoidClips.WAVE, "a later action replaces a swing")
	f.free()
	var anim := Animation.new()
	var t := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t, NodePath("Rig/Skeleton3D:mixamorig_Spine"))
	var _k := anim.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
	var t2 := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t2, NodePath("Rig/Skeleton3D:Unmapped"))
	var _k2 := anim.rotation_track_insert_key(t2, 0.0, Quaternion.IDENTITY)
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	map.set_skeleton_bone_name(&"Spine", &"mixamorig_Spine")
	var renamed := DotHumanoidActions.rename_humanoid(anim, map, {"mixamorig_Spine": Transform3D.IDENTITY})
	var out: Animation = renamed["animation"]
	_check(out.get_track_count() == 1 and String(out.track_get_path(0)).ends_with(":Abdomen") and renamed["rests"].has("Abdomen"),
		"an uploaded humanoid clip is renamed onto the kit's bones, unmapped bones dropped")
	_test_upload()


## An uploaded clip's scene, as the content cache builds it: Mixamo bone names, its own skeleton path.
func _test_upload() -> void:
	_check(DotHumanoidActions.profile_bone_of("mixamorig_LeftForeArm") == "LeftLowerArm"
		and DotHumanoidActions.profile_bone_of("thigh_R") == "RightUpperLeg"
		and DotHumanoidActions.profile_bone_of("upper_arm.L") == "LeftUpperArm"
		and DotHumanoidActions.profile_bone_of("mixamorig:Hips") == "Hips"
		and DotHumanoidActions.profile_bone_of("LeftHandIndex1") == "",
		"source bone names are guessed onto the humanoid profile, unknown ones left out")
	var scene := Node3D.new()
	var skel := Skeleton3D.new()
	skel.name = "Skel"
	var arm := Node3D.new()
	arm.name = "Armature"
	scene.add_child(arm)
	arm.add_child(skel)
	var bones := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Neck", "mixamorig_Head", "mixamorig_RightArm", "mixamorig_RightForeArm"]
	for b in bones:
		var _i := skel.add_bone(b)
	var player := AnimationPlayer.new()
	scene.add_child(player)
	var anim := Animation.new()
	anim.length = 1.0
	var raise := Quaternion(Vector3.FORWARD, 2.0)
	for b in bones:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("Armature/Skel:%s" % b))
		var _a := anim.rotation_track_insert_key(t, 0.0, raise if b == "mixamorig_RightArm" else Quaternion.IDENTITY)
		var _b := anim.rotation_track_insert_key(t, 1.0, raise if b == "mixamorig_RightArm" else Quaternion.IDENTITY)
	var lib := AnimationLibrary.new()
	var _l := lib.add_animation(&"Take", anim)
	var _p := player.add_animation_library(&"", lib)
	var f := DotHumanoidFigure.new()
	add_child(f)
	f.build(DotHumanoidLook.stock(2), 1.8)
	var id := &"action/12/3"
	_check(not DotHumanoidActions.clip_name(id).contains("/"), "a content id makes a clip name without a slash")
	_check(not f.add_action_scene(id, scene, "Missing").ok, "an upload without the named clip is refused")
	var added := f.add_action_scene(id, scene, "Take", true)
	_check(added.ok and added.value == true, "an uploaded clip is added to the body (%s)" % (added.error.message if not added.ok else "ok"))
	var rest := f.skeleton().get_bone_pose_rotation(f.skeleton().find_bone("UpperArm.R"))
	var plays := f.play_action(id, true)
	for i in 6:
		f.animate(0.0, 0.1)
	var moved := f.skeleton().get_bone_pose_rotation(f.skeleton().find_bone("UpperArm.R"))
	_check(plays and rest.angle_to(moved) > 0.3, "and plays on the kit's arm (%.2f rad)" % rest.angle_to(moved))
	f.free()
	scene.free()


func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
