extends Node3D

@onready var text_particle: PackedScene = preload("res://scenes/effects/particles/text_particle.tscn")


func _on_signal_bus_receiver_cell_increased_level(spawn_position: Vector3) -> void:
	var particle: Particle = text_particle.instantiate()
	add_child(particle)
	particle.global_position = spawn_position
	
	particle.spawn("+life")
