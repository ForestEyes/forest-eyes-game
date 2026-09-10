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
	if current_level == MAX_LEVEL:
		return
	current_level = clamp(current_level + ammount, 0, 15)
	populate_cell()
	if world_cells != null:
		world_cells.rebuild_tree_batches()


func get_tree_count() -> int:
	return mini(max_trees_per_cell, maxi(0, int(current_level * trees_per_level)))


func populate_cell() -> void:
	var water_mesh: Node3D = get_node_or_null("WaterShader") as Node3D
	var grass_mesh: Node3D = get_node_or_null("GrassShader") as Node3D
	var river_mesh: Node3D = get_node_or_null("RiverShader") as Node3D
	if water_mesh == null or grass_mesh == null or river_mesh == null:
		return

	water_mesh.visible = cell_type == "water"
	grass_mesh.visible = cell_type == "forest" or cell_type == "river"
	river_mesh.visible = cell_type == "river"
