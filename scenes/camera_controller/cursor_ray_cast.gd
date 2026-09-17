extends RayCast3D

@onready var camera: Camera3D = $"../Camera3D";
const RAY_LENGTH: int = 1000


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return

	var mousepos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mousepos)
	var ray_direction: Vector3 = camera.project_ray_normal(mousepos)
	var ray_end: Vector3 = ray_origin + ray_direction * RAY_LENGTH
	global_position = ray_origin
	target_position = to_local(ray_end)
	force_raycast_update()

	if not is_colliding():
		return

	var cell: HexCell = get_collider().get_parent()
	if event.button_index == MOUSE_BUTTON_LEFT:
		cell.increase_level(1)
	else:
		cell.confirm_level_up()
