extends CharacterBody2D
class_name Player


# Bitflags instead of a single mutually-exclusive state: several of these can
# be true at once (e.g. ATTACKING while airborne, or HURT while DASHING was
# just true a moment ago). WALL_JUMPING isn't here — that was never a real
# state, just wall_jump_control_lock_timer wearing a costume; check the timer
# directly instead.
enum Flag {
	DASHING = 1 << 0,
	WALL_CLINGING = 1 << 1,
	HURT = 1 << 2,
	DEAD = 1 << 3,
	ATTACKING = 1 << 4,
	PARRYING = 1 << 5,
	SPECIAL = 1 << 6,
}

var flags: int = 0

func has_flag(mask: int) -> bool:
	return (flags & mask) != 0

func set_flag(flag: int, value: bool) -> void:
	if value:
		flags |= flag
	else:
		flags &= ~flag

# Invulnerability has multiple sources (hit-flash, dash, dash grace) — one
# place to check all of them instead of repeating the combo everywhere.
func is_invulnerable() -> bool:
	return invulnerability_timer > 0.0 or dash_grace_timer > 0.0 or has_flag(Flag.DASHING)

func is_airborne() -> bool:
	return not is_on_floor()

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var timer: Timer = $Timer

func _ready() -> void:
	Global.player = self

	if Global.has_checkpoint:
		global_position = Global.last_checkpoint_position

	if Global.saved_current_health >= 0:
		current_health = Global.saved_current_health
		Global.saved_current_health = -1
	else:
		current_health = max_health

	Global.last_safe_position = global_position

	if Global.did_just_die:
		invulnerability_timer = invulnerability_duration
		respawn_lock_timer = respawn_lock_time
		Global.did_just_die = false

	if has_node("Hurtbox"):
		$Hurtbox.add_to_group("player_hitbox")
		if not $Hurtbox.is_connected("area_entered", Callable(self, "_on_hazard_area_entered")):
			$Hurtbox.connect("area_entered", Callable(self, "_on_hazard_area_entered"))
		if not $Hurtbox.is_connected("area_exited", Callable(self, "_on_hazard_area_exited")):
			$Hurtbox.connect("area_exited", Callable(self, "_on_hazard_area_exited"))
		# Tile-based hazards (TileMapLayer collision) enter as bodies, not
		# areas — area_entered/exited alone missed them entirely, so
		# hazard_overlap_count never saw tile spikes as "occupied."
		if not $Hurtbox.is_connected("body_entered", Callable(self, "_on_hazard_body_entered")):
			$Hurtbox.connect("body_entered", Callable(self, "_on_hazard_body_entered"))
		if not $Hurtbox.is_connected("body_exited", Callable(self, "_on_hazard_body_exited")):
			$Hurtbox.connect("body_exited", Callable(self, "_on_hazard_body_exited"))


# ========== HEALTH ==========

@export_group("Health")
@export var max_health := 3
var current_health := 3
var invulnerability_timer := 0.0
@export var invulnerability_duration := 1.0
var hit_flash_timer := 0.0
@export var hit_flash_duration := 0.4  # how long the "hit" animation plays, independent of HURT's action-lock
@export var knockback_control_lock_time := 0.15  # how long normal movement ignores held input after a knockback, so it doesn't get instantly canceled out — reuses the existing (previously unused) control_lock_timer

# ========== ATTACK ==========

@export_group("Attack")
@export var attack_damage := 1
@export var attack_duration := 0.25
@export var attack_cooldown := 0.4

var attack_state_timer := 0.0
var attack_cooldown_timer := 0.0

# ========== PARRY ==========

@export_group("Parry")
@export var parry_window_duration := 0.2
@export var parry_cooldown := 0.5
@export var parry_heal_amount := 0.25

var parry_state_timer := 0.0
var parry_cooldown_timer := 0.0
var _parry_heal_accumulator := 0.0

var parry_flash_timer := 0.0
const PARRY_FLASH_DURATION := 0.15

# ========== METER ==========

@export_group("Meter")
@export var max_meter := 5
var current_meter := 0

# ========== SPECIAL ==========

@export_group("Special")
@export var special_damage := 3
@export var special_duration := 0.4

var special_state_timer := 0.0

# ========== MOVEMENT ==========

@export_group("Movement")
@export var max_speed := 200.0
@export var max_air_speed := 200.0
@export var acceleration := 1200.0
@export var air_acceleration := 1000.0
@export var friction := 1800.0
@export var air_friction := 900.0  # was 300 — 4x weaker than air_acceleration (1200) meant releasing input in the air drifted for ~0.5s before stopping; raising max_speed on top of that only stretched that drift out further, reading as "slippery" instead of "fast."
@export var run_jump_speed_boost := 60.0  # max forward push added at takeoff, scaled by how close to max_speed you were the instant you jumped — full push at max speed, none from a standstill. Decays back to max_air_speed via the overspeed-friction handling in _handle_normal_movement, so it reads as a push off the ground rather than a permanent bonus.


