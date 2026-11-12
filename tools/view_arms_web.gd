extends Node3D

## The first-person arms' materials side by side in a browser (nightly web-view-arms-white): the main scene of a
## scratch web export, shot through `gpu.sh browser-shot`. Columns left to right:
##   0 crowd material, plain mesh          1 DotViewArmsMaterial, arms mesh (CUSTOM0)
##   2 DotViewArmsMaterial, plain mesh     3 crowd material, arms mesh (CUSTOM0)
##   4 StandardMaterial3D with the atlas, plain mesh

const COLUMNS := ["crowd", "arms+custom0", "arms plain", "crowd+custom0", "standard"]


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("9aa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 4.2)
	cam.fov = 60.0
	add_child(cam)
	var look := DotHumanoidLook.stock(3)
	var stripper := DotPlayerViewArms.new()
	for i in COLUMNS.size():
		var figure := DotHumanoidFigure.new()
		add_child(figure)
		figure.build(look, 1.8)
		figure.position = Vector3((i - 2) * 0.9, 0, 0)
		var m := figure.mesh()
		if m == null:
			push_error("view_arms_web: no mesh")
			continue
		if i == 1 or i == 3:
			stripper._strip_gear(figure)
		match i:
			1, 2:
				m.material_override = DotViewArmsMaterial.for_look(look)
			4:
				var std := StandardMaterial3D.new()
				std.albedo_texture = DotHumanoidAssets.material_for(look).get_shader_parameter(&"atlas")
				std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				m.material_override = std
		print("view_arms_web: column %d %s material %s" % [i, COLUMNS[i], m.get_active_material(0)])
		var label := Label3D.new()
		label.text = "%d %s" % [i, COLUMNS[i]]
		label.font_size = 24
		label.position = Vector3(0, 2.0, 0)
		figure.add_child(label)
	stripper.free()
