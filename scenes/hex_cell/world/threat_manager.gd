class_name ThreatManager
extends RefCounted

enum CureResult { FAILED, RESOLVED, INSUFFICIENT_RESOURCES, INVALID_REQUEST }

const MIN_EXPLORED_TILES_FOR_THREATS: int = 15

## Spawns threats on explored forest cells and resolves their cure attempts
## and failure consequences.

var spawn_min_interval: float = 15.0
var spawn_max_interval: float = 45.0
var min_count_per_wave: int = 1
var max_count_per_wave: int = 3
var allowed_threat_types: int = 7

var _world: WorldCells
var _spawn_timer: float = 0.0
var _next_spawn_interval: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init(world: WorldCells) -> void:
	_world = world
	_rng.randomize()
	_next_spawn_interval = _get_random_spawn_interval()


## Forgets every tracked threatened cell, e.g. before a world regeneration.
func reset() -> void:
	_spawn_timer = 0.0
	_next_spawn_interval = _get_random_spawn_interval()


static func get_cure_resource_weights(threat: StringName) -> Vector2i:
	match threat:
		HexCell.THREAT_FIRE:
			return Vector2i(1, 2)
		HexCell.THREAT_CONTAMINATION:
			return Vector2i.ONE
		HexCell.THREAT_DEFORESTATION:
			return Vector2i(2, 1)
	return Vector2i.ZERO


static func calculate_cure_chance(threat: StringName, level: int, life_amount: int, water_amount: int) -> float:
	var weights := get_cure_resource_weights(threat)
	if weights == Vector2i.ZERO:
		return 0.0

	var target_score: int = maxi(1, level) * maxi(weights.x, weights.y)
	var resource_score: int = maxi(0, life_amount) * weights.x + maxi(0, water_amount) * weights.y
	return clampf(float(resource_score) / float(target_score), 0.0, 1.0)


static func calculate_combined_cure_chance(
	threats: Array[StringName],
	level: int,
	life_amount: int,
	water_amount: int
) -> float:
	var combined_chance := 0.0
	for threat: StringName in threats:
		combined_chance += calculate_cure_chance(threat, level, life_amount, water_amount)
	return clampf(combined_chance, 0.0, 1.0)


static func get_default_cure_allocation(
	threats: Array[StringName],
	level: int,
	available_life: int,
	available_water: int
) -> Vector2i:
	var effective_level: int = maxi(1, level)
	var life_efficiency := 0.0
	var water_efficiency := 0.0
	for threat: StringName in threats:
		var weights := get_cure_resource_weights(threat)
		if weights == Vector2i.ZERO:
			continue
		var target_score: int = effective_level * maxi(weights.x, weights.y)
		life_efficiency += float(weights.x) / float(target_score)
		water_efficiency += float(weights.y) / float(target_score)

	var life_required: int = ceili(1.0 / life_efficiency) if life_efficiency > 0.0 else 0
	var water_required: int = ceili(1.0 / water_efficiency) if water_efficiency > 0.0 else 0
	var life_can_guarantee: bool = life_required > 0 and available_life >= life_required
	var water_can_guarantee: bool = water_required > 0 and available_water >= water_required
	if life_can_guarantee and (life_efficiency >= water_efficiency or not water_can_guarantee):
		return Vector2i(life_required, 0)
	if water_can_guarantee:
		return Vector2i(0, water_required)
	if life_efficiency >= water_efficiency and life_efficiency > 0.0:
		if available_life > 0:
			return Vector2i(mini(life_required, available_life), 0)
		return Vector2i(0, mini(water_required, maxi(0, available_water)))
	if water_efficiency > 0.0:
		if available_water > 0:
			return Vector2i(0, mini(water_required, available_water))
		return Vector2i(mini(life_required, maxi(0, available_life)), 0)
	return Vector2i.ZERO


