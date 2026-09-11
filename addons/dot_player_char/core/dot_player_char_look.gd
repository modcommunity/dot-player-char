class_name DotPlayerCharLook
extends RefCounted

## What a player has chosen for their character, as a bounded document.
##
## [b]The whole point is that a server can validate one without holding any art.[/b]
## Four questions, all answered from ids: does the character have that slot, is that a
## legal option for it, are there no more colours than the character has channels, and
## is every colour a colour. dot-user-avatar makes the same promise for cosmetics that
## follow a person between servers; this is the smaller one for the character itself.
##
## Kept separate from [DotPlayerCharDef] because a definition is content and a look is a
## choice: one ships with the game and the other arrives from a client.

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
##
## [b]If a change here ever needs a [code]load()[/code] or a
## [code]ResourceLoader.exists[/code], that is the thing to push back on.[/b] The whole
## value of the document is that a dedicated server can check it, and a server that has
## to hold the art to check it is a server that has to ship every cosmetic anybody owns.
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
##
## The counterpart to [method validate] and used in a different place: validate is for
## the trust boundary, where a bad document should be refused; conform is for loading
## somebody's saved look after the content it referred to has been removed, where
## refusing would lock them out of their own character.
##
## Returns how many things it dropped.
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


## Fills every empty slot with the character's first option.
##
## So that a player who has never opened the customisation screen still has a complete,
## valid look rather than a half-built one — which is what a renderer would otherwise
## have to have an opinion about.
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
