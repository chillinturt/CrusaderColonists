class_name HeroAvatar
extends RTSEntity
## A hero's stand-in on the RTS battlefield (a child of the Hero, so it's
## always where the hero is). Units, towers and keeps find it, chase it and
## shoot it like any other enemy, the fog counts its sight, and the minimap
## draws it; damage it takes goes straight to the hero. While the hero is dead
## it's taken off the battlefield.
## It counts as flying while the hero is high off the ground (swinging on the
## hook, rocket jumping), so only attacks that hit air can reach it there.

const FLYING_HEIGHT := 3.5

var hero: Hero


func setup_avatar(p_game: RTSGame, p_hero: Hero) -> void:
	hero = p_hero
	setup(p_game, hero.team, "hero", {"name": hero.hero_name, "hp": hero.max_health, "armor": 0.0, "sight": 28.0,
		"height": 2.0, "damage": 1.0, "air": true, "ground": true})
	radius = 0.45


func take_damage(amount: float, attacker: RTSEntity) -> void:
	if dead or hero.dead:
		return
	var from := global_position
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
		from = attacker.global_position
	hero.receive_damage(amount, attacker, from)
	game.on_damaged(self, attacker)


## Called by the hero every tick.
func sync() -> void:
	hp = maxf(hero.health, 0.0)
	max_hp = hero.max_health
	dead = hero.dead
	flying = hero.global_position.y - game.map.height_at(hero.global_position.x, hero.global_position.z) > FLYING_HEIGHT


func display_name() -> String:
	return hero.hero_name
