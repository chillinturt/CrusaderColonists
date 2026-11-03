class_name HeroIntent
extends RefCounted
## What a hero wants to do this tick: the only way anything steers a Hero.
## HeroInput fills it from your keyboard and mouse, HeroBot from its own head
## (and a network peer could fill it from packets), so every hero plays by
## the same rules.

## Movement: x = right, y = back (like Input.get_vector), length <= 1.
var move := Vector2.ZERO
## Where you look (radians). Yaw turns the body; pitch only tilts the aim.
var yaw := 0.0
var pitch := 0.0
## Held buttons.
var jump := false
var gas := false
var fire := false
## The grappling hook: press to fire, hold to stay attached.
var hook := false
var reel_in := false
var reel_out := false
var reload := false
## One-shot requests, consumed by the hero: a slot to switch to (-1 = none),
## a step through the weapons (0 = none), or back to the last weapon.
var weapon_slot := -1
var weapon_cycle := 0
var weapon_last := false
## What the crosshair is on (third person: the camera's aim, not the eyes').
## INF = straight along yaw / pitch.
var aim_point := Vector3.INF


## Lets go of everything (yaw and pitch stay where they are).
func clear() -> void:
	move = Vector2.ZERO
	jump = false
	gas = false
	fire = false
	hook = false
	reel_in = false
	reel_out = false
	reload = false
	aim_point = Vector3.INF
