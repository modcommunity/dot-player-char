class_name DotPlayerAnimSink
extends Node

## Where an animation decision actually goes.
##
## [b]The reason this addon works for both 2D and 3D without depending on either.[/b]
## The driver decides what should be playing; a sink makes it happen — on an
## [AnimationPlayer], on a sprite sheet, on a game's own [AnimationTree], or nowhere at
## all in a headless test.
##
## The two shipped sinks are in this addon and neither imports the thing it drives:
## [DotPlayerAnimPlayerSink] takes an [AnimationPlayer], which is native, and
## [DotPlayerAnimSpriteSink] duck-types [code]set_row[/code] and [code]set_frame[/code]
## — so dot-player-char-animations stays installable without dot-player-char-sprite.

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
