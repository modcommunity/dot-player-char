class_name DotPlayerAnimSpriteSink
extends DotPlayerAnimSink

## Drives a sprite sheet. The 2D sink.
##
## [b]Duck-typed on purpose.[/b] It calls [code]set_row[/code] and [code]set_frame[/code]
## on whatever it is pointed at. [DotPlayerSpriteVisual] is in this same addon and could
## be named directly — the reason not to is that a game with its own sprite node, its
## own [AnimatedSprite2D] wrapper or its own tilemap-based character gets this whole
## animation layer by offering two methods, and nothing here needs to know which it got.

const SINK_CHANNEL := "player.anim"

## What to drive. Empty uses the first sibling or descendant that has [code]set_row[/code].
@export var target_ref: DotNodeRef = null

var _target: Node = null
var _row: int = -1
var _frame: int = -1


func _ready() -> void:
	_resolve()


func target() -> Node:
	if _target == null or not is_instance_valid(_target):
		_resolve()

	return _target


func is_ready_to_play() -> bool:
	return target() != null


func play(clip: DotPlayerAnimClip, elapsed: float) -> void:
	advance_to(clip, elapsed)


func advance_to(clip: DotPlayerAnimClip, elapsed: float) -> void:
	var t := target()

	if t == null or clip == null:
		return

	var frame := clip.frame_at(elapsed)

	# Only on a change: a sprite node's setters are cheap but not free, and this runs
	# once a frame for every visible character.
	if clip.row != _row:
		_row = clip.row
		t.call("set_row", clip.row)

	if frame != _frame:
		_frame = frame
		t.call("set_frame", frame)


func stop() -> void:
	_row = -1
	_frame = -1


func _resolve() -> void:
	if target_ref != null:
		_target = target_ref.resolve_or_null(self, SINK_CHANNEL)
		return

	_target = _find(self)

	if _target == null and get_parent() != null:
		# Direct siblings only, never the parent's whole subtree. A recursive search
		# upward finds another player's node in a scene that holds several — and the
		# symptom is one character driving somebody else's animation, which is not
		# where anybody would look. Anything further away is what player_ref is for.
		for sibling in get_parent().get_children():
			if sibling != self and sibling.has_method("set_row") \
					and sibling.has_method("set_frame"):
				_target = sibling
				break


func _find(root: Node) -> Node:
	for child in root.get_children():
		if child.has_method("set_row") and child.has_method("set_frame"):
			return child

		var deeper := _find(child)

		if deeper != null:
			return deeper

	return null


func describe_lines() -> PackedStringArray:
	return PackedStringArray(["sprite sink: %s, row %d frame %d" % [
		"connected" if target() != null else "NOT FOUND", _row, _frame
	]])