func attempt_cure_all(cell: HexCell, life_amount: int, water_amount: int) -> CureResult:
	if (
		not is_instance_valid(cell)
		or not cell.is_explored
		or cell.world_cells != _world
		or cell.active_threats.is_empty()
	):
		return CureResult.INVALID_REQUEST
	if life_amount < 0 or water_amount < 0:
		return CureResult.INVALID_REQUEST
	var active_threats: Array[StringName] = []
	for threat: StringName in HexCell.THREAT_TYPES:
		if cell.active_threats.has(threat):
			active_threats.append(threat)
	if active_threats.is_empty():
		return CureResult.INVALID_REQUEST
	if _world.life < life_amount or _world.water < water_amount:
		return CureResult.INSUFFICIENT_RESOURCES
	if not _world.spend_resources(life_amount, water_amount):
		return CureResult.INSUFFICIENT_RESOURCES

	var chance := calculate_combined_cure_chance(active_threats, cell.current_level, life_amount, water_amount)
	if chance >= 1.0 or _rng.randf() < chance:
		cell.clear_threats()
		return CureResult.RESOLVED
	_apply_failed_cure_effects(cell, active_threats)
	return CureResult.FAILED


func tick(delta: float, cells: Dictionary) -> void:
	if _world.explored_cell_count < MIN_EXPLORED_TILES_FOR_THREATS:
		return

	_spawn_timer += delta
	if _spawn_timer >= _next_spawn_interval:
		_spawn_timer = 0.0
		_next_spawn_interval = _get_random_spawn_interval()
		_spawn_threat_wave(cells)


func _apply_failed_cure_effects(cell: HexCell, threats: Array[StringName]) -> void:
	var level_at_failure: int = maxi(0, cell.current_level)
	var trees_changed := false
	for threat: StringName in threats:
		match threat:
			HexCell.THREAT_FIRE:
				if cell.degrade_from_fire():
					trees_changed = true
			HexCell.THREAT_DEFORESTATION:
				_world.lose_life(level_at_failure)
			HexCell.THREAT_CONTAMINATION:
				_spread_contamination(cell)

	if trees_changed:
		_world.rebuild_tree_batches()


func _spawn_threat_wave(cells: Dictionary) -> void:
	var candidates: Array[HexCell] = []
	for cell: HexCell in cells.values():
		if cell.cell_type == "forest" and cell.is_explored:
			candidates.append(cell)

	if candidates.is_empty() or allowed_threat_types == 0:
		return

	candidates.shuffle()
	var wave_count: int = _rng.randi_range(min_count_per_wave, max_count_per_wave)
	var affected_count: int = mini(wave_count, candidates.size())
	for index in range(affected_count):
		_apply_random_threat(candidates[index])


func _get_random_spawn_interval() -> float:
	return _rng.randf_range(spawn_min_interval, spawn_max_interval)


func _apply_random_threat(cell: HexCell) -> void:
	var available_threats: Array[StringName] = []
	for threat_index in range(HexCell.THREAT_TYPES.size()):
		if (allowed_threat_types & (1 << threat_index)) != 0:
			available_threats.append(HexCell.THREAT_TYPES[threat_index])
	if available_threats.is_empty():
		return

	var threat: StringName = available_threats[_rng.randi_range(0, available_threats.size() - 1)]
	_apply_threat(cell, threat)


func _apply_threat(cell: HexCell, threat: StringName) -> void:
	cell.add_threat(threat)


func _spread_contamination(source_cell: HexCell) -> void:
	var candidates: Array[HexCell] = []
	for neighbor: HexCell in source_cell.neigboring_cells.values():
		if neighbor != null and neighbor.is_explored and neighbor.cell_type == "forest" and not neighbor.active_threats.has(HexCell.THREAT_CONTAMINATION):
			candidates.append(neighbor)

	if candidates.is_empty():
		return

	_apply_threat(candidates[_rng.randi_range(0, candidates.size() - 1)], HexCell.THREAT_CONTAMINATION)
