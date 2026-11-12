## The people's shared files and caches (scenes, clip libraries, materials); [DotHumanoidFigure] forwards its public statics here.
class_name DotHumanoidAssets
extends RefCounted

const CHANNEL := "player.humanoid"

## The atlas colours each body wears, by role (`tools/people_palette.gd`); the shader swaps them for
## the look's. A swatch shared by two parts is split by `tools/split_people_atlas.py`. Forearm and
## finger swatches are listed too, or they keep their painted brown beside a pale skin.
const WEARS := {
	&"matt": {"skin": ["7c4e26", "af8d68"], "hair": ["312515"], "top": ["af6c1c", "99a38b", "b5b999"], "bottom": ["4e694b"]},
	&"lis": {"skin": ["c09264", "4c3a21"], "hair": ["225385"], "top": ["bd8e30"], "bottom": ["466469", "b5b999"]},
	&"sam": {"skin": ["7c4e26", "923c12"], "hair": ["4c3a21"], "top": ["504c43", "b2b2b2"], "bottom": ["333333"]},
	&"shaun": {"skin": ["c09264", "4c3a21"], "hair": ["923c12"], "top": ["5f4009", "b5b999", "4e694b", "a58a3b", "c0c0c0"], "bottom": ["466469", "5a8a5a", "b59a4b"]},
}

## The body whose file carries the clip set.
const CLIP_BODY := &"matt"
const BASE := &"base"

