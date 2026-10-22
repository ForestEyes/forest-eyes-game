extends Node3D

@onready var world_cells: WorldCells = $WorldCells
@onready var fps_label: Label = $UserInterface/FPSLabel
@onready var life_label: Label = $UserInterface/ResourcesBar/MarginContainer/HBoxContainer/LifeLabel
@onready var water_label: Label = $UserInterface/ResourcesBar/MarginContainer/HBoxContainer/WaterLabel
@onready var tree_count_label: Label = $UserInterface/ResourcesBar/MarginContainer/HBoxContainer/TreeCountLabel
@onready var science_label: Label = $UserInterface/ResourcesBar/MarginContainer/HBoxContainer/ScienceLabel
@onready var pause_button: Button = $UserInterface/PauseButton
@onready var pause_menu: PauseMenu = $UserInterface/PauseMenu
@onready var threat_treatment_panel: ThreatTreatmentPanel = $UserInterface/ThreatTreatmentPanel

func _ready() -> void:
	pause_button.pressed.connect(pause_menu.open_pause_menu)
	world_cells.threat_treatment_requested.connect(_on_threat_treatment_requested)
	world_cells.level_up_confirmation_requested.connect(_on_level_up_confirmation_requested)
	threat_treatment_panel.cure_requested.connect(_on_cure_requested)
	threat_treatment_panel.level_up_confirmed.connect(_on_level_up_confirmed)
	threat_treatment_panel.interaction_lock_changed.connect(world_cells.set_map_interaction_locked)


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	life_label.text = "Vida: %d" % world_cells.life
	water_label.text = "Água: %d" % world_cells.water
	tree_count_label.text = "Árvores: %d" % world_cells.generated_tree_count
	science_label.text = "Ciência: %d" % world_cells.science


func _on_threat_treatment_requested(cell: HexCell) -> void:
	threat_treatment_panel.open_for_treatment(cell, world_cells.life, world_cells.water)


func _on_level_up_confirmation_requested(cell: HexCell) -> void:
	threat_treatment_panel.open_for_level_up(cell, world_cells.life, world_cells.water)


func _on_cure_requested(cell: HexCell, life_amount: int, water_amount: int) -> void:
	var result := world_cells.attempt_threat_cure_all(cell, life_amount, water_amount)
	threat_treatment_panel.handle_cure_result(result, world_cells.life, world_cells.water)


func _on_level_up_confirmed(cell: HexCell) -> void:
	cell.confirm_level_up()
	if cell.level_up_pending:
		threat_treatment_panel.handle_level_up_result(cell, world_cells.life, world_cells.water)
	else:
		threat_treatment_panel.close_panel()
