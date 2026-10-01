class_name HexGrid
extends RefCounted

## Flat-top hex grid math library.
##
## Based on the reference implementation from Red Blob Games:
## https://www.redblobgames.com/grids/hexagons/
##
## The project stores cells using "offset coordinates" as Vector2i(column, row),
## following the "odd-q" vertical layout: odd columns are pushed down half a
## cell so flat-top hexagons tile without gaps. This library centralizes the
## neighbor, distance and pixel-layout math so gameplay code never needs to
## hand-roll hex offsets again.

enum Direction {NORTH, NORTH_EAST, SOUTH_EAST, SOUTH, SOUTH_WEST, NORTH_WEST}

const DIRECTIONS: Array[Direction] = [
	Direction.NORTH,
	Direction.NORTH_EAST,
	Direction.SOUTH_EAST,
	Direction.SOUTH,
	Direction.SOUTH_WEST,
	Direction.NORTH_WEST,
]

const DIRECTION_NAMES: Dictionary[Direction, StringName] = {
	Direction.NORTH: &"N",
	Direction.NORTH_EAST: &"NE",
	Direction.SOUTH_EAST: &"SE",
	Direction.SOUTH: &"S",
	Direction.SOUTH_WEST: &"SW",
	Direction.NORTH_WEST: &"NW",
}

## "odd-q" neighbor offsets: which table applies depends on column parity.
const _EVEN_COLUMN_OFFSETS: Dictionary[Direction, Vector2i] = {
	Direction.NORTH: Vector2i(0, -1),
	Direction.NORTH_EAST: Vector2i(1, -1),
	Direction.NORTH_WEST: Vector2i(-1, -1),
	Direction.SOUTH: Vector2i(0, 1),
	Direction.SOUTH_EAST: Vector2i(1, 0),
	Direction.SOUTH_WEST: Vector2i(-1, 0),
}

const _ODD_COLUMN_OFFSETS: Dictionary[Direction, Vector2i] = {
	Direction.NORTH: Vector2i(0, -1),
	Direction.NORTH_EAST: Vector2i(1, 0),
	Direction.NORTH_WEST: Vector2i(-1, 0),
	Direction.SOUTH: Vector2i(0, 1),
	Direction.SOUTH_EAST: Vector2i(1, 1),
	Direction.SOUTH_WEST: Vector2i(-1, 1),
}


static func direction_name(direction: Direction) -> StringName:
	return DIRECTION_NAMES[direction]


## Returns the {Direction: Vector2i offset} table that applies to [param column].
static func get_neighbor_offsets(column: int) -> Dictionary[Direction, Vector2i]:
	return _EVEN_COLUMN_OFFSETS if column % 2 == 0 else _ODD_COLUMN_OFFSETS


static func get_neighbor(coordinate: Vector2i, direction: Direction) -> Vector2i:
	return coordinate + get_neighbor_offsets(coordinate.x)[direction]


## Returns every neighboring coordinate of [param coordinate], keyed by direction.
static func get_all_neighbors(coordinate: Vector2i) -> Dictionary[Direction, Vector2i]:
	var offsets: Dictionary[Direction, Vector2i] = get_neighbor_offsets(coordinate.x)
	var neighbors: Dictionary[Direction, Vector2i] = {}
	for direction: Direction in offsets:
		neighbors[direction] = coordinate + offsets[direction]
	return neighbors


# --- Axial / cube coordinates (used for hex distance) ---------------------
# Conversion follows Red Blob Games' "odd-q" offset layout (offset = ODD = -1).

static func offset_to_axial(coordinate: Vector2i) -> Vector2i:
	var q := coordinate.x
	var r := coordinate.y - (coordinate.x - (coordinate.x & 1)) / 2
	return Vector2i(q, r)


static func axial_to_offset(axial: Vector2i) -> Vector2i:
	var column := axial.x
	var row := axial.y + (axial.x - (axial.x & 1)) / 2
	return Vector2i(column, row)


static func axial_to_cube(axial: Vector2i) -> Vector3i:
	return Vector3i(axial.x, axial.y, -axial.x - axial.y)


static func cube_distance(a: Vector3i, b: Vector3i) -> int:
	return (absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)) / 2


## Number of hex steps between two offset coordinates.
static func distance(a: Vector2i, b: Vector2i) -> int:
	return cube_distance(
		axial_to_cube(offset_to_axial(a)),
		axial_to_cube(offset_to_axial(b))
	)


# --- Pixel-space layout for a flat-top hex grid ----------------------------

## World-space position of a cell on the XZ plane, matching a flat-top hex
## grid laid out column-by-column with the given spacings.
static func offset_to_world(coordinate: Vector2i, horizontal_spacing: float, vertical_spacing: float) -> Vector3:
	return Vector3(
		coordinate.x * horizontal_spacing,
		0.0,
		coordinate.y * vertical_spacing + (coordinate.x % 2) * vertical_spacing / 2.0
	)


# --- Hexagon geometry helpers ----------------------------------------------

## Position of corner [param index] (0..5) of a flat-top hexagon on the XZ
## plane, at the given [param radius] and [param height] (Y offset).
static func corner_point_3d(index: int, radius: float, height: float = 0.0) -> Vector3:
	var angle := deg_to_rad(index * 60.0)
	return Vector3(radius * cos(angle), height, radius * sin(angle))


## 2D equivalent of [method corner_point_3d], useful for footprint checks.
static func corner_point_2d(index: int, radius: float = 1.0) -> Vector2:
	var angle := deg_to_rad(index * 60.0)
	return Vector2(cos(angle), sin(angle)) * radius


## Whether [param point] lies inside a flat-top hexagon of [param radius]
## centered at the origin.
static func is_point_in_hexagon(point: Vector2, radius: float = 1.0) -> bool:
	for index in range(6):
		var p1: Vector2 = corner_point_2d(index, radius)
		var p2: Vector2 = corner_point_2d((index + 1) % 6, radius)
		if (p2 - p1).cross(point - p1) < 0.0:
			return false
	return true
