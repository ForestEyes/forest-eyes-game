class_name TreeScatter
extends RefCounted

## Scatters trees inside every "forest" cell and batches them into
## MultiMeshInstance3D chunks for efficient rendering, including the
## grow-in animation played when a cell levels up.

signal growth_finished

const TREE_MIN_DISTANCE: float = 0.150
const TREE_SCALE_MULTIPLIER: float = 1.5

var _host: Node3D
var _horizontal_spacing: float
var _vertical_spacing: float
var tree_chunk_size: int
var exact_test_tree_culling: bool
var use_fixed_test_culling: bool
var tree_generation_seed: int

var _generated_tree_root: Node3D
var _tree_growth_root: Node3D
var _generated_tree_chunks: Dictionary[Vector2i, Node3D] = {}
var _active_tree_growth_tweens: int = 0
var _pending_tree_animations: Dictionary = {}


func _init(
	host: Node3D,
	horizontal_spacing: float,
	vertical_spacing: float,
	p_tree_chunk_size: int,
	p_exact_test_tree_culling: bool,
	p_use_fixed_test_culling: bool
) -> void:
	_host = host
	_horizontal_spacing = horizontal_spacing
	_vertical_spacing = vertical_spacing
	tree_chunk_size = p_tree_chunk_size
	exact_test_tree_culling = p_exact_test_tree_culling
	use_fixed_test_culling = p_use_fixed_test_culling


func get_chunks() -> Dictionary[Vector2i, Node3D]:
	return _generated_tree_chunks


func _get_cell_position(coordinate: Vector2i) -> Vector3:
	return HexGrid.offset_to_world(coordinate, _horizontal_spacing, _vertical_spacing)


## Rebuilds every tree chunk from the current cell states. If [param animated_cell]
## leveled up from [param animated_from_count] trees, its new trees grow in with a tween
## instead of appearing instantly.
func generate(cells: Dictionary, generated_tree_count: int, animated_cell: HexCell = null, animated_from_count: int = -1) -> void:
	if animated_cell != null and animated_from_count >= 0:
		if not _pending_tree_animations.has(animated_cell):
			_pending_tree_animations[animated_cell] = animated_from_count

	clear_generated_trees()
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
	var generated_tree_positions: Dictionary = {}
	var animated_tree_data: Array[Dictionary] = []
	for coordinate: Vector2i in cells:
		if cells[coordinate].cell_type != "forest":
			continue
		var chunk_coordinate := _get_tree_chunk_coordinate(coordinate)
		if not transforms_by_chunk.has(chunk_coordinate):
			var chunk_mesh_transforms: Array = []
			for _mesh_data: Dictionary in tree_mesh_data:
				chunk_mesh_transforms.append([])
			transforms_by_chunk[chunk_coordinate] = chunk_mesh_transforms

	for coordinate: Vector2i in cells:
		var cell: HexCell = cells[coordinate]
		if cell.cell_type != "forest":
			continue
		var chunk_coordinate := _get_tree_chunk_coordinate(coordinate)
		var transforms_by_mesh: Array = transforms_by_chunk[chunk_coordinate]
		var cell_rng := RandomNumberGenerator.new()
		cell_rng.seed = _get_cell_tree_seed(coordinate)

		var spawn_count: int = cell.get_tree_count()
		for tree_index in range(spawn_count):
			var spawn_position: Vector2
			var has_valid_position := false
			for _attempt in range(250):
				var candidate_position: Vector2 = _get_random_point_in_hex(cell_rng)
				var world_position := Vector2(
					cell.position.x + candidate_position.x,
					cell.position.z + candidate_position.y
				)
				var position_bucket := Vector2i(
					floori(world_position.x / TREE_MIN_DISTANCE),
					floori(world_position.y / TREE_MIN_DISTANCE)
				)
				var is_too_close := false
				for bucket_x in range(-1, 2):
					for bucket_y in range(-1, 2):
						var nearby_bucket := position_bucket + Vector2i(bucket_x, bucket_y)
						if not generated_tree_positions.has(nearby_bucket):
							continue
						for generated_position: Vector2 in generated_tree_positions[nearby_bucket]:
							if world_position.distance_squared_to(generated_position) < TREE_MIN_DISTANCE * TREE_MIN_DISTANCE:
								is_too_close = true
								break
						if is_too_close:
							break
				if is_too_close:
					continue
				spawn_position = candidate_position
				var bucket_positions: Array = generated_tree_positions.get(position_bucket, [])
				bucket_positions.append(world_position)
				generated_tree_positions[position_bucket] = bucket_positions
				has_valid_position = true
				break
			if not has_valid_position:
				continue

			var variant_index: int = cell_rng.rand_weighted([0.725, 0.225, 0.05])
			var tree_scale: float = 1 + cell_rng.randf_range(1, 1.15)
			tree_scale *= TREE_SCALE_MULTIPLIER
			var tree_transform := Transform3D(
				Basis(Vector3.UP, cell_rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * tree_scale),
				cell.position + Vector3(spawn_position.x, 0.05, spawn_position.y)
			)

			var pending_from_count: int = _pending_tree_animations.get(cell, -1)
			var is_pending_tree := pending_from_count >= 0 and tree_index >= pending_from_count
			var animate_tree := cell == animated_cell and is_pending_tree
			if animate_tree:
				animated_tree_data.append({
					"tree_transform": tree_transform,
					"tree_scene": cell.tree_meshes[variant_index]
				})
			for mesh_index: int in range(tree_mesh_data.size()):
				if tree_mesh_data[mesh_index]["tree_index"] == variant_index:
					var base_transform: Transform3D = tree_mesh_data[mesh_index]["transform"]
					if not is_pending_tree:
						transforms_by_mesh[mesh_index].append(tree_transform * base_transform)

	_generated_tree_root = Node3D.new()
	_generated_tree_root.name = "GeneratedTrees"
	_host.add_child(_generated_tree_root)

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

	_animate_new_trees(animated_tree_data)


