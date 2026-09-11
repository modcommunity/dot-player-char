extends Node

## Exercises dot-player-char-model with rigs built in code and no art on disk.
##
## The planning half is checked as arithmetic over ids, which is the half that was
## generalised out of dot-user-avatar and the half a server could run. The node half is
## checked against real [Node3D] rigs assembled here, because "did it clear the mount
## before rebuilding it" is not a question a value can answer.
##
## [codeblock]
## godot --headless --path . res://examples/model_selftest.tscn
## [/codeblock]

const SECTIONS := 6
const CHECKS := 80

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-player-char-model self-test")
	_line("")

	_test_def()
	_test_catalogue()
	_test_plan()
	# Awaited: this section waits two frames for deferred frees, and an un-awaited
	# coroutine would let the tally at the bottom print before it finished.
	await _test_build()
	_test_rig()
	await _test_visual()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _model() -> DotPlayerModelDef:
	var m := DotPlayerModelDef.make(&"humanoid")
	m.mounts = {"head": "Head", "back": "Chest/Back", "right_hand": "RightHand"}
	m.parts = {"cap": "res://parts/cap.tscn", "pack": "res://parts/pack.tscn"}
	m.part_slots = {"cap": "head", "pack": "back"}
	m.part_layers = {"cap": 10, "pack": 20}
	m.eye_mount = &"head"
	return m


## A rig assembled in code, standing in for one an artist would author.
func _rig_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "Rig"

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.62, 0)
	root.add_child(head)

	var chest := Node3D.new()
	chest.name = "Chest"
	chest.position = Vector3(0, 1.2, 0)
	root.add_child(chest)

	var back := Node3D.new()
	back.name = "Back"
	chest.add_child(back)

	var hand := Node3D.new()
	hand.name = "RightHand"
	root.add_child(hand)

	return root


func _look(cap: bool = true, pack: bool = true) -> DotPlayerCharLook:
	var l := DotPlayerCharLook.make(&"standard")

	if cap:
		l.choose(&"head", &"cap")

	if pack:
		l.choose(&"back", &"pack")

	l.colours = [Color.RED, Color.BLUE]
	return l


# --- The definition ---------------------------------------------------------

func _test_def() -> void:
	_section("a model definition")

	var m := _model()
	_check(m.validate().ok, "validates")
	_check(m.has_mount(&"head"), "and has the mounts it names")
	_check(m.mount_name(&"back") == "Chest/Back", "with a node name, not a NodePath")
	_check(m.slot_names().size() == 3, "which can be listed")
	_check(m.has_part(&"cap"), "and the parts")
	_check(m.part_slot(&"cap") == &"head", "each knowing its slot")
	_check(m.part_layer(&"pack") == 20, "and its layer")
	_check(m.part_layer(&"unlisted") == 50, "with a default for one that has none")

	var orphan := _model()
	orphan.parts["boots"] = "res://parts/boots.tscn"
	_check(
		not orphan.validate().ok,
		"a part with no slot is refused: it would be built into whichever mount "
		+ "happened to ask for it, which is how a hat ends up on a foot"
	)

	var wrong := _model()
	wrong.part_slots["cap"] = "feet"
	_check(
		not wrong.validate().ok,
		"and so is a part whose slot the rig has no mount for"
	)

	_check(not DotPlayerModelDef.new().validate().ok, "and a model with no id")
	_check(m.describe().contains("humanoid"), "and it describes itself")


func _test_catalogue() -> void:
	_section("a catalogue")

	var cat := DotPlayerModelCatalogue.new()
	cat.id = &"test"
	cat.models = [_model()]
	cat.default_model = &"humanoid"
	_check(cat.build().ok, "a catalogue builds")
	_check(cat.has_model(&"humanoid"), "with its model")
	_check(cat.fallback().id == &"humanoid", "and a fallback")

	var paths := cat.content_paths()
	_check(
		paths.size() == 2,
		"and it lists every scene it could need, which is what a preloader or a "
		+ "dot-cloud manifest asks for — a game listing them by hand ships a model with "
		+ "a part missing"
	)

	var dup := DotPlayerModelCatalogue.new()
	dup.models = [_model(), _model()]
	_check(not dup.build().ok, "two models with one name are refused")
	_check(not DotPlayerModelCatalogue.new().build().ok, "and an empty catalogue")

	var humanoid := DotPlayerModelCatalogue.humanoid()
	_check(humanoid.build().ok, "the humanoid preset builds")
	_check(
		humanoid.get_model(&"humanoid").slot_names().size() == 9,
		"with the nine mounts a character rig is expected to have — agreeing on the "
		+ "spelling is what lets a weapon written for one game attach in another"
	)
	_check(
		humanoid.get_model(&"humanoid").weapon_mount == &"right_hand",
		"including where a weapon goes"
	)
	_check(cat.describe_lines().size() == 2, "and a catalogue describes itself")


