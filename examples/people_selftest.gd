extends Node

## Exercises the family's people: the look (stock, the site's avatar, a side's colour), the clip
## set on every body (carried over by retargeting, the made crouch, the grounded air clips), and
## the figure choosing clips from how it moves, holding, swinging and sharing materials. What a
## person LOOKS like is not here: that is `tools/people_sheet.gd`'s contact sheets.
##
## [codeblock]
## godot --headless --path . res://examples/people_selftest.tscn
## [/codeblock]

const SECTIONS := 15
const CHECKS := 148

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
	await _test_hand_and_aim()
	_test_actions()
	_test_materials()
	await _test_break()
	_test_unimported()
	await DotPeopleViewChecks.new(self).run()
	await DotPeopleLegsChecks.new(self).run()
	await _test_held_arms()
	await _test_held_gun_steady()
	await _test_pose_record()

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
	_check(int(m1.get_shader_parameter(&"swaps")) == 4, "skin, hair, top and bottom are swapped (%d)" % int(m1.get_shader_parameter(&"swaps")))
	var paths := DotHumanoidFigure.content_paths()
	_check(paths.size() == 6 and Array(paths).all(func(p: String) -> bool: return ResourceLoader.exists(p)), "every file a figure loads is listed, and exists")
	DotHumanoidFigure.clear_cache()
	_check(DotHumanoidFigure.material_count() == 0, "clear_cache() empties the shared materials")
	DotHumanoidFigure.material_for(look)
	_check(DotHumanoidFigure.material_count() == 1, "and a material refills it")


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


