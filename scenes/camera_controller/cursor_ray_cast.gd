extends RayCast3D

@onready var camera: Camera3D = $"../Camera3D";
const RAY_LENGTH: int = 1000


func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("left_mouse"):
		var mousepos: Vector2 = get_viewport().get_mouse_position()
		
		global_position = camera.project_ray_origin(mousepos)
		target_position = global_position + camera.project_ray_normal(mousepos) *RAY_LENGTH
		force_raycast_update()
		
		if is_colliding():
			var cell: HexCell = get_collider().get_parent()
			cell.increase_level(1)
