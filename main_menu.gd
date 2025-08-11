extends Control

@onready var rules_overlay: Panel = $RulesOverlay

func _ready() -> void:
	if has_node("/root/MusicManager"):
		get_node("/root/MusicManager").fade_to_menu()
	rules_overlay.visible = false

func _on_play_button_pressed() -> void:
	if has_node("/root/MusicManager"):
		get_node("/root/MusicManager").fade_to_gameplay()
	if ResourceLoader.exists("res://main.tscn"):
		get_tree().change_scene_to_file("res://main.tscn")

func _on_rules_button_pressed() -> void:
	rules_overlay.visible = true

func _on_back_button_pressed() -> void:
	rules_overlay.visible = false

func _on_quit_button_pressed() -> void:
	get_tree().quit()

func _on_rich_text_label_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))
