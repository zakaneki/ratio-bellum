# Base Unit class (used for both player and enemy units)
extends CharacterBody2D
class_name Unit
signal died(unit)

# Team: "player", "friendly", "enemy"
var side: String = "enemy"
@export var enemy_frames: SpriteFrames
@export var friendly_frames: SpriteFrames
# Class id: "warrior", "lancer", "archer", "monk"
var class_id: String = "warrior"

# Core stats
var max_hp: int = 1
var hp: int = 1
var move_range: int = 1
var attack_range: int = 1
var damage: int = 1

# Economy drop (for enemies)
@export var coin_value: int = 1
@export var is_captain: bool = false

# Grid position (managed by GameManager)
var grid_pos: Vector2i = Vector2i.ZERO

# Turn-state flags
var moved_this_turn: bool = false

func reset_turn_flags() -> void:
	moved_this_turn = false

func get_attack_damage() -> int:
	return damage

func take_damage(amount: int) -> void:
	var inc := amount
	hp -= inc
	if hp <= 0:
		emit_signal("died", self)
		queue_free()

# Specials are triggered via GameManager; helpers below encapsulate effects.

func _ready() -> void:
	var sprite = $AnimatedSprite2D
	match side:
		"enemy":
			sprite.sprite_frames = enemy_frames
		"friendly":
			sprite.sprite_frames = friendly_frames
	$AnimatedSprite2D.play("idle") 



# Simple enemy AI placeholder (unchanged)
func apply_enemy_ai():
	# Deterministic enemy logic placeholder
	pass

# Legacy rules API (kept for compatibility; no-ops here)
func apply_rules(_rules: Array):
	pass
