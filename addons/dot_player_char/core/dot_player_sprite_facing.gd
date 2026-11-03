class_name DotPlayerSpriteFacing
extends RefCounted

## Which way a 2D character is drawn, from which way it is actually pointing.
## Returns the mirror flag with the index, so callers need not know which directions the
## sheet derives. Angles: radians in [code]-PI..PI[/code], zero along +X, anticlockwise.

## One direction: the row offset, and whether to draw it flipped.
class Facing extends RefCounted:
	var index: int = 0
	var flip_h: bool = false

	func _init(p_index: int = 0, p_flip: bool = false) -> void:
		index = p_index
		flip_h = p_flip

	func describe() -> String:
		return "%d%s" % [index, " flipped" if flip_h else ""]


## Resolves an angle to a row offset and a flip.
static func resolve(angle: float, count: int, mirror: bool = true, first: int = 0) -> Facing:
	if count <= 1:
		return Facing.new(0, false)

	var wrapped := wrapf(angle, -PI, PI)

	if count == 2:
		# Left and right, which is what a side-on game has. The mirror flag does the
		# work; there is only ever one drawn direction.
		var facing_left := absf(wrapped) > PI * 0.5
		if mirror:
			return Facing.new(first, facing_left)
		return Facing.new(first + (1 if facing_left else 0), false)

	# Sectors are offset by half a sector so an exact cardinal lands mid-sector, not on
	# a boundary where it would flicker between two frames.
	var sector := TAU / float(count)
	var raw := int(floor((wrapf(angle, 0.0, TAU) + sector * 0.5) / sector)) % count

	if not mirror:
		return Facing.new(first + raw, false)

	# Mirrored: directions past halfway are the reflection of their counterpart.
	var half := count / 2

	if raw <= half:
		return Facing.new(first + raw, false)

	return Facing.new(first + (count - raw), true)


## How many rows a mirrored sheet actually has to draw.
## Eight directions mirrored need only five; more rows are never indexed.
static func drawn_directions(count: int, mirror: bool) -> int:
	if count <= 1:
		return 1

	if not mirror:
		return count

	if count == 2:
		return 1

	return count / 2 + 1


## An angle from a movement vector, or a fallback when it is not moving.
## A zero velocity has no angle, so the previous facing is passed through rather than
## snapping to a default.
static func angle_of(velocity: Vector2, previous: float) -> float:
	if velocity.length_squared() < 0.0001:
		return previous

	return wrapf(velocity.angle(), -PI, PI)
