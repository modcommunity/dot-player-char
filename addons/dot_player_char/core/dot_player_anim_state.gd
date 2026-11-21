class_name DotPlayerAnimState
extends DotAnimationLocomotion

## Which locomotion state a character is in, as a pure function of how it is moving.
##
## The state machine and its hysteresis moved to GameSpice Animation ([DotAnimationLocomotion]); this keeps the name games and this addon's [DotPlayerAnimDriver] use. Nothing is added: the vocabulary constants, thresholds and [method advance] are inherited unchanged.


func _to_string() -> String:
	return "DotPlayerAnimState(%s)" % describe()
