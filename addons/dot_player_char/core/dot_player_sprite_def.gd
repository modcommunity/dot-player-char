@tool
class_name DotPlayerSpriteDef
extends Resource

## A 2D character: which sheets, how they are cut, and how many ways it can face.
## The frame arithmetic (a state is a row, a direction an offset, a frame a column) lives in
## [method frame_index] so every layer asks it instead of rewriting it with rows and columns swapped.

## The name everything else uses.
@export var id: StringName = &""

@export var display_name: String = ""

@export_group("The sheet")

## The base sheet. A path rather than a [Texture2D] export, for the same reason
## [DotPlayerModelDef]'s rig is: a catalogue of forty would load forty textures.
@export_file("*.png", "*.webp", "*.svg") var sheet: String = ""

## One frame's size in pixels.
@export var frame_size: Vector2i = Vector2i(32, 32)

## How many columns the sheet has.
## Given, not derived from the texture width, so a server or editor tool can reason about the sheet
## without loading it, and padding on the right does not add a column.
@export_range(1, 512, 1) var columns: int = 8

## How many rows.
@export_range(1, 512, 1) var rows: int = 8

@export_group("Facing")

## How many directions the sheet draws: 1, 2, 4 or 8.
## Not free-form: any other number gives a facing calculation that lands between two rows.
@export_enum("1", "2", "4", "8") var directions: int = 2

## Whether the left-facing frames are the right-facing ones, flipped.
## Saves drawing three directions on a four- or eight-way sheet; [method DotPlayerSpriteFacing.resolve]
## returns the flip so nothing downstream knows which were drawn.
@export var mirror_left: bool = true

## The direction index the sheet starts at. 0 is usually "down" or "right".
@export_range(0, 7, 1) var first_direction: int = 0

@export_group("Drawing")

## Where the sprite's origin sits within a frame, as a fraction.
## Bottom centre (0.5, 1.0) is the default: a sprite anchored at its middle sinks into the floor
## by half its height, which reads as a collision bug.
@export var anchor: Vector2 = Vector2(0.5, 1.0)

## Integer scale. Fractional scaling of pixel art is the thing to avoid here.
@export_range(1, 16, 1) var pixel_scale: int = 1

## Whether the texture is filtered. Off for pixel art.
@export var filtered: bool = false

## Z ordering relative to the character's node.
@export_range(-4096, 4096, 1) var z_offset: int = 0

@export_group("Layers")

## slot id -> overlay sheet path. Drawn over the base, cut identically.
## An overlay on a different grid cannot share the base's frame index, and every animation would
## need a second table.
@export var layers: Dictionary = {}

## slot id -> draw order. Higher is in front.
@export var layer_order: Dictionary = {}

@export_group("Tinting")

## How many tint channels. 0 is none, 1 is [member CanvasItem.modulate].
## Above one needs a shader, which this addon does not ship (a shader is art).
@export_range(0, 8, 1) var tint_channels: int = 1

@export var tint_parameter: String = "dot_tint_"

@export_group("Anything else")

@export var attributes: Dictionary = {}


static func make(p_id: StringName, p_sheet: String = "") -> DotPlayerSpriteDef:
	var s := DotPlayerSpriteDef.new()
	s.id = p_id
	s.display_name = String(p_id).capitalize()
	s.sheet = p_sheet
	return s


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A sprite with no id.")

	if frame_size.x <= 0 or frame_size.y <= 0:
		return DotResult.fail(
			DotError.CODE_INVALID, "'%s' has a frame of no size." % String(id)
		)

	if not [1, 2, 4, 8].has(direction_count()):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' draws %d directions." % [String(id), direction_count()],
			"A sheet is cut for 1, 2, 4 or 8; anything else lands the facing "
			+ "calculation between two rows."
		)

	if direction_count() > columns * rows:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' has %d directions and only %d cells."
			% [String(id), direction_count(), columns * rows]
		)

	for slot: Variant in layers.keys():
		if str(layers[slot]) == "":
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Layer '%s' on '%s' names no sheet." % [str(slot), String(id)]
			)

	return DotResult.success(null)


## The number this definition's [member directions] enum stands for.
func direction_count() -> int:
	match directions:
		0: return 1
		1: return 2
		2: return 4
		3: return 8
	return 1


## Which cell in the sheet, given a row, a direction and a frame.
## Clamped, not wrapped: a frame past the end of a row is a content error, and wrapping draws the
## start of the animation mid-way, which reads as a stutter instead of a mistake.
func frame_index(row: int, direction: int, frame: int) -> int:
	var d := direction_count()
	var effective_row := clampi(row * d + direction, 0, maxi(0, rows - 1))
	var column := clampi(frame, 0, maxi(0, columns - 1))
	return effective_row * columns + column


## The pixel rectangle of a cell.
func frame_rect(index: int) -> Rect2i:
	var safe := clampi(index, 0, maxi(0, columns * rows - 1))
	return Rect2i(
		Vector2i(safe % columns, safe / columns) * frame_size,
		frame_size
	)


## The offset from the node's origin to the frame's top-left, given the anchor.
func draw_offset() -> Vector2:
	return -Vector2(frame_size) * anchor * float(pixel_scale)


func has_layer(slot: StringName) -> bool:
	return layers.has(String(slot))


func layer_sheet(slot: StringName) -> String:
	return str(layers.get(String(slot), ""))


func layer_z(slot: StringName) -> int:
	return int(layer_order.get(String(slot), 0))


## Every slot, in draw order. Ties broken by name so two machines agree.
func layer_slots() -> Array[StringName]:
	var out: Array[StringName] = []

	for key: Variant in layers.keys():
		out.append(StringName(str(key)))

	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var za := layer_z(a)
		var zb := layer_z(b)
		if za != zb:
			return za < zb
		return String(a) < String(b)
	)

	return out


## Every texture path this definition needs.
func content_paths() -> PackedStringArray:
	var out := PackedStringArray()

	if sheet != "":
		out.append(sheet)

	for slot: Variant in layers.keys():
		var path := str(layers[slot])
		if path != "" and not out.has(path):
			out.append(path)

	return out


func describe() -> String:
	return "%s: %dx%d frames, %dx%d grid, %d directions, %d layers" % [
		String(id), frame_size.x, frame_size.y, columns, rows,
		direction_count(), layers.size(),
	]


func _to_string() -> String:
	return "DotPlayerSpriteDef(%s)" % describe()
