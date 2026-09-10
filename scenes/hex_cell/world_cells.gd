class_name WorldCells
extends Node3D

signal world_generated(center: Vector3, bounds: AABB)

@export_range(1, 1000, 1) var height: int = 40
@export_range(1, 1000, 1) var width: int = 80
@export_range(0, 100, 1) var cell_level: int = 50
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
@export var culling_target_path: NodePath = NodePath("../CameraController/CameraTarget")
@export_range(1.0, 10.0, 0.1) var culling_zoom_multiplier: float = 2.5
@export_range(0.0, 100.0, 1.0) var culling_distance_offset: float = 10.0
@export_range(0.05, 1.0, 0.05) var culling_update_interval: float = 0.2
@export_range(2, 20, 1) var tree_chunk_size: int = 2
@export_group("Test Culling")
@export var use_fixed_test_culling: bool = true
@export_range(0.1, 100.0, 0.1) var fixed_test_culling_distance: float = 10
@export var exact_test_tree_culling: bool = false
@export var packed_hex_scene: PackedScene = preload("res://scenes/hex_cell/hex_cell.tscn")

var cells: Dictionary[Vector2i, HexCell] = {}
var is_generated: bool = false
var generated_tree_count: int = 0
var _culling_time: float = 0.0
var _generated_tree_root: Node3D
var _generated_tree_chunks: Dictionary[Vector2i, Node3D] = {}


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
			_set_cell_visible(cell, true)
		for chunk: Node3D in _generated_tree_chunks.values():
			_set_tree_chunk_visible(chunk, true)
		return

	_culling_time += delta
	if _culling_time < culling_update_interval:
		return

	_culling_time = 0.0
	_update_cell_visibility()


func generate_world() -> void:
	is_generated = false
	generated_tree_count = 0
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
			cell.current_level = cell_level
			cell.cell_type = _get_cell_type(coordinate, rng)
			cell.position = _get_cell_position(coordinate)
			add_child(cell)
			cells[coordinate] = cell
			if cell.cell_type == "forest":
				generated_tree_count += mini(cell.max_trees_per_cell, maxi(0, int(cell_level * cell.trees_per_level)))

	_assign_neighbors()
	_generate_world_trees()
	is_generated = true
	_culling_time = culling_update_interval
	_update_cell_visibility()
	var bounds: AABB = get_world_bounds()
	world_generated.emit(bounds.get_center(), bounds)


func _generate_world_trees() -> void:
	_clear_generated_trees()
	if generated_tree_count == 0:
		return

	var source_cell: HexCell
	for cell: HexCell in cells.values():
		if cell.cell_type == "forest" and not cell.tree_meshes.is_empty():
			source_cell = cell
			break

	if source_cell == null:
		return

	var tree_mesh_data: Array[Dictionary] = []
	for tree_index: int in range(source_cell.tree_meshes.size()):
		var tree_root: Node3D = source_cell.tree_meshes[tree_index].instantiate() as Node3D
		if tree_root == null:
			continue

		_collect_tree_mesh_data(tree_root, Transform3D.IDENTITY, tree_index, tree_mesh_data)
		tree_root.free()

	if tree_mesh_data.is_empty():
		return

	var transforms_by_chunk: Dictionary[Vector2i, Array] = {}
	for coordinate: Vector2i in cells:
		if cells[coordinate].cell_type != "forest":
			continue
		var chunk_coordinate := _get_tree_chunk_coordinate(coordinate)
		if not transforms_by_chunk.has(chunk_coordinate):
			var chunk_mesh_transforms: Array = []
			for _mesh_data: Dictionary in tree_mesh_data:
				chunk_mesh_transforms.append([])
			transforms_by_chunk[chunk_coordinate] = chunk_mesh_transforms

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for coordinate: Vector2i in cells:
		var cell: HexCell = cells[coordinate]
		if cell.cell_type != "forest":
			continue
		var chunk_coordinate := _get_tree_chunk_coordinate(coordinate)
		var transforms_by_mesh: Array = transforms_by_chunk[chunk_coordinate]

		var spawn_count: int = mini(
			cell.max_trees_per_cell,
			maxi(0, int(cell.current_level * cell.trees_per_level))
		)
		for _tree_index in range(spawn_count):
			var spawn_position: Vector2 = _get_random_point_in_hex(rng)
			var variant_index: int = rng.rand_weighted([0.7, 0.2, 0.1])
			var tree_scale: float = 1.0 + rng.randf_range(0.0, variant_index)
			var tree_transform := Transform3D(
				Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * tree_scale),
				cell.position + Vector3(spawn_position.x, 0.05, spawn_position.y)
			)

			for mesh_index: int in range(tree_mesh_data.size()):
				if tree_mesh_data[mesh_index]["tree_index"] == variant_index:
					var base_transform: Transform3D = tree_mesh_data[mesh_index]["transform"]
					transforms_by_mesh[mesh_index].append(tree_transform * base_transform)

	_generated_tree_root = Node3D.new()
	_generated_tree_root.name = "GeneratedTrees"
	add_child(_generated_tree_root)

	for chunk_coordinate: Vector2i in transforms_by_chunk:
		var chunk_mesh_transforms: Array = transforms_by_chunk[chunk_coordinate]
		var chunk_root := Node3D.new()
		chunk_root.name = "TreeChunk_%d_%d" % [chunk_coordinate.x, chunk_coordinate.y]
		chunk_root.position = _get_chunk_center(chunk_coordinate)
		_generated_tree_root.add_child(chunk_root)
		_generated_tree_chunks[chunk_coordinate] = chunk_root

		for mesh_index: int in range(tree_mesh_data.size()):
			var transforms: Array = chunk_mesh_transforms[mesh_index]
			if transforms.is_empty():
				continue

			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = tree_mesh_data[mesh_index]["mesh"]
			multimesh.instance_count = transforms.size()
			for instance_index: int in range(transforms.size()):
				var local_transform: Transform3D = transforms[instance_index]
				local_transform.origin -= chunk_root.position
				multimesh.set_instance_transform(instance_index, local_transform)

			var multimesh_instance := MultiMeshInstance3D.new()
			multimesh_instance.multimesh = multimesh
			chunk_root.add_child(multimesh_instance)


