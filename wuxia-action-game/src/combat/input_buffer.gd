# src/combat/input_buffer.gd
extends Node
class_name InputBuffer

const BUFFER_TIME: float = 0.1  # ~6 frames at 60fps

var _buffer: Array[Dictionary] = []

func push(action: String) -> void:
	# Remove older entries of same action (only keep latest)
	for i in range(_buffer.size() - 1, -1, -1):
		if _buffer[i].action == action:
			_buffer.remove_at(i)
	_buffer.append({"action": action, "timestamp": Time.get_ticks_msec() / 1000.0})

func consume(action: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	for i in _buffer.size():
		if _buffer[i].action == action and (now - _buffer[i].timestamp) <= BUFFER_TIME:
			_buffer.remove_at(i)
			return true
	return false

func has_buffered(action: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	for entry in _buffer:
		if entry.action == action and (now - entry.timestamp) <= BUFFER_TIME:
			return true
	return false
