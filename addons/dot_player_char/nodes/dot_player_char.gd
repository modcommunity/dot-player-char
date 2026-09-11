class_name DotPlayerChar
extends DotPlayerComponent

## Which character a player is, and the one place everything asks about their body.
##
## [b]This node owns the metrics, and that is what makes it worth having.[/b] The
## collision capsule, the crouch test, the camera height, the hitbox layout and the
## third-person model are five things that have to agree about how tall somebody is, and
## in most projects they agree by five separate numbers that were the same on the day
## they were typed.
##
## [codeblock]
## DotPlayer
##   CharacterBody3D
##     CollisionShape3D          sized by apply_to_body()
##   DotPlayerChar               char_id = &"medium"
##     DotPlayerModelVisual      or a sprite visual, or none at all
## [/codeblock]

## Not [code]CHANNEL[/code]: [DotPlayerComponent] declares one already.
const CHAR_CHANNEL := "player.char"

## The character, or the look, changed.
signal char_changed(def: DotPlayerCharDef)

## The stance changed. A camera and a visual both want this.
signal stance_changed(crouched: bool)

@export var catalogue: DotPlayerCharCatalogue = null

## Which character. Empty takes the catalogue's fallback on the first bind.
@export var char_id: StringName = &"":
	set(value):
		if value == char_id:
			return

		char_id = value
		_refresh()

## Whether to resize the player's collision shape when the character changes.
##
## On: a character that is visibly two metres tall and collides as if it were 1.8 is the
## exact bug the metrics live in one place to prevent. Off for a game whose bodies are
## built by hand and whose characters are all the same size.
@export var size_body: bool = true

## Whether to keep the roster's [code]char_id[/code] in step with this node.
@export var report_to_roster: bool = true

var look: DotPlayerCharLook = null

var _def: DotPlayerCharDef = null
var _crouched: bool = false


func _ready() -> void:
	# A visual added after this node has already bound would otherwise never be told
	# what to draw: `_push_to_visuals` runs during the bind, and at that moment the
	# visual is not a child yet. A game that instances its character and then attaches
	# a first-person arms rig — which is the ordinary way round — would see an empty
	# player and debug it in the renderer.
	child_entered_tree.connect(_on_child_entered)
	super()


func _on_child_entered(node: Node) -> void:
	var visual := node as DotPlayerCharVisual

	if visual == null:
		return

	# Deferred, because the child's own _ready has not run at this point and a visual
	# that builds its root node there would be told what to draw before it had anywhere
	# to draw it.
	visual.call_deferred("apply_char", _def, look)
	visual.call_deferred("set_stance", _crouched)


func _on_bound(_p: DotPlayer) -> void:
	_refresh()


## Pushes the current character and look at every visual again.
##
## Called automatically when a visual is added; public for a game that swaps a visual's
## catalogue at runtime, where nothing about the character has changed and so nothing
## else would prompt a redraw.
func refresh_visuals() -> void:
	_push_to_visuals()


# --- The character ----------------------------------------------------------

## The definition in force, or null when there is no catalogue.
func def() -> DotPlayerCharDef:
	return _def


## Changes character, validating the look against the new one.
func set_char(new_id: StringName) -> DotResult:
	if catalogue == null:
		return DotResult.fail(
			DotError.CODE_STATE, "This DotPlayerChar has no catalogue."
		)

	if not catalogue.has_char(new_id):
		return DotResult.fail(
			DotError.CODE_INVALID, "No such character: '%s'." % String(new_id)
		)

	char_id = new_id
	return DotResult.success(_def)


## Replaces the look, conforming it rather than refusing it.
##
## Conform rather than validate because this is the loading path: somebody's saved
## character after the hat they chose was removed from the game should lose the hat,
## not be locked out of playing. The trust boundary — a look arriving from a client —
## is the game's [method DotPlayerCharLook.validate] call, not this.
func set_look(new_look: DotPlayerCharLook) -> int:
	look = new_look if new_look != null else DotPlayerCharLook.make(char_id)
	look.char_id = char_id

	var dropped := 0

	if _def != null:
		dropped = look.conform(_def)
		look.fill_defaults(_def)

	_push_to_visuals()
	char_changed.emit(_def)
	return dropped


# --- Stance -----------------------------------------------------------------

## Standing or crouched. Drives the capsule, the eye height and every visual.
func set_crouched(crouched: bool) -> void:
	if crouched == _crouched:
		return

	_crouched = crouched

	if size_body:
		_size_body()

	for v in visuals():
		v.set_stance(crouched)

	stance_changed.emit(crouched)


func is_crouched() -> bool:
	return _crouched


# --- Metrics ----------------------------------------------------------------

## How tall this player is right now.
func height() -> float:
	return _def.height_for(_crouched) if _def != null else 1.8


func radius() -> float:
	return _def.radius if _def != null else 0.35


