class_name ViewRng
extends RefCounted

## Deterministic per-entity offsets for the view (docs/MODEL_PIPELINE_PLAN.md section 3.3).
## A pure hash of (id, salt). It never touches the sim Rng, the engine random generators or any sim state.

const MODULUS: int = 10007


static func hash01(id: int, salt: int) -> float:
	var h: int = ((id * 73856093) ^ (salt * 19349663)) & 0x7FFFFFFF
	return float(h % MODULUS) / float(MODULUS)
