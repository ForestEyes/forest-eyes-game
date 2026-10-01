class_name TerrainGenerator
extends RefCounted

## Decides the base terrain type ("forest" vs "water") for every cell of the
## island: the outer border plus a noisy coastline of bays, and a weighted
## random starting level for forest cells.

var width: int
var height: int
var water_border_distance: int
var coastline_bay_depth: int
var coastline_bay_frequency: float
var seed_value: int


func _init(
	p_width: int,
	p_height: int,
	p_water_border_distance: int,
	p_coastline_bay_depth: int,
	p_coastline_bay_frequency: float,
	p_seed_value: int
) -> void:
	width = p_width
	height = p_height
	water_border_distance = p_water_border_distance
	coastline_bay_depth = p_coastline_bay_depth
	coastline_bay_frequency = p_coastline_bay_frequency
	seed_value = p_seed_value


func generate_weighted_cell_level(rng: RandomNumberGenerator) -> int:
	var bucket_roll := rng.randi_range(1, 11)
	if bucket_roll <= 5:
		return 0
	if bucket_roll <= 8:
		return rng.randi_range(1, 5)
	if bucket_roll <= 10:
		return rng.randi_range(6, 10)
	return rng.randi_range(11, 15)


## Assigns "water" or "forest" to every cell and repopulates its visuals.
func assign_base_terrain(cells: Dictionary) -> void:
	for coordinate: Vector2i in cells:
		var cell: HexCell = cells[coordinate]
		cell.cell_type = "water" if is_water_border(coordinate) else "forest"
		cell.populate_cell()


func is_water_border(coordinate: Vector2i) -> bool:
	var distance_from_border: int = mini(
		mini(coordinate.x, width - 1 - coordinate.x),
		mini(coordinate.y, height - 1 - coordinate.y)
	)
	if distance_from_border <= water_border_distance:
		return true

	var side_distances: Array[int] = [
		coordinate.x,
		width - 1 - coordinate.x,
		coordinate.y,
		height - 1 - coordinate.y
	]
	for side: int in range(side_distances.size()):
		var bay_depth := _get_coastline_bay_depth(_get_coastline_coordinate(coordinate, side), side)
		if side_distances[side] <= water_border_distance + bay_depth:
			return true

	return false


func _get_coastline_coordinate(coordinate: Vector2i, side: int) -> int:
	if side < 2:
		return coordinate.y
	return coordinate.x


func _get_coastline_bay_depth(along: int, side: int) -> int:
	if coastline_bay_depth == 0:
		return 0

	var seed_offset := float((seed_value % 1000) + side * 173)
	var wave_position := float(along) * coastline_bay_frequency + seed_offset * 0.01
	var wave := (sin(wave_position) + sin(wave_position * 0.47 + 1.8)) * 0.5
	if wave <= 0.25:
		return 0

	var normalized_depth := clampf((wave - 0.25) / 0.75, 0.0, 1.0)
	var depth_variation := _get_coastline_depth_variation(along, side)
	var varied_bay_depth: int = maxi(0, coastline_bay_depth + depth_variation)
	return roundi(normalized_depth * varied_bay_depth)


func _get_coastline_depth_variation(along: int, side: int) -> int:
	var segment := floori(float(along) / 4.0)
	var random_value := sin(
		segment * 12.9898 + float(side) * 78.233 + float(seed_value % 10000) * 0.017
	) * 43758.5453
	var normalized_value := random_value - floorf(random_value)
	return roundi(normalized_value * 4.0 - 2.0)
