extends Node3D

@export var particle_text: String = "TEXT"

func _ready() -> void:
	$GPUParticles3D.restart()
	$SubViewport/Control/Label.text = particle_text
