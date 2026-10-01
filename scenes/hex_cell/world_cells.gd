class_name WorldCells
extends Node3D

## Orchestrates the hex-grid island: owns the cell dictionary and delegates
## terrain, river, tree and visibility concerns to focused modules (see
## scenes/hex_cell/world/ and [HexGrid]).

signal world_generated(center: Vector3, bounds: AABB)

const LEVEL_PROGRESS_VIEWPORT_SCENE: PackedScene = preload("res://scenes/hex_cell/level_progress_viewport.tscn")
const LEVEL_PROGRESS_VIEWPORT_POOL_SIZE: int = 10

@export_range(1, 1000, 1) var height: int = 40
@export_range(1, 1000, 1) var width: int = 80
@export_range(0, 100, 1) var cell_level: int = 50
@export_range(0, 1000000, 1) var random_seed: int = 0
@export_range(0, 100, 1) var water_border_distance: int = 10
@export_group("Coastline")
@export_range(0, 20, 1) var coastline_bay_depth: int = 4
@export_range(0.05, 1.0, 0.05) var coastline_bay_frequency: float = 0.5
@export_group("Terrain Generation Chances")
@export var forest_chance: float = 0.7
@export var river_chance: float = 0.2
@export var water_chance: float = 0.1
@export var river_neighbor_influence: float = 0.15
@export var water_neighbor_influence: float = 0.2
@export_group("Distance Culling")
@export var enable_distance_culling: bool = true
@export var culling_camera_path: NodePath = NodePath("../CameraController")
@export var culling_target_path: NodePath = NodePath("../CameraController/CameraTarget")
@export_range(1.0, 10.0, 0.1) var culling_zoom_multiplier: float = 2.5
@export_range(0.0, 100.0, 1.0) var culling_distance_offset: float = 12.0
@export_range(0.05, 1.0, 0.05) var culling_update_interval: float = 0.05
@export_range(2, 20, 1) var tree_chunk_size: int = 2
@export_group("Tree LOD")
@export var enable_tree_lod: bool = true
@export_range(0.0, 100.0, 0.5) var tree_lod_start_zoom: float = 8.0
@export_range(0.0, 100.0, 0.5) var tree_lod_end_zoom: float = 25.0
@export_range(0.05, 1.0, 0.05) var tree_lod_min_ratio: float = 0.2
@export_group("River Rendering")
@export_range(0.05, 2.0, 0.05) var river_width: float = 0.45
@export_range(0.05, 2.0, 0.05) var river_max_width: float = 0.9
@export_range(2, 50, 1) var river_min_points_for_scaling: int = 4
@export_range(2, 100, 1) var river_max_points_for_scaling: int = 25
@export_range(0.1, 3.0, 0.05) var river_source_lake_width: float = 1.1
@export_range(0.1, 3.0, 0.1) var river_source_lake_length: float = 1.0
@export_range(0.0, 1.0, 0.05) var river_width_variation: float = 0.35
@export_range(0.0, 0.5, 0.01) var river_position_noise: float = 0.12
@export_range(0.1, 5.0, 0.1) var river_noise_frequency: float = 1.5
@export_range(0.001, 0.1, 0.002) var river_height_offset: float = 0.01
@export_range(0.01, 0.5, 0.01) var river_curve_bake_interval: float = 0.1
@export var river_shader: Shader = preload("res://shaders/water_shader.tres")
@export var river_material: Material
@export_group("Test Culling")
@export var use_fixed_test_culling: bool = true
@export_range(0.1, 100.0, 0.1) var fixed_test_culling_distance: float = 15
@export var exact_test_tree_culling: bool = false
@export var packed_hex_scene: PackedScene = preload("res://scenes/hex_cell/hex_cell.tscn")
@export_group("Threats")
@export_range(1.0, 120.0, 0.5) var threat_spawn_interval: float = 10.0
@export_range(1, 50, 1) var threat_cells_per_wave: int = 5
@export_range(0.5, 60.0, 0.5) var threat_effect_interval: float = 5.0

const HEX_RADIUS: float = 1.0
const HEX_HORIZONTAL_SPACING: float = HEX_RADIUS * 1.5 + 0.05
const HEX_VERTICAL_SPACING: float = HEX_RADIUS * sqrt(3.0) + 0.025

var cells: Dictionary[Vector2i, HexCell] = {}
var is_generated: bool = false
var generated_tree_count: int = 0
var life: int = 0
var water: int = 0
var science: int = 0

