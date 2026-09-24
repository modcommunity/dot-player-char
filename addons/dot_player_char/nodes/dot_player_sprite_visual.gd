class_name DotPlayerSpriteVisual
extends DotPlayerCharVisual

## The 2D implementation of dot-player-char's visual seam.
##
## [b]One [Sprite2D] per layer, all indexed by one frame number.[/b] That is the whole
## design and it is why [DotPlayerSpriteDef] insists every overlay is cut on the same
## grid as the base: an overlay with a different grid cannot share the index, and every
## animation would then need a second table that somebody has to keep in step.
##
## The node does not animate. It exposes [method set_frame] and
## [method set_facing_angle], and [DotPlayerAnimDriver] drives them — or a game
## does, in four lines, if it has no use for an animation layer.

## Not [code]CHANNEL[/code]: the parent chain already has one.
const SPRITE_CHANNEL := "player.sprite"

## The layers were rebuilt. Carries how many.
signal rebuilt(layers: int)

@export var catalogue: DotPlayerSpriteCatalogue = null

## Material applied to every layer, for a game with a tint shader.
##
## This addon ships no shader on purpose: a shader is art, and an addon that shipped one
## would be an addon with an opinion about a game's rendering. Above one tint channel,
## supply one whose parameters match [member DotPlayerSpriteDef.tint_parameter].
@export var layer_material: Material = null

@export var hide_when_not_shown: bool = true

var _def: DotPlayerSpriteDef = null
var _look: DotPlayerCharLook = null
var _root: Node2D = null
var _base: Sprite2D = null
var _layers: Dictionary = {}
var _mounts: Dictionary = {}

var _row: int = 0
var _frame: int = 0
var _facing: DotPlayerSpriteFacing.Facing = null


func _ready() -> void:
	if _root == null:
		_root = Node2D.new()
		_root.name = "Sprite"
		add_child(_root)

	_facing = DotPlayerSpriteFacing.Facing.new(0, false)

	# Onto the player body, not left here: a Node2D under a plain Node is placed on the
	# canvas, not on the player. See [member DotPlayerCharVisual.anchor_ref].
	var _seated := seat()


func _drawn_node() -> Node:
	return _root


func _anchor_class() -> StringName:
	return &"Node2D"


# --- The seam ---------------------------------------------------------------

func apply_char(def: DotPlayerCharDef, look: DotPlayerCharLook) -> void:
	if catalogue == null:
		return

	var wanted := def.sprite_id if def != null else &""
	var sprite: DotPlayerSpriteDef = null

	if wanted != &"" and catalogue.has_sprite(wanted):
		sprite = catalogue.get_sprite(wanted)
	else:
		sprite = catalogue.fallback()

	if sprite == null:
		DotLog.warn(SPRITE_CHANNEL, "no sprite to build", {"wanted": String(wanted)})
		return

	_look = look

	if sprite != _def:
		_def = sprite
		_rebuild()

	_apply_layer_visibility()
	_apply_tints()
	_apply_frame()


func set_stance(crouched: bool) -> void:
	# A stance is a row in the sheet, and which row is the animation layer's business.
	# Recorded here so a game with no animation layer can still read it.
	if _root != null:
		_root.set_meta("crouched", crouched)


func set_shown(shown: bool) -> void:
	if hide_when_not_shown and _root != null:
		_root.visible = shown


func attachment(point: StringName) -> Node:
	return _mounts.get(point, null)


func attachment_names() -> Array[StringName]:
	var out: Array[StringName] = []

	for key: Variant in _mounts.keys():
		out.append(key as StringName)

	return out


# --- Drawing ----------------------------------------------------------------

## Which row of the sheet — which state — is being drawn.
func set_row(row: int) -> void:
	if row == _row:
		return

	_row = row
	_apply_frame()


## Which column — which frame of the animation.
func set_frame(frame: int) -> void:
	if frame == _frame:
		return

	_frame = frame
	_apply_frame()


## Which way the character is pointing, in radians.
##
## Takes the angle rather than a direction index so that a caller never has to know how
## the sheet was cut. The mirror flag comes back out of
## [method DotPlayerSpriteFacing.resolve] and is applied here.
func set_facing_angle(angle: float) -> void:
	if _def == null:
		return

	var facing := DotPlayerSpriteFacing.resolve(
		angle, _def.direction_count(), _def.mirror_left, _def.first_direction
	)

	if _facing != null and facing.index == _facing.index and facing.flip_h == _facing.flip_h:
		return

	_facing = facing
	_apply_frame()


func row() -> int:
	return _row


func frame() -> int:
	return _frame


