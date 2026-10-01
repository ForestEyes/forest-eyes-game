class_name HexCell
extends Node3D

@export_enum("forest", "water", "river") var cell_type: String = "water"

@export var tree_meshes: Array[PackedScene]

@export var current_level: int = 5
@export var trees_per_level: float = 4.0
@export var max_trees_per_cell: int = 200
@export var tree_visibility_distance: float = 60.0

@export var packed_hex_scene: PackedScene

const MAX_LEVEL: int = 15
const LIFE_PER_CLICK: int = 1
const LEVEL_UP_LIFE_COST: int = 50
const CLICKS_PER_LEVEL_MULTIPLIER: int = 5
const LEVEL_PROGRESS_TWEEN_DURATION: float = 0.2
const LEVEL_PROGRESS_VISIBLE_DURATION: float = 1.0

const LEVEL_PROGRESS_COLOR: Color = Color(0.0, 1.0, 0.0)
const THREAT_PROGRESS_COLOR: Color = Color(0.85, 0.1, 0.1)
const THREAT_CLEAR_CLICKS: int = 3

const THREAT_FIRE: StringName = &"fire"
const THREAT_DEFORESTATION: StringName = &"deforestation"
const THREAT_CONTAMINATION: StringName = &"contamination"
const THREAT_TYPES: Array[StringName] = [THREAT_FIRE, THREAT_DEFORESTATION, THREAT_CONTAMINATION]
const THREAT_COLORS: Dictionary[StringName, Color] = {
	THREAT_FIRE: Color(0.8, 0.1, 0.1),
	THREAT_DEFORESTATION: Color(0.9, 0.85, 0.1),
	THREAT_CONTAMINATION: Color(0.5, 0.1, 0.55),
}

var world_cells: WorldCells
var level_progress: ProgressBar
var level_progress_viewport: SubViewport
@onready var level_progress_sprite: Sprite3D = $LevelProgressSprite
@onready var threat_shader: Node3D = get_node_or_null("ThreatShader") as Node3D
var level_progress_value: float = 0.0
var level_progress_tween: Tween
var level_up_pending: bool = false

var active_threats: Dictionary[StringName, bool] = {}
var threat_progress_value: float = 0.0
var _threat_material: StandardMaterial3D

var neigboring_cells: Dictionary[StringName, HexCell] = {
	"N": null,
	"NE": null,
	"NW": null,
	"S": null,
	"SE": null,
	"SW": null
}

const OFFSET_GAP: float = 0.05

const NEIGHBORS_OFFSET: Dictionary[StringName, Vector3] = {
	"N": Vector3(0, 0, - (sqrt(3) + OFFSET_GAP)),
	"NE": Vector3((1.5 + OFFSET_GAP * sqrt(3) / 2), 0, - (sqrt(3) / 2 + OFFSET_GAP / 2)),
	"NW": Vector3(- (1.5 + OFFSET_GAP * sqrt(3) / 2), 0, - (sqrt(3) / 2 + OFFSET_GAP / 2)),
	"S": Vector3(0, 0, (sqrt(3) + OFFSET_GAP)),
	"SE": Vector3((1.5 + OFFSET_GAP * sqrt(3) / 2), 0, (sqrt(3) / 2 + OFFSET_GAP / 2)),
	"SW": Vector3(- (1.5 + OFFSET_GAP * sqrt(3) / 2), 0, (sqrt(3) / 2 + OFFSET_GAP / 2))
}

signal increased_level(spawn_position: Vector3)

func _ready() -> void:
	world_cells = get_parent()
	level_progress_sprite.visible = false
	_prepare_threat_material()
	populate_cell()


func _prepare_threat_material() -> void:
	var threat_cylinder := get_node_or_null("ThreatShader/Cylinder") as MeshInstance3D
	if threat_cylinder == null:
		return

	var material := threat_cylinder.get_surface_override_material(0)
	if material is StandardMaterial3D:
		_threat_material = (material as StandardMaterial3D).duplicate()
		threat_cylinder.set_surface_override_material(0, _threat_material)


func _ensure_level_progress_viewport() -> bool:
	if level_progress != null:
		return true
	if world_cells == null:
		return false

	var assignment := world_cells.acquire_level_progress_viewport(self)
	if assignment.is_empty():
		return false

	level_progress_viewport = assignment["viewport"]
	level_progress = assignment["progress"]
	level_progress_sprite.texture = level_progress_viewport.get_texture()
	return true


