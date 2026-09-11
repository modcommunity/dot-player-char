@tool
class_name DotPlayerCharDef
extends Resource

## One character: how big it is, what it is called, and which content it names.
##
## [b]The body metrics are the reason this is not just a cosmetic.[/b] A character's
## height decides the collision capsule, the eye height decides where the camera and the
## muzzle are, the crouch height decides whether it fits under a vent — and every one of
## those is read by a different addon. Keeping them in the same document as the model id
## is what stops a game shipping a character that is visibly two metres tall and
## collides as if it were 1.8.
##
## Everything else is an id. A server has to be able to say "that is not a legal
## character" without loading a mesh, which is dot-user-avatar's rule and dot-loadout's
## and dot-player-class's, for the same reason.

## The name everything else uses.
@export var id: StringName = &""

@export var display_name: String = ""

@export_multiline var description: String = ""

@export_group("Body")

## Standing height, in metres. In 2D, in pixels.
##
## [b]Read by at least four things[/b]: the collision capsule, the crouch test, the
## camera height and the hitbox layout. One number, one place.
@export_range(0.1, 10.0, 0.01, "or_greater") var height: float = 1.8

## Height while crouched.
@export_range(0.1, 10.0, 0.01, "or_greater") var crouch_height: float = 1.0

## Capsule radius.
@export_range(0.05, 5.0, 0.01, "or_greater") var radius: float = 0.35

## Eye height above the feet, standing.
##
## Not a fraction of [member height]: the fraction is different for a tall thin
## character and a short wide one, and a game that computed it would have every
## character's camera in slightly the wrong place.
@export_range(0.05, 10.0, 0.01, "or_greater") var eye_height: float = 1.65

## Eye height while crouched.
@export_range(0.05, 10.0, 0.01, "or_greater") var crouch_eye_height: float = 0.9

## Kilograms, for anything that pushes or is pushed.
@export_range(1.0, 10000.0, 1.0) var mass: float = 80.0

## Multiplier on how big a target this character is, for a game that wants one.
##
## Separate from [member radius] because a hitbox is not a collision hull: a character
## can be harder to hit than it is to walk into, which is how an asymmetric mode makes a
## large character viable.
@export_range(0.1, 5.0, 0.01) var hitbox_scale: float = 1.0

@export_group("Content ids")

## dot-player-char-model id, for a 3D game.
@export var model_id: StringName = &""

## dot-player-char-sprite id, for a 2D game.
@export var sprite_id: StringName = &""

## dot-player-char-animations set id.
@export var animation_set: StringName = &""

## dot-audio voice set id.
@export var voice_set: StringName = &""

## dot-audio footstep set id, if this character sounds different from the default.
@export var footstep_set: StringName = &""

@export_group("Customisation")

## Named slots a player may change: [code]{"hat": ["none", "cap"], ...}[/code].
##
## Values are ids, never scenes. A slot with no options is a slot nothing can be put in,
## which is how a character is made fixed without a second flag.
@export var slots: Dictionary = {}

## How many tintable colour channels this character has.
##
## Zero means it cannot be recoloured. Bounded on purpose: a document that may carry an
## arbitrary number of colours is a document a client can make arbitrarily large, and a
## server validating one has to have a limit to check against.
@export_range(0, 8, 1) var colour_channels: int = 0

@export_group("Availability")

## Which teams may use it. Empty means all.
@export var teams: Array[StringName] = []

## Which classes may use it. Empty means all.
@export var classes: Array[StringName] = []

## An entitlement id, checked by the game rather than here.
@export var requires_entitlement: StringName = &""

@export var selectable: bool = true

## Open-ended, the way the other definitions in this family are.
@export var attributes: Dictionary = {}


