extends Control


func _ready() -> void:
	$RestartButton.pressed.connect(_on_restart_button_pressed)
	$QuitButton.pressed.connect(_on_quit_button_pressed)


func _on_restart_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/start_game.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