func increase_level(ammount: int, propagate_to_neighbors: bool = true, generate_water: bool = true) -> void:
	if cell_type != "forest":
		return

	increased_level.emit(global_position)
	if generate_water and world_cells != null:
		world_cells.add_water(_get_adjacent_water_count() * ammount)

	# Deforestation strips the tile's ability to spread clicks to its neighbors.
	var neighbor_clicks := 0
	if propagate_to_neighbors and not active_threats.has(THREAT_DEFORESTATION):
		if current_level > 10:
			neighbor_clicks = 2
		elif current_level > 5:
			neighbor_clicks = 1

	if world_cells != null:
		# Contamination caps the tile's productivity to a single point of life per click.
		var life_gained := 1 if active_threats.has(THREAT_CONTAMINATION) else LIFE_PER_CLICK * ammount
		world_cells.add_life(life_gained)

	if active_threats.is_empty():
		_advance_level_up_progress(ammount)
	else:
		_advance_threat_clear_progress(ammount)

	if neighbor_clicks > 0:
		for neighboring_cell: HexCell in neigboring_cells.values():
			if neighboring_cell == null:
				continue
			for _click in range(neighbor_clicks):
				neighboring_cell.increase_level(1, false, false)


func _advance_level_up_progress(ammount: int) -> void:
	if current_level >= MAX_LEVEL:
		level_up_pending = false
		level_progress_value = 0.0
		if level_progress != null:
			level_progress.value = 0.0
		level_progress_sprite.visible = false
		if level_progress_tween != null and level_progress_tween.is_valid():
			level_progress_tween.kill()
		return

	if level_up_pending and not _requires_life_confirmation():
		return

	var clicks_required := maxi(1, CLICKS_PER_LEVEL_MULTIPLIER * current_level)
	var progress_per_click := 100.0 / float(clicks_required)
	var target_progress := level_progress_value + progress_per_click * ammount
	if target_progress >= 100.0 - 0.001:
		target_progress = 100.0
	level_progress_value = target_progress
	var has_progress_viewport := _ensure_level_progress_viewport()
	if has_progress_viewport:
		LevelProgressViewportPool.set_fill_color(level_progress, LEVEL_PROGRESS_COLOR)
	level_progress_sprite.visible = true
	level_up_pending = target_progress >= 100.0
	var requires_confirmation := level_up_pending and _requires_life_confirmation()
	if has_progress_viewport:
		if level_progress_tween != null and level_progress_tween.is_valid():
			level_progress_tween.kill()

		level_progress_tween = create_tween()
		level_progress_tween.set_trans(Tween.TRANS_QUAD)
		level_progress_tween.set_ease(Tween.EASE_OUT)
		level_progress_tween.tween_property(
			level_progress,
			"value",
			target_progress,
			LEVEL_PROGRESS_TWEEN_DURATION
		)
		world_cells.update_level_progress_viewport(level_progress_viewport)
		if level_up_pending and not requires_confirmation:
			level_progress_tween.tween_callback(_complete_level_up)
		if not requires_confirmation:
			level_progress_tween.tween_interval(LEVEL_PROGRESS_VISIBLE_DURATION - LEVEL_PROGRESS_TWEEN_DURATION)
			level_progress_tween.tween_callback(_hide_level_progress)
	elif level_up_pending and not requires_confirmation:
		_complete_level_up()


func _advance_threat_clear_progress(ammount: int) -> void:
	var progress_per_click := 100.0 / float(THREAT_CLEAR_CLICKS)
	var target_progress: float = minf(100.0, threat_progress_value + progress_per_click * ammount)
	threat_progress_value = target_progress

	var has_progress_viewport := _ensure_level_progress_viewport()
	if has_progress_viewport:
		LevelProgressViewportPool.set_fill_color(level_progress, THREAT_PROGRESS_COLOR)
	level_progress_sprite.visible = true

	if level_progress_tween != null and level_progress_tween.is_valid():
		level_progress_tween.kill()

	var is_complete := target_progress >= 100.0 - 0.001
	if has_progress_viewport:
		level_progress_tween = create_tween()
		level_progress_tween.set_trans(Tween.TRANS_QUAD)
		level_progress_tween.set_ease(Tween.EASE_OUT)
		level_progress_tween.tween_property(level_progress, "value", target_progress, LEVEL_PROGRESS_TWEEN_DURATION)
		world_cells.update_level_progress_viewport(level_progress_viewport)
		if is_complete:
			level_progress_tween.tween_callback(_complete_threat_clear)
			level_progress_tween.tween_interval(LEVEL_PROGRESS_VISIBLE_DURATION - LEVEL_PROGRESS_TWEEN_DURATION)
			level_progress_tween.tween_callback(_hide_level_progress)
	elif is_complete:
		_complete_threat_clear()


