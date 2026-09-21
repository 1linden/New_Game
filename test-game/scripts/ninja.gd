extends CharacterBody2D

signal health_changed(new_health: int)
signal player_died

enum BlockWalkState { NONE, ENTERING, WALKING, EXITING, EXITING_TO_WALK }

@export var movement_speed: float = 250.0
@export var sprint_multiplier: float = 1.5
@export var jump_velocity: float = -600.0
@export var maximum_health: int = 3
@export var attack_damage: int = 50
@export var attack_cooldown_seconds: float = 0.4
@export var land_animation_seconds: float = 0.12
@export var horizontal_boost_deceleration: float = 1100
@export var starts_facing_left: bool = false

var health: int
var is_dead: bool = false
var is_attacking: bool = false
var attack_cooldown_remaining: float = 0.0
var land_animation_remaining: float = 0.0
var was_blocking: bool = false
var is_releasing_block: bool = false
var block_walk_state: int = BlockWalkState.NONE
var block_walk_uses_transition: bool = false
var enemies_hit_this_attack: Array[Node] = []
var damage_flash_tween: Tween
var horizontal_boost: float = 0.0
var god_mode_enabled: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_walk: CollisionShape2D = $CollisionWalk
@onready var collision_standing: CollisionShape2D = $CollisionStanding
@onready var collision_jump: CollisionShape2D = $CollisionJump
@onready var collision_fall: CollisionShape2D = $CollisionFall
@onready var collision_land: CollisionShape2D = $CollisionLand
@onready var collision_block: CollisionShape2D = $CollisionBlock
@onready var collision_block_walk: CollisionShape2D = $CollisionBlockWalk
@onready var collision_attack_0: CollisionShape2D = $CollisionAttack0
@onready var collision_attack_1: CollisionShape2D = $CollisionAttack1
@onready var collision_attack_2: CollisionShape2D = $CollisionAttack2
@onready var collision_attack_3: CollisionShape2D = $CollisionAttack3
@onready var collision_attack_4: CollisionShape2D = $CollisionAttack4
@onready var collision_attack_5: CollisionShape2D = $CollisionAttack5
@onready var collision_walk_flipped: CollisionShape2D = $CollisionWalkFlipped
@onready var collision_standing_flipped: CollisionShape2D = $CollisionStandingFlipped
@onready var collision_jump_flipped: CollisionShape2D = $CollisionJumpFlipped
@onready var collision_fall_flipped: CollisionShape2D = $CollisionFallFlipped
@onready var collision_land_flipped: CollisionShape2D = $CollisionLandFlipped
@onready var collision_block_flipped: CollisionShape2D = $CollisionBlockFlipped
@onready var collision_block_walk_flipped: CollisionShape2D = $CollisionBlockWalkFlipped
@onready var collision_attack_0_flipped: CollisionShape2D = $CollisionAttack0Flipped
@onready var collision_attack_1_flipped: CollisionShape2D = $CollisionAttack1Flipped
@onready var collision_attack_2_flipped: CollisionShape2D = $CollisionAttack2Flipped
@onready var collision_attack_3_flipped: CollisionShape2D = $CollisionAttack3Flipped
@onready var collision_attack_4_flipped: CollisionShape2D = $CollisionAttack4Flipped
@onready var collision_attack_5_flipped: CollisionShape2D = $CollisionAttack5Flipped
@onready var take_damage_sound: AudioStreamPlayer = $TakeDamageSound
@onready var attack_sound: AudioStreamPlayer = $AttackSound


