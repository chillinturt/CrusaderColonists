class_name RTSEntity
extends Node3D
## Anything a team owns on the battlefield: units, structures, and the stand-in
## each hero has here (HeroAvatar). Holds health, armor, sight, the selection
## ring, and what it can attack. RTSUnit and RTSStructure build on it.
## Units and structures carry a Hitbox (a physics body) so heroes can shoot them.

var game: RTSGame
var team := 0
var kind := ""
var def: Dictionary = {}
var hp := 100.0
var max_hp := 100.0
var armor := 0.0
## Footprint radius: ranges and spacing are measured from its edge.
var radius := 0.5
var sight := 12.0
## How tall it is (health bars float above, shots leave from near the top).
var bar_height := 2.0
var flying := false
var is_structure := false
var dead := false
## Enemy structures stay shown once seen.
var discovered := false
## Hidden inside something (a peasant in an extractor).
var tucked_away := false
## Takes no damage (a lane tower or keep behind a standing tower).
var shielded := false
## Who hit it last (for kill credit: a HeroAvatar means a hero gets the gold).
var last_attacker: RTSEntity
var hitbox: Hitbox
var selected := false:
	set(value):
		selected = value
		if _ring:
			_ring.visible = value
var visual: Node3D

var _ring: MeshInstance3D


func setup(p_game: RTSGame, p_team: int, p_kind: String, p_def: Dictionary) -> void:
	game = p_game
	team = p_team
	kind = p_kind
	def = p_def
	max_hp = def.hp
	hp = max_hp
	armor = def.get("armor", 0.0)
	sight = def.get("sight", 12.0)
	bar_height = def.get("height", 2.0)


func display_name() -> String:
	return def.get("name", kind)


func can_attack() -> bool:
	return def.get("damage", 0.0) > 0.0


## Whether its attack can hit `other` (an enemy, on a layer it can reach).
func can_hit(other: RTSEntity) -> bool:
	if other == null or other.dead or other.team == team or other.team < 0 or not can_attack() or other.shielded:
		return false
	if other.flying:
		return def.get("air", false)
	return def.get("ground", false)


## Distance between the edges of the two footprints, on the ground plane.
func edge_distance(other: Node3D) -> float:
	var other_radius: float = other.get("radius") if other.get("radius") != null else 0.0
	var offset := other.global_position - global_position
	return Vector2(offset.x, offset.z).length() - radius - other_radius


func take_damage(amount: float, attacker: RTSEntity) -> void:
	if dead or shielded:
		return
	if attacker != null and is_instance_valid(attacker):
		last_attacker = attacker
	hp -= amount
	game.on_damaged(self, attacker)
	if hp <= 0.0:
		hp = 0.0
		die()


func die() -> void:
	if dead:
		return
	dead = true
	selected = false
	if hitbox:
		hitbox.queue_free()
		hitbox = null
	game.on_entity_died(self)
	_on_die()


## Hook: death effects. Removes itself when done.
func _on_die() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.3)
	tween.tween_callback(queue_free)


func _make_ring() -> void:
	var color := Color(0.35, 1.0, 0.45) if team == 0 else Color(1.0, 0.3, 0.25)
	_ring = RTSModels.ring(radius + 0.2, color)
	_ring.position.y = 0.08
	_ring.visible = selected
	add_child(_ring)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
