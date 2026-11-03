class_name DotPlayerCharVisual
extends Node

## The seam between "who this character is" and "what is drawn".
## Implemented by [DotPlayerModelVisual] (3D) and [DotPlayerSpriteVisual] (2D); a game with its own art
## writes a third, and a game with no art still gets the metrics, customisation and validation.

## Whether this visual is currently being drawn.
## Set by [DotPlayerChar]: first-person self and third-person body are two visuals, and only one shows.
@export var visual_enabled: bool = true

## Where the drawn node hangs. Unset, the nearest ancestor that can place it ([Node3D] or [Node2D]).
## The drawn node moves onto the anchor because a visual is a plain [Node]: a [Node3D] under it would
## sit at the world origin whatever its player did. This visual keeps the reference.
@export var anchor_ref: DotNodeRef = null

## Not [code]CHANNEL[/code]: the parent chain already has one.
const SEAT_CHANNEL := "player.char"

var _seat_pending := false


## Called when the character, or the look, changes. Must be safe to call repeatedly.
## An editing menu calls it several times a second, so an implementation that appends rather than
## replaces grows a hat every frame.
func apply_char(_def: DotPlayerCharDef, _look: DotPlayerCharLook) -> void:
	pass


## Called when the stance changes: standing, crouched, prone.
## Separate from [method apply_char] because rebuilding a rig on every duck would be absurd.
func set_stance(_crouched: bool) -> void:
	pass


## Called when the character should or should not be drawn for the local viewer.
## Not [member visual_enabled]: this is dead or interest-managed away, that is the wrong visual
## for the current camera.
func set_shown(_shown: bool) -> void:
	pass


## Where this visual thinks the eyes are, if it knows better than the definition.
## Negative (the default) means no opinion and [DotPlayerChar] uses the definition's number; a rig
## with a head bone answers so a first-person camera lines up with the model.
func eye_offset() -> float:
	return -1.0


## An attachment point by name, for a weapon, an effect or a nameplate.
## Null when the visual has no such point, which every caller must handle: a sprite visual has no
## bones.
func attachment(_point: StringName) -> Node:
	return null


func attachment_names() -> Array[StringName]:
	return []


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
## Defers while the anchor is still readying its children, because Godot refuses [code]add_child[/code]
## there with an error; deferred, it lands before the frame is drawn.
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
