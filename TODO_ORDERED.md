# Dash-Based-Game — MVP TODO

Full rewrite. Goal: a working, start-to-finish game — not good, not fun, not
pretty, just complete and playable end to end so there's something to
actually improve on later. Ordered by priority toward that MVP, cheapest
and most-blocking first. Post-MVP polish/content is pushed to the bottom
regardless of how "important" it sounds, per that goal.

---

## Already working (context, not tasks)

Skip re-reading these as work items — they're done and stable:

- Movement: run/accel/friction, coyote time, jump buffer, wall cling/climb/
  wall jump, single 8-directional dash (refined feel, ground + wall-touch
  refill, land-cooldown-clamp), hazard damage + respawn-to-checkpoint
- Parry: window, cooldown, heal-on-success, meter build, currently
  instant-kills whatever it parries (interim — see Known Issues)
- Enemies: melee ground type (LimboAI behavior tree — chase/jump/ledge-wait)
  and flying type (chase/stop), contact damage only, no real attacks yet
- Checkpoints: heal, save-trigger, visual active state, position persistence
- World state: enemy kills persist across death-reload, reset on checkpoint
  rest (Hollow Knight-style), permanent bucket ready for future one-time
  pickups
- Save system: multi-slot ConfigFile, persists checkpoint/health/world
  state/currency+xp+death_count (the last three are just numbers right now
  — nothing grants or spends them yet)
- Preferences autoload: audio bus volumes + full rebindable-keybinding
  backend — fully functional, just has zero UI exposing it in-game yet
- Pause menu: pause/resume/restart/quit all work

---

## Phase 1: Combat is currently non-functional — fix first

**Why first, why cheapest:** the player's attack and special exist as
states (flag, timer, cooldown) but deal no damage — there's no hitbox at
all. Right now the *only* way to kill anything is the interim parry-kill
rule. This reuses the exact `DamageHitbox` pattern enemies already use, so
it's small, and nothing else combat-related matters until it exists.

- [ ] Add an Area2D attack hitbox to `player.tscn` (child, disabled by
      default — same shape/pattern as enemy `Hitbox` nodes)
- [ ] Enable it only during the active swing frames of `Flag.ATTACKING`,
      disable the rest of the time
- [ ] On enemy contact: call `enemy.take_damage(attack_damage, knockback)`
- [ ] Same wiring for `Flag.SPECIAL` using `special_damage` (bigger
      hitbox/range is enough differentiation for MVP — no new animation)
- [ ] Decide + implement: does a *parried* hit still instant-kill (current
      behavior), or should landing a normal attack be the main kill method
      and parry become a stagger instead? (Interim comment in `enemy.gd`
      flags this as a decision, not a bug — your call once attacks exist)

---

## Phase 2: Minimal HUD

**Why now, why cheap:** one Label/ProgressBar bound to values that already
exist on `Global`/`Player`. No new game logic, just visibility — but
without it the player has no idea how much health or meter they have.

- [ ] Health display (numbers or simple bar — no art needed)
- [ ] Meter/special bar display
- [ ] Wire both to update on change (signal or poll in `_process`, either
      is fine for MVP)

---

## Phase 3: Wrap the loop start-to-finish

**Why now:** this turns "a scene that runs" into "a game with a beginning
and an end" — the actual definition of MVP-complete. Each piece here is a
small scene plus a scene-change call; no new gameplay systems.

- [ ] Start menu scene: Start Game / Settings / Quit, loads
      `Global.last_checkpoint_scene` (or a fixed first-level path for a
      fresh save)
- [ ] Finish/win scene: a trigger area placed at the end of the level,
      transitions to a plain "You Win" scene (Restart / Quit buttons)
- [ ] Settings menu UI: sliders for the three volumes already wired in
      `Preferences`, a screen-shake toggle, a Back button — all of this
      just calls existing `Preferences` functions, no new backend
- [ ] Keybinding UI: list of `Preferences.REBINDABLE_ACTIONS`, a
      "press a key to rebind" capture per row, a "reset to default" button
      — the only genuinely new logic in this phase (an input-capture mode),
      everything else is calling `rebind_action()`/`reset_action_to_default()`