func _get_chunk_center(chunk_coordinate: Vector2i) -> Vector3:
	if exact_test_tree_culling and use_fixed_test_culling:
		return _get_cell_position(chunk_coordinate)

	var center_coordinate := Vector2i(
		chunk_coordinate.x * tree_chunk_size + tree_chunk_size / 2,
		chunk_coordinate.y * tree_chunk_size + tree_chunk_size / 2
	)
	return _get_cell_position(center_coordinate)


func _get_tree_chunk_coordinate(coordinate: Vector2i) -> Vector2i:
	if exact_test_tree_culling and use_fixed_test_culling:
		return coordinate

	return Vector2i(
		floori(coordinate.x / tree_chunk_size),
		floori(coordinate.y / tree_chunk_size)
	)


func _collect_tree_mesh_data(
	node: Node,
	parent_transform: Transform3D,
	tree_index: int,
	result: Array[Dictionary]
) -> void:
	var node_transform: Transform3D = parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh != null:
			result.append({
				"mesh": mesh_instance.mesh,
				"transform": node_transform,
				"tree_index": tree_index
			})

	for child: Node in node.get_children():
		_collect_tree_mesh_data(child, node_transform, tree_index, result)


func _get_random_point_in_hex(rng: RandomNumberGenerator) -> Vector2:
	for _attempt in range(50):
		var angle: float = rng.randf_range(0.0, TAU)
		var distance: float = rng.randf_range(0.0, 1.0)
		var point := Vector2(cos(angle) * distance, sin(angle) * distance)
		if _is_point_in_hexagon(point):
			return point

	return Vector2.ZERO


func _is_point_in_hexagon(point: Vector2) -> bool:
	var vertices: Array[Vector2] = []
	for index in range(6):
		var angle: float = deg_to_rad(index * 60.0)
		vertices.append(Vector2(cos(angle), sin(angle)))

	for index in range(6):
		var p1: Vector2 = vertices[index]
		var p2: Vector2 = vertices[(index + 1) % 6]
		if (p2 - p1).cross(point - p1) < 0.0:
			return false

	return true


func _update_cell_visibility() -> void:
	var camera_controller: Node3D = get_node_or_null(culling_camera_path) as Node3D
	if camera_controller == null:
		return

	var camera_target: Node3D = get_node_or_null(culling_target_path) as Node3D
	if camera_target == null:
		return

	var culling_distance: float
	if use_fixed_test_culling:
		culling_distance = fixed_test_culling_distance
	else:
		var phantom_camera: Node = camera_controller.get_node_or_null("PhantomCamera3D")
		if phantom_camera == null:
			return
		var zoom_distance: float = phantom_camera.get("spring_length")
		culling_distance = zoom_distance * culling_zoom_multiplier + culling_distance_offset
	var target_position: Vector3 = camera_target.global_position
	var culling_distance_squared: float = culling_distance * culling_distance

	for cell: HexCell in cells.values():
		var cell_position: Vector3 = cell.global_position
		var horizontal_offset := Vector2(
			cell_position.x - target_position.x,
			cell_position.z - target_position.z
		)
		_set_cell_visible(cell, horizontal_offset.length_squared() < culling_distance_squared)

	for chunk_coordinate: Vector2i in _generated_tree_chunks:
		var chunk: Node3D = _generated_tree_chunks[chunk_coordinate]
		var chunk_offset := Vector2(
			chunk.global_position.x - target_position.x,
			chunk.global_position.z - target_position.z
		)
		_set_tree_chunk_visible(chunk, chunk_offset.length_squared() < culling_distance_squared)


func _set_cell_visible(cell: HexCell, is_visible: bool) -> void:
	var water_mesh: Node3D = cell.get_node_or_null("WaterShader") as Node3D
	var grass_mesh: Node3D = cell.get_node_or_null("GrassShader") as Node3D
	var river_mesh: Node3D = cell.get_node_or_null("RiverShader") as Node3D
	if water_mesh != null:
		_set_visual_descendants_visible(water_mesh, is_visible and cell.cell_type == "water")
	if grass_mesh != null:
		_set_visual_descendants_visible(grass_mesh, is_visible and (cell.cell_type == "forest" or cell.cell_type == "river"))
	if river_mesh != null:
		_set_visual_descendants_visible(river_mesh, is_visible and cell.cell_type == "river")


func _set_tree_chunk_visible(chunk: Node3D, is_visible: bool) -> void:
	for child: Node in chunk.get_children():
		_set_visual_descendants_visible(child, is_visible)


func _set_visual_descendants_visible(node: Node, is_visible: bool) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = is_visible
	for child: Node in node.get_children():
		_set_visual_descendants_visible(child, is_visible)


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
	_clear_generated_trees()
	for child: Node in get_children():
		if child is HexCell:
			child.free()


func _clear_generated_trees() -> void:
	if is_instance_valid(_generated_tree_root):
		_generated_tree_root.free()
	_generated_tree_root = null
	_generated_tree_chunks.clear()