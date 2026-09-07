extends Node3D

# Holds a backdrop piece at a near-fixed place on screen. follow = 1 locks it to
# the camera (no parallax at all, for the sky shell); slightly under 1 lets a
# distant object drift very slowly as the player crosses the track.

@export_range(0.0, 1.0) var follow: float = 1.0

var _base: Vector3

func _ready() -> void:
	_base = position

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	global_position = _base + Vector3(c.x * follow, 0.0, c.z * follow)
