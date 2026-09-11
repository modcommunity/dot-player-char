extends Node

## Exercises dot-player-char with no art, which is the promise being checked.
##
## A dedicated server has to decide whether a character and a customisation document are
## legal without loading a mesh. This suite loads nothing at all, and the section that
## uses a real node uses a stub visual — which doubles as the worked example of what a
## visual implements.
##
## [codeblock]
## godot --headless --path . res://examples/char_selftest.tscn
## [/codeblock]

const SECTIONS := 6
const CHECKS := 104

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-player-char self-test")
	_line("")

	_test_metrics()
	_test_shapes()
	_test_catalogue()
	_test_look()
	await _test_node()
	await _test_visuals()

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


## A worked example of a visual: four overrides and nothing else.
class StubVisual extends DotPlayerCharVisual:
	var applied := 0
	var last_char: StringName = &""
	var crouched := false
	var shown := true
	var head: Node = null
	var offer_eye := -1.0

	func apply_char(def: DotPlayerCharDef, _look: DotPlayerCharLook) -> void:
		applied += 1
		last_char = def.id if def != null else &""

	func set_stance(p_crouched: bool) -> void:
		crouched = p_crouched

	func set_shown(p_shown: bool) -> void:
		shown = p_shown

	func eye_offset() -> float:
		return offer_eye

	func attachment(point: StringName) -> Node:
		return head if point == &"head" else null

	func attachment_names() -> Array[StringName]:
		return [&"head"]


# --- Metrics ----------------------------------------------------------------

func _test_metrics() -> void:
	_section("body metrics")

	var c := DotPlayerCharDef.make(&"medium", 1.8, 0.35)
	_check(c.validate().ok, "the derived metrics validate")
	_check(c.crouch_height < c.height, "crouching makes you shorter")
	_check(c.eye_height < c.height, "and your eyes are below the top of your head")
	_check(
		is_equal_approx(c.eye_for(false), c.eye_height),
		"the eye height depends on the stance"
	)
	_check(is_equal_approx(c.eye_for(true), c.crouch_eye_height), "on both of them")
	_check(is_equal_approx(c.height_for(true), c.crouch_height), "and so does the height")

	var backwards := DotPlayerCharDef.make(&"bad", 1.8)
	backwards.crouch_height = 2.5
	_check(
		not backwards.validate().ok,
		"crouching taller is refused: it would get stuck coming out of every gap it "
		+ "crouched into"
	)

	var floating := DotPlayerCharDef.make(&"floaty", 1.8)
	floating.eye_height = 3.0
	_check(
		not floating.validate().ok,
		"and so are eyes above the head — the camera would sit outside the collision "
		+ "hull and the player would see over walls they are standing behind"
	)

	var crouch_floating := DotPlayerCharDef.make(&"c", 1.8)
	crouch_floating.crouch_eye_height = 1.7
	_check(not crouch_floating.validate().ok, "the crouched pair is checked too")
	_check(not DotPlayerCharDef.new().validate().ok, "and a character with no id")

	c.teams = [&"blue"]
	c.classes = [&"scout"]
	_check(c.allows(&"blue", &"scout"), "restrictions admit a match")
	_check(not c.allows(&"red", &"scout"), "and refuse the wrong side")
	_check(not c.allows(&"blue", &"heavy"), "and the wrong class")
	_check(c.allows(&"", &""), "and a game with neither is admitted")

	c.selectable = false
	_check(not c.allows(&"blue", &"scout"), "an unselectable character admits nobody")
	c.selectable = true

	var wire := DotPlayerCharDef.from_dict(c.to_dict())
	_check(is_equal_approx(wire.height, c.height), "a definition survives the wire")
	_check(is_equal_approx(wire.eye_height, c.eye_height), "with its eye height")

	c.voice_set = &"scout_voice"
	c.footstep_set = &"light_steps"
	c.requires_entitlement = &"scout_unlock"
	var ids := DotPlayerCharDef.from_dict(c.to_dict())
	_check(
		ids.voice_set == &"scout_voice" and ids.footstep_set == &"light_steps"
		and ids.requires_entitlement == &"scout_unlock",
		"and every content id it names — an id declared on the definition and absent "
		+ "from its wire form is an id a mirroring client never learns"
	)
	_check(c.describe().contains("medium"), "and describes itself")