# ========== JUMP / GRAVITY ==========

@export_group("Jump / Gravity")
@export var jump_velocity := -320.0  # was -350 — slightly lower peak height, part of trading height for a wider, rounder arc
@export var gravity := 980.0
@export var max_fall_speed := 550.0
@export var jump_cut_multiplier := 0.4
@export var apex_threshold := 120.0  # was 30 — the old value only softened gravity for ~2 frames near the peak, which read as a sharp corner (a "V") instead of a rounded top. Widening this stretches that softened zone across a real chunk of the arc.
@export var apex_gravity_mult := 0.75  # was 0.9 — barely softened gravity before; this makes the widened apex zone actually feel floaty/round instead of just slightly less sharp.
@export var fall_gravity_mult := 1.2

var jump_cut_disabled_timer := 0.0

const WALL_JUMP_CUT_DISABLE_TIME := 0.2


# ========== COYOTE / BUFFER ==========

@export_group("Coyote / Buffer")
@export var coyote_time := 0.05
@export var jump_buffer_time := 0.1
@export var dash_buffer_time := 0.1

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_buffered := false
var dash_buffer_timer := 0.0


# ========== DASH ==========
# Single horizontal dash. Refills on ground touch or wall-cling entry, plus a
# small fixed cooldown so a refill can't chain instantly into another dash.

@export_group("Dash")
@export var dash_speed := 670.0
@export var dash_duration := 0.07
@export var dash_cooldown := 0.07
@export var dash_grace_time := 0.2  # invuln grace after the dash ends — was 0.1, technically already longer than dash_duration (0.07) but too subtle to actually feel
@export var dash_gravity_mult := 0.75  # slight softening of gravity during the dash's fall — only applies while already falling; an ongoing jump's rise decays at normal gravity so dashing mid-jump doesn't extend the rise
@export var dash_tail_speed_mult := 0.6  # horizontal speed eases to this fraction by dash end
@export var dash_start_ease_window := 0.15  # fraction of dash_duration spent ramping up to full speed instead of snapping to it instantly — sharp, but not a single-frame step
@export var dash_animation_speed_mult := 4.0  # playback speed multiplier for the "dash" animation, so it's visible during the short dash
@export var dash_ledge_refill_window := 0.3  # last fraction of the dash that checks for a ledge below
@export var dash_ledge_check_distance := 10.0  # pixels below the player to check

var dash_available := true
var dash_direction := Vector2.ZERO
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_grace_timer := 0.0
var facing_direction := 1

# ========== WALL JUMP BUFFER ==========
var wall_jump_buffered := false
var wall_jump_buffer_timer := 0.0
@export var wall_jump_buffer_time := 0.1


var was_on_floor := false


# ========== WALL CLING ==========

@export_group("Wall")
@export var wall_cling_gravity_mult := 0.4
@export var wall_cling_max_fall_speed := 120.0

var is_next_to_wall := false
var was_wall_clinging := false
var wall_normal := Vector2.ZERO
var last_wall_normal := Vector2.ZERO  # kept alive through wall_coyote_time after leaving a wall, since update_wall_detection() zeroes wall_normal the instant contact is lost


# ========== WALL JUMP ==========
# Two distinct jumps, chosen by what's held the instant the jump fires:
#   - Holding toward the wall while clinging: "climb" — small push, full
#     height, meant for chaining hops up one wall.
#   - Anything else: "escape" — bigger push, slightly lower arc, meant for
#     actually launching off the wall.
# Since clinging requires holding toward the wall, that input is the natural
# default right up to the jump press, so climb fires most of the time by
# construction — wall_jump_redirect_window exists to fix that (see below)
# instead of requiring you to redirect before a jump you haven't taken yet.

@export var wall_jump_push_force := 260.0  # escape jump's horizontal push
@export var wall_climb_jump_push_force := 140.0  # climb jump's horizontal push — smaller, so normal air control can pull you back into wall range afterward without a scripted yank
@export var wall_jump_control_lock_time := 0.12

@export_group("Wall Jump Forgiveness")
@export var wall_coyote_time := 0.03  # was on the ground: 0.05. A wall jump still works this long after actually leaving the wall.
@export var wall_jump_redirect_window := 0.1  # after a wall jump fires, holding the opposite direction within this window swaps in the other jump's trajectory once — the actual fix for "reacting" to a jump you didn't mean to take, instead of needing to have already committed before it happened.
@export_group("")

