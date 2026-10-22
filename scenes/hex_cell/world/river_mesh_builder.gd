class_name RiverMeshBuilder
extends RefCounted

## Turns ordered river chains (see [RiverGenerator]) into smooth curves and
## per-cell water meshes, owning the mesh nodes until [method clear] is called.

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

var _river_mesh_instances: Array[MeshInstance3D] = []
var _river_mesh_cells: Array[HexCell] = []


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
	for mesh_node: MeshInstance3D in _river_mesh_instances:
		if is_instance_valid(mesh_node):
			mesh_node.free()
	_river_mesh_instances.clear()
	_river_mesh_cells.clear()


func update_exploration_visibility() -> void:
	for index in range(_river_mesh_instances.size()):
		var cell: HexCell = _river_mesh_cells[index]
		_river_mesh_instances[index].visible = is_instance_valid(cell) and cell.is_explored


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
	var river_meshes := _create_river_meshes(
		baked_points,
		chain,
		river_source_lake_length,
		river_seed,
		scaled_base_width
	)
	for coordinate: Vector2i in river_meshes:
		var cell: HexCell = cells.get(coordinate) as HexCell
		if cell == null:
			continue

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "RiverMeshInstance_%d_%d" % [coordinate.x, coordinate.y]
		mesh_instance.mesh = river_meshes[coordinate]
		mesh_instance.visible = cell.is_explored
		if river_material != null:
			mesh_instance.material_override = river_material
		elif river_shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = river_shader
			mesh_instance.material_override = mat
		_host.add_child(mesh_instance)
		_river_mesh_instances.append(mesh_instance)
		_river_mesh_cells.append(cell)


func _create_river_meshes(
	baked_points: PackedVector3Array,
	chain: Array[Vector2i],
	source_lake_length: float,
	river_seed: int = 0,
	base_river_width: float = -1.0
) -> Dictionary[Vector2i, ArrayMesh]:
	var surface_tools: Dictionary[Vector2i, SurfaceTool] = {}

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
			"center": center_pt,
			"v": cumulative_distance
		})

	for k in range(rows.size() - 1):
		var r1: Dictionary = rows[k]
		var r2: Dictionary = rows[k + 1]
		var segment_center: Vector3 = (r1.center + r2.center) * 0.5
		var nearest_coordinate := _get_nearest_cell_coordinate(segment_center, chain)
		var segment_coordinates: Array[Vector2i] = [nearest_coordinate]
		for neighbor: Vector2i in HexGrid.get_all_neighbors(nearest_coordinate).values():
			if chain.has(neighbor):
				segment_coordinates.append(neighbor)

		var norm_left: Vector3 = (r1.tl - r1.tr).normalized()
		norm_left.y = 0.0
		norm_left = norm_left.normalized()
		var norm_right: Vector3 = (r1.tr - r1.tl).normalized()
		norm_right.y = 0.0
		norm_right = norm_right.normalized()
		for coordinate: Vector2i in segment_coordinates:
			var st: SurfaceTool = surface_tools.get(coordinate) as SurfaceTool
			var is_new_surface_tool: bool = st == null
			if st == null:
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)

			var added_geometry := _append_clipped_triangle(
				st, coordinate, r1.tl, r2.tr, r1.tr, Vector3.UP,
				Vector2(0.0, r1.v), Vector2(1.0, r2.v), Vector2(1.0, r1.v)
			)
			added_geometry = _append_clipped_triangle(
				st, coordinate, r1.tl, r2.tl, r2.tr, Vector3.UP,
				Vector2(0.0, r1.v), Vector2(0.0, r2.v), Vector2(1.0, r2.v)
			) or added_geometry

			added_geometry = _append_clipped_triangle(st, coordinate, r1.bl, r1.tl, r2.tl, norm_left) or added_geometry
			added_geometry = _append_clipped_triangle(st, coordinate, r1.bl, r2.tl, r2.bl, norm_left) or added_geometry
			added_geometry = _append_clipped_triangle(st, coordinate, r1.tr, r1.br, r2.br, norm_right) or added_geometry
			added_geometry = _append_clipped_triangle(st, coordinate, r1.tr, r2.br, r2.tr, norm_right) or added_geometry
			if is_new_surface_tool and added_geometry:
				surface_tools[coordinate] = st

	var meshes: Dictionary[Vector2i, ArrayMesh] = {}
	for coordinate: Vector2i in surface_tools:
		meshes[coordinate] = surface_tools[coordinate].commit()
	return meshes


