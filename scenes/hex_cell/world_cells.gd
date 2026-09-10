class_name WorldCells
extends Node3D

signal world_generated(center: Vector3, bounds: AABB)

@export_range(1, 1000, 1) var height: int = 40
@export_range(1, 1000, 1) var width: int = 80
@export_range(0, 1000000, 1) var random_seed: int = 0
@export_range(0, 100, 1) var water_border_distance: int = 10
@export_group("Terrain Generation Chances")
@export var forest_chance: float = 0.7
@export var river_chance: float = 0.2
@export var water_chance: float = 0.1
@export var river_neighbor_influence: float = 0.15
@export var water_neighbor_influence: float = 0.2
@export_group("Distance Culling")
@export var enable_distance_culling: bool = true
@export var culling_camera_path: NodePath = NodePath("../CameraController")
@export_range(1.0, 10.0, 0.1) var culling_zoom_multiplier: float = 2.5
@export_range(0.0, 100.0, 1.0) var culling_distance_offset: float = 10.0
@export_range(0.05, 1.0, 0.05) var culling_update_interval: float = 0.2
@export var packed_hex_scene: PackedScene = preload("res://scenes/hex_cell/hex_cell.tscn")

var cells: Dictionary[Vector2i, HexCell] = {}
var is_generated: bool = false
var _culling_time: float = 0.0


const HEX_RADIUS: float = 1.0
const HEX_HORIZONTAL_SPACING: float = HEX_RADIUS * 1.5 + 0.05
const HEX_VERTICAL_SPACING: float = HEX_RADIUS * sqrt(3.0) + 0.025
const CENTRAL_FOREST_RADIUS_RATIO: float = 0.2


const EVEN_COLUMN_NEIGHBOR_OFFSETS: Dictionary[StringName, Vector2i] = {
	"N": Vector2i(0, -1),
	"NE": Vector2i(1, -1),
	"NW": Vector2i(-1, -1),
	"S": Vector2i(0, 1),
	"SE": Vector2i(1, 0),
	"SW": Vector2i(-1, 0)
}

const ODD_COLUMN_NEIGHBOR_OFFSETS: Dictionary[StringName, Vector2i] = {
	"N": Vector2i(0, -1),
	"NE": Vector2i(1, 0),
	"NW": Vector2i(-1, 0),
	"S": Vector2i(0, 1),
	"SE": Vector2i(1, 1),
	"SW": Vector2i(-1, 1)
}


func _ready() -> void:
	generate_world()


func _process(delta: float) -> void:
	if not enable_distance_culling:
		for cell: HexCell in cells.values():
			cell.visible = true
		return

	_culling_time += delta
	if _culling_time < culling_update_interval:
		return

	_culling_time = 0.0
	_update_cell_visibility()


func generate_world() -> void:
	is_generated = false
	_clear_cells()
	cells.clear()

	if packed_hex_scene == null:
		push_error("WorldCells requires a packed hex cell scene.")
		return

	var rng := RandomNumberGenerator.new()
	if random_seed == 0:
		rng.randomize()
	else:
		rng.seed = random_seed

	for row in range(height):
		for column in range(width):
			var cell: HexCell = packed_hex_scene.instantiate() as HexCell
			if cell == null:
				push_error("The packed hex scene must have a HexCell root node.")
				return

			var coordinate := Vector2i(column, row)
			cell.name = "HexCell_%d_%d" % [column, row]
			cell.cell_type = _get_cell_type(coordinate, rng)
			cell.position = _get_cell_position(coordinate)
			add_child(cell)
			cells[coordinate] = cell

	_assign_neighbors()
	is_generated = true
	_culling_time = culling_update_interval
	var bounds: AABB = get_world_bounds()
	world_generated.emit(bounds.get_center(), bounds)


