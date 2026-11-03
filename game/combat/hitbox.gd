class_name Hitbox
extends StaticBody3D
## The part of an RTS unit or structure that heroes' shots, blades and blasts
## can touch. Units get a capsule on their team's hitbox layer (shots pass
## through, nobody bumps into it); structures get a solid box in the world
## layer (you can stand on a tower, and it stops bullets). Combat.resolve()
## turns a hit on this into a hit on `entity`.

var entity: RTSEntity


static func for_unit(unit: RTSEntity, radius: float, height: float) -> Hitbox:
	var box := Hitbox.new()
	box.entity = unit
	box.collision_layer = Combat.UNIT_LAYERS[unit.team]
	box.collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(radius, 0.35)
	capsule.height = maxf(height, capsule.radius * 2.0 + 0.1)
	var holder := CollisionShape3D.new()
	holder.shape = capsule
	holder.position.y = capsule.height * 0.5
	box.add_child(holder)
	unit.add_child(box)
	unit.hitbox = box
	return box


static func for_structure(structure: RTSEntity, width: float, height: float) -> Hitbox:
	var box := Hitbox.new()
	box.entity = structure
	box.collision_layer = Combat.WORLD
	box.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, width)
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.position.y = height * 0.5
	box.add_child(holder)
	structure.add_child(box)
	structure.hitbox = box
	return box
