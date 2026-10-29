## The people's shared files and caches (scenes, clip libraries, materials); [DotHumanoidFigure] forwards its public statics here.
class_name DotHumanoidAssets
extends RefCounted

const CHANNEL := "player.humanoid"

## The atlas colours each body wears, by role, measured by `tools/people_palette.gd`; the shader
## swaps them for the look's colours. Several swatches of one role all take its colour.
const WEARS := {
	&"matt": {"skin": ["7c4e26"], "hair": ["312515"], "top": ["af6c1c"], "bottom": ["4e694b"]},
	&"lis": {"skin": ["c09264"], "hair": ["225385"], "top": ["bd8e30"], "bottom": ["466469"]},
	&"sam": {"skin": ["7c4e26"], "hair": ["4c3a21"], "top": ["504c43"], "bottom": ["333333"]},
	&"shaun": {"skin": ["c09264"], "hair": ["923c12"], "top": ["5f4009"], "bottom": ["466469"]},
}

## The body whose file carries the clip set.
const CLIP_BODY := &"matt"

const SWAPS := 8
const SHADER := """
shader_type spatial;
render_mode cull_back, specular_disabled;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec4 from_colour[8];
uniform vec4 to_colour[8];
uniform vec4 from_linear[8];
uniform vec4 to_linear[8];
uniform int swaps = 0;
uniform float tolerance = 0.002;
uniform float flash = 0.0;

void fragment() {
	// Sampled as a StandardMaterial3D samples its albedo (source_color), so a person is lit like
	// the walls beside them. What comes back differs by renderer (the compatibility one hands back
	// the stored sRGB values), so a swap is matched in both spaces and answered in the space it
	// matched; game-zombie-zone's first version converted by hand and drew everybody near black.
	vec3 c = texture(atlas, UV).rgb;
	for (int i = 0; i < swaps; i++) {
		vec3 d = c - from_colour[i].rgb;
		if (dot(d, d) < tolerance) {
			c = to_colour[i].rgb;
			break;
		}
		vec3 e = c - from_linear[i].rgb;
		if (dot(e, e) < tolerance * 0.25) {
			c = to_linear[i].rgb;
			break;
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
	EMISSION = vec3(flash * 0.35, flash * 0.05, flash * 0.03);
}
"""

static var _scenes: Dictionary = {}
static var _libraries: Dictionary = {}
static var _materials: Dictionary = {}
static var _shader: Shader = null
static var _atlas: Texture2D = null


## The directory the people's files are in, found from this script so a pack mounted under
## another root still finds them.
static func directory() -> String:
	var here: String = (DotHumanoidAssets as Script).resource_path
	return here.get_base_dir().get_base_dir().path_join("people")


## Every file a figure may load, for a preloader or a pack manifest.
static func content_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for id in DotHumanoidLook.BODIES:
		out.append(body_path(id))
	out.append(directory().path_join("atlas_people.png"))
	out.append(real_clips_path())
	return out


## The clips baked from the Universal Animation Library ([method DotHumanoidClips.adopt]); a
## figure without the file plays the made ones.
static func real_clips_path() -> String:
	return directory().path_join("people_ual.res")


static func body_path(id: StringName) -> String:
	return directory().path_join("people_%s.glb" % id)


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load_model(path)
	return _scenes[path]