func _complete_threat_clear() -> void:
	active_threats.clear()
	threat_progress_value = 0.0
	if level_progress != null:
		level_progress.value = 0.0
	_refresh_threat_visuals()


## Adds [param threat] to this cell. Returns false if the threat is already active
## or the cell can't be threatened (only forest cells can).
func add_threat(threat: StringName) -> bool:
	if cell_type != "forest" or active_threats.has(threat):
		return false

	active_threats[threat] = true
	_refresh_threat_visuals()
	return true


## Drops the cell one level to simulate fire damage. Returns true if the tree
## count actually changed (so the caller knows to rebuild tree batches).
func degrade_from_fire() -> bool:
	if current_level <= 0:
		return false

	var previous_tree_count := get_tree_count()
	current_level = maxi(0, current_level - 1)
	populate_cell()
	return get_tree_count() != previous_tree_count


func _refresh_threat_visuals() -> void:
	if threat_shader == null:
		return

	if active_threats.is_empty():
		threat_shader.visible = false
		return

	var blended_color := Color(0.0, 0.0, 0.0, 0.0)
	for threat: StringName in active_threats:
		blended_color += THREAT_COLORS.get(threat, Color.WHITE)
	blended_color /= float(active_threats.size())
	blended_color.a = 1.0

	if _threat_material != null:
		_threat_material.albedo_color = blended_color
	threat_shader.visible = true


func _get_adjacent_water_count() -> int:
	var water_count := 0
	for neighboring_cell: HexCell in neigboring_cells.values():
		if neighboring_cell != null and neighboring_cell.cell_type in ["water", "river"]:
			water_count += 1
	return water_count


func confirm_level_up() -> void:
	if not level_up_pending or not _requires_life_confirmation():
		return
	if level_progress_value < 100.0:
		return
	if world_cells == null or not world_cells.spend_life(LEVEL_UP_LIFE_COST):
		return

	if level_progress_tween != null and level_progress_tween.is_valid():
		level_progress_tween.kill()
	_complete_level_up()
	_hide_level_progress()


func _requires_life_confirmation() -> bool:
	return current_level == 5 or current_level == 10


func _complete_level_up() -> void:
	if not level_up_pending:
		return

	level_up_pending = false
	level_progress_value = 0.0
	if level_progress != null:
		level_progress.value = 0.0
	if current_level == MAX_LEVEL:
		return

	var previous_tree_count := get_tree_count()
	current_level += 1
	populate_cell()
	if world_cells != null:
		world_cells.rebuild_tree_batches(self, previous_tree_count)


func _hide_level_progress() -> void:
	level_progress_sprite.visible = false
	if level_progress_tween != null and level_progress_tween.is_valid():
		level_progress_tween.kill()
	level_progress_tween = null
	if world_cells != null:
		world_cells.release_level_progress_viewport(self)
	level_progress = null
	level_progress_viewport = null
	level_progress_sprite.texture = null


func get_tree_count() -> int:
	return maxi(0, current_level)


func populate_cell() -> void:
	var water_mesh: Node3D = get_node_or_null("WaterShader") as Node3D
	var grass_mesh: Node3D = get_node_or_null("GrassShader") as Node3D
	var river_mesh: Node3D = get_node_or_null("RiverShader") as Node3D
	if water_mesh == null or grass_mesh == null:
		return

	water_mesh.visible = cell_type == "water"
	grass_mesh.visible = cell_type == "forest" or cell_type == "river"
	if river_mesh != null:
		river_mesh.visible = false


func pulse() -> void:
	$AnimationPlayer.play("pulse")
