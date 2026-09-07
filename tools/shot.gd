extends Node3D

# Dev harness: loads the real world scene, parks the player at requested X
# positions, lets it settle on the ground, and writes a PNG of the gameplay
# camera for each.
#
#   godot --path . --resolution 1600x900 res://tools/shot.tscn -- --out=/tmp/s 0 -34 34
#
# Nothing here is used at runtime.

const WORLD := "res://scenes/world.tscn"

var _out := "user://shots"
var _xs: Array[float] = [0.0]

func _ready() -> void:
	var xs: Array[float] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.is_valid_float():
			xs.append(float(a))
	if not xs.is_empty():
		_xs = xs
	DirAccess.make_dir_recursive_absolute(_out)
	_run()

func _run() -> void:
	var world := (load(WORLD) as PackedScene).instantiate() as Node3D
	add_child(world)
	var player := world.get_node("Player") as CharacterBody3D
	for i in 30:
		await get_tree().process_frame
	for x in _xs:
		player.global_position = Vector3(x, 4.0, 0.0)
		player.velocity = Vector3.ZERO
		for i in 90:
			await get_tree().physics_frame
			if player.is_on_floor() and i > 30:
				break
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/x%+04d.png" % [_out, int(round(x))]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
	get_tree().quit()