func _animate_new_trees(tree_data: Array[Dictionary]) -> void:
	if tree_data.is_empty():
		return

	if _tree_growth_root == null:
		_tree_growth_root = Node3D.new()
		_tree_growth_root.name = "GrowingTrees"
		_host.add_child(_tree_growth_root)

	_active_tree_growth_tweens += tree_data.size()
	for data: Dictionary in tree_data:
		var tree_root: Node3D = data["tree_scene"].instantiate() as Node3D
		if tree_root == null:
			_active_tree_growth_tweens -= 1
			continue

		tree_root.transform = data["tree_transform"]
		var final_scale := tree_root.scale
		tree_root.scale = Vector3.ZERO
		_tree_growth_root.add_child(tree_root)

		var tween := _host.create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(tree_root, "scale", final_scale, 0.6)
		tween.finished.connect(_on_tree_growth_tween_finished)


func _on_tree_growth_tween_finished() -> void:
	_active_tree_growth_tweens -= 1
	if _active_tree_growth_tweens == 0:
		_pending_tree_animations.clear()
		clear_growth()
		growth_finished.emit()


func _get_cell_tree_seed(coordinate: Vector2i) -> int:
	return tree_generation_seed + coordinate.x * 73856093 + coordinate.y * 19349663


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
			var mesh: Mesh = mesh_instance.mesh
			var material_overrides: Array[Material] = []
			for surface_index: int in range(mesh.get_surface_count()):
				var material: Material = mesh_instance.get_surface_override_material(surface_index)
				if material != null:
					material_overrides.append(material)
				else:
					material_overrides.append(null)

			if material_overrides.any(func(material: Material) -> bool:
				return material != null
			):
				var mesh_copy: Mesh = mesh.duplicate()
				for surface_index: int in range(mini(mesh_copy.get_surface_count(), material_overrides.size())):
					if material_overrides[surface_index] != null:
						mesh_copy.surface_set_material(surface_index, material_overrides[surface_index])
				mesh = mesh_copy

			result.append({
				"mesh": mesh,
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
		if HexGrid.is_point_in_hexagon(point):
			return point

	return Vector2.ZERO


func clear_generated_trees() -> void:
	if is_instance_valid(_generated_tree_root):
		_generated_tree_root.free()
	_generated_tree_root = null
	_generated_tree_chunks.clear()


func clear_growth() -> void:
	if is_instance_valid(_tree_growth_root):
		_tree_growth_root.free()
	_tree_growth_root = null
	_active_tree_growth_tweens = 0


func clear_all() -> void:
	clear_generated_trees()
	clear_growth()
