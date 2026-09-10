extends Node3D

@onready var world_cells: WorldCells = $WorldCells
@onready var fps_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/FPSLabel
@onready var tree_count_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/TreeCountLabel
@onready var regenerate_button: Button = $UserInterface/Panel/MarginContainer/VBoxContainer/RegenerateButton
@onready var level_slider: HSlider = $UserInterface/Panel/MarginContainer/VBoxContainer/LevelSlider
@onready var width_slider: HSlider = $UserInterface/Panel/MarginContainer/VBoxContainer/WidthSlider
@onready var height_slider: HSlider = $UserInterface/Panel/MarginContainer/VBoxContainer/HeightSlider
@onready var level_value_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/LevelValueLabel
@onready var width_value_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/WidthValueLabel
@onready var height_value_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/HeightValueLabel

func _ready() -> void:
	regenerate_button.pressed.connect(_on_regenerate_pressed)
	level_slider.value_changed.connect(_on_slider_changed)
	width_slider.value_changed.connect(_on_slider_changed)
	height_slider.value_changed.connect(_on_slider_changed)
	_update_slider_labels()


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	tree_count_label.text = "Trees: %d" % world_cells.generated_tree_count


func _on_regenerate_pressed() -> void:
	world_cells.cell_level = int(level_slider.value)
	world_cells.width = int(width_slider.value)
	world_cells.height = int(height_slider.value)
	world_cells.generate_world()


func _on_slider_changed(_value: float) -> void:
	_update_slider_labels()


func _update_slider_labels() -> void:
	level_value_label.text = "Cell level: %d" % int(level_slider.value)
	width_value_label.text = "Width: %d" % int(width_slider.value)
	height_value_label.text = "Height: %d" % int(height_slider.value)