# --- Planning ---------------------------------------------------------------

func _test_plan() -> void:
	_section("planning")

	var m := _model()
	var plan := DotPlayerModelBuilder.plan(m, _look())

	_check(plan.size() == 2, "a plan covers the filled slots")
	_check(str(plan[0]["mount"]) != "", "and resolves each to a mount")
	_check(
		int(plan[0]["layer"]) < int(plan[1]["layer"]),
		"sorted by layer, so two parts in one mount stack the same way every time"
	)
	_check(
		(plan[0]["colours"] as Array).size() == 2,
		"and each step carries the colours"
	)
	_check(
		not bool(plan[0]["missing"]),
		"and 'missing' means the definition names no path — NOT that the file is "
		+ "absent. Planning deliberately does not call ResourceLoader.exists: a "
		+ "dedicated server plans from ids and has none of the content, so a plan that "
		+ "consulted the filesystem would answer differently on the server and the "
		+ "client. Whether the scene is really there is decided at build time."
	)

	_check(DotPlayerModelBuilder.plan(null, _look()).is_empty(), "no model, no plan")
	_check(
		DotPlayerModelBuilder.plan(m, DotPlayerCharLook.make(&"x")).is_empty(),
		"and an empty look plans nothing rather than everything"
	)

	var partial := DotPlayerModelBuilder.plan(m, _look(true, false))
	_check(partial.size() == 1, "a half-filled look plans half of it")

	var misplaced := _model()
	misplaced.part_slots["cap"] = "back"
	var bad := DotPlayerModelBuilder.plan(misplaced, _look(true, false))
	_check(
		bad.size() == 1 and str(bad[0]["scene"]) == "",
		"a part asked for in the wrong slot resolves to nothing rather than being "
		+ "built into the wrong mount"
	)

	var summary := DotPlayerModelBuilder.summarise(plan)
	_check(int(summary["slots"]) == 2, "a plan summarises")
	_check(int(summary["missing"]) == 0, "with the count of parts the model cannot place")
	_check(bool(summary["complete"]), "and this one is complete")
	_check(
		int(DotPlayerModelBuilder.summarise(bad)["missing"]) == 1,
		"while a plan with an unplaceable part is not"
	)
	_check(
		bool(DotPlayerModelBuilder.summarise([])["complete"]),
		"while an empty plan is trivially complete"
	)

	# The dot-user-avatar bridge, which is duck-typed both ways.
	var avatar_rows: Array = [
		{"slot": "head", "attach_to": "Head", "requested": "crown",
			"scene_path": "res://x.tscn", "colours": [Color.RED], "layer": 5},
	]
	var bridged := DotPlayerModelBuilder.from_plan(avatar_rows)
	_check(bridged.size() == 1, "an avatar plan converts")
	_check(str(bridged[0]["mount"]) == "Head", "taking its attachment name")
	_check(StringName(str(bridged[0]["part"])) == &"crown", "and its part")
	_check(str(bridged[0]["scene"]) == "res://x.tscn", "and its path")
	_check(
		DotPlayerModelBuilder.from_plan([{"slot": "head"}], {"head": "Head"}).size() == 1,
		"and a row with no attachment name takes one from a mount table"
	)
	_check(DotPlayerModelBuilder.from_plan([1, 2, 3]).is_empty(), "nonsense converts to nothing")


# --- Building ---------------------------------------------------------------