func _test_shapes() -> void:
	_section("collision shapes")

	var c := DotPlayerCharDef.make(&"medium", 1.8, 0.35)

	var standing := c.capsule_3d(false)
	_check(is_equal_approx(standing.radius, 0.35), "a capsule takes the radius")
	_check(is_equal_approx(standing.height, 1.8), "and the standing height")

	var crouched := c.capsule_3d(true)
	_check(crouched.height < standing.height, "and shrinks when crouched")

	_check(
		c.capsule_3d(false) != standing,
		"a fresh shape each time — a Shape3D handed to two bodies is shared by them, "
		+ "so resizing one character would resize everybody using the resource"
	)

	var squat := DotPlayerCharDef.make(&"squat", 0.5, 0.4)
	squat.crouch_height = 0.4
	squat.eye_height = 0.45
	squat.crouch_eye_height = 0.35
	_check(squat.validate().ok, "a character wider than it is tall is legal")
	_check(
		squat.capsule_3d().height >= squat.radius * 2.0,
		"and its capsule is clamped to at least two radii, which is the smallest "
		+ "capsule there is"
	)

	var flat := c.capsule_2d()
	_check(is_equal_approx(flat.radius, 0.35), "there is a 2D capsule too")


func _test_catalogue() -> void:
	_section("a catalogue")

	var std := DotPlayerCharCatalogue.standard()
	_check(std.build().ok, "the standard catalogue builds")
	_check(
		is_equal_approx(std.get_char(&"standard").height, 1.8),
		"with the metrics every corridor and doorway in this genre was built around"
	)
	_check(std.fallback_for() != null, "and a fallback")

	var three := DotPlayerCharCatalogue.three_builds()
	_check(three.build().ok, "the three-build catalogue builds")
	_check(three.ids().size() == 3, "with three characters")
	_check(
		three.get_char(&"heavy").height > three.get_char(&"light").height,
		"whose metrics actually differ — three characters with identical hulls are "
		+ "three skins"
	)
	_check(
		three.get_char(&"heavy").hitbox_scale > three.get_char(&"light").hitbox_scale,
		"and the large one is genuinely easier to hit"
	)
	_check(three.fallback_for().id == &"medium", "with the baseline as the default")

	var flat := DotPlayerCharCatalogue.sprite_2d(48.0)
	_check(flat.build().ok, "the 2D catalogue builds")
	_check(is_equal_approx(flat.get_char(&"sprite").height, 48.0), "in pixels")

	var restricted := DotPlayerCharCatalogue.three_builds()
	restricted.get_char(&"heavy").teams = [&"red"]
	_check(restricted.ids_for(&"blue").size() == 2, "a side sees what it may use")
	_check(restricted.ids_for(&"red").size() == 3, "and the other sees all of it")
	_check(
		restricted.fallback_for(&"blue").id != &"heavy",
		"and a fallback is one that side can actually be"
	)

	var dup := DotPlayerCharCatalogue.new()
	dup.characters = [DotPlayerCharDef.make(&"a"), DotPlayerCharDef.make(&"a")]
	_check(not dup.build().ok, "two characters with one name are refused")

	var bad := DotPlayerCharCatalogue.new()
	bad.characters = [DotPlayerCharDef.make(&"a")]
	bad.default_char = &"missing"
	_check(not bad.build().ok, "a default that is not in it is refused")
	_check(not DotPlayerCharCatalogue.new().build().ok, "and an empty catalogue")

	_check(DotPlayerCharCatalogue.presets().size() == 3, "three presets")
	_check(DotPlayerCharCatalogue.preset(&"three_builds") != null, "resolving by name")
	_check(std.describe_lines().size() == 2, "and a catalogue describes itself")


# --- The look document ------------------------------------------------------