## Where the eyes are above the feet, right now.
##
## Asks the visual first: a rig with a real head bone knows better than a number in a
## resource, and the two disagreeing is what makes a first-person camera float above a
## third-person model's shoulders.
func eye_height() -> float:
	for v in visuals():
		if not v.visual_enabled:
			continue

		var offered := v.eye_offset()

		if offered >= 0.0:
			return offered

	return _def.eye_for(_crouched) if _def != null else 1.65


func mass() -> float:
	return _def.mass if _def != null else 80.0


func hitbox_scale() -> float:
	return _def.hitbox_scale if _def != null else 1.0


## The eye transform, given where the feet are and where the player is looking.
##
## One function so a first-person camera, a muzzle and a lag-compensated trace all get
## the same answer. Getting three slightly different answers is how a shot comes out of
## somewhere the player cannot see.
func eye_transform(feet: Transform3D, look_basis: Basis) -> Transform3D:
	return Transform3D(look_basis, feet.origin + Vector3.UP * eye_height())


# --- The body ---------------------------------------------------------------

## Sizes the player's collision shape to this character.
##
## Called automatically on every change when [member size_body] is on. Public because a
## game that builds its body later needs to ask for it once the shape exists.
func apply_to_body() -> DotResult:
	return _size_body()


func _size_body() -> DotResult:
	if _def == null or not is_bound():
		return DotResult.fail(DotError.CODE_STATE, "No character or no player.")

	var body := player().body()

	if body == null:
		return DotResult.fail(DotError.CODE_STATE, "This player has no body.")

	var shaped := false

	for child in body.get_children():
		var s3 := child as CollisionShape3D

		if s3 != null:
			# A fresh shape each time: a Shape3D handed to two bodies is shared by
			# them, so resizing one character would resize every player using the same
			# resource — which presents as everybody crouching at once.
			s3.shape = _def.capsule_3d(_crouched)
			s3.position = Vector3.UP * (_def.height_for(_crouched) * 0.5)
			shaped = true
			continue

		var s2 := child as CollisionShape2D

		if s2 != null:
			s2.shape = _def.capsule_2d(_crouched)
			shaped = true

	if not shaped:
		return DotResult.fail(
			DotError.CODE_STATE,
			"This player's body has no collision shape to size.",
			"DotPlayerChar sizes a CollisionShape3D or CollisionShape2D under the "
			+ "body. A body built later should call apply_to_body() once it has one."
		)

	return DotResult.success(null)


# --- Visuals ----------------------------------------------------------------

## Every visual under this node.
func visuals() -> Array[DotPlayerCharVisual]:
	var out: Array[DotPlayerCharVisual] = []

	for child in get_children():
		var v := child as DotPlayerCharVisual
		if v != null:
			out.append(v)

	return out


## Turns exactly one visual on and the rest off.
##
## What a game calls when the camera changes: a first-person arms rig and a third-person
## body are two visuals under one player, and both being drawn is the bug where you can
## see your own head.
func use_visual(which: DotPlayerCharVisual) -> void:
	for v in visuals():
		v.visual_enabled = v == which

	_push_to_visuals()


## Shows or hides every visual. For death, or for interest management.
func set_shown(shown: bool) -> void:
	for v in visuals():
		v.set_shown(shown)


## An attachment point from whichever visual is enabled.
func attachment(point: StringName) -> Node:
	for v in visuals():
		if not v.visual_enabled:
			continue

		var node := v.attachment(point)

		if node != null:
			return node

	return null


# --- Internals --------------------------------------------------------------

func _refresh() -> void:
	if catalogue == null:
		_def = null
		return

	if char_id == &"":
		var fallback := catalogue.fallback_for(_team(), _class())

		if fallback != null:
			# This goes back through the setter, which calls this function again — one
			# level, and it terminates because a fallback id is never empty so the
			# branch is not taken twice. Returning here rather than falling through is
			# what keeps it to one level.
			char_id = fallback.id

		return

	_def = catalogue.get_char(char_id)

	if _def == null:
		DotLog.warn(CHAR_CHANNEL, "no such character", {"char": String(char_id)})
		return

	if look == null:
		look = DotPlayerCharLook.make(char_id)

	look.char_id = char_id
	var _dropped := look.conform(_def)
	look.fill_defaults(_def)

	if size_body:
		var _res := _size_body()

	if report_to_roster and is_bound():
		var roster := player().roster()
		if roster != null and roster.authoritative and roster.has_player(player().player_key):
			var _r := roster.set_char(player().player_key, char_id)

	_push_to_visuals()
	char_changed.emit(_def)


func _push_to_visuals() -> void:
	for v in visuals():
		v.apply_char(_def, look)
		v.set_stance(_crouched)


func _team() -> StringName:
	return player().team() if is_bound() else &""


func _class() -> StringName:
	return player().player_class() if is_bound() else &""


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("character: %s%s" % [
		String(char_id) if char_id != &"" else "<none>",
		" (crouched)" if _crouched else "",
	])

	if _def != null:
		out.append("  " + _def.describe())
		out.append("  eyes at %.2f" % eye_height())

	if look != null:
		out.append("  " + look.describe())

	for v in visuals():
		out.append_array(v.describe_lines())

	return out
