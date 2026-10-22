extends PanelContainer

@onready var world_cells: WorldCells = get_node("../../WorldCells") as WorldCells
@onready var width_slider: HSlider = $MarginContainer/VBoxContainer/WidthSlider
@onready var height_slider: HSlider = $MarginContainer/VBoxContainer/HeightSlider
@onready var width_value_label: Label = $MarginContainer/VBoxContainer/WidthValueLabel
@onready var height_value_label: Label = $MarginContainer/VBoxContainer/HeightValueLabel
@onready var regenerate_button: Button = $MarginContainer/VBoxContainer/RegenerateButton
@onready var science_button: Button = $MarginContainer/VBoxContainer/ScienceButton


func _ready() -> void:
	width_slider.value = world_cells.width
	height_slider.value = world_cells.height
	width_slider.value_changed.connect(_on_slider_changed)
	height_slider.value_changed.connect(_on_slider_changed)
	regenerate_button.pressed.connect(_on_regenerate_pressed)
	science_button.pressed.connect(_on_science_button_pressed)
	_update_slider_labels()


func _on_slider_changed(_value: float) -> void:
	_update_slider_labels()


func _on_regenerate_pressed() -> void:
	world_cells.width = int(width_slider.value)
	world_cells.height = int(height_slider.value)
	world_cells.generate_world()


func _on_science_button_pressed() -> void:
	world_cells.add_science(1)


func _update_slider_labels() -> void:
	width_value_label.text = "Width: %d" % int(width_slider.value)
	height_value_label.text = "Height: %d" % int(height_slider.value)
