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

func populate_cell() -> void:
	var water_mesh: Node3D = get_node_or_null("WaterShader") as Node3D
	var grass_mesh: Node3D = get_node_or_null("GrassShader") as Node3D
	var river_mesh: Node3D = get_node_or_null("RiverShader") as Node3D
	if water_mesh == null or grass_mesh == null or river_mesh == null:
		return

	water_mesh.visible = cell_type == "water"
	grass_mesh.visible = cell_type == "forest" or cell_type == "river"
	river_mesh.visible = cell_type == "river"


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
