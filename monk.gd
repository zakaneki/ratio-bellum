extends Unit
class_name Monk


func _ready() -> void:
	super._ready()
	class_id = "monk"
	max_hp = 5; hp = max_hp
	move_range = 1
	attack_range = 2
	damage = 3
	coin_value = 3
	update_health_label()
	update_damage_label()
	
func play_attack_animation(target_pos = null):
	var sprite = $AnimatedSprite2D
	_play_sfx_random(sfx_heal)
	sprite.play("heal")

	if target_pos != null:
		var effect_sprite = AnimatedSprite2D.new()
		effect_sprite.sprite_frames = sprite.sprite_frames
		effect_sprite.animation = "heal_effect"
		effect_sprite.position = target_pos
		get_tree().current_scene.add_child(effect_sprite)
		effect_sprite.play("heal_effect")
		await effect_sprite.animation_finished
		effect_sprite.queue_free()
		
	sprite.play("idle")
	
func update_damage_label():
	var label = $DamageLabel
	label.text = "HL: %d" % damage
	label.position = Vector2(-90, -80) # Top left of sprite, adjust as needed
	label.visible = true
