class_name HexCell
extends Node3D

@export_enum("forest", "water", "river") var cell_type: String = "water"

@export var tree_meshes: Array[PackedScene]

@export var current_level: int = 50
@export var trees_per_level: float = 4.0
@export var max_trees_per_cell: int = 200
@export var tree_visibility_distance: float = 60.0

@export var packed_hex_scene: PackedScene

var world_cells: WorldCells

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

func _ready() -> void:
	world_cells = get_parent()
	populate_cell()


func increase_level(ammount: int) -> void:
	current_level += ammount
	#spawn_tree(get_hex_radius(), get_mesh_node(), ammount*2)
	populate_cell()


func populate_cell() -> void:
	var water_mesh: Node3D = get_node_or_null("WaterShader") as Node3D
	var grass_mesh: Node3D = get_node_or_null("GrassShader") as Node3D
	var river_mesh: Node3D = get_node_or_null("RiverShader") as Node3D
	if water_mesh == null or grass_mesh == null or river_mesh == null:
		return

	water_mesh.visible = cell_type == "water"
	grass_mesh.visible = cell_type == "forest" or cell_type == "river"
	river_mesh.visible = cell_type == "river"

	if cell_type != "forest" or tree_meshes.is_empty():
		return

	var children_to_remove: Array[Node] = []
	for child: Node in get_children().filter(func(x: Node) -> bool: return x is not Area3D):
		if child != water_mesh and child != grass_mesh and child != river_mesh:
			children_to_remove.append(child)

	for child in children_to_remove:
		child.queue_free()

	var hex_radius: float = 1.0
	var spawn_count: int = mini(max_trees_per_cell, maxi(1, int(current_level * trees_per_level)))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var tree_mesh_data: Array[Dictionary] = []
	for tree_index: int in range(tree_meshes.size()):
		var tree_scene: PackedScene = tree_meshes[tree_index]
		var tree_root: Node3D = tree_scene.instantiate() as Node3D
		if tree_root == null:
			continue

		_collect_tree_mesh_data(tree_root, Transform3D.IDENTITY, tree_index, tree_mesh_data)
		tree_root.free()

	if tree_mesh_data.is_empty():
		return

	var multimeshes: Array[MultiMesh] = []
	for tree_data: Dictionary in tree_mesh_data:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = tree_data["mesh"]
		multimesh.instance_count = spawn_count

		var multimesh_instance := MultiMeshInstance3D.new()
		multimesh_instance.multimesh = multimesh
		multimesh_instance.visibility_range_end = tree_visibility_distance
		add_child(multimesh_instance)
		multimeshes.append(multimesh)

	for _index in range(spawn_count):
		var spawn_position: Vector2 = _get_random_point_in_hex(hex_radius, rng)
		var rng_index: int = rng.rand_weighted([.7, .2, .1])
		if rng_index >= multimeshes.size():
			rng_index = 0

		var tree_scale: float = 1.0 + randf_range(0.0, rng_index)
		var tree_transform := Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * tree_scale),
			Vector3(spawn_position.x, 0.05, spawn_position.y)
		)
		for mesh_index: int in range(tree_mesh_data.size()):
			if tree_mesh_data[mesh_index]["tree_index"] == rng_index:
				var base_transform: Transform3D = tree_mesh_data[mesh_index]["transform"]
				multimeshes[mesh_index].set_instance_transform(_index, tree_transform * base_transform)


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


func _get_random_point_in_hex(radius: float, rng: RandomNumberGenerator) -> Vector2:
	for _attempt in range(50):
		var angle: float = rng.randf_range(0.0, TAU)
		var distance: float = rng.randf_range(0.0, radius)
		var point: Vector2 = Vector2(cos(angle) * distance, sin(angle) * distance)

		if _is_point_in_hexagon(point, radius):
			return point

	return Vector2.ZERO


func _is_point_in_hexagon(point: Vector2, radius: float) -> bool:
	var vertices: Array[Vector2] = []
	for index in range(6):
		var angle: float = deg_to_rad(index * 60.0)
		vertices.append(Vector2(cos(angle) * radius, sin(angle) * radius))

	for index in range(6):
		var p1: Vector2 = vertices[index]
		var p2: Vector2 = vertices[(index + 1) % 6]
		var cross: float = (p2 - p1).cross(point - p1)
		if cross < 0.0:
			return false

	return true