func _test_held_arms() -> void:
	_section("your own arms holding a weapon")
	var arms := DotPlayerViewArms.new()
	add_child(arms)
	var weapon := Node3D.new()
	add_child(weapon)
	weapon.position = Vector3(0.08, -0.2, -0.4)
	arms.build(DotHumanoidLook.stock(3), 1.8)
	_check(not arms.arms().visible and not arms.describe()["held"], "off by default: nothing shown")
	var grip := Vector3(0.0, -0.08, 0.1)
	var fore := Vector3(-0.03, -0.07, -0.1)
	arms.set_held(DotViewGrip.two_hand(weapon, grip, fore))
	for i in 8:
		arms.tick(0.0, 1.0 / 30.0)
		await get_tree().process_frame
	var sk: Skeleton3D = (arms.arms() as DotHumanoidFigure).skeleton()
	_check(arms.arms().visible and arms.describe()["held"], "shown while a grip is set")
	var right := _bone_world(sk, "Middle1.R")
	_check(right.distance_to(_palm(arms, weapon.to_global(grip))) < 0.03, "the firing hand is palm_offset from the grip (%.3f m)" % right.distance_to(_palm(arms, weapon.to_global(grip))))
	_check(arms.palm_offset != Vector3.ZERO and right.distance_to(weapon.to_global(grip)) > 0.05, "by default the wrist is off the gun's centreline so the hand does not cover it (%.3f m)" % right.distance_to(weapon.to_global(grip)))
	var left := _bone_world(sk, "Middle1.L")
	_check(left.distance_to(_palm(arms, weapon.to_global(fore), true)) < 0.05, "the support hand reaches the foregrip (%.3f m)" % left.distance_to(_palm(arms, weapon.to_global(fore), true)))
	_check(sk.get_bone_pose_scale(sk.find_bone("Head")).x < 0.01 and sk.get_bone_pose_scale(sk.find_bone("UpperLeg.L")).x < 0.01, "head and legs are shrunk away")
	weapon.position += Vector3(0.1, 0.05, -0.05)
	for i in 3:
		arms.tick(0.0, 1.0 / 30.0)
	var moved := _bone_world(sk, "Middle1.R")
	_check(moved.distance_to(_palm(arms, weapon.to_global(grip))) < 0.03 and moved.distance_to(right) > 0.05, "the hand follows the weapon when it moves (%.3f m off)" % moved.distance_to(_palm(arms, weapon.to_global(grip))))
	var before := arms.sway()
	for i in 20:
		arms.tick(5.0, 1.0 / 30.0)
	_check(arms.sway().length() > 0.001 and not arms.sway().is_equal_approx(before), "walking sways the weapon mount (%.4f m)" % arms.sway().length())
	var worst := 0.0
	for i in 150:
		arms.tick(5.0, 1.0 / 30.0)
		worst = maxf(worst, _bone_world(sk, "Middle1.R").distance_to(_palm(arms, weapon.to_global(grip))))
		worst = maxf(worst, _bone_world(sk, "LowerArm.R").distance_to(weapon.to_global(grip)) - 0.6)
	_check(worst < 0.03, "the hand stays on the grip through a long walk (worst %.3f m)" % worst)
	arms.set_held(DotViewGrip.one_hand(weapon, grip))
	arms.tick(0.0, 1.0 / 30.0)
	var rest_left := _bone_world(sk, "Middle1.L")
	_check(rest_left.distance_to(weapon.to_global(fore)) > 0.1, "a one-hand grip leaves the other hand off the foregrip (%.2f m away)" % rest_left.distance_to(weapon.to_global(fore)))
	_check(sk.get_bone_pose_scale(sk.find_bone("UpperArm.L")).x < 0.01, "a one-hand grip hides the idle left arm")
	arms.show_idle_left_arm = true
	arms.tick(0.0, 1.0 / 30.0)
	_check(sk.get_bone_pose_scale(sk.find_bone("UpperArm.L")).x > 0.5, "show_idle_left_arm keeps it")
	arms.show_idle_left_arm = false
	arms.set_held(DotViewGrip.two_hand(weapon, grip, fore))
	arms.tick(0.0, 1.0 / 30.0)
	_check(sk.get_bone_pose_scale(sk.find_bone("UpperArm.L")).x > 0.5, "a two-hand grip shows the left arm")
	arms.set_held(DotViewGrip.two_hand(weapon, grip, Vector3(0.0, 5.0, 0.0)))
	arms.tick(0.0, 1.0 / 30.0)
	_check(_bone_world(sk, "Middle1.L").distance_to(weapon.to_global(Vector3(0.0, 5.0, 0.0))) > 1.0, "a support point out of reach is not reached (the check can fail)")
	arms.set_held(DotViewGrip.two_hand(weapon, grip, fore))
	arms.set_downed(true)
	for i in 4:
		arms.tick(1.0, 1.0 / 30.0)
		await get_tree().process_frame
	_check(not arms.describe()["held"] and (arms.arms() as DotHumanoidFigure).downed, "downed wins over a held weapon")
	var head := _bone_world(sk, "Head")
	var crawl_hand := _bone_world(sk, "Middle1.L")
	_check(crawl_hand.z < head.z - 0.2 and crawl_hand.y < head.y, "and the crawl is as without a grip: the hand ahead of the eye")
	arms.set_downed(false)
	arms.set_held(null)
	_check(not arms.arms().visible and arms.sway() == Vector3.ZERO, "mode off hides the arms and stops the sway")
	_check(not DotViewGrip.new().is_valid(), "a grip with no anchor is not valid, so the arms rest")
	arms.queue_free()
	weapon.queue_free()


## Where the wrist should be for a grip point: the point shifted by palm_offset in the arms' frame (x mirrored for the support hand).
func _palm(arms: DotPlayerViewArms, point: Vector3, support := false) -> Vector3:
	var o := arms.palm_offset
	return point + arms.global_transform.basis * Vector3(-o.x if support else o.x, o.y, o.z)


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin


