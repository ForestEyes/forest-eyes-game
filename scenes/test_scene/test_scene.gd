extends Node3D

@onready var world_cells: WorldCells = $WorldCells
@onready var fps_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/FPSLabel
@onready var regenerate_button: Button = $UserInterface/Panel/MarginContainer/VBoxContainer/RegenerateButton

func _ready() -> void:
	regenerate_button.pressed.connect(_on_regenerate_pressed)


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _on_regenerate_pressed() -> void:
	world_cells.generate_world()