var _tree_generation_seed: int = 0

var _level_progress_pool: LevelProgressViewportPool
var _culler: VisibilityCuller
var _terrain: TerrainGenerator
var _river_generator: RiverGenerator
var _river_mesh_builder: RiverMeshBuilder
var _tree_scatter: TreeScatter
var _threat_manager: ThreatManager


func _ready() -> void:
	_level_progress_pool = LevelProgressViewportPool.new(self, LEVEL_PROGRESS_VIEWPORT_SCENE, LEVEL_PROGRESS_VIEWPORT_POOL_SIZE)
	_culler = VisibilityCuller.new(
		get_node_or_null(culling_camera_path) as Node3D,
		get_node_or_null(culling_target_path) as Node3D
	)
	_threat_manager = ThreatManager.new(self)
	generate_world()


func _process(delta: float) -> void:
	_sync_culler_config()
	_culler.tick(delta, cells, _tree_scatter.get_chunks() if _tree_scatter != null else {})

	if is_generated:
		_sync_threat_config()
		_threat_manager.tick(delta, cells)


func _sync_culler_config() -> void:
	_culler.enable_distance_culling = enable_distance_culling
	_culler.use_fixed_test_culling = use_fixed_test_culling
	_culler.fixed_test_culling_distance = fixed_test_culling_distance
	_culler.culling_zoom_multiplier = culling_zoom_multiplier
	_culler.culling_distance_offset = culling_distance_offset
	_culler.culling_update_interval = culling_update_interval
	_culler.enable_tree_lod = enable_tree_lod
	_culler.tree_lod_start_zoom = tree_lod_start_zoom
	_culler.tree_lod_end_zoom = tree_lod_end_zoom
	_culler.tree_lod_min_ratio = tree_lod_min_ratio


func _sync_threat_config() -> void:
	_threat_manager.spawn_interval = threat_spawn_interval
	_threat_manager.cells_per_wave = threat_cells_per_wave
	_threat_manager.effect_tick_interval = threat_effect_interval


func acquire_level_progress_viewport(cell: HexCell) -> Dictionary:
	return _level_progress_pool.acquire(cell)


func release_level_progress_viewport(cell: HexCell) -> void:
	_level_progress_pool.release(cell)


func update_level_progress_viewport(viewport: SubViewport) -> void:
	_level_progress_pool.update(viewport)


func generate_world() -> void:
	is_generated = false
	generated_tree_count = 0
	life = 0
	water = 0
	science = 0
	_clear_cells()
	cells.clear()
	if _threat_manager != null:
		_threat_manager.reset()

	if packed_hex_scene == null:
		push_error("WorldCells requires a packed hex cell scene.")
		return

	var rng := RandomNumberGenerator.new()
	if random_seed == 0:
		rng.randomize()
		_tree_generation_seed = rng.seed
	else:
		rng.seed = random_seed
		_tree_generation_seed = random_seed

	_terrain = TerrainGenerator.new(width, height, water_border_distance, coastline_bay_depth, coastline_bay_frequency, _tree_generation_seed)
	_river_generator = RiverGenerator.new(width, height, water_border_distance, _terrain)
	_river_mesh_builder = _build_river_mesh_builder()
	_tree_scatter = _build_tree_scatter()

	for row in range(height):
		for column in range(width):
			var cell: HexCell = packed_hex_scene.instantiate() as HexCell
			if cell == null:
				push_error("The packed hex scene must have a HexCell root node.")
				return

			var coordinate := Vector2i(column, row)
			cell.name = "HexCell_%d_%d" % [column, row]
			cell.current_level = _terrain.generate_weighted_cell_level(rng)
			cell.cell_type = "water"
			cell.position = _get_cell_position(coordinate)
			add_child(cell)
			cells[coordinate] = cell

	_assign_neighbors()
	_generate_island_terrain(rng)
	for cell: HexCell in cells.values():
		if cell.cell_type == "forest":
			generated_tree_count += cell.get_tree_count()
	_tree_scatter.generate(cells, generated_tree_count)
	_generate_rivers()
	is_generated = true
	_sync_culler_config()
	_culler.force_update(cells, _tree_scatter.get_chunks())
	var bounds: AABB = get_world_bounds()
	world_generated.emit(bounds.get_center(), bounds)


