class_name DotHumanoidCarry
extends Resource

## How a person seen by others carries a gun of one class: where the gun hand holds it and which way the muzzle
## points in each stance, how the gun sways with the gait, and where the other hand takes the foregrip.
## [DotHumanoidFigure] draws it ([member DotHumanoidFigure.carry], [method DotHumanoidCarryPose.set_class]); see docs/people.md, "Carrying a gun".
## Cosmetic only: the gun is drawn where the arms put it; hit zones and the shot never follow it.
##
## A grip is where the gun hand's grip sits on a 1.8 m figure standing in the held-gun pose, in the figure's frame
## (metres; +X right, +Y up, -Z forward, feet at 0). A turn is the muzzle's pitch, yaw and roll in degrees
## (pitch up positive, yaw to the left positive, roll clockwise as the holder sees it negative).

const CHANNEL := "player.humanoid"

## The classes [method for_class] knows.
const CLASSES: Array[StringName] = [&"rifle", &"smg", &"shotgun", &"sniper", &"heavy", &"pistol"]

## The class this describes, for [method describe].
@export var id: StringName = &"rifle"

## Moving or standing, not firing: the low ready, muzzle down ahead.
@export var ready_grip := Vector3(0.16, 0.74, -0.32)
@export var ready_turn := Vector3(-22.0, 8.0, 0.0)

## Firing or raised: shouldered, level with the view.
@export var aim_grip := Vector3(0.15, 0.86, -0.36)
@export var aim_turn := Vector3(0.0, 2.0, 0.0)

## Sprinting: across the chest, muzzle down to the left.
@export var sprint_grip := Vector3(0.12, 0.70, -0.24)
@export var sprint_turn := Vector3(-28.0, 35.0, -15.0)

## Reloading: pulled in and rolled so the magazine well faces the other hand.
@export var reload_grip := Vector3(0.12, 0.76, -0.28)
@export var reload_turn := Vector3(-2.0, 15.0, 35.0)

## Changing weapon: lowered by the side.
@export var swap_grip := Vector3(0.22, 0.58, -0.18)
@export var swap_turn := Vector3(-55.0, 10.0, 0.0)

## Whether the other hand holds the gun, and where, in the gun's frame (metres from the grip, -Z along the barrel).
@export var two_handed := true
@export var support := Vector3(0.0, -0.03, -0.30)

## Gait sway at a walk and at a run: x the bob (metres, twice a stride), y the side sway (metres, once a
## stride), z the turn (degrees of yaw, with a little roll and pitch). Damped while firing.
@export var walk_sway := Vector3(0.010, 0.012, 2.5)
@export var run_sway := Vector3(0.025, 0.022, 5.0)

## How much the gun turns with the chest (lean and twist of the clip) at the ready; aiming holds it nearer the view.
@export_range(0.0, 1.0) var follow := 0.5

## A shot's kick: metres back along the barrel and degrees of muzzle climb, gone in a tenth of a second.
@export var kick := 0.03
@export var kick_climb := 4.0


## A new carry for [param kind] (one of [constant CLASSES]; "smg", "carbine", "assault" and the like read as
## the nearest), or null for a class held in one hand without a stance (melee, thrown). Each call builds its own.
static func for_class(kind: StringName) -> DotHumanoidCarry:
	var c: DotHumanoidCarry = new()
	match String(kind).to_lower():
		"rifle", "assault", "carbine", "ar", "lmg":
			c.id = &"rifle"
		"smg":
			c.id = &"smg"
			c.ready_turn = Vector3(-26.0, 8.0, 0.0)
			c.aim_grip = Vector3(0.14, 0.85, -0.38)
			c.support = Vector3(0.0, -0.03, -0.22)
			c.kick = 0.02
		"shotgun":
			c.id = &"shotgun"
			c.kick = 0.06
			c.kick_climb = 9.0
		"sniper", "marksman", "dmr":
			c.id = &"sniper"
			c.ready_turn = Vector3(-15.0, 6.0, 0.0)
			c.aim_grip = Vector3(0.15, 0.88, -0.34)
			c.support = Vector3(0.0, -0.03, -0.36)
			c.kick = 0.05
			c.kick_climb = 7.0
		"heavy", "minigun", "launcher":
			c.id = &"heavy"
			c.ready_grip = Vector3(0.20, 0.64, -0.28)
			c.ready_turn = Vector3(-8.0, 4.0, 0.0)
			c.aim_grip = Vector3(0.19, 0.68, -0.34)
			c.aim_turn = Vector3(0.0, 2.0, 0.0)
			c.sprint_grip = Vector3(0.14, 0.66, -0.22)
			c.sprint_turn = Vector3(-30.0, 30.0, -15.0)
			c.support = Vector3(0.0, -0.05, -0.34)
			c.follow = 0.6
			c.kick = 0.02
		"pistol", "handgun", "revolver":
			c.id = &"pistol"
			c.ready_grip = Vector3(0.06, 0.76, -0.30)
			c.ready_turn = Vector3(-35.0, 5.0, 0.0)
			c.aim_grip = Vector3(0.07, 0.90, -0.46)
			c.aim_turn = Vector3(0.0, 0.0, 0.0)
			c.sprint_grip = Vector3(0.25, 0.60, -0.14)
			c.sprint_turn = Vector3(-65.0, 0.0, 0.0)
			c.reload_grip = Vector3(0.10, 0.78, -0.28)
			c.reload_turn = Vector3(5.0, 10.0, 20.0)
			c.swap_grip = Vector3(0.24, 0.58, -0.14)
			c.swap_turn = Vector3(-65.0, 0.0, 0.0)
			c.support = Vector3(-0.04, -0.02, -0.01)
			c.walk_sway = Vector3(0.008, 0.010, 2.0)
			c.run_sway = Vector3(0.020, 0.018, 4.0)
			c.follow = 0.4
			c.kick = 0.02
			c.kick_climb = 8.0
		_:
			return null
	return c


## The class and whether it is two-handed.
func describe() -> Dictionary:
	return {"id": String(id), "two_handed": two_handed}
