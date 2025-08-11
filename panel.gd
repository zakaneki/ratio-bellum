extends Panel

signal play_again
signal quit_game

func _ready():
	$VBoxContainer/PlayAgain.pressed.connect(func(): emit_signal("play_again"))
	$VBoxContainer/Quit.pressed.connect(func(): emit_signal("quit_game"))