var wall_jump_control_lock_timer := 0.0
var control_lock_timer := 0.0
var wall_coyote_timer := 0.0
var wall_jump_redirect_timer := 0.0
var wall_jump_redirect_push_direction := 0
var wall_jump_redirect_was_climb := false

var hazard_overlap_count := 0

var velocity_clamp_timer := 0.0
var velocity_clamp_value := 0.0

@export var respawn_lock_time := 0.4
var respawn_lock_timer := 0.0


# ========== ASSISTS ==========

@export_group("Assists")
@export var corner_correction_pixels := 4


func _physics_process(delta: float) -> void:
	var input_x := Input.get_axis("move_left", "move_right")
	var input_y := Input.get_axis("move_up", "move_down")
	var jump_pressed := Input.is_action_just_pressed("jump")
	var jump_released := Input.is_action_just_released("jump")
	var dash_pressed := Input.is_action_just_pressed("dash")
	var attack_pressed := Input.is_action_just_pressed("attack")
	var parry_pressed := Input.is_action_just_pressed("parry")
	var special_pressed := Input.is_action_just_pressed("special")

	var grounded := is_on_floor()

	if has_flag(Flag.DEAD) or respawn_lock_timer > 0.0:
		dash_pressed = false
		jump_pressed = false
		jump_released = false
		attack_pressed = false
		parry_pressed = false
		special_pressed = false
		input_x = 0.0
		input_y = 0.0

	# Execution order matters: dash → jump → movement → gravity
	var jump_consumed = _handle_invulnerability(delta)
	_handle_input_buffers(jump_pressed, dash_pressed, grounded)
	_handle_dash_start(input_x, input_y)
	_handle_attack_start(attack_pressed)
	_handle_parry_start(parry_pressed)
	_handle_special_start(special_pressed)
	_handle_checkpoint(grounded)

	jump_consumed = _handle_dash_state(delta, jump_consumed)
	_handle_normal_movement(input_x, grounded, delta)

	jump_consumed = _handle_jump_execution(jump_pressed, jump_released, grounded, jump_consumed)

	_handle_wall_cling_state(input_x, grounded)
	_handle_velocity_clamp(delta)
	_handle_gravity(input_x, input_y, grounded, delta)

	was_on_floor = grounded

	jump_consumed = _handle_wall_jump(input_x, jump_pressed, grounded, jump_consumed)
	_handle_wall_jump_redirect(input_x)
	_handle_coyote_and_dash_refresh(input_x, input_y, grounded, delta)
	_update_timers(delta)

	sprite.flip_h = facing_direction == -1
	_update_animation()
	apply_corner_correction(delta, input_x)
	_handle_hazard_overlap()
	_apply_movement(delta)


func _update_animation() -> void:
	# Taking a hit always interrupts, even mid-dash-animation.
	if hit_flash_timer > 0.0:
		if sprite.animation != "hit":
			sprite.play("hit")
		return

	# "dash" is a one-shot (non-looping) clip now, and it's started directly
	# in _handle_dash_start() so it always plays from frame 0. Once it's
	# running, let it finish on its own — even after Flag.DASHING clears —
	# instead of getting cut off by idle/run every frame.
	if sprite.animation == "dash" and sprite.is_playing():
		return

	var target := "idle"
	if abs(velocity.x) > 1.0:
		# No dedicated jump/fall animation yet, so airborne movement also
		# falls back to run/idle based on horizontal speed.
		target = "run"

	if sprite.animation != target:
		sprite.play(target)


func _handle_invulnerability(delta: float) -> int:
	var invuln_color := Color.WHITE
	if invulnerability_timer > 0.0:
		invulnerability_timer -= delta
		invuln_color = Color.BLACK
	elif has_flag(Flag.HURT):
		set_flag(Flag.HURT, false)

	if sprite.self_modulate != invuln_color:
		sprite.self_modulate = invuln_color
	return 0


func _handle_input_buffers(jump_pressed: bool, dash_pressed: bool, grounded: bool) -> void:
	if dash_pressed:
		dash_buffer_timer = dash_buffer_time

	if jump_pressed:
		jump_buffered = true
		jump_buffer_timer = jump_buffer_time
		if not grounded:
			wall_jump_buffered = true
			wall_jump_buffer_timer = wall_jump_buffer_time


