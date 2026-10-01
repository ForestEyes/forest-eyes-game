class_name LevelProgressViewportPool
extends RefCounted

## Pools the SubViewports used to render each HexCell's level-up progress bar.

## Viewports are expensive to keep active for every cell at once, so a small
## pool is shared: a cell "acquires" a viewport only while its progress bar is
## visible, and "releases" it back to the pool once it finishes animating.

var _host: Node
var _viewport_scene: PackedScene
var _available_viewports: Array[SubViewport] = []
var _assignments: Dictionary = {}


func _init(host: Node, viewport_scene: PackedScene, pool_size: int) -> void:
	_host = host
	_viewport_scene = viewport_scene
	for _index in range(pool_size):
		var viewport := _viewport_scene.instantiate() as SubViewport
		if viewport == null:
			push_error("The level progress viewport scene must have a SubViewport root node.")
			continue
		# Each bar needs its own fill style so threat/level-up colors don't leak between cells.
		var progress := viewport.get_node("Control/LevelProgress") as ProgressBar
		var fill_style := progress.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style != null:
			progress.add_theme_stylebox_override("fill", fill_style.duplicate())
		_host.add_child(viewport)
		_available_viewports.append(viewport)


func acquire(cell: HexCell) -> Dictionary:
	if _assignments.has(cell):
		return _assignments[cell]
	if _available_viewports.is_empty():
		return {}

	var viewport: SubViewport = _available_viewports.pop_back()
	var progress := viewport.get_node("Control/LevelProgress") as ProgressBar
	progress.max_value = 100.0
	progress.value = 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

	var assignment := {"viewport": viewport, "progress": progress}
	_assignments[cell] = assignment
	return assignment


func release(cell: HexCell) -> void:
	if not _assignments.has(cell):
		return

	var assignment: Dictionary = _assignments[cell]
	_assignments.erase(cell)
	var viewport: SubViewport = assignment["viewport"]
	var progress: ProgressBar = assignment["progress"]
	progress.value = 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_available_viewports.append(viewport)


func update(viewport: SubViewport) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


## Recolors a pooled progress bar's fill, e.g. green for level-up, red while clearing a threat.
static func set_fill_color(progress: ProgressBar, color: Color) -> void:
	var fill_style := progress.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = color


# Releases every outstanding assignment back to the pool, before a world regeneration.
func reset_assignments() -> void:
	for assignment: Dictionary in _assignments.values():
		var viewport: SubViewport = assignment["viewport"]
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_available_viewports.append(viewport)
	_assignments.clear()
