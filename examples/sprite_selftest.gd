extends Node

## Exercises dot-player-char's sprite half with no art on disk.
##
## The frame arithmetic and the facing resolution are the two halves worth checking
## hardest, because both are the kind of four-line calculation that is wrong in one of
## the three places a project writes it — and because both are pure, so a suite can
## check every case rather than the one somebody happened to look at.
##
## [codeblock]
## godot --headless --path . res://examples/sprite_selftest.tscn
## [/codeblock]

const SECTIONS := 6
const CHECKS := 72

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-player-char sprite self-test")
	_line("")

	_test_def()
	_test_frames()
	_test_facing()
	_test_catalogue()
	await _test_visual()
	await _test_placement()

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


func _def() -> DotPlayerSpriteDef:
	var s := DotPlayerSpriteDef.make(&"hero")
	s.frame_size = Vector2i(32, 48)
	s.columns = 8
	s.rows = 16
	s.directions = 2
	s.layers = {"head": "res://sheets/head.png", "weapon": "res://sheets/weapon.png"}
	s.layer_order = {"head": 1, "weapon": 5}
	return s


# --- The definition ---------------------------------------------------------

func _test_def() -> void:
	_section("a sprite definition")

	var s := _def()
	_check(s.validate().ok, "validates")
	_check(s.direction_count() == 4, "the enum resolves to a real count")
	_check(s.has_layer(&"head"), "it has its layers")
	_check(s.layer_sheet(&"weapon").ends_with("weapon.png"), "with their sheets")

	var order := s.layer_slots()
	_check(
		order[0] == &"head" and order[1] == &"weapon",
		"which come back in draw order — ties broken by name, so two machines agree"
	)

	_check(
		s.content_paths().size() == 2,
		"and it lists every texture it needs, minus the base sheet it has not got"
	)

	_check(
		s.draw_offset().y < 0.0,
		"a bottom anchor offsets the frame upward, because a sprite anchored at its "
		+ "middle sinks into the floor by half its height and reads as a collision bug"
	)

	var no_frame := _def()
	no_frame.frame_size = Vector2i.ZERO
	_check(not no_frame.validate().ok, "a frame of no size is refused")

	var too_small := _def()
	too_small.columns = 1
	too_small.rows = 1
	too_small.directions = 3
	_check(
		not too_small.validate().ok,
		"and a sheet with fewer cells than directions — the facing would land outside "
		+ "the grid"
	)

	var blank_layer := _def()
	blank_layer.layers["hat"] = ""
	_check(not blank_layer.validate().ok, "and a layer naming no sheet")
	_check(not DotPlayerSpriteDef.new().validate().ok, "and a sprite with no id")
	_check(s.describe().contains("hero"), "and it describes itself")


func _test_frames() -> void:
	_section("frame arithmetic")

	var s := _def()

	_check(s.frame_index(0, 0, 0) == 0, "row 0, direction 0, frame 0 is cell 0")
	_check(s.frame_index(0, 0, 3) == 3, "the frame is the column")
	_check(
		s.frame_index(0, 1, 0) == 8,
		"and a direction offsets the row, because a state occupies as many rows as "
		+ "there are directions"
	)
	_check(s.frame_index(1, 0, 0) == 8 * 4, "so the next state starts four rows down")
	_check(s.frame_index(1, 2, 5) == (1 * 4 + 2) * 8 + 5, "and the general case holds")

	_check(
		s.frame_index(0, 0, 999) == 7,
		"a frame past the end of a row clamps rather than wrapping — wrapping draws "
		+ "the start of the animation in the middle of it, which reads as a stutter "
		+ "rather than as a mistake"
	)
	_check(s.frame_index(999, 0, 0) == (s.rows - 1) * s.columns, "and a row past the end too")
	_check(s.frame_index(0, 0, -5) == 0, "and a negative frame")

	var rect := s.frame_rect(9)
	_check(rect.position == Vector2i(32, 48), "cell 9 is the second row, second column")
	_check(rect.size == Vector2i(32, 48), "and is one frame in size")
	_check(s.frame_rect(99999).size == Vector2i(32, 48), "an impossible cell still gives a rect")

	var single := DotPlayerSpriteDef.make(&"one")
	single.directions = 0
	single.columns = 4
	single.rows = 4
	_check(
		single.frame_index(2, 0, 1) == 2 * 4 + 1,
		"a one-direction sheet is one row per state, which is the simple case and is "
		+ "the one an arithmetic error usually still gets right"
	)


