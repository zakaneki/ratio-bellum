extends Panel

signal start_over
signal main_menu
signal quit_game

func _ready():
	$VBoxContainer/StartOver.pressed.connect(func(): emit_signal("start_over"))
	$VBoxContainer/MainMenu.pressed.connect(func(): emit_signal("main_menu"))
	$VBoxContainer/Quit.pressed.connect(func(): emit_signal("quit_game"))
