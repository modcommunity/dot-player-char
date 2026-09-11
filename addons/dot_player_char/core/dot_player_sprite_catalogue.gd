@tool
class_name DotPlayerSpriteCatalogue
extends Resource

## Every 2D character sheet a session has, by id.

const CHANNEL := "player.sprite"

@export var id: StringName = &""

@export var sprites: Array[DotPlayerSpriteDef] = []

@export var default_sprite: StringName = &""

var _by_id: Dictionary = {}
var _built: bool = false


func build() -> DotResult:
	_by_id.clear()

	if sprites.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "A catalogue with no sprites.")

	for s in sprites:
		if s == null:
			return DotResult.fail(DotError.CODE_INVALID, "A null sprite.")

		var valid := s.validate()

		if not valid.ok:
			return valid.wrap("This sprite catalogue was not built")

		if _by_id.has(s.id):
			return DotResult.fail(
				DotError.CODE_INVALID, "Two sprites are called '%s'." % String(s.id)
			)

		_by_id[s.id] = s

	if default_sprite != &"" and not _by_id.has(default_sprite):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The default sprite '%s' is not in the catalogue." % String(default_sprite)
		)

	_built = true
	return DotResult.success(null)


func _ensure_built() -> void:
	if not _built or _by_id.size() != sprites.size():
		var res := build()
		if not res.ok:
			DotLog.error(CHANNEL, "sprite catalogue unusable", {"why": res.error.message})


func has_sprite(sprite_id: StringName) -> bool:
	_ensure_built()
	return _by_id.has(sprite_id)


func get_sprite(sprite_id: StringName) -> DotPlayerSpriteDef:
	_ensure_built()
	return _by_id.get(sprite_id, null)


func ids() -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for s in sprites:
		if s != null:
			out.append(s.id)

	return out


func fallback() -> DotPlayerSpriteDef:
	_ensure_built()

	if default_sprite != &"" and _by_id.has(default_sprite):
		return _by_id[default_sprite]

	for s in sprites:
		if s != null:
			return s

	return null


func content_paths() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()

	for s in sprites:
		if s == null:
			continue

		for path in s.content_paths():
			if not out.has(path):
				out.append(path)

	return out


func describe_lines() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()
	out.append("sprites (%s): %d" % [String(id), sprites.size()])

	for s in sprites:
		if s != null:
			out.append("  " + s.describe())

	return out


func describe() -> String:
	return "DotPlayerSpriteCatalogue(%s, %d)" % [String(id), sprites.size()]


func _to_string() -> String:
	return describe()


## A side-on sheet: two directions, mirrored, bottom-anchored.
##
## The platformer and the side-scroller shape. No sheet path — the art is the game's.
static func side_on(p_id: StringName = &"side", p_frame: Vector2i = Vector2i(32, 32)) -> DotPlayerSpriteCatalogue:
	var cat := DotPlayerSpriteCatalogue.new()
	cat.id = p_id

	var s := DotPlayerSpriteDef.make(p_id)
	s.frame_size = p_frame
	s.directions = 1
	s.mirror_left = true
	s.anchor = Vector2(0.5, 1.0)
	s.columns = 8
	s.rows = 8

	cat.sprites = [s]
	cat.default_sprite = p_id
	var _res := cat.build()
	return cat


## A top-down sheet: eight directions, mirrored, centre-anchored.
static func top_down(p_id: StringName = &"top_down", p_frame: Vector2i = Vector2i(48, 48)) -> DotPlayerSpriteCatalogue:
	var cat := DotPlayerSpriteCatalogue.new()
	cat.id = p_id

	var s := DotPlayerSpriteDef.make(p_id)
	s.frame_size = p_frame
	s.directions = 3
	s.mirror_left = true
	s.anchor = Vector2(0.5, 0.5)
	s.columns = 8
	s.rows = 40

	cat.sprites = [s]
	cat.default_sprite = p_id
	var _res := cat.build()
	return cat
