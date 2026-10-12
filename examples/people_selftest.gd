extends Node

## Exercises the family's people: the look (stock, the site's avatar, a side's colour), the clip
## set on every body (carried over by retargeting, the made crouch, the grounded air clips), and
## the figure choosing clips from how it moves, holding, swinging and sharing materials.
##
## What a person LOOKS like is not here: that is `tools/people_sheet.gd`'s contact sheets.
##
## [codeblock]
## godot --headless --path . res://examples/people_selftest.tscn
## [/codeblock]

const SECTIONS := 7
const CHECKS := 61

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
	_test_materials()
	await _test_break()

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
	f.animate(6.0, 0.1)
	_check(f.clip == DotHumanoidClips.RUN, "running: run")
	f.set_hold(DotHumanoidFigure.Hold.GUN)
	f.animate(6.0, 0.1)
	_check(f.clip == DotHumanoidClips.RUN_GUN, "running with a gun: the gun run")
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
	_check(f.state == DotPlayerAnimState.SWIM and f.clip == DotHumanoidClips.RUN, "swimming: a slow stroke, leaned forward")
	f.set_motion({"alive": false})
	f.animate(0.0, 0.1)
	_check(f.clip == DotHumanoidClips.DEATH, "dead: the death")

	f.set_motion({})
	f.set_hold(DotHumanoidFigure.Hold.MELEE)
	f.animate(6.0, 0.1)
	f.swing()
	_check(f.overlay == DotHumanoidClips.SLASH and f.clip == DotHumanoidClips.RUN, "a swing plays over the run: the legs keep running")
	for i in range(20):
		f.animate(6.0, 0.1)
	_check(f.overlay == &"", "and ends")

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
	_check(walker.clip == DotHumanoidClips.WALK or walker.clip == DotHumanoidClips.RUN,
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

	f.aim(0.0)
	f.set_motion({"seated": true})
	f.animate(3.0, 0.1)
	_check(f.clip == DotHumanoidClips.SIT, "seated, even carried at speed: sitting")
	var seat := f.seat_height()
	_check(seat > 0.2 and seat < 0.5, "the hips sit at knee height (%.2f m of 1.8: short cartoon legs)" % seat)
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
	_check(paths.size() == 5 and Array(paths).all(func(p: String) -> bool: return ResourceLoader.exists(p)), "every file a figure loads is listed, and exists")


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
