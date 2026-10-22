class_name PauseMenu
extends Node

@onready var overlay: Control = $Overlay


func _ready() -> void:
	overlay.visible = false
	$Overlay/CenterContainer/Menu/ResumeButton.pressed.connect(resume_game)
	$Overlay/CenterContainer/Menu/MainMenuButton.pressed.connect(_on_main_menu_pressed)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if event is InputEventKey and event.is_echo():
		return

	get_viewport().set_input_as_handled()
	if overlay.visible:
		resume_game()
	else:
		open_pause_menu()


func open_pause_menu() -> void:
	overlay.visible = true
	get_tree().paused = true


func resume_game() -> void:
	get_tree().paused = false
	overlay.visible = false


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
