class_name ThreatTreatmentPanel
extends Control

signal cure_requested(cell: HexCell, life_amount: int, water_amount: int)
signal level_up_confirmed(cell: HexCell)
signal interaction_lock_changed(is_locked: bool)

enum Mode { TREATMENT, LEVEL_UP }

const PANEL_SIZE: Vector2 = Vector2(420.0, 320.0)
const WORLD_HEIGHT_OFFSET: float = 3.0

@onready var title_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var level_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/LevelLabel
@onready var threat_summary_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/ThreatSummaryLabel
@onready var available_resources_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/AvailableResourcesLabel
@onready var life_row: Control = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/LifeRow
@onready var life_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/LifeRow/LifeLabel
@onready var life_selector: SpinBox = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/LifeRow/LifeSelector
@onready var water_row: Control = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/WaterRow
@onready var water_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/WaterRow/WaterLabel
@onready var water_selector: SpinBox = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/WaterRow/WaterSelector
@onready var chance_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/ChanceLabel
@onready var level_up_cost_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/LevelUpCostLabel
@onready var status_label: Label = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/StatusLabel
@onready var cure_button: Button = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/ButtonRow/CureButton
@onready var level_up_button: Button = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/ButtonRow/LevelUpButton
@onready var cancel_button: Button = $SubViewportContainer/SubViewport/Panel/MarginContainer/VBoxContainer/ButtonRow/CancelButton

var _target_cell: HexCell
var _mode: Mode = Mode.TREATMENT
var _available_threats: Array[StringName] = []
var _available_life: int = 0
var _available_water: int = 0
var _displayed_level: int = -1


func _ready() -> void:
	size = PANEL_SIZE
	visible = false
	life_selector.value_changed.connect(_update_cure_preview)
	water_selector.value_changed.connect(_update_cure_preview)
	cure_button.pressed.connect(_on_cure_pressed)
	level_up_button.pressed.connect(_on_level_up_pressed)
	cancel_button.pressed.connect(close_panel)
	_update_mode_visibility()


func open_for_treatment(cell: HexCell, available_life: int, available_water: int) -> void:
	if not is_instance_valid(cell):
		push_warning("ThreatTreatmentPanel received an invalid cell.")
		return
	var active_threats := _get_active_threats(cell)
	if active_threats.is_empty():
		push_warning("ThreatTreatmentPanel received a cell without an active threat.")
		return

	_target_cell = cell
	_mode = Mode.TREATMENT
	_displayed_level = cell.current_level
	_available_threats = active_threats
	life_selector.value = 0.0
	water_selector.value = 0.0
	title_label.text = "Curar tile"
	level_label.text = "Nível do tile: %d" % cell.current_level
	_update_threat_summary()
	status_label.text = ""
	_update_resource_availability(available_life, available_water)
	var default_allocation := ThreatManager.get_default_cure_allocation(
		_available_threats,
		cell.current_level,
		_available_life,
		_available_water
	)
	life_selector.value = default_allocation.x
	water_selector.value = default_allocation.y
	_update_mode_visibility()
	_show_panel()
	_update_cure_preview()


func open_for_level_up(cell: HexCell, available_life: int, available_water: int) -> void:
	if not is_instance_valid(cell) or not cell.level_up_pending:
		push_warning("ThreatTreatmentPanel received a cell without a pending level-up.")
		return

	_target_cell = cell
	_mode = Mode.LEVEL_UP
	_displayed_level = cell.current_level
	title_label.text = "Promover tile"
	level_label.text = "Nível %d → %d" % [cell.current_level, cell.current_level + 1]
	level_up_cost_label.text = "Custo fixo: %d Vida" % HexCell.LEVEL_UP_LIFE_COST
	status_label.text = ""
	_update_resource_availability(available_life, available_water)
	_update_mode_visibility()
	_show_panel()


func handle_cure_result(result: ThreatManager.CureResult, available_life: int, available_water: int) -> void:
	_update_resource_availability(available_life, available_water)
	match result:
		ThreatManager.CureResult.RESOLVED:
			close_panel()
		ThreatManager.CureResult.FAILED:
			status_label.text = "Não foi curado. Os recursos foram consumidos; ajuste e tente novamente."
			_update_cure_preview()
		ThreatManager.CureResult.INSUFFICIENT_RESOURCES:
			status_label.text = "Recursos insuficientes para essa tentativa."
			_update_cure_preview()
		_:
			status_label.text = "Essas ameaças não estão mais ativas."
			close_panel()


