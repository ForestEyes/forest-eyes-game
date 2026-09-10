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
	var angles: Array[float] = []
	for i: int in range(6):
		angles.append(deg_to_rad(i * 60.0))
	
	var top_center: Vector3 = Vector3(0.0, half_h, 0.0)
	for i: int in range(6):
		var next_i: int = (i + 1) % 6
		var p1: Vector3 = Vector3(r * cos(angles[i]), half_h, r * sin(angles[i]))
		var p2: Vector3 = Vector3(r * cos(angles[next_i]), half_h, r * sin(angles[next_i]))
		
		st.add_vertex(top_center)
		st.add_vertex(p1)
		st.add_vertex(p2)
		
	var bot_center: Vector3 = Vector3(0.0, -half_h, 0.0)
	for i: int in range(6):
		var next_i: int = (i + 1) % 6
		var p1: Vector3 = Vector3(r * cos(angles[i]), -half_h, r * sin(angles[i]))
		var p2: Vector3 = Vector3(r * cos(angles[next_i]), -half_h, r * sin(angles[next_i]))
		
		st.add_vertex(bot_center)
		st.add_vertex(p2)
		st.add_vertex(p1)
		
	for i: int in range(6):
		var next_i: int = (i + 1) % 6
		var top1: Vector3 = Vector3(r * cos(angles[i]), half_h, r * sin(angles[i]))
		var top2: Vector3 = Vector3(r * cos(angles[next_i]), half_h, r * sin(angles[next_i]))
		var bot1: Vector3 = Vector3(r * cos(angles[i]), -half_h, r * sin(angles[i]))
		var bot2: Vector3 = Vector3(r * cos(angles[next_i]), -half_h, r * sin(angles[next_i]))
		
		st.add_vertex(bot1)
		st.add_vertex(top2)
		st.add_vertex(top1)
		
		st.add_vertex(bot1)
		st.add_vertex(bot2)
		st.add_vertex(top2)
		
	st.generate_normals()
	return st.commit()