func _handle_dash_start(input_x: float, _input_y: float) -> void:
	if dash_buffer_timer <= 0.0 or not dash_available or dash_cooldown_timer > 0.0 or has_flag(Flag.DASHING | Flag.HURT):
		return

	# Horizontal-only: vertical input is ignored for dash direction.
	var dash_dir := Vector2(sign(input_x), 0.0) if input_x != 0.0 else Vector2(facing_direction, 0.0)

	facing_direction = int(dash_dir.x)

	dash_direction = dash_dir
	dash_timer = dash_duration
	# Horizontal velocity gets the dash snap; vertical velocity is left alone
	# so a dash mid-fall or mid-jump-arc continues that arc underneath the
	# dash instead of getting hard-reset to 0 — makes the dash feel layered
	# onto existing momentum rather than a separate, disconnected state.
	velocity.x = dash_direction.x * dash_speed
	dash_available = false
	dash_buffer_timer = 0.0
	set_flag(Flag.DASHING, true)
	sprite.play("dash", dash_animation_speed_mult)


func _handle_attack_start(attack_pressed: bool) -> void:
	if not attack_pressed or attack_cooldown_timer > 0.0 or has_flag(Flag.ATTACKING):
		return

	if has_flag(Flag.HURT | Flag.DEAD):
		return

	# Attacking is allowed to overlap a dash (dash-slash) — it no longer
	# needs to check or touch the DASHING flag to coexist with it.
	set_flag(Flag.ATTACKING, true)
	attack_state_timer = attack_duration
	attack_cooldown_timer = attack_cooldown


func _handle_parry_start(parry_pressed: bool) -> void:
	if not parry_pressed or parry_cooldown_timer > 0.0 or has_flag(Flag.PARRYING):
		return

	if has_flag(Flag.HURT | Flag.DEAD | Flag.DASHING | Flag.ATTACKING):
		return

	set_flag(Flag.PARRYING, true)
	parry_state_timer = parry_window_duration
	parry_cooldown_timer = parry_cooldown


func _handle_special_start(special_pressed: bool) -> void:
	if not special_pressed or has_flag(Flag.SPECIAL):
		return

	if current_meter < max_meter:
		return

	if has_flag(Flag.HURT | Flag.DEAD | Flag.DASHING | Flag.ATTACKING | Flag.PARRYING):
		return

	current_meter = 0
	set_flag(Flag.SPECIAL, true)
	special_state_timer = special_duration


func _handle_checkpoint(grounded: bool) -> void:
	if grounded and not has_flag(Flag.HURT | Flag.DEAD) and hazard_overlap_count == 0:
		Global.last_safe_position = global_position


func _handle_dash_state(delta: float, jump_consumed: int) -> int:
	if not has_flag(Flag.DASHING):
		return jump_consumed

	dash_timer -= delta

	# Sharp ramp to full dash_speed over the first dash_start_ease_window
	# (not an instant step), holds steady, then eases toward
	# dash_tail_speed_mult over the 2nd half.
	var t: float = 1.0 - (dash_timer / dash_duration)
	var start_ease: float = smoothstep(0.0, dash_start_ease_window, t)
	var tail_ease: float = lerp(1.0, dash_tail_speed_mult, smoothstep(0.5, 1.0, t))
	var speed_mult: float = start_ease * tail_ease
	velocity.x = dash_direction.x * dash_speed * speed_mult

	# Near the end of the dash only — not the whole thing, so dashing while
	# already grounded doesn't just refill instantly. This is what lets a
	# dash that ends right at/near a ledge keep its charge, without letting
	# two dashes chain across a gap that should only take one.
	if not dash_available and dash_timer <= dash_duration * dash_ledge_refill_window:
		_check_ledge_refill()

	if dash_timer <= 0.0:
		_end_dash()

	return jump_consumed


func _check_ledge_refill() -> void:
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.new()
	params.from = global_position
	params.to = global_position + Vector2(0.0, dash_ledge_check_distance)
	params.exclude = [self]
	if space.intersect_ray(params):
		dash_available = true


func _end_dash() -> void:
	if not has_flag(Flag.DASHING):
		return

	set_flag(Flag.DASHING, false)
	dash_cooldown_timer = dash_cooldown
	dash_grace_timer = dash_grace_time


func _handle_normal_movement(input_x: float, grounded: bool, delta: float) -> void:
	if has_flag(Flag.DASHING):
		return

	var direction := input_x
	var accel := acceleration if grounded else air_acceleration
	var fric := friction if grounded else air_friction

	if direction != 0.0:
		facing_direction = int(sign(direction))

	var max_spd := max_speed if grounded else max_air_speed
	var target_speed := direction * max_spd

	if wall_jump_control_lock_timer > 0.0 or control_lock_timer > 0.0 or respawn_lock_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)
		return

	if direction != 0.0:
		if abs(velocity.x) > max_spd and sign(velocity.x) == sign(direction):
			# Carrying more speed than max_spd in the held direction (e.g. a
			# wavedash exiting a dash) — decay it with friction like the
			# no-input case instead of accel snapping it straight down to
			# max_spd, which killed the wavedash's momentum ~4x faster
			# whenever the dash direction was still held.
			velocity.x = move_toward(velocity.x, target_speed, fric * delta)
		else:
			velocity.x = move_toward(velocity.x, target_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)


