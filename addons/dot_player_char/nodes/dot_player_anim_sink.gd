class_name DotPlayerAnimSink
extends Node

## Where an animation decision actually goes: the driver decides, a sink makes it happen on an [AnimationPlayer],
## a sprite sheet, a game's [AnimationTree], or nothing in a test. That is how the addon serves 2D and 3D without
## depending on either; [DotPlayerAnimSpriteSink] duck-types [code]set_row[/code] and [code]set_frame[/code].

## Start a clip. [param elapsed] is where in it to start, for a resumed state.
func play(_clip: DotPlayerAnimClip, _elapsed: float) -> void:
	pass


## Advance whatever is playing. Called once a frame with the clip and its elapsed time.
func advance_to(_clip: DotPlayerAnimClip, _elapsed: float) -> void:
	pass


## Stop everything. For a character that has left the world.
func stop() -> void:
	pass


## Whether this sink has anything to drive. A driver skips one that has not.
func is_ready_to_play() -> bool:
	return true


func describe_lines() -> PackedStringArray:
	return PackedStringArray([get_class()])
