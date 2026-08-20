# Dash-Based-Game — Ordered TODO

Organized by dependencies and complexity (simplest first).

---

## Phase 1: Foundation & Core Systems

### 1. Save System
**Why first:** Required for progression, checkpoint system, and game flow.

- [x] Implement save file structure (ConfigFile, multi-slot)
- [x] Save player health on checkpoint
- [ ] Save current level/area/progress
- [ ] Load on startup (read last checkpoint)
- [ ] Handle save file versioning for future updates

### 2. Checkpoint System
**Why early:** Needed for level design and tutorials; heavily used by other systems.

- [ ] Create checkpoint scene (bench/root node)
  - [ ] Node setup in editor (Area2D with collision)
  - [ ] Checkpoint.gd script
- [ ] On checkpoint touch:
  - [ ] Update `Global.last_safe_position` (already done via hazard system)
  - [ ] Heal player to max health
  - [ ] Show "Checkpoint reached" feedback
  - [ ] Save game state (calls Save System)
- [ ] Checkpoint UI (instrument change, stats display)

### 3. Health System Polish
**Why now:** Already exists, needs polish before combat mechanics.

- [ ] Visual health display (hearts/bar in UI)
- [ ] Player health regeneration on parry (small amount, ~0.25 health)
- [ ] Meter/special bar system (builds on parry + on-beat hits)
- [ ] Test full loop: take damage → respawn → heal at checkpoint

---

## Phase 2: Player Movement & Dash Polish

### 4. Dash Polish
**Single 8-directional dash, no cooldown, no wavedash, no dash-cancel wall bounce.**
Refills on ground touch and the instant wall contact begins. Instruments
change attacks only, not dash behavior — see Phase 3 for the attack system
that will eventually give instruments something to do.

