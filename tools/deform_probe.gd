extends Node3D

# Dev harness for the plastic landing deformation. Drives the real player in the
# real world scene and checks that a facet is only remoulded while it is rolling
# through the ground-contact patch.
#
#   godot --path . --quit-after 3000 res://tools/deform_probe.tscn
#
# It prints a PASS/FAIL line per property and exits non-zero on failure.

const IDLE_HOLD := 1.0
const MIN_AIR_TRAVEL := 1.5
const MIN_PASSES := 4
const EPS := 0.0005
# The slab runs x in [-40, 40]; turn round well inside it so the roll can go on
# as long as it needs to without the ball ever leaving the ground.
const TURN_X := 22.0
const TIME_LIMIT := 60.0

var _player: CharacterBody3D
var _d: ClayDeform
var _t := 0.0
var _phase := "settle"
var _mark := 0.0
var _prev := Vector3.ZERO
var _was_floor := false
var _report: Array[String] = []
var _failed := false

# per-phase accumulators
var _depth_at_mark := 0.0
var _idle_drift := 0.0
var _air_travel := 0.0
var _air_spin := 0.0
var _air_drift := 0.0
var _roll_travel := 0.0
var _off_travel := 0.0
var _off_drift := 0.0
var _on_travel := 0.0
var _passes := 0
var _in_patch := false
var _prev_depth := 0.0
var _dir := "ui_right"

func _ready() -> void:
	var w: Node3D = load("res://scenes/world.tscn").instantiate()
	add_child(w)
	_player = w.get_node("Player")
	_d = _player._deform
	_prev = _player.global_position

func _physics_process(delta: float) -> void:
	_t += delta
	var pos := _player.global_position
	var step := (pos - _prev)
	step.y = 0.0
	var travel := step.length()
	_prev = pos
	var on_floor := _player.is_on_floor()
	var depth: float = _d._depth[0]

	match _phase:
		"settle":
			# Let the spawn drop finish, then start from undeformed clay.
			if on_floor and _t > 0.8:
				_reset()
				_jump()
				_phase = "fall"
		"fall":
			if not _was_floor and on_floor:
				_depth_at_mark = depth
				_mark = _t
				_check("landing presses a facet", depth > EPS,
					"facet %.4f deep" % depth)
				_phase = "idle"
		"idle":
			# Standing still must not change anything.
			_idle_drift = maxf(_idle_drift, absf(depth - _depth_at_mark))
			if _t - _mark >= IDLE_HOLD:
				_check("idle holds the shape",
					_idle_drift <= EPS,
					"drift %.5f over %.1fs" % [_idle_drift, IDLE_HOLD])
				Input.action_press("ui_right")
				_jump()
				_depth_at_mark = depth
				_phase = "air"
		"air":
			# Travelling through the air spins the ball but must not knead it.
			if not on_floor:
				_air_travel += travel
				_air_spin += travel / maxf(_player._radius, 0.0001)
				_air_drift = maxf(_air_drift, absf(depth - _depth_at_mark))
			elif _air_travel > 0.0:
				_check("airborne travel leaves the facet alone",
					_air_drift <= EPS and _air_travel >= MIN_AIR_TRAVEL,
					"%.2f units of travel, %.2f rad of spin, drift %.5f"
						% [_air_travel, _air_spin, _air_drift])
				Input.action_release("ui_right")
				_reset()
				_jump()
				_phase = "fall2"
		"fall2":
			if not _was_floor and on_floor:
				_depth_at_mark = depth
				_prev_depth = depth
				_note("second landing pressed a facet %.4f deep" % depth)
				Input.action_press(_dir)
				_phase = "roll"
		"roll":
			_roll(travel, depth)

	_was_floor = on_floor

func _roll(travel: float, depth: float) -> void:
	var align: float = (_player._body_off * _d._axis[0]).dot(_player._contact.normalized())
	var inside: bool = align > _d.contact_edge
	var change := absf(depth - _prev_depth)
	_prev_depth = depth
	_roll_travel += travel

	var x: float = _player.global_position.x
	if (x > TURN_X and _dir == "ui_right") or (x < -TURN_X and _dir == "ui_left"):
		Input.action_release(_dir)
		_dir = "ui_left" if _dir == "ui_right" else "ui_right"
		Input.action_press(_dir)

	if inside:
		_on_travel += travel
		if not _in_patch:
			_passes += 1
	else:
		# The facet is on the side or the top of the ball: it must not move.
		_off_travel += travel
		_off_drift = maxf(_off_drift, change)
	_in_patch = inside

	if depth > EPS and _t < TIME_LIMIT:
		return

	Input.action_release(_dir)
	_check("the facet is fully remoulded", depth <= EPS,
		"%.4f left after %.1fs" % [depth, _t])
	_check("a facet off the contact patch is untouched",
		_off_drift <= EPS and _off_travel >= MIN_AIR_TRAVEL,
		"%.2f units rolled with the facet clear of the ground, drift %.5f"
			% [_off_travel, _off_drift])
	_check("remoulding needs several real contact passes",
		_passes >= MIN_PASSES,
		"%d passes, %.2f units of contact travel, %.2f units rolled in total"
			% [_passes, _on_travel, _roll_travel])
	_check("rounding stays well short of a sphere",
		_d._round < _d.round_max and _d._round < 0.25,
		"rounding %.3f after %.1f units of ground contact (cap %.2f)"
			% [_d._round, _d._contact_roll, _d.round_max])
	_finish()

func _reset() -> void:
	for i in ClayDeform.DENTS:
		_d._depth[i] = 0.0
		_d._depth0[i] = 0.0
		_d._knead[i] = 0.0

func _jump() -> void:
	_player.velocity.y = _player.JUMP_VELOCITY

func _note(text: String) -> void:
	_report.append("      %s" % text)

func _check(name: String, ok: bool, detail: String) -> void:
	_report.append("%s  %s" % ["PASS" if ok else "FAIL", name])
	_report.append("      %s" % detail)
	if not ok:
		_failed = true

func _finish() -> void:
	print("\n--- clay deformation probe ---")
	for line in _report:
		print(line)
	print("--- %s ---\n" % ("FAILED" if _failed else "all checks passed"))
	get_tree().quit(1 if _failed else 0)
