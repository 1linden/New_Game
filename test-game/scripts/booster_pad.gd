extends Area2D

@export var launch_multiplier: float = 1.65

@onready var launch_direction: Marker2D = $LaunchDirection


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	var character := body as CharacterBody2D
	if character == null:
		return

	var direction := global_position.direction_to(launch_direction.global_position)
	if direction == Vector2.ZERO:
		return

	var jump_velocity := float(character.get("jump_velocity"))
	character.velocity = direction.normalized() * absf(jump_velocity) * launch_multiplier
