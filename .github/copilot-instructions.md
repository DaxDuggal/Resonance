# Copilot Instructions

## Collaboration and communication

- This isn't the type of project where I tell you the end goal and you implement it. I want to collaborate with you on the design and implementation of the game, so I want you to do everything step by step. Each prompt and response is for one bug fix or one feature.
- Always make changes in the local checkout on this computer. Never branch, switch worktrees, or edit in different areas unless I explicitly specify it.
- Keep all edits on my local machine until I decide to commit them. Do not commit, push, stage, merge, rebase, or create pull requests unless I explicitly ask.
- Before making a meaningful code change, clearly explain what you intend to change, how it will work, which files or systems it affects, and any important trade-offs. Include enough implementation detail for the developer to catch a misunderstanding before more work is built on top of it.
- If you identify a bug, design concern, or likely problem while investigating, point it out immediately rather than silently working around it.
- Do not assume the developer's proposed solution is the best one. If a simpler, more efficient, more maintainable, or better-feeling gameplay solution exists, describe the alternative and why it may be preferable before implementing it.
- Always ask for permission before taking any Git action, including creating commits, switching or renaming branches, staging files, pushing changes, merging, rebasing, or creating pull requests.
- Never create or edit files outside the current local checkout, including other worktrees, alternate repositories, or the main checkout, unless I explicitly say to do so.
- Never silently move work into a different checkout, branch, or filesystem location to "save" or "organize" it. If a task requires another location, I must explicitly direct you there first.
- Preserve the developer's decision when they choose between alternatives, and do not treat unresolved design questions as settled requirements.
- Follow existing project patterns and keep changes focused. Explain deviations when the existing approach is not suitable.
- Recommend useful Godot plugins, tools, or workflows whenever they could materially improve development, debugging, iteration, or the player experience. Explain what each recommendation would help with; do not add or install anything without approval.

## Game direction

Resonance is a 2D metroidvania centered on dashing, fast movement, and precise timing. Future systems should support a responsive, readable, skill-based experience.

### Player movement and combat

- The player should feel light, agile, and fluid, with movement that flows from one action into the next.
- Aim for the responsive momentum and expressive traversal associated with *Ori*, while avoiding floatiness. Movement should feel controlled and intentional.
- The player should have a parry that feels like an air parry in *Nine Sols*: it should be readable, precise, satisfying to time, and integrated into aerial movement and combat.
- Combat should support multiple player movesets that can meaningfully change how the player approaches encounters. The intended direction is similar to *Hollow Knight: Silksong*'s crest system, while keeping the implementation extensible for additional movesets.
- When implementing movement or combat, prioritize responsiveness, clear timing windows, readable feedback, and interactions that preserve the game's focus on speed and timing.

### Enemies and encounters

- Enemies should create deliberate exchanges rather than encounters that are solved by overwhelming them with attacks. The intended feel is closer to *Sekiro*: observe, trade blows, defend, and exploit openings.
- Enemies should be able to parry or otherwise negate most incoming damage when they are defending effectively.
- Enemies should have clear vulnerable moments. In particular, the player should be able to punish the startup or endlag of an enemy attack when that attack leaves the enemy unable to parry.
- Enemies should lose access to their parry or become substantially more vulnerable around a health threshold, currently envisioned as roughly half health. Treat the exact threshold and behavior as open design decisions unless specified later.
- Every enemy attack must have a clear telegraph so the player can understand what is coming and make a deliberate response.
- Do not assume that every attack should deal the same damage. Damage values, attack categories, and their gameplay roles remain open decisions and should be discussed when they become relevant.

### World and level design

- The game is a metroidvania with exploration, ability-gated progression, and backtracking.
- The world should provide branching paths and room-level exploration while still giving the player a primarily legible route toward the final boss. The intended direction is closer to *Silksong* than to a world where the main route is difficult to identify.
- Avoid making progression depend on repeatedly searching for an obscure correct route. Signposting, landmarks, room structure, and progression cues should help players understand where they can go and why.
- Rooms should be substantial rather than tiny. Each room should offer some exploration, traversal, combat, or discovery without becoming unnecessarily sprawling.
- When proposing world systems or layouts, balance meaningful optional exploration with a clear main direction and a sense of forward momentum.

## Handling open decisions

- Preserve and call out decisions that have not been made yet, such as exact damage rules, parry behavior, health thresholds, and moveset details.
- When a new implementation depends on one of these decisions, present the relevant options and their gameplay or technical consequences before locking in a default.
