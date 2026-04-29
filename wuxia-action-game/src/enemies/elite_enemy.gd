# src/enemies/elite_enemy.gd
extends BaseEnemy
class_name EliteEnemy

@export var move_speed: float = 100.0
@export var detection_range: float = 700.0
@export var attack_range: float = 80.0
@export var attack_cooldown: float = 2.0
@export var super_armor_max: float = 60.0
@export var patrol_speed: float = 50.0
@export var patrol_distance: float = 200.0

enum State { IDLE, PATROL, CHASE, ATTACK, STUNNED, DEAD }
var current_state: State = State.IDLE
var attack_timer: float = 0.0
var player_ref: Node2D = null
var facing_dir: float = 1.0
var super_armor: float = super_armor_max
var _attack_windup_timer: SceneTreeTimer = null
var _current_attack_type: int = 0  # 0=heavy_slash, 1=sweep, 2=charge
var _patrol_origin: Vector2 = Vector2.ZERO
var _patrol_target: Vector2 = Vector2.ZERO
var _armor_regen_timer: float = 0.0
@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	health = 200.0
	attack_damage = 20.0
	super_armor = super_armor_max
	player_ref = get_tree().get_first_node_in_group("player")
	_patrol_origin = global_position
	_pick_patrol_target()


func _physics_process(delta: float) -> void:
	if health <= 0:
		_die()
		return

	if is_stunned and super_armor <= 0:
		current_state = State.STUNNED
		move_and_slide()
		return

	if super_armor > 0 and is_stunned:
		is_stunned = false

	attack_timer -= delta
	_regenerate_armor(delta)

	if not player_ref:
		_patrol_behavior(delta)
		return

	var dist_to_player := global_position.distance_to(player_ref.global_position)

	match current_state:
		State.IDLE:
			if dist_to_player <= detection_range:
				current_state = State.CHASE
			else:
				current_state = State.PATROL
		State.PATROL:
			_patrol_behavior(delta)
			if dist_to_player <= detection_range:
				current_state = State.CHASE
		State.CHASE:
			_chase_player(dist_to_player)
		State.ATTACK:
			pass
		State.STUNNED:
			if not is_stunned:
				current_state = State.CHASE


func _patrol_behavior(delta: float) -> void:
	var to_target := _patrol_target - global_position
	if to_target.length() < 10.0:
		_pick_patrol_target()
		return
	var dir := to_target.normalized()
	facing_dir = sign(dir.x)
	velocity.x = dir.x * patrol_speed
	move_and_slide()


func _pick_patrol_target() -> void:
	var offset := randf_range(-patrol_distance, patrol_distance)
	_patrol_target = _patrol_origin + Vector2(offset, 0)


func _chase_player(dist: float) -> void:
	var dir := (player_ref.global_position - global_position).normalized()
	facing_dir = sign(dir.x)
	velocity.x = dir.x * move_speed

	if dist <= attack_range and attack_timer <= 0:
		_start_attack()
	elif dist > detection_range * 1.5:
		current_state = State.PATROL
		velocity.x = 0

	move_and_slide()


func _start_attack() -> void:
	current_state = State.ATTACK
	attack_timer = attack_cooldown
	if _attack_windup_timer and _attack_windup_timer.time_left > 0:
		_attack_windup_timer.timeout.disconnect(_execute_attack)
	_current_attack_type = randi() % 3
	var windup: float
	match _current_attack_type:
		0: windup = 0.6  # heavy slash — slow, big damage
		1: windup = 0.5  # sweep — AOE
		2: windup = 0.8  # charge — knockback
	_attack_windup_timer = get_tree().create_timer(windup)
	_attack_windup_timer.timeout.connect(_execute_attack)


func _execute_attack() -> void:
	if current_state != State.ATTACK or not player_ref:
		return
	match _current_attack_type:
		0: _execute_heavy_slash()
		1: _execute_sweep()
		2: _execute_charge()
	current_state = State.CHASE


func _execute_heavy_slash() -> void:
	if global_position.distance_to(player_ref.global_position) <= attack_range * 1.5:
		player_ref.take_damage(25.0, self)


func _execute_sweep() -> void:
	var dist := global_position.distance_to(player_ref.global_position)
	if dist <= attack_range * 2.0:
		player_ref.take_damage(18.0, self)


func _execute_charge() -> void:
	velocity.x = facing_dir * 300.0
	move_and_slide()
	if global_position.distance_to(player_ref.global_position) <= attack_range * 2.5:
		player_ref.take_damage(22.0, self)


func _regenerate_armor(delta: float) -> void:
	if super_armor < super_armor_max and current_state != State.STUNNED:
		_armor_regen_timer += delta
		if _armor_regen_timer >= 3.0:
			super_armor = minf(super_armor + 10.0, super_armor_max)
			_armor_regen_timer = 0.0


func _die() -> void:
	if current_state == State.DEAD:
		return
	current_state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	if anim and anim.has_animation("death"):
		anim.play("death")
	await get_tree().create_timer(0.6).timeout
	queue_free()


func apply_hit(stun_duration: float, knockback_force: float, damage: float, attacker_pos: Vector2, extra_impulse: Vector2 = Vector2.ZERO, reaction: HitReaction = HitReaction.LIGHT_STUN, combo_count: int = 1) -> void:
	if super_armor > 0:
		var armor_damage := damage * 0.8
		super_armor -= armor_damage
		damage *= 0.2
		if super_armor > 0:
			stun_duration *= 0.2
			knockback_force *= 0.2
		else:
			super_armor = 0
	super.apply_hit(stun_duration, knockback_force, damage, attacker_pos, extra_impulse, reaction, combo_count)
