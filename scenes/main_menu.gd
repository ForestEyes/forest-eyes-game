extends Control

func _ready() -> void:
	$CenterContainer/Menu/PlayButton.pressed.connect(_on_play_pressed)
	$CenterContainer/Menu/ExitButton.pressed.connect(_on_exit_pressed)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_1.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
