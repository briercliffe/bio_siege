class_name OutbreakRun
extends RefCounted

## Outbreak mode run state: a chain of raids against one learning base.
## The run ends on the first raid where the defense holds (#90).

var generation: int = 1
var total_score: int = 0
var generation_scores: Array[int] = []
var ended: bool = false


func record(outcome: String, score: int) -> void:
	if ended:
		return
	if outcome == "attacker":
		generation_scores.append(score)
		total_score += score
		generation += 1
	else:
		ended = true


func generations_cleared() -> int:
	return generation_scores.size()


func to_dict() -> Dictionary:
	return {
		"generation": generation,
		"total_score": total_score,
		"generation_scores": generation_scores.duplicate(),
		"ended": ended,
	}
