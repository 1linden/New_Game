extends Node

var button_clicked_sound: AudioStream = preload("res://assets/audio/button_clicked.wav")
var button_clicked_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	button_clicked_player = AudioStreamPlayer.new()
	button_clicked_player.process_mode = Node.PROCESS_MODE_ALWAYS
	button_clicked_player.stream = button_clicked_sound
	add_child(button_clicked_player)


func play_button_clicked() -> void:
	button_clicked_player.play()
