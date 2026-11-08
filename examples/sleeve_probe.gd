extends Node

## Probe: skins the view arms' mesh on the CPU in a held pose and lists triangles whose edges grew far past their bind length.

var mirror_on := true

func _ready() -> void:
	for body in ["matt", "lis", "sam", "shaun"]:
		for sc in [[0.5, 1.0], [0.35, 0.7], [0.3, 1.2]]:
			for two in [true, false]:
				await _probe(body, two, sc)
	get_tree().quit()


func _probe(body: String, two: bool, sc: Array) -> void:
	var arms := DotPlayerViewArms.new()
	add_child(arms)
	var weapon := Node3D.new()
	add_child(weapon)
	weapon.position = Vector3(0.08, -0.2, -0.4)
	var lk := DotHumanoidLook.stock(1)
	lk.body = StringName(body)
	arms.mirror_support_forearm = mirror_on
	arms.hand_scale = sc[0]
	arms.forearm_scale = sc[1]
	arms.build(lk, 1.8)
	var grip := Vector3(0.0, -0.08, 0.1)
	var fore := Vector3(-0.03, -0.07, -0.1)
	arms.set_held(DotViewGrip.two_hand(weapon, grip, fore) if two else DotViewGrip.one_hand(weapon, grip))
	for i in 8:
		arms.tick(0.0, 1.0 / 30.0)
		await get_tree().process_frame
	var fig := arms.arms() as DotHumanoidFigure
	var sk := fig.skeleton()
	var mi := fig.mesh()
	var mesh := mi.mesh as ArrayMesh
	var skin := mi.skin
	print("== %s two_hand %s scales %s" % [body, two, sc])
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var b: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var per := b.size() / v.size()
		var posed := PackedVector3Array()
		posed.resize(v.size())
		for i in v.size():
			var p := Vector3.ZERO
			for k in per:
				var wt := w[i * per + k]
				if wt <= 0.0:
					continue
				var bind := b[i * per + k]
				var bone := sk.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)
				p += wt * ((sk.get_bone_global_pose(bone) * skin.get_bind_pose(bind)) * v[i])
			posed[i] = p
		var bad := {}
		for t in range(0, idx.size() - 2, 3):
			for e in 3:
				var i0 := idx[t + e]
				var i1 := idx[t + (e + 1) % 3]
				var rest := v[i0].distance_to(v[i1])
				var now := posed[i0].distance_to(posed[i1])
				if "Leg" in _dom(sk, skin, b, w, i0, per) or "Foot" in _dom(sk, skin, b, w, i0, per):
					continue
				if now > maxf(rest * 3.0, 0.03):
					var key := "%s|%s" % [_dom(sk, skin, b, w, i0, per), _dom(sk, skin, b, w, i1, per)]
					bad[key] = bad.get(key, 0) + 1
					if bad[key] == 1:
						print("  edge rest %.3f now %.3f  at %s  %s" % [rest, now, posed[i0], key])
		print(" surface %d: %d tris, stretched edge kinds %s" % [s, idx.size() / 3, bad])
	arms.queue_free()
	weapon.queue_free()


func _dom(sk: Skeleton3D, skin: Skin, b: PackedInt32Array, w: PackedFloat32Array, i: int, per: int) -> String:
	var best := 0
	for k in per:
		if w[i * per + k] > w[i * per + best]:
			best = k
	var bind := b[i * per + best]
	return String(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else sk.get_bone_name(skin.get_bind_bone(bind))