func _handle_jump_execution(_jump_pressed: bool, jump_released: bool, grounded: bool, jump_consumed: int) -> int:
	if jump_released and velocity.y < -100.0 and not has_flag(Flag.DASHING) and jump_cut_disabled_timer <= 0.0:
		velocity.y *= jump_cut_multiplier

	if not jump_buffered or jump_consumed:
		return jump_consumed

	if (grounded or coyote_timer > 0.0 or has_flag(Flag.DASHING)) and not has_flag(Flag.HURT):
		velocity.y = jump_velocity
		jump_buffered = false
		if not grounded and coyote_timer > 0.0:
			coyote_timer = 0.0

		# Push-off boost: scales continuously with how fast you were moving
		# the instant you left the ground (including via coyote time) — none
		# from a standstill, full push at max ground speed, proportional
		# in between. Height is unaffected, only takeoff speed. Decays back
		# to max_air_speed afterward (see the overspeed-friction branch in
		# _handle_normal_movement), so it feels like a kick off the ground
		# settling into your air speed, not a permanent bonus. Skipped during
		# a dash-jump since dash already owns velocity.x every frame.
		if not has_flag(Flag.DASHING):
			var takeoff_speed_ratio: float = clampf(abs(velocity.x) / max_speed, 0.0, 1.0)
			velocity.x += sign(velocity.x) * run_jump_speed_boost * takeoff_speed_ratio

		# Jumping out of an airborne dash no longer cancels DASHING — the dash
		# keeps driving velocity.x/gravity-softening until it naturally ends,
		# it just also gets an instant vertical kick. This is what makes the
		# player actionable mid-dash instead of jump silently doing nothing.
		set_flag(Flag.WALL_CLINGING, false)
		return 1

	return jump_consumed


func _handle_wall_cling_state(input_x: float, grounded: bool) -> void:
	var pushing_into_wall := (
		(wall_normal.x < 0.0 and input_x > 0.0)
		or
		(wall_normal.x > 0.0 and input_x < 0.0)
	)

	# Equivalent to the old "state == NORMAL" gate: nothing else exclusive
	# is currently happening, including a wall-jump's control-lock window.
	var locomotion_free := not has_flag(Flag.DASHING | Flag.WALL_CLINGING | Flag.HURT | Flag.DEAD | Flag.ATTACKING | Flag.PARRYING | Flag.SPECIAL) and wall_jump_control_lock_timer <= 0.0

	if not grounded and is_next_to_wall and velocity.y > 0.0 and pushing_into_wall and locomotion_free:
		set_flag(Flag.WALL_CLINGING, true)
	elif has_flag(Flag.WALL_CLINGING) and (grounded or not is_next_to_wall or not pushing_into_wall):
		set_flag(Flag.WALL_CLINGING, false)



func _handle_velocity_clamp(delta: float) -> void:
	if velocity_clamp_timer > 0.0:
		velocity_clamp_timer -= delta
		if velocity_clamp_timer <= 0.0 and not is_on_floor():
			if velocity_clamp_value < 0.0 and velocity.y < velocity_clamp_value:
				velocity.y = velocity_clamp_value
			elif velocity_clamp_value > 0.0 and velocity.y > velocity_clamp_value:
				velocity.y = velocity_clamp_value


func _handle_gravity(_input_x: float, _input_y: float, grounded: bool, delta: float) -> void:
	if has_flag(Flag.DASHING):
		# Vertical velocity carries in from whatever it was before the dash
		# (fall/jump arc) — gravity keeps acting on it the whole dash instead
		# of restarting from 0. Softening (dash_gravity_mult) only applies
		# while already falling (velocity.y >= 0); if you dash mid-jump while
		# still rising, full gravity applies so the rise decays normally —
		# otherwise the softened pull was letting an in-progress jump keep
		# climbing during the dash instead of just gliding through a fall.
		var dash_grav_mult := dash_gravity_mult if velocity.y >= 0.0 else 1.0
		velocity.y += gravity * dash_grav_mult * delta
		return

	if grounded:
		return

	var gravity_mult := 1.0

	if abs(velocity.y) < apex_threshold:
		gravity_mult = apex_gravity_mult
	elif velocity.y > 0.0:
		gravity_mult = fall_gravity_mult

	if has_flag(Flag.WALL_CLINGING):
		gravity_mult *= wall_cling_gravity_mult
		velocity.y = min(velocity.y, wall_cling_max_fall_speed)

	velocity.y += gravity * gravity_mult * delta
	velocity.y = min(velocity.y, max_fall_speed)


