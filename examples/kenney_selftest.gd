extends Node

## Plays every clip family on both Kenney packs (idle, walk, run, jump, fall, land, death, and the optional gun, crouch and crawl), checking that each track
## resolves, the pose moves, nothing goes through the floor, and the skins and licence manifest are all there. What they look like: tools/kenney_sheet.gd.
## godot --headless --path . res://examples/kenney_selftest.tscn

const SKIN_COUNT := 8
## How far under the floor a bone may go, as a share of the body's height, before a clip counts as through the floor (Kenney's own run points the toe 4.5% down).
const FLOOR_TOLERANCE := 0.05

var _passed := 0
var _failed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	print("dot-player-char kenney self-test")
	_data()
	await _packs()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", what)


func _data() -> void:
	print("data")
	var total := 0
	for pack in DotKenneyCharacters.packs():
		_check(DotKenneyCharacters.display_name(pack, &"nope") == "", "%s: an unknown skin has no name" % pack)
		for skin in DotKenneyCharacters.skins(pack):
			total += 1
			_check(DotKenneyCharacters.display_name(pack, skin).begins_with("GS - "), "%s/%s is named GS - <name>" % [pack, skin])
			_check(FileAccess.file_exists(DotKenneyCharacters.texture_path(pack, skin)), "%s/%s has a texture file" % [pack, skin])
	_check(total == SKIN_COUNT, "eight skins in two packs (%d)" % total)
	_check(DotKenneyCharacters.packs().size() == 2, "two packs")
	_check(DotKenneyCharacters.build(&"nope", &"x") == null, "an unknown pack builds nothing")
	var credits := FileAccess.get_file_as_string("res://addons/dot_player_char/people/CREDITS.md")
	_check(credits.contains("Animated Characters Protagonists") and credits.contains("Animated Characters Retro") and credits.contains("CC0"), "CREDITS.md lists both packs as CC0")
	for path in DotKenneyCharacters.content_paths():
		_check(ResourceLoader.exists(path), "%s loads" % path.get_file())


func _packs() -> void:
	for pack in DotKenneyCharacters.packs():
		print(pack)
		var skins := DotKenneyCharacters.skins(pack)
		var person := DotKenneyCharacters.build(pack, skins[0])
		_check(person != null, "%s builds" % pack)
		if person == null:
			continue
		add_child(person)
		await get_tree().process_frame
		var player := person.get_node("AnimationPlayer") as AnimationPlayer
		var model := player.get_node(player.root_node)
		var skeleton := model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		_check(not meshes.is_empty() and (meshes[0] as MeshInstance3D).material_override != null, "%s: the skin is on the body" % pack)
		_check(absf(person.scale.y - DotKenneyCharacters.SCALE) < 0.0001, "%s: scaled to the family's height" % pack)
		var height := _height(skeleton) * person.scale.y
		_check(absf(height - 1.8) < 0.25, "%s: stands about 1.8 m (%.2f)" % [pack, height])
		var clips: Array[StringName] = []
		clips.append_array(DotKenneyCharacters.REQUIRED)
		clips.append_array(DotKenneyCharacters.OPTIONAL)
		for clip in clips:
			_check(player.has_animation(clip), "%s plays %s" % [pack, clip])
			if player.has_animation(clip):
				_play(pack, clip, player, skeleton, model)
		for skin in skins:
			var other := DotKenneyCharacters.build(pack, skin)
			_check(other != null and other.get_node("AnimationPlayer").has_animation(&"walk"), "%s/%s builds with its clips" % [pack, skin])
			if other != null:
				other.free()
		person.queue_free()
		await get_tree().process_frame


func _play(pack: StringName, clip: StringName, player: AnimationPlayer, skeleton: Skeleton3D, model: Node) -> void:
	var animation := player.get_animation(clip)
	var broken := 0
	for t in animation.get_track_count():
		var path := animation.track_get_path(t)
		if model.get_node_or_null(NodePath(String(path).get_slice(":", 0))) == null or skeleton.find_bone(String(path).get_slice(":", 1)) < 0:
			broken += 1
	_check(broken == 0, "%s/%s: every track resolves (%d broken)" % [pack, clip, broken])
	skeleton.reset_bone_poses()
	var rest := _snapshot(skeleton)
	player.play(clip)
	var moved := 0.0
	var lowest := INF
	var steps := 12
	for step in steps + 1:
		player.seek(animation.length * float(step) / float(steps), true)
		var now := _snapshot(skeleton)
		for i in now.size():
			moved = maxf(moved, (now[i] - rest[i]).length())
		for i in skeleton.get_bone_count():
			lowest = minf(lowest, skeleton.get_bone_global_pose(i).origin.y)
	player.stop()
	_check(moved > 0.01, "%s/%s: the pose moves (%.3f)" % [pack, clip, moved])
	var floor_y := _floor(skeleton)
	_check(lowest >= floor_y - FLOOR_TOLERANCE * 3.77, "%s/%s: not through the floor (lowest %.2f, floor %.2f)" % [pack, clip, lowest, floor_y])


func _snapshot(skeleton: Skeleton3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in skeleton.get_bone_count():
		out.append(skeleton.get_bone_global_pose(i).origin)
	return out


## The rest pose's lowest bone (the foot): the floor the clips are built to.
func _floor(skeleton: Skeleton3D) -> float:
	var lowest := INF
	for i in skeleton.get_bone_count():
		lowest = minf(lowest, skeleton.get_bone_global_rest(i).origin.y)
	return lowest


func _height(skeleton: Skeleton3D) -> float:
	var low := INF
	var high := -INF
	for i in skeleton.get_bone_count():
		var y := skeleton.get_bone_global_rest(i).origin.y
		low = minf(low, y)
		high = maxf(high, y)
	return high - low
