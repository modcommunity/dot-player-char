extends Node

## Exercises the family's people: the look, the clip set on every body, and the figure choosing clips
## from how it moves. What a person LOOKS like is `tools/people_sheet.gd`'s contact sheets.
## godot --headless --path . res://examples/people_selftest.tscn

const SECTIONS := 20
const CHECKS := 200

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-player-char people self-test")
	_test_look()
	_test_site()
	_test_clips()
	await _test_figure()
	_test_zombie_gait()
	await _test_hand_and_aim()
	_test_actions()
	_test_materials()
	await _test_prepared_libraries()
	_test_arm_swatches()
	await _test_break()
	_test_unimported()
	await DotPeopleViewChecks.new(self).run()
	await DotPeopleLegsChecks.new(self).run()
	var held := DotPeopleHeldChecks.new(self)
	await held.run_arms()
	await held.run_arms_dress()
	await held.run_gun_steady()
	await held.run_full_body_action()
	await held.run_pose_record()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return
	if _passed + _failed != CHECKS:
		_line("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


## A body the project never imported still loads. user:// is never imported, so a copy of a body
## there is a .glb with no imported scene: the state of a project run straight after a pull.
func _test_unimported() -> void:
	_section("a body that was never imported")
	var source := DotHumanoidFigure.body_path(&"lis")
	var copy := "user://people_selftest_unimported.glb"
	var file := FileAccess.open(copy, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(source))
	file.close()
	_check(not ResourceLoader.exists(copy), "the copy has no import")
	var imported := (load(source) as PackedScene).instantiate()
	var loaded := DotHumanoidFigure.load_model(copy)
	var read := loaded.instantiate() if loaded != null else null
	var bones := func(root: Node) -> int:
		var found := root.find_children("*", "Skeleton3D", true, false) if root != null else []
		return (found.front() as Skeleton3D).get_bone_count() if not found.is_empty() else -1
	_check(read != null and bones.call(read) == bones.call(imported) and bones.call(read) > 0,
		"read from the file: the importer's skeleton (%d bones)" % bones.call(read))
	var atlas := DotHumanoidFigure.load_texture("user://nothing_here.png")
	_check(atlas == null and DotHumanoidFigure.load_model("user://nothing_here.glb") == null, "and a file that is not there is nothing")
	imported.free()
	if read != null:
		read.free()
	DirAccess.remove_absolute(copy)


func _test_look() -> void:
	_section("a look")
	var a := DotHumanoidLook.stock(42)
	var b := DotHumanoidLook.stock(42)
	_check(a.key() == b.key(), "the same seed dresses the same person")
	var keys := {}
	var bodies := {}
	for i in range(40):
		var l := DotHumanoidLook.stock(i * 7919)
		keys[l.key()] = true
		bodies[l.body] = true
	_check(keys.size() >= 35 and bodies.size() == 4, "forty seeds: %d looks on %d bodies" % [keys.size(), bodies.size()])
	var round := DotHumanoidLook.from_dict(a.to_dict())
	_check(round != null and round.key() == a.key(), "a look survives a dictionary")
	_check(DotHumanoidLook.from_dict({"skin": "zz"}) == null, "a dictionary that is not a look is refused")
	var odd := DotHumanoidLook.from_dict({"body": "retired", "skin": "ffffff", "hair": "000000", "top": "ff0000", "bottom": "0000ff"})
	_check(odd != null and odd.body == DotHumanoidLook.BODIES[0], "a retired body draws the first body, not nobody")
	var red := a.with_side(Color.RED, 1.0)
	_check(red.top == Color.RED and red.skin == a.skin and a.top != Color.RED, "a side's colour goes on the top of a copy")


func _test_site() -> void:
	_section("the site's avatar")
	var doc := _SiteDoc.new()
	doc.parts = {&"face": &"face.skin-b", &"top": &"top.skin-n", &"legs": &"legs.skin-q"}
	var look := DotHumanoidLook.from_site(doc)
	_check(look != null, "a builtin document becomes a look")
	_check(look.skin == Color(DotHumanoidLook.SITE_SKINS["b"][0]) and look.hair == Color(DotHumanoidLook.SITE_SKINS["b"][1]),
		"the face gives skin and hair")
	_check(look.top == Color(DotHumanoidLook.SITE_SKINS["n"][2]) and look.bottom == Color(DotHumanoidLook.SITE_SKINS["q"][3]),
		"the top and the legs give the clothes")
	var bare := _SiteDoc.new()
	bare.parts = {&"top": &"skin-k"}
	var only_top := DotHumanoidLook.from_site(bare)
	_check(only_top != null and only_top.top == Color(DotHumanoidLook.SITE_SKINS["k"][2]) and only_top.bottom == Color(DotHumanoidLook.SITE_SKINS["k"][3]),
		"a bare part id is read, and one slot dresses the rest")
	var other := _SiteDoc.new()
	other.schema_id = &"zz_people"
	other.parts = doc.parts
	_check(DotHumanoidLook.from_site(other) == null and DotHumanoidLook.from_site(null) == null, "another schema, or nothing, is no look")
	var junk := _SiteDoc.new()
	junk.parts = {&"top": &"top.hat-3"}
	_check(DotHumanoidLook.from_site(junk) == null, "a part this table does not know is no look")
	var kit := DotHumanoidLook.from_letter("res://assets/kenney/characters/Textures/texture-k.png")
	_check(kit != null and kit.top == Color(DotHumanoidLook.SITE_SKINS["k"][2]) and DotHumanoidLook.from_letter("k").key() == kit.key(),
		"a blocky atlas path or its letter is that skin's person")
	_check(DotHumanoidLook.from_letter("texture-z.png") == null and DotHumanoidLook.from_letter("") == null, "and nothing else is")


func _test_clips() -> void:
	_section("the clip set on every body")
	var everywhere := true
	var missing := []
	var libraries := {}
	for id in DotHumanoidLook.BODIES:
		var f := DotHumanoidFigure.new()
		add_child(f)
		f.build(DotHumanoidLook.make(id, Color.WHITE, Color.BLACK, Color.RED, Color.BLUE), 1.8)
		var player := f.body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer
		libraries[id] = player.get_animation_library(&"")
		for clip in DotHumanoidClips.ALL:
			if not player.has_animation(clip):
				everywhere = false
				missing.append("%s/%s" % [id, clip])
		f.free()
	_check(everywhere, "all %d clips on all four bodies %s" % [DotHumanoidClips.ALL.size(), str(missing)])
	var matt: AnimationLibrary = libraries[&"matt"]
	_check(matt.get_animation(DotHumanoidClips.WALK).loop_mode == Animation.LOOP_LINEAR
		and matt.get_animation(DotHumanoidClips.DEATH).loop_mode == Animation.LOOP_NONE, "walks loop, a death does not")
	_check(libraries[&"lis"] != matt and libraries[&"sam"] != matt, "the other bodies play a retargeted copy, not the clip body's own")
	_check(libraries[&"lis"] == _library_of(&"lis"), "and that copy is made once per body and shared")

	var idle := matt.get_animation(DotHumanoidClips.IDLE)
	var crouch := matt.get_animation(DotHumanoidClips.CROUCH)
	_check(_body_y(crouch, 0.0) < _body_y(idle, 0.0) - 0.05, "the made crouch is lower than standing (%.2f against %.2f)" % [_body_y(crouch, 0.0), _body_y(idle, 0.0)])
	var highest := -INF
	var fall := matt.get_animation(DotHumanoidClips.FALL)
	for i in range(11):
		highest = maxf(highest, _body_y(fall, fall.length * i / 10.0))
	_check(highest <= _body_y(idle, 0.0) + 0.001, "the fall does not lift the body above standing: the game lifts it")
	_check(matt.has_animation(DotHumanoidClips.SLIDE), "the real slide clip is on the clip body")
	var slider := DotHumanoidFigure.new()
	add_child(slider)
	slider.build(DotHumanoidLook.stock(1), 1.8)
	for i in range(30):
		slider.set_motion({"on_floor": true, "alive": true, "crouched": true, "sliding": true, "velocity": Vector3(0, 0, -6)})
		slider.animate(6.0, 1.0 / 30.0)
	_check(slider.clip == DotHumanoidClips.SLIDE, "a sliding motion plays the slide (%s)" % slider.clip)
	for i in range(15):
		slider.set_motion({"on_floor": false, "alive": true, "sliding": true, "vertical": -3.0, "velocity": Vector3(0, -3, -6)})
		slider.animate(6.0, 1.0 / 30.0)
	_check(slider.clip != DotHumanoidClips.SLIDE, "a slide in the air is a fall, not a slide (%s)" % slider.clip)
	slider.free()


func _test_zombie_gait() -> void:
	_section("the zombie gait")
	var f := DotHumanoidFigure.new()
	add_child(f)
	f.build(DotHumanoidLook.stock(9), 1.8)
	f.zombie_gait = true
	f.animate(0.0, 0.1)
	_check(f.clip == DotHumanoidClips.ZOMBIE_IDLE, "standing: the zombie idle (%s)" % f.clip)
	f.animate(1.3, 0.1)
	_check(f.clip == DotHumanoidClips.ZOMBIE_WALK, "walking: the zombie walk (%s)" % f.clip)
	_check(f._anim.get_animation(DotHumanoidClips.ZOMBIE_WALK).loop_mode == Animation.LOOP_LINEAR, "and it loops")
	f.animate(5.0, 0.1)
	_check(f.clip == DotHumanoidClips.SPRINT, "running: the real sprint (%s)" % f.clip)
	f.zombie_gait = false
	f.animate(1.5, 0.1)
	_check(f.clip == DotHumanoidClips.WALK, "off again, the person's own walk (%s)" % f.clip)
	f.free()


func _test_figure() -> void:
	_section("a figure picks its clip")
	var f := DotHumanoidFigure.new()
	add_child(f)
	f.build(DotHumanoidLook.stock(9), 1.8)
	_check(f.from_art and f.skeleton() != null and f.mesh() != null, "the body loaded: a skeleton and one mesh")
	var head := f.skeleton().find_bone("Head")
	var top_y := (f.skeleton().global_transform * f.skeleton().get_bone_global_pose(head)).origin.y
	_check(top_y > 0.8 and top_y < 1.6, "built to the height asked for (head bone at %.2f m of 1.8)" % top_y)

	f.animate(0.0, 0.1)
	_check(f.clip == DotHumanoidClips.IDLE, "standing: idle")
	f.animate(1.5, 0.1)
	_check(f.clip == DotHumanoidClips.WALK, "walking: walk")
	f.animate(5.0, 0.1)
	_check(f.clip == DotHumanoidClips.RUN, "running: run")
	f.animate(6.0, 0.1)
	_check(f.clip == DotHumanoidClips.SPRINT, "above the run clip's pace: the grounded sprint clip, not a hovering run")
	f.set_hold(DotHumanoidFigure.Hold.GUN)
	f.animate(4.0, 0.1)
	_check(f.clip == DotHumanoidClips.RUN_GUN, "running with a gun: the gun run")
	for _i in 5:
		f.animate(6.0, 0.1)
	_check(f.sprint_blend > 0.99, "a game that never sends `sprinting` still carries the gun sprinting when it runs (%.2f)" % f.sprint_blend)
	f.set_motion({"sprinting": false})
	for _i in 5:
		f.animate(6.0, 0.1)
	_check(f.sprint_blend < 0.01, "an explicit sprinting=false wins over the run state (%.2f)" % f.sprint_blend)
	_check(f.clip == DotHumanoidClips.SPRINT, "sprinting=false does not bring the hovering run clip back above its pace (%s)" % f.clip)
	var hold_anim: Animation = f._anim.get_animation(DotHumanoidClips.IDLE_GUN)
	var track := hold_anim.find_track(NodePath("%s:LowerArm.L" % f._model.get_path_to(f.skeleton())), Animation.TYPE_ROTATION_3D)
	var arm_now := f.skeleton().get_bone_pose_rotation(f.skeleton().find_bone("LowerArm.L"))
	_check(rad_to_deg(arm_now.angle_to(hold_anim.rotation_track_interpolate(track, 0.0))) < 8.0, "a gun held at sprint pace keeps its arms on the gun (the idle-gun overlay)")
	f.animate(4.5, 0.1)
	_check(f.clip == DotHumanoidClips.RUN_GUN, "sprinting=false below the run clip's pace: the gun run (%s)" % f.clip)
	f.set_motion({"crouched": true})
	f.animate(0.0, 0.1)
	_check(f.clip == DotHumanoidClips.CROUCH, "crouched: the crouch")
	f.animate(1.5, 0.1)
	_check(f.clip == DotHumanoidClips.CROUCH_WALK, "crouched and moving: the crouch walk")
	f.set_motion({"on_floor": false, "vertical": 4.0})
	f.animate(1.0, 0.2)
	_check(f.clip == DotHumanoidClips.JUMP, "rising: the jump")
	f.set_motion({"on_floor": false, "vertical": -4.0})
	f.animate(1.0, 0.2)
	_check(f.clip == DotHumanoidClips.FALL, "dropping: the fall")
	f.set_motion({"downed": true})
	f.animate(0.5, 0.1)
	_check(f.clip == DotHumanoidClips.CRAWL, "down: crawling")
	f.set_motion({"swimming": true})
	f.animate(2.0, 0.1)
	_check(f.state == DotPlayerAnimState.SWIM and f.clip == DotHumanoidClips.SWIM, "swimming: the made front crawl, not the run")
	_check_swim_stroke(f)
	f.set_motion({"alive": false})
	f.animate(0.0, 0.1)
	_check(f.clip == DotHumanoidClips.DEATH, "dead: the death")

	f.set_motion({})
	f.set_hold(DotHumanoidFigure.Hold.MELEE)
	f.animate(5.0, 0.1)
	f.swing()
	_check(f.overlay == DotHumanoidClips.SLASH and f.clip == DotHumanoidClips.RUN, "a swing plays over the run: the legs keep running")
	for i in range(20):
		f.animate(6.0, 0.1)
	_check(f.overlay == &"", "and ends")

	_check_planted_foot(2.0, DotHumanoidClips.WALK, "a walker's")
	_check_sprint_pop(9.0)
	_check_handover_slide(7.0)
	_check_handover_slide(7.5)
	await _test_figure_mounts(f)


## Through one swim cycle each hand is over its shoulder and under it, in the clip's own upright frame.
func _check_swim_stroke(f: DotHumanoidFigure) -> void:
	var sk := f.skeleton()
	var hand_l := sk.find_bone("Middle1.L") if sk != null else -1
	var shoulder_l := sk.find_bone("UpperArm.L") if sk != null else -1
	var over := false
	var under := false
	for i in 8:
		f.animate(2.5, DotHumanoidClips.SWIM_CYCLE / 8.0)
		if hand_l < 0 or shoulder_l < 0:
			break
		sk.force_update_all_bone_transforms()
		var rise := sk.get_bone_global_pose(hand_l).origin.y - sk.get_bone_global_pose(shoulder_l).origin.y
		over = over or rise > 0.1
		under = under or rise < -0.1
	_check(over and under, "and the arm goes round: the hand over the shoulder and under it in one stroke")


## A sprinter sampled at 15 fps, as the filmstrip captures, keeps every bone under the pop limit.
func _check_sprint_pop(pace: float) -> void:
	var g := DotHumanoidFigure.new()
	add_child(g)
	g.build(DotHumanoidLook.stock(9), 1.8)
	g.set_run_speeds(6.84, 6.04)
	g.sprint_speed = 6.0
	var m := DotClipMetrics.new()
	var dt := 1.0 / 15.0
	var v := 0.0
	for i in 42:
		v = minf(pace, v + pace / 0.3 * dt)
		g.position.z -= v * dt
		g.animate(v, dt)
		g.skeleton().force_update_all_bone_transforms()
		m.add(m.pose_sample(i * dt, g.skeleton(), g.global_position, true))
	var pop := 999.0
	for r in m.evaluate({"pop_deg": 135.0}):
		if r["check"] == "bone_pop":
			pop = float(r["value"])
	_check(g.clip == DotHumanoidClips.SPRINT and pop < 135.0, "a sprinter at %.0f m/s keeps bone pop under 135 degrees at 15 fps (clip %s, %.1f)" % [pace, g.clip, pop])
	g.queue_free()


## Through the walk-to-sprint hand-over (60 fps ramp) the foot on the ground stays within 8 cm of where it was: the incoming clip enters at the outgoing pose.
func _check_handover_slide(pace: float) -> void:
	var g := DotHumanoidFigure.new()
	add_child(g)
	g.build(DotHumanoidLook.stock(9), 1.8)
	g.set_run_speeds(6.84, 6.04)
	g.sprint_speed = 6.0
	var sk := g.skeleton()
	var feet := [sk.find_bone("Foot.L"), sk.find_bone("Foot.R")]
	var dt := 1.0 / 60.0
	var v := 0.0
	var before: Array = []
	var worst := 0.0
	var switched := -99
	var last: StringName = &""
	for i in 60:
		v = minf(pace, v + pace / 0.3 * dt)
		g.position.z -= v * dt
		g.animate(v, dt)
		sk.force_update_all_bone_transforms()
		var at: Array = feet.map(func(b: int) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(b).origin)
		if g.clip != last:
			if last == DotHumanoidClips.WALK:
				switched = i
			last = g.clip
		if not before.is_empty() and i == switched:
			for k in 2:
				if before[k].y < 0.06:
					# Along the ground: a sprint's foot entered late in its short stance lifts off that frame, which is not a slide.
					var moved: Vector3 = at[k] - before[k]
					worst = maxf(worst, Vector2(moved.x, moved.z).length())
		before = at
	_check(g.clip == DotHumanoidClips.SPRINT and worst < 0.08, "a ramp to %.1f m/s: the foot on the ground moves under 8 cm over the hand-over frame (%.3f m)" % [pace, worst])
	g.queue_free()


## A walker carried forward at a steady pace keeps the foot it stands on still in the world.
func _check_planted_foot(pace: float, expect: StringName, who: String) -> void:
	var g := DotHumanoidFigure.new()
	add_child(g)
	g.build(DotHumanoidLook.stock(9), 1.8)
	var sk := g.skeleton()
	var feet := [sk.find_bone("Foot.L"), sk.find_bone("Foot.R")]
	var dt := 1.0 / 60.0
	var ground := INF
	var start: Array = []
	var worst := 0.0
	var stances := 0
	for i in 150:
		g.position.z -= pace * dt
		g.animate(pace, dt)
		sk.force_update_all_bone_transforms()
		var at: Array = feet.map(func(b: int) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(b).origin)
		var k := 0 if at[0].y < at[1].y else 1
		ground = minf(ground, at[k].y)
		if i < 30 or at[k].y > ground + 0.02 or (not start.is_empty() and start[0] != k):
			start.clear()
			continue
		if start.is_empty():
			start = [k, at[k], i]
		elif (i - int(start[2])) * dt >= 0.1:
			var moved: Vector3 = at[k] - start[1]
			worst = maxf(worst, Vector2(moved.x, moved.z).length() / ((i - int(start[2])) * dt))
			stances += 1
	_check(g.clip == expect and stances > 10 and worst < 0.25, "%s planted foot stays put (clip %s): %.2f m/s at most over %d windows of 0.1 s or more" % [who, g.clip, worst, stances])
	g.queue_free()


## Mounts, the frame step and a carried figure animating itself; frees [param f].
func _test_figure_mounts(f: DotHumanoidFigure) -> void:
	var hand := f.attachment(&"right_hand")
	_check(hand != null and hand.get_parent() is BoneAttachment3D and f.attachment(&"right_hand") == hand,
		"a weapon hangs from a bone attachment in the hand, made once")
	_check(f.attachment(&"left_foot") == null, "no other mount")
	_check(f.anim_step == 1, "with no camera, the clip advances every frame")
	var walker := DotHumanoidFigure.new()
	add_child(walker)
	walker.build(DotHumanoidLook.stock(4), 1.8)
	walker.auto_animate = true
	for i in 12:
		walker.position.x += 0.05
		await get_tree().process_frame
	_check(walker.clip in [DotHumanoidClips.WALK, DotHumanoidClips.RUN, DotHumanoidClips.SPRINT],
		"a figure carried by something else animates from how far it moved (%s)" % walker.clip)
	walker.free()
	f.free()
	await get_tree().process_frame


## The right hand holds the gun (the kit's clips are mirrored), the upper body follows the view's
## pitch without the bend adding up, a rider sits, a climber climbs, and a crest rides the crown.
func _test_hand_and_aim() -> void:
	_section("the right hand, aiming, sitting, climbing, the crown")
	var raw := DotHumanoidClips.library_of(load(DotHumanoidFigure.body_path(DotHumanoidFigure.CLIP_BODY)) as PackedScene)
	var mirrored := _library_of(DotHumanoidFigure.CLIP_BODY)
	var gun_raw := raw.get_animation(DotHumanoidClips.IDLE_GUN)
	var gun := mirrored.get_animation(DotHumanoidClips.IDLE_GUN)
	var left := gun_raw.find_track(NodePath("CharacterArmature/Skeleton3D:UpperArm.L"), Animation.TYPE_ROTATION_3D)
	var right := gun.find_track(NodePath("CharacterArmature/Skeleton3D:UpperArm.R"), Animation.TYPE_ROTATION_3D)
	var a: Quaternion = gun_raw.rotation_track_interpolate(left, 0.0) if left >= 0 else Quaternion()
	var b: Quaternion = gun.rotation_track_interpolate(right, 0.0) if right >= 0 else Quaternion.IDENTITY
	_check(left >= 0 and right >= 0 and Quaternion(a.x, -a.y, -a.z, a.w).is_equal_approx(b),
		"the kit's left gun arm is the figure's right, reflected across the middle")

	var world := Node3D.new()
	add_child(world)
	var f := DotHumanoidFigure.new()
	world.add_child(f)
	f.build(DotHumanoidLook.stock(21), 1.8)
	f.set_hold(DotHumanoidFigure.Hold.GUN)
	var hand := f.attachment(&"right_hand")
	_check((hand.get_parent() as BoneAttachment3D).bone_name.ends_with(".R"), "the weapon hangs from the right hand's bone")
	var heights := {}
	var abdomen := f.skeleton().find_bone("Abdomen")
	var steady := true
	for pitch: float in [0.0, 0.6, -0.6]:
		f.aim(pitch)
		var last := Quaternion.IDENTITY
		for i in 3:
			f.animate(0.0, 0.1)
			await get_tree().process_frame
			var now := f.skeleton().get_bone_pose_rotation(abdomen)
			if i == 2 and not now.is_equal_approx(last):
				steady = false
			last = now
		heights[pitch] = f.to_local(hand.global_position)
	var level: Vector3 = heights[0.0]
	_check(level.x > 0.05, "standing with a gun, the hand is right of centre (x %.2f)" % level.x)
	_check(heights[0.6].y > level.y + 0.1 and heights[-0.6].y < level.y - 0.1,
		"aiming up raises the gun hand, aiming down lowers it (%.2f / %.2f / %.2f)" % [heights[-0.6].y, level.y, heights[0.6].y])
	_check(steady, "the bend is put on the clip's pose each frame, not added to last frame's")
	f.aim(INF)
	_check(f.aim_pitch == 0.0, "a pitch that is not a number is level")
	f.set_motion({"aim": 0.4})
	f.set_motion({"crouched": true})
	_check(is_equal_approx(f.aim_pitch, 0.4), "the motion's `aim` sets it, and a motion without one leaves it")

	world.scale = Vector3.ZERO
	f.aim(0.5)
	f.animate(0.0, 0.1)
	await get_tree().process_frame
	var after := f.skeleton().get_bone_pose_rotation(abdomen)
	world.scale = Vector3.ONE
	_check(after.is_finite() and absf(after.length() - 1.0) < 0.01, "a figure scaled to nothing aims without an error and keeps a unit pose")

	await _check_seat_climb_crown(world, f)


## Seated, climbing and the crown mount on the figure the aim checks used.
func _check_seat_climb_crown(world: Node3D, f: DotHumanoidFigure) -> void:
	f.aim(0.0)
	f.set_motion({"seated": true})
	f.animate(3.0, 0.1)
	_check(f.clip == DotHumanoidClips.SIT, "seated, even carried at speed: sitting")
	var seat := f.seat_height()
	_check(seat > 0.2 and seat < 0.5, "the hips sit at knee height (%.2f m of 1.8: short cartoon legs)" % seat)
	var real := load(DotHumanoidFigure.real_clips_path()) as AnimationLibrary
	var player := f.body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(real != null and real.has_animation(DotHumanoidClips.SIT) and player.has_animation(DotHumanoidClips.SIT) \
		and is_equal_approx(player.get_animation(DotHumanoidClips.SIT).length, real.get_animation(DotHumanoidClips.SIT).length),
		"the sit is the library's seated idle, not the made pose")
	# Past the 0.15 s blend in from the last clip.
	f.animate(3.0, 0.5)
	var sk := f.skeleton()
	sk.force_update_all_bone_transforms()
	var hips := sk.get_bone_global_pose(sk.find_bone("UpperLeg.L")).origin.y
	var feet := minf(sk.get_bone_global_pose(sk.find_bone("Foot.L")).origin.y, sk.get_bone_global_pose(sk.find_bone("Foot.R")).origin.y)
	var stood := minf(sk.get_bone_global_rest(sk.find_bone("Foot.L")).origin.y, sk.get_bone_global_rest(sk.find_bone("Foot.R")).origin.y)
	_check(absf(feet - stood) < 0.01 and hips - feet < 0.6 * (sk.get_bone_global_rest(sk.find_bone("UpperLeg.L")).origin.y - stood),
		"and its feet are on the floor (%.3f from where they stand), the hips down at the knees" % (feet - stood))
	f.set_motion({"climbing": true, "vertical": 2.0})
	f.animate(0.0, 0.1)
	_check(f.clip == DotHumanoidClips.CLIMB, "on a ladder: climbing, not the crawl")

	var crest := f.attachment(&"crest")
	_check(crest != null and f.attachment(&"hat") == crest and crest.get_parent() is BoneAttachment3D,
		"a crest and a hat share one mount, on the head bone")
	f.set_motion({})
	f.animate(0.0, 0.1)
	await get_tree().process_frame
	var top := f.to_local(crest.global_position).y
	_check(top > 1.5 and top < 2.0, "on the crown (%.2f m of 1.8)" % top)
	world.queue_free()
	await get_tree().process_frame


func _test_materials() -> void:
	_section("one material per look")
	var before := DotHumanoidFigure.material_count()
	var look := DotHumanoidLook.stock(1234)
	var m1 := DotHumanoidFigure.material_for(look)
	var m2 := DotHumanoidFigure.material_for(look.copy())
	_check(m1 == m2, "two people dressed alike share a material")
	_check(DotHumanoidFigure.material_count() == before + 1, "and it was made once")
	var expected := 0
	for hexes: Array in DotHumanoidAssets.WEARS[look.body].values():
		expected += hexes.size()
	_check(int(m1.get_shader_parameter(&"swaps")) == mini(expected, DotHumanoidAssets.SWAPS), "every mapped swatch of the body is swapped (%d)" % int(m1.get_shader_parameter(&"swaps")))
	var paths := DotHumanoidFigure.content_paths()
	_check(paths.size() == 6 and Array(paths).all(func(p: String) -> bool: return ResourceLoader.exists(p)), "every file a figure loads is listed, and exists")
	DotHumanoidFigure.clear_cache()
	_check(DotHumanoidFigure.material_count() == 0, "clear_cache() empties the shared materials")
	DotHumanoidFigure.material_for(look)
	_check(DotHumanoidFigure.material_count() == 1, "and a material refills it")

## The clip sets built off the frame (prepare_libraries) are the ones library_for builds in one.
func _test_prepared_libraries() -> void:
	_section("clip sets prepared off the frame")
	var other := &"lis"
	var model := DotHumanoidAssets.scene(DotHumanoidAssets.body_path(other))
	var probe := model.instantiate()
	var skeleton := probe.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	DotHumanoidAssets.clear_cache()
	var sync_base := DotHumanoidAssets.library_for(DotHumanoidAssets.CLIP_BODY, null)
	var sync_other := DotHumanoidAssets.library_for(other, skeleton)
	var sync_sit := DotHumanoidAssets.sit_height()
	DotHumanoidAssets.clear_cache()
	_check(DotHumanoidAssets.poll_libraries(), "nothing prepared: nothing to wait for")
	DotHumanoidAssets.prepare_libraries([other])
	var frames := 0
	while not DotHumanoidAssets.poll_libraries() and frames < 1200:
		frames += 1
		await get_tree().process_frame
	_check(frames < 1200, "the prepared build finishes (%d frames)" % frames)
	var base := DotHumanoidAssets.library_for(DotHumanoidAssets.CLIP_BODY, null)
	_check(base != null and base.get_animation_list() == sync_base.get_animation_list(), "the prepared shared set has the same clips")
	_check(is_equal_approx(DotHumanoidAssets.sit_height(), sync_sit), "and the same sit height")
	var prepared_other := DotHumanoidAssets.library_for(other, skeleton)
	_check(_first_key(prepared_other, DotHumanoidClips.IDLE).is_equal_approx(_first_key(sync_other, DotHumanoidClips.IDLE)), "the prepared retarget is the one library_for makes")
	DotHumanoidAssets.clear_cache()
	DotHumanoidAssets.prepare_libraries([other])
	_check(DotHumanoidAssets.library_for(DotHumanoidAssets.CLIP_BODY, null).get_animation_list() == sync_base.get_animation_list(), "library_for during a prepared build answers at once, the same")
	DotHumanoidAssets.clear_cache()
	frames = 0
	while not DotHumanoidAssets.poll_libraries() and frames < 1200:
		frames += 1
		await get_tree().process_frame
	_check(frames < 1200 and DotHumanoidAssets.poll_libraries(), "a build cleared mid-way still ends (%d frames)" % frames)
	DotHumanoidAssets.prepare_libraries([other])
	while not DotHumanoidAssets.poll_libraries() and frames < 2400:
		frames += 1
		await get_tree().process_frame
	_check(DotHumanoidAssets.library_for(other, skeleton) == DotHumanoidAssets.library_for(other, skeleton) and frames < 2400, "and a fresh one after it builds")
	DotHumanoidAssets.clear_cache()
	probe.free()


static func _first_key(library: AnimationLibrary, clip: StringName) -> Quaternion:
	var animation := library.get_animation(clip)
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_ROTATION_3D and animation.track_get_key_count(t) > 0:
			return animation.track_get_key_value(t, 0)
	return Quaternion()


## An arm or hand painted a colour no WEARS role covers keeps its painted colour whatever the
## person wears: brown forearms, white fingers. Dark neutrals (shadows, cuffs) may stay.
func _test_arm_swatches() -> void:
	_section("no unmapped arm or hand swatch")
	var image := (load("res://addons/dot_player_char/people/atlas_people.png") as Texture2D).get_image()
	var neutral := ["2a2927", "2a2929", "141414"]
	for id: StringName in [&"matt", &"lis", &"sam", &"shaun"]:
		var mapped := []
		for hexes: Array in DotHumanoidAssets.WEARS[id].values():
			mapped.append_array(hexes)
		var model := (load("res://addons/dot_player_char/people/people_%s.glb" % id) as PackedScene).instantiate()
		var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false).front()
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false).front()
		var arrays := mesh.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / uvs.size()
		var total := 0
		var loose := {}
		for i in uvs.size():
			var best := 0
			for k in per:
				if weights[i * per + k] > weights[i * per + best]:
					best = k
			var bind := bones[i * per + best]
			var bone_name := String(mesh.skin.get_bind_name(bind)) if mesh.skin != null and mesh.skin.get_bind_name(bind) != &"" else skeleton.get_bone_name(bind)
			if not ["Shoulder", "UpperArm", "LowerArm", "Pinky", "Middle", "Index", "Thumb", "Fist"].any(func(r: String) -> bool: return bone_name.contains(r)):
				continue
			total += 1
			var hex := image.get_pixel(clampi(int(uvs[i].x * image.get_width()), 0, image.get_width() - 1), clampi(int(uvs[i].y * image.get_height()), 0, image.get_height() - 1)).to_html(false)
			if not mapped.has(hex) and not neutral.has(hex):
				loose[hex] = int(loose.get(hex, 0)) + 1
		model.free()
		var worst := 0
		for hex: String in loose:
			worst = maxi(worst, int(loose[hex]))
		_check(total > 0 and worst * 100 <= total * 3, "%s: arm and hand swatches all mapped (%s)" % [id, loose])


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


class _SiteDoc:
	extends RefCounted
	var schema_id: StringName = &"builtin"
	var parts: Dictionary = {}

	func part_in(slot: StringName) -> StringName:
		return StringName(str(parts.get(slot, "")))


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
