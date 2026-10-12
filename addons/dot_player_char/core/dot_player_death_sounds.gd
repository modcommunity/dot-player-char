class_name DotPlayerDeathSounds
extends RefCounted

## The files behind the stock death reactions' sound ids, as plain data a game turns into its
## own audio definitions. Kenney's CC0 impact and foley sounds, shipped in
## [code]death/sounds/[/code] beside this addon (credited in its CREDITS.md).
##
## [b]Data, not dot-audio definitions[/b], because this addon does not depend on dot-audio: a
## game that uses it makes one [code]DotAudioDef[/code] per row (path, variants, pitch range,
## gain), positional, and the ids in [DotPlayerDeathReactions] then play. A game with its own
## sounds for these ids ignores this file.

## The directory the files are in, found from this script so a delivered pack mounted under
## another root still finds them.
static func directory() -> String:
	var here: String = (DotPlayerDeathSounds as Script).resource_path
	return here.get_base_dir().get_base_dir().path_join("death/sounds")


## One row per id: [code]{id, path, variants, gain_db, pitch_min, pitch_max, cooldown_ms}[/code].
## [code]variants[/code] holds every file, [code]path[/code] the first.
static func rows() -> Array[Dictionary]:
	var dir := directory()
	var out: Array[Dictionary] = []
	for spec: Array in [
		# id, file stem, how many, gain, pitch low, pitch high
		[DotPlayerDeathReactions.SOUND_FACE_PLANT, "face_plant", 3, 2.0, 0.85, 1.0],
		[DotPlayerDeathReactions.SOUND_THUD, "thud", 3, 0.0, 0.8, 1.0],
		[DotPlayerDeathReactions.SOUND_SLUMP, "slump", 2, -2.0, 0.8, 0.95],
		[DotPlayerDeathReactions.SOUND_WHOOSH, "whoosh", 3, -3.0, 0.9, 1.1],
	]:
		var variants := PackedStringArray()
		for i in range(int(spec[2])):
			variants.append(dir.path_join("%s_%d.ogg" % [spec[1], i]))
		out.append({
			"id": spec[0],
			"path": variants[0],
			"variants": variants,
			"gain_db": float(spec[3]),
			"pitch_min": float(spec[4]),
			"pitch_max": float(spec[5]),
			# Eight bodies landing in one frame is one thud, not eight.
			"cooldown_ms": 60,
		})
	return out