- [x] Inline single-dash logic directly on Player (no more per-ability scripts)
- [x] Block straight-vertical dash while wall clinging (prevents shaft-climbing spam)
- [x] Allow horizontal/diagonal dash off a wall while clinging
- [x] Dash refill on ground touch
- [x] Dash refill the instant wall contact begins (not on exit)
- [ ] Polish feel (speed/duration tuning, minor tweaks only)
- [ ] Test consistency across all input scenarios (keyboard + analog stick 8-way snap)
- [ ] Confirm dash-end feel (no momentum carry-over/end-speed multiplier — check it doesn't feel too abrupt, especially on an upward dash)

### 5. Player Movement Polish
- [ ] Coyote time feel (adjust 0.15s if needed)
- [ ] Jump buffer timing (adjust 0.1s if needed)
- [ ] Wall cling speed reduction (test against walls)
- [ ] Wall climb boost delay (currently 0.08s, adjust if feels sluggish)
- [ ] General movement juice (trails, particles)

---

## Phase 3: Combat Foundation

### 6. Basic Attack System (Player)
**Why before enemies:** Enemies need something to parry/react to.

**Code changes:**
- [x] Add `Flag.ATTACKING` to Player's flag system (Player.PlayerState enum was replaced with a bitflag `Flag` enum — several conditions, e.g. attacking + dashing, can now be true at once)
- [ ] Add attack cooldown timer
- [ ] Add attack range (Area2D child)
- [ ] Add attack damage value

**Implementation:**
- [ ] Input: detect "attack" action (not yet in input map)
- [ ] Animation: play swing animation on attack
- [ ] Hit detection: check what's in attack range
- [ ] Knockback: push hit enemies away
- [ ] Cleanup: disable attack hitbox after swing

### 7. Parry System (Player)
**Why now:** Core to the game's rhythm/feedback loop.

**Code changes:**
- [x] Add `PARRYING` to Player.PlayerState enum
- [x] Add parry cooldown + window duration
- [x] Add parry visual feedback (placeholder color tint/flash — no real art yet; audio not wired, no SFX assets/playback system exists yet)

**Implementation:**
- [x] Input: detect "parry" action (right-click / joypad button 1, rebindable via Preferences)
- [x] Parry window: 0.2s (`parry_window_duration`, tunable)
- [x] On parry — resolved in `take_enemy_damage()`, the existing entry point for enemy hits:
  - [x] Check if enemy attack lands during window (`is_parrying` check — ready for a hitbox to call once enemies exist)
  - [x] If yes: success feedback (color flash) + player heals in fractional increments (~0.25/parry via accumulator) — meter build deferred, no Meter/Special System yet (#8)
  - [x] If no: falls through to existing miss/damage flow (`take_damage()`)
- [ ] Add parry animation + visual effect — placeholder color only; real animation intentionally deferred

### 8. Meter/Special System
**Why now:** Needed for player feedback and combat pacing.

- [ ] Meter display in UI
- [x] Meter builds on: parry hits (`_on_parry_success()`, +1, capped at `max_meter` = 3) — on-beat hits still pending, no rhythm/beat system yet
- [x] Meter consumes on: special attack (drains fully to 0)
- [ ] Special attack (new `SPECIAL` state, gated by `current_meter == max_meter`):
  - [x] Larger damage value (`special_damage` = 3 vs. normal attack's 1) — knockback not implemented, no enemies to knock back yet
  - [ ] Different animation — deferred, no assets
  - [x] Drains meter

---

## Phase 4: Enemies & Combat

### 9. Enemy Foundation

**Base Enemy Script (enemy.gd):**
- [x] Extends CharacterBody2D
- [x] Health system (current_health, max_health, take_damage) — no shared HealthComponent, duplicated like Player's
- [ ] State machine — skipped for now; plain GDScript decision functions in each subclass instead, written to port cleanly to LimboAI once more enemy types exist and it's worth the setup
- [x] Physics (gravity, collision detection) — lives per-subclass, not the base, since grounded vs. flying enemies won't move alike
- [x] Death: removal from scene (no loot drop yet)

**Enemy Scene Template — first concrete type instead of a generic template:**
- [x] Create `scenes/melee_ground_enemy.tscn` (grounded, contact-damage-only, no attacks — see script comments)
- [x] CharacterBody2D with collision
- [ ] AnimatedSprite2D child — placeholder Polygon2D box for now, no art yet
- [ ] Attack hitbox (Area2D) — N/A, this enemy type has no attacks by design
- [x] Hurtbox (Area2D, receives damage) — wired and ready, but nothing calls into it yet since the player has no spatial attack hitbox to detect it with
- [ ] Spawn in levels — not yet placed in game.tscn

### 10. Enemy Type #1: Melee Minion
**Simplest enemy; teaches parry timing.**

**Behavior:**
- [ ] Idle: patrol or wait
- [ ] Chase: follow player within range (e.g., 5 units)
- [ ] Attack: 0.5s telegraph animation, then swing
  - [ ] Attack pattern: swing every 2s
  - [ ] Damage: 1 HP
  - [ ] Knockback: small (50 units away)
- [ ] Stagger: freeze for 0.3s after parry
- [ ] Death: remove from scene

**Assets needed:**
- [ ] Sprite/animations (idle, chase, attack, stagger, death)
- [ ] Sound effects (attack telegraph, hit, death)

**Testing:**
- [ ] Spawn in test room
- [ ] Verify parry window works (on parry: stagger + heal)
- [ ] Verify miss feedback (on miss: player takes damage)

### 11. Enemy Type #2: Ranged Minion
**Variant; teaches dodging.**

**Behavior:**
- [ ] Idle: stationary
- [ ] Chase: follow player within range (e.g., 7 units)
- [ ] Attack: 0.7s telegraph (aim), then fire projectile
  - [ ] Attack pattern: projectile every 3s
  - [ ] Projectile damage: 1 HP
  - [ ] Can be parried (projectile destroyed on parry)
- [ ] Stagger: freeze for 0.3s after parry
- [ ] Death: remove from scene

**Assets needed:**
- [ ] Sprite/animations (idle, chase, aim, stagger, death)
- [ ] Projectile sprite
- [ ] Sound effects (charge, fire, hit, death)

**Testing:**
- [ ] Verify projectile spawns and travels
- [ ] Verify parry destroys projectile
- [ ] Verify miss damage

### 12. Enemy Type #3: Aerial/Boss Minion (Optional)
**Can skip for MVP; add if time.**

- [ ] Hovers above ground
- [ ] Fast attacks, lower health (2 HP)
- [ ] Pattern: triple-swipe combo with 0.3s gaps

---

## Phase 5: UI & Menus

### 13. Start Menu
**Simple; no complex dependencies.**

**Scene: `scenes/start_menu.tscn`**
- [ ] Background (art or solid color)
- [ ] Title text
- [ ] Buttons:
  - [ ] "Start Game" → load first level
  - [ ] "Settings" → push settings menu
  - [ ] "Exit" → quit game

**Scripting:**
- [ ] Button signals wired to functions
- [ ] Load level on start
- [ ] Persist music across scene transitions

### 14. Settings Menu
**Low complexity; reuses from pause menu logic.**

**Scene: `scenes/settings_menu.tscn`**
- [ ] Master Volume slider
- [ ] Music Volume slider
- [ ] SFX Volume slider
- [ ] Screen Shake toggle
- [ ] Back button

**Scripting:**
- [ ] Sliders update AudioServer volume levels
- [ ] Toggle wires to screen shake flag in player/effects system
- [ ] Save settings to disk (calls Save System)

### 15. Pause Menu (Complete)
**Partially done; needs completion.**

- [ ] Add Settings submenu (done: basic structure)
- [ ] Add Tutorial prompt/help text
- [ ] Polish button styling
- [ ] Test pause/resume flow

### 16. Checkpoint/Instrument Menu
**UI shown when touching checkpoint.**

**Scene: overlay when checkpoint touched**
- [ ] Display current health/meter
- [ ] Button: "Change Instrument" (shows attack-loadout selector once the attack system supports multiple instruments — dash is unaffected by instrument choice)
- [ ] Heal + save feedback
- [ ] Auto-close after 2s or on input

---

## Phase 6: Audio & Feedback

### 17. Sound Effects
**Required for satisfying gameplay.**

**Core sounds needed:**
- [ ] Parry success (high, rewarding tone)
- [ ] Parry fail (low, warning tone)
- [ ] On-beat hit (satisfying sharp sound, synced to music beat)
- [ ] Enemy stagger (short impact sound)
- [ ] Player damage (pain grunt)
- [ ] Heal/checkpoint (bright, ascending tone)
- [ ] Dash (swish sound, varies per dash)
- [ ] Enemy death (sparkle/pop sound)

**Implementation:**
- [ ] Add AudioStreamPlayer nodes in scenes
- [ ] Wire parry system to play sounds
- [ ] Wire damage/heal systems to play sounds
- [ ] Adjust volume levels for balance

### 18. Background Music
**Loopable, clear beat; essential for rhythm gameplay.**

**Requirements:**
- [ ] 1 track (area/level background)
- [ ] Clear, audible beat (for on-beat hit feedback)
- [ ] 60-120 BPM (adjustable based on feel)
- [ ] Loopable (seamless loop point)

**Implementation:**
- [ ] Add AudioStreamPlayer in level/main scene
- [ ] Loop enabled
- [ ] Volume balanced with SFX

### 19. Visual Feedback
**Juice: makes hits feel satisfying.**

- [ ] Screen flash on parry success (white flash, 0.1s)
- [ ] Screen shake on parry success (small shake, 0.2s)
- [ ] Red flash on parry fail / damage
- [ ] Particle effect on hit (dust/slash effect)
- [ ] Enemy knockback animation (visual feedback for hit)
- [ ] Dash visual trail

---

## Phase 7: Level Design & Content

### 20. Tutorial Room
**Teaches core mechanics; players see first.**

**Design:**
- [ ] Single room, no enemies initially
- [ ] Path with simple platforming (dashes, jumps)
- [ ] Checkpoint at start
- [ ] Text prompts or NPC explaining:
  - [ ] "Press X to dash"
  - [ ] "Press C to attack / Z to parry"
  - [ ] "Hit enemies on the beat for meter"
  - [ ] "Parry to heal and stagger"
- [ ] Simple minion at end (harmless, for practice)
- [ ] Goal: reach exit to continue

### 21. Dash Mastery Room
**Single room teaching the one dash's full toolkit — no unlock gating, since there's only one dash.**

- [ ] Platforming built around 8-directional dashing (diagonals, not just horizontal/vertical)
- [ ] Wall-cling + dash-off-wall repositioning challenges (horizontal/diagonal dash while clinging)
- [ ] Gap/spike crossings that reward the wall-contact-start refill (dash again the instant you touch a wall, before cling even registers)
- [ ] Regular wall-jump chaining (separate from dash — jump while clinging)
- [ ] Once instruments-for-attacks exists (Phase 3+), revisit whether per-instrument rooms belong here instead of dash-focused

### 22. First Combat Room
**Gentle intro to fighting; after tutorials.**

- [ ] 2-3 melee minions (not aggressive, slow)
- [ ] Safe area to retreat
- [ ] Checkpoint nearby
- [ ] Clear goal: defeat all enemies
- [ ] Reward: progression to next area

### 23. Main Level Layout
**Full playable area with progression.**

- [ ] Start → tutorial room → dash tutorial rooms → combat intro
- [ ] 2-3 mid-level rooms (mix of platforming + combat)
- [ ] Boss arena
- [ ] Each room has checkpoint
- [ ] Each room has clear exit/goal

---

## Phase 8: Boss & Advanced Combat

### 24. Boss Enemy
**Full moveset; teaches all mechanics.**

**Boss Script (boss.gd, extends enemy):**
- [ ] Health: 10-15 HP (adjustable)
- [ ] State machine: IDLE, ATTACK_1, ATTACK_2, ATTACK_3, STAGGERED, DEAD
- [ ] Phase system (optional MVP): split into 2 phases at 50% health
  - [ ] Phase 1: attacks 1-3
  - [ ] Phase 2: attacks 1-4 + faster speed

**Attack Patterns (4-6 total):**
1. **Horizontal Swipe:**
   - Telegraph: 0.8s
   - Damage: 2 HP
   - Knockback: large
   - Parryable

2. **Vertical Slam:**
   - Telegraph: 1.0s
   - Damage: 2 HP
   - Knockback: medium
   - Creates shockwave (area damage)
   - Parryable

3. **Multi-Hit Combo:**
   - Telegraph: 0.5s
   - 3 quick hits, each 1 HP
   - Fast attacks, harder to parry (tighter window)
   - Parryable only on first hit (stuns full combo)

4. **Ranged Attack:**
   - Telegraph: 1.2s
   - Fires 2-3 projectiles
   - Each 1 HP
   - Parryable (each one)

5. **Heal/Buff (optional):**
   - Telegraph: 1.5s
   - Boss heals 3 HP (teach players must interrupt)
   - Parry prevents heal

**Phase 2 (if implementing):**
- Add attack 5-6 or increase attack speed
- Visual change (color shift, aura, etc.)

**Boss Scene:**
- [ ] Boss sprite/animations for each attack + stagger + death
- [ ] Large arena (wider than rooms)
- [ ] Safe platforms to retreat to
- [ ] Checkpoint before boss room

**Testing:**
- [ ] Each attack pattern works
- [ ] Parry windows are fair (0.3-0.5s)
- [ ] Phase transition smooth
- [ ] Death removes boss + shows victory

---

## Phase 9: Map Polish & Juice

### 25. Map Art & Polish
- [ ] Tile/background art for each room type
- [ ] Visual hierarchy (clear goals, safe zones)
- [ ] Parallax scrolling (depth effect)
- [ ] Enemy spawn effects (fade-in)
- [ ] Victory effects (confetti, screen shake on boss defeat)

### 26. Environmental Hazards (Optional MVP)
**If time allows.**

- [ ] Spike pits (already respawn system)
- [ ] Moving platforms
- [ ] Timed platforms (disappear/reappear)
- [ ] Lava (damage over time)

---

## Phase 10: Polish & QA

### 27. Game Feel Tweaks
**Iterate based on playtesting.**

- [ ] Dash speed/duration (feel responsive?)
- [ ] Jump arc (floaty? snappy?)
- [ ] Gravity multipliers (fall speed)
- [ ] Knockback distances (too far? not far enough?)
- [ ] Parry window timing (too tight? too forgiving?)
- [ ] Attack telegraphs (clear enough?)

### 28. Bug Fixes & Edge Cases
- [ ] Test rapid input sequences
- [ ] Test wall jumps near edges
- [ ] Test parry during dash
- [ ] Test checkpoint healing after respawn
- [ ] Test save/load cycle
- [ ] Test wall-cling vertical-dash block doesn't false-positive on diagonal input

### 29. Performance
- [ ] Profile FPS in full level
- [ ] Optimize particle effects
- [ ] Optimize enemy spawning/despawning

---

## Post-MVP (Future)

- [ ] More areas / levels
- [ ] More enemy variety (ranged variants, flying enemies)
- [ ] Boss phases + phase-specific attacks
- [ ] Story/dialogue system
- [ ] More instruments (attack variety — dash stays single/unified by design)
- [ ] Difficulty modes
- [ ] Leaderboards (if online)

---

## Quick Reference: Critical Path

1. Save System
2. Checkpoint System
3. Health Polish
4. Dash Polish (single 8-directional dash feel/tuning)
5. Basic Attack + Parry
6. Enemy Type #1
7. Sound Effects + Music
8. Tutorial + Combat Room
9. Boss
10. Polish

**Estimated scope for MVP:** Phases 1-8 (~2-4 weeks depending on art/audio resources)