- [ ] Wire the same Settings scene into the pause menu as a submenu
      (`_on_settings_pressed` currently doesn't exist — pause menu has no
      settings entry point at all yet)
- [ ] Remove or repurpose the dead "instrument" buttons in the pause menu
      (`_on_basic_pressed` etc. are no-ops left over from the old
      per-instrument-dash design that was removed — either delete them or
      fold them into the pickup-unlock system in Phase 5 if instruments
      become real attack loadouts)

---

## Phase 4: Level content (the actual game part)

**Why after the above, not before:** none of Phase 1-3 depends on level
content, and content is the most open-ended, time-consuming category here
— building it before the core loop works end-to-end would mean redoing
placement work once attacks/HUD/menus land anyway.

- [ ] Turn the current single test scene into (or build alongside it) a
      real first area: deliberate platforming using the dash's full
      toolkit (diagonals, wall-cling-refill, wall jump chains)
- [ ] Place hazards (spikes/pits) and enemies with actual intent instead of
      scattered test placement
- [ ] At least one more room/area beyond the first, connected by a scene
      transition (tests the untested multi-scene path in
      `SaveManager.load_game()`/`Global.last_checkpoint_scene`)
- [ ] A checkpoint at the start of each room/area
- [ ] Place the Phase 3 finish trigger at the end of the last area

---

## Phase 5: Progression systems

**Why last:** these are additive systems on top of a game that already
works start-to-finish — genuinely "improve on later" territory, not needed
for a first complete playthrough. Ordered cheapest-first within the phase.

- [ ] Pickup scene template (Area2D, one-shot, uses `WorldState`'s
      `permanent` bucket from the world-state system so a collected pickup
      never reappears)
- [ ] Gate wall jump and/or dash behind a pickup each (simplest version:
      a bool on `Global`/`Player` checked before the relevant input branch
      runs — the movement code itself doesn't need to change, just an
      early-return gate)
- [ ] XP/currency actually granted somewhere (simplest: enemy death grants
      a fixed amount) — `Global.currency`/`Global.xp` already exist and
      save/load correctly, nothing has ever incremented them
- [ ] At least one thing to spend currency/XP on, even a placeholder (a
      currency counter that only ever goes up isn't a system yet)
- [ ] Enemy attacks: give melee/flying enemies a real telegraphed attack
      instead of contact-only damage (old TODO already had a detailed
      design for this — telegraph timing, damage, parryable window; salvage
      it from git history if useful, not rewritten here since it's
      unchanged)
- [ ] More enemy types per area, reusing the existing `Enemy`/BT pattern

---

## Known issues / cleanup (not blocking, don't forget)

- [ ] `flying_enemy.tscn`'s behavior tree reverted to plain
      `BTSelector`/`BTSequence` (non-reactive — see melee enemy's
      `BTDynamicSelector`/`BTDynamicSequence` fix) and was deliberately left
      broken pending this cleanup pass
- [ ] No real "game over" state exists — death always just respawns at the
      last checkpoint with full health restored, forever. Confirm that's
      actually the intended design (matches the genre) before assuming it
      needs fixing

---

## Post-MVP (explicitly not part of "working game," revisit later)

- [ ] Sound effects + music
- [ ] Visual feedback/juice (screen flash, particles, dash trail, knockback
      animation)
- [ ] Boss encounter
- [ ] Tutorial prompts/text
- [ ] Map art, parallax, tile variety
- [ ] Difficulty/game-feel tuning pass
- [ ] Performance profiling

---

## Quick reference: critical path to MVP

1. Player attack/special hitboxes (Phase 1)
2. HUD (Phase 2)
3. Start menu + Finish screen (Phase 3)
4. Settings + keybinding UI (Phase 3)
5. First playable area + one more connected room (Phase 4)
6. Progression systems (Phase 5) — genuinely optional for "working game,"
   include if there's appetite before calling it MVP-complete
