extends Enemy
class_name FlyingEnemy

# All decision-making lives in the BTPlayer's behavior tree — built visually
# in the editor's LimboAI panel, not hand-authored here (same reasoning as
# the Phantom Camera scene earlier: don't hand-write a plugin's node graph
# resource, use the tool's own editor). This script just ticks the tree
# manually each physics frame and applies whatever velocity it decided on.
# No gravity — flying enemies hover freely, unlike the grounded chase-and-hop
# type.
#
# The BTPlayer node exists in scenes/flying_enemy.tscn with an empty tree.
# Leaf tasks live in scripts/bt/: bt_player_in_range.gd (condition),
# bt_chase_player.gd (action, direct hover-chase per current scope),
# bt_stop.gd (fallback action for when the player's out of range). Assemble
# them into: Selector [ Sequence [ PlayerInRange, ChasePlayer ], Stop ].

@export_group("Movement")
@export var move_speed := 90.0
@export var detection_range := 350.0

@onready var bt_player: BTPlayer = $BTPlayer


func _ready() -> void:
	super._ready()
	# agent_node (a NodePath, not directly settable to a Node instance) is
	# left unset — it defaults to BTPlayer's parent, which is this node.
	bt_player.update_mode = BTPlayer.UpdateMode.MANUAL


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	tick_lifetime(delta)
	if is_dead:
		return

	bt_player.update(delta)
	move_and_slide()
