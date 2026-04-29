# src/combat/skill_system.gd
extends Node

class_name SkillSystem

const SKILL_POJUN = "pojun"
const SKILL_HUIFENG = "huifeng"
const SKILL_NINGSHEN = "ningshen"

var cooldowns: Dictionary = {
    SKILL_POJUN: {"current": 0.0, "max": 3.0, "ready": true},
    SKILL_HUIFENG: {"current": 0.0, "max": 5.0, "ready": true},
    SKILL_NINGSHEN: {"current": 0.0, "max": 6.0, "ready": true},
}

signal skill_cast(skill_id: String, is_derivation: bool)
signal skill_cooldown_updated(skill_id: String, remaining: float)

func _process(delta: float) -> void:
    for skill_id in cooldowns:
        if not cooldowns[skill_id].ready:
            cooldowns[skill_id].current -= delta
            skill_cooldown_updated.emit(skill_id, cooldowns[skill_id].current)
            if cooldowns[skill_id].current <= 0.0:
                cooldowns[skill_id].ready = true
                cooldowns[skill_id].current = 0.0

func try_cast(skill_id: String) -> bool:
    if not cooldowns[skill_id].ready:
        return false
    cooldowns[skill_id].ready = false
    cooldowns[skill_id].current = cooldowns[skill_id].max
    skill_cast.emit(skill_id, false)
    return true

func is_ready(skill_id: String) -> bool:
    return cooldowns[skill_id].ready
