class_name DotPlayerCharLook
extends RefCounted

## What a player has chosen for their character, as a bounded document.
## A server validates one from ids alone (slot exists, option legal, colour count and
## values), holding no art. Separate from [DotPlayerCharDef]: content ships, a look arrives.

## Which character this is a look for.
var char_id: StringName = &""

## slot name -> chosen option id.
var choices: Dictionary = {}

## Tint colours, in channel order. At most the character's [code]colour_channels[/code].
var colours: Array[Color] = []


static func make(p_char: StringName) -> DotPlayerCharLook:
	var l := DotPlayerCharLook.new()
	l.char_id = p_char
	return l


func choose(slot: StringName, option: StringName) -> void:
	choices[String(slot)] = String(option)


func chosen(slot: StringName) -> StringName:
	return StringName(str(choices.get(String(slot), "")))


func clear_slot(slot: StringName) -> void:
	choices.erase(String(slot))


## Whether this look is legal for a character. Loads nothing.
## Keep it that way: a server must be able to check it without holding the art.
func validate(def: DotPlayerCharDef) -> DotResult:
	if def == null:
		return DotResult.fail(DotError.CODE_INVALID, "No character to validate against.")

	if char_id != &"" and char_id != def.id:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"This look is for '%s' and was checked against '%s'."
			% [String(char_id), String(def.id)]
		)

	for key: Variant in choices.keys():
		var slot := StringName(str(key))

		if not def.has_slot(slot):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"'%s' has no slot called '%s'." % [String(def.id), String(slot)]
			)

		var option := StringName(str(choices[key]))
		var options := def.slot_options(slot)

		if not options.has(option):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"'%s' is not an option for '%s' on '%s'."
				% [String(option), String(slot), String(def.id)],
				"Known: %s" % ", ".join(_names(options))
			)

	if colours.size() > def.colour_channels:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"%d colours for a character with %d channels."
			% [colours.size(), def.colour_channels],
			"A document that may carry any number of colours is a document a client "
			+ "can make arbitrarily large."
		)

	return DotResult.success(null)


## Removes everything illegal, rather than refusing the whole document.
## For loading a saved look after its content was removed; [method validate] is for the
## trust boundary. Returns how many things it dropped.
func conform(def: DotPlayerCharDef) -> int:
	if def == null:
		return 0

	var dropped := 0

	for key: Variant in choices.keys().duplicate():
		var slot := StringName(str(key))
		var option := StringName(str(choices[key]))

		if not def.has_slot(slot) or not def.slot_options(slot).has(option):
			choices.erase(key)
			dropped += 1

	while colours.size() > def.colour_channels:
		colours.remove_at(colours.size() - 1)
		dropped += 1

	return dropped


## Fills every empty slot with the character's first option, so a renderer never sees
## a half-built look.
func fill_defaults(def: DotPlayerCharDef) -> void:
	if def == null:
		return

	for slot in def.slot_names():
		if choices.has(String(slot)):
			continue

		var options := def.slot_options(slot)

		if not options.is_empty():
			choices[String(slot)] = String(options[0])

	while colours.size() < def.colour_channels:
		colours.append(Color.WHITE)


func to_dict() -> Dictionary:
	var raw: Array = []

	for c in colours:
		raw.append(c.to_html(false))

	return {
		"char": String(char_id),
		"choices": choices.duplicate(true),
		"colours": raw,
	}


static func from_dict(d: Dictionary) -> DotPlayerCharLook:
	var l := DotPlayerCharLook.new()
	l.char_id = StringName(str(d.get("char", "")))

	var c: Variant = d.get("choices", {})
	l.choices = (c as Dictionary).duplicate(true) if c is Dictionary else {}

	for raw: Variant in d.get("colours", []):
		# Html() rather than a cast: a colour arriving from a client is a string, and
		# Color(str) is not a conversion GDScript performs. An unparseable one comes
		# back black, which is visible rather than silent.
		l.colours.append(Color.html(str(raw)))

	return l


func copy_look() -> DotPlayerCharLook:
	return DotPlayerCharLook.from_dict(to_dict())


func describe() -> String:
	return "%s: %d slots, %d colours" % [String(char_id), choices.size(), colours.size()]


func _names(list: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()

	for s in list:
		out.append(String(s))

	return out


func _to_string() -> String:
	return "DotPlayerCharLook(%s)" % describe()
