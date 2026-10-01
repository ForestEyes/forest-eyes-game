class_name RiverGenerator
extends RefCounted

## Carves river cells across the island grid (from an inland source out to the
## coast) and later traces the resulting cells back into ordered chains that
## [RiverMeshBuilder] can turn into curves and meshes.

var width: int
var height: int
var water_border_distance: int
var terrain: TerrainGenerator


func _init(p_width: int, p_height: int, p_water_border_distance: int, p_terrain: TerrainGenerator) -> void:
	width = p_width
	height = p_height
	water_border_distance = p_water_border_distance
	terrain = p_terrain


## Picks river sources and carves their paths to the coast, then cleans up
## any river tiles that ended up overwhelmed by water/other rivers.
func carve_rivers(cells: Dictionary, rng: RandomNumberGenerator) -> void:
	var river_count: int = maxi(1, roundi(float(width * height) / 350.0))
	var river_sources: Array[Vector2i] = []
	for river_index in range(river_count):
		var source := _get_river_source(cells, rng, river_sources)
		river_sources.append(source)
		_generate_river_path(cells, source, river_index % 4, rng)

	_convert_overwhelmed_rivers_to_water(cells)


func _generate_river_path(cells: Dictionary, start: Vector2i, target_side: int, rng: RandomNumberGenerator) -> void:
	var current := start
	var previous_direction := Vector2i.ZERO
	var visited: Dictionary[Vector2i, bool] = {}
	var max_steps: int = maxi(1, width + height)

	for _step in range(max_steps):
		if terrain.is_water_border(current):
			_expand_river_mouth_coast(cells, current, rng)
			return

		var cell: HexCell = cells.get(current) as HexCell
		if cell == null:
			return
		cell.cell_type = "river"
		visited[current] = true

		# Se atingiu a zona costeira / encontrou oceano próximo
		var reached_coast := _get_distance_to_target_side(current, target_side) <= water_border_distance + 1
		if not reached_coast:
			for neighbor_coord: Vector2i in HexGrid.get_all_neighbors(current).values():
				if cells.has(neighbor_coord) and (cells[neighbor_coord].cell_type == "water" or terrain.is_water_border(neighbor_coord)):
					reached_coast = true
					break

		if reached_coast:
			# Itera para o lado entre 1 a 3 vezes ao longo da costa antes de terminar
			var coast_steps := rng.randi_range(1, 3)
			var coast_current := current
			var coast_prev_dir := previous_direction

			for _side_step in range(coast_steps):
				var next_side := _get_next_coast_river_coordinate(cells, coast_current, visited, coast_prev_dir, rng)
				if next_side == coast_current:
					break
				var next_side_cell: HexCell = cells.get(next_side) as HexCell
				if next_side_cell != null:
					next_side_cell.cell_type = "river"
				visited[next_side] = true
				coast_prev_dir = next_side - coast_current
				coast_current = next_side

			# Transforma os tiles ao redor da foz em tiles de água
			_expand_river_mouth_coast(cells, coast_current, rng)
			return

		var next_coordinate := _get_next_river_coordinate(
			cells,
			current,
			target_side,
			previous_direction,
			visited,
			rng
		)
		if next_coordinate == current:
			_expand_river_mouth_coast(cells, current, rng)
			return
		previous_direction = next_coordinate - current
		current = next_coordinate


