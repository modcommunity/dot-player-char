class_name DotPlayerSpriteFacing
extends RefCounted

## Which way a 2D character is drawn, from which way it is actually pointing.
##
## [b]Static, and it returns the mirror flag with the index.[/b] A four-way sheet that
## mirrors is five drawn directions and three derived ones, and a caller that had to
## work out the flip itself would have to know which three — so the answer is both
## numbers together and nothing downstream needs to know how the sheet was drawn.
##
## Angles are the same convention as everything else in this family: radians, wrapped to
## [code]-PI..PI[/code], zero pointing along +X, increasing anticlockwise.

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

	# Four- or eight-way: the circle is divided into `count` sectors, offset by half a
	# sector so that an exact cardinal angle lands in the middle of its sector rather
	# than on the boundary between two — which is what makes a character walking due
	# north flicker between two frames.
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
##
## Useful to an artist and to a validator: a sheet claiming eight directions with
## mirroring on only needs five, and one that drew all eight has three rows nothing will
## ever index.
static func drawn_directions(count: int, mirror: bool) -> int:
	if count <= 1:
		return 1

	if not mirror:
		return count

	if count == 2:
		return 1

	return count / 2 + 1


## An angle from a movement vector, or a fallback when it is not moving.
##
## The fallback matters: a character that stopped should keep facing where it was, and a
## velocity of zero has no angle at all. Passing the previous facing through rather than
## snapping to a default is the difference between a character standing still and one
## that turns to face south every time it stops.
static func angle_of(velocity: Vector2, previous: float) -> float:
	if velocity.length_squared() < 0.0001:
		return previous

	return wrapf(velocity.angle(), -PI, PI)
