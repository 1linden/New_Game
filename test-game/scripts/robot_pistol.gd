extends CharacterBody2D

signal defeated

@export var maximum_health: int = 100
@export var bullet_scene: PackedScene
@export var shoot_range: float = 300
@export var shoot_cooldown_seconds: float = 1.5
@export var gun_rotation_offset: float = PI

var health: int
var shoot_cooldown_remaining: float = 0.0
var health_bar_fill_style := StyleBoxFlat.new()
var facing_right: bool = false
var damage_flash_tween: Tween

@onready var robot_left: Sprite2D = find_optional_node("RobotLeft", "Sprite2DLeft") as Sprite2D
@onready var robot_right: Sprite2D = find_optional_node("RobotRight", "Sprite2DRight") as Sprite2D
@onready var collision_left: CollisionShape2D = get_node_or_null("CollisionLeft") as CollisionShape2D
@onready var collision_right: CollisionShape2D = get_node_or_null("CollisionRight") as CollisionShape2D
@onready var gun_pivot_left: Node2D = find_optional_node("GunPivotLeft", "GunPivot") as Node2D
@onready var gun_pivot_right: Node2D = get_node_or_null("GunPivotRight") as Node2D
@onready var bullet_spawn_left: Marker2D = find_optional_node("GunPivotLeft/BulletSpawnLeft", "GunPivot/BulletSpawn") as Marker2D
@onready var bullet_spawn_right: Marker2D = get_node_or_null("GunPivotRight/BulletSpawnRight") as Marker2D
@onready var gunshot_sound: AudioStreamPlayer = $GunshotSound
@onready var enemy_take_damage_sound: AudioStreamPlayer = $EnemyTakeDamageSound
@onready var health_bar: ProgressBar = $HealthBar


func _ready() -> void:
	health = maximum_health
	setup_health_bar()
	update_facing(false)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()
	face_player()
	update_shooting(delta)


func face_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return

	facing_right = player.global_position.x > global_position.x
	update_facing(facing_right)
	if is_player_in_shoot_range(player):
		aim_gun_at(player.global_position)
	else:
		reset_active_gun_rotation()


func update_facing(use_right_side: bool) -> void:
	var has_right_robot := robot_right != null
	var has_right_gun := gun_pivot_right != null
	var has_right_collision := collision_right != null

	set_node_visible(robot_left, not use_right_side or not has_right_robot)
	set_node_visible(robot_right, use_right_side)
	set_node_visible(gun_pivot_left, not use_right_side or not has_right_gun)
	set_node_visible(gun_pivot_right, use_right_side)

	if collision_left != null:
		collision_left.disabled = use_right_side and has_right_collision
	if collision_right != null:
		collision_right.disabled = not use_right_side


func aim_gun_at(target_position: Vector2) -> void:
	var aim_direction := get_aim_origin().direction_to(target_position)
	if aim_direction == Vector2.ZERO:
		return

	var active_gun_pivot := get_active_gun_pivot()
	if active_gun_pivot == null:
		return

	active_gun_pivot.global_rotation = aim_direction.angle() if facing_right else aim_direction.angle() + gun_rotation_offset


func update_shooting(delta: float) -> void:
	if not is_level_started():
		return

	shoot_cooldown_remaining = maxf(shoot_cooldown_remaining - delta, 0.0)

	if shoot_cooldown_remaining > 0.0 or bullet_scene == null:
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return

	if not is_player_in_shoot_range(player):
		return

	if not has_line_of_sight_to(player):
		return

	shoot_at(player.global_position)
	shoot_cooldown_remaining = shoot_cooldown_seconds


