extends Area2D

@export var vertical_launch_multiplier: float = 1.65
@export var horizontal_launch_strength: float = 1600

var booster_launch_sound: AudioStream = preload("res://assets/audio/booster_launch.wav")
var booster_launch_sound_player: AudioStreamPlayer

@onready var launch_direction: Marker2D = $LaunchDirection
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	booster_launch_sound_player = AudioStreamPlayer.new()
	booster_launch_sound_player.stream = booster_launch_sound
	add_child(booster_launch_sound_player)
	body_entered.connect(_on_body_entered)
	animated_sprite.play(&"Burn")


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	var character := body as CharacterBody2D
	if character == null:
		return

	var direction := global_position.direction_to(launch_direction.global_position).normalized()
	if direction == Vector2.ZERO:
		return

	var jump_velocity := float(character.get("jump_velocity"))
	var launch_velocity := Vector2(
		direction.x * horizontal_launch_strength,
		direction.y * absf(jump_velocity) * vertical_launch_multiplier
	)
	if character.has_method("apply_booster_launch"):
		character.apply_booster_launch(launch_velocity)
	else:
		character.velocity = launch_velocity

	booster_launch_sound_player.play()
