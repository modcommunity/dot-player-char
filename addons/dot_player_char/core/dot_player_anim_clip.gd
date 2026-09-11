@tool
class_name DotPlayerAnimClip
extends Resource

## One animation, described in a way both a rig and a sprite sheet can honour.
##
## [b]Two vocabularies in one resource, on purpose.[/b] An [AnimationPlayer] wants a
## clip name and a speed; a sprite sheet wants a row, a frame count and a frame rate.
## A game that shipped both — and hungario and arena between them do — would otherwise
## need two tables that say the same thing and drift apart, and the drift shows up as
## the 2D build running an animation at the wrong speed.

## The state or action this clip is for.
@export var id: StringName = &""

@export var loops: bool = true

## Playback speed multiplier.
@export_range(0.01, 20.0, 0.01) var speed: float = 1.0

## Seconds to blend from whatever was playing. Zero is a cut.
@export_range(0.0, 5.0, 0.01) var blend: float = 0.15

@export_group("For an AnimationPlayer")

## The clip name in the rig's [AnimationPlayer]. Empty uses [member id].
@export var clip_name: StringName = &""

@export_group("For a sprite sheet")

## Which row of the sheet. See [code]DotPlayerSpriteDef.frame_index[/code].
@export_range(0, 512, 1) var row: int = 0

## How many frames the animation has.
@export_range(1, 512, 1) var frames: int = 1

## Frames per second.
@export_range(0.1, 240.0, 0.1) var fps: float = 10.0

@export_group("Events")

## Frame numbers that fire a footstep, as a fraction of the clip.
##
## Fractions rather than frame indices so one clip works for a rig and a sheet: a rig's
## animation has a length in seconds and a sheet's has a frame count, and 0.25 means the
## same place in both.
@export var footsteps: PackedFloat32Array = PackedFloat32Array()

## Other named events: [code]{"fire": 0.1, "eject": 0.4}[/code].
@export var events: Dictionary = {}


static func make(
	p_id: StringName,
	p_loops: bool = true,
	p_row: int = 0,
	p_frames: int = 1
) -> DotPlayerAnimClip:
	var c := DotPlayerAnimClip.new()
	c.id = p_id
	c.loops = p_loops
	c.row = p_row
	c.frames = p_frames
	return c


func name_for_player() -> StringName:
	return clip_name if clip_name != &"" else id


## How long one pass through the sprite version takes, in seconds.
func sheet_duration() -> float:
	return float(frames) / maxf(0.01, fps * speed)


## Which frame is showing after [param elapsed] seconds.
##
## Clamps rather than wrapping for a non-looping clip, so a one-shot holds its last
## frame instead of snapping back to the first — which reads as the animation being cut
## off rather than as having finished.
func frame_at(elapsed: float) -> int:
	var index := int(floor(elapsed * fps * speed))

	if loops:
		return posmod(index, maxi(1, frames))

	return clampi(index, 0, maxi(0, frames - 1))


## Whether a non-looping clip has finished.
func finished_at(elapsed: float) -> bool:
	return not loops and elapsed >= sheet_duration()


## Event names whose moment falls between two elapsed times.
##
## [b]A window rather than an instant.[/b] A clip event at 0.25 of the way through will
## never be tested at exactly that moment, so an implementation that compared for
## equality would fire nothing, and one that compared for "past it" would fire every
## tick afterwards. The pair of times is the only thing that fires it once.
func events_between(from: float, to: float) -> PackedStringArray:
	var out := PackedStringArray()
	var length := sheet_duration()

	if length <= 0.0:
		return out

	for step in footsteps:
		if _crossed(float(step) * length, from, to):
			out.append("footstep")

	for key: Variant in events.keys():
		if _crossed(float(events[key]) * length, from, to):
			out.append(str(key))

	return out


func _crossed(moment: float, from: float, to: float) -> bool:
	if to <= from:
		return false

	if loops:
		var length := sheet_duration()

		if length <= 0.0:
			return false

		# A looping clip's event fires once per pass, which means comparing positions
		# within the loop and allowing for the wrap.
		var a := fposmod(from, length)
		var b := fposmod(to, length)

		if b >= a:
			return moment > a and moment <= b

		return moment > a or moment <= b

	return moment > from and moment <= to


func describe() -> String:
	return "%s: %d frames @ %.1f fps%s" % [
		String(id), frames, fps, "" if loops else ", one shot"
	]


func _to_string() -> String:
	return "DotPlayerAnimClip(%s)" % describe()
