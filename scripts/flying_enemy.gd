extends Enemy
class_name FlyingEnemy

@export_group("Movement")
@export var move_speed := 130.0
@export var detection_range := 350.0
@export var hover_height := 80.0
@export var gravity := 150.0
@export var hop_impulse := 90.0
@export var hop_interval := 0.28
@export var max_rise_speed := 140.0
@export var max_fall_speed := 220.0

var hop_timer := 0.0
var _spawn_y := 0.0

@export_group("Dive Attack")
@export var dive_speed := 420.0
@export var dive_trigger_range := 24.0
@export var dive_trigger_min_height := 40.0
@export var dive_trigger_max_height := 200.0
@export var dive_track_speed := 260.0
@export var relaunch_speed := 260.0

var _was_attacking := false

@onready var bt_player: BTPlayer = $BTPlayer
@onready var visual: Polygon2D = $Placeholder


func _ready() -> void:
	super._ready()
	bt_player.update_mode = BTPlayer.UpdateMode.MANUAL
	_spawn_y = global_position.y


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_tick_attack(delta)

	if _tick_knockback_stun(delta):
		move_and_slide()
		_track_attack_end()
		return

	if is_attacking():
		_process_attack(delta)
		move_and_slide()
		_track_attack_end()
		return

	bt_player.update(delta)
	_apply_flight(delta)

	move_and_slide()
	_track_attack_end()


# While chasing/patrolling: horizontal eases toward the player when in range
# (otherwise eases to a stop), vertical is light gravity plus periodic small
# upward hops whenever we're below the target height — a self-correcting bob
# around that height instead of a locked hover or an unbounded climb. Target
# height is the player's height (plus hover_height) when chasing, or wherever
# it was when it last had a target (patrol altitude) when idle.
func _apply_flight(delta: float) -> void:
	var in_range := Global.player != null and global_position.distance_to(Global.player.global_position) <= detection_range

	if in_range:
		var direction_x := signf(Global.player.global_position.x - global_position.x)
		velocity.x = move_toward(velocity.x, direction_x * move_speed, move_speed * 4.0 * delta)
		_spawn_y = Global.player.global_position.y - hover_height
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)

	hop_timer = maxf(hop_timer - delta, 0.0)
	if global_position.y > _spawn_y and hop_timer <= 0.0:
		velocity.y = -hop_impulse
		hop_timer = hop_interval

	velocity.y += gravity * delta
	velocity.y = clampf(velocity.y, -max_rise_speed, max_fall_speed)


func _process_attack(delta: float) -> void:
	match attack_phase:
		AttackPhase.STARTUP:
			velocity = Vector2.ZERO
		AttackPhase.ACTIVE:
			if Global.player:
				var dir_x := signf(Global.player.global_position.x - global_position.x)
				velocity.x = move_toward(velocity.x, dir_x * dive_track_speed, dive_track_speed * 6.0 * delta)
			velocity.y = dive_speed
			if is_on_floor():
				attack_phase_timer = 0.0
		AttackPhase.RECOVERY:
			velocity = Vector2.ZERO


func _track_attack_end() -> void:
	var attacking_now := is_attacking()
	if _was_attacking and not attacking_now:
		velocity.y = -relaunch_speed
	_was_attacking = attacking_now


func _is_attack_ready() -> bool:
	if not can_start_attack():
		return false
	if not Global.player:
		return false
	if global_position.distance_to(Global.player.global_position) > detection_range:
		return false
	var to_player := Global.player.global_position - global_position
	if to_player.y < dive_trigger_min_height:
		return false
	if to_player.y > dive_trigger_max_height:
		return false
	if absf(to_player.x) > dive_trigger_range:
		return false
	return true