func _test_look() -> void:
	_section("the customisation document")

	var def := DotPlayerCharDef.make(&"medium", 1.8)
	def.slots = {"head": ["none", "cap", "helmet"], "back": ["none", "pack"]}
	def.colour_channels = 2

	_check(def.has_slot(&"head"), "a character has slots")
	_check(def.slot_options(&"head").size() == 3, "with options")
	_check(def.slot_options(&"nope").is_empty(), "and nothing for a slot it has not")
	_check(def.slot_names().size() == 2, "and they can be listed")

	var look := DotPlayerCharLook.make(&"medium")
	look.choose(&"head", &"cap")
	_check(look.chosen(&"head") == &"cap", "a choice reads back")
	_check(look.validate(def).ok, "and validates")

	look.choose(&"head", &"crown")
	_check(
		not look.validate(def).ok,
		"an option the character does not have is refused, from ids alone — nothing "
		+ "here loads a mesh, which is the whole value of the document"
	)

	look.clear_slot(&"head")
	look.choose(&"ears", &"none")
	_check(not look.validate(def).ok, "and so is a slot it does not have")

	look.clear_slot(&"ears")
	look.colours = [Color.RED, Color.BLUE, Color.GREEN]
	_check(
		not look.validate(def).ok,
		"and more colours than channels — a document that may carry any number of "
		+ "colours is one a client can make arbitrarily large"
	)

	look.colours = [Color.RED]
	_check(look.validate(def).ok, "within the channel count it is fine")

	var wrong := DotPlayerCharLook.make(&"other")
	_check(
		not wrong.validate(def).ok,
		"and a look for a different character is refused rather than half-applied"
	)
	_check(not DotPlayerCharLook.new().validate(null).ok, "with nothing to check against")

	# Conform, which is the loading path rather than the trust boundary.
	var stale := DotPlayerCharLook.make(&"medium")
	stale.choose(&"head", &"crown")
	stale.choose(&"back", &"pack")
	stale.colours = [Color.RED, Color.BLUE, Color.GREEN, Color.WHITE]
	var dropped := stale.conform(def)
	_check(dropped == 3, "conform drops what is no longer legal")
	_check(stale.chosen(&"head") == &"", "including the removed hat")
	_check(
		stale.chosen(&"back") == &"pack",
		"and keeps what still is — refusing the whole document would lock somebody out "
		+ "of their own character because a cosmetic was retired"
	)
	_check(stale.validate(def).ok, "and the result validates")

	stale.fill_defaults(def)
	_check(stale.chosen(&"head") == &"none", "filling defaults completes the document")
	_check(
		stale.colours.size() == 2,
		"and tops the colours up, so a player who never opened the menu still has a "
		+ "complete look rather than one a renderer has to have an opinion about"
	)

	var wire := DotPlayerCharLook.from_dict(stale.to_dict())
	_check(wire.chosen(&"back") == &"pack", "a look survives the wire")
	_check(wire.colours.size() == 2, "with its colours")
	_check(
		wire.colours[0].is_equal_approx(stale.colours[0]),
		"which round-trip through hex rather than through a cast that does not exist"
	)

	var copy := stale.copy_look()
	copy.choose(&"back", &"none")
	_check(stale.chosen(&"back") == &"pack", "a copy is a copy")
	_check(stale.describe().contains("medium"), "and it describes itself")


# --- The node ---------------------------------------------------------------

