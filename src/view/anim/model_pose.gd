class_name ModelPose
extends RefCounted

## Plain data handed from AnimDriver to a ModelPainter (docs/MODEL_PIPELINE_PLAN.md section 3.2).
## A painter is a pure function of the pose and the tile size; it reads nothing else.

enum Anim { IDLE, MOVE, WINDUP, STRIKE, RECOVER, HIT, DEAD }

var anim: Anim = Anim.IDLE
var facing_right: bool = true        # mirror rule, view-side only
var gait_phase: float = 0.0          # 0..1, advances with distance travelled
var attack_t: float = 0.0            # 0..1 across windup -> strike -> recover
var hit_t: float = 0.0               # 1 at the hit, decays to 0 (already scaled by Reduce flashes)
var shake: float = 0.0               # 0..1 shake amount (Reduce flashes halves it)
var death_t: float = 0.0             # 0..1 across the death animation
var hp_frac: float = 1.0
var aim: Vector2 = Vector2.ZERO      # towers: unit direction to the target on screen
var seed: int = 0                    # entity id, for per-entity phase offsets
var time: float = 0.0                # view clock in seconds for idle loops (stops while paused)