func _test_facing() -> void:
	_section("facing")

	# Two directions, mirrored: one drawn row, the flip does the work.
	var right := DotPlayerSpriteFacing.resolve(0.0, 2, true)
	_check(right.index == 0 and not right.flip_h, "facing right is the drawn direction")

	var left := DotPlayerSpriteFacing.resolve(PI, 2, true)
	_check(
		left.index == 0 and left.flip_h,
		"and facing left is the same row, flipped — which is why the flag comes back "
		+ "with the index rather than the caller working it out"
	)

	var unmirrored := DotPlayerSpriteFacing.resolve(PI, 2, false)
	_check(
		unmirrored.index == 1 and not unmirrored.flip_h,
		"a sheet that draws both gets the second row instead"
	)

	# Four directions.
	_check(DotPlayerSpriteFacing.resolve(0.0, 4, false).index == 0, "four-way: east is 0")
	_check(
		DotPlayerSpriteFacing.resolve(PI * 0.5, 4, false).index == 1,
		"a quarter turn is the next sector"
	)
	_check(
		DotPlayerSpriteFacing.resolve(PI * 0.49, 4, false).index == 1,
		"and a sector is centred on its cardinal, so an angle just short of it does "
		+ "not flicker between two rows"
	)
	_check(
		DotPlayerSpriteFacing.resolve(PI * 0.51, 4, false).index == 1,
		"nor an angle just past it"
	)

	# Eight, mirrored: five drawn, three derived.
	var east := DotPlayerSpriteFacing.resolve(0.0, 8, true)
	_check(east.index == 0 and not east.flip_h, "eight-way mirrored: east is drawn")
	var west := DotPlayerSpriteFacing.resolve(PI, 8, true)
	_check(west.index == 4 and not west.flip_h, "so is west, at the halfway row")

	var south_west := DotPlayerSpriteFacing.resolve(PI * 1.25, 8, true)
	_check(
		south_west.flip_h,
		"and the far half is mirrored, which is the standard saving on a directional "
		+ "sheet: draw five, mirror three"
	)

	_check(
		DotPlayerSpriteFacing.drawn_directions(8, true) == 5,
		"an eight-way mirrored sheet only has to draw five rows"
	)
	_check(DotPlayerSpriteFacing.drawn_directions(8, false) == 8, "and an unmirrored one, eight")
	_check(DotPlayerSpriteFacing.drawn_directions(2, true) == 1, "a side-on one draws one")
	_check(DotPlayerSpriteFacing.drawn_directions(1, true) == 1, "and a fixed one, one")

	_check(
		DotPlayerSpriteFacing.resolve(1.234, 1, true).index == 0,
		"a one-direction sheet ignores the angle entirely"
	)

	_check(
		is_equal_approx(DotPlayerSpriteFacing.angle_of(Vector2.ZERO, 1.5), 1.5),
		"a character that stopped keeps facing where it was — snapping to a default "
		+ "makes it turn south every time it stands still"
	)
	_check(
		is_equal_approx(DotPlayerSpriteFacing.angle_of(Vector2(1, 0), 1.5), 0.0),
		"and one that is moving faces where it is going"
	)


func _test_catalogue() -> void:
	_section("a catalogue")

	var cat := DotPlayerSpriteCatalogue.new()
	cat.id = &"test"
	cat.sprites = [_def()]
	cat.default_sprite = &"hero"
	_check(cat.build().ok, "a catalogue builds")
	_check(cat.has_sprite(&"hero"), "with its sprite")
	_check(cat.fallback().id == &"hero", "and a fallback")
	_check(cat.content_paths().size() == 2, "and lists every texture")

	var dup := DotPlayerSpriteCatalogue.new()
	dup.sprites = [_def(), _def()]
	_check(not dup.build().ok, "two sprites with one name are refused")
	_check(not DotPlayerSpriteCatalogue.new().build().ok, "and an empty catalogue")

	var side := DotPlayerSpriteCatalogue.side_on()
	_check(side.build().ok, "the side-on preset builds")
	_check(side.get_sprite(&"side").direction_count() == 2, "with two directions")
	_check(
		side.get_sprite(&"side").anchor.y > 0.9,
		"anchored at the feet, which is what a character standing on the ground wants"
	)

	var top := DotPlayerSpriteCatalogue.top_down()
	_check(top.build().ok, "the top-down preset builds")
	_check(top.get_sprite(&"top_down").direction_count() == 8, "with eight directions")
	_check(
		is_equal_approx(top.get_sprite(&"top_down").anchor.y, 0.5),
		"anchored at the middle, which is what a top-down game wants"
	)
	_check(cat.describe_lines().size() == 2, "and a catalogue describes itself")


