extends Node3D

@export var brown_material: Material = preload("res://shaders/brown_material.tres")
@export var green_material: Material = preload("res://shaders/green_material.tres")


func _ready() -> void:
    var mesh: MeshInstance3D = $LowPolyTreeV1
    mesh.set_surface_override_material(0, brown_material)
    mesh.set_surface_override_material(1, green_material)
