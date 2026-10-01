extends Node3D

@onready var world_cells: WorldCells = $WorldCells
@onready var fps_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/FPSLabel
@onready var life_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/LifeLabel
@onready var water_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/WaterLabel
@onready var science_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/ScienceLabel
@onready var tree_count_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/TreeCountLabel
@onready var regenerate_button: Button = $UserInterface/Panel/MarginContainer/VBoxContainer/RegenerateButton
@onready var science_button: Button = $UserInterface/Panel/MarginContainer/VBoxContainer/ScienceButton
@onready var width_slider: HSlider = $UserInterface/Panel/MarginContainer/VBoxContainer/WidthSlider
@onready var height_slider: HSlider = $UserInterface/Panel/MarginContainer/VBoxContainer/HeightSlider
@onready var width_value_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/WidthValueLabel
@onready var height_value_label: Label = $UserInterface/Panel/MarginContainer/VBoxContainer/HeightValueLabel

func _ready() -> void:
	regenerate_button.pressed.connect(_on_regenerate_pressed)
	science_button.pressed.connect(_on_science_button_pressed)
	width_slider.value_changed.connect(_on_slider_changed)
	height_slider.value_changed.connect(_on_slider_changed)
	_update_slider_labels()


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	life_label.text = "Vida: %d" % world_cells.life
	water_label.text = "Água: %d" % world_cells.water
	science_label.text = "Ciência: %d" % world_cells.science
	tree_count_label.text = "Trees: %d" % world_cells.generated_tree_count


func _on_regenerate_pressed() -> void:
	world_cells.width = int(width_slider.value)
	world_cells.height = int(height_slider.value)
	world_cells.generate_world()


func _on_science_button_pressed() -> void:
	world_cells.add_science(1)


func _on_slider_changed(_value: float) -> void:
	_update_slider_labels()


func _update_slider_labels() -> void:
	width_value_label.text = "Width: %d" % int(width_slider.value)
	height_value_label.text = "Height: %d" % int(height_slider.value)