func _test_visual() -> void:
	_section("the visual")

	var cat := DotPlayerSpriteCatalogue.new()
	cat.id = &"test"
	cat.sprites = [_def()]
	cat.default_sprite = &"hero"
	var _built := cat.build()

	var player := DotPlayer.new()
	add_child(player)

	var ch := DotPlayerChar.new()
	ch.catalogue = DotPlayerCharCatalogue.sprite_2d(48.0)
	ch.catalogue.get_char(&"sprite").sprite_id = &"hero"
	ch.catalogue.get_char(&"sprite").slots = {"head": ["none", "cap"], "weapon": ["none", "axe"]}
	ch.catalogue.get_char(&"sprite").colour_channels = 1
	ch.size_body = false
	ch.report_to_roster = false
	player.add_child(ch)

	var visual := DotPlayerSpriteVisual.new()
	visual.catalogue = cat
	ch.add_child(visual)

	await get_tree().process_frame

	_check(visual.def() != null, "the visual picked up the character's sheet")
	_check(visual.def().id == &"hero", "the right one")
	_check(
		visual.attachment_names().size() == 2,
		"and every layer is an attachment point — in 2D, 'where the hand is' is the "
		+ "hand layer's own node"
	)
	_check(visual.attachment(&"head") != null, "which resolve by name")
	_check(visual.attachment(&"nothing") == null, "and answer null otherwise")

	visual.set_row(3)
	_check(visual.row() == 3, "a row can be set")
	visual.set_frame(2)
	_check(visual.frame() == 2, "and a frame")

	# Four directions with mirroring: east and west are both drawn, and the two on the
	# far side of the circle are the mirrored ones. -PI/2 is one of those, which is
	# what makes this check able to fail.
	visual.set_facing_angle(-PI * 0.5)
	_check(
		visual.facing().flip_h,
		"a facing angle resolves to a flip, so a caller never has to know how the "
		+ "sheet was cut"
	)
	visual.set_facing_angle(0.0)
	_check(not visual.facing().flip_h, "and back again")

	visual.set_shown(false)
	_check(visual.describe_lines().size() >= 1, "the visual describes itself")
	visual.set_shown(true)

	visual.set_stance(true)
	_check(visual.row() == 3, "a stance does not change the row by itself — which row "
		+ "a state is, is the animation layer's business")

	# The 'none' convention, which is how a slot is worn empty.
	ch.look.choose(&"head", &"none")
	ch.look.choose(&"weapon", &"axe")
	var _applied := ch.set_look(ch.look)
	_check(
		visual.attachment(&"head") != null,
		"a slot set to 'none' keeps its node — hiding a layer is cheaper and more "
		+ "reversible than rebuilding without it"
	)

	var bare := DotPlayerSpriteVisual.new()
	ch.add_child(bare)
	await get_tree().process_frame
	bare.apply_char(ch.def(), ch.look)
	_check(
		bare.def() == null,
		"a visual with no catalogue builds nothing rather than erroring inside a "
		+ "character screen"
	)
	bare.set_frame(1)
	bare.set_facing_angle(1.0)
	_check(bare.frame() == 1, "and still takes instructions without drawing anything")

	player.queue_free()


## Where the sheet is DRAWN. A [Node2D] under a plain [Node] is placed on the canvas, not on
## anybody, so the sprite root kept as this visual's own child stood at the canvas origin
## whatever its player did — the 2D half of the rig bug `model_selftest` describes.
func _test_placement() -> void:
	_section("where the sheet is drawn")

	var cat := DotPlayerSpriteCatalogue.new()
	cat.id = &"placed"
	cat.sprites = [_def()]
	cat.default_sprite = &"hero"
	var _built := cat.build()

	var body := Node2D.new()
	body.name = "Body"
	body.position = Vector2(300.0, -120.0)
	add_child(body)

	var holder := Node.new()
	holder.name = "Components"
	body.add_child(holder)

	var visual := DotPlayerSpriteVisual.new()
	visual.catalogue = cat
	holder.add_child(visual)

	_check(visual.is_seated(), "the sheet hangs off the nearest Node2D above the visual")
	var root := visual.get_node_or_null("../../Sprite") as Node2D
	_check(
		root != null and root.global_position.is_equal_approx(body.global_position),
		"so it is drawn where the body is, not at the canvas origin"
	)
	body.position = Vector2(-50.0, 40.0)
	_check(
		root != null and root.global_position.is_equal_approx(body.global_position),
		"and it moves with the body"
	)

	var loose_parent := Node.new()
	add_child(loose_parent)
	var loose := DotPlayerSpriteVisual.new()
	loose.catalogue = cat
	loose_parent.add_child(loose)
	await get_tree().process_frame
	_check(
		not loose.is_seated() and loose.get_node_or_null("Sprite") != null,
		"with no Node2D above it, the sheet stays where it was"
	)

	body.queue_free()
	loose_parent.queue_free()
	await get_tree().process_frame


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