## A gun in the hand stays put when the pace flickers across the walk, run and sprint thresholds
## (a bot's noisy speed, a remote player's interpolation): the stride cut must not snap the arm.
func _test_held_gun_steady() -> void:
	_section("a held gun while the pace flickers")
	var world := Node3D.new()
	add_child(world)
	var f := DotHumanoidFigure.new()
	world.add_child(f)
	f.build(DotHumanoidLook.stock(21), 1.8)
	f.set_hold(DotHumanoidFigure.Hold.GUN)
	var hand := f.attachment(&"right_hand")
	var worst := {}
	for pair: Array in [[2.0, 4.6], [4.6, 6.5]]:
		var last := Transform3D.IDENTITY
		var big := 0.0
		var far := 0.0
		for i in 240:
			f.animate(pair[0] if (i / 6) % 2 == 0 else pair[1], 1.0 / 60.0)
			await get_tree().process_frame
			var now: Transform3D = f.global_transform.affine_inverse() * hand.global_transform
			if i > 30:
				big = maxf(big, last.basis.get_rotation_quaternion().angle_to(now.basis.get_rotation_quaternion()))
				far = maxf(far, (now.origin - last.origin).length())
			last = now
		worst[pair[1]] = [rad_to_deg(big), far]
	var sprint: Array = worst[6.5]
	var run: Array = worst[4.6]
	_check(run[0] < 8.0 and sprint[0] < 8.0, "the hand turns under 8 degrees a frame (%.1f / %.1f)" % [run[0], sprint[0]])
	_check(run[1] < 0.08 and sprint[1] < 0.08, "the hand moves under 8 cm a frame (%.3f / %.3f)" % [run[1], sprint[1]])
	f.queue_free()
	_check(true, "the flicker run finished")


func _test_pose_record() -> void:
	_section("a recorded pose replays as drawn")
	var world := Node3D.new()
	add_child(world)
	var live := DotHumanoidFigure.new()
	var copy := DotHumanoidFigure.new()
	for f: DotHumanoidFigure in [live, copy]:
		world.add_child(f)
		f.build(DotHumanoidLook.stock(21), 1.8)
		f.set_hold(DotHumanoidFigure.Hold.GUN)
	var sk := live.skeleton()
	var steps: Array = []
	for i in 30:
		steps.append([{"on_floor": true, "aim": 0.3}, 4.6])
	for i in 30:
		steps.append([{"on_floor": true, "crouched": true, "aim": -0.4}, 1.5])
	for i in 30:
		steps.append([{"on_floor": true, "aim": 0.6}, 0.0])
	var worst := 0.0
	var off_rest := INF
	var applied := true
	var last := PackedFloat32Array()
	for step: Array in steps:
		live.set_motion(step[0])
		live.animate(step[1], 1.0 / 60.0)
		var rec := live.pose_record()
		applied = copy.pose_apply(rec, rec, 0.0) and applied
		worst = maxf(worst, _pose_gap(sk, copy.skeleton(), true))
		off_rest = minf(off_rest, _pose_gap(sk, sk, false))
		last = rec
	_check(applied and worst < 0.001, "each frame of run, crouch and aim applied to another figure is the live pose (worst %.5f rad)" % worst)
	_check(off_rest > 0.5, "and none of them is the rest pose (least %.2f rad from it)" % off_rest)
	var first := steps.size()
	live.set_motion({"on_floor": true})
	live.animate(0.0, 1.0 / 60.0)
	var other := live.pose_record()
	_check(copy.pose_apply(last, other, 0.5) and not copy.pose_apply(last, other.slice(0, other.size() - 3), 0.5),
		"two records blend; records of different sizes are refused (%d floats a pose)" % last.size())
	var still := DotHumanoidFigure.new()
	world.add_child(still)
	still.build(DotHumanoidLook.stock(21), 1.8)
	still.set_hold(DotHumanoidFigure.Hold.GUN)
	still.set_motion({"on_floor": true})
	still.animate(4.6, 0.0)
	var frozen := still.pose_record()
	for i in 20:
		still.animate(4.6, 0.0)
	var gap := _pose_gap(still.skeleton(), still.skeleton(), false)
	_check(gap > 0.0 and still.pose_record() == frozen and first > 0,
		"a body posed by speed alone, with no time, stands frozen at a run (%.2f rad from rest): why a replay records the pose" % gap)
	world.queue_free()
	await get_tree().process_frame


## Largest bone rotation gap, in radians: between two skeletons' poses, or (same=false) a pose and its rest.
func _pose_gap(a: Skeleton3D, b: Skeleton3D, same: bool) -> float:
	var gap := 0.0
	for i in a.get_bone_count():
		var qa := a.get_bone_pose_rotation(i)
		var qb := b.get_bone_pose_rotation(i) if same else b.get_bone_rest(i).basis.get_rotation_quaternion()
		gap = maxf(gap, qa.normalized().angle_to(qb.normalized()))
	return gap


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
