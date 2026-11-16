extends SceneTree

## A contact sheet of Kenney's characters: one row per clip, four times along it, from the side. Rendered, so not headless:
## xvfb-run -a godot --path . --script tools/kenney_sheet.gd -- [--pack=retro] [--skin=zombieMaleA] [--out=/tmp/kenney_sheet.png]

const CELL := Vector2i(200, 260)
const TIMES := 4

var _args := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	var pack := StringName(_args.get("pack", "protagonists"))
	var skin := StringName(_args.get("skin", DotKenneyCharacters.skins(pack)[0]))
	var clips: Array[StringName] = [&"idle", &"walk", &"run", &"jump", &"fall", &"land", &"death", &"idle_gun", &"walk_gun", &"run_gun", &"crouch", &"crouch_walk", &"crawl"]
	var sheet := Image.create(CELL.x * TIMES, CELL.y * clips.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.35, 0.4, 0.45))
	var viewport := SubViewport.new()
	viewport.size = CELL
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	viewport.add_child(camera)
	camera.position = Vector3(4, 0.9, 0.3)
	camera.look_at(Vector3(0, 0.9, 0.3))
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	light.rotation_degrees = Vector3(-35, 50, 0)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	viewport.add_child(floor_mesh)
	var person := DotKenneyCharacters.build(pack, skin)
	if person == null:
		quit(1)
		return
	viewport.add_child(person)
	var player := person.get_node("AnimationPlayer") as AnimationPlayer
	for row in clips.size():
		if not player.has_animation(clips[row]):
			continue
		var length := player.get_animation(clips[row]).length
		for col in TIMES:
			player.play(clips[row])
			player.seek(length * float(col) / float(TIMES), true)
			player.pause()
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await process_frame
			await process_frame
			var cell := viewport.get_texture().get_image()
			cell.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
	var out := String(_args.get("out", "/tmp/kenney_sheet.png"))
	print("saved ", out, " ", sheet.save_png(out), "  rows: ", clips)
	quit(0)
