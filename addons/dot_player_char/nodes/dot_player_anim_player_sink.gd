class_name DotPlayerAnimPlayerSink
extends DotPlayerAnimSink

## Drives an [AnimationPlayer]. The 3D sink.

const SINK_CHANNEL := "player.anim"

## Where the [AnimationPlayer] is. Empty searches this node's descendants and siblings.
@export var player_ref: DotNodeRef = null

## Whether a clip the [AnimationPlayer] does not have is reported.
##
## On. A missing clip means the character keeps playing whatever it was, which looks
## like the animation system not working at all rather than like one absent clip — and
## once per clip is cheap because [member _warned] remembers.
@export var warn_on_missing: bool = true

var _player: AnimationPlayer = null
var _playing: StringName = &""
var _warned: Dictionary = {}


func _ready() -> void:
	_resolve()


func player() -> AnimationPlayer:
	if _player == null or not is_instance_valid(_player):
		_resolve()

	return _player


func is_ready_to_play() -> bool:
	return player() != null


func play(clip: DotPlayerAnimClip, elapsed: float) -> void:
	var p := player()

	if p == null or clip == null:
		return

	var wanted := clip.name_for_player()

	if not p.has_animation(String(wanted)):
		if warn_on_missing and not _warned.has(wanted):
			_warned[wanted] = true
			DotLog.warn(SINK_CHANNEL, "no such animation", {"clip": String(wanted)})
		return

	if _playing == wanted and p.is_playing():
		return

	_playing = wanted

	if clip.blend > 0.0:
		p.play(String(wanted), clip.blend, clip.speed)
	else:
		p.play(String(wanted), -1.0, clip.speed)

	if elapsed > 0.0:
		p.seek(elapsed, true)


func advance_to(_clip: DotPlayerAnimClip, _elapsed: float) -> void:
	# An AnimationPlayer advances itself. The driver still calls this every frame,
	# because a sprite sink needs it — and a sink that only some callers drove would be
	# a contract nobody could rely on.
	pass


func stop() -> void:
	var p := player()

	if p != null:
		p.stop()

	_playing = &""


func playing() -> StringName:
	return _playing


func _resolve() -> void:
	if player_ref != null:
		_player = player_ref.resolve_or_null(self, SINK_CHANNEL) as AnimationPlayer
		return

	_player = _find(self)

	if _player == null and get_parent() != null:
		# Direct siblings only, never the parent's whole subtree. A recursive search
		# upward finds another player's AnimationPlayer in a scene that holds several,
		# and the symptom is one character driving somebody else's animation — which is
		# not where anybody would look. Anything further away is what player_ref is for.
		for sibling in get_parent().get_children():
			if sibling is AnimationPlayer:
				_player = sibling as AnimationPlayer
				break


func _find(root: Node) -> AnimationPlayer:
	for child in root.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer

		var deeper := _find(child)

		if deeper != null:
			return deeper

	return null


func describe_lines() -> PackedStringArray:
	return PackedStringArray(["AnimationPlayer sink: %s, playing '%s'" % [
		"connected" if player() != null else "NOT FOUND", String(_playing)
	]])
