class_name SignalBusSender
extends Node

@export var signal_prefix := ""

func _ready() -> void:
	for conn_info in get_incoming_connections():
		var sig: Signal = conn_info.signal
		var clb: Callable = conn_info.callable
		var sig_name: StringName = signal_prefix
		
		if clb.get_method() == connect_signal_named.get_method():
			sig_name += clb.get_bound_arguments()[0]
			clb.unbind(1)
		else:
			sig_name += sig.get_name()
		
		sig.connect(func(...args):
			SignalBus.send(sig_name, args)
		)

func connect_signal(..._args):
	return

## Bind a custom signal name when connecting the signal
func connect_signal_named(..._args):
	return