func has_line_of_sight_to(target: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(get_aim_origin(), target.global_position, 1)
	query.exclude = [self]

	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func shoot_at(target_position: Vector2) -> void:
	var bullet := bullet_scene.instantiate() as Area2D
	get_tree().current_scene.add_child(bullet)

	var aim_origin := get_aim_origin()
	var shoot_direction := aim_origin.direction_to(target_position)
	var spawn_position := get_bullet_spawn_position()
	bullet.collision_layer = 16
	bullet.collision_mask = 3
	bullet.damage = 1
	bullet.launch(spawn_position, shoot_direction.angle())
	gunshot_sound.play()


func get_aim_origin() -> Vector2:
	var active_gun_pivot := get_active_gun_pivot()
	if active_gun_pivot != null:
		return active_gun_pivot.global_position

	return global_position


func get_bullet_spawn_position() -> Vector2:
	var active_bullet_spawn := get_active_bullet_spawn()
	if active_bullet_spawn != null:
		return active_bullet_spawn.global_position

	return get_aim_origin()


func get_active_gun_pivot() -> Node2D:
	if facing_right and gun_pivot_right != null:
		return gun_pivot_right

	return gun_pivot_left


func get_active_bullet_spawn() -> Marker2D:
	if facing_right and bullet_spawn_right != null:
		return bullet_spawn_right

	return bullet_spawn_left


func reset_active_gun_rotation() -> void:
	var active_gun_pivot := get_active_gun_pivot()
	if active_gun_pivot != null:
		active_gun_pivot.rotation = 0.0


func set_node_visible(node: CanvasItem, should_be_visible: bool) -> void:
	if node != null:
		node.visible = should_be_visible


func find_optional_node(primary_path: NodePath, fallback_path: NodePath) -> Node:
	var node := get_node_or_null(primary_path)
	if node != null:
		return node

	return get_node_or_null(fallback_path)


func is_player_in_shoot_range(player: Node2D) -> bool:
	return get_aim_origin().distance_to(player.global_position) <= shoot_range


func is_level_started() -> bool:
	var current_level := get_tree().current_scene
	return current_level == null or not current_level.has_method("is_level_started") or current_level.is_level_started()


func take_damage(amount: int) -> void:
	var previous_health := health
	health = max(health - amount, 0)
	update_health_bar()

	if health < previous_health:
		flash_damage()
		if health == 0:
			play_detached_take_damage_sound()
		else:
			enemy_take_damage_sound.play()

	if health == 0:
		die()


func play_detached_take_damage_sound() -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = enemy_take_damage_sound.stream
	sound.bus = enemy_take_damage_sound.bus
	get_tree().current_scene.add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func flash_damage() -> void:
	if damage_flash_tween != null:
		damage_flash_tween.kill()

	set_robot_modulate(Color(1, 0.2, 0.2))
	damage_flash_tween = create_tween()
	damage_flash_tween.tween_method(set_robot_modulate, Color(1, 0.2, 0.2), Color.WHITE, 0.2)


func set_robot_modulate(color: Color) -> void:
	if robot_left != null:
		robot_left.modulate = color
	if robot_right != null:
		robot_right.modulate = color


func setup_health_bar() -> void:
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color(0, 0, 0, 0.55)

	health_bar_fill_style.bg_color = get_health_bar_color(1.0)
	health_bar.add_theme_stylebox_override("background", background_style)
	health_bar.add_theme_stylebox_override("fill", health_bar_fill_style)
	update_health_bar()


func update_health_bar() -> void:
	var health_ratio := 0.0 if maximum_health <= 0 else float(health) / float(maximum_health)
	health_bar.visible = health < maximum_health
	health_bar.value = health_ratio * health_bar.max_value
	health_bar_fill_style.bg_color = get_health_bar_color(health_ratio)


func get_health_bar_color(health_ratio: float) -> Color:
	var red := Color.RED
	var yellow := Color.YELLOW
	var green := Color.GREEN

	if health_ratio <= 0.1:
		return red

	if health_ratio <= 0.5:
		return red.lerp(yellow, inverse_lerp(0.1, 0.5, health_ratio))

	return yellow.lerp(green, inverse_lerp(0.5, 1.0, health_ratio))


func die() -> void:
	defeated.emit()
	call_deferred("queue_free")
