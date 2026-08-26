extends Enemy
class_name MeleeGroundEnemy

# Basic grounded chase-and-hop enemy. No attacks — contact damage only,
# handled entirely by the base Enemy class. Movement uses its own small,
# separate set of tunable values rather than reusing anything from player.gd.
#
# Decision-making lives in the BTPlayer's behavior tree (same pattern as
# FlyingEnemy) — built visually in the editor's LimboAI panel, not
# hand-authored here. This script keeps ONLY the physics/perception plumbing
# the tree's conditions and actions read from: gravity, facing, raycast
# positioning, and the jump-cooldown timer. The tree itself replicates the
# old _decide_movement() priority order exactly:
#   Selector [
#     Sequence [ PlayerInRange, PlayerAbove, JumpReady, Jump ]
#     Sequence [ PlayerInRange, ForwardBlocked, ObstacleTooTall, TurnAround ]
#     Sequence [ PlayerInRange, ForwardBlocked, JumpReady, Jump ]
#     Sequence [ PlayerInRange, ForwardBlocked, HaltHorizontal ]
#     Sequence [ PlayerInRange, AtLedge, HaltHorizontal ]
#     Sequence [ PlayerInRange, Walk ]
#     HaltHorizontal  (fallback: player out of range)
#   ]
# At a ledge, the enemy just stops rather than turning away — it keeps
# facing the player (via _update_facing(), unaffected since no TurnAround
# runs here) and re-evaluates every frame. Once the player ends up on the
# enemy's own side of the ledge, _update_facing() naturally flips
# facing_direction toward them, LedgeRay now checks solid ground instead
# of the gap, AtLedge fails, and Walk takes over — no explicit "wait for
# player to cross" state needed, it falls out of the existing per-frame
# re-evaluation.
# One deliberate behavior change from the old version: when blocked by an
# obstacle it can't yet jump over (on cooldown), this now zeroes velocity.x
# via HaltHorizontal instead of leaving it untouched — cleaner, and the old
# behavior only mattered because it left the enemy drifting into a wall it
# was already colliding with, which is harmless either way.
#
# Leaf tasks live in scripts/bt/: bt_player_in_range.gd (shared with
# FlyingEnemy), bt_player_above.gd, bt_jump_ready.gd, bt_forward_blocked.gd,
# bt_obstacle_too_tall.gd, bt_at_ledge.gd, bt_turn_around.gd, bt_jump.gd,
# bt_walk.gd, bt_halt_horizontal.gd.

@export_group("Movement")
@export var move_speed := 150.0
@export var gravity := 900.0
@export var max_fall_speed := 400.0
@export var jump_velocity := -280.0

@export_group("AI")
@export var detection_range := 400.0  # how far the player can be and still get chased
@export var obstacle_check_height := 32.0  # how far above the ground the "can I jump over this" ray sits — match this to your tile size
@export var jump_cooldown := 0.4  # minimum time between jumps so it doesn't spam-jump against a wall or a raised player
@export_group("AI/Hop To Reach Player")
@export var player_above_min_height := 16.0  # how much higher than the enemy the player needs to be to trigger a hop-to-reach jump — lower than obstacle_check_height on purpose, since a player mid-jump-arc only clears a given height briefly and this needs to be easy to catch
@export var player_above_max_horizontal := 48.0  # how far ahead/behind the player can be (at the required height) and still count as "above" rather than just "nearby"
@export_group("AI/Turn Lock")
@export var turn_lock_time := 0.35  # after TurnAround fires, how long _update_facing() is suppressed — without this, facing the player every single frame instantly undoes the turn (it's still across the ledge/wall), causing a permanent facing-flip loop that looks like the enemy is "stuck". This gives it a window to actually walk away first.

var facing_direction := 1
var jump_cooldown_timer := 0.0
var turn_lock_timer := 0.0

@onready var forward_ray: RayCast2D = $ForwardRay
@onready var ledge_ray: RayCast2D = $LedgeRay
@onready var obstacle_top_ray: RayCast2D = $ObstacleTopRay
@onready var bt_player: BTPlayer = $BTPlayer


func _ready() -> void:
	super._ready()
	# agent_node defaults to BTPlayer's parent (this node) — left unset.
	bt_player.update_mode = BTPlayer.UpdateMode.MANUAL


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	jump_cooldown_timer = maxf(jump_cooldown_timer - delta, 0.0)
	turn_lock_timer = maxf(turn_lock_timer - delta, 0.0)

	_apply_gravity(delta)
	_update_facing()
	_update_rays()

	bt_player.update(delta)

	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y += gravity * delta
	velocity.y = min(velocity.y, max_fall_speed)


func _player_in_range() -> bool:
	return Global.player and global_position.distance_to(Global.player.global_position) <= detection_range


func _update_facing() -> void:
	if turn_lock_timer > 0.0:
		return
	if not _player_in_range():
		return
	facing_direction = 1 if Global.player.global_position.x > global_position.x else -1


# Raycast positions/directions are authored pointing right by default in the
# scene; this mirrors them to match whichever way the enemy is currently
# facing, then forces an immediate update so this frame's is_colliding()
# checks reflect the flip instead of lagging a frame behind.
func _update_rays() -> void:
	forward_ray.target_position.x = abs(forward_ray.target_position.x) * facing_direction
	ledge_ray.position.x = abs(ledge_ray.position.x) * facing_direction
	obstacle_top_ray.position.y = -obstacle_check_height
	obstacle_top_ray.target_position.x = abs(obstacle_top_ray.target_position.x) * facing_direction

	forward_ray.force_raycast_update()
	ledge_ray.force_raycast_update()
	obstacle_top_ray.force_raycast_update()


func _is_player_above() -> bool:
	if not _player_in_range():
		return false
	var above_by: float = global_position.y - Global.player.global_position.y
	var horizontal_dist: float = abs(global_position.x - Global.player.global_position.x)
	return above_by > player_above_min_height and horizontal_dist < player_above_max_horizontal


func _jump() -> void:
	velocity.y = jump_velocity
	jump_cooldown_timer = jump_cooldown