func _test_node() -> void:
	_section("the component")

	var roster := DotPlayerRoster.new()
	roster.register_service = false
	add_child(roster)
	var _j := roster.join("ada", "Ada", 1, 0)

	var player := DotPlayer.new()
	player.roster_ref = DotNodeRef.of_path(roster.get_path())
	add_child(player)

	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	player.add_child(body)

	var ch := DotPlayerChar.new()
	ch.catalogue = DotPlayerCharCatalogue.three_builds()
	player.add_child(ch)
	player.player_key = "ada"

	await get_tree().process_frame

	_check(ch.is_bound(), "the component binds")
	_check(
		ch.char_id == &"medium",
		"and takes the catalogue's fallback when nothing was chosen, rather than "
		+ "leaving the player with no body metrics at all"
	)
	_check(ch.def() != null, "with a definition")
	_check(is_equal_approx(ch.height(), 1.8), "and a height")
	_check(is_equal_approx(ch.eye_height(), ch.def().eye_height), "and an eye height")

	_check(
		shape.shape is CapsuleShape3D,
		"and it sized the body's collision shape, which is the whole reason the "
		+ "metrics live in one place"
	)
	_check(
		is_equal_approx((shape.shape as CapsuleShape3D).height, 1.8),
		"to this character"
	)

	_check(
		roster.get_record("ada").char_id == &"medium",
		"and reported the character to the roster, so a scoreboard and a client mirror "
		+ "both know"
	)

	ch.set_crouched(true)
	_check(ch.is_crouched(), "crouching is recorded")
	_check(is_equal_approx(ch.height(), ch.def().crouch_height), "the height follows")
	_check(ch.eye_height() < ch.def().eye_height, "and so do the eyes")
	_check(
		is_equal_approx((shape.shape as CapsuleShape3D).height, ch.def().crouch_height),
		"and the capsule"
	)
	ch.set_crouched(false)

	_check(ch.set_char(&"heavy").ok, "the character can be changed")
	_check(is_equal_approx(ch.height(), 2.0), "and the metrics change with it")
	_check(
		is_equal_approx((shape.shape as CapsuleShape3D).height, 2.0),
		"and so does the hull, so a character that looks two metres tall is two metres "
		+ "tall"
	)
	_check(not ch.set_char(&"nonexistent").ok, "an unknown character is refused")

	var eye := ch.eye_transform(Transform3D.IDENTITY, Basis.IDENTITY)
	_check(
		is_equal_approx(eye.origin.y, ch.eye_height()),
		"one eye transform, so a camera, a muzzle and a lag-compensated trace cannot "
		+ "get three slightly different answers"
	)

	var no_cat := DotPlayerChar.new()
	player.add_child(no_cat)
	await get_tree().process_frame
	_check(not no_cat.set_char(&"anything").ok, "a component with no catalogue refuses")
	_check(is_equal_approx(no_cat.height(), 1.8), "and falls back to sane metrics")

	_check(ch.describe_lines().size() >= 3, "and it describes itself")

	player.queue_free()
	roster.queue_free()


func _test_visuals() -> void:
	_section("visuals")

	var player := DotPlayer.new()
	add_child(player)

	var ch := DotPlayerChar.new()
	ch.catalogue = DotPlayerCharCatalogue.three_builds()
	ch.size_body = false
	ch.report_to_roster = false
	player.add_child(ch)

	var a := StubVisual.new()
	var b := StubVisual.new()
	ch.add_child(a)
	ch.add_child(b)

	await get_tree().process_frame

	var _set := ch.set_char(&"light")
	_check(a.applied > 0, "a visual is told about the character")
	_check(a.last_char == &"light", "which one")
	_check(b.applied > 0, "and so is every other one")

	var before := a.applied
	var _again := ch.set_look(DotPlayerCharLook.make(&"light"))
	_check(
		a.applied > before,
		"and again when the look changes — which must be safe, because a player "
		+ "editing their character in a menu does it several times a second"
	)

	ch.set_crouched(true)
	_check(a.crouched, "a stance change reaches the visuals")
	_check(
		a.applied == before + 1,
		"without rebuilding them, because rebuilding a rig every time somebody ducks "
		+ "would be absurd"
	)
	ch.set_crouched(false)

	ch.set_shown(false)
	_check(not a.shown and not b.shown, "hiding hides all of them")
	ch.set_shown(true)

	ch.use_visual(a)
	_check(
		a.visual_enabled and not b.visual_enabled,
		"exactly one visual is enabled — a first-person arms rig and a third-person "
		+ "body both drawn is the bug where you can see your own head"
	)

	a.offer_eye = 1.42
	_check(
		is_equal_approx(ch.eye_height(), 1.42),
		"a rig with a real head bone overrides the number in the resource, which is "
		+ "what makes a first-person camera line up with a third-person model"
	)
	a.offer_eye = -1.0
	_check(
		is_equal_approx(ch.eye_height(), ch.def().eye_height),
		"and no opinion falls back to the definition"
	)

	var head := Node3D.new()
	a.head = head
	add_child(head)
	_check(ch.attachment(&"head") == head, "an attachment point resolves")
	_check(
		ch.attachment(&"nothing") == null,
		"and an unknown one answers null, which every caller must handle — a game that "
		+ "switched from models to sprites loses every bone"
	)

	ch.use_visual(b)
	_check(
		ch.attachment(&"head") == null,
		"and only the enabled visual is asked"
	)

	_check(ch.visuals().size() == 2, "the visuals can be listed")
	_check(a.attachment_names().size() == 1, "and name their attachment points")
	_check(a.describe_lines().size() == 1, "and describe themselves")

	head.queue_free()
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