func _handle_wall_jump(input_x: float, _jump_pressed: bool, grounded: bool, jump_consumed: int) -> int:
	var wall_available := is_next_to_wall or wall_coyote_timer > 0.0
	if not wall_jump_buffered or jump_consumed or not wall_available or grounded or has_flag(Flag.DASHING):
		return jump_consumed

	# last_wall_normal covers the wall_coyote_timer case, where wall_normal
	# has already been zeroed by update_wall_detection() since contact was
	# lost a frame or two ago.
	var effective_wall_normal := wall_normal if is_next_to_wall else last_wall_normal
	var push_direction := int(sign(effective_wall_normal.x))

	var pushing_into_wall := (
		(effective_wall_normal.x < 0.0 and input_x > 0.0)
		or
		(effective_wall_normal.x > 0.0 and input_x < 0.0)
	)

	var is_climb := has_flag(Flag.WALL_CLINGING) and pushing_into_wall

	if is_climb:
		velocity.x = push_direction * wall_climb_jump_push_force
		velocity.y = jump_velocity
	else:
		velocity.x = push_direction * wall_jump_push_force
		velocity.y = jump_velocity * 0.8

	# Redirect window: since clinging requires holding toward the wall, climb
	# fires by default most of the time — this is what actually lets you
	# correct that after the fact instead of needing to have redirected
	# before a jump that hadn't happened yet. See _handle_wall_jump_redirect.
	wall_jump_redirect_timer = wall_jump_redirect_window
	wall_jump_redirect_push_direction = push_direction
	wall_jump_redirect_was_climb = is_climb

	jump_cut_disabled_timer = WALL_JUMP_CUT_DISABLE_TIME
	wall_jump_control_lock_timer = wall_jump_control_lock_time

	wall_jump_buffered = false
	set_flag(Flag.WALL_CLINGING, false)
	coyote_timer = 0.0
	wall_coyote_timer = 0.0
	return 1


func _handle_wall_jump_redirect(input_x: float) -> void:
	if wall_jump_redirect_timer <= 0.0:
		return

	var held_dir := int(sign(input_x))
	if held_dir == 0:
		return

	if wall_jump_redirect_was_climb and held_dir == wall_jump_redirect_push_direction:
		# Was the small climb hop; now holding away from the wall — upgrade
		# to the full escape jump.
		velocity.x = wall_jump_redirect_push_direction * wall_jump_push_force
		velocity.y = jump_velocity * 0.8
		wall_jump_redirect_timer = 0.0
	elif not wall_jump_redirect_was_climb and held_dir == -wall_jump_redirect_push_direction:
		# Was the escape jump; now holding toward the wall — downgrade to
		# the climb hop.
		velocity.x = wall_jump_redirect_push_direction * wall_climb_jump_push_force
		velocity.y = jump_velocity
		wall_jump_redirect_timer = 0.0


func _handle_coyote_and_dash_refresh(_input_x: float, _input_y: float, grounded: bool, delta: float) -> void:
	if grounded:
		coyote_timer = coyote_time
		if not has_flag(Flag.DASHING):
			dash_available = true
	else:
		coyote_timer = tick_timer(coyote_timer, delta)

	# Refills on entering wall-cling specifically, not any wall touch.
	if has_flag(Flag.WALL_CLINGING) and not was_wall_clinging:
		dash_available = true

	was_wall_clinging = has_flag(Flag.WALL_CLINGING)


