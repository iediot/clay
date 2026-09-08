extends Node3D

# Holds a backdrop piece at a near-fixed place on screen. follow = 1 locks it to
# the camera (no parallax at all, for the sky shell); slightly under 1 lets a
# distant object drift very slowly as the player crosses the track.

@export_range(0.0, 1.0) var follow: float = 1.0
# Turn to face the camera each frame. The sun is a flat disc with rays cut into
# it, so it only reads as a sun seen square-on; parked in a corner of the frame
# it would otherwise be viewed at an angle and flatten into an ellipse.
@export var face_camera: bool = false

var _base: Vector3

func _ready() -> void:
	_base = position

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	global_position = _base + Vector3(c.x * follow, 0.0, c.z * follow)
	if face_camera:
		var away := global_position - c
		if away.length() > 0.001:
			# looking_at points -Z at the target, and the disc's face is +Z, so
			# it is aimed at the point mirrored through the sun.
			global_transform = global_transform.looking_at(global_position + away, Vector3.UP)