func _update_cell_visibility() -> void:
	var camera_controller: Node3D = get_node_or_null(culling_camera_path) as Node3D
	if camera_controller == null:
		return

	var camera_target: Node3D = camera_controller.get_node_or_null("CameraTarget") as Node3D
	var phantom_camera: Node = camera_controller.get_node_or_null("PhantomCamera3D")
	if camera_target == null or phantom_camera == null:
		return

	var zoom_distance: float = phantom_camera.get("spring_length")
	var culling_distance: float = zoom_distance * culling_zoom_multiplier + culling_distance_offset
	var target_position: Vector3 = camera_target.global_position
	var culling_distance_squared: float = culling_distance * culling_distance

	for cell: HexCell in cells.values():
		var cell_position: Vector3 = cell.global_position
		var horizontal_offset := Vector2(
			cell_position.x - target_position.x,
			cell_position.z - target_position.z
		)
		cell.visible = horizontal_offset.length_squared() <= culling_distance_squared


func _get_cell_type(coordinate: Vector2i, rng: RandomNumberGenerator) -> String:
	var distance_from_border: int = mini(
		mini(coordinate.x, width - 1 - coordinate.x),
		mini(coordinate.y, height - 1 - coordinate.y)
	)
	if distance_from_border <= water_border_distance:
		return "water"

	var map_center := Vector2((width - 1) * 0.5, (height - 1) * 0.5)
	var central_radius: float = maxf(1.0, mini(width, height) * CENTRAL_FOREST_RADIUS_RATIO)
	if Vector2(coordinate).distance_to(map_center) <= central_radius:
		return "forest"

	var river_neighbors: int = 0
	var water_neighbors: int = 0
	var neighbor_offsets: Dictionary[StringName, Vector2i] = _get_neighbor_offsets(coordinate.x)
	for neighbor_offset: Vector2i in neighbor_offsets.values():
		var neighbor: HexCell = cells.get(coordinate + neighbor_offset) as HexCell
		if neighbor == null:
			continue
		if neighbor.cell_type == "river":
			river_neighbors += 1
		elif neighbor.cell_type == "water":
			water_neighbors += 1

	var forest_weight: float = maxf(
		0.0,
		forest_chance - river_neighbors * river_neighbor_influence - water_neighbors * water_neighbor_influence
	)
	var river_weight: float = 0.0
	var favorable_river_neighbors: int = 0
	for neighbor_offset: Vector2i in neighbor_offsets.values():
		var neighbor: HexCell = cells.get(coordinate + neighbor_offset) as HexCell
		if neighbor != null and (neighbor.cell_type == "forest" or neighbor.cell_type == "river"):
			favorable_river_neighbors += 1

	if favorable_river_neighbors > water_neighbors:
		river_weight = river_chance + river_neighbors * river_neighbor_influence

	var water_weight: float = water_chance + water_neighbors * water_neighbor_influence
	var selected_type: int = rng.rand_weighted([forest_weight, river_weight, water_weight])
	return ["forest", "river", "water"][selected_type]


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
	return Vector3(
		coordinate.x * HEX_HORIZONTAL_SPACING,
		0.0,
		coordinate.y * HEX_VERTICAL_SPACING + (coordinate.x % 2) * HEX_VERTICAL_SPACING / 2.0
	)


func _assign_neighbors() -> void:
	for coordinate: Vector2i in cells:
		var cell: HexCell = cells[coordinate]
		var neighbor_offsets: Dictionary[StringName, Vector2i] = _get_neighbor_offsets(coordinate.x)
		for direction: StringName in neighbor_offsets:
			var neighbor_coordinate: Vector2i = coordinate + neighbor_offsets[direction]
			cell.neigboring_cells[direction] = cells.get(neighbor_coordinate) as HexCell


func _get_neighbor_offsets(column: int) -> Dictionary[StringName, Vector2i]:
	return EVEN_COLUMN_NEIGHBOR_OFFSETS if column % 2 == 0 else ODD_COLUMN_NEIGHBOR_OFFSETS


func _clear_cells() -> void:
	for child: Node in get_children():
		if child is HexCell:
			child.free()