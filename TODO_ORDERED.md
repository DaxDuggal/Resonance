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
- Combat: player attack and special hitboxes deal real damage/knockback to
  enemies (`take_enemy_damage`); parry stuns + cancels the enemy's attack
  and heals/builds meter on success — normal attacks are the actual kill
  method, parry is a stagger, not an instant-kill (that design decision is
  resolved, not still open)
- HUD: health and special-meter labels, live-bound to the player's current
  values — plain text, no bars/icons/art yet, but functional
- Enemies: melee ground type and flying type, both on LimboAI behavior
  trees using the reactive `BTDynamicSelector`/`BTDynamicSequence` nodes
  (chase/attack/back-away for melee; chase/back-away/hold/dive-attack for
  flying), contact damage + a real telegraphed attack each — not
  contact-only anymore
- Player/enemy bodies never physically overlap (a scripted horizontal push,
  not physics collision — see `Enemy._apply_player_overlap_push`), except
  while the player is invulnerable or parrying
- Checkpoints: heal, save-trigger, visual active state, position persistence
- World state: enemy kills persist across death-reload, reset on checkpoint
  rest (Hollow Knight-style), `permanent` bucket implemented and ready for
  future one-time pickups (chests, doors, etc.) — just has nothing using it
  yet
- Save system: multi-slot ConfigFile, persists checkpoint/health/world
  state/currency+xp+death_count (the last three are just numbers right now
  — nothing grants or spends them yet)
- Preferences autoload: audio bus volumes + full rebindable-keybinding
  backend — fully functional, just has zero UI exposing it in-game yet
- Pause menu: pause/resume/restart/quit all work (the old no-op instrument
  buttons have been removed, not just left as dead code)

---

## Phase 1: Wrap the loop start-to-finish

**Why first now:** combat and HUD (the old Phase 1/2 here) are done, so
this is the next thing standing between "a scene that runs" and "a game
with a beginning and an end" — the actual definition of MVP-complete. Each
piece here is a small scene plus a scene-change call; no new gameplay
systems.

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

---

## Phase 2: Level content (the actual game part)

**Why after the above, not before:** none of Phase 1 depends on level
content, and content is the most open-ended, time-consuming category here
— building it before the core loop works end-to-end would mean redoing
placement work once menus land anyway.

- [ ] Turn the current single test scene into (or build alongside it) a
      real first area: deliberate platforming using the dash's full
      toolkit (diagonals, wall-cling-refill, wall jump chains)
- [ ] Place hazards (spikes/pits) and enemies with actual intent instead of
      scattered test placement
- [ ] At least one more room/area beyond the first, connected by a scene
      transition (tests the untested multi-scene path in
      `SaveManager.load_game()`/`Global.last_checkpoint_scene`)
- [ ] A checkpoint at the start of each room/area
- [ ] Place the Phase 1 finish trigger at the end of the last area

---

## Phase 3: Progression systems

**Why last:** these are additive systems on top of a game that already
works start-to-finish — genuinely "improve on later" territory, not needed
for a first complete playthrough. Ordered cheapest-first within the phase.

- [ ] Pickup scene template (Area2D, one-shot, uses `WorldState`'s
      `permanent` bucket so a collected pickup never reappears)
- [ ] Gate wall jump and/or dash behind a pickup each (simplest version:
      a bool on `Global`/`Player` checked before the relevant input branch
      runs — the movement code itself doesn't need to change, just an
      early-return gate)
- [ ] XP/currency actually granted somewhere (simplest: enemy death grants
      a fixed amount) — `Global.currency`/`Global.xp` already exist and
      save/load correctly, nothing has ever incremented them
- [ ] At least one thing to spend currency/XP on, even a placeholder (a
      currency counter that only ever goes up isn't a system yet)
- [ ] More enemy types per area, reusing the existing `Enemy`/BT pattern

---

## Known issues / cleanup (not blocking, don't forget)

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

1. Start menu + Finish screen (Phase 1)
2. Settings + keybinding UI (Phase 1)
3. First playable area + one more connected room (Phase 2)
4. Progression systems (Phase 3) — genuinely optional for "working game,"
   include if there's appetite before calling it MVP-complete
