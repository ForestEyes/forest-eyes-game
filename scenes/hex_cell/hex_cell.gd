class_name HexCell
extends Node3D

@export_enum("forest", "water") var cell_type: String = "forest"

@export var tree_meshes: Array[PackedScene]


var current_level: int = 100

func _ready() -> void:
    populate_cell()

func populate_cell() -> void:
    if cell_type != "forest":
        return

    var mesh_node: MeshInstance3D = get_node_or_null("HexCellMesh") as MeshInstance3D
    if mesh_node == null:
        return

    if tree_meshes.is_empty():
        return

    var children_to_remove: Array[Node] = []
    for child in get_children():
        if child != mesh_node:
            children_to_remove.append(child)

    for child in children_to_remove:
        child.queue_free()

    var hex_radius: float = float(mesh_node.get("radius"))
    if hex_radius <= 0.0:
        hex_radius = 1.0

    var spawn_count: int = max(1, current_level * 2)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.randomize()

    for _index in range(spawn_count):
        var spawn_position: Vector2 = _get_random_point_in_hex(hex_radius, rng)
        var tree_scene: PackedScene = tree_meshes[rng.randi_range(0, tree_meshes.size() - 1)]
        var tree_instance: Node3D = tree_scene.instantiate()

        var mesh_height: float = 0.5
        if mesh_node.has_method("get") and mesh_node.get("height") != null:
            mesh_height = float(mesh_node.get("height"))

        tree_instance.position = Vector3(spawn_position.x, mesh_height * 0.5 + 0.05, spawn_position.y)
        tree_instance.rotation.y = rng.randf_range(0.0, TAU)
        add_child(tree_instance)


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
        var angle: float = deg_to_rad(float(index) * 60.0)
        vertices.append(Vector2(cos(angle) * radius, sin(angle) * radius))

    for index in range(6):
        var p1: Vector2 = vertices[index]
        var p2: Vector2 = vertices[(index + 1) % 6]
        var cross: float = (p2 - p1).cross(point - p1)
        if cross < 0.0:
            return false

    return true
