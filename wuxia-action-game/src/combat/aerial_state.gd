# src/combat/aerial_state.gd
extends Node
class_name AerialState

signal aerial_started()
signal aerial_ended()
signal aerial_attack(attack_num: int)

const MAX_AERIAL_HITS: int = 2
const MAX_AIR_TIME: float = 1.5
const FALL_SPEED: float = 300.0

var is_airborne: bool = false
var aerial_hit_count: int = 0
var air_time: float = 0.0

func enter_aerial(target: Node2D) -> void:
	is_airborne = true
	aerial_hit_count = 0
	air_time = 0.0
	target.position.y -= 40
	aerial_started.emit()

func _physics_process(delta: float) -> void:
	if not is_airborne:
		return
	air_time += delta
	if air_time >= MAX_AIR_TIME:
		_land()

func try_aerial_attack() -> bool:
	if not is_airborne or aerial_hit_count >= MAX_AERIAL_HITS:
		return false
	aerial_hit_count += 1
	aerial_attack.emit(aerial_hit_count)
	return true

func _land() -> void:
	is_airborne = false
	aerial_hit_count = 0
	air_time = 0.0
	aerial_ended.emit()
