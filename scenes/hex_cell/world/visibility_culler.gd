class_name VisibilityCuller
extends RefCounted

## Hides cells and tree chunks that are too far from the camera target, and
## fades out distant tree chunks' detail (LOD) to keep the scene light.

var enable_distance_culling: bool = true
var use_fixed_test_culling: bool = true
var fixed_test_culling_distance: float = 15.0
var culling_zoom_multiplier: float = 2.5
var culling_distance_offset: float = 12.0
var culling_update_interval: float = 0.05

var enable_tree_lod: bool = true
var tree_lod_start_zoom: float = 8.0
var tree_lod_end_zoom: float = 25.0
var tree_lod_min_ratio: float = 0.2

var _camera_controller: Node3D
var _camera_target: Node3D
var _culling_time: float = 0.0


func _init(camera_controller: Node3D, camera_target: Node3D) -> void:
	_camera_controller = camera_controller
	_camera_target = camera_target


## Call once per frame. Runs the actual visibility update at most every
## [member culling_update_interval] seconds.
func tick(delta: float, cells: Dictionary, tree_chunks: Dictionary) -> void:
	if not enable_distance_culling:
		for cell: HexCell in cells.values():
			set_cell_visible(cell, true)
		for chunk: Node3D in tree_chunks.values():
			set_tree_chunk_visible(chunk, true)
		return

	_culling_time += delta
	if _culling_time < culling_update_interval:
		return

	_culling_time = 0.0
	force_update(cells, tree_chunks)


## Forces an immediate visibility update, ignoring the update interval.
func force_update(cells: Dictionary, tree_chunks: Dictionary) -> void:
	_culling_time = culling_update_interval
	if not enable_distance_culling:
		return

	if _camera_controller == null or _camera_target == null:
		return

	var phantom_camera: Node = _camera_controller.get_node_or_null("PhantomCamera3D")
	var culling_distance: float
	if use_fixed_test_culling:
		culling_distance = fixed_test_culling_distance
	else:
		if phantom_camera == null:
			return
		var zoom_distance: float = phantom_camera.get("spring_length")
		culling_distance = zoom_distance * culling_zoom_multiplier + culling_distance_offset
	var target_position: Vector3 = _camera_target.global_position
	var culling_distance_squared: float = culling_distance * culling_distance

	for cell: HexCell in cells.values():
		var cell_position: Vector3 = cell.global_position
		var horizontal_offset := Vector2(
			cell_position.x - target_position.x,
			cell_position.z - target_position.z
		)
		set_cell_visible(cell, horizontal_offset.length_squared() < culling_distance_squared)

	for chunk: Node3D in tree_chunks.values():
		var chunk_offset := Vector2(
			chunk.global_position.x - target_position.x,
			chunk.global_position.z - target_position.z
		)
		var chunk_is_visible: bool = chunk_offset.length_squared() < culling_distance_squared
		set_tree_chunk_visible(chunk, chunk_is_visible)
		_update_tree_chunk_lod(chunk, phantom_camera, chunk_is_visible)


func set_cell_visible(cell: HexCell, is_visible: bool) -> void:
	var water_mesh: Node3D = cell.get_node_or_null("WaterShader") as Node3D
	var grass_mesh: Node3D = cell.get_node_or_null("GrassShader") as Node3D
	var river_mesh: Node3D = cell.get_node_or_null("RiverShader") as Node3D
	if water_mesh != null:
		_set_visual_descendants_visible(water_mesh, is_visible and cell.cell_type == "water")
	if grass_mesh != null:
		_set_visual_descendants_visible(grass_mesh, is_visible and (cell.cell_type == "forest" or cell.cell_type == "river"))
	if river_mesh != null:
		_set_visual_descendants_visible(river_mesh, false)


func set_tree_chunk_visible(chunk: Node3D, is_visible: bool) -> void:
	for child: Node in chunk.get_children():
		_set_visual_descendants_visible(child, is_visible)


func _update_tree_chunk_lod(chunk: Node3D, phantom_camera: Node, chunk_is_visible: bool) -> void:
	var lod_ratio: float = 1.0
	if enable_tree_lod and phantom_camera != null:
		var zoom_distance: float = phantom_camera.get("spring_length")
		var zoom_range: float = maxf(0.001, tree_lod_end_zoom - tree_lod_start_zoom)
		lod_ratio = clampf(
			1.0 - (zoom_distance - tree_lod_start_zoom) / zoom_range,
			tree_lod_min_ratio,
			1.0
		)

	for child: Node in chunk.get_children():
		_set_multimesh_lod(child, lod_ratio, chunk_is_visible)


func _set_multimesh_lod(node: Node, lod_ratio: float, chunk_is_visible: bool) -> void:
	if node is MultiMeshInstance3D:
		var multimesh_instance: MultiMeshInstance3D = node as MultiMeshInstance3D
		multimesh_instance.visible = chunk_is_visible and (not enable_tree_lod or lod_ratio >= 0.5)

	for child: Node in node.get_children():
		_set_multimesh_lod(child, lod_ratio, chunk_is_visible)


func _set_visual_descendants_visible(node: Node, is_visible: bool) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = is_visible
	for child: Node in node.get_children():
		_set_visual_descendants_visible(child, is_visible)