func handle_level_up_result(cell: HexCell, available_life: int, available_water: int) -> void:
	if not is_instance_valid(cell) or not cell.level_up_pending:
		close_panel()
		return

	_target_cell = cell
	_update_resource_availability(available_life, available_water)
	status_label.text = "São necessários %d de vida." % HexCell.LEVEL_UP_LIFE_COST
	level_up_button.disabled = available_life < HexCell.LEVEL_UP_LIFE_COST


func close_panel() -> void:
	if not visible:
		return

	visible = false
	_target_cell = null
	interaction_lock_changed.emit(false)


func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_target_cell):
		close_panel()
		return
	if _mode == Mode.TREATMENT and _target_cell.current_level != _displayed_level:
		_displayed_level = _target_cell.current_level
		level_label.text = "Nível do tile: %d" % _displayed_level
		_update_cure_preview()
	if _mode == Mode.TREATMENT:
		var active_threats := _get_active_threats(_target_cell)
		if active_threats.is_empty():
			close_panel()
			return
		if active_threats != _available_threats:
			_available_threats = active_threats
			_update_threat_summary()
			_update_cure_preview()

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var world_position: Vector3 = _target_cell.global_position + Vector3.UP * WORLD_HEIGHT_OFFSET
	var screen_position: Vector2 = camera.unproject_position(world_position)
	if camera.is_position_behind(world_position):
		screen_position = Vector2(get_viewport_rect().size.x * 0.5, 24.0)

	var viewport_size: Vector2 = get_viewport_rect().size
	position = Vector2(
		clampf(screen_position.x - size.x * 0.5, 0.0, maxf(0.0, viewport_size.x - size.x)),
		clampf(screen_position.y - size.y, 0.0, maxf(0.0, viewport_size.y - size.y))
	)


func _on_cure_pressed() -> void:
	if not is_instance_valid(_target_cell) or _available_threats.is_empty():
		return

	cure_requested.emit(
		_target_cell,
		roundi(life_selector.value),
		roundi(water_selector.value)
	)


func _on_level_up_pressed() -> void:
	if is_instance_valid(_target_cell):
		level_up_confirmed.emit(_target_cell)


func _update_cure_preview(_value: float = 0.0) -> void:
	if _mode != Mode.TREATMENT or not is_instance_valid(_target_cell) or _available_threats.is_empty():
		return

	var life_amount := roundi(life_selector.value)
	var water_amount := roundi(water_selector.value)
	var chance: float = ThreatManager.calculate_combined_cure_chance(
		_available_threats,
		_target_cell.current_level,
		life_amount,
		water_amount
	)
	chance_label.text = "Chance de cura: %d%%" % roundi(chance * 100.0)
	cure_button.disabled = life_amount + water_amount == 0


func _update_resource_availability(available_life: int, available_water: int) -> void:
	_available_life = maxi(0, available_life)
	_available_water = maxi(0, available_water)
	life_selector.max_value = _available_life
	water_selector.max_value = _available_water
	life_label.text = "Vida (%d)" % _available_life
	water_label.text = "Água (%d)" % _available_water
	available_resources_label.text = "Vida disponível: %d" % _available_life
	level_up_button.disabled = _available_life < HexCell.LEVEL_UP_LIFE_COST


func _update_mode_visibility() -> void:
	var is_treatment: bool = _mode == Mode.TREATMENT
	threat_summary_label.visible = is_treatment
	available_resources_label.visible = not is_treatment
	life_row.visible = is_treatment
	water_row.visible = is_treatment
	chance_label.visible = is_treatment
	cure_button.visible = is_treatment
	level_up_cost_label.visible = not is_treatment
	level_up_button.visible = not is_treatment
	level_up_button.disabled = _available_life < HexCell.LEVEL_UP_LIFE_COST


func _show_panel() -> void:
	visible = true
	interaction_lock_changed.emit(true)


func _get_threat_display_name(threat: StringName) -> String:
	match threat:
		HexCell.THREAT_FIRE:
			return "Queimada"
		HexCell.THREAT_DEFORESTATION:
			return "Desmatamento"
		HexCell.THREAT_CONTAMINATION:
			return "Contaminação"
	return "Ameaça"


func _get_active_threats(cell: HexCell) -> Array[StringName]:
	var threats: Array[StringName] = []
	for threat: StringName in HexCell.THREAT_TYPES:
		if cell.active_threats.has(threat):
			threats.append(threat)
	return threats


func _update_threat_summary() -> void:
	var threat_names := PackedStringArray()
	for threat: StringName in _available_threats:
		threat_names.append(_get_threat_display_name(threat))
	var joined_names := " + ".join(threat_names)
	threat_summary_label.text = "Ameaças: %s" % joined_names