func _append_clipped_triangle(
	surface_tool: SurfaceTool,
	coordinate: Vector2i,
	point_a: Vector3,
	point_b: Vector3,
	point_c: Vector3,
	normal: Vector3,
	uv_a: Vector2 = Vector2.ZERO,
	uv_b: Vector2 = Vector2.ZERO,
	uv_c: Vector2 = Vector2.ZERO
) -> bool:
	var polygon: Array[Dictionary] = [
		{"position": point_a, "normal": normal, "uv": uv_a},
		{"position": point_b, "normal": normal, "uv": uv_b},
		{"position": point_c, "normal": normal, "uv": uv_c},
	]
	polygon = _clip_polygon_to_cell(polygon, coordinate)
	if polygon.size() < 3:
		return false

	for index in range(1, polygon.size() - 1):
		for vertex: Dictionary in [polygon[0], polygon[index], polygon[index + 1]]:
			surface_tool.set_normal(vertex.normal)
			surface_tool.set_uv(vertex.uv)
			surface_tool.add_vertex(vertex.position)
	return true


func _clip_polygon_to_cell(polygon: Array[Dictionary], coordinate: Vector2i) -> Array[Dictionary]:
	var cell_position: Vector3 = _get_cell_position(coordinate)
	var cell_center := Vector2(cell_position.x, cell_position.z)
	for corner_index in range(6):
		if polygon.is_empty():
			break

		var edge_start: Vector2 = cell_center + HexGrid.corner_point_2d(corner_index)
		var edge_end: Vector2 = cell_center + HexGrid.corner_point_2d((corner_index + 1) % 6)
		var edge := edge_end - edge_start
		var clipped_polygon: Array[Dictionary] = []
		var previous: Dictionary = polygon.back()
		var previous_position: Vector3 = previous.position
		var previous_distance: float = edge.cross(
			Vector2(previous_position.x, previous_position.z) - edge_start
		)

		for current: Dictionary in polygon:
			var current_position: Vector3 = current.position
			var current_distance: float = edge.cross(
				Vector2(current_position.x, current_position.z) - edge_start
			)
			var previous_inside: bool = previous_distance >= -0.00001
			var current_inside: bool = current_distance >= -0.00001
			if previous_inside != current_inside:
				var intersection_ratio: float = previous_distance / (previous_distance - current_distance)
				clipped_polygon.append(_interpolate_river_vertex(previous, current, intersection_ratio))
			if current_inside:
				clipped_polygon.append(current)

			previous = current
			previous_position = current_position
			previous_distance = current_distance

		polygon = clipped_polygon
	return polygon


func _interpolate_river_vertex(a: Dictionary, b: Dictionary, amount: float) -> Dictionary:
	var normal: Vector3 = a.normal.lerp(b.normal, amount).normalized()
	return {
		"position": a.position.lerp(b.position, amount),
		"normal": normal,
		"uv": a.uv.lerp(b.uv, amount),
	}


func _get_nearest_cell_coordinate(position: Vector3, chain: Array[Vector2i]) -> Vector2i:
	var nearest_coordinate: Vector2i = chain[0]
	var nearest_distance_squared: float = INF
	var position_2d := Vector2(position.x, position.z)
	for coordinate: Vector2i in chain:
		var cell_position: Vector3 = _get_cell_position(coordinate)
		var distance_squared: float = position_2d.distance_squared_to(Vector2(cell_position.x, cell_position.z))
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_coordinate = coordinate
	return nearest_coordinate
