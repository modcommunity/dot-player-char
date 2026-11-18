extends RefCounted

## Crouch and slide on a remote figure (motion dict only, no local prediction): the crouch amount lerps, the head
## glides between stances without a pop, and a slide keeps the head up where the hull is, not flat on the floor.

const DT := 1.0 / 60.0
const RUN := Vector3(0, 0, -6)
const WALK := Vector3(0, 0, -2.5)
var suite: Node


func _init(host: Node) -> void:
	suite = host


func _head(g: DotHumanoidFigure) -> Vector3:
	var sk := g.skeleton()
	sk.force_update_all_bone_transforms()
	return (g.global_transform.affine_inverse() * sk.global_transform) * sk.get_bone_global_pose(sk.find_bone("Head")).origin


## Settles on `a`, switches to `b`, returns {steps (head moves per frame), end (head), amounts (crouch_amount per frame)}.
func _run_seq(g: DotHumanoidFigure, a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {"steps": [], "end": Vector3.ZERO, "amounts": []}
	var last := Vector3.INF
	for phase in 2:
		var m := {"on_floor": true, "alive": true}
		m.merge(a if phase == 0 else b)
		var sp := (m.get("velocity", Vector3.ZERO) as Vector3).length()
		for i in 90 if phase == 0 else 60:
			g.set_motion(m)
			g.animate(sp, DT)
			var h := _head(g)
			if phase == 1:
				out["amounts"].append(g.crouch_amount)
				if last.is_finite():
					out["steps"].append(h.distance_to(last))
			last = h
			out["end"] = h
	return out


func run() -> void:
	suite._section("crouch and slide blend on a remote figure")
	var g := DotHumanoidFigure.new()
	suite.add_child(g)
	g.build(DotHumanoidLook.stock(9), 1.372)
	g.set_hold(DotHumanoidFigure.Hold.GUN)
	var stand := _run_seq(g, {}, {})
	var crouch := _run_seq(g, {}, {"crouched": true})
	var slide := _run_seq(g, {"velocity": RUN}, {"crouched": true, "sliding": true, "velocity": RUN})
	var rise := _run_seq(g, {"crouched": true, "sliding": true, "velocity": RUN}, {"velocity": RUN})
	var cw := _run_seq(g, {"velocity": WALK}, {"crouched": true, "velocity": WALK})
	var sh: float = (stand["end"] as Vector3).y
	var ch: float = (crouch["end"] as Vector3).y
	var lh: float = (slide["end"] as Vector3).y
	suite._check(g.crouch_amount > 0.99, "a slide leaves crouch_amount at 1 (%.2f)" % g.crouch_amount)
	var am: Array = crouch["amounts"]
	suite._check(am[0] < 0.2 and am[5] > am[0] and am[5] < 0.9 and am[-1] > 0.99, "crouch_amount ramps over a short time, not a switch (%.2f, %.2f, %.2f)" % [am[0], am[5], am[-1]])
	suite._check(ch < sh - 0.05, "a crouch lowers the head (%.2f to %.2f)" % [sh, ch])
	var worst := 0.0
	for s: Dictionary in [crouch, slide, rise, cw]:
		for d: float in s["steps"]:
			worst = maxf(worst, d)
	suite._check(worst < 0.1, "no stance pops: head moves at most %.3f a frame" % worst)
	suite._check(lh > ch - 0.15 and lh < ch + 0.1, "a slide holds the head at the hull, near the crouch (slide %.2f, crouch %.2f)" % [lh, ch])
	suite._check(lh > 0.45 * sh, "a slide is not flat on the ground (head %.2f of %.2f standing)" % [lh, sh])
	g.queue_free()