func _ready() -> void:
	health = maximum_health
	animated_sprite.flip_h = starts_facing_left
	if animated_sprite.sprite_frames.has_animation(&"BlockWalkTransition"):
		animated_sprite.sprite_frames.set_animation_loop(&"BlockWalkTransition", false)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	play_standing_animation()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	var was_on_floor := is_on_floor()

	if not is_on_floor():
		velocity += get_gravity() * delta
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)

	var direction := Input.get_axis("move_left", "move_right")
	var current_movement_speed := movement_speed * sprint_multiplier if direction != 0.0 and Input.is_action_pressed("sprint") and not is_blocking() else movement_speed
	var movement_velocity := direction * current_movement_speed
	if absf(horizontal_boost) > 50.0:
		movement_velocity *= 0.05

	velocity.x = movement_velocity + horizontal_boost
	horizontal_boost = move_toward(horizontal_boost, 0.0, horizontal_boost_deceleration * delta)

	if is_attacking and is_on_floor() and absf(horizontal_boost) <= 50.0:
		velocity.x = 0.0

	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	if direction != 0.0:
		animated_sprite.flip_h = direction < 0.0

	var blocking := is_blocking()
	var moving_sideways := direction != 0.0
	var block_just_pressed := Input.is_action_just_pressed("block")

	if is_attacking:
		play_attack_animation()
	elif blocking:
		is_releasing_block = false
		update_block_animation(moving_sideways, block_just_pressed, is_on_floor())

	move_and_slide()

	if is_attacking:
		play_attack_animation()
		handle_attack_damage()
		return

	if blocking:
		was_blocking = true
		update_block_animation(moving_sideways, block_just_pressed, is_on_floor())
		return

	if was_blocking:
		was_blocking = false
		if moving_sideways and is_in_block_walk_animation():
			start_block_walk_transition(BlockWalkState.EXITING_TO_WALK)
			return

		start_block_release_animation()
		return

	if block_walk_state == BlockWalkState.EXITING_TO_WALK:
		play_block_walk_transition()
		return

	if is_releasing_block:
		use_block_collision()
		return

	update_jump_animation(delta, was_on_floor, direction)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and can_start_attack():
		start_attack()


func update_jump_animation(delta: float, was_on_floor: bool, direction: float) -> void:
	if not was_on_floor and is_on_floor():
		land_animation_remaining = land_animation_seconds

	if land_animation_remaining > 0.0:
		land_animation_remaining = maxf(land_animation_remaining - delta, 0.0)
		play_land_animation()
		return

	if not is_on_floor():
		if velocity.y < 0.0:
			play_jump_animation()
		else:
			play_fall_animation()
		return

	if direction != 0.0:
		play_movement_animation()
	else:
		play_standing_animation()


func play_movement_animation() -> void:
	use_walk_collision()
	var animation_name := &"Sprint" if Input.is_action_pressed("sprint") else &"Walk"
	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)


func play_standing_animation() -> void:
	use_standing_collision()
	if animated_sprite.animation != &"Standing":
		animated_sprite.play(&"Standing")


func play_jump_animation() -> void:
	use_jump_collision()
	if animated_sprite.animation != &"Jump":
		animated_sprite.play(&"Jump")


func play_fall_animation() -> void:
	use_fall_collision()
	if animated_sprite.animation != &"Fall":
		animated_sprite.play(&"Fall")


func play_land_animation() -> void:
	use_land_collision()
	if animated_sprite.animation != &"Land":
		animated_sprite.play(&"Land")


func play_block_animation() -> void:
	use_block_collision()
	is_releasing_block = false

	if animated_sprite.animation != &"Block":
		animated_sprite.play(&"Block")
	elif not animated_sprite.is_playing() and not is_on_last_block_frame():
		animated_sprite.play(&"Block")


func update_block_animation(moving_sideways: bool, block_just_pressed: bool, can_block_walk: bool) -> void:
	if not can_block_walk:
		var was_block_walking := is_in_block_walk_animation()
		block_walk_state = BlockWalkState.NONE
		block_walk_uses_transition = false
		if was_block_walking:
			show_last_block_frame()
		else:
			play_block_animation()
		return

	if moving_sideways:
		if block_walk_state == BlockWalkState.WALKING:
			play_block_walk_animation()
		elif block_walk_state == BlockWalkState.ENTERING:
			play_block_walk_transition()
		elif block_just_pressed:
			block_walk_uses_transition = true
			start_block_walk_transition(BlockWalkState.ENTERING)
		else:
			block_walk_uses_transition = false
			block_walk_state = BlockWalkState.WALKING
			play_block_walk_animation()
		return

	if block_walk_state == BlockWalkState.WALKING:
		block_walk_state = BlockWalkState.NONE
		block_walk_uses_transition = false
		show_last_block_frame()
	elif block_walk_state == BlockWalkState.EXITING:
		play_block_walk_transition()
	elif block_walk_state == BlockWalkState.ENTERING:
		block_walk_state = BlockWalkState.NONE
		block_walk_uses_transition = false
		show_last_block_frame()
	else:
		block_walk_state = BlockWalkState.NONE
		block_walk_uses_transition = false
		play_block_animation()


func start_block_walk_transition(next_state: int) -> void:
	block_walk_state = next_state
	use_block_walk_collision()

	if animated_sprite.animation != &"BlockWalkTransition" or not animated_sprite.is_playing():
		animated_sprite.play(&"BlockWalkTransition")