func _build_river_mesh_builder() -> RiverMeshBuilder:
	var builder := RiverMeshBuilder.new(self, HEX_HORIZONTAL_SPACING, HEX_VERTICAL_SPACING, _tree_generation_seed)
	builder.river_width = river_width
	builder.river_max_width = river_max_width
	builder.river_min_points_for_scaling = river_min_points_for_scaling
	builder.river_max_points_for_scaling = river_max_points_for_scaling
	builder.river_source_lake_width = river_source_lake_width
	builder.river_source_lake_length = river_source_lake_length
	builder.river_width_variation = river_width_variation
	builder.river_position_noise = river_position_noise
	builder.river_noise_frequency = river_noise_frequency
	builder.river_height_offset = river_height_offset
	builder.river_curve_bake_interval = river_curve_bake_interval
	builder.river_shader = river_shader
	builder.river_material = river_material
	return builder


func _build_tree_scatter() -> TreeScatter:
	var scatter := TreeScatter.new(self, HEX_HORIZONTAL_SPACING, HEX_VERTICAL_SPACING, tree_chunk_size, exact_test_tree_culling, use_fixed_test_culling)
	scatter.tree_generation_seed = _tree_generation_seed
	scatter.growth_finished.connect(_on_tree_growth_finished)
	return scatter


func _on_tree_growth_finished() -> void:
	rebuild_tree_batches()


func add_life(amount: int) -> void:
	life += amount


func add_water(amount: int) -> void:
	water += maxi(0, amount)


func add_science(amount: int) -> void:
	science += maxi(0, amount)


func spend_life(amount: int) -> bool:
	if life < amount:
		return false

	life -= amount
	return true


func rebuild_tree_batches(animated_cell: HexCell = null, animated_from_count: int = -1) -> void:
	generated_tree_count = 0
	for cell: HexCell in cells.values():
		if cell.cell_type == "forest":
			generated_tree_count += cell.get_tree_count()

	_tree_scatter.generate(cells, generated_tree_count, animated_cell, animated_from_count)
	if enable_distance_culling:
		_sync_culler_config()
		_culler.force_update(cells, _tree_scatter.get_chunks())


func _generate_island_terrain(rng: RandomNumberGenerator) -> void:
	_terrain.assign_base_terrain(cells)
	_river_generator.carve_rivers(cells, rng)
	for cell: HexCell in cells.values():
		cell.populate_cell()


func _generate_rivers() -> void:
	var chains: Array[Array] = _river_generator.trace_river_chains(cells)
	_river_mesh_builder.rebuild(cells, chains)


func get_cell(coordinate: Vector2i) -> HexCell:
	return cells.get(coordinate) as HexCell


func get_neighbors(coordinate: Vector2i) -> Dictionary[StringName, HexCell]:
	var cell: HexCell = get_cell(coordinate)
	if cell == null:
		return {}

	return cell.neigboring_cells.duplicate()


func get_world_bounds() -> AABB:
	var bounds := AABB(Vector3.ZERO, Vector3.ZERO)
	var has_bounds: bool = false

	for cell: HexCell in cells.values():
		var cell_bounds := AABB(
			cell.position - Vector3(HEX_RADIUS, 0.0, HEX_VERTICAL_SPACING / 2.0),
			Vector3(HEX_RADIUS * 2.0, 0.0, HEX_VERTICAL_SPACING)
		)
		if not has_bounds:
			bounds = cell_bounds
			has_bounds = true
		else:
			bounds = bounds.merge(cell_bounds)

	return bounds


func _get_cell_position(coordinate: Vector2i) -> Vector3:
	return HexGrid.offset_to_world(coordinate, HEX_HORIZONTAL_SPACING, HEX_VERTICAL_SPACING)


func _assign_neighbors() -> void:
	for coordinate: Vector2i in cells:
		var cell: HexCell = cells[coordinate]
		var neighbors: Dictionary[HexGrid.Direction, Vector2i] = HexGrid.get_all_neighbors(coordinate)
		for direction: HexGrid.Direction in neighbors:
			cell.neigboring_cells[HexGrid.direction_name(direction)] = cells.get(neighbors[direction]) as HexCell


func _clear_cells() -> void:
	if _tree_scatter != null:
		_tree_scatter.clear_all()
	if _river_mesh_builder != null:
		_river_mesh_builder.clear()
	if _level_progress_pool != null:
		_level_progress_pool.reset_assignments()
	for child: Node in get_children():
		if child is HexCell:
			child.free()
