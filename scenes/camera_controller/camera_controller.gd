extends Node3D

@export_category("Movimento da Câmera (Edge Pan)")
@export var pan_speed: float = 20.0
@export var edge_margin: float = 20.0

@export_category("Movimento de Arrasto (Drag Pan)")
@export var enable_drag: bool = true
@export var drag_sensitivity: float = 0.05
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE

@export_category("Limites do Mapa")
@export var enable_limits: bool = true
@export var limit_left: float = -50.0
@export var limit_right: float = 50.0
@export var limit_top: float = -50.0
@export var limit_bottom: float = 50.0

@export_category("Zoom")
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 30.0

@onready var camera_target: Marker3D = $CameraTarget
@onready var pcam: PhantomCamera3D = $PhantomCamera3D

var _is_dragging: bool = false

func _ready() -> void:
    # Prende o mouse dentro da janela do jogo
    Input.mouse_mode = Input.MOUSE_MODE_CONFINED
    _apply_zoom(min_zoom)

func _process(delta: float) -> void:
    if not _is_dragging:
        _handle_edge_movement(delta)

func _handle_edge_movement(delta: float) -> void:
    var viewport := get_viewport()
    var mouse_pos := viewport.get_mouse_position()
    var screen_size := viewport.get_visible_rect().size
    
    var input_dir := Vector2.ZERO

    if Rect2(Vector2.ZERO, screen_size).has_point(mouse_pos):
        if mouse_pos.x <= edge_margin:
            input_dir.x -= 1
        elif mouse_pos.x >= screen_size.x - edge_margin:
            input_dir.x += 1
            
        if mouse_pos.y <= edge_margin:
            input_dir.y -= 1
        elif mouse_pos.y >= screen_size.y - edge_margin:
            input_dir.y += 1

    if input_dir == Vector2.ZERO:
        return

    input_dir = input_dir.normalized()

    var move_dir := _get_camera_direction(input_dir)
    var new_position: Vector3 = camera_target.global_position + (move_dir * pan_speed * delta)
    
    camera_target.global_position = _apply_limits(new_position)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _is_dragging = false
        
    if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
        if Input.mouse_mode != Input.MOUSE_MODE_CONFINED:
            Input.mouse_mode = Input.MOUSE_MODE_CONFINED

    if enable_drag and event is InputEventMouseButton and event.button_index == drag_button:
        _is_dragging = event.is_pressed()
        
    if enable_drag and _is_dragging and event is InputEventMouseMotion:
        var drag_input := Vector2(event.relative.x, event.relative.y)
        
        var move_dir := _get_camera_direction(drag_input)

        var new_position: Vector3 = camera_target.global_position + (-move_dir * drag_sensitivity)
        
        camera_target.global_position = _apply_limits(new_position)

    if event is InputEventMouseButton and event.is_pressed():
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _apply_zoom(-zoom_speed)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _apply_zoom(zoom_speed)


func _get_camera_direction(input_dir: Vector2) -> Vector3:
    var cam_basis := pcam.global_transform.basis
    
    var forward := -cam_basis.z
    forward.y = 0
    forward = forward.normalized()
    
    var right := cam_basis.x
    right.y = 0
    right = right.normalized()

    return (right * input_dir.x + forward * -input_dir.y)

func _apply_limits(pos: Vector3) -> Vector3:
    if enable_limits:
        pos.x = clamp(pos.x, limit_left, limit_right)
        pos.z = clamp(pos.z, limit_top, limit_bottom)
    return pos
    
func _apply_zoom(amount: float) -> void:
    var current_length: float = pcam.spring_length
    pcam.spring_length = clamp(current_length + amount, min_zoom, max_zoom)