extends Control


func _ready() -> void:
	$StartGame.pressed.connect(_on_start_game_pressed)


func _on_start_game_pressed() -> void:
	UISounds.play_button_clicked()
	get_tree().change_scene_to_file("res://scenes/level_selector.tscn")
