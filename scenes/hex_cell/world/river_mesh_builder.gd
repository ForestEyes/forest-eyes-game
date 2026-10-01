class_name RiverMeshBuilder
extends RefCounted

## Turns ordered river chains (see [RiverGenerator]) into smooth [Curve3D]
## paths and flowing water meshes, owning the Path3D/MeshInstance3D nodes it
## creates until [method clear] is called.

var _host: Node3D
var _horizontal_spacing: float
var _vertical_spacing: float
var _seed_value: int

## Visual tuning, assigned by WorldCells after construction (mirrors its exported fields).
var river_width: float = 0.45
var river_max_width: float = 0.9
var river_min_points_for_scaling: int = 4
var river_max_points_for_scaling: int = 25
var river_source_lake_width: float = 1.1
var river_source_lake_length: float = 1.0
var river_width_variation: float = 0.35
var river_position_noise: float = 0.12
var river_noise_frequency: float = 1.5
var river_height_offset: float = 0.01
var river_curve_bake_interval: float = 0.1
var river_shader: Shader
var river_material: Material

var _river_paths: Array[Path3D] = []
var _river_mesh_instances: Array[MeshInstance3D] = []


func _init(host: Node3D, horizontal_spacing: float, vertical_spacing: float, seed_value: int) -> void:
	_host = host
	_horizontal_spacing = horizontal_spacing
	_vertical_spacing = vertical_spacing
	_seed_value = seed_value


func _get_cell_position(coordinate: Vector2i) -> Vector3:
	return HexGrid.offset_to_world(coordinate, _horizontal_spacing, _vertical_spacing)


## Rebuilds every river mesh from the given chains, replacing any previous ones.
func rebuild(cells: Dictionary, chains: Array[Array]) -> void:
	clear()
	for chain: Array in chains:
		var typed_chain: Array[Vector2i] = []
		typed_chain.assign(chain)
		_build_river_for_chain(cells, typed_chain)


func clear() -> void:
	for path_node: Path3D in _river_paths:
		if is_instance_valid(path_node):
			path_node.free()
	_river_paths.clear()

	for mesh_node: MeshInstance3D in _river_mesh_instances:
		if is_instance_valid(mesh_node):
			mesh_node.free()
	_river_mesh_instances.clear()