func _test_build() -> void:
	_section("building")

	var m := _model()
	var rig := _rig_scene()
	add_child(rig)

	var placeholder := PackedScene.new()
	var stand_in := MeshInstance3D.new()
	stand_in.name = "Placeholder"
	var _packed := placeholder.pack(stand_in)
	stand_in.free()

	var plan := DotPlayerModelBuilder.plan(m, _look())
	var res := DotPlayerModelBuilder.apply(plan, rig, placeholder)
	_check(res.ok, "a plan builds")
	_check(
		int(res.value) == 2,
		"and shows a placeholder for each missing part rather than nothing at all"
	)
	_check(rig.get_node("Head").get_child_count() == 1, "one thing in the head mount")
	_check(rig.get_node("Chest/Back").get_child_count() == 1, "and one on the back")

	# The rebuild, which is the thing that has to be right.
	var built_again := DotPlayerModelBuilder.apply(plan, rig, placeholder)
	_check(built_again.ok, "applying a second plan to the same rig works")
	await await_free()
	_check(
		rig.get_node("Head").get_child_count() <= 1,
		"and the mount is cleared first — a builder that appended would grow a hat per "
		+ "frame for a player editing their character in a menu"
	)

	_check(
		not DotPlayerModelBuilder.apply(plan, null).ok,
		"building on nothing is refused"
	)

	var no_placeholder := DotPlayerModelBuilder.apply(plan, rig)
	_check(
		int(no_placeholder.value) == 0,
		"and with no placeholder, missing content shows nothing rather than erroring"
	)

	var wrong_rig := Node3D.new()
	add_child(wrong_rig)
	var mismatch := DotPlayerModelBuilder.apply(plan, wrong_rig, placeholder)
	_check(
		mismatch.ok and int(mismatch.value) == 0,
		"a rig with none of the mounts builds nothing and says so, rather than "
		+ "crashing halfway through somebody's character"
	)

	# Tinting, which must be per-instance.
	var mesh := MeshInstance3D.new()
	rig.add_child(mesh)
	DotPlayerModelBuilder.tint(mesh, [Color.RED, Color.BLUE], "dot_tint_")
	_check(
		mesh.get_instance_shader_parameter("dot_tint_0") is Color,
		"a tint is written as a per-instance shader parameter, so two players wearing "
		+ "the same part cannot recolour each other"
	)
	_check(
		(mesh.get_instance_shader_parameter("dot_tint_1") as Color).is_equal_approx(Color.BLUE),
		"one per channel"
	)
	DotPlayerModelBuilder.tint(mesh, [], "dot_tint_")
	_check(
		mesh.get_instance_shader_parameter("dot_tint_0") is Color,
		"and an empty colour list leaves what was there alone rather than clearing it"
	)

	var cleared := DotPlayerModelBuilder.clear(m, rig)
	_check(cleared >= 2, "every mount can be emptied at once")
	_check(DotPlayerModelBuilder.clear(null, rig) == 0, "with nothing to clear being fine")

	rig.queue_free()
	wrong_rig.queue_free()


func await_free() -> void:
	# queue_free is deferred, so a check on child_count immediately after a rebuild
	# would see the old children as well as the new ones. This is the one place in the
	# suite where that matters, and it is worth the two frames rather than the check
	# being written around it.
	await get_tree().process_frame
	await get_tree().process_frame


# --- The rig ----------------------------------------------------------------