func facing() -> DotPlayerSpriteFacing.Facing:
	return _facing


func def() -> DotPlayerSpriteDef:
	return _def


# --- Building ---------------------------------------------------------------

func _rebuild() -> void:
	for child in _root.get_children():
		child.queue_free()

	_layers.clear()
	_mounts.clear()
	_base = null

	if _def == null:
		return

	_base = _make_sprite(_def.sheet, _def.z_offset)
	_root.add_child(_base)

	for slot in _def.layer_slots():
		var s := _make_sprite(_def.layer_sheet(slot), _def.z_offset + _def.layer_z(slot) + 1)
		s.name = "Layer_%s" % String(slot)
		_root.add_child(s)
		_layers[slot] = s

		# A layer is also an attachment point: in 2D, "where the hand is" is the hand
		# layer's own node, and a game that wanted a Marker2D per slot would be adding
		# nodes that track something already there.
		_mounts[slot] = s

	_root.scale = Vector2.ONE * float(_def.pixel_scale)
	rebuilt.emit(_layers.size() + 1)


func _make_sprite(path: String, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.z_index = clampi(z, -4096, 4096)
	s.material = layer_material
	s.texture_filter = (
		CanvasItem.TEXTURE_FILTER_LINEAR if _def.filtered
		else CanvasItem.TEXTURE_FILTER_NEAREST
	)
	s.region_enabled = true

	if path != "" and ResourceLoader.exists(path):
		s.texture = load(path) as Texture2D
	elif path != "":
		# Named, not silent: a sheet that is not there draws nothing, and "the character
		# is invisible" is otherwise debugged in the renderer.
		DotLog.warn(SPRITE_CHANNEL, "sheet not found", {"path": path})

	return s


func _apply_frame() -> void:
	if _def == null or _base == null:
		return

	var direction := _facing.index if _facing != null else 0
	var flip := _facing.flip_h if _facing != null else false
	var index := _def.frame_index(_row, direction, _frame)
	var rect := _def.frame_rect(index)
	var offset := _def.draw_offset() / float(maxi(1, _def.pixel_scale))

	_set_region(_base, rect, flip, offset)

	for key: Variant in _layers.keys():
		_set_region(_layers[key] as Sprite2D, rect, flip, offset)


func _set_region(sprite: Sprite2D, rect: Rect2i, flip: bool, offset: Vector2) -> void:
	sprite.region_rect = Rect2(rect)
	sprite.flip_h = flip
	sprite.position = offset

	if flip:
		# The anchor is measured from the left, so flipping about the node's origin
		# moves the sprite by its own width. Without this a mirrored character walks
		# with its feet a frame-width to the side, which reads as the collision being
		# offset rather than as the sprite.
		sprite.position.x += float(rect.size.x)


func _apply_layer_visibility() -> void:
	if _def == null:
		return

	for key: Variant in _layers.keys():
		var slot := key as StringName
		var sprite := _layers[key] as Sprite2D
		var chosen := _look.chosen(slot) if _look != null else &""

		# A slot set to "none" is the ordinary way of wearing nothing, and hiding the
		# layer is cheaper and more reversible than rebuilding without it.
		sprite.visible = chosen != &"" and chosen != &"none"


func _apply_tints() -> void:
	if _def == null or _look == null or _def.tint_channels <= 0:
		return

	if _look.colours.is_empty():
		return

	# One channel is modulate, which needs no shader and is why a game with a single
	# team colour ships no material at all.
	_base.modulate = _look.colours[0]

	for key: Variant in _layers.keys():
		(_layers[key] as Sprite2D).modulate = _look.colours[0]

	if _def.tint_channels <= 1:
		return

	for i in range(1, mini(_def.tint_channels, _look.colours.size())):
		var parameter := "%s%d" % [_def.tint_parameter, i]
		_set_shader_parameter(_base, parameter, _look.colours[i])

		for key: Variant in _layers.keys():
			_set_shader_parameter(_layers[key] as Sprite2D, parameter, _look.colours[i])


func _set_shader_parameter(sprite: Sprite2D, parameter: String, colour: Color) -> void:
	var material := sprite.material as ShaderMaterial

	if material == null:
		return

	material.set_shader_parameter(parameter, colour)


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("sprite visual: %s, row %d frame %d, facing %s%s" % [
		String(_def.id) if _def != null else "<none>",
		_row, _frame,
		_facing.describe() if _facing != null else "-",
		"" if visual_enabled else " (disabled)",
	])

	for key: Variant in _layers.keys():
		out.append("  layer %s: %s" % [
			String(key), "shown" if (_layers[key] as Sprite2D).visible else "hidden"
		])

	return out