## A model by path, imported or not: [code]load()[/code] when the project has imported it, and
## otherwise the source file read at run time through [GLTFDocument], packed as a scene.
## The fallback matters: a stale import cache has the [code].glb[/code] but no imported scene.
static func load_model(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		var imported := load(path) as PackedScene
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	var root := doc.generate_scene(state, 30.0, false, true) if err == OK else null
	if root == null:
		DotLog.warn(CHANNEL, "model is neither imported nor readable", {"path": path, "error": error_string(err)})
		return null
	var packed := PackedScene.new()
	var packed_err := packed.pack(root)
	root.free()
	if packed_err != OK:
		return null
	DotLog.warn(CHANNEL, "model was never imported; read from the source file instead (run the project's import once)", {"path": path})
	return packed


## A texture by path, imported or not; the image fallback is [method load_model]'s reasoning.
static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	# From the bytes rather than Image.load_from_file, which prints an export warning for any
	# res:// path even where, as here, there is nothing to export.
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


## The clip set for [param id]'s body, retargeted by [method DotHumanoidClips.retarget] once per
## body and shared. Mirrored first (the kit is left-handed; [constant HAND_BONE]), then the made
## clips, then the real ones from [method real_clips_path] over the ones they replace.
static func library_for(id: StringName, skeleton: Skeleton3D) -> AnimationLibrary:
	var base_key := StringName("base")
	if not _libraries.has(base_key):
		var scene := scene(body_path(CLIP_BODY))
		var probe := scene.instantiate() if scene != null else null
		var bones: Array = probe.find_children("*", "Skeleton3D", true, false) if probe != null else []
		var clip_skeleton: Skeleton3D = bones.front() as Skeleton3D if not bones.is_empty() else null
		var library := DotHumanoidClips.mirror(DotHumanoidClips.library_of(scene))
		_libraries[base_key] = DotHumanoidClips.synthesise(library, clip_skeleton)
		var real_path := real_clips_path()
		var real: AnimationLibrary = load(real_path) as AnimationLibrary if ResourceLoader.exists(real_path) else null
		var _adopted := DotHumanoidClips.adopt(library, real)
		_libraries[&"rests"] = DotHumanoidClips.rests_of(clip_skeleton)
		_libraries[&"sit_height"] = DotHumanoidClips.sit_height(library, clip_skeleton)
		if probe != null:
			probe.free()
	if id == CLIP_BODY or skeleton == null:
		return _libraries[base_key]
	if not _libraries.has(id):
		_libraries[id] = DotHumanoidClips.retarget(_libraries[base_key], _libraries[&"rests"], skeleton)
	return _libraries[id]


## One material per look: people with the same colours share it.
static func material_for(p_look: DotHumanoidLook) -> ShaderMaterial:
	var key := p_look.key()
	if _materials.has(key):
		return _materials[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	if _atlas == null:
		var path := directory().path_join("atlas_people.png")
		_atlas = load_texture(path)

	var wears: Dictionary = WEARS.get(p_look.body, {})
	var colours := {"skin": p_look.skin, "hair": p_look.hair, "top": p_look.top, "bottom": p_look.bottom}
	# vec4, not vec3: a vec3 array is padded on the GPU and a PackedVector3Array set into one is
	# read skewed.
	var from := PackedVector4Array()
	var to := PackedVector4Array()
	var from_lin := PackedVector4Array()
	var to_lin := PackedVector4Array()
	for role: String in ["skin", "hair", "top", "bottom"]:
		for hex: String in wears.get(role, []):
			if from.size() >= SWAPS:
				break
			var a := Color(hex)
			var b: Color = colours[role]
			from.append(Vector4(a.r, a.g, a.b, 1.0))
			to.append(Vector4(b.r, b.g, b.b, 1.0))
			var al := a.srgb_to_linear()
			var bl := b.srgb_to_linear()
			from_lin.append(Vector4(al.r, al.g, al.b, 1.0))
			to_lin.append(Vector4(bl.r, bl.g, bl.b, 1.0))
	var used := from.size()
	while from.size() < SWAPS:
		from.append(Vector4(-9.0, -9.0, -9.0, 0.0))
		to.append(Vector4.ZERO)
		from_lin.append(Vector4(-9.0, -9.0, -9.0, 0.0))
		to_lin.append(Vector4.ZERO)

	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter(&"atlas", _atlas)
	material.set_shader_parameter(&"from_colour", from)
	material.set_shader_parameter(&"to_colour", to)
	material.set_shader_parameter(&"from_linear", from_lin)
	material.set_shader_parameter(&"to_linear", to_lin)
	material.set_shader_parameter(&"swaps", used)
	_materials[key] = material
	return material


## How many distinct materials the looks drawn so far made: a crowd's draw-state cost.
static func material_count() -> int:
	return _materials.size()


## Drops every shared scene, library, material, shader and atlas so a process can exit without leaking them.
static func clear_cache() -> void:
	_scenes.clear()
	_libraries.clear()
	_materials.clear()
	_shader = null
	_atlas = null


## The seated hip height of the shared clip set (0 until a library was built).
static func sit_height() -> float:
	return _libraries.get(&"sit_height", 0.0)
