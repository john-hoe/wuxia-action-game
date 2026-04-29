# src/ui/ui_manager.gd
# Autoload — bridges combat signals to UI widgets.
# Registered in project.godot as "UIManager".
extends Node

var _hp_bar: Node = null
var _skill_icons: Node = null
var _combo_counter: Node = null
var _debug_label: Label = null
var _widgets_ready: bool = false


func _ready() -> void:
	call_deferred("_connect_signals")


func _connect_signals() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if not player:
		return

	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("combo_updated"):
		player.combo_updated.connect(_on_combo_updated)

	var skill_sys: Node = player.get_node_or_null("SkillSystem")
	if skill_sys and skill_sys.has_signal("skill_cooldown_updated"):
		skill_sys.skill_cooldown_updated.connect(_on_skill_cooldown_updated)

	_find_widgets()
	_widgets_ready = true


func _find_widgets() -> void:
	var root: Node = get_tree().root
	var game: Node = root.get_node_or_null("Game")
	if not game:
		return

	var ui_layer: CanvasLayer = game.get_node_or_null("UILayer")
	if not ui_layer:
		return

	_hp_bar = ui_layer.get_node_or_null("HPBar")
	_skill_icons = ui_layer.get_node_or_null("SkillIcons")
	_combo_counter = ui_layer.get_node_or_null("ComboCounter")
	_debug_label = ui_layer.get_node_or_null("DebugLabel")


func _on_health_changed(current_hp: float, max_hp: float) -> void:
	if _hp_bar and _hp_bar.has_method("set_hp"):
		_hp_bar.set_hp(current_hp, max_hp)
	if _debug_label:
		_debug_label.text = "HP: %d" % int(current_hp)


func _on_combo_updated(current_combo: int, max_combo: int) -> void:
	if _combo_counter and _combo_counter.has_method("set_combo"):
		_combo_counter.set_combo(current_combo, max_combo)
	if _debug_label:
		var combo_text := _debug_label.text
		var hp_part := ""
		if "|" in combo_text:
			hp_part = combo_text.split("|")[0].strip_edges() + "  |  "
		_debug_label.text = "%sCombo: %d/%d" % [hp_part, current_combo, max_combo]


func _on_skill_cooldown_updated(skill_id: String, remaining: float) -> void:
	if _skill_icons and _skill_icons.has_method("update_cooldown"):
		_skill_icons.update_cooldown(skill_id, remaining)
