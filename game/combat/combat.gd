class_name Combat
extends RefCounted
## Where the two halves of the game meet: heroes (physics bodies, the
## third-person shooter) and the RTS battlefield (units and structures, plain
## Node3Ds that carry a Hitbox so heroes can shoot them). Teams, collision
## layers, damage in both directions, and explosions.
##
## Physics layers:
##   1      world: terrain, trees, rocks, crystals, structures (blocks everyone)
##   5      boundary: invisible walls at the edge of the map (heroes only)
##   6 / 7  RTS unit hitboxes of team 0 / team 1
##   8 / 9  heroes of team 0 / team 1
## A shot looks for the world plus the enemy team's layers, so it passes
## through teammates (no friendly fire) but not through walls.

const WORLD := 1
const BOUNDARY := 16
const UNIT_LAYERS: Array[int] = [32, 64]
const HERO_LAYERS: Array[int] = [128, 256]

## The match (set by RTSGame when it starts).
static var game: RTSGame


## Shots fired by `team`: walls and the other team's bodies.
static func shot_mask(team: int) -> int:
	return WORLD | enemy_bodies(team)


## The other team's heroes and unit hitboxes.
static func enemy_bodies(team: int) -> int:
	return UNIT_LAYERS[1 - team] | HERO_LAYERS[1 - team]


## What a collider stands for: a Hero, an RTSEntity (hit through its Hitbox),
## or null for scenery.
static func resolve(collider: Object) -> Object:
	if collider is Hero:
		return collider
	if collider is Hitbox:
		var entity: RTSEntity = (collider as Hitbox).entity
		return entity if is_instance_valid(entity) and not entity.dead else null
	return null


static func team_of(thing: Object) -> int:
	if thing is Hero:
		return (thing as Hero).team
	if thing is RTSEntity:
		return (thing as RTSEntity).team
	return -1


## Deals `amount` from `attacker` (a Hero, an RTSEntity, or null for the map
## itself) to `target` (a Hero or RTSEntity, see resolve()). Friendly fire does
## nothing, except to yourself (rocket jumps). True if it landed.
static func deal(target: Object, amount: float, attacker: Object, from: Vector3) -> bool:
	if target == null or amount <= 0.0:
		return false
	var attacker_team := team_of(attacker)
	if attacker_team >= 0 and team_of(target) == attacker_team and target != attacker:
		return false
	if target is Hero:
		var hero := target as Hero
		if hero.dead:
			return false
		hero.receive_damage(amount, attacker, from)
		return true
	if target is RTSEntity:
		var entity := target as RTSEntity
		if entity.dead or entity.shielded:
			return false
		var by: RTSEntity = (attacker as Hero).avatar if attacker is Hero else attacker as RTSEntity
		entity.take_damage(maxf(0.5, amount - entity.armor), by)
		return true
	return false


## A blast at `center` set off by `instigator` (a hero) for `team`: damages and
## launches enemies in the radius that aren't behind cover, and the instigator
## too at self_multiplier (rocket and grenade jumps). Structures are measured
## to their nearest wall, so a rocket into a tower's side counts as close.
static func explode(world: Node3D, center: Vector3, radius: float, damage: float, force: float,
		instigator: Hero, team: int, self_multiplier := 0.35, exclude: Array[RID] = []) -> void:
	var space := world.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = enemy_bodies(team) | HERO_LAYERS[team]
	params.exclude = exclude

	var hit := {}
	for result in space.intersect_shape(params, 48):
		var target := resolve(result.collider)
		if target == null or hit.has(target):
			continue
		if target is Hero and (target as Hero).team == team and target != instigator:
			continue
		hit[target] = true
		var body := result.collider as CollisionObject3D
		var aim_point: Vector3 = body.global_position + Vector3.UP * 0.9
		var cover_exclude: Array[RID] = exclude.duplicate()
		cover_exclude.append(body.get_rid())
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(center, aim_point, WORLD, cover_exclude)):
			continue
		var falloff := clampf(1.0 - center.distance_to(aim_point) / radius, 0.0, 1.0)
		var amount := damage * lerpf(0.2, 1.0, falloff)
		if target == instigator:
			amount *= self_multiplier
		deal(target, amount, instigator, center)
		if target is Hero:
			(target as Hero).push((aim_point - center).normalized() * force * falloff)

	if game:
		for entity in game.nearby(center, radius):
			if entity.is_structure and entity.team != team and not hit.has(entity):
				var edge := RTSEntity.flat(entity.global_position - center).length() - entity.radius
				var falloff := clampf(1.0 - maxf(edge, 0.0) / radius, 0.0, 1.0)
				deal(entity, damage * lerpf(0.2, 1.0, falloff), instigator, center)

	Explosion.spawn_fx(world.get_parent() if world.get_parent() else world, center, radius)
