# src/combat/combo_data.gd
extends Node
class_name ComboData

# Derivation table structure:
# DERIVATIONS[segment: int][skill_id: String] = {
#   "animation": String,          # AnimationTree trigger name
#   "damage_mult": float,         # Damage multiplier
#   "effect": String,             # "launch", "armor_break", "pull", "buff", "none"
#   "description": String,        # Human-readable name for UI
#   "unlock_condition": String,   # "default", "manual_xxx", "proficiency_pojun_25"
# }
const DERIVATIONS: Dictionary = {
    1: {
        "pojun": {
            "animation": "deriv_1_pojun",
            "damage_mult": 1.0,
            "effect": "gap_close",
            "description": "破军突进",
            "unlock_condition": "default",
        },
        "huifeng": {
            "animation": "deriv_1_huifeng",
            "damage_mult": 1.2,
            "effect": "knockback",
            "description": "回锋清场",
            "unlock_condition": "default",
        },
        "ningshen": {
            "animation": "deriv_1_ningshen",
            "damage_mult": 0.8,
            "effect": "extended_parry",
            "description": "凝神预判",
            "unlock_condition": "default",
        },
    },
    2: {
        "pojun": {
            "animation": "deriv_2_pojun",
            "damage_mult": 1.3,
            "effect": "launch",
            "description": "浮空破军",
            "unlock_condition": "default",
        },
        "huifeng": {
            "animation": "deriv_2_huifeng",
            "damage_mult": 1.0,
            "effect": "pull_strong",
            "description": "回锋聚敌",
            "unlock_condition": "default",
        },
        "ningshen": {
            "animation": "deriv_2_ningshen",
            "damage_mult": 1.0,
            "effect": "advance_combo",
            "description": "凝神转攻",
            "unlock_condition": "default",
        },
    },
    3: {
        "pojun": {
            "animation": "deriv_3_pojun",
            "damage_mult": 1.2,
            "effect": "armor_break",
            "description": "破军破甲",
            "unlock_condition": "proficiency_pojun_25",
        },
        "huifeng": {
            "animation": "deriv_3_huifeng",
            "damage_mult": 1.5,
            "effect": "tornado",
            "description": "回锋旋风",
            "unlock_condition": "default",
        },
        "ningshen": {
            "animation": "deriv_3_ningshen",
            "damage_mult": 1.0,
            "effect": "buff_extend",
            "description": "凝神专注",
            "unlock_condition": "proficiency_ningshen_50",
        },
    },
    4: {
        "pojun": {
            "animation": "deriv_4_pojun",
            "damage_mult": 1.8,
            "effect": "pierce",
            "description": "破军穿透",
            "unlock_condition": "default",
        },
        "huifeng": {
            "animation": "deriv_4_huifeng",
            "damage_mult": 1.6,
            "effect": "finisher",
            "description": "回锋终结",
            "unlock_condition": "default",
        },
        "ningshen": {
            "animation": "deriv_4_ningshen",
            "damage_mult": 2.0,
            "effect": "perfect_counter",
            "description": "凝神完美",
            "unlock_condition": "default",
        },
    },
}

const MANUAL_DERIVATIONS: Dictionary = {
    "manual_dragon_fist": {
        "name": "龙拳",
        "description": "普攻第4段后接破军触发龙拳派生",
        "segment": 4,
        "skill": "pojun",
        "animation": "deriv_manual_dragon_fist",
        "damage_mult": 2.5,
        "effect": "shockwave",
        "pages_required": 4,
    },
    "manual_shadow_step": {
        "name": "影步",
        "description": "闪避后0.3s内按普攻瞬移至最近敌人身后",
        "segment": 0,
        "skill": "pojun",
        "animation": "deriv_manual_shadow_step",
        "damage_mult": 1.0,
        "effect": "teleport_backstab",
        "pages_required": 3,
    },
}
