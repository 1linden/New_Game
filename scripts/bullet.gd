extends Area2D

@export var speed: float = 1400
@export var damage: int = 50

var direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	$VisibleOnScreenNotifier2D.screen_exited.connect(_on_screen_exited)


func launch(spawn_position: Vector2, spawn_rotation: float) -> void:
	global_position = spawn_position
	global_rotation = spawn_rotation
	direction = Vector2.RIGHT.rotated(spawn_rotation)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_bullet_damage"):
		body.take_bullet_damage(damage, direction)
	elif body.has_method("take_damage"):
		body.take_damage(damage)

	queue_free()


func _on_screen_exited() -> void:
	queue_free()