func _update_timers(delta: float) -> void:
	if jump_buffered:
		jump_buffer_timer = tick_timer(jump_buffer_timer, delta)
		if jump_buffer_timer <= 0.0:
			jump_buffered = false

	if wall_jump_buffered:
		wall_jump_buffer_timer = tick_timer(wall_jump_buffer_timer, delta)
		if wall_jump_buffer_timer <= 0.0:
			wall_jump_buffered = false

	jump_cut_disabled_timer = tick_timer(jump_cut_disabled_timer, delta)
	dash_buffer_timer = tick_timer(dash_buffer_timer, delta)
	dash_cooldown_timer = tick_timer(dash_cooldown_timer, delta)
	dash_grace_timer = tick_timer(dash_grace_timer, delta)
	hit_flash_timer = tick_timer(hit_flash_timer, delta)

	wall_jump_control_lock_timer = tick_timer(wall_jump_control_lock_timer, delta)
	wall_coyote_timer = tick_timer(wall_coyote_timer, delta)
	wall_jump_redirect_timer = tick_timer(wall_jump_redirect_timer, delta)

	if control_lock_timer > 0.0:
		control_lock_timer = tick_timer(control_lock_timer, delta)

	if respawn_lock_timer > 0.0:
		respawn_lock_timer = tick_timer(respawn_lock_timer, delta)

	if attack_state_timer > 0.0:
		attack_state_timer = tick_timer(attack_state_timer, delta)
		if attack_state_timer <= 0.0:
			set_flag(Flag.ATTACKING, false)

	attack_cooldown_timer = tick_timer(attack_cooldown_timer, delta)

	if parry_state_timer > 0.0:
		parry_state_timer = tick_timer(parry_state_timer, delta)
		if parry_state_timer <= 0.0:
			set_flag(Flag.PARRYING, false)

	parry_cooldown_timer = tick_timer(parry_cooldown_timer, delta)
	parry_flash_timer = tick_timer(parry_flash_timer, delta)

	if special_state_timer > 0.0:
		special_state_timer = tick_timer(special_state_timer, delta)
		if special_state_timer <= 0.0:
			set_flag(Flag.SPECIAL, false)


func _apply_movement(delta: float) -> void:
	# Only wall-like hits cut the dash short; floor/ceiling hits fall through to move_and_slide().
	if has_flag(Flag.DASHING) and velocity.length() > 1.0:
		var next_pos := global_position + velocity * delta
		var space = get_world_2d().direct_space_state
		var params = PhysicsRayQueryParameters2D.new()
		params.from = global_position
		params.to = next_pos
		params.exclude = [self]
		# World only — this query has no mask by default, which means it was
		# treating anything solid (including enemy bodies) as a wall and
		# cutting the dash short. Dashing already grants invulnerability, so
		# the dash should pass through enemies, not get stopped by them.
		params.collision_mask = 1
		var hit = space.intersect_ray(params)
		if hit and hit.has("position"):
			var hit_normal: Vector2 = hit.get("normal", Vector2.ZERO)
			var hit_is_wall: bool = abs(hit_normal.x) > 0.5 and abs(hit_normal.y) < 0.5
			if hit_is_wall:
				var hit_pos: Vector2 = hit.get("position")
				var safe_pos := hit_pos - velocity.normalized() * 2.0
				global_position = safe_pos
				velocity = Vector2.ZERO

				is_next_to_wall = true
				wall_normal = hit_normal
				last_wall_normal = hit_normal

				_end_dash()
				return

	move_and_slide()
	update_wall_detection()

	if has_flag(Flag.DASHING):
		for i in range(get_slide_collision_count()):
			var collision := get_slide_collision(i)
			if not collision:
				continue
			var normal: Vector2 = collision.get_normal()
			var is_wall: bool = abs(normal.x) > 0.5 and abs(normal.y) < 0.5
			if is_wall and dash_direction.dot(normal) < -0.3:
				velocity = Vector2.ZERO
				_end_dash()
				break

	var target_modulate := Color.RED
	if parry_flash_timer > 0.0:
		target_modulate = Color.GREEN
	elif has_flag(Flag.DASHING):
		target_modulate = Color.CYAN
	elif has_flag(Flag.PARRYING):
		target_modulate = Color(1.0, 0.85, 0.2)
	elif dash_available:
		target_modulate = Color.WHITE

	if sprite.modulate != target_modulate:
		sprite.modulate = target_modulate


func update_wall_detection() -> void:
	var was_next_to_wall := is_next_to_wall

	is_next_to_wall = false
	wall_normal = Vector2.ZERO

	var collision_count := get_slide_collision_count()

	for i in range(collision_count):
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()

		if abs(normal.x) > 0.5 and abs(normal.y) < 0.5:
			is_next_to_wall = true
			wall_normal = normal
			last_wall_normal = normal
			return

	# Just lost contact this frame — start the wall jump's coyote grace.
	# last_wall_normal keeps the direction available since wall_normal itself
	# is zeroed above the moment contact is lost.
	if was_next_to_wall:
		wall_coyote_timer = wall_coyote_time


func apply_corner_correction(delta: float, input_x: float) -> void:
	if velocity.y >= 0.0:
		return

	var vertical_motion := Vector2(0.0, velocity.y * delta)

	if not test_move(global_transform, vertical_motion):
		return

	var preferred_dir := int(sign(input_x))

	if preferred_dir == 0:
		preferred_dir = int(sign(velocity.x))

	var directions := [1, -1]

	if preferred_dir != 0:
		directions = [preferred_dir, -preferred_dir]

	for amount in range(1, corner_correction_pixels + 1):
		for dir in directions:
			var offset := Vector2(dir * amount, 0.0)

			if test_move(global_transform, offset):
				continue

			var corrected_transform := global_transform
			corrected_transform.origin += offset

			if not test_move(corrected_transform, vertical_motion):
				global_position.x += offset.x
				return