func _build_river_for_chain(cells: Dictionary, chain: Array[Vector2i]) -> void:
	if chain.is_empty():
		return

	var tile_top_y: float = 0.25 + river_height_offset
	var path_points: Array[Vector3] = []

	for i in range(chain.size()):
		var coord: Vector2i = chain[i]
		var cell_pos: Vector3 = _get_cell_position(coord)
		cell_pos.y = tile_top_y

		var is_first: bool = (i == 0)
		var is_last: bool = (i == chain.size() - 1)

		if is_first:
			# Tile de nascente: 2 pontos (meio e saída para o próximo tile)
			path_points.append(cell_pos)
			if chain.size() > 1:
				var next_cell_pos: Vector3 = _get_cell_position(chain[i + 1])
				next_cell_pos.y = tile_top_y
				path_points.append((cell_pos + next_cell_pos) * 0.5)
		elif not is_last:
			# Tile intermediário: 3 pontos (entrada, meio, saída)
			# O ponto de entrada já foi adicionado como a saída do tile anterior na borda compartilhada
			path_points.append(cell_pos)
			var next_cell_pos: Vector3 = _get_cell_position(chain[i + 1])
			next_cell_pos.y = tile_top_y
			path_points.append((cell_pos + next_cell_pos) * 0.5)
		else:
			# Último tile: centro do tile e ponto de saída na foz (em direção ao vizinho de água)
			path_points.append(cell_pos)
			var water_coord := Vector2i(-1, -1)
			for offset: Vector2i in HexGrid.get_neighbor_offsets(coord.x).values():
				var candidate: Vector2i = coord + offset
				if cells.has(candidate) and cells[candidate].cell_type == "water":
					water_coord = candidate
					break
			if water_coord != Vector2i(-1, -1):
				var water_pos: Vector3 = _get_cell_position(water_coord)
				water_pos.y = tile_top_y
				path_points.append((cell_pos + water_pos) * 0.5)

	if path_points.size() < 2:
		return

	# Criar Curve3D com tangentes (spline suave)
	var curve := Curve3D.new()
	var tension: float = 0.25
	for j in range(path_points.size()):
		var p: Vector3 = path_points[j]
		var handle_in := Vector3.ZERO
		var handle_out := Vector3.ZERO
		if j > 0 and j < path_points.size() - 1:
			var dir: Vector3 = (path_points[j + 1] - path_points[j - 1]).normalized()
			var dist_prev: float = p.distance_to(path_points[j - 1])
			var dist_next: float = p.distance_to(path_points[j + 1])
			handle_in = - dir * dist_prev * tension
			handle_out = dir * dist_next * tension
		elif j == 0:
			handle_out = (path_points[1] - path_points[0]) * tension
		else:
			handle_in = - (path_points[j] - path_points[j - 1]) * tension
		curve.add_point(p, handle_in, handle_out)

	curve.bake_interval = river_curve_bake_interval

	# Criar nó Path3D
	var path_node := Path3D.new()
	path_node.name = "RiverPath_%d_%d" % [chain[0].x, chain[0].y]
	path_node.curve = curve
	_host.add_child(path_node)
	_river_paths.append(path_node)

	# Gerar Mesh 3D a partir dos pontos assados da curva
	var baked_points: PackedVector3Array = curve.get_baked_points()
	if baked_points.size() < 2:
		return

	# Escalonar a largura base conforme a quantidade de pontos do rio
	var points_ratio: float = 0.0
	if river_max_points_for_scaling > river_min_points_for_scaling:
		points_ratio = clampf(
			float(path_points.size() - river_min_points_for_scaling) / float(river_max_points_for_scaling - river_min_points_for_scaling),
			0.0,
			1.0
		)
	var scaled_base_width: float = lerpf(river_width, river_max_width, points_ratio)

	var river_seed: int = absi(chain[0].x * 73856093 ^ chain[0].y * 19349663 ^ _seed_value)
	var river_mesh: ArrayMesh = _create_river_mesh(baked_points, river_source_lake_length, river_seed, scaled_base_width)
	if river_mesh == null:
		return

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RiverMeshInstance"
	mesh_instance.mesh = river_mesh
	if river_material != null:
		mesh_instance.material_override = river_material
	elif river_shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = river_shader
		mesh_instance.material_override = mat
	path_node.add_child(mesh_instance)
	_river_mesh_instances.append(mesh_instance)


