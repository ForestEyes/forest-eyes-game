class_name ThreatManager
extends RefCounted

## Periodically afflicts forest cells with threats (fire, deforestation,
## contamination) and applies their ongoing effects until the player clicks
## the cell clear. See HexCell.add_threat()/active_threats for the per-cell
## side of this system.

var spawn_interval: float = 10.0
var cells_per_wave: int = 5
var effect_tick_interval: float = 5.0
var contamination_spread_min_interval: float = 5.0
var contamination_spread_max_interval: float = 20.0

var _world: WorldCells
var _spawn_timer: float = 0.0
var _effect_timer: float = 0.0
var _threatened_cells: Dictionary = {}
var _contamination_spread_timers: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init(world: WorldCells) -> void:
	_world = world
	_rng.randomize()


## Forgets every tracked threatened cell, e.g. before a world regeneration.
func reset() -> void:
	_spawn_timer = 0.0
	_effect_timer = 0.0
	_threatened_cells.clear()
	_contamination_spread_timers.clear()


func tick(delta: float, cells: Dictionary) -> void:
	_spawn_timer += delta
	if _spawn_timer >= spawn_interval:
		_spawn_timer = 0.0
		_spawn_threat_wave(cells)

	_effect_timer += delta
	if _effect_timer >= effect_tick_interval:
		_effect_timer = 0.0
		_apply_periodic_effects()

	_update_contamination_spread(delta)


func _spawn_threat_wave(cells: Dictionary) -> void:
	var candidates: Array[HexCell] = []
	for cell: HexCell in cells.values():
		if cell.cell_type == "forest":
			candidates.append(cell)

	if candidates.is_empty():
		return

	candidates.shuffle()
	var affected_count: int = mini(cells_per_wave, candidates.size())
	for index in range(affected_count):
		_apply_random_threat(candidates[index])


func _apply_random_threat(cell: HexCell) -> void:
	var threat: StringName = HexCell.THREAT_TYPES[_rng.randi_range(0, HexCell.THREAT_TYPES.size() - 1)]
	_apply_threat(cell, threat)


func _apply_threat(cell: HexCell, threat: StringName) -> void:
	if cell.add_threat(threat):
		_threatened_cells[cell] = true


func _apply_periodic_effects() -> void:
	var trees_changed := false
	for cell: HexCell in _threatened_cells.keys():
		if not is_instance_valid(cell) or cell.active_threats.is_empty():
			_threatened_cells.erase(cell)
			_contamination_spread_timers.erase(cell)
			continue

		if cell.active_threats.has(HexCell.THREAT_FIRE) and cell.degrade_from_fire():
			trees_changed = true

	if trees_changed:
		_world.rebuild_tree_batches()


func _update_contamination_spread(delta: float) -> void:
	for cell: HexCell in _threatened_cells.keys():
		if not is_instance_valid(cell) or not cell.active_threats.has(HexCell.THREAT_CONTAMINATION):
			_contamination_spread_timers.erase(cell)
			continue

		if not _contamination_spread_timers.has(cell):
			_contamination_spread_timers[cell] = _get_random_contamination_interval()
			continue

		var remaining: float = _contamination_spread_timers[cell] - delta
		if remaining > 0.0:
			_contamination_spread_timers[cell] = remaining
			continue

		_contamination_spread_timers[cell] = _get_random_contamination_interval()
		_spread_contamination(cell)


func _get_random_contamination_interval() -> float:
	return _rng.randf_range(contamination_spread_min_interval, contamination_spread_max_interval)


func _spread_contamination(source_cell: HexCell) -> void:
	var candidates: Array[HexCell] = []
	for neighbor: HexCell in source_cell.neigboring_cells.values():
		if neighbor != null and neighbor.cell_type == "forest" and not neighbor.active_threats.has(HexCell.THREAT_CONTAMINATION):
			candidates.append(neighbor)

	if candidates.is_empty():
		return

	_apply_threat(candidates[_rng.randi_range(0, candidates.size() - 1)], HexCell.THREAT_CONTAMINATION)