func play_block_walk_transition() -> void:
	use_block_walk_collision()
	if animated_sprite.animation != &"BlockWalkTransition":
		animated_sprite.play(&"BlockWalkTransition")


func play_block_walk_animation() -> void:
	use_block_walk_collision()
	if animated_sprite.animation != &"BlockWalk":
		animated_sprite.play(&"BlockWalk")


func show_last_block_frame() -> void:
	is_releasing_block = false
	use_block_collision()
	animated_sprite.animation = &"Block"
	animated_sprite.set_frame_and_progress(animated_sprite.sprite_frames.get_frame_count(&"Block") - 1, 1.0)
	animated_sprite.pause()


func is_in_block_walk_animation() -> bool:
	return block_walk_state != BlockWalkState.NONE or animated_sprite.animation == &"BlockWalk" or animated_sprite.animation == &"BlockWalkTransition"


func start_block_release_animation() -> void:
	is_releasing_block = true
	block_walk_state = BlockWalkState.NONE
	block_walk_uses_transition = false
	use_block_collision()

	if animated_sprite.animation != &"Block":
		animated_sprite.animation = &"Block"
		animated_sprite.set_frame_and_progress(animated_sprite.sprite_frames.get_frame_count(&"Block") - 1, 1.0)

	animated_sprite.play_backwards(&"Block")


func is_on_last_block_frame() -> bool:
	if animated_sprite.animation != &"Block":
		return false

	return animated_sprite.frame >= animated_sprite.sprite_frames.get_frame_count(&"Block") - 1


func start_attack() -> void:
	is_attacking = true
	is_releasing_block = false
	was_blocking = false
	block_walk_state = BlockWalkState.NONE
	block_walk_uses_transition = false
	attack_cooldown_remaining = attack_cooldown_seconds
	enemies_hit_this_attack.clear()
	play_attack_animation()
	attack_sound.play()


func can_start_attack() -> bool:
	if is_attacking or attack_cooldown_remaining > 0.0:
		return false

	return true


func play_attack_animation() -> void:
	use_attack_collision(get_current_attack_collision())
	if animated_sprite.animation != &"Attack":
		animated_sprite.play(&"Attack")


func handle_attack_damage() -> void:
	var active_attack_collision := get_current_attack_collision()
	use_attack_collision(active_attack_collision)

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = active_attack_collision.shape
	query.transform = active_attack_collision.global_transform
	query.collision_mask = 4
	query.exclude = [self]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var collider := result["collider"] as Node
		var robot := get_attack_damage_target(collider)
		if robot == null or robot in enemies_hit_this_attack or not robot.has_method("take_damage"):
			continue

		enemies_hit_this_attack.append(robot)
		robot.take_damage(attack_damage)


func get_attack_damage_target(collider: Node) -> Node:
	var current_node := collider
	while current_node != null:
		if current_node.has_method("take_damage"):
			return current_node

		current_node = current_node.get_parent()

	return null


func get_current_attack_collision() -> CollisionShape2D:
	match animated_sprite.frame:
		0:
			return get_facing_collision(collision_attack_0, collision_attack_0_flipped)
		1:
			return get_facing_collision(collision_attack_1, collision_attack_1_flipped)
		2:
			return get_facing_collision(collision_attack_2, collision_attack_2_flipped)
		3:
			return get_facing_collision(collision_attack_3, collision_attack_3_flipped)
		4:
			return get_facing_collision(collision_attack_4, collision_attack_4_flipped)
		_:
			return get_facing_collision(collision_attack_5, collision_attack_5_flipped)


func use_walk_collision() -> void:
	set_collision_shape(get_facing_collision(collision_walk, collision_walk_flipped))


func use_standing_collision() -> void:
	set_collision_shape(get_facing_collision(collision_standing, collision_standing_flipped))


func use_jump_collision() -> void:
	set_collision_shape(get_facing_collision(collision_jump, collision_jump_flipped))


func use_fall_collision() -> void:
	set_collision_shape(get_facing_collision(collision_fall, collision_fall_flipped))


func use_land_collision() -> void:
	set_collision_shape(get_facing_collision(collision_land, collision_land_flipped))


func use_block_collision() -> void:
	set_collision_shape(get_facing_collision(collision_block, collision_block_flipped))


func use_block_walk_collision() -> void:
	set_collision_shape(get_facing_collision(collision_block_walk, collision_block_walk_flipped))


func use_attack_collision(active_shape: CollisionShape2D) -> void:
	set_collision_shape(active_shape)