func _create_river_mesh(baked_points: PackedVector3Array, source_lake_length: float, river_seed: int = 0, base_river_width: float = -1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var count: int = baked_points.size()
	var river_depth: float = 0.02
	var transition_distance: float = maxf(0.2, source_lake_length)
	var active_base_width: float = river_width if base_river_width <= 0.0 else base_river_width

	# Calcular comprimento total do rio
	var total_length: float = 0.0
	for k in range(1, count):
		total_length += baked_points[k].distance_to(baked_points[k - 1])

	# Pré-computar rows com larguras e coordenadas ao longo do rio
	var rows: Array[Dictionary] = []
	var cumulative_distance: float = 0.0
	var seed_offset: float = float(river_seed % 10000)

	for k in range(count):
		var pt: Vector3 = baked_points[k]
		if k > 0:
			cumulative_distance += pt.distance_to(baked_points[k - 1])

		var forward: Vector3 = Vector3.ZERO
		if k == 0:
			forward = (baked_points[1] - baked_points[0]).normalized()
		elif k == count - 1:
			forward = (baked_points[k] - baked_points[k - 1]).normalized()
		else:
			forward = (baked_points[k + 1] - baked_points[k - 1]).normalized()

		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		else:
			forward = forward.normalized()

		var right: Vector3 = forward.cross(Vector3.UP).normalized()

		# Ruído contínuo baseado na distância ao longo do rio
		var noise_param: float = cumulative_distance * river_noise_frequency + seed_offset
		var width_noise: float = sin(noise_param * 1.3) * 0.6 + sin(noise_param * 2.7 + 1.2) * 0.4
		var pos_noise: float = sin(noise_param * 0.9 + 2.5) * 0.7 + cos(noise_param * 2.1) * 0.3

		# Fator de atenuação nas pontas (nascente e foz) para não descolar dos hexágonos
		var edge_fade: float = 1.0
		if cumulative_distance < transition_distance:
			edge_fade = clampf(cumulative_distance / transition_distance, 0.0, 1.0)
		var dist_to_end: float = total_length - cumulative_distance
		if dist_to_end < 0.6:
			edge_fade = minf(edge_fade, clampf(dist_to_end / 0.6, 0.0, 1.0))

		# Aplicação do deslocamento horizontal (ruído na posição)
		var center_pt: Vector3 = pt + right * (pos_noise * river_position_noise * edge_fade)

		var base_width: float = active_base_width
		if cumulative_distance < transition_distance:
			var t: float = clampf(cumulative_distance / transition_distance, 0.0, 1.0)
			# Transição suave (smoothstep) da largura do pequeno lago na nascente até a largura padrão do rio
			var smooth_t: float = t * t * (3.0 - 2.0 * t)
			var lake_w: float = maxf(river_source_lake_width, active_base_width)
			base_width = lerpf(lake_w, active_base_width, smooth_t)

		# Variação randômica da largura ao longo do caminho
		var current_width: float = base_width * (1.0 + width_noise * river_width_variation * edge_fade)

		var half_w: float = current_width * 0.5
		var top_left: Vector3 = center_pt - right * half_w
		var top_right: Vector3 = center_pt + right * half_w
		var bot_left: Vector3 = top_left + Vector3(0.0, -river_depth, 0.0)
		var bot_right: Vector3 = top_right + Vector3(0.0, -river_depth, 0.0)

		rows.append({
			"tl": top_left,
			"tr": top_right,
			"bl": bot_left,
			"br": bot_right,
			"v": cumulative_distance
		})

	for k in range(rows.size() - 1):
		var r1: Dictionary = rows[k]
		var r2: Dictionary = rows[k + 1]

		# Superfície superior da água
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, r1.v))
		st.add_vertex(r1.tl)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, r2.v))
		st.add_vertex(r2.tr)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, r1.v))
		st.add_vertex(r1.tr)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, r1.v))
		st.add_vertex(r1.tl)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, r2.v))
		st.add_vertex(r2.tl)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1.0, r2.v))
		st.add_vertex(r2.tr)

		# Borda lateral esquerda
		var norm_left: Vector3 = (r1.tl - r1.tr).normalized()
		norm_left.y = 0.0
		norm_left = norm_left.normalized()

		st.set_normal(norm_left)
		st.add_vertex(r1.bl)
		st.set_normal(norm_left)
		st.add_vertex(r1.tl)
		st.set_normal(norm_left)
		st.add_vertex(r2.tl)

		st.set_normal(norm_left)
		st.add_vertex(r1.bl)
		st.set_normal(norm_left)
		st.add_vertex(r2.tl)
		st.set_normal(norm_left)
		st.add_vertex(r2.bl)

		# Borda lateral direita
		var norm_right: Vector3 = (r1.tr - r1.tl).normalized()
		norm_right.y = 0.0
		norm_right = norm_right.normalized()

		st.set_normal(norm_right)
		st.add_vertex(r1.tr)
		st.set_normal(norm_right)
		st.add_vertex(r1.br)
		st.set_normal(norm_right)
		st.add_vertex(r2.br)

		st.set_normal(norm_right)
		st.add_vertex(r1.tr)
		st.set_normal(norm_right)
		st.add_vertex(r2.br)
		st.set_normal(norm_right)
		st.add_vertex(r2.tr)

	return st.commit()