# ============ Death / Health ==========
func take_damage(amount: int = 1, knockback: Vector2 = Vector2.ZERO) -> void:
	current_health = maxi(current_health - amount, 0)
	invulnerability_timer = invulnerability_duration
	set_flag(Flag.HURT, true)
	hit_flash_timer = hit_flash_duration

	if knockback != Vector2.ZERO:
		velocity += knockback
		control_lock_timer = knockback_control_lock_time

	if current_health <= 0:
		dead()

func take_enemy_damage(amount: int = 1, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_invulnerable():
		return

	if has_flag(Flag.PARRYING):
		_on_parry_success()
		return

	take_damage(amount, knockback)

func _on_parry_success() -> void:
	_parry_heal_accumulator += parry_heal_amount
	while _parry_heal_accumulator >= 1.0 and current_health < max_health:
		_parry_heal_accumulator -= 1.0
		current_health += 1

	parry_flash_timer = PARRY_FLASH_DURATION

	current_meter = mini(current_meter + 1, max_meter)

func _on_hitbox_body_entered(_body: Node2D) -> void:
	hazard_hit()

func _on_hitbox_area_entered(area: Area2D) -> void:
	# DamageHitbox (enemy contact, future projectiles, etc.) just carries a
	# damage value and goes through take_enemy_damage() — parry-aware, no
	# forced respawn. Anything else hitting this layer (generic hazards) is
	# still the harsher hazard_hit()/respawn path.
	if area is DamageHitbox:
		var knockback := Vector2.ZERO
		if area.knockback_force > 0.0:
			# Horizontal-dominant on purpose: a raw normalized direction
			# between the two positions can end up mostly vertical depending
			# on exactly where the hitboxes overlapped, which read as "sent
			# me up" instead of "pushed away." Sign of the x-difference plus
			# a smaller fixed vertical pop is what actually feels like a
			# sideways shove regardless of contact geometry.
			var away_x := global_position.x - area.global_position.x
			var horizontal_dir := signf(away_x) if absf(away_x) > 1.0 else float(-facing_direction)
			knockback = Vector2(horizontal_dir, -area.knockback_vertical_ratio) * area.knockback_force
		take_enemy_damage(area.damage, knockback)
	else:
		hazard_hit()

func hazard_hit() -> void:
	if is_invulnerable():
		return

	take_damage(1)

	if not has_flag(Flag.DEAD):
		respawn()

# The enter signals only fire once, on first contact — if invulnerability
# was still active at that exact moment (e.g. dashing into a hazard), the
# hit was silently swallowed and nothing re-checked afterward. This catches
# hazards the player is still standing in the instant invulnerability ends.
func _handle_hazard_overlap() -> void:
	if hazard_overlap_count > 0 and not is_invulnerable():
		hazard_hit()

func respawn() -> void:
	global_position = Global.last_safe_position
	velocity = Vector2.ZERO
	set_flag(Flag.HURT, false)

	invulnerability_timer = invulnerability_duration

	jump_buffered = false
	jump_buffer_timer = 0.0
	wall_jump_buffered = false
	wall_jump_buffer_timer = 0.0
	dash_buffer_timer = 0.0
	dash_cooldown_timer = 0.0

	respawn_lock_timer = respawn_lock_time

	Engine.time_scale = 0.85
	await get_tree().create_timer(0.15 / Engine.time_scale).timeout
	Engine.time_scale = 1.0

func dead() -> void:
	if has_flag(Flag.DEAD):
		return

	set_flag(Flag.DEAD, true)
	set_flag(Flag.HURT, false)
	current_health = max_health
	Global.death_count += 1
	Global.did_just_die = true
	Engine.time_scale = 0.7
	timer.start()

func _on_timer_timeout() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func tick_timer(time_value: float, delta: float) -> float:
	return maxf(time_value - delta, 0.0)

func _on_hazard_area_entered(_area: Area2D) -> void:
	hazard_overlap_count += 1

func _on_hazard_area_exited(_area: Area2D) -> void:
	hazard_overlap_count = maxi(hazard_overlap_count - 1, 0)

func _on_hazard_body_entered(_body: Node2D) -> void:
	hazard_overlap_count += 1

func _on_hazard_body_exited(_body: Node2D) -> void:
	hazard_overlap_count = maxi(hazard_overlap_count - 1, 0)
