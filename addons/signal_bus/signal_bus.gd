extends Node

var _free_locks: Array[int] = []
var _locks: Array[int] = []
var _buffer: Array[Dictionary] = []


func send(signal_name: StringName, args: Array):
	if _locks.size() > 0:
		_buffer.append({signal_name = signal_name, args = args})
	else:
		_broadcast(signal_name, args)


func is_locked() -> bool:
	return not _locks.is_empty()


func lock() -> int:
	var lock_id := -1
	if _free_locks.is_empty():
		lock_id = _locks.size() + 1
	else:
		lock_id = _free_locks.pop_front()
	_locks.append(lock_id)
	return lock_id


func unlock(lock_id: int):
	if lock_id in _locks:
		_locks.erase(lock_id)
		_free_locks.append(lock_id)
	while not _buffer.is_empty() and _locks.is_empty():
		var signal_call: Dictionary = _buffer.pop_front()
		_broadcast(signal_call.signal_name, signal_call.args)


func _broadcast(signal_name: StringName, args: Array):
	for receiver in SignalBusReceiver.all(get_tree()):
		receiver.callv(&'emit_signal', [signal_name] + args)
