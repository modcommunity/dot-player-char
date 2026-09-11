@tool
class_name DotPlayerCharCatalogue
extends Resource

## Every character a session has.

const CHANNEL := "player.char"

@export var id: StringName = &""

@export var characters: Array[DotPlayerCharDef] = []

@export var default_char: StringName = &""

var _by_id: Dictionary = {}
var _built: bool = false


func build() -> DotResult:
	_by_id.clear()

	if characters.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "A catalogue with no characters.")

	for c in characters:
		if c == null:
			return DotResult.fail(DotError.CODE_INVALID, "A null character.")

		var valid := c.validate()

		if not valid.ok:
			return valid.wrap("This character catalogue was not built")

		if _by_id.has(c.id):
			return DotResult.fail(
				DotError.CODE_INVALID, "Two characters are called '%s'." % String(c.id)
			)

		_by_id[c.id] = c

	if default_char != &"" and not _by_id.has(default_char):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The default character '%s' is not in the catalogue." % String(default_char)
		)

	_built = true
	return DotResult.success(null)


func _ensure_built() -> void:
	if not _built or _by_id.size() != characters.size():
		var res := build()
		if not res.ok:
			DotLog.error(CHANNEL, "character catalogue unusable", {"why": res.error.message})


func has_char(char_id: StringName) -> bool:
	_ensure_built()
	return _by_id.has(char_id)


func get_char(char_id: StringName) -> DotPlayerCharDef:
	_ensure_built()
	return _by_id.get(char_id, null)


func ids() -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for c in characters:
		if c != null:
			out.append(c.id)

	return out


func ids_for(team: StringName, player_class: StringName = &"") -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for c in characters:
		if c != null and c.allows(team, player_class):
			out.append(c.id)

	return out


## Never null for a built catalogue. Same reasoning as dot-player-class's.
func fallback_for(team: StringName = &"", player_class: StringName = &"") -> DotPlayerCharDef:
	_ensure_built()

	if default_char != &"" and _by_id.has(default_char):
		var declared: DotPlayerCharDef = _by_id[default_char]
		if declared.allows(team, player_class):
			return declared

	for c in characters:
		if c != null and c.allows(team, player_class):
			return c

	for c in characters:
		if c != null:
			return c

	return null


func describe_lines() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()
	out.append("characters (%s): %d" % [String(id), characters.size()])

	for c in characters:
		if c != null:
			out.append("  " + c.describe())

	return out


func describe() -> String:
	return "DotPlayerCharCatalogue(%s, %d)" % [String(id), characters.size()]


func _to_string() -> String:
	return describe()


# --- Presets ----------------------------------------------------------------

## One character with the metrics a first-person shooter assumes.
##
## 1.8 m standing, 1.0 m crouched, 0.35 m radius, eyes at 1.65 — the numbers behind
## every corridor, doorway and vent anybody has ever built for this genre. A game that
## changes them changes what every existing map means, which is worth knowing before
## changing them.
static func standard() -> DotPlayerCharCatalogue:
	var cat := DotPlayerCharCatalogue.new()
	cat.id = &"standard"

	var one := DotPlayerCharDef.make(&"standard", 1.8, 0.35)
	one.display_name = "Standard"
	one.crouch_height = 1.0
	one.eye_height = 1.65
	one.crouch_eye_height = 0.9
	one.colour_channels = 2
	one.slots = {"head": ["none", "cap", "helmet"], "back": ["none", "pack"]}

	cat.characters = [one]
	cat.default_char = &"standard"
	var _res := cat.build()
	return cat


## Three body types, which is what a game with visible characters actually needs.
##
## The metrics differ and that is the point: a small character is genuinely harder to
## hit and genuinely fits through gaps a large one does not, and a game whose three
## characters have identical hulls has three skins rather than three characters.
static func three_builds() -> DotPlayerCharCatalogue:
	var cat := DotPlayerCharCatalogue.new()
	cat.id = &"three_builds"

	var light := DotPlayerCharDef.make(&"light", 1.65, 0.30)
	light.display_name = "Light"
	light.description = "Small. Fits where the others do not, and is harder to hit."
	light.mass = 62.0
	light.hitbox_scale = 0.92
	light.colour_channels = 2

	var medium := DotPlayerCharDef.make(&"medium", 1.80, 0.35)
	medium.display_name = "Medium"
	medium.description = "The baseline every map was built around."
	medium.mass = 80.0
	medium.colour_channels = 2

	var heavy := DotPlayerCharDef.make(&"heavy", 2.00, 0.42)
	heavy.display_name = "Heavy"
	heavy.description = "Large. Blocks a doorway, and is easier to hit."
	heavy.mass = 115.0
	heavy.hitbox_scale = 1.1
	heavy.colour_channels = 2

	for c in [light, medium, heavy]:
		c.slots = {"head": ["none", "cap", "helmet"], "back": ["none", "pack"]}

	cat.characters = [light, medium, heavy]
	cat.default_char = &"medium"
	var _res := cat.build()
	return cat


## A 2D character, in pixels rather than metres.
static func sprite_2d(p_height: float = 48.0) -> DotPlayerCharCatalogue:
	var cat := DotPlayerCharCatalogue.new()
	cat.id = &"sprite_2d"

	var one := DotPlayerCharDef.make(&"sprite", p_height, p_height * 0.3)
	one.display_name = "Sprite"
	one.crouch_height = p_height * 0.6
	one.eye_height = p_height * 0.8
	one.crouch_eye_height = p_height * 0.5
	one.colour_channels = 1

	cat.characters = [one]
	cat.default_char = &"sprite"
	var _res := cat.build()
	return cat


static func presets() -> Dictionary:
	return {
		&"standard": Callable(DotPlayerCharCatalogue, "standard"),
		&"three_builds": Callable(DotPlayerCharCatalogue, "three_builds"),
		&"sprite_2d": Callable(DotPlayerCharCatalogue, "sprite_2d"),
	}


static func preset(p_id: StringName) -> DotPlayerCharCatalogue:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	return fn.call() as DotPlayerCharCatalogue
