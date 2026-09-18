class_name Particle
extends Node3D


func spawn(particle_text: String) -> void:
	$SubViewport/Control/Label.text = particle_text
	
	$GPUParticles3D.restart() # emit a single particle
	
	await get_tree().create_timer($GPUParticles3D.lifetime).timeout
	queue_free()
