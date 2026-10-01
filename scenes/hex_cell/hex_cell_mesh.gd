@tool
extends MeshInstance3D

@export var radius: float = 1.0
@export var height: float = 0.5


func _ready() -> void:
	_update_mesh()

func _update_mesh() -> void:
	mesh = create_hexagon_mesh(radius, height)

func create_hexagon_mesh(r: float, h: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_h: float = h / 2.0
	var top_center: Vector3 = Vector3(0.0, half_h, 0.0)
	var bot_center: Vector3 = Vector3(0.0, -half_h, 0.0)

	for i: int in range(6):
		var next_i: int = (i + 1) % 6
		var top1: Vector3 = HexGrid.corner_point_3d(i, r, half_h)
		var top2: Vector3 = HexGrid.corner_point_3d(next_i, r, half_h)
		var bot1: Vector3 = HexGrid.corner_point_3d(i, r, -half_h)
		var bot2: Vector3 = HexGrid.corner_point_3d(next_i, r, -half_h)

		st.add_vertex(top_center)
		st.add_vertex(top1)
		st.add_vertex(top2)

		st.add_vertex(bot_center)
		st.add_vertex(bot2)
		st.add_vertex(bot1)

		st.add_vertex(bot1)
		st.add_vertex(top2)
		st.add_vertex(top1)

		st.add_vertex(bot1)
		st.add_vertex(bot2)
		st.add_vertex(top2)

	st.generate_normals()
	return st.commit()