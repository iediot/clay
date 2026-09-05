extends Camera3D

# Cinematic lead: the camera drifts ahead of the direction of travel, holds the
# shot for a beat once the player stops, then eases back to centre.

@export var lead_distance: float = 4.0
@export var lead_time: float = 1.1
@export var recentre_time: float = 1.6
@export var hold_delay: float = 0.35
@export var damping: float = 1.0
@export var deadzone: float = 0.05

var _rest: Vector3
var _player: CharacterBody3D
var _offset := 0.0
var _target := 0.0
var _vel := 0.0
var _idle := 0.0

func _ready() -> void:
	_rest = position
	_player = get_parent() as CharacterBody3D

func _physics_process(delta: float) -> void:
	if _player == null:
		return

	var smooth := lead_time
	if absf(_player.velocity.x) > deadzone:
		_idle = 0.0
		_target = signf(_player.velocity.x) * lead_distance
	else:
		# Let the frame settle before pulling back, so a brief pause is not a swing.
		_idle += delta
		if _idle >= hold_delay:
			_target = 0.0
			smooth = recentre_time

	_offset = _spring(_offset, _target, smooth, delta)
	position = _rest + Vector3(_offset, 0.0, 0.0)

# Damped spring rather than a lerp: it eases in as well as out, so the pan has no
# hard start and settles instead of snapping.
func _spring(x: float, target: float, smooth_time: float, delta: float) -> float:
	var w := 2.0 / maxf(smooth_time, 0.0001)
	_vel += (w * w * (target - x) - 2.0 * damping * w * _vel) * delta
	return x + _vel * delta
