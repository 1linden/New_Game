extends Control


func _ready() -> void:
	$MainMenu.pressed.connect(_on_main_menu_pressed)


func _on_main_menu_pressed() -> void:
	UISounds.play_button_clicked()
	get_tree().change_scene_to_file("res://scenes/start_game.tscn")
