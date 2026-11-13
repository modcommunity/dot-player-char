class_name DotPeopleCarryChecks
extends RefCounted

## The suite's gun-carry section ([DotHumanoidCarryPose]), split out to keep people_selftest under the file-size
## gate. Reports through the suite's `_section` and `_check`.

const DT := 1.0 / 60.0

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("a gun carried as others see it")
	var f := DotHumanoidFigure.new()
	suite.add_child(f)
	f.build(DotHumanoidLook.stock(9), 1.8)
	f.set_hold(DotHumanoidFigure.Hold.GUN)
	_frames(f, 0.0, 20)
	suite._check(f.carry.weight > 0.99 and f.carry.style != null and f.carry.style.id == &"rifle",
		"a gun is carried as a rifle until the game says otherwise (%s)" % f.carry.describe())
	suite._check(not f.carry.support_grip.is_finite(), "an implicit carry leaves the other hand to the clip")
	var gun := _gun(f)
	var want := f.carry.style.ready_grip * (f.height / 1.8)
	suite._check(gun.origin.distance_to(want) < 0.08, "standing, the gun hand is at the low ready (%s, want %s)" % [gun.origin, want])
	var muzzle := -gun.basis.z.normalized()
	suite._check(muzzle.z < -0.7 and muzzle.y < -0.1, "and the muzzle points ahead and down (%s)" % muzzle)

	f.carry.set_class(&"rifle")
	_frames(f, 0.0, 15)
	suite._check(f.carry.support_grip.is_finite() and f.carry.describe()["support"], "a rifle the game chose: the other hand takes the foregrip")
	_frames(f, 6.0, 30)
	suite._check(f.sprint_blend < 0.01, "sprinting with a carry: the carry swings the gun, not a second sprint (%.2f)" % f.sprint_blend)
	var sprint := _gun(f)
	suite._check(-sprint.basis.z.normalized().x < -0.2, "and sprinting it is carried across the body (%s)" % -sprint.basis.z)

	var a := _gun(f).origin
	_frames(f, 4.0, 9)
	var b := _gun(f).origin
	suite._check(a.distance_to(b) > 0.005, "running, the gun sways with the stride (%.3f m)" % a.distance_to(b))

	f.carry.fired()
	_frames(f, 0.0, 10)
	var aimed := _gun(f)
	suite._check(f.carry.aim > 0.99 and absf(-aimed.basis.z.normalized().y) < 0.2, "a shot shoulders it level (aim %.2f, muzzle %s)" % [f.carry.aim, -aimed.basis.z])
	_frames(f, 0.0, 120)
	suite._check(f.carry.aim < 0.01, "and it comes back down to the ready (%.2f)" % f.carry.aim)

	f.carry.reloading = true
	_frames(f, 0.0, 30)
	suite._check(f.carry.reload > 0.99 and f.carry.support_grip.is_finite(), "reloading rolls it in and the other hand goes for the magazine")
	f.carry.reloading = false
	f.carry.switching = true
	_frames(f, 0.0, 30)
	suite._check(f.carry.swap > 0.99 and not f.carry.support_grip.is_finite(), "changing weapon lowers it, the other hand off it")
	f.carry.switching = false

	f.set_motion({"swimming": true})
	_frames(f, 2.0, 30)
	suite._check(f.carry.weight < 0.01, "swimming: no carry (%.2f)" % f.carry.weight)
	f.set_motion({})
	_frames(f, 0.0, 30)
	f.carry.set_class(null)
	_frames(f, 0.0, 30)
	suite._check(f.carry.weight < 0.01, "a class of none: the clip's arms alone (%.2f)" % f.carry.weight)
	f.carry.set_class(&"pistol")
	_frames(f, 0.0, 20)
	suite._check(f.carry.weight > 0.99 and f.carry.style.id == &"pistol", "a pistol by name")
	suite._check(DotHumanoidCarry.for_class(&"knife") == null and DotHumanoidCarry.for_class(&"carbine").id == &"rifle",
		"a class held without a stance has none; a carbine reads as a rifle")
	f.queue_free()
	await suite.get_tree().process_frame


func _frames(f: DotHumanoidFigure, speed: float, n: int) -> void:
	for _i in n:
		f.animate(speed, DT)


## The gun's frame (the hand's frame for a weapon model) in the figure's.
func _gun(f: DotHumanoidFigure) -> Transform3D:
	var sk := f.skeleton()
	var hand := sk.get_bone_global_pose(sk.find_bone(DotHumanoidFigure.HAND_BONE))
	return f._to_figure() * hand * f.carry._hand_frame
