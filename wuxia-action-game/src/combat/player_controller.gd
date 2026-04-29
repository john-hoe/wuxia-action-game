# src/combat/player_controller.gd
extends CharacterBody2D

@export var move_speed: float = 400.0
var current_depth: int = 1  # 0=back, 1=mid, 2=front (will be used in P1.03)

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * move_speed
	move_and_slide()

func _ready() -> void:
	pass  # Depth system comes in P1.03