func _get_next_coast_river_coordinate(
	cells: Dictionary,
	coordinate: Vector2i,
	visited: Dictionary[Vector2i, bool],
	previous_direction: Vector2i,
	rng: RandomNumberGenerator
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for candidate: Vector2i in HexGrid.get_all_neighbors(coordinate).values():
		if not cells.has(candidate) or visited.has(candidate):
			continue
		if (cells[candidate] as HexCell).cell_type == "water" or terrain.is_water_border(candidate):
			continue
		candidates.append(candidate)

	if candidates.is_empty():
		return coordinate

	# Prefere vizinhos perpendiculares ou com curvatura suave em relação à direção anterior
	var best_candidate: Vector2i = candidates[0]
	var best_score: float = INF
	for candidate: Vector2i in candidates:
		var score: float = rng.randf_range(0.0, 1.0)
		if previous_direction != Vector2i.ZERO:
			var dir := Vector2(candidate - coordinate).normalized()
			var prev := Vector2(previous_direction).normalized()
			score += absf(dir.dot(prev))
		if score < best_score:
			best_score = score
			best_candidate = candidate

	return best_candidate


func _expand_river_mouth_coast(cells: Dictionary, mouth_coord: Vector2i, rng: RandomNumberGenerator) -> void:
	var neighbor_offsets: Dictionary[HexGrid.Direction, Vector2i] = HexGrid.get_neighbor_offsets(mouth_coord.x)
	for neighbor_offset: Vector2i in neighbor_offsets.values():
		var neighbor: Vector2i = mouth_coord + neighbor_offset
		if cells.has(neighbor):
			var neighbor_cell: HexCell = cells[neighbor]
			# Transforma tiles adjacentes que não sejam rio em água (criando a abertura da baía/foz)
			if neighbor_cell.cell_type != "river":
				neighbor_cell.cell_type = "water"

	# Pequena chance de expandir mais um tile para formar uma foz/baía ainda mais ampla
	for neighbor_offset: Vector2i in neighbor_offsets.values():
		if rng.randf() < 0.5:
			var second_tier: Vector2i = mouth_coord + neighbor_offset * 2
			if cells.has(second_tier) and (cells[second_tier] as HexCell).cell_type != "river":
				(cells[second_tier] as HexCell).cell_type = "water"


func _get_river_source(cells: Dictionary, rng: RandomNumberGenerator, existing_sources: Array[Vector2i]) -> Vector2i:
	var center := Vector2((width - 1) * 0.5, (height - 1) * 0.5)
	var source_radius := Vector2(
		maxf(1.0, (width - water_border_distance * 2) * 0.2),
		maxf(1.0, (height - water_border_distance * 2) * 0.2)
	)
	var minimum_spacing := maxf(2.0, mini(width, height) * 0.12)
	var best_source := Vector2i(roundi(center.x), roundi(center.y))
	var best_score := -INF

	for _attempt in range(40):
		var candidate := Vector2i(
			clampi(roundi(center.x + rng.randf_range(-source_radius.x, source_radius.x)), 0, width - 1),
			clampi(roundi(center.y + rng.randf_range(-source_radius.y, source_radius.y)), 0, height - 1)
		)
		if terrain.is_water_border(candidate):
			continue
		if (cells[candidate] as HexCell).cell_type != "forest":
			continue

		var spacing_score := INF
		for existing_source: Vector2i in existing_sources:
			spacing_score = minf(spacing_score, Vector2(candidate).distance_to(Vector2(existing_source)))
		if existing_sources.is_empty():
			spacing_score = source_radius.length()
		if spacing_score < minimum_spacing and best_score >= minimum_spacing:
			continue
		if spacing_score > best_score:
			best_score = spacing_score
			best_source = candidate

	return best_source


func _get_next_river_coordinate(
	cells: Dictionary,
	coordinate: Vector2i,
	target_side: int,
	previous_direction: Vector2i,
	visited: Dictionary[Vector2i, bool],
	rng: RandomNumberGenerator
) -> Vector2i:
	var best_coordinate := coordinate
	var best_score := INF
	for candidate: Vector2i in HexGrid.get_all_neighbors(coordinate).values():
		if not cells.has(candidate) or terrain.is_water_border(candidate) or visited.has(candidate):
			continue

		var distance_to_edge: float
		match target_side:
			0:
				distance_to_edge = candidate.x
			1:
				distance_to_edge = width - 1 - candidate.x
			2:
				distance_to_edge = candidate.y
			_:
				distance_to_edge = height - 1 - candidate.y

		var score: float = distance_to_edge * 0.65 + rng.randf_range(0.0, 1.2)
		if previous_direction != Vector2i.ZERO:
			var direction := Vector2(candidate - coordinate).normalized()
			var last_direction := Vector2(previous_direction).normalized()
			var direction_change := 1.0 - direction.dot(last_direction)
			score += direction_change * 0.1
		if (cells[candidate] as HexCell).cell_type == "river":
			score += 3.0
		if score < best_score:
			best_score = score
			best_coordinate = candidate

	return best_coordinate


func _get_distance_to_target_side(coordinate: Vector2i, target_side: int) -> int:
	match target_side:
		0:
			return coordinate.x
		1:
			return width - 1 - coordinate.x
		2:
			return coordinate.y
		_:
			return height - 1 - coordinate.y


func _convert_overwhelmed_rivers_to_water(cells: Dictionary) -> void:
	var has_converted_cells := true
	while has_converted_cells:
		has_converted_cells = false
		var cells_to_convert: Array[HexCell] = []
		for coordinate: Vector2i in cells:
			var cell: HexCell = cells[coordinate]
			if cell.cell_type != "river":
				continue

			var river_neighbors := 0
			var water_neighbors := 0
			for neighbor_offset: Vector2i in HexGrid.get_neighbor_offsets(coordinate.x).values():
				var neighboring_cell: HexCell = cells.get(coordinate + neighbor_offset) as HexCell
				if neighboring_cell == null:
					continue
				if neighboring_cell.cell_type == "river":
					river_neighbors += 1
				elif neighboring_cell.cell_type == "water":
					water_neighbors += 1

			if river_neighbors >= 3 or water_neighbors >= 2:
				cells_to_convert.append(cell)

		for cell: HexCell in cells_to_convert:
			cell.cell_type = "water"
			has_converted_cells = true


## Groups every cell currently marked as "river" into ordered chains, each
## running from an endpoint (source or mouth) to the next. Used to build the
## river curves/meshes.
func trace_river_chains(cells: Dictionary) -> Array[Array]:
	var river_cells: Dictionary[Vector2i, bool] = {}
	for coordinate: Vector2i in cells:
		if cells[coordinate].cell_type == "river":
			river_cells[coordinate] = true

	if river_cells.is_empty():
		return []

	var visited: Dictionary[Vector2i, bool] = {}
	var endpoints: Array[Vector2i] = []
	for coord: Vector2i in river_cells:
		var river_neighbors := 0
		for offset: Vector2i in HexGrid.get_neighbor_offsets(coord.x).values():
			if river_cells.has(coord + offset):
				river_neighbors += 1
		if river_neighbors <= 1:
			endpoints.append(coord)

	# Ordena os endpoints para que as nascentes (com menos vizinhos de água) comecem primeiro
	endpoints.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var water_a := 0
		var water_b := 0
		for offset: Vector2i in HexGrid.get_neighbor_offsets(a.x).values():
			var n: Vector2i = a + offset
			if cells.has(n) and cells[n].cell_type == "water":
				water_a += 1
		for offset: Vector2i in HexGrid.get_neighbor_offsets(b.x).values():
			var n: Vector2i = b + offset
			if cells.has(n) and cells[n].cell_type == "water":
				water_b += 1
		return water_a < water_b
	)

	var river_chains: Array[Array] = []
	for ep: Vector2i in endpoints:
		if visited.has(ep):
			continue
		river_chains.append(_trace_chain_from(river_cells, visited, ep))

	# Fallback para ciclos fechados isolados (caso existam)
	for coord: Vector2i in river_cells:
		if visited.has(coord):
			continue
		river_chains.append(_trace_chain_from(river_cells, visited, coord))

	return river_chains


func _trace_chain_from(river_cells: Dictionary[Vector2i, bool], visited: Dictionary[Vector2i, bool], start: Vector2i) -> Array[Vector2i]:
	var chain: Array[Vector2i] = [start]
	visited[start] = true
	var current := start
	while true:
		var next_coord := Vector2i(-1, -1)
		for offset: Vector2i in HexGrid.get_neighbor_offsets(current.x).values():
			var candidate: Vector2i = current + offset
			if river_cells.has(candidate) and not visited.has(candidate):
				next_coord = candidate
				break
		if next_coord == Vector2i(-1, -1):
			break
		visited[next_coord] = true
		chain.append(next_coord)
		current = next_coord
	return chain