func get_facing_collision(normal_shape: CollisionShape2D, flipped_shape: CollisionShape2D) -> CollisionShape2D:
	return flipped_shape if animated_sprite.flip_h else normal_shape


func set_collision_shape(active_shape: CollisionShape2D) -> void:
	collision_walk.disabled = active_shape != collision_walk
	collision_standing.disabled = active_shape != collision_standing
	collision_jump.disabled = active_shape != collision_jump
	collision_fall.disabled = active_shape != collision_fall
	collision_land.disabled = active_shape != collision_land
	collision_block.disabled = active_shape != collision_block
	collision_block_walk.disabled = active_shape != collision_block_walk
	collision_attack_0.disabled = active_shape != collision_attack_0
	collision_attack_1.disabled = active_shape != collision_attack_1
	collision_attack_2.disabled = active_shape != collision_attack_2
	collision_attack_3.disabled = active_shape != collision_attack_3
	collision_attack_4.disabled = active_shape != collision_attack_4
	collision_attack_5.disabled = active_shape != collision_attack_5
	collision_walk_flipped.disabled = active_shape != collision_walk_flipped
	collision_standing_flipped.disabled = active_shape != collision_standing_flipped
	collision_jump_flipped.disabled = active_shape != collision_jump_flipped
	collision_fall_flipped.disabled = active_shape != collision_fall_flipped
	collision_land_flipped.disabled = active_shape != collision_land_flipped
	collision_block_flipped.disabled = active_shape != collision_block_flipped
	collision_block_walk_flipped.disabled = active_shape != collision_block_walk_flipped
	collision_attack_0_flipped.disabled = active_shape != collision_attack_0_flipped
	collision_attack_1_flipped.disabled = active_shape != collision_attack_1_flipped
	collision_attack_2_flipped.disabled = active_shape != collision_attack_2_flipped
	collision_attack_3_flipped.disabled = active_shape != collision_attack_3_flipped
	collision_attack_4_flipped.disabled = active_shape != collision_attack_4_flipped
	collision_attack_5_flipped.disabled = active_shape != collision_attack_5_flipped


func take_bullet_damage(amount: int, bullet_direction: Vector2) -> void:
	if is_blocking_against_bullet(bullet_direction):
		return

	take_damage(amount)


func apply_booster_launch(launch_velocity: Vector2) -> void:
	horizontal_boost = launch_velocity.x
	if not is_zero_approx(launch_velocity.y):
		velocity.y = launch_velocity.y


func take_damage(amount: int) -> void:
	if is_dead or god_mode_enabled:
		return

	var previous_health := health
	health = max(health - amount, 0)
	health_changed.emit(health)

	if health < previous_health:
		take_damage_sound.play()
		flash_damage()

	if health == 0:
		die()


func die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	player_died.emit()


func flash_damage() -> void:
	if damage_flash_tween != null:
		damage_flash_tween.kill()

	animated_sprite.modulate = Color(1, 0.2, 0.2)
	damage_flash_tween = create_tween()
	damage_flash_tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.2)


func is_blocking() -> bool:
	return Input.is_action_pressed("block")


func is_blocking_against_bullet(bullet_direction: Vector2) -> bool:
	if is_attacking:
		return false

	if not is_blocking():
		return false

	var facing_direction := Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
	var incoming_direction := -bullet_direction.normalized()
	return facing_direction.dot(incoming_direction) > 0.0


func _on_animation_finished() -> void:
	if animated_sprite.animation == &"Attack" and is_attacking:
		is_attacking = false
		enemies_hit_this_attack.clear()
		return

	if animated_sprite.animation == &"BlockWalkTransition":
		if block_walk_state == BlockWalkState.ENTERING and is_blocking() and is_on_floor() and Input.get_axis("move_left", "move_right") != 0.0:
			block_walk_state = BlockWalkState.WALKING
			play_block_walk_animation()
		elif block_walk_state == BlockWalkState.EXITING and is_blocking():
			block_walk_state = BlockWalkState.NONE
			block_walk_uses_transition = false
			play_block_animation()
		elif block_walk_state == BlockWalkState.EXITING_TO_WALK:
			block_walk_state = BlockWalkState.NONE
			block_walk_uses_transition = false
			if Input.get_axis("move_left", "move_right") != 0.0:
				play_movement_animation()
			else:
				play_standing_animation()
		else:
			block_walk_state = BlockWalkState.NONE
			block_walk_uses_transition = false
		return

	if animated_sprite.animation != &"Block" or not is_releasing_block:
		return

	is_releasing_block = false