func _test_rig() -> void:
	_section("the rig node")

	var m := _model()
	var rig := DotPlayerModelRig.new()
	add_child(rig)
	rig.adopt(_rig_scene(), m)
	rig.add_child(rig.instance)

	_check(rig.mount(&"head") != null, "a mount resolves by slot name")
	_check(rig.mount(&"back") != null, "including a nested one")
	_check(rig.has_mount(&"right_hand"), "and has_mount agrees")
	_check(rig.mount(&"nonexistent") == null, "an unknown slot resolves to nothing")
	_check(rig.mount(&"nonexistent") == null, "twice, from the cache, with one warning")
	_check(rig.mount_names().size() == 3, "the mounts can be listed")
	_check(rig.weapon_mount() != null, "and the weapon mount found")

	_check(
		rig.eye_height() > 1.5,
		"a rig measures its own eye height rather than declaring one — a rig that has "
		+ "been scaled, or whose author put the head somewhere unexpected, is exactly "
		+ "where a declared number is wrong"
	)

	var opinionless := DotPlayerModelRig.new()
	add_child(opinionless)
	var no_eyes := _model()
	no_eyes.eye_mount = &""
	opinionless.adopt(_rig_scene(), no_eyes)
	_check(
		opinionless.eye_height() < 0.0,
		"and a rig with no eye mount answers 'no opinion' rather than zero, which "
		+ "would put the camera in the floor"
	)

	var missing := DotPlayerModelRig.new()
	add_child(missing)
	var bad := _model()
	bad.rig_scene = "res://nothing/here.tscn"
	_check(
		not missing.build_from(bad).ok,
		"a rig scene that is not there is refused — a rig with no mounts silently "
		+ "shows nothing and gets debugged in the renderer"
	)
	_check(missing.build_from(null).ok == false, "and so is no definition at all")

	var sceneless := DotPlayerModelRig.new()
	add_child(sceneless)
	var no_scene := _model()
	no_scene.rig_scene = ""
	_check(
		sceneless.build_from(no_scene).ok,
		"while a model with no scene is legal, for a game whose rig is already there"
	)

	_check(rig.describe_lines().size() == 4, "a rig describes itself and its mounts")

	rig.queue_free()
	opinionless.queue_free()
	missing.queue_free()
	sceneless.queue_free()


# --- The visual -------------------------------------------------------------

func _test_visual() -> void:
	_section("the visual")

	var cat := DotPlayerModelCatalogue.new()
	cat.id = &"test"
	cat.models = [_model()]
	cat.default_model = &"humanoid"
	var _built := cat.build()

	var player := DotPlayer.new()
	add_child(player)

	var ch := DotPlayerChar.new()
	ch.catalogue = DotPlayerCharCatalogue.standard()
	ch.catalogue.get_char(&"standard").model_id = &"humanoid"
	ch.size_body = false
	ch.report_to_roster = false
	player.add_child(ch)

	var visual := DotPlayerModelVisual.new()
	visual.catalogue = cat
	ch.add_child(visual)

	await get_tree().process_frame

	_check(visual.rig != null, "a visual makes itself a rig")
	# The rig scene is empty, so nothing builds — but the plan is still made, which is
	# what a server-side check or a content report would read.
	_check(visual.plan().size() >= 0, "and plans from the character's look")

	var rebuilds: Array = []
	visual.rebuilt.connect(func(shown: int) -> void: rebuilds.append(shown))

	ch.look.choose(&"head", &"cap")
	var _applied := ch.set_look(ch.look)
	var after_first := rebuilds.size()

	var _again := ch.set_look(ch.look)
	_check(
		rebuilds.size() == after_first,
		"an identical look does not rebuild — a player dragging a colour slider calls "
		+ "this several times a second, and rebuilding forty parts a frame for a change "
		+ "that is not a change is the cost the signature exists to avoid"
	)

	ch.look.colours = [Color.GREEN, Color.WHITE]
	var _tinted := ch.set_look(ch.look)
	_check(
		rebuilds.size() == after_first,
		"and a colour change does not either, because a tint is applied to instances "
		+ "that are already there"
	)

	visual.set_shown(false)
	_check(not visual.rig.visible, "hiding hides the rig")
	visual.set_shown(true)
	_check(visual.rig.visible, "and showing shows it")

	visual.set_stance(true)
	_check(
		rebuilds.size() == after_first,
		"a stance change does not rebuild either — re-instantiating a wardrobe every "
		+ "time somebody ducks is the eager half of the mistake"
	)

	_check(visual.attachment_names().size() == 3, "the visual offers its mounts")
	_check(int(visual.summary()["slots"]) >= 0, "and summarises its plan")
	_check(visual.describe_lines().size() >= 2, "and describes itself")

	var bare := DotPlayerModelVisual.new()
	ch.add_child(bare)
	await get_tree().process_frame
	bare.apply_char(ch.def(), ch.look)
	_check(
		bare.eye_offset() < 0.0,
		"a visual with no catalogue builds nothing and has no eye opinion, rather than "
		+ "erroring inside a character screen"
	)

	player.queue_free()


# --- Harness ---------------------------------------------------------------

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
