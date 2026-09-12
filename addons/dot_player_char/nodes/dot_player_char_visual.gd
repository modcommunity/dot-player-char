class_name DotPlayerCharVisual
extends Node

## The seam between "who this character is" and "what is drawn".
##
## [b]One abstract node, three implementations, and the reason none of them is
## required.[/b] [DotPlayerModelVisual] builds a 3D rig, [DotPlayerSpriteVisual] builds
## a 2D one, and a game with its own art pipeline writes a third — and a project that
## deletes the two it does not want still has this one. A game that ships no art at all still gets the metrics, the
## customisation document and the validation, which is most of the value.
##
## Overriding is four methods, and the first is the only compulsory one.

## Whether this visual is currently being drawn.
##
## Set by [DotPlayerChar] rather than by the game: a character's first-person self and
## its third-person body are two visuals under one player, and exactly one of them being
## visible to the local player is the whole reason this is a property and not a call.
@export var visual_enabled: bool = true


## Called when the character, or the look, changes. Must be safe to call repeatedly.
##
## [b]Repeatedly matters.[/b] A player editing their character in a menu calls this
## several times a second, so an implementation that appends rather than replaces grows
## a hat every frame — which is the bug dot-user-avatar's builder documents having
## avoided by clearing each slot before rebuilding it.
func apply_char(_def: DotPlayerCharDef, _look: DotPlayerCharLook) -> void:
	pass


## Called when the stance changes: standing, crouched, prone.
##
## Separate from [method apply_char] because it happens every time somebody ducks and
## rebuilding a rig for that would be absurd.
func set_stance(_crouched: bool) -> void:
	pass


## Called when the character should or should not be drawn for the local viewer.
##
## Not the same as [member visual_enabled]: this is "the player is dead" or "the player
## is behind a wall and interest management has dropped them", while the property is
## "this is the wrong visual for the current camera".
func set_shown(_shown: bool) -> void:
	pass


## Where this visual thinks the eyes are, if it knows better than the definition.
##
## Returns a negative number by default, meaning "no opinion", and [DotPlayerChar] then
## uses the definition's number. A rig with a real head bone can answer properly, which
## is what makes a first-person camera line up with a third-person model.
func eye_offset() -> float:
	return -1.0


## An attachment point by name, for a weapon, an effect or a nameplate.
##
## Null when the visual has no such point, which every caller must handle: a game
## switching from models to sprites loses every bone, and a weapon that assumed one
## would crash on the first frame of the 2D build.
func attachment(_point: StringName) -> Node:
	return null


func attachment_names() -> Array[StringName]:
	return []


func describe_lines() -> PackedStringArray:
	return PackedStringArray(["%s%s" % [
		get_class(), "" if visual_enabled else " (disabled)"
	]])
