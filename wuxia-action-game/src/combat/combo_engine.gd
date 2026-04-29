# src/combat/combo_engine.gd
extends Node

signal combo_advanced(segment: int)
signal combo_ended(final_segment: int)
signal combo_window_opened(segment: int)
signal combo_window_closed(segment: int)
signal derivation_triggered(base_segment: int, skill_id: String)

const MAX_COMBO: int = 12
const CANCEL_WINDOW_FRAMES: int = 8

var current_segment: int = 0
var total_hits: int = 0
var derivation_table: Dictionary = {}
var is_in_window: bool = false
var combo_queued: bool = false
var aerial_state: AerialState = null
var _window_timer: SceneTreeTimer = null
var _anim_timer: SceneTreeTimer = null

func try_attack() -> bool:
	if aerial_state and aerial_state.is_airborne:
		return aerial_state.try_aerial_attack()
	if total_hits >= MAX_COMBO:
		_force_recovery()
		return false

	if current_segment == 0:
		_start_combo()
		return true

	# Buffer input unconditionally while combo is active — the window timer
	# will consume it when it fires. This fixes mashing J to chain combos.
	combo_queued = true
	return true

func _start_combo() -> void:
	current_segment = 1
	if total_hits == 0:
		total_hits = 1
	combo_advanced.emit(1)
	_schedule_window()

func _advance_segment() -> void:
	if current_segment >= 4:
		_force_recovery()
		return
	current_segment += 1
	total_hits += 1
	combo_advanced.emit(current_segment)
	_schedule_window()

func _schedule_window() -> void:
	var segment_duration: float = 0.4  # ~400ms per attack segment
	var window_start := segment_duration - (CANCEL_WINDOW_FRAMES / 60.0)
	_cancel_timers()
	_window_timer = get_tree().create_timer(window_start)
	_window_timer.timeout.connect(_open_window)
	_anim_timer = get_tree().create_timer(segment_duration)
	_anim_timer.timeout.connect(_on_anim_finished)

func _cancel_timers() -> void:
	if _window_timer and _window_timer.time_left > 0:
		_window_timer.timeout.disconnect(_open_window)
	_window_timer = null
	if _anim_timer and _anim_timer.time_left > 0:
		_anim_timer.timeout.disconnect(_on_anim_finished)
	_anim_timer = null

func _open_window() -> void:
	if combo_queued:
		combo_queued = false
		_advance_segment()
		return
	is_in_window = true
	combo_window_opened.emit(current_segment)

func _on_anim_finished() -> void:
	if combo_queued:
		combo_queued = false
		is_in_window = false
		combo_window_closed.emit(current_segment)
		_advance_segment()
		return
	if is_in_window:
		is_in_window = false
		combo_window_closed.emit(current_segment)
		_force_recovery()

func _force_recovery() -> void:
	var finished_segment := current_segment
	_cancel_timers()
	current_segment = 0
	total_hits = 0
	is_in_window = false
	combo_queued = false
	combo_ended.emit(finished_segment)

func try_skill_derivation(skill_id: String) -> bool:
	if not is_in_window or current_segment == 0:
		return false
	var seg_table: Dictionary = derivation_table.get(current_segment, {})
	if not seg_table.has(skill_id):
		return false
	_trigger_derivation(current_segment, skill_id, seg_table[skill_id])
	return true

func _trigger_derivation(segment: int, skill_id: String, _data) -> void:
	is_in_window = false
	total_hits += 1
	_cancel_timers()
	derivation_triggered.emit(segment, skill_id)
	if _data.get("effect", "") == "launch" and aerial_state:
		aerial_state.enter_aerial(_get_player_node())
	current_segment = 0
	combo_queued = false
	if total_hits >= MAX_COMBO:
		var recovery_timer := get_tree().create_timer(0.6)
		recovery_timer.timeout.connect(_force_recovery)

func register_hit() -> void:
	total_hits += 1

func load_derivation_table(table: Dictionary) -> void:
	derivation_table = table

func _get_player_node() -> Node2D:
	return get_parent() as Node2D
