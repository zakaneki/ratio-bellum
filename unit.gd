# Base Unit class (used for both player and enemy units)
extends CharacterBody2D
class_name Unit
signal died(unit)

var side: String = "enemy"
@export var enemy_frames: SpriteFrames
@export var friendly_frames: SpriteFrames
var class_id: String = "warrior"
@export var sfx_attack: Array[AudioStream] = []
@export var sfx_run: AudioStream
@export var sfx_heal: Array[AudioStream] = []
@export var sfx_death: Array[AudioStream] = []

# Core stats
var max_hp: int = 1
var hp: int = 1
var move_range: int = 1
var attack_range: int = 1
var damage: int = 1
var ap: int = 2 # Action Points per turn
# Economy drop (for enemies)
@export var coin_value: int = 1
@export var is_captain: bool = false

# Grid position (managed by GameManager)
var grid_pos: Vector2i = Vector2i.ZERO

# Turn-state flags
var sprinted_this_turn: bool = false
var tp_cooldown: int = 0
var teleport_active_modifier: bool = false
var move_cd: int = 0
var carrying_token: bool = false

func reset_turn_flags() -> void:
	sprinted_this_turn = false
	if tp_cooldown > 0:
		tp_cooldown -= 1
	if move_cd > 0:
		move_cd -= 1
	ap = 2
	update_ap_label()
	update_health_label()
	update_damage_label()
	update_coin_cd_label()

func get_attack_damage() -> int:
	return damage

func take_damage(amount: int) -> void:
	var inc := amount
	hp -= inc
	if hp <= 0:
		play_death_sfx()
		emit_signal("died", self)
		queue_free()
	update_health_label()

func _ready() -> void:
	var sprite = $AnimatedSprite2D
	match side:
		"enemy":
			sprite.sprite_frames = enemy_frames
		"friendly":
			sprite.sprite_frames = friendly_frames
	$AnimatedSprite2D.play("idle") 

func update_ap_label():
	var label = $APLabel
	label.text = str(ap) + " AP"
	label.position = Vector2(-90, 40) # Adjust offset as needed
	label.visible = (side == "friendly") # Only show for friendly units
	
func update_health_label():
	var label = $HealthLabel
	label.text = "❤️: %d" % hp
	label.position = Vector2(30, -80) # Top right of sprite, adjust as needed
	label.visible = true

func update_damage_label():
	var label = $DamageLabel
	label.text = "⚔️: %d" % damage
	label.position = Vector2(-90, -80) # Top left of sprite, adjust as needed
	label.visible = true
	
func update_coin_cd_label():
	var label = $CoinCDLabel
	label.position = Vector2(30, 40)
	if side == "enemy":
		label.text = "💰: %d" % coin_value
		label.visible = true
	elif side == "friendly" and teleport_active_modifier:
		label.text = "⏳: %s" % (str((tp_cooldown - 1)) if tp_cooldown > 0 else "✅")
		label.visible = true
	else:
		label.visible = false

func set_ap(value: int):
	ap = value
	update_ap_label()

func set_hp(value: int):
	hp = value
	update_health_label()

func set_damage(value: int):
	damage = value
	update_damage_label()
	
func play_attack_animation():
	var sprite = $AnimatedSprite2D
	_play_sfx_random(sfx_attack)
	sprite.play("attack")
	await sprite.animation_finished
	sprite.play("idle")
	
func play_move_animation(target_pos: Vector2):
	var sprite = $AnimatedSprite2D
	sprite.play("run")
	var player := AudioStreamPlayer2D.new()
	player.stream = sfx_run
	player.volume_db = -2.0
	get_tree().current_scene.add_child(player)
	player.global_position = global_position
	# Pick a random start time (e.g. between 0 and 2 seconds, adjust for your file length)
	var max_start = max(0.0, sfx_run.get_length() - 2.0)
	player.seek(randf_range(0.0, max_start))
	player.play()
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	timer.connect("timeout", Callable(player, "stop"))
	timer.connect("timeout", Callable(player, "queue_free"))
	player.add_child(timer)
	timer.start()
	var duration := 0.3
	var start := position
	var t := 0.0
	while t < duration:
		t += get_process_delta_time()
		position = start.lerp(target_pos, t / duration)
		await get_tree().process_frame
	position = target_pos
	sprite.play("idle")
	
func _play_sfx_random(streams: Array, volume_db: float = 0.0) -> void:
	if streams.is_empty():
		return
	var stream = streams[randi_range(0, streams.size() - 1)]
	if stream == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.volume_db = volume_db
	# p.bus = "SFX" # optional: use a dedicated bus if you have one
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.finished.connect(p.queue_free)
	p.play()

func play_death_sfx():
	_play_sfx_random(sfx_death, -1.0)