static func make(
	p_id: StringName,
	p_height: float = 1.8,
	p_radius: float = 0.35
) -> DotPlayerCharDef:
	var c := DotPlayerCharDef.new()
	c.id = p_id
	c.display_name = String(p_id).capitalize()
	c.height = p_height
	c.radius = p_radius
	c.crouch_height = p_height * 0.55
	c.eye_height = p_height * 0.92
	c.crouch_eye_height = c.crouch_height * 0.9
	return c


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A character with no id.")

	if crouch_height > height:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' is %.2f tall and %.2f crouched." % [String(id), height, crouch_height],
			"Crouching would make it bigger, so it would get stuck coming out of every "
			+ "gap it crouched into."
		)

	if eye_height > height:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' has its eyes %.2f above the ground and is %.2f tall."
			% [String(id), eye_height, height],
			"The camera would sit above the collision hull, so the player would see "
			+ "over walls they are standing behind."
		)

	if crouch_eye_height > crouch_height:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' has its crouched eyes above its crouched height." % String(id)
		)

	if radius * 2.0 > height:
		# Not refused: a wide low character is legal and some games want one. Worth
		# saying, because a capsule wider than it is tall behaves as a sphere and
		# stops climbing stairs.
		DotLog.debug(
			"player.char",
			"a character is wider than it is tall; its capsule is effectively a sphere",
			{"char": String(id)}
		)

	return DotResult.success(null)


func allows(team: StringName, player_class: StringName) -> bool:
	if not selectable:
		return false

	if not teams.is_empty() and team != &"" and not teams.has(team):
		return false

	if not classes.is_empty() and player_class != &"" and not classes.has(player_class):
		return false

	return true


## The options a slot offers, or an empty list.
func slot_options(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var raw: Variant = slots.get(String(slot), null)

	if raw is Array:
		for v: Variant in raw as Array:
			out.append(StringName(str(v)))

	return out


func has_slot(slot: StringName) -> bool:
	return slots.has(String(slot))


func slot_names() -> Array[StringName]:
	var out: Array[StringName] = []

	for key: Variant in slots.keys():
		out.append(StringName(str(key)))

	out.sort()
	return out


## The eye height for a given stance, which is the question a camera actually asks.
func eye_for(crouched: bool) -> float:
	return crouch_eye_height if crouched else eye_height


func height_for(crouched: bool) -> float:
	return crouch_height if crouched else height


## Builds the collision shape this character should have.
##
## A capsule because that is what every character controller in this family assumes —
## a box catches on corners and a cylinder has no standard Godot character body. The
## returned shape is fresh each time: a [Shape3D] handed to two bodies is shared by
## them, and resizing one resizes the other.
func capsule_3d(crouched: bool = false) -> CapsuleShape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(radius * 2.0 + 0.01, height_for(crouched))
	return shape


func capsule_2d(crouched: bool = false) -> CapsuleShape2D:
	var shape := CapsuleShape2D.new()
	shape.radius = radius
	shape.height = maxf(radius * 2.0 + 0.01, height_for(crouched))
	return shape


func attribute(key: String, fallback: Variant = null) -> Variant:
	return attributes.get(key, fallback)


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"height": height,
		"crouch_height": crouch_height,
		"radius": radius,
		"eye": eye_height,
		"crouch_eye": crouch_eye_height,
		"model": String(model_id),
		"sprite": String(sprite_id),
		"anims": String(animation_set),
		"channels": colour_channels,
		"slots": slots.duplicate(true),
	}


static func from_dict(d: Dictionary) -> DotPlayerCharDef:
	var c := DotPlayerCharDef.new()
	c.id = StringName(str(d.get("id", "")))
	c.display_name = str(d.get("name", String(c.id).capitalize()))
	c.height = float(d.get("height", 1.8))
	c.crouch_height = float(d.get("crouch_height", 1.0))
	c.radius = float(d.get("radius", 0.35))
	c.eye_height = float(d.get("eye", 1.65))
	c.crouch_eye_height = float(d.get("crouch_eye", 0.9))
	c.model_id = StringName(str(d.get("model", "")))
	c.sprite_id = StringName(str(d.get("sprite", "")))
	c.animation_set = StringName(str(d.get("anims", "")))
	c.colour_channels = int(d.get("channels", 0))

	var s: Variant = d.get("slots", {})
	c.slots = (s as Dictionary).duplicate(true) if s is Dictionary else {}

	return c


func describe() -> String:
	return "%s: %.2f m (%.2f crouched), r %.2f, eyes %.2f%s" % [
		String(id), height, crouch_height, radius, eye_height,
		"" if colour_channels == 0 else ", %d colours" % colour_channels,
	]


func _to_string() -> String:
	return "DotPlayerCharDef(%s)" % describe()
