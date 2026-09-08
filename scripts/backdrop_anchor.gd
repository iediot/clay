extends Node3D

# Holds a backdrop piece at a fixed place on screen.
#
# `follow` = 1 locks a piece to the camera in x/z so it never parallaxes; a little
# under 1 lets a distant object drift very slowly as the player crosses the track.
# `lock_to_view` instead parks the piece straight ahead of the camera, which is
# how the sky sheet stays centred and fully covering whatever the camera does.

@export_range(0.0, 1.0) var follow: float = 1.0
@export var lock_to_view: bool = false
@export var view_distance: float = 600.0
# Match the camera's own rotation rather than turning to look at it. A flat
# object aimed at the camera's position sits square to the view *ray*, and the
# projection then stretches it into an ellipse the further it is from the centre
# of a wide frame — which is what was deforming the sun in the corner. Anything
# parallel to the image plane projects to the same shape wherever it sits, so a
# circle stays a circle.
@export var face_camera: bool = false

var _base: Vector3

func _ready() -> void:
	_base = position

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if lock_to_view:
		# -Z is the camera's forward, so this sits `view_distance` ahead of it.
		global_transform = Transform3D(cam.global_transform.basis,
			cam.global_position - cam.global_transform.basis.z * view_distance)
		return
	var c := cam.global_position
	global_position = _base + Vector3(c.x * follow, 0.0, c.z * follow)
	if face_camera:
		global_transform = Transform3D(cam.global_transform.basis, global_position)
