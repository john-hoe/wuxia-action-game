# src/combat/player_controller.gd
extends CharacterBody2D

@export var move_speed: float = 400.0
@export var depth_switch_speed: float = 200.0
var current_depth: int = 1  # 0=back, 1=mid, 2=front
var target_depth_y: float
var depth_y_positions: Array[float] = [740.0, 540.0, 340.0]  # bottom to top on screen
var depth_scales: Array[float] = [0.7, 1.0, 1.3]

func _ready() -> void:
    target_depth_y = depth_y_positions[current_depth]
    position.y = target_depth_y

func _physics_process(delta: float) -> void:
    _handle_depth_input()
    _handle_movement(delta)
    _apply_depth_transition(delta)

func _handle_depth_input() -> void:
    if Input.is_action_just_pressed("depth_forward") and current_depth < 2:
        current_depth += 1
        target_depth_y = depth_y_positions[current_depth]
    if Input.is_action_just_pressed("depth_back") and current_depth > 0:
        current_depth -= 1
        target_depth_y = depth_y_positions[current_depth]

func _handle_movement(_delta: float) -> void:
    var input_dir := Input.get_axis("move_left", "move_right")
    velocity.x = input_dir * move_speed
    move_and_slide()

func _apply_depth_transition(delta: float) -> void:
    position.y = move_toward(position.y, target_depth_y, depth_switch_speed * delta)
    var target_scale := Vector2.ONE * depth_scales[current_depth]
    scale = scale.lerp(target_scale, 10.0 * delta)
    var darkness := float(2 - current_depth) * 0.2
    var target_modulate := Color(1, 1, 1).lerp(Color(0.6, 0.6, 0.6), darkness)
    modulate = modulate.lerp(target_modulate, 10.0 * delta)