const SWAPS := 12
const SHADER := """
shader_type spatial;
render_mode cull_back, specular_disabled;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec4 from_colour[12];
uniform vec4 to_colour[12];
uniform vec4 from_linear[12];
uniform vec4 to_linear[12];
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
# Running prepare_libraries builds: [task id, what it writes, the _generation it was started in].
static var _tasks: Array = []
static var _generation := 0
static var _later: Array[StringName] = []
static var _queued: Dictionary = {}


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
## Takes what a [method prepare_libraries] build finished; one still running is not waited for (the
## set is built here as well), since a worker can need a main-thread step that a wait would block.
static func library_for(id: StringName, skeleton: Skeleton3D) -> AnimationLibrary:
	var _done := _settle()
	if not _libraries.has(BASE):
		_build(_inputs({CLIP_BODY: scene(body_path(CLIP_BODY))}), _libraries, _libraries)
	if id == CLIP_BODY or skeleton == null:
		return _libraries[BASE]
	if not _libraries.has(id):
		_libraries[id] = DotHumanoidClips.retarget(_libraries[BASE], _libraries[&"rests"], skeleton)
	return _libraries[id]


## Starts building the shared clip set and [param bodies]' retargets of it (each on its own model's
## skeleton) off the frame: on a worker thread where there are threads, else one per
## [method poll_libraries] call. The shared set alone is well over 100 ms in one frame.
static func prepare_libraries(bodies: Array[StringName] = []) -> void:
	var _done := _settle()
	if _tasks.any(func(t: Array) -> bool: return t[2] == _generation):
		_later.append_array(bodies)
		return
	var scenes := {}
	if not _libraries.has(BASE):
		scenes[CLIP_BODY] = scene(body_path(CLIP_BODY))
	for id in bodies:
		if id != CLIP_BODY and not _libraries.has(id):
			scenes[id] = scene(body_path(id))
	if scenes.is_empty():
		return
	if not DotPlatform.has_threads():
		_queued.merge(scenes)
		return
	# The worker reads only what is passed and writes only its own dictionary, read here once it is done.
	# Models are instanced here, not there: a mesh instance made off the main thread waits for the main thread.
	var out := {}
	var task := WorkerThreadPool.add_task(_build.bind(_inputs(scenes), out, _libraries.duplicate()), false, "DotHumanoidAssets clips")
	_tasks.append([task, out, _generation])


## Moves a [method prepare_libraries] build on. True when there is nothing left to wait for; false while
## the worker runs, and false after building the next clip set where there are no threads.
static func poll_libraries() -> bool:
	if not _settle():
		return false
	if not _later.is_empty():
		var bodies: Array[StringName] = _later.duplicate()
		_later.clear()
		prepare_libraries(bodies)
		return _tasks.is_empty() and _queued.is_empty()
	while not _queued.is_empty():
		var id: StringName = _queued.keys().front()
		var one := {id: _queued[id]}
		var _e := _queued.erase(id)
		if not _libraries.has(BASE if id == CLIP_BODY else id):
			_build(_inputs(one), _libraries, _libraries)
			return false
	return true


## Takes in every finished build (of this cache generation; an older one's is dropped). True when none is left running.
static func _settle() -> bool:
	var running: Array = []
	for t: Array in _tasks:
		if not WorkerThreadPool.is_task_completed(t[0]):
			running.append(t)
			continue
		var _w := WorkerThreadPool.wait_for_task_completion(t[0])
		if t[2] != _generation:
			continue
		var out: Dictionary = t[1]
		for key: StringName in out:
			if not _libraries.has(key):
				_libraries[key] = out[key]
	_tasks = running
	return running.is_empty()


## What [method _build] needs of each of [param scenes] (body id to model), read on the main thread:
## a bare copy of its skeleton (names, parents, rests; no mesh, so nothing on a server) and, for the clip
## body, its clips.
static func _inputs(scenes: Dictionary) -> Dictionary:
	var out := {}
	for id: StringName in scenes:
		var model: PackedScene = scenes[id]
		var probe := model.instantiate() if model != null else null
		var found: Array = probe.find_children("*", "Skeleton3D", true, false) if probe != null else []
		var bones: Skeleton3D = null
		if not found.is_empty():
			var from := found.front() as Skeleton3D
			bones = Skeleton3D.new()
			for i in from.get_bone_count():
				var _i := bones.add_bone(from.get_bone_name(i))
			for i in from.get_bone_count():
				bones.set_bone_parent(i, from.get_bone_parent(i))
				bones.set_bone_rest(i, from.get_bone_rest(i))
		out[id] = [bones, DotHumanoidClips.clips_of(probe) if id == CLIP_BODY else null]
		if probe != null:
			probe.free()
	return out


## Builds each of [param inputs] (from [method _inputs]) into [param out]: the clip body's as the shared
## set, its rests and sit height; any other's as its retarget of the shared set in [param out] or [param from].
## Thread-safe for a worker: it touches no node in a tree and no server, and writes nothing shared.
static func _build(inputs: Dictionary, out: Dictionary, from: Dictionary) -> void:
	for id: StringName in inputs:
		var skeleton: Skeleton3D = inputs[id][0]
		if id == CLIP_BODY:
			var library := DotHumanoidClips.mirror(DotHumanoidClips.library_from(inputs[id][1]))
			out[BASE] = DotHumanoidClips.synthesise(library, skeleton)
			var real_path := real_clips_path()
			var real: AnimationLibrary = load(real_path) as AnimationLibrary if ResourceLoader.exists(real_path) else null
			var _adopted := DotHumanoidClips.adopt(library, real)
			out[&"rests"] = DotHumanoidClips.rests_of(skeleton)
			out[&"sit_height"] = DotHumanoidClips.sit_height(library, skeleton)
		elif skeleton != null:
			var base: AnimationLibrary = out.get(BASE, from.get(BASE))
			out[id] = DotHumanoidClips.retarget(base, out.get(&"rests", from.get(&"rests", {})), skeleton)
		if skeleton != null:
			skeleton.free()


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
## A build still running is not waited for; its result is dropped, and [method poll_libraries] says when it is gone.
static func clear_cache() -> void:
	var _done := _settle()
	_generation += 1
	_later.clear()
	_queued.clear()
	_scenes.clear()
	_libraries.clear()
	_materials.clear()
	_shader = null
	_atlas = null


## The seated hip height of the shared clip set (0 until a library was built).
static func sit_height() -> float:
	return _libraries.get(&"sit_height", 0.0)
