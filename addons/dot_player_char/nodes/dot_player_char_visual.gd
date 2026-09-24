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

## Where the drawn node hangs. Unset, the nearest ancestor of the kind that can place it —
## a [Node3D] for a 3D visual, a [Node2D] for a 2D one — which is the player body in every
## game shaped the ordinary way.
##
## [b]Why the drawn node does not simply stay a child of this one.[/b] A visual is a plain
## [Node]: it is a behaviour, not a place. A [Node3D] whose parent is not a [Node3D] inherits
## nobody's transform — it is placed in world space — so a rig kept here stood at the world
## origin whatever its player did, and a 2D sheet stood at the canvas origin the same way.
## game-playground drew every body at (0, 0, 0) for as long as it had bodies, hidden only
## because its lobby spawn is the origin, and worked round it from the game. The drawn node
## is moved onto the anchor instead, and this visual keeps its reference, so everything it
## offers — hiding, mounts, tints, a rebuild — still reaches it.
@export var anchor_ref: DotNodeRef = null

## Not [code]CHANNEL[/code]: the parent chain already has one.
const SEAT_CHANNEL := "player.char"

var _seat_pending := false


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


# --- Where the drawn node hangs ------------------------------------------------

## The node this visual draws into: what gets seated on the anchor. Null for a visual that
## draws nothing of its own, which is the default.
func _drawn_node() -> Node:
	return null


## The class an anchor must be for the drawn node to inherit its place from it.
func _anchor_class() -> StringName:
	return &""


## The node the drawn node hangs off, or null when there is none — a visual used outside a
## spatial scene, which keeps its drawn node as its own child exactly as before.
func anchor_node() -> Node:
	if not is_inside_tree():
		return null

	if anchor_ref != null:
		return anchor_ref.resolve_or_null(self, SEAT_CHANNEL)

	var kind := _anchor_class()

	if kind == &"":
		return null

	var at := get_parent()

	while at != null and not at.is_class(kind):
		at = at.get_parent()

	return at


## Whether the drawn node is on its anchor, which is what places it.
func is_seated() -> bool:
	var drawn := _drawn_node()
	var anchor := anchor_node()
	return drawn != null and anchor != null and drawn.get_parent() == anchor


## Puts the drawn node on the anchor. Returns whether it is there now.
##
## Safe to call at any time. [b]It defers when the anchor is still readying its
## children[/b] — the ordinary case when a whole player is added at once and this runs from
## this visual's own [code]_ready[/code] — because Godot refuses [code]add_child[/code] on a
## node that is part-way through setting up the ones it has, and says so with an error rather
## than a result. Deferred, it lands before the frame is drawn.
func seat() -> bool:
	var drawn := _drawn_node()

	if drawn == null or not is_instance_valid(drawn):
		return false

	var anchor := anchor_node()

	if anchor == null:
		return false

	if drawn.get_parent() == anchor:
		return true

	if not anchor.is_node_ready():
		_seat_later()
		return false

	# Not keeping the global transform. Under a plain Node the drawn node's local transform
	# WAS its global one, so keeping it would carry the world origin over as an offset from
	# the player — the bug, moved one level down.
	if drawn.get_parent() == null:
		anchor.add_child(drawn)
	else:
		drawn.reparent(anchor, false)

	DotLog.debug(SEAT_CHANNEL, "the drawn node hangs off its anchor", {
		"visual": String(name), "anchor": String(anchor.name),
	})
	return true


func _seat_later() -> void:
	if _seat_pending:
		return
	_seat_pending = true
	_seat_deferred.call_deferred()


func _seat_deferred() -> void:
	_seat_pending = false
	if is_inside_tree():
		var _seated := seat()


## Brings a seated drawn node back under this visual once it has left the tree, so a visual
## taken off a player does not leave its body standing there. Deferred for the reason
## [method seat] is: a node leaving the tree cannot rearrange its parent's children.
func _unseat_deferred() -> void:
	if is_inside_tree():
		return

	var drawn := _drawn_node()

	if drawn != null and is_instance_valid(drawn) and drawn.get_parent() != self:
		if drawn.get_parent() != null:
			drawn.get_parent().remove_child(drawn)
		add_child(drawn)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			# Not on the first entry: `_ready` has not built the drawn node yet, and seats it
			# itself. This is for a visual moved to another player, or re-added.
			if is_node_ready():
				_seat_later()
		NOTIFICATION_EXIT_TREE:
			var drawn := _drawn_node()
			if drawn != null and drawn.get_parent() != self:
				_unseat_deferred.call_deferred()
		NOTIFICATION_PREDELETE:
			# A seated drawn node is somebody else's child now, so it would outlive this
			# visual: a body left standing in the world for a player who is gone.
			var drawn := _drawn_node()
			if drawn != null and is_instance_valid(drawn) and drawn.get_parent() != self:
				drawn.queue_free()


func describe_lines() -> PackedStringArray:
	return PackedStringArray(["%s%s" % [
		get_class(), "" if visual_enabled else " (disabled)"
	]])
