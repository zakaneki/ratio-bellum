extends Node2D

var target_pos: Vector2
var travel_time := 0.4 # seconds

func _ready():
	# Rotate arrow to face target (arrow faces right by default)
	var dir = (target_pos - position).normalized()
	$Sprite2D.rotation = dir.angle()
	# Move toward target
	var tween := create_tween()
	tween.tween_property(self, "position", target_pos, travel_time)
	tween.tween_callback(Callable(self, "queue_free"))
