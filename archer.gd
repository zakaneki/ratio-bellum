extends Unit
class_name Archer

func _ready() -> void:
	super._ready()
	class_id = "archer"
	max_hp = 5; hp = max_hp
	move_range = 1
	attack_range = 3
	damage = 2
	coin_value = 3
	update_health_label()
	update_damage_label()
	
func play_attack_animation(target_pos = null):
	var sprite = $AnimatedSprite2D
	_play_sfx_random(sfx_attack)
	sprite.play("attack")
	if target_pos != null:
		_spawn_arrow(target_pos)
	await sprite.animation_finished
	sprite.play("idle")

func _spawn_arrow(target_pos: Vector2):
	var arrow_scene = preload("res://arrow.tscn")
	var arrow = arrow_scene.instantiate()
	arrow.position = $AnimatedSprite2D.global_position
	arrow.target_pos = target_pos
	get_tree().current_scene.add_child(arrow)
