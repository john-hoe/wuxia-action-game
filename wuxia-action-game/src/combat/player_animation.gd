# src/combat/player_animation.gd
# Pure visual layer — does NOT drive combat timing.
# Timer system (combo_engine + SceneTreeTimers) remains the sole truth source.
extends Node

@onready var _anim_player: AnimationPlayer = $"../AnimationPlayer"
@onready var _anim_tree: AnimationTree = $"../AnimationTree"


func play_idle() -> void:
	if _anim_player and _anim_player.has_animation("idle"):
		_anim_player.play("idle")


func play_walk() -> void:
	if _anim_player and _anim_player.has_animation("walk"):
		_anim_player.play("walk")


func play_attack(segment: int) -> void:
	var name := "attack_%d" % segment
	if _anim_player and _anim_player.has_animation(name):
		_anim_player.play(name)


func play_dash() -> void:
	if _anim_player and _anim_player.has_animation("dash"):
		_anim_player.play("dash")


func play_dodge() -> void:
	if _anim_player and _anim_player.has_animation("dodge"):
		_anim_player.play("dodge")


func play_parry() -> void:
	if _anim_player and _anim_player.has_animation("parry"):
		_anim_player.play("parry")


func play_skill(skill_id: String) -> void:
	if _anim_player and _anim_player.has_animation(skill_id):
		_anim_player.play(skill_id)


func play_hurt() -> void:
	if _anim_player and _anim_player.has_animation("hurt"):
		_anim_player.play("hurt")
