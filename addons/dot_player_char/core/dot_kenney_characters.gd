class_name DotKenneyCharacters
extends RefCounted

## Kenney's "Animated Characters Protagonists" and "Animated Characters Retro" (CC0, kenney.nl) as people: one body (a 58-bone rig, 3.77 units tall as exported),
## eight skins in two packs, and the family's clip set baked onto it (`people/kenney/kenney_clips.res`, built by `tools/kenney_retarget.gd`).
## Kenney ships the same model and the same three clips (idle, run, jump) in both packs, so there is one glb and the packs are groups of skins.
## Beside the Quaternius people ([DotHumanoidFigure]), not instead of them: this builds a plain node tree to play and look at. docs/kenney-characters.md.

const DIR := "res://addons/dot_player_char/people/kenney/"
const MODEL := DIR + "kenney_character.glb"
const CLIPS := DIR + "kenney_clips.res"

## The family's height (metres, [DotPlayerCharDef]) over the model's own: the wrapper node carries this scale, because the glTF exporter drops the armature's.
const SCALE := 1.8 / 3.7654

## What a pack must be able to play: a pack missing one is a broken build, not a quieter one.
const REQUIRED: Array[StringName] = [&"idle", &"walk", &"run", &"jump", &"fall", &"land", &"death"]
## What a figure may play when it has it: holding a gun, crouching, crawling.
const OPTIONAL: Array[StringName] = [&"idle_gun", &"walk_gun", &"run_gun", &"crouch", &"crouch_walk", &"crawl"]

## Pack id -> display name, the Kenney pack it came from, and its skins (id -> display name; the texture is `<pack>_<skin>.png`).
const PACKS := {
	&"protagonists": {
		"name": "GS - Protagonists", "source": "Animated Characters Protagonists",
		"skins": {&"criminalMaleA": "GS - Criminal", &"cyborgFemaleA": "GS - Cyborg", &"skaterFemaleA": "GS - Skater Girl", &"skaterMaleA": "GS - Skater Boy"},
	},
	&"retro": {
		"name": "GS - Retro", "source": "Animated Characters Retro",
		"skins": {&"humanFemaleA": "GS - Human Woman", &"humanMaleA": "GS - Human Man", &"zombieFemaleA": "GS - Zombie Woman", &"zombieMaleA": "GS - Zombie Man"},
	},
}


static func packs() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in PACKS:
		out.append(id)
	return out


static func skins(pack: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if PACKS.has(pack):
		for id: StringName in PACKS[pack]["skins"]:
			out.append(id)
	return out


## The name a picker shows for a skin ("GS - Cyborg"), or "" for an unknown pack or skin.
static func display_name(pack: StringName, skin: StringName) -> String:
	if not PACKS.has(pack):
		return ""
	return String(PACKS[pack]["skins"].get(skin, ""))


static func texture_path(pack: StringName, skin: StringName) -> String:
	return "%s%s_%s.png" % [DIR, pack, skin]


## Every file a client must have to draw any of these people (for `DotHumanoidAssets.content_paths`-style lists); pure data.
static func content_paths() -> Array[String]:
	var out: Array[String] = [MODEL, CLIPS]
	for pack in packs():
		for skin in skins(pack):
			out.append(texture_path(pack, skin))
	return out


## The clips a library lacks of [constant REQUIRED], empty when it is complete.
static func missing(library: AnimationLibrary) -> Array[StringName]:
	var out: Array[StringName] = []
	for clip in REQUIRED:
		if library == null or not library.has_animation(clip):
			out.append(clip)
	return out


## A person: a scaled wrapper holding the model with [param skin] on it and an [AnimationPlayer] (named `AnimationPlayer`, the clips on it, none playing).
## Null and an error for an unknown pack or skin or a missing file; nothing is approximated.
static func build(pack: StringName, skin: StringName) -> Node3D:
	if display_name(pack, skin) == "":
		push_error("DotKenneyCharacters: no skin %s in pack %s" % [skin, pack])
		return null
	var scene := load(MODEL) as PackedScene
	var library := load(CLIPS) as AnimationLibrary
	var texture := load(texture_path(pack, skin)) as Texture2D
	if scene == null or library == null or texture == null:
		push_error("DotKenneyCharacters: %s, %s or %s did not load (import the project once)" % [MODEL, CLIPS, texture_path(pack, skin)])
		return null
	var absent := missing(library)
	if not absent.is_empty():
		push_error("DotKenneyCharacters: the clip library lacks %s" % [absent])
		return null
	var wrapper := Node3D.new()
	wrapper.name = display_name(pack, skin)
	wrapper.scale = Vector3.ONE * SCALE
	var model := scene.instantiate()
	wrapper.add_child(model)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	wrapper.add_child(player)
	player.root_node = player.get_path_to(model)
	var err := player.add_animation_library(&"", library)
	if err != OK:
		push_error("DotKenneyCharacters: could not add the clips (%s)" % error_string(err))
	return wrapper
